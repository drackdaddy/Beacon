local _, ns = ...

---------------------------------------------------------------------------
-- Lists page in Options > AddOns
-- Beacon's page in the game's Options window, under the AddOns tab. Two views,
-- chosen with buttons at the top: Personal (the player's own aliases, shown
-- first) and Guild (shared; officers edit and send it, everyone else reads it).
-- Editable lists get an editor (alias, display name, Role/Person, Discord ID)
-- and an Import button; every list can be exported, searched by alias or
-- display name, and filtered to roles or people.
-- /beacon and the minimap button open Options straight to this page. Options
-- can't be opened by an addon during combat, so that waits until combat ends.
-- Events: PLAYER_LOGIN (registers the page), PLAYER_REGEN_ENABLED (deferred open)
-- SavedVariables: none (edits go through ns.SaveEntry and ns.DeleteEntry)
---------------------------------------------------------------------------
local HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"

local frame
local category             -- the page's entry in Options > AddOns
local openAfterCombat = false
local current = "personal" -- list shown: "personal" or "guild"
local selected             -- entry loaded in the editor, or nil for a new one
local kind = "role"        -- Role/Person choice in the editor
local showKind = "all"     -- list filter: "all", "role" or "user"

local function SetStatus(text, color)
	frame.status:SetText(text or "")
	frame.status:SetTextColor((color or NORMAL_FONT_COLOR):GetRGB())
end

local function SetKind(value)
	kind = value
	frame.kindChoice:Select(value)
end

-- Sets the list filter to "all", "role" or "user" and redraws the list.
local function SetFilter(value)
	showKind = value
	frame.filterChoice:Select(value)
	ns.RefreshManager()
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

-- Switches to the "personal" or "guild" list, clearing the search and filter.
local function ShowView(value)
	current = value
	frame.viewChoice:Select(value)
	frame.search:SetText("")
	SetFilter("all")
	Select(nil)
end

-- Message shown after an edit; guild edits are shared automatically.
local function SavedMessage(verb)
	if current == "guild" then
		return verb .. " Your guild gets the change automatically in a few seconds."
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

-- Creates a standard red game button. Also used by the import and export window.
function ns.CreateButton(parent, label, width, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(label)
	button:SetScript("OnClick", onClick)
	return button
end

-- Creates a row of full-size game buttons where one is chosen at a time; the
-- chosen one stays lit with white text. These are much easier to click than
-- radio buttons. options = { { value, label }, ... }; onChoose(value) runs on click.
-- The caller anchors row.buttons[1]. row:Select(value) marks a button as chosen.
local function CreateChoiceRow(parent, options, width, onChoose)
	local row = { buttons = {} }
	for i, option in ipairs(options) do
		local button = ns.CreateButton(parent, option[2], width, function()
			onChoose(option[1])
		end)
		button.value = option[1]
		if i > 1 then
			button:SetPoint("LEFT", row.buttons[i - 1], "RIGHT", 4, 0)
		end
		row.buttons[i] = button
	end
	function row:Select(value)
		for _, button in ipairs(self.buttons) do
			local chosen = button.value == value
			button:SetNormalFontObject(chosen and GameFontHighlight or GameFontNormal)
			if chosen then
				button:LockHighlight()
			else
				button:UnlockHighlight()
			end
		end
	end
	return row
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

-- Builds the page. Options sizes and positions it, so everything is anchored
-- to its edges.
local function CreatePage()
	frame = CreateFrame("Frame")
	frame:SetScript("OnShow", function()
		ns.RefreshManager()
	end)
	-- The lists aren't settings: Options' Okay, Cancel and Defaults leave them alone.
	local function DoNothing() end
	frame.OnCommit = DoNothing
	frame.OnDefault = DoNothing
	frame.OnRefresh = DoNothing

	-- Header, matching other Options pages
	local logo = frame:CreateTexture(nil, "ARTWORK")
	logo:SetSize(32, 32)
	logo:SetTexture(ns.LOGO)
	logo:SetPoint("TOPLEFT", 8, -8)
	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
	title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
	title:SetText("Beacon")
	local divider = frame:CreateTexture(nil, "ARTWORK")
	divider:SetAtlas("Options_HorizontalDivider", true)
	divider:SetPoint("TOP", 0, -48)

	-- Personal / Guild
	frame.viewChoice = CreateChoiceRow(frame, { { "personal", "Personal" }, { "guild", "Guild" } }, 120, ShowView)
	frame.viewChoice.buttons[1]:SetPoint("TOPLEFT", 10, -60)
	frame.subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.subtitle:SetPoint("TOPLEFT", 12, -92)
	frame.subtitle:SetPoint("RIGHT", -12, 0)
	frame.subtitle:SetJustifyH("LEFT")

	-- Search box, filter and alias list
	frame.search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	frame.search:SetSize(266, 20)
	frame.search:SetPoint("TOPLEFT", 16, -112)
	frame.search:SetAutoFocus(false)
	-- Hooked so the template keeps its own clear button and placeholder handling.
	frame.search:HookScript("OnTextChanged", function()
		ns.RefreshManager()
	end)

	frame.filterChoice = CreateChoiceRow(frame, { { "all", "All" }, { "role", "Roles" }, { "user", "People" } }, 88, SetFilter)
	frame.filterChoice.buttons[1]:SetPoint("TOPLEFT", 10, -136)

	local listInset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
	listInset:SetPoint("TOPLEFT", 10, -164)
	listInset:SetPoint("BOTTOMLEFT", 10, 40)
	listInset:SetWidth(272)
	local scrollBox = CreateFrame("Frame", nil, listInset, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", 4, -4)
	scrollBox:SetPoint("BOTTOMRIGHT", -18, 4)
	local scrollBar = CreateFrame("EventFrame", nil, listInset, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(20)
	view:SetElementInitializer("Button", InitRow)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	frame.scrollBox = scrollBox

	frame.empty = listInset:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	frame.empty:SetPoint("CENTER", scrollBox)

	-- Editor for lists the player may edit
	local editor = CreateFrame("Frame", nil, frame)
	editor:SetPoint("TOPLEFT", 306, -112)
	editor:SetPoint("BOTTOMRIGHT", -10, 40)
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
	frame.kindChoice = CreateChoiceRow(editor, { { "role", "Role" }, { "user", "Person" } }, 113, SetKind)
	frame.kindChoice.buttons[1]:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", 0, -4)

	local saveButton = ns.CreateButton(editor, "Save", 74, Save)
	saveButton:SetPoint("TOPLEFT", 0, -186)
	frame.deleteButton = ns.CreateButton(editor, "Delete", 74, Delete)
	frame.deleteButton:SetPoint("LEFT", saveButton, "RIGHT", 4, 0)
	local newButton = ns.CreateButton(editor, "New", 74, function()
		Select(nil)
		frame.aliasBox:SetFocus()
	end)
	newButton:SetPoint("LEFT", frame.deleteButton, "RIGHT", 4, 0)
	frame.status = editor:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	frame.status:SetPoint("TOPLEFT", saveButton, "BOTTOMLEFT", 0, -10)
	frame.status:SetPoint("RIGHT")
	frame.status:SetJustifyH("LEFT")

	-- Read-only note for the guild list
	frame.info = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	frame.info:SetPoint("TOPLEFT", 306, -116)
	frame.info:SetPoint("RIGHT", -16, 0)
	frame.info:SetJustifyH("LEFT")
	frame.info:SetSpacing(4)
	frame.info:SetText("Your guild officers keep this list up to date. Changes arrive automatically.\n\n"
		.. "Type @ in Guild or Guild Discord chat to pick an alias. Discord receives the real mention, and your chat window shows the name.\n\n"
		.. "Add your own aliases under Personal.\n\n"
		.. GRAY_FONT_COLOR:WrapTextInColorCode("@everyone and @here are always blocked."))

	-- Bottom bar
	frame.count = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	frame.count:SetPoint("BOTTOMLEFT", 14, 16)
	frame.exportButton = ns.CreateButton(frame, "Export...", 90, function()
		ns.OpenTransfer("export", current)
	end)
	frame.importButton = ns.CreateButton(frame, "Import...", 90, function()
		ns.OpenTransfer("import", current)
	end)

	ShowView("personal")
end

-- Lines up the visible bottom-bar buttons from the right edge.
local function LayoutBottomButtons()
	local previous
	for _, button in ipairs({ frame.exportButton, frame.importButton }) do
		if button:IsShown() then
			button:ClearAllPoints()
			if previous then
				button:SetPoint("RIGHT", previous, "LEFT", -4, 0)
			else
				button:SetPoint("BOTTOMRIGHT", -10, 10)
			end
			previous = button
		end
	end
end

-- Redraws the page from the shown list. Does nothing while it is not on screen.
function ns.RefreshManager()
	if not frame or not frame:IsVisible() then
		return
	end
	local list = ns.GetList(current)
	local entries = list and list.entries or {}
	local editable = ns.CanEdit(current)
	if selected and not tContains(entries, selected) then
		selected = nil
	end

	-- Show only entries of the chosen kind whose alias or display name contains the search text.
	local search = strtrim(frame.search:GetText()):lower()
	local shown = {}
	for _, entry in ipairs(entries) do
		local kindMatches = showKind == "all" or entry.kind == showKind
		local searchMatches = search == "" or entry.alias:find(search, 1, true) or entry.name:lower():find(search, 1, true)
		if kindMatches and searchMatches then
			shown[#shown + 1] = entry
		end
	end
	table.sort(shown, function(a, b)
		return a.alias < b.alias
	end)
	frame.scrollBox:SetDataProvider(CreateDataProvider(shown), ScrollBoxConstants.RetainScrollPosition)
	frame.empty:SetText(#entries == 0 and "No aliases yet." or "No matches.")
	frame.empty:SetShown(#shown == 0)

	local guildName = GetGuildInfo("player")
	local subtitleColor = HIGHLIGHT_FONT_COLOR
	if current == "personal" then
		frame.subtitle:SetText("Your own aliases. Only you use them, and they win over guild aliases with the same name.")
	elseif not guildName then
		frame.subtitle:SetText("Join a guild to receive its shared list.")
	elseif editable and ns.HasNewerGuildList() then
		frame.subtitle:SetText("A guildmate has a newer list than yours. Wait for another officer to come online before editing, or your edits will replace it.")
		subtitleColor = RED_FONT_COLOR
	elseif ns.IsSending() then
		frame.subtitle:SetText(guildName .. "  -  sharing the list with your guild...")
	elseif list and list.editor then
		frame.subtitle:SetText(string.format("%s  -  last changed by %s on %s",
			guildName, Ambiguate(list.editor, "guild"), date("%b %d", list.rev)))
	else
		frame.subtitle:SetText(guildName)
	end
	frame.subtitle:SetTextColor(subtitleColor:GetRGB())
	if #shown < #entries then
		frame.count:SetText(string.format("%d of %d shown", #shown, #entries))
	else
		frame.count:SetText(string.format("%d / %d entries", #entries, ns.MAX_ENTRIES))
	end

	frame.editor:SetShown(editable)
	frame.info:SetShown(not editable and guildName ~= nil)
	frame.deleteButton:SetEnabled(selected ~= nil)

	frame.exportButton:SetEnabled(#entries > 0)
	frame.importButton:SetShown(editable)
	LayoutBottomButtons()
end

-- Opens Options to Beacon's page, or right after combat if the player is fighting.
function ns.OpenManager()
	if InCombatLockdown() then
		openAfterCombat = true
		ns.Print("Opens in Options when combat ends.")
		return
	end
	Settings.OpenToCategory(category:GetID())
end

ns.On("PLAYER_LOGIN", function()
	CreatePage()
	category = Settings.RegisterCanvasLayoutCategory(frame, "Beacon")
	Settings.RegisterAddOnCategory(category)
end)

ns.On("PLAYER_REGEN_ENABLED", function()
	if openAfterCombat then
		openAfterCombat = false
		ns.OpenManager()
	end
end)
