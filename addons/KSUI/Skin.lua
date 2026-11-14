-- Recolors Blizzard's own frames, so buffs, cast bars and Edit Mode positions keep working.
-- Only UnitClass can be secret here (identity-restricted units), and it is guarded below.

local _, ns = ...

local UNKNOWN_CLASS = { 0.6, 0.6, 0.6 }
local ICON_CROP = 0.07

local unitTextures, partyTextures, actionTextures, icons = {}, {}, {}, {}
local healthBars = {}

local function tint(texture, enabled, r, g, b)
	texture:SetDesaturated(enabled)
	if enabled then
		texture:SetVertexColor(r, g, b)
	else
		texture:SetVertexColor(1, 1, 1)
	end
end

local function unitColor(unit)
	if not UnitIsPlayer(unit) then
		return UnitSelectionColor(unit)
	end
	local _, class = UnitClass(unit)
	-- A secret class cannot be used as a table key, so it falls back to gray.
	local color = not issecretvalue(class) and class and RAID_CLASS_COLORS[class] or nil
	if color then
		return color.r, color.g, color.b
	end
	return UNKNOWN_CLASS[1], UNKNOWN_CLASS[2], UNKNOWN_CLASS[3]
end

-- Blizzard can recolor these bars itself, so the color is reapplied after every SetStatusBarColor.
local function classColorBar(bar, unit)
	local applying = false
	local entry = {}

	function entry.apply()
		if applying or not ns.db.classColorBars or not UnitExists(unit) then
			return
		end
		local r, g, b = unitColor(unit)
		applying = true
		bar:SetStatusBarDesaturated(true)
		bar:SetStatusBarColor(r, g, b)
		applying = false
	end

	function entry.reset()
		bar:SetStatusBarDesaturated(false)
		bar:SetStatusBarColor(1, 1, 1)
	end

	hooksecurefunc(bar, "SetStatusBarColor", entry.apply)
	return entry
end

local function collectPartyTextures()
	partyTextures = {}
	for frame in PartyFrame.PartyMemberFramePool:EnumerateActive() do
		partyTextures[#partyTextures + 1] = frame.Texture
	end
end

function ns.InitSkin()
	local player = PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
	local target = TargetFrame.TargetFrameContent.TargetFrameContentMain

	unitTextures[1] = PlayerFrame.PlayerFrameContainer.FrameTexture
	unitTextures[2] = TargetFrame.TargetFrameContainer.FrameTexture
	unitTextures[3] = FocusFrame.TargetFrameContainer.FrameTexture
	unitTextures[4] = PlayerFrame.PlayerFrameContainer.VehicleFrameTexture
	unitTextures[5] = PlayerFrame.PlayerFrameContainer.AlternatePowerFrameTexture
	for i = 1, MAX_BOSS_FRAMES do
		unitTextures[#unitTextures + 1] = _G["Boss" .. i .. "TargetFrame"].TargetFrameContainer.FrameTexture
	end
	-- Party frames are created the first time the party UI is shown, which can be after login.
	hooksecurefunc(PartyFrame, "InitializePartyMemberFrames", function()
		collectPartyTextures()
		ns.RefreshSkin()
	end)
	collectPartyTextures()
	actionTextures[1] = MainActionBar.EndCaps.LeftEndCap.Texture
	actionTextures[2] = MainActionBar.EndCaps.RightEndCap.Texture

	ns.ForEachActionButton(function(button)
		actionTextures[#actionTextures + 1] = button.NormalTexture
		actionTextures[#actionTextures + 1] = button.SlotArt
		actionTextures[#actionTextures + 1] = button.SlotBackground
		icons[#icons + 1] = button.icon
	end)

	healthBars.player = classColorBar(player.HealthBarsContainer.HealthBar, "player")
	healthBars.target = classColorBar(target.HealthBarsContainer.HealthBar, "target")
end

function ns.RefreshSkin()
	local db = ns.db
	local r, g, b = CreateColorFromHexString(db.artColor):GetRGB()

	for _, texture in ipairs(unitTextures) do
		tint(texture, db.darkUnitFrames, r, g, b)
	end
	for _, texture in ipairs(partyTextures) do
		tint(texture, db.darkUnitFrames, r, g, b)
	end
	for _, texture in ipairs(actionTextures) do
		tint(texture, db.darkActionBars, r, g, b)
	end

	local crop = db.cropIcons and ICON_CROP or 0
	for _, icon in ipairs(icons) do
		icon:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
	end

	for _, entry in pairs(healthBars) do
		if db.classColorBars then
			entry.apply()
		else
			entry.reset()
		end
	end
end

-- Blizzard_Minimap/Camelot/Minimap.lua uses the same mask for both rotation modes. The hybrid minimap used in
-- some zones has its own round mask.
local ROUND_MASK = "ui-hud-minimap-frame-generic-mask"
local HYBRID_ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- A plain white texture that Blizzard's chat frames use, so it is known to exist in Forever.
local SQUARE_MASK = "Interface\\ChatFrame\\ChatFrameBackground"
local MINIMAP_BORDER = 2

local minimapBorder

function ns.RefreshMinimap()
	local square = ns.db.squareMinimap
	Minimap:SetMaskTexture(square and SQUARE_MASK or ROUND_MASK)
	MinimapCompassTexture:SetShown(not square)
	-- Blizzard shows the underlay only while the minimap rotates.
	MinimapCompassTextureUnderlay:SetShown(not square and GetCVarBool("rotateMinimap"))
	minimapBorder:SetShown(square)
	if HybridMinimap then
		HybridMinimap.CircleMask:SetTexture(square and SQUARE_MASK or HYBRID_ROUND_MASK,
			"CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	end
end

function ns.InitMinimap()
	minimapBorder = CreateFrame("Frame", nil, Minimap, "BackdropTemplate")
	minimapBorder:SetPoint("TOPLEFT", -MINIMAP_BORDER, MINIMAP_BORDER)
	minimapBorder:SetPoint("BOTTOMRIGHT", MINIMAP_BORDER, -MINIMAP_BORDER)
	minimapBorder:SetBackdrop({ edgeFile = SQUARE_MASK, edgeSize = MINIMAP_BORDER })
	minimapBorder:SetBackdropBorderColor(0, 0, 0, 1)
	-- Toggling rotation makes Blizzard put the round mask and frame back.
	hooksecurefunc(MinimapCluster, "UpdateMinimapConfig", function()
		if ns.db.squareMinimap then
			ns.RefreshMinimap()
		end
	end)
	EventUtil.ContinueOnAddOnLoaded("Blizzard_HybridMinimap", ns.RefreshMinimap)
	-- Minimap button libraries ask this to place their buttons on the edge.
	function GetMinimapShape()
		return ns.db.squareMinimap and "SQUARE" or "ROUND"
	end
	ns.RefreshMinimap()
end

-- Raid frames and the target threat number stay Blizzard's, which keep working with secret values in instances.
function ns.RefreshCVars()
	-- A change made during combat is applied on PLAYER_REGEN_ENABLED.
	if not InCombatLockdown() then
		SetCVar("raidFramesDisplayClassColor", ns.db.raidClassColors and "1" or "0")
		SetCVar("raidFramesDisplayOnlyDispellableDebuffs", ns.db.dispellableOnly and "1" or "0")
		SetCVar("threatShowNumeric", ns.db.threatNumbers and "1" or "0")
		-- Blizzard's own bar text, so it keeps working when health is secret in instances.
		SetCVar("cooldownViewerEnabled", ns.db.cooldownManager and "1" or "0")
		SetCVar("statusTextDisplay", ns.db.healthPercent and "BOTH" or "NUMERIC")
		if ns.db.healthPercent then
			SetCVar("statusText", "1")
		end
		-- Each is only a filter on top of a Blizzard switch, so the switch is turned on with it.
		if ns.db.dispellableOnly then
			SetCVar("raidFramesDisplayDebuffs", "1")
		end
		if ns.db.threatNumbers then
			SetCVar("threatWarning", "3")
		end
	end
end

function ns.RefreshTargetColor()
	if healthBars.target then
		healthBars.target.apply()
	end
end
