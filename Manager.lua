local _, ns = ...

---------------------------------------------------------------------------
-- Lists window
-- /beacon or the minimap button opens a standard Blizzard portrait window with
-- two tabs: Guild (shared; officers edit and send it, everyone else reads it)
-- and Personal (the player's own aliases). Editable lists get an editor
-- (alias, display name, Role/Person, Discord ID) and an Import button.
-- Built the first time it is opened.
-- Events: none (refreshed through ns.RefreshManager)
-- SavedVariables: none (edits go through ns.SaveEntry and ns.DeleteEntry)
---------------------------------------------------------------------------
local HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local TABS = { "guild", "personal" }

local frame
local current = "guild" -- list shown: "guild" or "personal"
local selected          -- entry loaded in the editor, or nil for a new one
local kind = "role"     -- Role/Person choice in the editor

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

-- Message shown after an edit; guild edits still need sending.
local function SavedMessage(verb)
	if current == "guild" then
		return verb .. " Choose Send to Guild to share your changes."
	end
	return verb
end

local function Save()
	local alias = strtrim(frame.aliasBox:GetText())
	local name = strtrim(frame.nameBox:GetText())
	local fields = { alias = alias, name = name ~= "" and name or alias, kind = kind, id = strtrim(frame.idBox:GetText()) }
	local entry, err = ns.SaveEntry(current, fields, selected)
	if not entry then
		SetStatus(err, RED_FONT_COLOR)
		return
	end
	Select(entry)
	SetStatus(SavedMessage("Saved."), GREEN_FONT_COLOR)
end

local function Delete()
	if selected then
		ns.DeleteEntry(current, selected)
		Select(nil)
		SetStatus(SavedMessage("Deleted."), GREEN_FONT_COLOR)
	end
end

-- Switches the window to tab index (1 = Guild, 2 = Personal).
local function ShowTab(index)
	current = TABS[index]
	PanelTemplates_SetTab(frame, index)
	Select(nil)
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

-- Creates a standard red game button. Also used by the import window.
function ns.CreateButton(parent, label, width, onClick)
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
			if ns.CanEdit(current) then
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
	frame:SetPortraitToAsset(ns.LOGO)
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

	-- Bottom tabs. Blizzard's tab helpers find them by the frame's name.
	for index, label in ipairs({ "Guild", "Personal" }) do
		local tab = CreateFrame("Button", "BeaconFrameTab" .. index, frame, "PanelTabButtonTemplate")
		tab:SetID(index)
		tab:SetText(label)
		tab:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
			ShowTab(index)
		end)
		if index == 1 then
			tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2)
		else
			tab:SetPoint("TOPLEFT", _G["BeaconFrameTab" .. (index - 1)], "TOPRIGHT", 3, 0)
		end
		PanelTemplates_TabResize(tab, 0)
	end
	PanelTemplates_SetNumTabs(frame, #TABS)
	PanelTemplates_SetTab(frame, 1)

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

	-- Editor for lists the player may edit
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

	local saveButton = ns.CreateButton(editor, "Save", 74, Save)
	saveButton:SetPoint("TOPLEFT", 0, -186)
	frame.deleteButton = ns.CreateButton(editor, "Delete", 74, Delete)
	frame.deleteButton:SetPoint("LEFT", saveButton, "RIGHT", 4, 0)
	local newButton = ns.CreateButton(editor, "New", 74, function()
		Select(nil)
		frame.aliasBox:SetFocus()
	end)
	newButton:SetPoint("LEFT", frame.deleteButton, "RIGHT", 4, 0)
	local importButton = ns.CreateButton(editor, "Import...", 230, function()
		ns.OpenImport(current)
	end)
	importButton:SetPoint("TOPLEFT", saveButton, "BOTTOMLEFT", 0, -6)

	frame.status = editor:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	frame.status:SetPoint("TOPLEFT", importButton, "BOTTOMLEFT", 0, -10)
	frame.status:SetPoint("RIGHT")
	frame.status:SetJustifyH("LEFT")

	-- Read-only note for the guild list
	frame.info = inset:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	frame.info:SetPoint("TOPLEFT", 296, -16)
	frame.info:SetPoint("RIGHT", -16, 0)
	frame.info:SetJustifyH("LEFT")
	frame.info:SetSpacing(4)
	frame.info:SetText("Your guild officers keep this list up to date. Changes arrive automatically.\n\n"
		.. "Type @ in Guild or Guild Discord chat to pick an alias. Discord receives the real mention, and your chat window shows the name.\n\n"
		.. "Add your own aliases on the Personal tab.\n\n"
		.. GRAY_FONT_COLOR:WrapTextInColorCode("@everyone and @here are always blocked."))

	-- Bottom bar
	frame.count = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	frame.count:SetPoint("BOTTOMLEFT", 16, 9)
	frame.sendButton = ns.CreateButton(frame, "Send to Guild", 140, function()
		ns.SendList(true)
		ns.RefreshManager()
	end)
	frame.sendButton:SetPoint("BOTTOMRIGHT", -6, 4)
end

-- Redraws the window from the shown list. Does nothing while it is closed.
function ns.RefreshManager()
	if not frame or not frame:IsShown() then
		return
	end
	local list = ns.GetList(current)
	local entries = list and list.entries or {}
	local editable = ns.CanEdit(current)
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
	if current == "personal" then
		frame.subtitle:SetText("Your own aliases. Only you use them, and they win over guild aliases with the same name.")
	elseif not guildName then
		frame.subtitle:SetText("Join a guild to receive its shared list.")
	elseif list and list.editor then
		frame.subtitle:SetText(string.format("%s  -  last changed by %s on %s",
			guildName, Ambiguate(list.editor, "guild"), date("%b %d", list.rev)))
	else
		frame.subtitle:SetText(guildName)
	end
	frame.count:SetText(string.format("%d / %d entries", #entries, ns.MAX_ENTRIES))

	frame.editor:SetShown(editable)
	frame.info:SetShown(not editable and guildName ~= nil)
	frame.deleteButton:SetEnabled(selected ~= nil)

	local officerGuildTab = current == "guild" and editable
	frame.sendButton:SetShown(officerGuildTab)
	frame.sendButton:SetEnabled(list ~= nil and not ns.IsSending())
	frame.sendButton:SetText(ns.IsSending() and "Sending..." or "Send to Guild")
end

function ns.ToggleManager()
	if not frame then
		CreateManager()
	end
	frame:SetShown(not frame:IsShown())
end
