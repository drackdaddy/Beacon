local _, ns = ...

---------------------------------------------------------------------------
-- Guild list sync
-- Shares the officer-managed list over the hidden guild addon channel.
--   Q|rev            sent once per session on login: "my copy is at rev".
--   D|rev|i|n|chunk  one piece of the list; n pieces make the whole list.
-- Any client whose copy is older asks; an online officer with a newer copy
-- answers after a short random wait (so several officers don't all answer),
-- at most once a minute. Officers can also send right away from the window.
-- Lists are only accepted from players whose guild rank is an officer rank,
-- and only when newer than the local copy. Pieces go out one per second to
-- keep addon traffic light.
-- Events: CHAT_MSG_ADDON, PLAYER_ENTERING_WORLD, GUILD_ROSTER_UPDATE
-- SavedVariables: BeaconDB.guilds (through ns.GetGuildData)
---------------------------------------------------------------------------
local PREFIX = "Beacon"
local CHUNK_BYTES = 200
local MAX_CHUNKS = 100
local SEND_INTERVAL = 1
local MAX_SEND_FAILURES = 30
local REPLY_COOLDOWN = 60

local queried = {}   -- guild keys already queried this session
local incoming = {}  -- sender -> { rev, total, parts, received } while pieces arrive
local sending        -- { messages, index, failures, ticker, announce } during a send
local replyTimer
local lastSendTime = -REPLY_COOLDOWN
local answerAfterSend = false

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

-- Sends one addon message to the guild. Returns true on success.
local function Send(message)
	return C_ChatInfo.SendAddonMessage(PREFIX, message, "GUILD") == Enum.SendAddonMessageResult.Success
end

-- Turns the guild list into "editor;alias,r|u,id,name;..." text.
local function Serialize(data)
	local parts = { data.editor or ns.PlayerName() }
	for _, entry in ipairs(data.entries) do
		parts[#parts + 1] = table.concat({ entry.alias, entry.kind == "role" and "r" or "u", entry.id, entry.name }, ",")
	end
	return table.concat(parts, ";")
end

-- Reads Serialize() text back. Invalid or duplicate entries are skipped.
-- Returns editor, entries.
local function Deserialize(payload)
	local editor
	local entries, seen = {}, {}
	for field in payload:gmatch("[^;]+") do
		if not editor then
			editor = field
		elseif #entries < ns.MAX_ENTRIES then
			local alias, kind, id, name = field:match("^([^,]+),([ru]),([^,]+),([^,]+)$")
			local entry = alias and { alias = alias:lower(), kind = kind == "r" and "role" or "user", id = id, name = name }
			if entry and ns.ValidateEntry(entry) and not seen[entry.alias] then
				seen[entry.alias] = true
				entries[#entries + 1] = entry
			end
		end
	end
	return editor, entries
end

local function StopSending()
	sending.ticker:Cancel()
	sending = nil
	lastSendTime = GetTime()
	if ns.RefreshManager then
		ns.RefreshManager()
	end
	if answerAfterSend then
		answerAfterSend = false
		ns.ScheduleAnswer()
	end
end

-- Sends the next piece. A refused send (throttle, chat lockdown) is retried on
-- the next tick; after too many refusals the send is abandoned.
local function SendNextPiece()
	if Send(sending.messages[sending.index]) then
		sending.index = sending.index + 1
		sending.failures = 0
		if sending.index > #sending.messages then
			if sending.announce then
				ns.Print("Guild list sent.")
			end
			StopSending()
		end
	else
		sending.failures = sending.failures + 1
		if sending.failures >= MAX_SEND_FAILURES then
			ns.Print("Couldn't send the guild list right now. Try again later.")
			StopSending()
		end
	end
end

function ns.IsSending()
	return sending ~= nil
end

-- Officer only. Sends the whole guild list to everyone in the guild who has
-- Beacon. announce prints a confirmation when it finishes.
-- Returns true if the send started.
function ns.SendList(announce)
	local data = ns.GetGuildData()
	if sending or not data or not ns.IsOfficer() then
		return false
	end
	if replyTimer then
		replyTimer:Cancel()
		replyTimer = nil
	end

	local payload = Serialize(data)
	local total = math.ceil(#payload / CHUNK_BYTES)
	if total > MAX_CHUNKS then
		ns.Print("The guild list is too large to send.")
		return false
	end
	local messages = {}
	for i = 1, total do
		local piece = payload:sub((i - 1) * CHUNK_BYTES + 1, i * CHUNK_BYTES)
		messages[i] = string.format("D|%d|%d|%d|%s", data.rev, i, total, piece)
	end

	sending = { messages = messages, index = 1, failures = 0, announce = announce }
	sending.ticker = C_Timer.NewTicker(SEND_INTERVAL, SendNextPiece)
	SendNextPiece()
	return true
end

-- Officer only. Answers a guildmate's request after a random 3-8 second wait,
-- and no sooner than a minute after the last send. Repeated requests share one answer.
function ns.ScheduleAnswer()
	if replyTimer or not ns.IsOfficer() then
		return
	end
	if sending then
		answerAfterSend = true
		return
	end
	local wait = math.max(0, lastSendTime + REPLY_COOLDOWN - GetTime()) + math.random(3, 8)
	replyTimer = C_Timer.NewTimer(wait, function()
		replyTimer = nil
		ns.SendList(false)
	end)
end

-- Stores a fully received list if it is still newer than the local copy.
local function ApplyList(rev, payload)
	local data = ns.GetGuildData(true)
	if rev <= data.rev then
		return
	end
	local editor, entries = Deserialize(payload)
	data.rev, data.editor, data.entries = rev, editor, entries
	ns.ListChanged()
	ns.Print(string.format("Guild list updated (%d entries).", #entries))
end

-- Collects one piece of a list from sender and applies the list once complete.
local function OnPiece(sender, rev, index, total, piece)
	local data = ns.GetGuildData()
	if not ns.IsOfficer(sender) or (data and rev <= data.rev) or total > MAX_CHUNKS then
		return
	end
	-- Another officer is already sending a list at least as new as ours.
	if replyTimer and data and rev >= data.rev then
		replyTimer:Cancel()
		replyTimer = nil
	end

	local transfer = incoming[sender]
	if index == 1 then
		transfer = { rev = rev, total = total, parts = {}, received = 0 }
		incoming[sender] = transfer
	elseif not transfer or transfer.rev ~= rev or transfer.total ~= total or index < 1 or index > total then
		return
	end
	if not transfer.parts[index] then
		transfer.parts[index] = piece
		transfer.received = transfer.received + 1
	end
	if transfer.received == total then
		incoming[sender] = nil
		ApplyList(rev, table.concat(transfer.parts))
	end
end

ns.On("CHAT_MSG_ADDON", function(prefix, message, channel, sender)
	if issecretvalue(prefix) or issecretvalue(message) or issecretvalue(sender) then
		return
	end
	if prefix ~= PREFIX or channel ~= "GUILD" then
		return
	end
	sender = ns.FullName(sender)
	if sender == ns.PlayerName() then
		return
	end

	local kind, rest = message:match("^(%a)|(.*)$")
	if kind == "Q" then
		local data = ns.GetGuildData()
		local theirRev = tonumber(rest)
		if data and theirRev and data.rev > theirRev then
			ns.ScheduleAnswer()
		end
	elseif kind == "D" then
		local rev, index, total, piece = (rest or ""):match("^(%d+)|(%d+)|(%d+)|(.*)$")
		if rev then
			OnPiece(sender, tonumber(rev), tonumber(index), tonumber(total), piece)
		end
	end
end)

-- The roster is needed to check officer ranks, so ask the server for it on login.
ns.On("PLAYER_ENTERING_WORLD", function(isInitialLogin, isReloadingUi)
	if (isInitialLogin or isReloadingUi) and IsInGuild() then
		C_GuildInfo.GuildRoster()
	end
end)

-- Once the roster is in, ask officers once per session whether there is a newer list.
ns.On("GUILD_ROSTER_UPDATE", function()
	local key = ns.GetGuildKey()
	if not key or queried[key] then
		return
	end
	queried[key] = true
	local data = ns.GetGuildData()
	Send("Q|" .. (data and data.rev or 0))
end)
