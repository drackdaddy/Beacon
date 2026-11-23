local _, ns = ...

---------------------------------------------------------------------------
-- Guild list sync
-- Keeps every guild member's copy of the officer-managed list up to date over
-- the hidden guild addon channel, with no button to press:
--   Q|rev            "my copy is at rev". Sent once per session on login, and
--                    as a request when a newer copy is known to be online.
--   D|rev|i|n|chunk  one piece of the list; n pieces make the whole list.
-- Every send carries the whole list, and receivers replace their copy with it,
-- so additions, changes and deletions all arrive. A list is only accepted from
-- a player whose guild rank is an officer rank, and only when it is newer
-- (higher rev) than the local copy.
-- When it happens:
--   * An officer edits or imports: their list goes out 10 seconds after the
--     last change, so a burst of edits is sent once.
--   * Anyone logs in with an older copy: an online officer with a newer one
--     answers after a short random wait (so several officers don't all
--     answer), at most once a minute.
--   * An officer logs in with a newer copy than guildmates who are online:
--     one of them (picked by a random wait) asks, and the officer answers.
--   * An officer logs in with an older copy while only members are online:
--     one member says so, and the officer is warned not to edit until another
--     officer comes online and sends the newer list.
-- Pieces go out one per second to keep addon traffic light, so a full
-- 500-entry list takes about two minutes. If two officers change the list at
-- nearly the same time, the later change wins as a whole.
-- The personal list never leaves the player's computer.
-- Events: CHAT_MSG_ADDON, PLAYER_ENTERING_WORLD, GUILD_ROSTER_UPDATE
-- SavedVariables: BeaconDB.guilds (through ns.GetGuildData)
---------------------------------------------------------------------------
local PREFIX = "Beacon"
local CHUNK_BYTES = 230 -- plus a ~21 byte header stays under the 255 byte message limit
local MAX_CHUNKS = 200  -- enough for 500 entries of maximum length
local SEND_INTERVAL = 1
local MAX_SEND_FAILURES = 30
local SHARE_DELAY = 10
local ANSWER_COOLDOWN = 60

local queried = {}   -- guild keys already announced this session
local incoming = {}  -- sender -> { rev, total, parts, received } while pieces arrive
local sending        -- { rev, messages, index, failures, ticker, announce } during a send
local shareTimer     -- pending send after an officer's own edits
local answerTimer    -- pending answer to a guildmate with an older copy
local requestTimer   -- pending request to an officer with a newer copy
local requestRev     -- rev that requestTimer is waiting for
local noticeTimer    -- pending notice to an officer with an older copy
local newestSeenRev = 0 -- highest rev a guildmate has reported having
local lastAnswerTime = -ANSWER_COOLDOWN
local answerAfterSend = false

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

-- Sends one addon message to the guild. Returns true on success.
local function Send(message)
	return C_ChatInfo.SendAddonMessage(PREFIX, message, "GUILD") == Enum.SendAddonMessageResult.Success
end

local function CancelTimer(timer)
	if timer then
		timer:Cancel()
	end
end

local function MyRev()
	local data = ns.GetGuildData()
	return data and data.rev or 0
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

local SendList

-- Ends the current send. If the list changed while it was going out, the new
-- version is sent right away; otherwise any answer that had to wait goes next.
local function StopSending()
	local sentRev = sending.rev
	sending.ticker:Cancel()
	sending = nil
	if MyRev() > sentRev then
		SendList(true)
	elseif answerAfterSend then
		answerAfterSend = false
		ns.ScheduleAnswer()
	end
	ns.RefreshManager()
end

-- Sends the next piece. A refused send (throttle, chat lockdown) is retried on
-- the next tick; after too many refusals the send is abandoned.
local function SendNextPiece()
	if Send(sending.messages[sending.index]) then
		sending.index = sending.index + 1
		sending.failures = 0
		if sending.index > #sending.messages then
			if sending.announce then
				ns.Print("Guild list shared with your guild.")
			end
			StopSending()
		end
	else
		sending.failures = sending.failures + 1
		if sending.failures >= MAX_SEND_FAILURES then
			ns.Print("Couldn't share the guild list right now. It will go out the next time a guildmate logs in or you make a change.")
			-- Sent as far as it got; don't let StopSending retry straight away.
			sending.rev = MyRev()
			StopSending()
		end
	end
end

function ns.IsSending()
	return sending ~= nil
end

-- Officer only. Sends the whole guild list to everyone in the guild who has
-- Beacon. announce prints a confirmation when it finishes.
function SendList(announce)
	local data = ns.GetGuildData()
	if sending or not data or not ns.IsOfficer() then
		return
	end
	CancelTimer(answerTimer)
	answerTimer = nil

	local payload = Serialize(data)
	local total = math.ceil(#payload / CHUNK_BYTES)
	if total > MAX_CHUNKS then
		ns.Print("The guild list is too large to share.")
		return
	end
	local messages = {}
	for i = 1, total do
		local piece = payload:sub((i - 1) * CHUNK_BYTES + 1, i * CHUNK_BYTES)
		messages[i] = string.format("D|%d|%d|%d|%s", data.rev, i, total, piece)
	end

	sending = { rev = data.rev, messages = messages, index = 1, failures = 0, announce = announce }
	sending.ticker = C_Timer.NewTicker(SEND_INTERVAL, SendNextPiece)
	ns.RefreshManager()
	SendNextPiece()
end

-- Called by Core after an officer edits or imports into the guild list. Sends
-- the list SHARE_DELAY seconds after the last change. A send already in
-- progress picks up the change when it finishes (see StopSending).
function ns.QueueShare()
	CancelTimer(shareTimer)
	shareTimer = C_Timer.NewTimer(SHARE_DELAY, function()
		shareTimer = nil
		SendList(true)
	end)
end

-- Officer only. Answers a guildmate with an older copy after a random 3-8
-- second wait, and no sooner than a minute after the last answer. Repeated
-- requests share one answer.
function ns.ScheduleAnswer()
	if answerTimer or not ns.IsOfficer() then
		return
	end
	if sending then
		answerAfterSend = true
		return
	end
	local wait = math.max(0, lastAnswerTime + ANSWER_COOLDOWN - GetTime()) + math.random(3, 8)
	answerTimer = C_Timer.NewTimer(wait, function()
		answerTimer = nil
		lastAnswerTime = GetTime()
		SendList(false)
	end)
end

-- An officer with a newer copy (theirRev) is online. After a random 2-8 second
-- wait, ask for it, unless a guildmate asks first or the list starts arriving.
local function ScheduleRequest(theirRev)
	if requestTimer and requestRev >= theirRev then
		return
	end
	CancelTimer(requestTimer)
	requestRev = theirRev
	requestTimer = C_Timer.NewTimer(math.random(2, 8), function()
		requestTimer = nil
		Send("Q|" .. MyRev())
	end)
end

local function CancelRequest()
	CancelTimer(requestTimer)
	requestTimer = nil
end

-- Stores a fully received list if it is still newer than the local copy.
-- It replaces the old list completely, so deleted entries disappear too.
local function ApplyList(rev, payload)
	local data = ns.GetGuildData(true)
	if rev <= data.rev then
		return
	end
	local editor, entries = Deserialize(payload)
	data.rev, data.editor, data.entries = rev, editor, entries
	-- A newer list from another officer replaces any of our own edits still waiting to go out.
	CancelTimer(shareTimer)
	shareTimer = nil
	ns.ListChanged()
	ns.Print(string.format("Guild list updated (%d entries).", #entries))
end

-- Collects one piece of a list from sender and applies the list once complete.
local function OnPiece(sender, rev, index, total, piece)
	if not ns.IsOfficer(sender) then
		return
	end
	local myRev = MyRev()
	-- Another officer is already sending a list at least as new as ours: no need
	-- to answer too, or to tell anyone a newer one exists.
	if rev >= myRev then
		CancelTimer(answerTimer)
		answerTimer = nil
		CancelTimer(noticeTimer)
		noticeTimer = nil
	end
	-- The newer list is on its way: no need to ask for it.
	if requestTimer and rev >= requestRev then
		CancelRequest()
	end
	if rev <= myRev or total > MAX_CHUNKS then
		return
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

-- Returns true when a guildmate has a newer guild list than ours that hasn't
-- arrived yet. Only an officer can send it, so an officer seeing this should
-- wait before editing, or their older list would replace the newer one.
function ns.HasNewerGuildList()
	return newestSeenRev > MyRev()
end

-- Handles a guildmate saying "my copy is at theirRev".
local function OnVersion(sender, theirRev)
	local myRev = MyRev()
	-- Someone already told the guild about a copy at least as new as ours.
	if noticeTimer and theirRev >= myRev then
		CancelTimer(noticeTimer)
		noticeTimer = nil
	end
	if myRev > theirRev then
		ns.ScheduleAnswer()
		-- A member can't send the list, but can tell an officer with an older copy
		-- that a newer one exists, so they wait before editing. One member does
		-- it, picked by a random 2-8 second wait.
		if not ns.IsOfficer() and ns.IsOfficer(sender) and not noticeTimer then
			noticeTimer = C_Timer.NewTimer(math.random(2, 8), function()
				noticeTimer = nil
				Send("Q|" .. MyRev())
			end)
		end
	elseif theirRev > myRev then
		if ns.IsOfficer(sender) then
			ScheduleRequest(theirRev)
		elseif ns.IsOfficer() and newestSeenRev <= myRev then
			ns.Print("A guildmate has a newer guild list than yours. It arrives when another officer is online; edits you make before then would replace it.")
		end
		newestSeenRev = math.max(newestSeenRev, theirRev)
		ns.RefreshManager()
	end
	-- Someone else with an older copy already asked; the officer will answer them and us.
	if requestTimer and theirRev < requestRev then
		CancelRequest()
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
		local theirRev = tonumber(rest)
		if theirRev then
			OnVersion(sender, theirRev)
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

-- Once the roster is in, tell the guild which version we have, once per session.
ns.On("GUILD_ROSTER_UPDATE", function()
	local key = ns.GetGuildKey()
	if not key or queried[key] then
		return
	end
	queried[key] = true
	Send("Q|" .. MyRev())
end)
