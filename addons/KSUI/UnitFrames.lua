-- Square player, target and focus frames with a moving portrait, drawn over Blizzard's. Blizzard's secure frames stay
-- underneath with only their art, bars and portrait faded out, so clicks, menus, Edit Mode positions, target auras,
-- the threat number and the icons beside the frame keep working. Ours are children of theirs, so they show and hide
-- with the unit. Health, power and names can be secret in instances, so they only go to setters that accept secrets.

local _, ns = ...

-- Fits inside Blizzard's 232 x 100 frame, which stays the click area.
local WIDTH, HEIGHT = 224, 56
local POWER_HEIGHT = 12
local GAP = 2
local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local HEALTH_GREEN = { 0.1, 0.8, 0.1 }

local frames = {}

-- White with a black outline reads on any bar color, including a secret one.
local function outlinedText(bar)
	local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	local font, size = text:GetFont()
	text:SetFont(font, size, "OUTLINE")
	return text
end

local function statusBar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(FLAT)
	bar.background = bar:CreateTexture(nil, "BACKGROUND")
	bar.background:SetAllPoints()
	bar.background:SetColorTexture(0, 0, 0, 0.5)
	bar.value = outlinedText(bar)
	return bar
end

-- The portrait sits on the outer side: left for you, right for the target and focus.
local function build(blizzard, unit, portraitRight)
	local frame = CreateFrame("Frame", nil, blizzard, "BackdropTemplate")
	frame.unit = unit
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
	frame:SetBackdropColor(0, 0, 0, 0.6)
	frame:SetBackdropBorderColor(0, 0, 0, 1)

	local near, far = "LEFT", "RIGHT"
	local inward = 1
	if portraitRight then
		near, far, inward = "RIGHT", "LEFT", -1
	end

	local size = HEIGHT - 2
	frame.portrait = CreateFrame("Frame", nil, frame)
	frame.portrait:SetSize(size, size)
	frame.portrait:SetPoint("TOP" .. near, inward, -1)
	frame.model = CreateFrame("PlayerModel", nil, frame.portrait)
	frame.model:SetAllPoints()
	frame.picture = frame.portrait:CreateTexture(nil, "ARTWORK")
	frame.picture:SetAllPoints()

	frame.health = statusBar(frame)
	frame.health:SetPoint("TOP" .. near, frame.portrait, "TOP" .. far, GAP * inward, 0)
	frame.health:SetPoint("BOTTOM" .. far, frame, "BOTTOM" .. far, -inward, POWER_HEIGHT + GAP + 1)
	frame.health.name = outlinedText(frame.health)
	frame.health.name:SetPoint("TOP" .. near, 4 * inward, -4)
	frame.health.value:SetPoint("BOTTOM" .. far, -4 * inward, 4)

	frame.power = statusBar(frame)
	frame.power:SetPoint("TOP" .. near, frame.health, "BOTTOM" .. near, 0, -GAP)
	frame.power:SetPoint("BOTTOM" .. far, frame, "BOTTOM" .. far, -inward, 1)
	frame.power.value:SetPoint(far, -4 * inward, 0)

	frames[#frames + 1] = frame
	return frame
end

local function updateHealth(frame)
	local unit = frame.unit
	local health = UnitHealth(unit)
	frame.health:SetMinMaxValues(0, UnitHealthMax(unit))
	frame.health:SetValue(health)
	if ns.db.healthPercent then
		frame.health.value:SetFormattedText("%s  %.0f%%", AbbreviateNumbers(health),
			UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))
	else
		frame.health.value:SetText(AbbreviateNumbers(health))
	end
end

local function updatePower(frame)
	local unit = frame.unit
	local power = UnitPower(unit)
	frame.power:SetMinMaxValues(0, UnitPowerMax(unit))
	frame.power:SetValue(power)
	frame.power.value:SetText(AbbreviateNumbers(power))
	local _, token = UnitPowerType(unit)
	local color = not issecretvalue(token) and token and PowerBarColor[token] or PowerBarColor.MANA
	frame.power:SetStatusBarColor(color.r, color.g, color.b)
end

local function updateColor(frame)
	if ns.db.classColorBars then
		frame.health:SetStatusBarColor(ns.UnitColor(frame.unit))
	else
		frame.health:SetStatusBarColor(HEALTH_GREEN[1], HEALTH_GREEN[2], HEALTH_GREEN[3])
	end
end

local function updateName(frame)
	local unit = frame.unit
	local level = UnitLevel(unit)
	-- Bosses and units far above you report -1.
	if not issecretvalue(level) and level < 0 then
		level = "??"
	end
	-- Forever names carry a surname, joined the way Blizzard_FrameXMLUtil/Camelot/NameUtil.lua does.
	local name, surname = UnitName(unit)
	if issecretvalue(surname) or surname then
		frame.health.name:SetFormattedText("%s  %s%s%s", level, name,
			Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR, surname)
	else
		frame.health.name:SetFormattedText("%s  %s", level, name)
	end
end

-- A model needs the unit nearby and its identity readable; otherwise the still picture stands in.
local function updatePortrait(frame)
	local unit = frame.unit
	local moving = ns.db.animatedPortraits and not C_Secrets.ShouldUnitIdentityBeSecret(unit) and UnitIsVisible(unit)
	frame.model:SetShown(moving)
	frame.picture:SetShown(not moving)
	if moving then
		frame.model:ClearModel()
		frame.model:SetUnit(unit)
		frame.model:SetPortraitZoom(1)
		frame.model:SetPosition(0, 0, 0)
	else
		SetPortraitTexture(frame.picture, unit, true)
	end
end

local function updateAll(frame)
	if not UnitExists(frame.unit) then
		return
	end
	updateHealth(frame)
	updatePower(frame)
	updateColor(frame)
	updateName(frame)
	updatePortrait(frame)
end

local UPDATES = {
	UNIT_HEALTH = updateHealth, UNIT_MAXHEALTH = updateHealth,
	UNIT_POWER_UPDATE = updatePower, UNIT_MAXPOWER = updatePower, UNIT_DISPLAYPOWER = updatePower,
	UNIT_NAME_UPDATE = updateName, UNIT_LEVEL = updateName, PLAYER_LEVEL_CHANGED = updateName,
	UNIT_FACTION = updateColor,
	UNIT_MODEL_CHANGED = updatePortrait, UNIT_PORTRAIT_UPDATE = updatePortrait, PORTRAITS_UPDATED = updatePortrait,
}
-- Registered by hand: these two are not unit events.
local GLOBAL_EVENTS = { PLAYER_LEVEL_CHANGED = true, PORTRAITS_UPDATED = true }

local function listen(frame, unitChanged)
	local events = CreateFrame("Frame")
	for event in pairs(UPDATES) do
		if not GLOBAL_EVENTS[event] then
			events:RegisterUnitEvent(event, frame.unit)
		end
	end
	events:RegisterUnitEvent("UNIT_CONNECTION", frame.unit)
	if unitChanged then
		events:RegisterEvent(unitChanged)
	end
	-- Blizzard_UnitFrame/Mainline/UnitFrame.lua redraws every portrait on this one.
	events:RegisterEvent("PORTRAITS_UPDATED")
	events:SetScript("OnEvent", function(_, event)
		if ns.db.customUnitFrames and UnitExists(frame.unit) then
			(UPDATES[event] or updateAll)(frame)
		end
	end)
	return events
end

local function blizzardParts()
	return {
		PlayerFrame.PlayerFrameContainer, PlayerFrame.PlayerFrameContent.PlayerFrameContentMain,
		TargetFrame.TargetFrameContainer, TargetFrame.TargetFrameContent.TargetFrameContentMain,
		FocusFrame.TargetFrameContainer, FocusFrame.TargetFrameContent.TargetFrameContentMain,
	}
end

function ns.InitUnitFrames()
	-- Your model may not be loaded yet at login.
	-- UNIT_LEVEL does not cover your own level; Blizzard_UnitFrame/Mainline/PlayerFrame.lua listens to this instead.
	listen(build(PlayerFrame, "player", false), "PLAYER_ENTERING_WORLD"):RegisterEvent("PLAYER_LEVEL_CHANGED")
	listen(build(TargetFrame, "target", true), "PLAYER_TARGET_CHANGED")
	listen(build(FocusFrame, "focus", true), "PLAYER_FOCUS_CHANGED")
end

function ns.RefreshUnitFrames()
	local custom = ns.db.customUnitFrames
	for _, part in ipairs(blizzardParts()) do
		part:SetAlpha(custom and 0 or 1)
	end
	for _, frame in ipairs(frames) do
		frame:SetShown(custom)
		if custom then
			updateAll(frame)
		end
	end
end

-- Blizzard's bar text follows the same option, so both change together.
function ns.RefreshHealthPercent()
	ns.RefreshCVars()
	ns.RefreshUnitFrames()
end
