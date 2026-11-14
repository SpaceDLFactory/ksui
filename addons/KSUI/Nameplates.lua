-- Flat nameplate health bars with a thin black border and no level box, matching KSUI's unit frames. Blizzard keeps
-- some nameplates (friendly ones in instances) out of addons' reach; those keep Blizzard's look. Blizzard restyles a
-- plate in UpdateAnchors, from Blizzard_NamePlates/Blizzard_NamePlateUnitFrame.lua, so KSUI's look goes back on after.

local _, ns = ...

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local BORDER = 1

local hooked = {}

local function restyle(unitFrame)
	if not ns.db.flatNameplates then
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
