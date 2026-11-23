local _, ns = ...

---------------------------------------------------------------------------
-- Mass import
-- A window where the player pastes many aliases at once, one per line, into
-- the list they are viewing: the personal list for anyone, the guild list for
-- officers. Existing aliases are updated and the rest are added.
-- Events: none
-- SavedVariables: none (changes go through ns.ImportEntries)
---------------------------------------------------------------------------
local LIST_NAMES = { guild = "guild list", personal = "personal list" }
local MAX_SKIPPED_SHOWN = 10

local frame
local target -- list receiving the import: "guild" or "personal"

local function SetStatus(text, color)
	frame.status:SetText(text)
	frame.status:SetTextColor(color:GetRGB())
end

-- Describes skipped line numbers, listing at most MAX_SKIPPED_SHOWN of them.
local function SkippedText(skipped)
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

local function Import()
	local editBox = frame.input:GetEditBox()
	local added, updated, skipped = ns.ImportEntries(target, editBox:GetText())
	if not added then
		SetStatus(updated, RED_FONT_COLOR)
		return
	end
	local summary = string.format("Added %d, updated %d.", added, updated)
	if target == "guild" and added + updated > 0 then
		summary = summary .. " Choose Send to Guild to share them."
	end
	if #skipped > 0 then
		-- The full list of skipped lines can be long, so it goes to chat.
		SetStatus(summary .. " Some lines were skipped; see chat.", RED_FONT_COLOR)
		ns.Print(SkippedText(skipped))
	else
		SetStatus(summary, GREEN_FONT_COLOR)
		editBox:SetText("")
	end
end

local function CreateImport()
	frame = CreateFrame("Frame", "BeaconImportFrame", UIParent, "ButtonFrameTemplate")
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
	table.insert(UISpecialFrames, "BeaconImportFrame")

	local help = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", 70, -32)
	help:SetPoint("RIGHT", -12, 0)
	help:SetJustifyH("LEFT")
	help:SetText("One per line: alias, Role or Person, Discord ID, display name (optional).\n"
		.. GRAY_FONT_COLOR:WrapTextInColorCode("Example: raid, Role, 123456789012345678, Raid Team"))

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

	local importButton = ns.CreateButton(frame, "Import", 96, Import)
	importButton:SetPoint("BOTTOMRIGHT", -6, 4)
end

-- Opens the import window for which ("guild" or "personal").
function ns.OpenImport(which)
	if not frame then
		CreateImport()
	end
	target = which
	frame:SetTitle("Import into your " .. LIST_NAMES[which])
	frame.status:SetText("")
	frame:Show()
	frame.input:GetEditBox():SetFocus()
end
