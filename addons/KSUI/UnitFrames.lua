-- Square player, target, focus and party frames with a moving portrait, drawn over Blizzard's. Blizzard's secure frames stay
-- underneath with only their art, bars and portrait faded out, so clicks, menus, Edit Mode positions, target auras,
-- the threat number and the icons beside the frame keep working. Ours are children of theirs, so they show and hide
-- with the unit. Health, power and names can be secret in instances, so they only go to setters that accept secrets.

local _, ns = ...

-- Each fits inside Blizzard's frame (232 x 100, party 120 x 53), which stays the click area.
local WIDTH, HEIGHT = 224, 56
-- Your pet and your target's target, inside Blizzard's 120 x 49 frames, which stay the click area.
local SMALL_WIDTH, SMALL_HEIGHT = 120, 46
-- Party frames get the full height so the name and the health number don't overlap, and run past Blizzard's
-- 120-wide frame to the right so the bars have room.
local PARTY_WIDTH, PARTY_HEIGHT = 200, 52
-- Blizzard_UnitFrame/Shared/PartyFrame.xml stacks the members this far apart.
local PARTY_SPACING = 10
local POWER_HEIGHT = 12
local GAP = 2
local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local HEALTH_GREEN = { 0.1, 0.8, 0.1 }
-- Incoming heals as a green stretch past the health, then shields in pale blue, like Blizzard's raid frames.
local HEAL_COLOR = { 0.35, 0.9, 0.35, 0.6 }
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

	-- Heals and absorbs can be secret, so their lengths can't be worked out here. Each bar instead starts where the
	-- one before it ends and is as wide as the health bar on the same scale, so the client draws the right length;
	-- whatever runs past a full bar is clipped.
	frame.health:SetClipsChildren(true)
	local function after(previous, color)
		local bar = CreateFrame("StatusBar", nil, frame.health)
		bar:SetStatusBarTexture(FLAT)
		bar:SetStatusBarColor(color[1], color[2], color[3], color[4])
		local fill = previous:GetStatusBarTexture()
		bar:SetPoint("TOPLEFT", fill, "TOPRIGHT")
		bar:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT")
		return bar
	end
	frame.heal = after(frame.health, HEAL_COLOR)
	frame.absorb = after(frame.heal, ABSORB_COLOR)
	frame.health:SetScript("OnSizeChanged", function(_, width)
		frame.heal:SetWidth(width)
		frame.absorb:SetWidth(width)
	end)
	-- The incoming heal and shield amounts, each in its bar's color.
	frame.health.absorbValue = outlinedText(frame.health)
	frame.health.absorbValue:SetPoint("BOTTOM" .. far, frame.health.value, "BOTTOM" .. near, -6 * inward, 0)
	-- The shield bar is a child frame, so it would draw over the bar's text; the text moves to a frame above it.
	local texts = CreateFrame("Frame", nil, frame.health)
	texts:SetAllPoints()
	texts:SetFrameLevel(frame.absorb:GetFrameLevel() + 1)
	for _, text in ipairs({ frame.health.name, frame.health.value, frame.health.absorbValue }) do
		text:SetParent(texts)
	end
	frame.health.texts = texts

	frame.power = statusBar(frame)
	frame.power:SetPoint("TOP" .. near, frame.health, "BOTTOM" .. near, 0, -GAP)
	frame.power:SetPoint("BOTTOM" .. far, frame, "BOTTOM" .. far, -inward, 1)
	frame.power.value:SetPoint(far, -4 * inward, 0)

	frames[#frames + 1] = frame
	return frame
end

local function colored(color, amount)
	local r, g, b = math.floor(color[1] * 255), math.floor(color[2] * 255), math.floor(color[3] * 255)
	return ("|cff%02x%02x%02x+%s|r"):format(r, g, b, AbbreviateNumbers(amount))
end

local function updatePrediction(frame)
	local unit = frame.unit
	local maxHealth = UnitHealthMax(unit)
	local heal = UnitGetIncomingHeals(unit)
	if not issecretvalue(heal) and heal == nil then
		heal = 0
	end
	local absorb = UnitGetTotalAbsorbs(unit)
	frame.heal:SetMinMaxValues(0, maxHealth)
	frame.heal:SetValue(heal)
	frame.absorb:SetMinMaxValues(0, maxHealth)
	frame.absorb:SetValue(absorb)
	-- A secret amount can't be checked for zero, so only the bar shows it then.
	local parts = {}
	if not issecretvalue(heal) and heal > 0 then
		parts[#parts + 1] = colored(HEAL_COLOR, heal)
	end
	if not issecretvalue(absorb) and absorb > 0 then
		parts[#parts + 1] = colored(ABSORB_COLOR, absorb)
	end
	frame.health.absorbValue:SetShown(#parts > 0)
	frame.health.absorbValue:SetText(table.concat(parts, " "))
end

local function updateHealth(frame)
	local unit = frame.unit
	local health = UnitHealth(unit)
	frame.health:SetMinMaxValues(0, UnitHealthMax(unit))
	frame.health:SetValue(health)
	updatePrediction(frame)
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

-- Party rows show the group role with Blizzard's own small icons. A role can be secret for units whose identity is
-- hidden in instances; the icon stays hidden then.
local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }
local ROLE_SIZE = 12

local function updateRole(frame)
	if not frame.role then
		return
	end
	local role = UnitGroupRolesAssigned(frame.unit)
	local atlas = not issecretvalue(role) and ROLE_ATLAS[role]
	frame.role:SetShown(atlas ~= nil and atlas ~= false)
	if atlas then
		frame.role:SetAtlas(atlas)
	end
end

local function addRole(frame)
	frame.role = frame.health:CreateTexture(nil, "OVERLAY")
	frame.role:SetSize(ROLE_SIZE, ROLE_SIZE)
	frame.role:SetPoint("TOPRIGHT", -3, -3)
	-- The name stops short of it.
	frame.health.name:SetPoint("TOPRIGHT", -(ROLE_SIZE + 6), -4)
	frame.events:RegisterEvent("PLAYER_ROLES_ASSIGNED")
end

-- Defined with the party rows further down.
local updateHots

local function updateAll(frame)
	if not UnitExists(frame.unit) then
		return
	end
	updateHealth(frame)
	updatePower(frame)
	updateColor(frame)
	updateName(frame)
	updatePortrait(frame)
	updateRole(frame)
	updateHots(frame)
end

local UPDATES = {
	UNIT_HEALTH = updateHealth, UNIT_MAXHEALTH = updateHealth, UNIT_ABSORB_AMOUNT_CHANGED = updatePrediction,
	UNIT_HEAL_PREDICTION = updatePrediction,
	UNIT_AURA = function(frame) updateHots(frame) end,
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
		elseif event == "UNIT_AURA" or event == "GROUP_ROSTER_UPDATE" then
			-- Shield icons also go on Blizzard's party frames while KSUI's rows are off.
			updateHots(frame)
		end
	end)
	return events
end

local function targetParts(blizzard)
	return { blizzard.TargetFrameContainer, blizzard.TargetFrameContent.TargetFrameContentMain }
end

local partyFrames = {}
local threatGlowFrame

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

-- Blizzard's party frames leave you out, so a row for you goes on top of them, drawn like the others. It is a child
-- of the party frame, so it shares its size, and a secure button of its own, so clicks target you and open your menu.
-- It is kept out of Blizzard's layout, which would otherwise read KSUI's values while placing protected frames in
-- combat; the layout moves the party frames down by one row instead.
local partyPlayer

local function buildPartyPlayer()
	partyPlayer = CreateFrame("Button", "KSUIPartyPlayer", PartyFrame, "SecureUnitButtonTemplate")
	partyPlayer:SetSize(PARTY_WIDTH, PARTY_HEIGHT)
	partyPlayer:SetPoint("BOTTOMLEFT", PartyFrame, "TOPLEFT", 0, PARTY_SPACING)
	partyPlayer:RegisterForClicks("AnyUp")
	partyPlayer:SetAttribute("unit", "player")
	partyPlayer:SetAttribute("type1", "target")
	partyPlayer:SetAttribute("type2", "togglemenu")
	local frame = build(partyPlayer, "player", false, PARTY_WIDTH, PARTY_HEIGHT, {})
	listen(frame, "GROUP_ROSTER_UPDATE")
	addRole(frame)
end

-- Shown in a party but not a raid, which has its own frames with you in them, nor with Blizzard's raid-style party
-- frames, which have you in them too.
local function refreshPartyPlayer()
	if InCombatLockdown() then
		return
	end
	if ns.db.customUnitFrames and not EditModeManagerFrame:UseRaidStylePartyFrames() then
		RegisterStateDriver(partyPlayer, "visibility", "[group:raid] hide; [group:party] show; hide")
	else
		UnregisterStateDriver(partyPlayer, "visibility")
		partyPlayer:Hide()
	end
end

-- Blizzard's party frames keep doing the hard parts, moved out from under KSUI's row: its aggro glow becomes a thin
-- edge round the row, and its debuff icons, filtered by Blizzard down to dispellable ones when that option is on, sit
-- to the row's right. Blizzard reshapes the glow with its art, so it is squared off again after.
local PARTY_GLOW = 2
local PARTY_DEBUFFS_GAP = 4
-- Where Blizzard_UnitFrame/Mainline/PartyFrameTemplates.xml puts them.
local BLIZZARD_DEBUFFS_X, BLIZZARD_DEBUFFS_Y = 48, -43

-- The glow is a texture, so it is squared off again at once, in combat too, whenever Blizzard redraws its art. The
-- debuff icons' frame hangs off Blizzard's secure frame, so it moves only out of combat.
local function placePartyExtras(member, frame)
	local glow, debuffs = member.Flash, member.AuraFrameContainer
	glow:ClearAllPoints()
	if ns.db.customUnitFrames then
		glow:SetParent(frame)
		glow:SetTexture(FLAT)
		glow:SetDrawLayer("BACKGROUND", -8)
		glow:SetPoint("TOPLEFT", -PARTY_GLOW, PARTY_GLOW)
		glow:SetPoint("BOTTOMRIGHT", PARTY_GLOW, -PARTY_GLOW)
	else
		glow:SetParent(member)
		glow:SetDrawLayer("ARTWORK")
		member:UpdateArt()
	end
	if InCombatLockdown() then
		return
	end
	debuffs:ClearAllPoints()
	if ns.db.customUnitFrames then
		debuffs:SetPoint("TOPLEFT", frame, "TOPRIGHT", PARTY_DEBUFFS_GAP, 0)
	else
		debuffs:SetPoint("TOPLEFT", member, "TOPLEFT", BLIZZARD_DEBUFFS_X, BLIZZARD_DEBUFFS_Y)
	end
end

-- Shields and heals over time (ShortBuffs.lua): small at the bottom left of KSUI's party row, and to the right of
-- Blizzard's own party frame for when KSUI's rows are switched off.
local HOT_SIZE, BLIZZARD_HOT_SIZE = 12, 14

local function addHots(frame, member)
	frame.hots = ns.CreateShortBuffIcons(frame.health, HOT_SIZE, "BOTTOMLEFT", 2, 2, "RIGHT", frame.absorb:GetFrameLevel() + 2)
	frame.blizzardHots = ns.CreateShortBuffIcons(member, BLIZZARD_HOT_SIZE, "TOPRIGHT", BLIZZARD_HOT_SIZE + 2, 0, "RIGHT",
		member:GetFrameLevel() + 5)
end

function updateHots(frame)
	if not frame.hots then
		return
	end
	local custom = ns.db.customUnitFrames
	ns.UpdateShortBuffIcons(frame.hots, custom and frame.unit or nil)
	if frame.blizzardHots then
		ns.UpdateShortBuffIcons(frame.blizzardHots, not custom and frame.unit or nil)
	end
end

local function attachPartyFrames()
	for member in PartyFrame.PartyMemberFramePool:EnumerateActive() do
		local frame = partyFrames[member]
		if not frame then
			frame = build(member, member.unitToken, false, PARTY_WIDTH, PARTY_HEIGHT, {
				member.Texture, member.VehicleTexture, member.Portrait, member.Name,
				member.HealthBarContainer, member.ManaBar,
			})
			-- Grows to the right from Blizzard's frame instead of from its middle.
			frame:ClearAllPoints()
			frame:SetPoint("LEFT")
			listen(frame, "GROUP_ROSTER_UPDATE")
			addRole(frame)
			addHots(frame, member)
			hooksecurefunc(member.Portrait, "SetAlpha", keepPortraitHidden)
			for _, art in ipairs({ "ToPlayerArt", "ToVehicleArt", "ToCharacterStyleArt" }) do
				hooksecurefunc(member, art, function()
					if ns.db.customUnitFrames then
						placePartyExtras(member, frame)
					end
				end)
			end
			partyFrames[member] = frame
		end
		setUnit(frame, member.unitToken)
		updateClicker(frame)
		placePartyExtras(member, frame)
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

-- Blizzard shows your threat as a colored glow round its own player frame, which ours covers. That glow moves to ours,
-- squared off and just outside its edge; Blizzard keeps showing, hiding and coloring it, threat being secret in
-- instances. Blizzard sets its shape again when the frame changes, so it is squared off again after.
local THREAT_GLOW = 3

local function placeThreatGlow(frame)
	local glow = PlayerFrame.PlayerFrameContainer.FrameFlash
	if not ns.db.customUnitFrames then
		-- Back where Blizzard_UnitFrame/Mainline/PlayerFrame.xml has it; Blizzard's rest and combat art is anchored to
		-- its parent, so that is placed again too.
		glow:SetParent(PlayerFrame.PlayerFrameContainer)
		glow:ClearAllPoints()
		glow:SetDrawLayer("OVERLAY")
		PlayerFrame_UpdateFlashTextureVisuals()
		PlayerFrame_UpdateStatusTextureVisuals()
		return
	end
	glow:SetParent(frame)
	glow:SetTexture(FLAT)
	glow:SetDrawLayer("BACKGROUND", -8)
	glow:ClearAllPoints()
	glow:SetPoint("TOPLEFT", -THREAT_GLOW, THREAT_GLOW)
	glow:SetPoint("BOTTOMRIGHT", THREAT_GLOW, -THREAT_GLOW)
end

-- Your pet, under your frame where Blizzard_UnitFrame/Mainline/PetFrame.xml puts its own. Blizzard's happiness icon
-- hangs off the right of its frame, so it stays beside ours.
local function buildPet()
	local pet = build(PetFrame, "pet", false, SMALL_WIDTH, SMALL_HEIGHT, {
		PetFrameTexture, PetPortrait, PetName, PetFrameHealthBar, PetFrameManaBar, PetFrameFlash, PetAttackModeTexture,
	})
	listen(pet, "UNIT_PET")
end

-- Blizzard gives "targettarget" no unit events and redraws its frame from TargetFrame's updates instead
-- (Blizzard_UnitFrame/Mainline/TargetFrame.lua), so ours follows those. The model only loads again when the target
-- picks a new target, not at every redraw.
local function buildTargetOfTarget()
	local blizzard = TargetFrameToT
	if not blizzard then
		return
	end
	local tot = build(blizzard, "targettarget", true, SMALL_WIDTH, SMALL_HEIGHT, {
		blizzard.FrameTexture, blizzard.Portrait, blizzard.Name, blizzard.HealthBar, blizzard.ManaBar,
	})
	listen(tot, "PLAYER_TARGET_CHANGED"):RegisterUnitEvent("UNIT_TARGET", "target")
	hooksecurefunc(blizzard, "Update", function()
		if ns.db.customUnitFrames and UnitExists(tot.unit) then
			updateHealth(tot)
			updatePower(tot)
			updateColor(tot)
			updateName(tot)
		end
	end)
end

-- The ammo a hunter has left, at the bottom left of your health bar; red when it runs low. Read the way
-- Blizzard_UIPanels_Game/Camelot/PaperDollFrame.lua fills its ammo slot.
local AMMO_LOW = 100
local ammoText

local function updateAmmo()
	if not ammoText then
		return
	end
	local shown = ns.db.ammoCount and UnitUsesAmmo("player")
	ammoText:SetShown(shown)
	if not shown then
		return
	end
	local count = GetInventoryItemCount("player", INVSLOT_AMMO)
	if not issecretvalue(count) and count == nil then
		count = 0
	end
	if not issecretvalue(count) and count < AMMO_LOW then
		ammoText:SetTextColor(1, 0.2, 0.2)
	else
		ammoText:SetTextColor(1, 1, 1)
	end
	ammoText:SetFormattedText(ns.L.AMMO, count)
end

local function buildAmmo(player)
	ammoText = outlinedText(player.health)
	-- On the layer above the shield bar, with the bar's other text.
	ammoText:SetParent(player.health.texts)
	ammoText:SetPoint("BOTTOMLEFT", 4, 4)
	player.ammo = ammoText
	local events = CreateFrame("Frame")
	events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
	events:RegisterEvent("BAG_UPDATE")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:SetScript("OnEvent", updateAmmo)
end

function ns.InitUnitFrames()
	-- Your model may not be loaded yet at login.
	-- UNIT_LEVEL does not cover your own level; Blizzard_UnitFrame/Mainline/PlayerFrame.lua listens to this instead.
	local player = build(PlayerFrame, "player", false, WIDTH, HEIGHT,
		{ PlayerFrame.PlayerFrameContainer, PlayerFrame.PlayerFrameContent.PlayerFrameContentMain })
	listen(player, "PLAYER_ENTERING_WORLD"):RegisterEvent("PLAYER_LEVEL_CHANGED")
	buildAmmo(player)
	threatGlowFrame = player
	hooksecurefunc("PlayerFrame_UpdateFlashTextureVisuals", function()
		if ns.db.customUnitFrames then
			placeThreatGlow(player)
		end
	end)
	local target = build(TargetFrame, "target", true, WIDTH, HEIGHT, targetParts(TargetFrame))
	listen(target, "PLAYER_TARGET_CHANGED")
	followAuras(TargetFrame, target)
	local focus = build(FocusFrame, "focus", true, WIDTH, HEIGHT, targetParts(FocusFrame))
	listen(focus, "PLAYER_FOCUS_CHANGED")
	followAuras(FocusFrame, focus)
	buildPet()
	buildTargetOfTarget()
	hooksecurefunc(PartyFrame, "InitializePartyMemberFrames", function()
		attachPartyFrames()
		ns.RefreshUnitFrames()
	end)
	attachPartyFrames()
	buildPartyPlayer()
	-- Blizzard redraws the party when its style changes in Edit Mode.
	hooksecurefunc(PartyFrame, "UpdatePartyFrames", refreshPartyPlayer)
	local combatEnd = CreateFrame("Frame")
	combatEnd:RegisterEvent("PLAYER_REGEN_ENABLED")
	combatEnd:SetScript("OnEvent", function()
		for member, frame in pairs(partyFrames) do
			updateClicker(frame)
			placePartyExtras(member, frame)
		end
		refreshPartyPlayer()
		-- Catches up the secure parts that couldn't fade while the setting changed in combat.
		local alpha = ns.db.customUnitFrames and 0 or 1
		for _, frame in ipairs(frames) do
			for _, part in ipairs(frame.blizzardParts) do
				part:SetAlpha(alpha)
			end
		end
	end)
end

function ns.RefreshUnitFrames()
	local custom = ns.db.customUnitFrames
	for member, frame in pairs(partyFrames) do
		updateClicker(frame)
		placePartyExtras(member, frame)
	end
	refreshPartyPlayer()
	updateAmmo()
	for _, frame in ipairs(frames) do
		for _, part in ipairs(frame.blizzardParts) do
			-- Some parts are secure (the target of target's health bar); those change after combat.
			if not (InCombatLockdown() and part.IsProtected and part:IsProtected()) then
				part:SetAlpha(custom and 0 or 1)
			end
		end
		frame:SetShown(custom)
		if custom then
			updateAll(frame)
		else
			updateHots(frame)
		end
	end
	-- Blizzard's own anchoring puts the auras back when the option is off; the hook moves them when it's on.
	if not InCombatLockdown() then
		placeThreatGlow(threatGlowFrame)
		TargetFrame:AnchorAuraContainer()
		FocusFrame:AnchorAuraContainer()
	end
end

-- Blizzard's bar text follows the same option, so both change together.
function ns.RefreshHealthPercent()
	ns.RefreshCVars()
	ns.RefreshUnitFrames()
end
