local _, ns = ...

---------------------------------------------------------------------------
-- Import and export
-- One window with two uses:
--   Import: the player pastes many aliases at once, one per line, into the
--     list they are viewing (personal for anyone, guild for officers).
--     Existing aliases are updated and the rest are added.
--   Export: shows the viewed list as text in the same format, selected and
--     ready to copy, for backups or pasting into Import elsewhere.
-- Events: none
-- SavedVariables: none (changes go through ns.ImportEntries)
---------------------------------------------------------------------------
local LIST_NAMES = { guild = "guild list", personal = "personal list" }
local MAX_SKIPPED_SHOWN = 10
local IMPORT_HELP = "One per line: alias, Role or Person, Discord ID, display name (optional).\n"
	.. GRAY_FONT_COLOR:WrapTextInColorCode("Example: raid, Role, 123456789012345678, Raid Team")
local EXPORT_HELP = "Press Ctrl+C to copy. Paste it into Import on any list or character, or keep it as a backup.\n"
	.. GRAY_FONT_COLOR:WrapTextInColorCode("Press Escape to close.")

local frame
local target -- list being imported into: "guild" or "personal"

local function SetStatus(text, color)
	frame.status:SetText(text)
	frame.status:SetTextColor(color:GetRGB())
end

-- Describes skipped line numbers, listing at most MAX_SKIPPED_SHOWN of them.
-- Also used by the Discord import prompt.
function ns.SkippedText(skipped)
	local shown = {}
	for i = 1, math.min(#skipped, MAX_SKIPPED_SHOWN) do
		shown[i] = skipped[i]
	end
	local text = "Skipped line " .. table.concat(shown, ", ")
	if #skipped > MAX_SKIPPED_SHOWN then
		text = text .. string.format(" and %d more", #skipped - MAX_SKIPPED_SHOWN)
	end
	return text .. " (check the format, or the list is full)."
end

-- Returns a one-line result such as "Added 3, updated 1, removed 2." for an
-- import into which. Also used by the Discord import prompt.
function ns.ImportSummary(which, added, updated, removed)
	local summary = string.format("Added %d, updated %d", added, updated)
	if removed > 0 then
		summary = summary .. string.format(", removed %d", removed)
	end
	summary = summary .. "."
	if which == "guild" and added + updated + removed > 0 then
		summary = summary .. " Shared with your guild automatically."
	end
	return summary
end

local function Import()
	local editBox = frame.input:GetEditBox()
	local added, updated, skipped, removed, note = ns.ImportEntries(target, editBox:GetText())
	if not added then
		SetStatus(updated, RED_FONT_COLOR)
		return
	end
	local summary = ns.ImportSummary(target, added, updated, removed)
	-- Longer details go to chat, because the status line has room for one line.
	if note then
		ns.Print(note)
	end
	if #skipped > 0 then
		SetStatus(summary .. " Some lines were skipped; see chat.", RED_FONT_COLOR)
		ns.Print(ns.SkippedText(skipped))
	elseif note then
		SetStatus(summary .. " See chat.", NORMAL_FONT_COLOR)
	else
		SetStatus(summary, GREEN_FONT_COLOR)
		editBox:SetText("")
	end
end

local function CreateTransfer()
	frame = CreateFrame("Frame", "BeaconTransferFrame", UIParent, "ButtonFrameTemplate")
	frame:SetSize(480, 400)
	frame:SetPoint("CENTER", 40, -20)
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:SetFrameStrata("DIALOG")
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetPortraitToAsset(ns.LOGO)
	frame:Hide()
	table.insert(UISpecialFrames, "BeaconTransferFrame")

	frame.help = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.help:SetPoint("TOPLEFT", 70, -32)
	frame.help:SetPoint("RIGHT", -12, 0)
	frame.help:SetJustifyH("LEFT")

	local inset = frame.Inset
	frame.input = CreateFrame("Frame", nil, inset, "ScrollingEditBoxTemplate")
	frame.input:SetPoint("TOPLEFT", 8, -8)
	frame.input:SetPoint("BOTTOMRIGHT", -26, 8)
	local scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", frame.input, "TOPRIGHT", 6, 0)
	scrollBar:SetPoint("BOTTOMLEFT", frame.input, "BOTTOMRIGHT", 6, 0)
	ScrollUtil.RegisterScrollBoxWithScrollBar(frame.input:GetScrollBox(), scrollBar)
	local editBox = frame.input:GetEditBox()
	editBox:SetFontObject(ChatFontNormal)
	editBox:SetMaxLetters(0)

	frame.status = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	frame.status:SetPoint("BOTTOMLEFT", 16, 9)
	frame.status:SetPoint("RIGHT", -110, 0)
	frame.status:SetJustifyH("LEFT")
	frame.status:SetWordWrap(false)

	frame.importButton = ns.CreateButton(frame, "Import", 96, Import)
	frame.importButton:SetPoint("BOTTOMRIGHT", -6, 4)
end

-- Opens the window. mode is "import" or "export"; which is "guild" or "personal".
function ns.OpenTransfer(mode, which)
	if not frame then
		CreateTransfer()
	end
	target = which
	local editBox = frame.input:GetEditBox()
	frame.status:SetText("")
	frame.importButton:SetShown(mode == "import")
	if mode == "import" then
		frame:SetTitle("Import into your " .. LIST_NAMES[which])
		frame.help:SetText(IMPORT_HELP)
		editBox:SetText("")
	else
		frame:SetTitle("Export your " .. LIST_NAMES[which])
		frame.help:SetText(EXPORT_HELP)
		editBox:SetText(ns.ExportEntries(which))
	end
	frame:Show()
	editBox:SetFocus()
	if mode == "export" then
		editBox:HighlightText()
	end
end
