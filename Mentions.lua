local _, ns = ...

---------------------------------------------------------------------------
-- Outgoing mentions
-- Just before a Guild or Guild Discord message is sent, turns @alias into the
-- Discord mention (<@&id> for roles, <@id> for people) and defuses @everyone
-- and @here. Only the text the player is already sending is changed; nothing
-- is ever posted by the addon.
-- Events: EventRegistry "ChatFrame.OnEditBoxPreSendText", PLAYER_LOGIN
-- SavedVariables: none (reads the guild list through ns.GetLookups)
---------------------------------------------------------------------------
local MAX_MESSAGE_BYTES = 255

-- Returns the raw Discord mention for a guild list entry.
function ns.MentionFor(entry)
	return (entry.kind == "role" and "<@&" or "<@") .. entry.id .. ">"
end

-- Returns true for the chat types Blizzard relays to the guild's Discord channel.
function ns.IsGuildChat(editBox)
	local chatType = editBox:GetChatType()
	return chatType == "GUILD" or chatType == "GUILD_DISCORD"
end

-- Removes the @ from @everyone and @here so Discord shows them as plain words.
-- Returns the new text and how many were changed.
local function BlockMassMentions(text)
	local blocked = 0
	text = text:gsub("@(%a+)", function(word)
		local lower = word:lower()
		if lower == "everyone" or lower == "here" then
			blocked = blocked + 1
			return word
		end
	end)
	return text, blocked
end

-- Replaces every known @alias with its Discord mention. An alias only counts at
-- the start of the text or after a character that can't be part of a word, so
-- e-mail-like text and existing <@123> mentions are left alone.
local function ExpandAliases(text)
	local byAlias = ns.GetLookups()
	local expanded = (" " .. text):gsub("([^%w_<@])@([%w_]+)", function(before, alias)
		local entry = byAlias[alias:lower()]
		if entry then
			return before .. ns.MentionFor(entry)
		end
	end)
	return expanded:sub(2)
end

-- Rewrites the edit box text before Blizzard sends it.
local function OnPreSendText(editBox)
	-- During chat lockdown (restricted combat content) the chat box must not be
	-- touched at all, or Blizzard's send would be blocked.
	if C_ChatInfo.InChatMessagingLockdown() then
		return
	end
	local text = editBox:GetText()
	if issecretvalue(text) or not ns.IsGuildChat(editBox) then
		return
	end

	-- Enter while suggestions are open sends the highlighted alias.
	if ns.AcceptSuggestion(editBox) then
		text = editBox:GetText()
	end

	local outgoing, blocked = BlockMassMentions(text)
	if blocked > 0 then
		ns.Print("@everyone and @here are blocked in guild chat.")
	end

	local expanded = ExpandAliases(outgoing)
	if #expanded > MAX_MESSAGE_BYTES then
		ns.Print("Message too long once mentions are added, so they were sent as plain text. Shorten it and try again.")
	else
		outgoing = expanded
	end

	if outgoing ~= text then
		editBox:SetText(outgoing)
	end
end

---------------------------------------------------------------------------
-- Readable chat
-- Shows @Display Name in the chat window in place of raw <@id> mentions, for
-- your own messages and everyone else's. Discord still gets the real mention.
-- Events: CHAT_MSG_GUILD and CHAT_MSG_GUILD_DISCORD message filters, PLAYER_LOGIN
-- SavedVariables: none
---------------------------------------------------------------------------

-- Chat message filter: returns false plus the rewritten message when it changed.
local function FriendlyNames(_, _, message, ...)
	if issecretvalue(message) or not message:find("<@", 1, true) then
		return false
	end
	local _, byMention = ns.GetLookups()
	local friendly = message:gsub("<@([!&]?)(%d+)>", function(marker, id)
		local entry = byMention[(marker == "&" and "&" or "") .. id]
		if entry then
			return "@" .. entry.name
		end
	end)
	if friendly ~= message then
		return false, friendly, ...
	end
	return false
end

ns.On("PLAYER_LOGIN", function()
	EventRegistry:RegisterCallback("ChatFrame.OnEditBoxPreSendText", function(_, editBox)
		-- An addon error here must never stop the player's message from sending.
		pcall(OnPreSendText, editBox)
	end, ns)

	ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", FriendlyNames)
	ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD_DISCORD", FriendlyNames)
end)
