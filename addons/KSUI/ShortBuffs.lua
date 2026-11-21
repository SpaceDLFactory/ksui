-- Shields and heals over time as small icons, whoever cast them, on KSUI's party rows, Blizzard's own party frames and
-- Blizzard's raid frames (also used for raid-style party frames). Forever reports other players' auras with no
-- duration and ignores the aura filters, so they are picked by name from this list (Classic rank 1 spell IDs; any
-- rank matches by name), which leaves the long group buffs out. When an aura's name is secret, as in instances, it is
-- left out.
--
-- The time left shows as a cooldown swipe. The game gives other players' auras no duration and no start, so KSUI times
-- them itself: from the moment UNIT_AURA reports the aura added, for the spell's duration in the list below. An aura
-- that was already there when KSUI first saw it (after a reload, joining a group) has no start and shows no swipe.

local _, ns = ...

local COUNT = 4
-- Rank 1 spell ID, seconds, and whether it absorbs damage (its updates are then the amount left, not a recast).
-- Durations are Classic's; the ones that change with rank are in RANK_DURATION by the rank's spell ID.
local SHORT_BUFF_SPELLS = {
	{ 17, 30, true }, { 139, 15 }, { 7001, 10 }, { 552, 20 }, -- Power Word: Shield, Renew, Lightwell Renew, Abolish Disease
	{ 774, 12 }, { 8936, 21 }, { 2893, 8 }, -- Rejuvenation, Regrowth, Abolish Poison
	{ 1022, 6 }, { 498, 6 }, { 642, 10 }, -- Blessing of Protection, Divine Protection, Divine Shield
	{ 11426, 60, true }, { 1463, 60, true }, -- Ice Barrier, Mana Shield
	{ 543, 30, true }, { 6143, 30, true }, -- Fire Ward, Frost Ward
	{ 6229, 30, true }, { 7812, 30, true }, -- Shadow Ward, Sacrifice (Voidwalker)
}
local RANK_DURATION = { [5599] = 8, [10278] = 10, [5573] = 8, [1020] = 12 }
local RAID_SIZE = 11
local shortBuffNames

-- auraInstanceID -> GetTime() when UNIT_AURA reported it added, or re-cast for a heal over time.
local started = {}
-- Every icon row, so a start that arrives after an icon was drawn still reaches it.
local iconRows = setmetatable({}, { __mode = "k" })

local function isShortBuff(aura)
	if not shortBuffNames then
		shortBuffNames = {}
		for _, spell in ipairs(SHORT_BUFF_SPELLS) do
			local name = C_Spell.GetSpellName(spell[1])
			if name then
				shortBuffNames[name] = spell
			end
		end
	end
	-- A readable list can still hold an aura that isn't.
	if issecretvalue(aura) or not canaccesstable(aura) then
		return false
	end
	local name, id = aura.name, aura.auraInstanceID
	if issecretvalue(name) or issecretvalue(id) then
		return false
	end
	return shortBuffNames[name] ~= nil
end

-- Seconds the aura lasts and whether it absorbs, from the list; isShortBuff(aura) has been checked.
local function spellOf(aura)
	local spell = shortBuffNames[aura.name]
	local id = aura.spellId
	local byRank = not issecretvalue(id) and RANK_DURATION[id]
	return byRank or spell[2], spell[3] == true
end

local function startCooldown(icon, aura)
	local start = started[aura.auraInstanceID]
	if start then
		icon.cooldown:SetCooldown(start, (spellOf(aura)))
	else
		icon.cooldown:Clear()
	end
end

-- Icons in a row from the given corner of the parent, growing towards "RIGHT" or "LEFT", above the parent's children
-- up to the given frame level.
function ns.CreateShortBuffIcons(parent, size, corner, x, y, grow, level)
	local icons = {}
	iconRows[icons] = true
	local step = (size + 1) * (grow == "LEFT" and -1 or 1)
	for i = 1, COUNT do
		local icon = CreateFrame("Frame", nil, parent)
		icon:SetSize(size, size)
		icon:SetPoint(corner, x + (i - 1) * step, y)
		icon:SetFrameLevel(level)
		icon.texture = icon:CreateTexture(nil, "ARTWORK")
		icon.texture:SetAllPoints()
		icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
		icon.cooldown:SetAllPoints()
		icon.cooldown:SetHideCountdownNumbers(true)
		icon:Hide()
		icons[i] = icon
	end
	return icons
end

-- Where auras are secret (instances, encounters), the aura queries raise an error for addon code instead of
-- returning secrets, so they aren't asked then. The pcall covers a unit restricted on its own. Returns nil when the
-- unit's auras can't be read.
function ns.ReadAuras(query, ...)
	if C_Secrets.ShouldAurasBeSecret() then
		return nil
	end
	local ok, result = pcall(query, ...)
	if ok then
		return result
	end
end

function ns.UpdateShortBuffIcons(icons, unit)
	local shown = {}
	icons.auras = shown
	if unit and UnitExists(unit) then
		local auras = ns.ReadAuras(C_UnitAuras.GetUnitAuras, unit, "HELPFUL")
		-- The result itself is checked before it is tested.
		if not issecretvalue(auras) and auras and canaccesstable(auras) then
			for _, aura in ipairs(auras) do
				if #shown < COUNT and isShortBuff(aura) then
					shown[#shown + 1] = aura
				end
			end
		end
	end
	for i, icon in ipairs(icons) do
		local aura = shown[i]
		icon:SetShown(aura ~= nil)
		if aura then
			icon.texture:SetTexture(aura.icon)
			local duration = aura.duration
			-- The duration query has the same guard as the list, and returns nothing once the aura is gone.
			local object = not issecretvalue(duration) and duration > 0
				and ns.ReadAuras(C_UnitAuras.GetAuraDuration, unit, aura.auraInstanceID)
			if object then
				icon.cooldown:SetCooldownFromDurationObject(object)
			else
				startCooldown(icon, aura)
			end
		end
	end
end

-- Blizzard's raid frames, and its party frames in raid style, are named CompactRaid... and CompactParty...; the same
-- code also draws frames that addons may not touch, which are left alone.
local compactFrames = {}
local clearedSecret = false

local function isGroupFrame(frame)
	if frame:IsForbidden() then
		return false
	end
	local name = frame:GetName()
	return name ~= nil and (name:find("^CompactRaid") ~= nil or name:find("^CompactParty") ~= nil)
end

-- Records when short buffs are added, re-cast or gone, from UNIT_AURA's update info, and restarts the swipe of any icon
-- already showing that aura (the frames' own UNIT_AURA handlers may have drawn before this one ran).
local function track(unit, info)
	if issecretvalue(unit) or issecretvalue(info) or type(info) ~= "table" or not canaccesstable(info)
		or C_Secrets.ShouldAurasBeSecret() then
		return
	end
	local changed = {}
	for _, aura in ipairs(info.addedAuras or {}) do
		if isShortBuff(aura) then
			started[aura.auraInstanceID] = GetTime()
			changed[aura.auraInstanceID] = true
		end
	end
	for _, id in ipairs(info.updatedAuraInstanceIDs or {}) do
		-- A shield's updates are the amount it has left; a heal over time's is a re-cast.
		if not issecretvalue(id) and started[id] then
			local aura = ns.ReadAuras(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, id)
			local reCast = false
			if aura and isShortBuff(aura) then
				local _, absorbs = spellOf(aura)
				reCast = not absorbs
			end
			if reCast then
				started[id] = GetTime()
				changed[id] = true
			end
		end
	end
	for _, id in ipairs(info.removedAuraInstanceIDs or {}) do
		if not issecretvalue(id) then
			started[id] = nil
		end
	end
	if next(changed) then
		for icons in pairs(iconRows) do
			for i, aura in ipairs(icons.auras or {}) do
				if changed[aura.auraInstanceID] then
					startCooldown(icons[i], aura)
				end
			end
		end
	end
end

-- Made as the file loads, so it is the first of KSUI's frames to hear UNIT_AURA.
local tracker = CreateFrame("Frame")
tracker:RegisterEvent("UNIT_AURA")
tracker:SetScript("OnEvent", function(_, _, unit, info)
	track(unit, info)
end)

local function onSetUnit(frame)
	if not isGroupFrame(frame) then
		return
	end
	local icons = compactFrames[frame]
	if not icons then
		icons = ns.CreateShortBuffIcons(frame, RAID_SIZE, "TOPRIGHT", -2, -2, "LEFT", frame:GetFrameLevel() + 5)
		compactFrames[frame] = icons
	end
	ns.UpdateShortBuffIcons(icons, frame.displayedUnit)
end

function ns.InitShortBuffs()
	hooksecurefunc("CompactUnitFrame_SetUnit", onSetUnit)
	local events = CreateFrame("Frame")
	events:RegisterEvent("UNIT_AURA")
	events:RegisterEvent("GROUP_ROSTER_UPDATE")
	events:SetScript("OnEvent", function(_, event, unit)
		-- UNIT_AURA's unit can itself be secret where auras are (SecretWhenAurasRestricted), so it isn't compared
		-- then; every frame is redrawn instead, which clears icons nothing can be read for any more.
		local secret = event == "UNIT_AURA" and issecretvalue(unit)
		-- Once cleared there is nothing more to clear until auras can be read again.
		if secret and clearedSecret then
			return
		end
		clearedSecret = secret
		local all = event == "GROUP_ROSTER_UPDATE" or secret
		for frame, icons in pairs(compactFrames) do
			local shown = frame.displayedUnit
			if all or shown == unit then
				ns.UpdateShortBuffIcons(icons, shown)
			end
		end
	end)
end
