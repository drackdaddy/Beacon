local addonName, ns = ...

---------------------------------------------------------------------------
-- Beacon window
-- Beacon's own movable window, styled after Discord: rounded dark panels, a
-- segmented control for the views, and each alias shown as a card with a
-- round initial and a ROLE or GAMER tag, two cards to a row.
-- Views: Personal (the player's own aliases, shown first), Guild (shared;
-- officers edit it, everyone else reads it), Info (what the Beacon Discord
-- Sync companion tool is, with a link to copy) and, for officers only, Log
-- (guild list syncs and changes, newest first).
-- Editable lists get a "+ New alias" card, a side panel editor (alias,
-- display name, Discord ID, Role/Gamer; new entries start as Gamer) and an
-- Import button; every list can be exported, searched by alias or display
-- name, and filtered to roles or gamers.
-- /beacon and the minimap button open and close it. It's a plain window with
-- no protected parts, so it opens in combat too. Drag the header to move it;
-- Escape closes it.
-- Events: none
-- SavedVariables: none (edits go through ns.SaveEntry and ns.DeleteEntry)
---------------------------------------------------------------------------
local COMPANION_URL = "https://github.com/drackdaddy/BeaconDiscordSync"
local AVATAR_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- A white 32x32 rounded rectangle with 8-pixel corners. Drawn as a nine-slice,
-- so it stretches to any size while the corners stay round, and tinted to
-- any color. Every panel, card, button and field uses it.
local ROUNDED = "Interface\\AddOns\\Beacon\\Rounded.png"
local CORNER = 8

-- Discord's dark theme colors.
local BACKGROUND = CreateColor(0.192, 0.200, 0.220)
local PANEL = CreateColor(0.169, 0.176, 0.192)
local FIELD = CreateColor(0.118, 0.122, 0.133)
local CHOSEN = CreateColor(0.251, 0.259, 0.286)
local CARD_BORDER = CreateColor(0.122, 0.125, 0.137)
local NEW_BORDER = CreateColor(0.306, 0.314, 0.345)
local BLURPLE = CreateColor(0.345, 0.396, 0.949)
local DANGER = CreateColor(0.855, 0.216, 0.235)
local NEUTRAL = CreateColor(0.306, 0.314, 0.345)
local MUTED_TEXT = CreateColor(0.710, 0.729, 0.757)
local DIM_TEXT = CreateColor(0.580, 0.608, 0.643)
local ROLE_CHIP = CreateColor(0.235, 0.271, 0.647)
local GAMER_CHIP = CreateColor(0.102, 0.361, 0.220)
-- Gamers get one of these, picked from their Discord ID so it never changes.
local GAMER_COLORS = {
	CreateColor(0.761, 0.486, 0.055),
	CreateColor(0.659, 0.235, 0.541),
	CreateColor(0.137, 0.647, 0.353),
	CreateColor(0.918, 0.267, 0.267),
	CreateColor(0.102, 0.600, 0.749),
}

-- Window layout, in pixels.
local WINDOW_WIDTH, WINDOW_HEIGHT = 820, 600
local PAD = 16
local CARD_WIDTH, CARD_HEIGHT, CARD_GAP = 232, 56, 10
local CARDS_WIDTH = CARD_WIDTH * 2 + CARD_GAP
local CONTENT_TOP = -102   -- below the header and the search row
local CONTENT_BOTTOM = 52  -- above the bottom bar
local NEW_CARD = {}        -- stands in the card list for the "+ New alias" card

local frame
local current = "personal" -- view shown: "personal", "guild", "info" or "log"
local selected             -- entry loaded in the editor, or nil for a new one
local kind = "user"        -- Role/Gamer choice in the editor ("user" is a gamer)
local showKind = "all"     -- list filter: "all", "role" or "user"

-- Gives texture rounded corners and tints it color, at alpha (default 1).
local function Fill(texture, color, alpha)
	texture:SetTexture(ROUNDED)
	texture:SetTextureSliceMargins(CORNER, CORNER, CORNER, CORNER)
	texture:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
	texture:SetVertexColor(color.r, color.g, color.b, alpha or 1)
end

-- Recolors a texture already set up by Fill.
local function Tint(texture, color)
	texture:SetVertexColor(color:GetRGB())
end

-- Adds a faint rounded light that the game shows while the mouse is over button.
local function AddHover(button, anchor)
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints(anchor or button)
	Fill(hover, HIGHLIGHT_FONT_COLOR, 0.06)
end

-- Creates a rounded background texture covering owner, inset by inset pixels.
local function AddBackground(owner, color, inset, subLevel)
	local background = owner:CreateTexture(nil, "BACKGROUND", nil, subLevel)
	background:SetPoint("TOPLEFT", inset or 0, -(inset or 0))
	background:SetPoint("BOTTOMRIGHT", -(inset or 0), inset or 0)
	Fill(background, color)
	return background
end

-- Creates a flat Discord-style button filled with color.
local function CreateFlatButton(parent, label, width, color, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, 30)
	AddBackground(button, color)
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
	box:SetHeight(30)
	box:SetFontObject(ChatFontNormal)
	box:SetTextInsets(10, 10, 0, 0)
	box:SetAutoFocus(false)
	AddBackground(box, FIELD)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	return box
end

-- Creates a Discord-style segmented control where the chosen button is lit.
-- options = { { value, label }, ... }; onChoose(value) runs on click. With
-- strip, the buttons sit on a dark strip. The caller anchors the returned row.
-- row:Select(value) marks a button as chosen; row:Layout() closes the gap
-- after showing or hiding one.
local function CreateSegmented(parent, options, width, onChoose, strip)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(32)
	if strip then
		AddBackground(row, FIELD)
	end
	row.buttons = {}
	for i, option in ipairs(options) do
		local button = CreateFrame("Button", nil, row)
		button:SetSize(width, 26)
		button.value = option[1]
		button.chosen = AddBackground(button, CHOSEN)
		AddHover(button)
		button:SetNormalFontObject(GameFontHighlight)
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

-- Colors an avatar for a role (blurple) or a gamer (a color from their
-- Discord ID) and shows the alias's first letter, or + when there's no alias.
local function SetAvatar(avatar, letter, alias, entryKind, id)
	local color = BLURPLE
	if entryKind == "user" then
		color = GAMER_COLORS[(tonumber(id:sub(-1)) or 0) % #GAMER_COLORS + 1]
	end
	avatar:SetColorTexture(color:GetRGB())
	letter:SetText(alias ~= "" and alias:sub(1, 1):upper() or "+")
end

-- Creates a gray uppercase label in an editor panel, y pixels below its top.
local function CreateLabel(parent, text, y)
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", PAD, y)
	label:SetText(text:upper())
	label:SetTextColor(MUTED_TEXT:GetRGB())
	return label
end

-- Creates a rounded panel in Discord's darker card color.
local function CreatePanel(parent)
	local panel = CreateFrame("Frame", nil, parent)
	AddBackground(panel, PANEL)
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
	frame.editKind:SetText(kind == "role" and "Role mention" or "Gamer mention")
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
-- New entries start as Gamer, the most common kind of alias.
local function Select(entry)
	selected = entry
	frame.aliasBox:SetText(entry and entry.alias or "")
	frame.nameBox:SetText(entry and entry.name or "")
	frame.idBox:SetText(entry and entry.id or "")
	SetKind(entry and entry.kind or "user")
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
	box:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -6)
	box:SetPoint("RIGHT", -PAD, 0)
	box:SetMaxLetters(maxLetters)
	box:SetScript("OnEnterPressed", Save)
	return box
end

-- Creates one empty alias card inside a card row.
local function CreateCard(row)
	local card = CreateFrame("Button", nil, row)
	card:SetSize(CARD_WIDTH, CARD_HEIGHT)
	card.border = AddBackground(card, CARD_BORDER)
	local background = AddBackground(card, PANEL, 1, 1)
	AddHover(card, background)
	card.avatar, card.letter = CreateAvatar(card, 34, "GameFontHighlightLarge")
	card.avatar:SetPoint("LEFT", 10, 0)
	card.chip = card:CreateTexture(nil, "ARTWORK")
	card.chip:SetSize(54, 16)
	card.chip:SetPoint("RIGHT", -10, 0)
	Fill(card.chip, ROLE_CHIP)
	card.chipText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	card.chipText:SetPoint("CENTER", card.chip)
	card.alias = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
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
	card.newText = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	card.newText:SetPoint("CENTER")
	card.newText:SetText("+ New alias")
	card.newText:SetTextColor(MUTED_TEXT:GetRGB())
	card:SetScript("OnClick", function(self)
		if self.entry == NEW_CARD then
			Select(nil)
			frame.aliasBox:SetFocus()
		elseif ns.CanEdit(current) then
			Select(self.entry)
		end
	end)
	return card
end

-- Fills one card with entry, or turns it into the "+ New alias" card.
local function SetCard(card, entry)
	card.entry = entry
	local isNew = entry == NEW_CARD
	card.newText:SetShown(isNew)
	for _, part in ipairs({ card.avatar, card.letter, card.chip, card.chipText, card.alias, card.name }) do
		part:SetShown(not isNew)
	end
	if isNew then
		Tint(card.border, NEW_BORDER)
		return
	end
	SetAvatar(card.avatar, card.letter, entry.alias, entry.kind, entry.id)
	card.alias:SetText("@" .. entry.alias)
	card.name:SetText(entry.name)
	Tint(card.chip, entry.kind == "role" and ROLE_CHIP or GAMER_CHIP)
	card.chipText:SetText(entry.kind == "role" and "ROLE" or "GAMER")
	Tint(card.border, entry == selected and BLURPLE or CARD_BORDER)
end

-- Fills one row of up to two cards. pair = { entry, entry or nil }.
-- Rows are created plain and get their cards the first time they are used.
local function InitCardRow(row, pair)
	if not row.cards then
		row.cards = { CreateCard(row), CreateCard(row) }
		row.cards[1]:SetPoint("TOPLEFT")
		row.cards[2]:SetPoint("TOPLEFT", CARD_WIDTH + CARD_GAP, 0)
	end
	for i, card in ipairs(row.cards) do
		card:SetShown(pair[i] ~= nil)
		if pair[i] then
			SetCard(card, pair[i])
		end
	end
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

-- Shows the current guild's log and, in the bottom bar, the most recent sync.
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

	frame.editAvatar, frame.editLetter = CreateAvatar(editor, 44, "GameFontHighlightHuge")
	frame.editAvatar:SetPoint("TOPLEFT", PAD, -PAD)
	frame.editTitle = editor:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	frame.editTitle:SetPoint("TOPLEFT", frame.editAvatar, "TOPRIGHT", 10, -6)
	frame.editTitle:SetPoint("RIGHT", -PAD, 0)
	frame.editTitle:SetJustifyH("LEFT")
	frame.editTitle:SetWordWrap(false)
	frame.editKind = editor:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.editKind:SetPoint("BOTTOMLEFT", frame.editAvatar, "BOTTOMRIGHT", 10, 6)
	frame.editKind:SetTextColor(DIM_TEXT:GetRGB())

	frame.aliasBox = CreateInput(editor, "Alias", -76, 24)
	frame.nameBox = CreateInput(editor, "Display name", -133, 32)
	frame.idBox = CreateInput(editor, "Discord ID", -190, 20)
	frame.idBox:SetNumeric(true)
	frame.aliasBox:SetScript("OnTabPressed", function() frame.nameBox:SetFocus() end)
	frame.nameBox:SetScript("OnTabPressed", function() frame.idBox:SetFocus() end)
	frame.idBox:SetScript("OnTabPressed", function() frame.aliasBox:SetFocus() end)
	-- The header shows the alias's first letter as it is typed.
	frame.aliasBox:HookScript("OnTextChanged", function(self)
		frame.editLetter:SetText(self:GetText() ~= "" and self:GetText():sub(1, 1):upper() or "+")
	end)

	local typeLabel = CreateLabel(editor, "Type", -247)
	frame.kindChoice = CreateSegmented(editor, { { "role", "Role" }, { "user", "Gamer" } }, 124, SetKind, true)
	frame.kindChoice:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", 0, -6)

	frame.status = editor:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	frame.status:SetPoint("TOPLEFT", frame.kindChoice, "BOTTOMLEFT", 0, -12)
	frame.status:SetPoint("RIGHT", -PAD, 0)
	frame.status:SetJustifyH("LEFT")

	frame.deleteButton = CreateFlatButton(editor, "Delete", 70, DANGER, Delete)
	frame.deleteButton:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	local saveButton = CreateFlatButton(editor, "Save", 0, BLURPLE, Save)
	saveButton:SetPoint("BOTTOMLEFT", PAD, PAD)
	saveButton:SetPoint("RIGHT", frame.deleteButton, "LEFT", -8, 0)
end

-- Builds the window, named so Escape can close it, and everything in it. The
-- header (logo, name and version, view switcher) is where the window is dragged from.
local function CreateWindow()
	frame = CreateFrame("Frame", "BeaconFrame", UIParent)
	frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:Hide()
	frame:SetScript("OnShow", function()
		ns.RefreshManager()
	end)
	table.insert(UISpecialFrames, "BeaconFrame")
	AddBackground(frame, CARD_BORDER, 0, -8)
	AddBackground(frame, BACKGROUND, 1, -7)

	-- Header. Log is the last view so hiding it from members leaves no gap.
	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(56)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() frame:StartMoving() end)
	header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
	local logo = header:CreateTexture(nil, "ARTWORK")
	logo:SetSize(32, 32)
	logo:SetPoint("TOPLEFT", PAD, -14)
	logo:SetTexture(ns.LOGO)
	local logoMask = header:CreateMaskTexture()
	logoMask:SetAllPoints(logo)
	logoMask:SetTexture(ROUNDED, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	logo:AddMaskTexture(logoMask)
	-- The name with the version from the TOC under it, together as tall as the logo.
	local title = header:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, 1)
	title:SetText("Beacon")
	local version = header:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -1)
	version:SetText("v" .. C_AddOns.GetAddOnMetadata(addonName, "Version"))
	version:SetTextColor(DIM_TEXT:GetRGB())
	frame.viewChoice = CreateSegmented(header, { { "personal", "Personal" }, { "guild", "Guild" }, { "info", "Info" }, { "log", "Log" } }, 84, ShowView, true)
	frame.viewChoice:SetPoint("LEFT", logo, "RIGHT", 10 + math.max(title:GetStringWidth(), version:GetStringWidth()) + 22, 0)

	-- A flat close button: an X made of two thin crossed lines.
	local close = CreateFrame("Button", nil, header)
	close:SetSize(28, 28)
	close:SetPoint("RIGHT", -12, 0)
	close:SetPoint("TOP", logo, "TOP", 0, -2)
	AddHover(close)
	for _, angle in ipairs({ 45, -45 }) do
		local line = close:CreateTexture(nil, "ARTWORK")
		line:SetSize(14, 2)
		line:SetPoint("CENTER")
		line:SetColorTexture(MUTED_TEXT:GetRGB())
		line:SetRotation(math.rad(angle))
	end
	close:SetScript("OnClick", function() frame:Hide() end)

	-- Bottom bar text: what the list is, its sync state or warnings, and the last sync on Log.
	frame.subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.subtitle:SetPoint("BOTTOMLEFT", PAD, 14)
	frame.subtitle:SetWidth(560)
	frame.subtitle:SetJustifyH("LEFT")
	frame.subtitle:SetMaxLines(2)

	-- Lists view: search and filter row, alias cards, side panel and Import/Export
	local listView = CreateFrame("Frame", nil, frame)
	listView:SetAllPoints()
	frame.listView = listView
	frame.search = CreateField(listView)
	frame.search:SetPoint("TOPLEFT", PAD, -60)
	frame.search:SetWidth(280)
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
	frame.filterChoice = CreateSegmented(listView, { { "all", "All" }, { "role", "Roles" }, { "user", "Gamers" } }, 64, SetFilter)
	frame.filterChoice:SetPoint("LEFT", frame.search, "RIGHT", 8, 0)
	frame.count = listView:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.count:SetPoint("RIGHT", -PAD, 0)
	frame.count:SetPoint("TOP", frame.search, "TOP", 0, -9)
	frame.count:SetTextColor(DIM_TEXT:GetRGB())

	local cards = CreateFrame("Frame", nil, listView)
	cards:SetPoint("TOPLEFT", PAD, CONTENT_TOP)
	cards:SetPoint("BOTTOMLEFT", PAD, CONTENT_BOTTOM)
	cards:SetWidth(CARDS_WIDTH + 18)
	frame.scrollBox = CreateScrollList(cards, "Frame", CARD_HEIGHT, 8, InitCardRow)
	frame.empty = cards:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	frame.empty:SetPoint("CENTER", frame.scrollBox)

	local sidePanel = CreatePanel(listView)
	sidePanel:SetPoint("TOPLEFT", cards, "TOPRIGHT", 8, 0)
	sidePanel:SetPoint("BOTTOMRIGHT", -PAD, CONTENT_BOTTOM)
	CreateEditor(sidePanel)

	-- Read-only note for the guild list
	frame.info = sidePanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	frame.info:SetPoint("TOPLEFT", PAD, -PAD)
	frame.info:SetPoint("RIGHT", -PAD, 0)
	frame.info:SetJustifyH("LEFT")
	frame.info:SetSpacing(4)
	frame.info:SetText("Your guild officers keep this list up to date. Changes arrive automatically.\n\n"
		.. "Type @ in Guild or Guild Discord chat to pick an alias. Discord receives the real mention, and your chat window shows the name.\n\n"
		.. "Add your own aliases under Personal.\n\n"
		.. GRAY_FONT_COLOR:WrapTextInColorCode("@everyone and @here are always blocked."))

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
	logPanel:SetPoint("TOPLEFT", PAD, -60)
	logPanel:SetPoint("BOTTOMRIGHT", -PAD, CONTENT_BOTTOM)
	local logArea = CreateFrame("Frame", nil, logPanel)
	logArea:SetPoint("TOPLEFT", 4, -8)
	logArea:SetPoint("BOTTOMRIGHT", -4, 8)
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
	infoPanel:SetPoint("TOPLEFT", PAD, -60)
	infoPanel:SetPoint("BOTTOMRIGHT", -PAD, CONTENT_BOTTOM)
	local infoText = infoPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	infoText:SetPoint("TOPLEFT", 20, -20)
	infoText:SetPoint("RIGHT", -20, 0)
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
	linkBox:SetWidth(420)
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
				button:SetPoint("BOTTOMRIGHT", -PAD, 12)
			end
			previous = button
		end
	end
end

-- Redraws the window from the shown list. Does nothing while it is not on screen.
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
	local cardsShown = #shown
	if editable then
		shown[#shown + 1] = NEW_CARD
	end
	-- Two cards to a row.
	local rows = {}
	for i = 1, #shown, 2 do
		rows[#rows + 1] = { shown[i], shown[i + 1] }
	end
	frame.scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
	frame.empty:SetText(#entries == 0 and "No aliases yet." or "No matches.")
	frame.empty:SetShown(#shown == 0)

	local guildName = GetGuildInfo("player")
	local subtitleColor = MUTED_TEXT
	local lastChanged = ""
	if current == "personal" then
		frame.subtitle:SetText("Your own aliases. Only you use them, and they win over guild aliases with the same name.")
	elseif not guildName then
		frame.subtitle:SetText("Join a guild to receive its shared list.")
	elseif editable and ns.HasNewerGuildList() then
		frame.subtitle:SetText("A guildmate has a newer list than yours. Wait for another officer to come online before editing, or your edits will replace it.")
		subtitleColor = RED_FONT_COLOR
	elseif ns.IsSending() then
		frame.subtitle:SetText(guildName .. "  -  sharing the list with your guild...")
	else
		frame.subtitle:SetText(guildName)
	end
	if current == "guild" and list and list.editor then
		lastChanged = string.format("  ·  last changed by %s", Ambiguate(list.editor, "guild"))
	end
	frame.subtitle:SetTextColor(subtitleColor:GetRGB())
	if cardsShown < #entries then
		frame.count:SetText(string.format("%d of %d shown", cardsShown, #entries) .. lastChanged)
	else
		frame.count:SetText(string.format("%d / %d", #entries, ns.MAX_ENTRIES) .. lastChanged)
	end

	frame.editor:SetShown(editable)
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
		CreateWindow()
	end
	frame:SetShown(not frame:IsShown())
end
