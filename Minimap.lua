local _, ns = ...

---------------------------------------------------------------------------
-- Minimap button
-- A round button with the Beacon logo in the standard minimap tracking
-- border. Click opens the lists window; drag moves it around the minimap.
-- /beacon minimap shows or hides it.
-- Events: PLAYER_LOGIN
-- SavedVariables: BeaconDB.minimap.angle (degrees), BeaconDB.minimap.hide
---------------------------------------------------------------------------
local button

-- Places the button on the minimap's edge at the saved angle.
local function Place()
	local angle = math.rad(BeaconDB.minimap.angle)
	local radius = Minimap:GetWidth() / 2 + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- While dragging, follows the cursor around the minimap's edge.
local function OnDragUpdate()
	local centerX, centerY = Minimap:GetCenter()
	local cursorX, cursorY = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	BeaconDB.minimap.angle = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX))
	Place()
end

local function CreateMinimapButton()
	button = CreateFrame("Button", nil, Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetSize(24, 24)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetPoint("CENTER")
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetTexture(ns.LOGO)
	icon:SetPoint("CENTER")
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(50, 50)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function()
		ns.ToggleManager()
	end)
	button:SetScript("OnDragStart", function(self)
		self:LockHighlight()
		self:SetScript("OnUpdate", OnDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self)
		self:UnlockHighlight()
		self:SetScript("OnUpdate", nil)
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Beacon")
		GameTooltip:AddLine("Click to open your mention lists.", HIGHLIGHT_FONT_COLOR:GetRGB())
		GameTooltip:AddLine("Drag to move this button.", GRAY_FONT_COLOR:GetRGB())
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)

	Place()
	button:SetShown(not BeaconDB.minimap.hide)
end

function ns.ToggleMinimapButton()
	BeaconDB.minimap.hide = not BeaconDB.minimap.hide
	button:SetShown(not BeaconDB.minimap.hide)
	ns.Print(BeaconDB.minimap.hide and "Minimap button hidden. Type /beacon minimap to show it again."
		or "Minimap button shown.")
end

ns.On("PLAYER_LOGIN", CreateMinimapButton)
