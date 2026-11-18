-- Flat nameplate health bars with a thin black border, matching KSUI's unit frames. Blizzard's level box only shows
-- when the level gap matters, so it goes and the level is written at the bar's right end instead. Blizzard keeps
-- some nameplates (friendly ones in instances) out of addons' reach; those keep Blizzard's look. Blizzard restyles a
-- plate in UpdateAnchors, from Blizzard_NamePlates/Blizzard_NamePlateUnitFrame.lua, so KSUI's look goes back on after.

local _, ns = ...

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local BORDER = 1
-- Blizzard_NamePlates/Camelot/Blizzard_NamePlateLevelFrame.xml marks bosses with this skull.
local SKULL = "ui-hud-nameplates-levelindicator-skull"
local SKULL_SIZE = 12

local hooked = {}

local function restyle(unitFrame)
	if not ns.db.flatNameplates then
		if unitFrame.ksuiLevel then
			unitFrame.ksuiLevel:Hide()
			unitFrame.ksuiSkull:Hide()
		end
		return
	end
	local bar = unitFrame.HealthBarsContainer.healthBar
	bar.barTexture:SetTexture(FLAT)
	-- Blizzard's background doubles as the border art; a black box one pixel larger than the bar replaces it.
	local border = bar.bgTexture
	border:SetTexture(FLAT)
	border:SetTexCoord(0, 1, 0, 1)
	border:SetVertexColor(0, 0, 0, 1)
	border:SetDrawLayer("BACKGROUND")
	border:ClearAllPoints()
	border:SetPoint("TOPLEFT", bar, "TOPLEFT", -BORDER, BORDER)
	border:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", BORDER, -BORDER)
	unitFrame.PlayerLevelDiffFrame:SetAlpha(0)

	if not unitFrame.ksuiLevel then
		unitFrame.ksuiLevel = ns.OutlinedText(bar)
		unitFrame.ksuiLevel:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
		unitFrame.ksuiSkull = bar:CreateTexture(nil, "OVERLAY")
		unitFrame.ksuiSkull:SetAtlas(SKULL)
		unitFrame.ksuiSkull:SetSize(SKULL_SIZE, SKULL_SIZE)
		unitFrame.ksuiSkull:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
	end
	-- The level can be secret in instances; then it is shown as is, in white.
	local level = UnitLevel(unitFrame.unit)
	-- Bosses and units far above you report -1 and get the skull instead.
	local skull = not issecretvalue(level) and level < 0
	unitFrame.ksuiSkull:SetShown(skull)
	unitFrame.ksuiLevel:SetShown(not skull)
	if issecretvalue(level) then
		unitFrame.ksuiLevel:SetText(level)
		unitFrame.ksuiLevel:SetTextColor(1, 1, 1)
	elseif not skull then
		unitFrame.ksuiLevel:SetText(level)
		local color = GetCreatureDifficultyColor(level)
		unitFrame.ksuiLevel:SetTextColor(color.r, color.g, color.b)
	end
end

local function onPlateAdded(_, unit)
	-- Without includeForbidden this returns nothing for plates addons may not touch.
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	local unitFrame = plate and plate.UnitFrame
	if not unitFrame then
		return
	end
	if not hooked[unitFrame] then
		hooksecurefunc(unitFrame, "UpdateAnchors", restyle)
		hooked[unitFrame] = true
	end
	restyle(unitFrame)
end

function ns.InitNameplates()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_NamePlates", function()
		hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", onPlateAdded)
	end)
end
