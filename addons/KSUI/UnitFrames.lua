-- Square player, target, focus and party frames with a moving portrait, drawn over Blizzard's. Blizzard's secure frames stay
-- underneath with only their art, bars and portrait faded out, so clicks, menus, Edit Mode positions, target auras,
-- the threat number and the icons beside the frame keep working. Ours are children of theirs, so they show and hide
-- with the unit. Health, power and names can be secret in instances, so they only go to setters that accept secrets.

local _, ns = ...

-- Each fits inside Blizzard's frame (232 x 100, party 120 x 53), which stays the click area.
local WIDTH, HEIGHT = 224, 56
-- Party frames get the full height so the name and the health number don't overlap, and run past Blizzard's
-- 120-wide frame to the right so the bars have room.
local PARTY_WIDTH, PARTY_HEIGHT = 200, 52
local POWER_HEIGHT = 12
local GAP = 2
local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local HEALTH_GREEN = { 0.1, 0.8, 0.1 }
-- Shields as a pale blue stretch past the health, like Blizzard's raid frames.
local ABSORB_COLOR = { 0.55, 0.85, 1, 0.7 }
-- Turns a power share into the power number's alpha: hidden at nothing, shown at anything more. Going through a curve
-- works when the power is secret, which it is for many units outside your group.
local POWER_TEXT_ALPHA = C_CurveUtil.CreateCurve()
POWER_TEXT_ALPHA:SetType(Enum.LuaCurveType.Step)
POWER_TEXT_ALPHA:AddPoint(0, 0)
POWER_TEXT_ALPHA:AddPoint(0.001, 1)

local frames = {}

-- White with a black outline reads on any bar color, including a secret one.
local function outlinedText(bar)
	local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	local font, size = text:GetFont()
	text:SetFont(font, size, "OUTLINE")
	return text
end
ns.OutlinedText = outlinedText

local function statusBar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(FLAT)
	bar.background = bar:CreateTexture(nil, "BACKGROUND")
	bar.background:SetAllPoints()
	bar.background:SetColorTexture(0, 0, 0, 0.5)
	bar.value = outlinedText(bar)
	return bar
end

-- The portrait sits on the outer side: left for you and the party, right for the target and focus.
-- parts are Blizzard's art, bars and text that ours replaces.
local function build(blizzard, unit, portraitRight, width, height, parts)
	local frame = CreateFrame("Frame", nil, blizzard, "BackdropTemplate")
	frame.unit = unit
	frame.blizzardParts = parts
	frame:SetSize(width, height)
	frame:SetPoint("CENTER")
	frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
	frame:SetBackdropColor(0, 0, 0, 0.6)
	frame:SetBackdropBorderColor(0, 0, 0, 1)

	local near, far = "LEFT", "RIGHT"
	local inward = 1
	if portraitRight then
		near, far, inward = "RIGHT", "LEFT", -1
	end

	local size = height - 2
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
	-- Anchored at both ends so a long name is cut short instead of running past the bar.
	frame.health.name:SetPoint("TOP" .. near, 4 * inward, -4)
	frame.health.name:SetPoint("TOP" .. far, -4 * inward, -4)
	frame.health.name:SetJustifyH(near)
	frame.health.name:SetWordWrap(false)
	frame.health.value:SetPoint("BOTTOM" .. far, -4 * inward, 4)

	-- Absorbs can be secret, so their length can't be worked out here. The bar instead starts where the health fill
	-- ends and is as wide as the health bar on the same scale, so the client draws the right length; whatever runs
	-- past a full bar is clipped.
	frame.health:SetClipsChildren(true)
	frame.absorb = CreateFrame("StatusBar", nil, frame.health)
	frame.absorb:SetStatusBarTexture(FLAT)
	frame.absorb:SetStatusBarColor(ABSORB_COLOR[1], ABSORB_COLOR[2], ABSORB_COLOR[3], ABSORB_COLOR[4])
	local fill = frame.health:GetStatusBarTexture()
	frame.absorb:SetPoint("TOPLEFT", fill, "TOPRIGHT")
	frame.absorb:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT")
	frame.health:SetScript("OnSizeChanged", function(_, width)
		frame.absorb:SetWidth(width)
	end)
	frame.health.absorbValue = outlinedText(frame.health)
	frame.health.absorbValue:SetPoint("BOTTOM" .. far, frame.health.value, "BOTTOM" .. near, -6 * inward, 0)
	frame.health.absorbValue:SetTextColor(ABSORB_COLOR[1], ABSORB_COLOR[2], ABSORB_COLOR[3])
	-- The shield bar is a child frame, so it would draw over the bar's text; the text moves to a frame above it.
	local texts = CreateFrame("Frame", nil, frame.health)
	texts:SetAllPoints()
	texts:SetFrameLevel(frame.absorb:GetFrameLevel() + 1)
	for _, text in ipairs({ frame.health.name, frame.health.value, frame.health.absorbValue }) do
		text:SetParent(texts)
	end

	frame.power = statusBar(frame)
	frame.power:SetPoint("TOP" .. near, frame.health, "BOTTOM" .. near, 0, -GAP)
	frame.power:SetPoint("BOTTOM" .. far, frame, "BOTTOM" .. far, -inward, 1)
	frame.power.value:SetPoint(far, -4 * inward, 0)

	frames[#frames + 1] = frame
	return frame
end

local function updateAbsorb(frame)
	local unit = frame.unit
	local absorb = UnitGetTotalAbsorbs(unit)
	frame.absorb:SetMinMaxValues(0, UnitHealthMax(unit))
	frame.absorb:SetValue(absorb)
	-- A secret amount can't be checked for zero, so only the bar shows it then.
	local readable = not issecretvalue(absorb) and absorb > 0
	frame.health.absorbValue:SetShown(readable)
	if readable then
		frame.health.absorbValue:SetFormattedText("+%s", AbbreviateNumbers(absorb))
	end
end

local function updateHealth(frame)
	local unit = frame.unit
	local health = UnitHealth(unit)
	frame.health:SetMinMaxValues(0, UnitHealthMax(unit))
	frame.health:SetValue(health)
	updateAbsorb(frame)
	if ns.db.healthPercent then
		frame.health.value:SetFormattedText("%s  %.0f%%", AbbreviateNumbers(health),
			UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))
	else
		frame.health.value:SetText(AbbreviateNumbers(health))
	end
end

local function updatePower(frame)
	local unit = frame.unit
	local power, maxPower = UnitPower(unit), UnitPowerMax(unit)
	frame.power:SetMinMaxValues(0, maxPower)
	frame.power:SetValue(power)
	frame.power.value:SetText(AbbreviateNumbers(power))
	-- An empty bar needs no "0": beasts with no power at all, and rage or energy that has not built up yet.
	frame.power.value:SetAlpha(UnitPowerPercent(unit, nil, false, POWER_TEXT_ALPHA))
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
	UNIT_HEALTH = updateHealth, UNIT_MAXHEALTH = updateHealth, UNIT_ABSORB_AMOUNT_CHANGED = updateAbsorb,
	UNIT_POWER_UPDATE = updatePower, UNIT_MAXPOWER = updatePower, UNIT_DISPLAYPOWER = updatePower,
	UNIT_NAME_UPDATE = updateName, UNIT_LEVEL = updateName, PLAYER_LEVEL_CHANGED = updateName,
	UNIT_FACTION = updateColor,
	UNIT_MODEL_CHANGED = updatePortrait, UNIT_PORTRAIT_UPDATE = updatePortrait, PORTRAITS_UPDATED = updatePortrait,
}
-- Registered by hand: these two are not unit events.
local GLOBAL_EVENTS = { PLAYER_LEVEL_CHANGED = true, PORTRAITS_UPDATED = true }

-- Registering again replaces the unit, for party frames that Blizzard hands a new one.
local function setUnit(frame, unit)
	frame.unit = unit
	for event in pairs(UPDATES) do
		if not GLOBAL_EVENTS[event] then
			frame.events:RegisterUnitEvent(event, unit)
		end
	end
	frame.events:RegisterUnitEvent("UNIT_CONNECTION", unit)
end

local function listen(frame, unitChanged)
	local events = CreateFrame("Frame")
	frame.events = events
	setUnit(frame, frame.unit)
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

local function targetParts(blizzard)
	return { blizzard.TargetFrameContainer, blizzard.TargetFrameContent.TargetFrameContentMain }
end

local partyFrames = {}

-- Blizzard pulses the portrait's alpha on a member in trouble, so it is put back to zero after each change.
local function keepPortraitHidden(portrait)
	if ns.db.customUnitFrames and portrait:GetAlpha() ~= 0 then
		portrait:SetAlpha(0)
	end
end

-- Party frames come from a pool that Blizzard fills again whenever it rebuilds them, possibly after login.
-- The part past Blizzard's frame gets its own secure button, so clicking anywhere on the bars still targets the
-- member and right-click opens the menu. It hangs off Blizzard's button rather than ours, so ours never becomes a
-- protected parent. Secure buttons can't be changed in combat, so that waits for it to end.
local function updateClicker(frame)
	if InCombatLockdown() then
		return
	end
	if not frame.clicker then
		local member = frame:GetParent()
		local clicker = CreateFrame("Button", nil, member, "SecureUnitButtonTemplate")
		clicker:SetPoint("TOPLEFT", member, "TOPRIGHT")
		clicker:SetPoint("BOTTOMLEFT", member, "BOTTOMRIGHT")
		clicker:SetWidth(PARTY_WIDTH - member:GetWidth())
		clicker:RegisterForClicks("AnyUp")
		clicker:SetAttribute("type1", "target")
		clicker:SetAttribute("type2", "togglemenu")
		frame.clicker = clicker
	end
	frame.clicker:SetAttribute("unit", frame.unit)
	frame.clicker:SetShown(ns.db.customUnitFrames)
end

local function attachPartyFrames()
	for member in PartyFrame.PartyMemberFramePool:EnumerateActive() do
		local frame = partyFrames[member]
		if not frame then
			frame = build(member, member.unitToken, false, PARTY_WIDTH, PARTY_HEIGHT, {
				member.Texture, member.VehicleTexture, member.Flash, member.Portrait, member.Name,
				member.HealthBarContainer, member.ManaBar,
			})
			-- Grows to the right from Blizzard's frame instead of from its middle.
			frame:ClearAllPoints()
			frame:SetPoint("LEFT")
			listen(frame, "GROUP_ROSTER_UPDATE")
			hooksecurefunc(member.Portrait, "SetAlpha", keepPortraitHidden)
			partyFrames[member] = frame
		end
		setUnit(frame, member.unitToken)
		updateClicker(frame)
	end
end

-- Blizzard hangs target auras under its own art, which sits lower and further left than ours, so they would start off
-- our left edge and cover the power bar. They go right under ours instead, or right above when buffs go on top.
local AURAS_GAP = 3

local function placeAuras(blizzard, frame)
	local auras = blizzard:GetAuraContainer()
	if not ns.db.customUnitFrames or (InCombatLockdown() and auras:IsProtected()) then
		return
	end
	auras:ClearAllPoints()
	if auras:IsFlowLayoutMirroredVertically() then
		auras:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, AURAS_GAP)
	else
		auras:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -AURAS_GAP)
	end
end

local function followAuras(blizzard, frame)
	hooksecurefunc(blizzard, "AnchorAuraContainer", function()
		placeAuras(blizzard, frame)
	end)
	placeAuras(blizzard, frame)
end

function ns.InitUnitFrames()
	-- Your model may not be loaded yet at login.
	-- UNIT_LEVEL does not cover your own level; Blizzard_UnitFrame/Mainline/PlayerFrame.lua listens to this instead.
	local player = build(PlayerFrame, "player", false, WIDTH, HEIGHT,
		{ PlayerFrame.PlayerFrameContainer, PlayerFrame.PlayerFrameContent.PlayerFrameContentMain })
	listen(player, "PLAYER_ENTERING_WORLD"):RegisterEvent("PLAYER_LEVEL_CHANGED")
	local target = build(TargetFrame, "target", true, WIDTH, HEIGHT, targetParts(TargetFrame))
	listen(target, "PLAYER_TARGET_CHANGED")
	followAuras(TargetFrame, target)
	local focus = build(FocusFrame, "focus", true, WIDTH, HEIGHT, targetParts(FocusFrame))
	listen(focus, "PLAYER_FOCUS_CHANGED")
	followAuras(FocusFrame, focus)
	hooksecurefunc(PartyFrame, "InitializePartyMemberFrames", function()
		attachPartyFrames()
		ns.RefreshUnitFrames()
	end)
	attachPartyFrames()
	local combatEnd = CreateFrame("Frame")
	combatEnd:RegisterEvent("PLAYER_REGEN_ENABLED")
	combatEnd:SetScript("OnEvent", function()
		for _, frame in pairs(partyFrames) do
			updateClicker(frame)
		end
	end)
end

function ns.RefreshUnitFrames()
	local custom = ns.db.customUnitFrames
	for _, frame in pairs(partyFrames) do
		updateClicker(frame)
	end
	for _, frame in ipairs(frames) do
		for _, part in ipairs(frame.blizzardParts) do
			part:SetAlpha(custom and 0 or 1)
		end
		frame:SetShown(custom)
		if custom then
			updateAll(frame)
		end
	end
	-- Blizzard's own anchoring puts the auras back when the option is off; the hook moves them when it's on.
	if not InCombatLockdown() then
		TargetFrame:AnchorAuraContainer()
		FocusFrame:AnchorAuraContainer()
	end
end

-- Blizzard's bar text follows the same option, so both change together.
function ns.RefreshHealthPercent()
	ns.RefreshCVars()
	ns.RefreshUnitFrames()
end
