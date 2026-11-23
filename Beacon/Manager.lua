local _, ns = ...

---------------------------------------------------------------------------
-- Guild list window
-- /beacon opens a standard Blizzard portrait window listing the guild's
-- aliases. Officers also get an editor (alias, display name, Role/Person,
-- Discord ID) and a Send to Guild button; everyone else sees a read-only list.
-- Built the first time it is opened.
-- Events: none (refreshed through ns.RefreshManager)
-- SavedVariables: none (edits go through ns.SaveEntry and ns.DeleteEntry)
---------------------------------------------------------------------------
local ICON = "Interface\\Icons\\Ability_Paladin_BeaconofLight"
local HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"

local frame
local selected      -- entry loaded in the editor, or nil for a new one
local kind = "role" -- Role/Person choice in the editor

local function SetStatus(text, color)
	frame.status:SetText(text or "")
	frame.status:SetTextColor((color or NORMAL_FONT_COLOR):GetRGB())
end

local function SetKind(value)
	kind = value
	frame.roleRadio:SetChecked(value == "role")
	frame.personRadio:SetChecked(value == "user")
end

-- Loads entry into the editor, or clears it for a new entry when entry is nil.
local function Select(entry)
	selected = entry
	frame.aliasBox:SetText(entry and entry.alias or "")
	frame.nameBox:SetText(entry and entry.name or "")
	frame.idBox:SetText(entry and entry.id or "")
	SetKind(entry and entry.kind or "role")
	SetStatus(nil)
	ns.RefreshManager()
end

local function Save()
	local alias = strtrim(frame.aliasBox:GetText())
	local name = strtrim(frame.nameBox:GetText())
	local fields = { alias = alias, name = name ~= "" and name or alias, kind = kind, id = strtrim(frame.idBox:GetText()) }
	local entry, err = ns.SaveEntry(fields, selected)
	if not entry then
		SetStatus(err, RED_FONT_COLOR)
		return
	end
	Select(entry)
	SetStatus("Saved. Choose Send to Guild to share your changes.", GREEN_FONT_COLOR)
end

local function Delete()
	if selected then
		ns.DeleteEntry(selected)
		Select(nil)
		SetStatus("Deleted. Choose Send to Guild to share your changes.", GREEN_FONT_COLOR)
	end
end

-- Creates a gold label with an input box under it. Returns the input box.
local function CreateInput(parent, label, y, maxLetters)
	local text = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	text:SetPoint("TOPLEFT", 0, y)
	text:SetText(label)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(220, 20)
	box:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 6, -2)
	box:SetAutoFocus(false)
	box:SetMaxLetters(maxLetters)
	box:SetScript("OnEnterPressed", Save)
	return box
end

local function CreateRadio(parent, label, value)
	local radio = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
	local text = radio:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	text:SetPoint("LEFT", radio, "RIGHT", 4, 0)
	text:SetText(label)
	radio:SetScript("OnClick", function()
		SetKind(value)
	end)
	return radio
end

local function CreateButton(parent, label, width, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(label)
	button:SetScript("OnClick", onClick)
	return button
end

-- Fills one list row. Rows are created plain and set up the first time they are used.
local function InitRow(row, entry)
	if not row.alias then
		row:SetHighlightTexture(HIGHLIGHT, "ADD")
		row.alias = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		row.alias:SetPoint("LEFT", 6, 0)
		row.detail = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		row.detail:SetPoint("RIGHT", -6, 0)
		row:SetScript("OnClick", function(self)
			if ns.IsOfficer() then
				Select(self.entry)
			end
		end)
	end
	row.entry = entry
	row.alias:SetText("@" .. entry.alias)
	row.detail:SetText(entry.name .. (entry.kind == "role" and " (Role)" or " (Person)"))
	if entry == selected then
		row:LockHighlight()
	else
		row:UnlockHighlight()
	end
end

local function CreateManager()
	frame = CreateFrame("Frame", "BeaconFrame", UIParent, "ButtonFrameTemplate")
	frame:SetSize(560, 400)
	frame:SetPoint("CENTER")
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetTitle("Beacon")
	frame:SetPortraitToAsset(ICON)
	frame:SetScript("OnShow", function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
		ns.RefreshManager()
	end)
	frame:SetScript("OnHide", function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
	end)
	frame:Hide()
	-- Lets Escape close the window like other game panels.
	table.insert(UISpecialFrames, "BeaconFrame")

	frame.subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.subtitle:SetPoint("TOPLEFT", 70, -36)
	frame.subtitle:SetPoint("RIGHT", -12, 0)
	frame.subtitle:SetJustifyH("LEFT")

	-- Alias list
	local inset = frame.Inset
	local scrollBox = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", 6, -6)
	scrollBox:SetPoint("BOTTOMRIGHT", inset, "BOTTOMLEFT", 262, 6)
	local scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(20)
	view:SetElementInitializer("Button", InitRow)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	frame.scrollBox = scrollBox

	frame.empty = inset:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	frame.empty:SetPoint("CENTER", scrollBox)
	frame.empty:SetText("No aliases yet.")

	-- Officer editor
	local editor = CreateFrame("Frame", nil, inset)
	editor:SetPoint("TOPLEFT", 296, -12)
	editor:SetPoint("BOTTOMRIGHT", -12, 12)
	frame.editor = editor

	frame.aliasBox = CreateInput(editor, "Alias (typed after @)", 0, 24)
	frame.nameBox = CreateInput(editor, "Display name", -46, 32)
	frame.idBox = CreateInput(editor, "Discord ID", -92, 20)
	frame.idBox:SetNumeric(true)
	frame.aliasBox:SetScript("OnTabPressed", function() frame.nameBox:SetFocus() end)
	frame.nameBox:SetScript("OnTabPressed", function() frame.idBox:SetFocus() end)
	frame.idBox:SetScript("OnTabPressed", function() frame.aliasBox:SetFocus() end)

	local typeLabel = editor:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	typeLabel:SetPoint("TOPLEFT", 0, -138)
	typeLabel:SetText("Mentions a")
	frame.roleRadio = CreateRadio(editor, "Role", "role")
	frame.roleRadio:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", 2, -4)
	frame.personRadio = CreateRadio(editor, "Person", "user")
	frame.personRadio:SetPoint("LEFT", frame.roleRadio, "RIGHT", 60, 0)

	local saveButton = CreateButton(editor, "Save", 74, Save)
	saveButton:SetPoint("TOPLEFT", 0, -186)
	frame.deleteButton = CreateButton(editor, "Delete", 74, Delete)
	frame.deleteButton:SetPoint("LEFT", saveButton, "RIGHT", 4, 0)
	local newButton = CreateButton(editor, "New", 74, function()
		Select(nil)
		frame.aliasBox:SetFocus()
	end)
	newButton:SetPoint("LEFT", frame.deleteButton, "RIGHT", 4, 0)

	frame.status = editor:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	frame.status:SetPoint("TOPLEFT", saveButton, "BOTTOMLEFT", 0, -10)
	frame.status:SetPoint("RIGHT")
	frame.status:SetJustifyH("LEFT")

	-- Read-only note for members
	frame.info = inset:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	frame.info:SetPoint("TOPLEFT", 296, -16)
	frame.info:SetPoint("RIGHT", -16, 0)
	frame.info:SetJustifyH("LEFT")
	frame.info:SetSpacing(4)

	-- Bottom bar
	frame.count = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	frame.count:SetPoint("BOTTOMLEFT", 16, 9)
	frame.sendButton = CreateButton(frame, "Send to Guild", 140, function()
		ns.SendList(true)
		ns.RefreshManager()
	end)
	frame.sendButton:SetPoint("BOTTOMRIGHT", -6, 4)
end

-- Redraws the window from the current guild list. Does nothing while it is closed.
function ns.RefreshManager()
	if not frame or not frame:IsShown() then
		return
	end
	local data = ns.GetGuildData()
	local entries = data and data.entries or {}
	local officer = ns.IsOfficer()
	if selected and not tContains(entries, selected) then
		selected = nil
	end

	local sorted = {}
	for i, entry in ipairs(entries) do
		sorted[i] = entry
	end
	table.sort(sorted, function(a, b)
		return a.alias < b.alias
	end)
	frame.scrollBox:SetDataProvider(CreateDataProvider(sorted), ScrollBoxConstants.RetainScrollPosition)
	frame.empty:SetShown(#entries == 0)

	local guildName = GetGuildInfo("player")
	if not guildName then
		frame.subtitle:SetText("Join a guild to use Beacon.")
	elseif data and data.editor then
		frame.subtitle:SetText(string.format("%s  -  last changed by %s on %s",
			guildName, Ambiguate(data.editor, "guild"), date("%b %d", data.rev)))
	else
		frame.subtitle:SetText(guildName)
	end
	frame.count:SetText(string.format("%d / %d entries", #entries, ns.MAX_ENTRIES))

	frame.editor:SetShown(officer)
	frame.deleteButton:SetEnabled(selected ~= nil)
	frame.sendButton:SetShown(officer)
	frame.sendButton:SetEnabled(data ~= nil and not ns.IsSending())
	frame.sendButton:SetText(ns.IsSending() and "Sending..." or "Send to Guild")

	frame.info:SetShown(not officer)
	frame.info:SetText("Type @ in Guild or Guild Discord chat to pick an alias. Discord receives the real mention, and your chat window shows the name.\n\n"
		.. "Your guild officers keep this list up to date. Changes arrive automatically.\n\n"
		.. GRAY_FONT_COLOR:WrapTextInColorCode("@everyone and @here are always blocked."))
end

function ns.ToggleManager()
	if not frame then
		CreateManager()
	end
	frame:SetShown(not frame:IsShown())
end
