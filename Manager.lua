local _, ns = ...

---------------------------------------------------------------------------
-- Beacon window
-- Beacon's own movable window, styled after Discord: dark panels, a
-- segmented control for the views, and each alias shown as a card with a round initial and a ROLE or PERSON tag.
-- Views: Personal (the player's own aliases, shown first), Guild (shared;
-- officers edit it, everyone else reads it), Info (what the Beacon Discord
-- Sync companion tool is, with a link to copy) and, for officers only, Log
-- (guild list syncs and changes, newest first).
-- Editable lists get a side panel editor (alias, display name, Discord ID,
-- Role/Person) and an Import button; every list can be exported, searched by
-- alias or display name, and filtered to roles or people.
-- /beacon and the minimap button open and close it. It's a plain window with
-- no protected parts, so it opens in combat too. Escape closes it.
-- Events: none
-- SavedVariables: none (edits go through ns.SaveEntry and ns.DeleteEntry)
---------------------------------------------------------------------------
local COMPANION_URL = "https://github.com/drackdaddy/BeaconDiscordSync"
local AVATAR_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- Discord's dark theme colors.
local BACKGROUND = CreateColor(0.192, 0.200, 0.220)
local PANEL = CreateColor(0.169, 0.176, 0.192)
local FIELD = CreateColor(0.118, 0.122, 0.133)
local CHOSEN = CreateColor(0.251, 0.259, 0.286)
local CARD_BORDER = CreateColor(0.122, 0.125, 0.137)
local BLURPLE = CreateColor(0.345, 0.396, 0.949)
local DANGER = CreateColor(0.855, 0.216, 0.235)
local NEUTRAL = CreateColor(0.306, 0.314, 0.345)
local MUTED_TEXT = CreateColor(0.710, 0.729, 0.757)
local DIM_TEXT = CreateColor(0.580, 0.608, 0.643)
local ROLE_CHIP = CreateColor(0.235, 0.271, 0.647)
local PERSON_CHIP = CreateColor(0.102, 0.361, 0.220)
-- People get one of these, picked from their Discord ID so it never changes.
local PEOPLE_COLORS = {
	CreateColor(0.761, 0.486, 0.055),
	CreateColor(0.659, 0.235, 0.541),
	CreateColor(0.137, 0.647, 0.353),
	CreateColor(0.918, 0.267, 0.267),
	CreateColor(0.102, 0.600, 0.749),
}

local WINDOW_WIDTH, WINDOW_HEIGHT = 680, 560
local TITLE_HEIGHT = 30

local frame
local current = "personal" -- view shown: "personal", "guild", "info" or "log"
local selected             -- entry loaded in the editor, or nil for a new one
local kind = "role"        -- Role/Person choice in the editor
local showKind = "all"     -- list filter: "all", "role" or "user"

local function Fill(texture, color)
	texture:SetColorTexture(color:GetRGB())
end

-- Adds a faint light overlay that the game shows while the mouse is over button.
local function AddHover(button, anchor)
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints(anchor or button)
	hover:SetColorTexture(1, 1, 1, 0.06)
end

-- Creates a flat Discord-style button filled with color.
local function CreateFlatButton(parent, label, width, color, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, 28)
	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	Fill(background, color)
	AddHover(button)
	button:SetNormalFontObject(GameFontHighlight)
	button:SetText(label)
	button:SetScript("OnClick", onClick)
	return button
end

-- Flat buttons have no disabled look of their own, so they fade instead.
local function SetButtonEnabled(button, enabled)
	button:SetEnabled(enabled)
	button:SetAlpha(enabled and 1 or 0.4)
end

-- Creates a flat text box on a dark field, with no border.
local function CreateField(parent)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetHeight(28)
	box:SetFontObject(ChatFontNormal)
	box:SetTextInsets(10, 10, 0, 0)
	box:SetAutoFocus(false)
	local background = box:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	Fill(background, FIELD)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	return box
end

-- Creates a Discord-style segmented control: buttons on a dark strip where the
-- chosen one is lit. options = { { value, label }, ... }; onChoose(value) runs
-- on click. The caller anchors the returned row. row:Select(value) marks a
-- button as chosen; row:Layout() closes the gap after showing or hiding one.
local function CreateSegmented(parent, options, width, onChoose)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(30)
	local background = row:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	Fill(background, FIELD)
	row.buttons = {}
	for i, option in ipairs(options) do
		local button = CreateFrame("Button", nil, row)
		button:SetSize(width, 24)
		button.value = option[1]
		button.chosen = button:CreateTexture(nil, "BACKGROUND")
		button.chosen:SetAllPoints()
		Fill(button.chosen, CHOSEN)
		AddHover(button)
		button:SetNormalFontObject(GameFontHighlightSmall)
		button:SetText(option[2])
		button:SetScript("OnClick", function()
			onChoose(option[1])
		end)
		row.buttons[i] = button
	end
	function row:Layout()
		local x = 3
		for _, button in ipairs(self.buttons) do
			if button:IsShown() then
				button:SetPoint("LEFT", x, 0)
				x = x + width + 2
			end
		end
		self:SetWidth(x + 1)
	end
	function row:Select(value)
		for _, button in ipairs(self.buttons) do
			local chosen = button.value == value
			button.chosen:SetShown(chosen)
			button:GetFontString():SetTextColor((chosen and HIGHLIGHT_FONT_COLOR or MUTED_TEXT):GetRGB())
		end
	end
	row:Layout()
	return row
end

-- Creates a round colored avatar of size pixels with a letter on it.
-- Returns the avatar texture and the letter's font string.
local function CreateAvatar(parent, size, fontObject)
	local avatar = parent:CreateTexture(nil, "ARTWORK")
	avatar:SetSize(size, size)
	local mask = parent:CreateMaskTexture()
	mask:SetAllPoints(avatar)
	mask:SetTexture(AVATAR_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	avatar:AddMaskTexture(mask)
	local letter = parent:CreateFontString(nil, "OVERLAY", fontObject)
	letter:SetPoint("CENTER", avatar)
	return avatar, letter
end

-- Colors an avatar for a role (blurple) or a person (a color from their
-- Discord ID) and shows the alias's first letter, or + when there's no alias.
local function SetAvatar(avatar, letter, alias, entryKind, id)
	local color = BLURPLE
	if entryKind == "user" then
		color = PEOPLE_COLORS[(tonumber(id:sub(-1)) or 0) % #PEOPLE_COLORS + 1]
	end
	Fill(avatar, color)
	letter:SetText(alias ~= "" and alias:sub(1, 1):upper() or "+")
end

-- Creates a gray uppercase label in an editor panel, y pixels below its top.
local function CreateLabel(parent, text, y)
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", 16, y)
	label:SetText(text:upper())
	label:SetTextColor(MUTED_TEXT:GetRGB())
	return label
end

-- Creates a panel with Discord's darker card color.
local function CreatePanel(parent)
	local panel = CreateFrame("Frame", nil, parent)
	local background = panel:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	Fill(background, PANEL)
	return panel
end

local function SetStatus(text, color)
	frame.status:SetText(text or "")
	frame.status:SetTextColor((color or NORMAL_FONT_COLOR):GetRGB())
end

-- Shows the entry being edited at the top of the editor: its avatar, its
-- alias (or "New alias") and what kind of mention it is.
local function UpdateEditorHeader()
	local alias = selected and selected.alias or ""
	SetAvatar(frame.editAvatar, frame.editLetter, alias, kind, selected and selected.id or "")
	frame.editTitle:SetText(selected and ("@" .. alias) or "New alias")
	frame.editKind:SetText(kind == "role" and "Role mention" or "Person mention")
end

local function SetKind(value)
	kind = value
	frame.kindChoice:Select(value)
	UpdateEditorHeader()
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

-- Switches to the "personal", "guild", "info" or "log" view, clearing the search and filter.
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

-- Creates a labelled text box in the editor, y pixels below its top. Returns the box.
local function CreateInput(parent, label, y, maxLetters)
	local text = CreateLabel(parent, label, y)
	local box = CreateField(parent)
	box:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -4)
	box:SetPoint("RIGHT", -16, 0)
	box:SetMaxLetters(maxLetters)
	box:SetScript("OnEnterPressed", Save)
	return box
end

-- Fills one alias card. Cards are created plain and set up the first time they are used.
local function InitCard(card, entry)
	if not card.alias then
		card.border = card:CreateTexture(nil, "BACKGROUND")
		card.border:SetAllPoints()
		local background = card:CreateTexture(nil, "BORDER")
		background:SetPoint("TOPLEFT", 1, -1)
		background:SetPoint("BOTTOMRIGHT", -1, 1)
		Fill(background, PANEL)
		AddHover(card, background)
		card.avatar, card.letter = CreateAvatar(card, 32, "GameFontHighlight")
		card.avatar:SetPoint("LEFT", 10, 0)
		card.chip = card:CreateTexture(nil, "ARTWORK")
		card.chip:SetSize(54, 16)
		card.chip:SetPoint("RIGHT", -10, 0)
		card.chipText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		card.chipText:SetPoint("CENTER", card.chip)
		card.alias = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		card.alias:SetPoint("TOPLEFT", card.avatar, "TOPRIGHT", 10, -1)
		card.alias:SetPoint("RIGHT", card.chip, "LEFT", -8, 0)
		card.alias:SetJustifyH("LEFT")
		card.alias:SetWordWrap(false)
		card.name = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		card.name:SetPoint("BOTTOMLEFT", card.avatar, "BOTTOMRIGHT", 10, 1)
		card.name:SetPoint("RIGHT", card.chip, "LEFT", -8, 0)
		card.name:SetJustifyH("LEFT")
		card.name:SetWordWrap(false)
		card.name:SetTextColor(DIM_TEXT:GetRGB())
		card:SetScript("OnClick", function(self)
			if ns.CanEdit(current) then
				Select(self.entry)
			end
		end)
	end
	card.entry = entry
	SetAvatar(card.avatar, card.letter, entry.alias, entry.kind, entry.id)
	card.alias:SetText("@" .. entry.alias)
	card.name:SetText(entry.name)
	Fill(card.chip, entry.kind == "role" and ROLE_CHIP or PERSON_CHIP)
	card.chipText:SetText(entry.kind == "role" and "ROLE" or "PERSON")
	Fill(card.border, entry == selected and BLURPLE or CARD_BORDER)
end

-- Formats a server timestamp for the log, such as "Nov 23 02:31 PM".
local function LogTime(stamp)
	return date("%b %d %I:%M %p", stamp)
end

-- Fills one log row: time on the left, what happened on the right. Hovering a
-- row shows the full text, which may be cut off in the row.
local function InitLogRow(row, item)
	if not row.time then
		row.time = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		row.time:SetPoint("LEFT", 10, 0)
		row.time:SetWidth(120)
		row.time:SetJustifyH("LEFT")
		row.time:SetTextColor(DIM_TEXT:GetRGB())
		row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", row.time, "RIGHT", 6, 0)
		row.text:SetPoint("RIGHT", -6, 0)
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		row:EnableMouse(true)
		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
			GameTooltip:SetText(self.item.text, nil, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
	end
	row.item = item
	row.time:SetText(LogTime(item.time))
	row.text:SetText(item.text)
end

-- Builds a scrolling list inside parent with a thin scroll bar on its right.
-- Rows are frameType frames extent pixels tall, filled by initializer.
local function CreateScrollList(parent, frameType, extent, spacing, initializer)
	local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", 0, 0)
	scrollBox:SetPoint("BOTTOMRIGHT", -14, 0)
	local scrollBar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
	local view = CreateScrollBoxListLinearView(0, 0, 0, 0, spacing)
	view:SetElementExtent(extent)
	view:SetElementInitializer(frameType, initializer)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	return scrollBox
end

-- Shows the current guild's log and, above it, the most recent sync.
local function RefreshLog()
	local data = ns.GetGuildData()
	local log = data and data.log or {}
	frame.logBox:SetDataProvider(CreateDataProvider(log), ScrollBoxConstants.RetainScrollPosition)
	frame.logEmpty:SetShown(#log == 0)
	local lastSync
	for _, item in ipairs(log) do
		if item.sync then
			lastSync = item
			break
		end
	end
	frame.subtitle:SetTextColor(MUTED_TEXT:GetRGB())
	if lastSync then
		frame.subtitle:SetText(string.format("Last sync: %s  -  %s", LogTime(lastSync.time), lastSync.text))
	else
		frame.subtitle:SetText("Last sync: none yet. Only officers can see this log.")
	end
end

-- Builds the editor in the side panel, for lists the player may edit.
local function CreateEditor(sidePanel)
	local editor = CreateFrame("Frame", nil, sidePanel)
	editor:SetAllPoints()
	frame.editor = editor

	frame.editAvatar, frame.editLetter = CreateAvatar(editor, 40, "GameFontHighlightLarge")
	frame.editAvatar:SetPoint("TOPLEFT", 16, -16)
	frame.editTitle = editor:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	frame.editTitle:SetPoint("TOPLEFT", frame.editAvatar, "TOPRIGHT", 10, -3)
	frame.editTitle:SetPoint("RIGHT", -16, 0)
	frame.editTitle:SetJustifyH("LEFT")
	frame.editTitle:SetWordWrap(false)
	frame.editKind = editor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.editKind:SetPoint("BOTTOMLEFT", frame.editAvatar, "BOTTOMRIGHT", 10, 3)
	frame.editKind:SetTextColor(DIM_TEXT:GetRGB())

	frame.aliasBox = CreateInput(editor, "Alias (typed after @)", -70, 24)
	frame.nameBox = CreateInput(editor, "Display name", -120, 32)
	frame.idBox = CreateInput(editor, "Discord ID", -170, 20)
	frame.idBox:SetNumeric(true)
	frame.aliasBox:SetScript("OnTabPressed", function() frame.nameBox:SetFocus() end)
	frame.nameBox:SetScript("OnTabPressed", function() frame.idBox:SetFocus() end)
	frame.idBox:SetScript("OnTabPressed", function() frame.aliasBox:SetFocus() end)
	-- The header shows the alias's first letter as it is typed.
	frame.aliasBox:HookScript("OnTextChanged", function(self)
		frame.editLetter:SetText(self:GetText() ~= "" and self:GetText():sub(1, 1):upper() or "+")
	end)

	local typeLabel = CreateLabel(editor, "Mentions a", -220)
	frame.kindChoice = CreateSegmented(editor, { { "role", "Role" }, { "user", "Person" } }, 100, SetKind)
	frame.kindChoice:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", 0, -4)

	frame.status = editor:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	frame.status:SetPoint("TOPLEFT", frame.kindChoice, "BOTTOMLEFT", 0, -12)
	frame.status:SetPoint("RIGHT", -16, 0)
	frame.status:SetJustifyH("LEFT")

	local saveButton = CreateFlatButton(editor, "Save", 120, BLURPLE, Save)
	saveButton:SetPoint("BOTTOMLEFT", 16, 16)
	frame.deleteButton = CreateFlatButton(editor, "Delete", 90, DANGER, Delete)
	frame.deleteButton:SetPoint("BOTTOMRIGHT", -16, 16)
end

-- Builds the window: a thin border, a title bar to drag it by and a close
-- button, with the page in the area below. Named so Escape can close it.
local function CreateWindow()
	local window = CreateFrame("Frame", "BeaconFrame", UIParent)
	window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
	window:SetPoint("CENTER")
	window:SetFrameStrata("HIGH")
	window:SetToplevel(true)
	window:SetMovable(true)
	window:SetClampedToScreen(true)
	window:EnableMouse(true)
	window:Hide()
	table.insert(UISpecialFrames, "BeaconFrame")
	local border = window:CreateTexture(nil, "BACKGROUND", nil, -8)
	border:SetAllPoints()
	Fill(border, CARD_BORDER)

	local titleBar = CreateFrame("Frame", nil, window)
	titleBar:SetPoint("TOPLEFT", 1, -1)
	titleBar:SetPoint("TOPRIGHT", -1, -1)
	titleBar:SetHeight(TITLE_HEIGHT)
	local titleBackground = titleBar:CreateTexture(nil, "BACKGROUND")
	titleBackground:SetAllPoints()
	Fill(titleBackground, FIELD)
	titleBar:EnableMouse(true)
	titleBar:RegisterForDrag("LeftButton")
	titleBar:SetScript("OnDragStart", function() window:StartMoving() end)
	titleBar:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
	local titleText = titleBar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	titleText:SetPoint("LEFT", 12, 0)
	titleText:SetText("Beacon")
	titleText:SetTextColor(DIM_TEXT:GetRGB())
	-- The template's own click hides only its parent, the title bar.
	local close = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
	close:SetPoint("RIGHT", 2, 0)
	close:SetScript("OnClick", function() window:Hide() end)
	return window
end

-- Builds the page inside the window, below the title bar.
local function CreatePage()
	local window = CreateWindow()
	frame = CreateFrame("Frame", nil, window)
	frame:SetPoint("TOPLEFT", 1, -(TITLE_HEIGHT + 1))
	frame:SetPoint("BOTTOMRIGHT", -1, 1)
	frame:SetScript("OnShow", function()
		ns.RefreshManager()
	end)
	frame.window = window
	local background = frame:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	Fill(background, BACKGROUND)

	-- Header: logo, name and the view switcher. Log is last so hiding it from
	-- members leaves no gap.
	local logo = frame:CreateTexture(nil, "ARTWORK")
	logo:SetSize(32, 32)
	logo:SetTexture(ns.LOGO)
	logo:SetPoint("TOPLEFT", 12, -10)
	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
	title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
	title:SetText("Beacon")
	frame.viewChoice = CreateSegmented(frame, { { "personal", "Personal" }, { "guild", "Guild" }, { "info", "Info" }, { "log", "Log" } }, 84, ShowView)
	frame.viewChoice:SetPoint("LEFT", title, "RIGHT", 18, 0)
	frame.subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.subtitle:SetPoint("TOPLEFT", 14, -54)
	frame.subtitle:SetPoint("RIGHT", -14, 0)
	frame.subtitle:SetJustifyH("LEFT")

	-- Lists view: search, filter, alias cards, side panel and bottom bar
	local listView = CreateFrame("Frame", nil, frame)
	listView:SetAllPoints()
	frame.listView = listView
	frame.search = CreateField(listView)
	frame.search:SetPoint("TOPLEFT", 12, -76)
	frame.search:SetWidth(300)
	local placeholder = frame.search:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	placeholder:SetPoint("LEFT", 10, 0)
	placeholder:SetText("Search")
	local function UpdatePlaceholder(self)
		placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
	end
	frame.search:SetScript("OnEditFocusGained", UpdatePlaceholder)
	frame.search:SetScript("OnEditFocusLost", UpdatePlaceholder)
	frame.search:SetScript("OnTextChanged", function(self)
		UpdatePlaceholder(self)
		ns.RefreshManager()
	end)

	frame.filterChoice = CreateSegmented(listView, { { "all", "All" }, { "role", "Roles" }, { "user", "People" } }, 64, SetFilter)
	frame.filterChoice:SetPoint("TOPLEFT", 12, -110)
	frame.newButton = CreateFlatButton(listView, "+ New", 70, NEUTRAL, function()
		Select(nil)
		frame.aliasBox:SetFocus()
	end)
	frame.newButton:SetHeight(30)
	frame.newButton:SetPoint("TOPRIGHT", frame.search, "BOTTOMRIGHT", 0, -6)

	local cards = CreateFrame("Frame", nil, listView)
	cards:SetPoint("TOPLEFT", 12, -148)
	cards:SetPoint("BOTTOMLEFT", 12, 44)
	cards:SetWidth(314)
	frame.scrollBox = CreateScrollList(cards, "Button", 50, 6, InitCard)
	frame.empty = cards:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	frame.empty:SetPoint("CENTER", frame.scrollBox)

	local sidePanel = CreatePanel(listView)
	sidePanel:SetPoint("TOPLEFT", 340, -76)
	sidePanel:SetPoint("BOTTOMRIGHT", -12, 44)
	CreateEditor(sidePanel)

	-- Read-only note for the guild list
	frame.info = sidePanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	frame.info:SetPoint("TOPLEFT", 16, -16)
	frame.info:SetPoint("RIGHT", -16, 0)
	frame.info:SetJustifyH("LEFT")
	frame.info:SetSpacing(4)
	frame.info:SetText("Your guild officers keep this list up to date. Changes arrive automatically.\n\n"
		.. "Type @ in Guild or Guild Discord chat to pick an alias. Discord receives the real mention, and your chat window shows the name.\n\n"
		.. "Add your own aliases under Personal.\n\n"
		.. GRAY_FONT_COLOR:WrapTextInColorCode("@everyone and @here are always blocked."))

	-- Bottom bar
	frame.count = listView:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.count:SetPoint("BOTTOMLEFT", 14, 18)
	frame.count:SetTextColor(DIM_TEXT:GetRGB())
	frame.exportButton = CreateFlatButton(listView, "Export...", 90, NEUTRAL, function()
		ns.OpenTransfer("export", current)
	end)
	frame.importButton = CreateFlatButton(listView, "Import...", 90, NEUTRAL, function()
		ns.OpenTransfer("import", current)
	end)

	-- Log view (officers only)
	local logView = CreateFrame("Frame", nil, frame)
	logView:SetAllPoints()
	frame.logView = logView
	local logPanel = CreatePanel(logView)
	logPanel:SetPoint("TOPLEFT", 12, -76)
	logPanel:SetPoint("BOTTOMRIGHT", -12, 12)
	local logArea = CreateFrame("Frame", nil, logPanel)
	logArea:SetPoint("TOPLEFT", 4, -6)
	logArea:SetPoint("BOTTOMRIGHT", -4, 6)
	frame.logBox = CreateScrollList(logArea, "Frame", 22, 0, InitLogRow)
	frame.logEmpty = logPanel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	frame.logEmpty:SetPoint("CENTER")
	frame.logEmpty:SetText("No guild list activity yet.")

	-- Info view: what the companion tool does, and its link. The game can't open
	-- web links, so the link sits in a box that selects itself for copying.
	local infoView = CreateFrame("Frame", nil, frame)
	infoView:SetAllPoints()
	frame.infoView = infoView
	local infoPanel = CreatePanel(infoView)
	infoPanel:SetPoint("TOPLEFT", 12, -76)
	infoPanel:SetPoint("BOTTOMRIGHT", -12, 12)
	local infoText = infoPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	infoText:SetPoint("TOPLEFT", 16, -16)
	infoText:SetPoint("RIGHT", -16, 0)
	infoText:SetJustifyH("LEFT")
	infoText:SetSpacing(4)
	infoText:SetText("Beacon Discord Sync is a free Windows tool, downloaded separately, that fills your Beacon lists "
		.. "from your Discord server. It reads the server's members and roles with your own Discord bot and turns them "
		.. "into aliases, so nobody has to look up Discord IDs by hand.\n\n"
		.. "Run it again whenever people join or leave. It writes its export into the Beacon folder, so you type /reload "
		.. "and choose a list, or posts it in a Discord channel for you to paste into Import. People who left are "
		.. "removed, and everyone keeps their alias.\n\n"
		.. "Download it and read the setup steps here:")
	local linkBox = CreateField(infoPanel)
	linkBox:SetSize(380, 28)
	linkBox:SetPoint("TOPLEFT", infoText, "BOTTOMLEFT", 0, -10)
	linkBox:SetText(COMPANION_URL)
	linkBox:SetCursorPosition(0)
	-- Puts the link back if it was typed over, and selects it for Ctrl+C.
	local function SelectLink(self)
		self:SetText(COMPANION_URL)
		self:HighlightText()
	end
	linkBox:SetScript("OnEditFocusGained", SelectLink)
	linkBox:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			SelectLink(self)
		end
	end)
	linkBox:SetScript("OnEnterPressed", linkBox.ClearFocus)
	local copyHint = infoPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	copyHint:SetPoint("TOPLEFT", linkBox, "BOTTOMLEFT", 0, -6)
	copyHint:SetText("Click the link, press Ctrl+C to copy it, then paste it into your web browser.")
	copyHint:SetTextColor(DIM_TEXT:GetRGB())

	ShowView("personal")
end

-- Lines up the visible bottom-bar buttons from the right edge.
local function LayoutBottomButtons()
	local previous
	for _, button in ipairs({ frame.exportButton, frame.importButton }) do
		if button:IsShown() then
			button:ClearAllPoints()
			if previous then
				button:SetPoint("RIGHT", previous, "LEFT", -8, 0)
			else
				button:SetPoint("BOTTOMRIGHT", -12, 10)
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
	local officer = ns.IsOfficer()
	frame.viewChoice.buttons[4]:SetShown(officer)
	frame.viewChoice:Layout()
	if current == "log" and not officer then
		ShowView("personal")
		return
	end
	frame.listView:SetShown(current == "personal" or current == "guild")
	frame.logView:SetShown(current == "log")
	frame.infoView:SetShown(current == "info")
	if current == "log" then
		RefreshLog()
		return
	end
	if current == "info" then
		frame.subtitle:SetText("Keep your lists in step with your Discord server.")
		frame.subtitle:SetTextColor(MUTED_TEXT:GetRGB())
		return
	end

	local list = ns.GetList(current)
	local entries = list and list.entries or {}
	local editable = ns.CanEdit(current)
	if selected and not tContains(entries, selected) then
		selected = nil
		UpdateEditorHeader()
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
	local subtitleColor = MUTED_TEXT
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
	frame.newButton:SetShown(editable)
	frame.info:SetShown(not editable and guildName ~= nil)
	SetButtonEnabled(frame.deleteButton, selected ~= nil)

	SetButtonEnabled(frame.exportButton, #entries > 0)
	frame.importButton:SetShown(editable)
	LayoutBottomButtons()
end

-- Opens the Beacon window, or closes it when it is already open. The window
-- is built the first time it opens.
function ns.ToggleManager()
	if not frame then
		CreatePage()
	end
	frame.window:SetShown(not frame.window:IsShown())
end
