local _, ns = ...

---------------------------------------------------------------------------
-- Autocomplete
-- Typing @ in Guild or Guild Discord chat shows matching aliases in a
-- tooltip-style list above the chat box. Tab inserts the highlighted alias,
-- Shift+Tab moves the highlight, a click inserts that alias, and Enter sends
-- the message with the highlighted alias filled in (see Mentions.lua).
-- Only post-hooks are used on Blizzard's chat boxes, so the secure send path
-- stays untouched.
-- Events: PLAYER_LOGIN; chat edit box OnTextChanged, OnTabPressed and OnHide hooks
-- SavedVariables: none
---------------------------------------------------------------------------
local MAX_ROWS = 8
local ROW_HEIGHT = 16
local HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"

local popup
local rows = {}
-- What the list currently suggests: the chat box, the byte positions of the
-- typed "@partial", the matching entries and the highlighted row.
local state = { results = {} }

local function Hide()
	if popup then
		popup:Hide()
	end
	state.editBox = nil
end

local function Highlight(index)
	state.index = index
	for i, row in ipairs(rows) do
		row.selected:SetShown(i == index)
	end
end

-- Inserts the highlighted alias (or the given row) in place of the typed @partial.
-- Returns true if the chat box text changed.
function ns.AcceptSuggestion(editBox, index)
	if not popup or not popup:IsShown() or state.editBox ~= editBox then
		return false
	end
	local entry = state.results[index or state.index]
	local text = editBox:GetText()
	Hide()
	-- Blizzard's own key handlers run first; give up if they changed the text.
	if not entry or text:sub(state.start, state.start) ~= "@" then
		return false
	end
	local after = text:sub(state.stop + 1)
	local insert = "@" .. entry.alias .. (after:sub(1, 1) == " " and "" or " ")
	editBox:SetText(text:sub(1, state.start - 1) .. insert .. after)
	editBox:SetCursorPosition(state.start - 1 + #insert)
	return true
end

-- Returns up to MAX_ROWS entries whose alias or display name starts with partial.
local function FindMatches(partial)
	local data = ns.GetGuildData()
	local matches = {}
	for _, entry in ipairs(data and data.entries or {}) do
		if entry.alias:sub(1, #partial) == partial or entry.name:lower():sub(1, #partial) == partial then
			matches[#matches + 1] = entry
		end
	end
	table.sort(matches, function(a, b)
		return a.alias < b.alias
	end)
	for i = #matches, MAX_ROWS + 1, -1 do
		matches[i] = nil
	end
	return matches
end

local function CreatePopup()
	popup = CreateFrame("Frame", nil, UIParent, "TooltipBackdropTemplate")
	popup:SetFrameStrata("DIALOG")
	popup:SetClampedToScreen(true)
	popup:SetWidth(260)
	popup:Hide()

	for i = 1, MAX_ROWS do
		local row = CreateFrame("Button", nil, popup)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 8, -8 - (i - 1) * ROW_HEIGHT)
		row:SetPoint("RIGHT", -8, 0)
		row:SetHighlightTexture(HIGHLIGHT, "ADD")

		row.selected = row:CreateTexture(nil, "BACKGROUND")
		row.selected:SetTexture(HIGHLIGHT)
		row.selected:SetBlendMode("ADD")
		row.selected:SetAllPoints()

		row.alias = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		row.alias:SetPoint("LEFT", 4, 0)
		row.detail = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		row.detail:SetPoint("RIGHT", -4, 0)

		row:SetScript("OnClick", function()
			local editBox = state.editBox
			if ns.AcceptSuggestion(editBox, i) then
				editBox:SetFocus()
			end
		end)
		rows[i] = row
	end
end

-- Shows or hides suggestions for the word being typed at the cursor.
local function Update(editBox, userInput)
	if not userInput or C_ChatInfo.InChatMessagingLockdown() then
		Hide()
		return
	end
	local text = editBox:GetText()
	if issecretvalue(text) or not ns.IsGuildChat(editBox) then
		Hide()
		return
	end

	local cursor = editBox:GetCursorPosition()
	local start, partial = text:sub(1, cursor):match("()@([%w_]*)$")
	if not start or (start > 1 and text:sub(start - 1, start - 1):match("[%w_<@]")) then
		Hide()
		return
	end
	local results = FindMatches(partial:lower())
	if #results == 0 then
		Hide()
		return
	end

	if not popup then
		CreatePopup()
	end
	state.editBox, state.start, state.stop, state.results = editBox, start, cursor, results
	for i, row in ipairs(rows) do
		local entry = results[i]
		row:SetShown(entry ~= nil)
		if entry then
			row.alias:SetText("@" .. entry.alias)
			row.detail:SetText(entry.name .. (entry.kind == "role" and " (Role)" or ""))
		end
	end
	Highlight(1)
	popup:SetHeight(#results * ROW_HEIGHT + 16)
	popup:ClearAllPoints()
	popup:SetPoint("BOTTOMLEFT", editBox, "TOPLEFT", 0, 2)
	popup:Show()
end

local function OnTabPressed(editBox)
	if not popup or not popup:IsShown() or state.editBox ~= editBox then
		return
	end
	if IsShiftKeyDown() then
		Highlight(state.index % #state.results + 1)
	else
		ns.AcceptSuggestion(editBox)
	end
end

ns.On("PLAYER_LOGIN", function()
	for i = 1, NUM_CHAT_WINDOWS do
		local editBox = _G["ChatFrame" .. i .. "EditBox"]
		if editBox then
			editBox:HookScript("OnTextChanged", function(box, userInput)
				-- A restricted chat box may refuse to be read; that must not raise errors.
				pcall(Update, box, userInput)
			end)
			editBox:HookScript("OnTabPressed", OnTabPressed)
			editBox:HookScript("OnHide", function(box)
				if state.editBox == box then
					Hide()
				end
			end)
		end
	end
end)
