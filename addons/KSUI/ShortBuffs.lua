-- Shields and heals over time as small icons, whoever cast them, on KSUI's party rows, Blizzard's own party frames and
-- Blizzard's raid frames (also used for raid-style party frames). Forever reports other players' auras with no
-- duration and ignores the aura filters, so they are picked by name from this list (Classic rank 1 spell IDs; any
-- rank matches by name), which leaves the long group buffs out. When an aura's name is secret, as in instances, it is
-- left out. Two debuffs come along: Weakened Soul (no new Power Word: Shield yet) and Forbearance (no new Blessing of
-- Protection or Divine Shield yet), after the buffs.
--
-- The time left shows as a cooldown swipe. The game gives other players' auras no duration and no start, so KSUI times
-- them itself: from the moment UNIT_AURA reports the aura added, for the spell's duration in the list below. An aura
-- that was already there when KSUI first saw it (after a reload, joining a group) has no start and shows no swipe.

local _, ns = ...

local COUNT = 4
-- Rank 1 spell ID, seconds, and "absorb" for a shield (its updates are the amount it has left, not a re-cast).
-- Durations are Classic's base; the ones that change with rank are in RANK_DURATION by the rank's spell ID. Talents
-- that lengthen a heal (Forever's Nature's Splendor) aren't known for other players, so their swipe ends early.
local SHORT_BUFF_SPELLS = {
	{ 17, 30, "absorb" }, { 139, 15 }, { 7001, 10 }, { 552, 20 }, -- Power Word: Shield, Renew, Lightwell Renew, Abolish Disease
	{ 774, 12 }, { 8936, 21 }, { 2893, 8 }, -- Rejuvenation, Regrowth, Abolish Poison
	{ 1022, 6 }, { 498, 6 }, { 642, 10 }, -- Blessing of Protection, Divine Protection, Divine Shield
	{ 11426, 60, "absorb" }, { 1463, 60, "absorb" }, -- Ice Barrier, Mana Shield
	{ 543, 30, "absorb" }, { 6143, 30, "absorb" }, -- Fire Ward, Frost Ward
	{ 6229, 30, "absorb" }, { 7812, 30, "absorb" }, -- Shadow Ward, Sacrifice (Voidwalker)
}
-- The debuffs that say a shield or a blessing can't go on again yet. Their updates (Renewed Hope shortening Weakened
-- Soul) aren't a re-cast either. They keep their places on a full row.
local LOCKOUT_SPELLS = { { 6788, 15, "lockout" }, { 25771, 60, "lockout" } } -- Weakened Soul, Forbearance
local RANK_DURATION = { [5599] = 8, [10278] = 10, [5573] = 8, [1020] = 12 }
local RAID_SIZE = 11
local buffNames, lockoutNames, lockoutIDs

-- auraInstanceID -> { start = GetTime(), duration, unit } from when UNIT_AURA reported it added, or a heal re-cast.
local started = {}
-- Every icon row, so a start that arrives after an icon was drawn still reaches it.
local iconRows = setmetatable({}, { __mode = "k" })

local function byName(list)
	local names = {}
	for _, spell in ipairs(list) do
		local name = C_Spell.GetSpellName(spell[1])
		if name then
			names[name] = spell
		end
	end
	return names
end

-- The list entry for a shield, heal or (harmful) lockout, or nil. A readable list can still hold an aura that isn't.
local function shortBuffOf(aura, harmful)
	if not buffNames then
		buffNames, lockoutNames, lockoutIDs = byName(SHORT_BUFF_SPELLS), byName(LOCKOUT_SPELLS), {}
		for _, spell in ipairs(LOCKOUT_SPELLS) do
			lockoutIDs[spell[1]] = spell
		end
	end
	if issecretvalue(aura) or type(aura) ~= "table" or not canaccesstable(aura) then
		return nil
	end
	local name, id, spellId = aura.name, aura.auraInstanceID, aura.spellId
	if issecretvalue(name) or issecretvalue(id) then
		return nil
	end
	if not harmful then
		return buffNames[name]
	end
	-- A harmful aura can share a buff's name (the Voidwalker's Sacrifice is also a stun); the ID decides when readable.
	if not issecretvalue(spellId) and spellId then
		return lockoutIDs[spellId]
	end
	return lockoutNames[name]
end

local function durationOf(spell, aura)
	local id = aura.spellId
	return not issecretvalue(id) and RANK_DURATION[id] or spell[2]
end

-- The recorded start of a timed aura, dropped once its time is over so a reused ID can't pick it up.
local function startOf(id)
	local entry = started[id]
	if entry and entry.start + entry.duration < GetTime() then
		started[id], entry = nil, nil
	end
	return entry
end

local function startCooldown(icon, aura)
	local entry = startOf(aura.auraInstanceID)
	if entry then
		icon.cooldown:SetCooldown(entry.start, entry.duration)
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

-- A list from the client or an event, or an empty one when it is missing or can't be read.
local function readable(list)
	if issecretvalue(list) or type(list) ~= "table" or not canaccesstable(list) then
		return {}
	end
	return list
end

local function collect(unit, harmful, limit)
	local found = {}
	local auras = ns.ReadAuras(C_UnitAuras.GetUnitAuras, unit, harmful and "HARMFUL" or "HELPFUL")
	for _, aura in ipairs(readable(auras)) do
		if #found < limit and shortBuffOf(aura, harmful) then
			found[#found + 1] = aura
		end
	end
	return found
end

function ns.UpdateShortBuffIcons(icons, unit)
	local shown = {}
	if unit and UnitExists(unit) then
		local lockouts = collect(unit, true, #LOCKOUT_SPELLS)
		shown = collect(unit, false, COUNT - #lockouts)
		for _, aura in ipairs(lockouts) do
			shown[#shown + 1] = aura
		end
	end
	icons.auras = shown
	for i, icon in ipairs(icons) do
		local aura = shown[i]
		icon:SetShown(aura ~= nil)
		icon.native = nil
		if aura then
			icon.texture:SetTexture(aura.icon)
			local duration = aura.duration
			-- The duration query has the same guard as the list, and returns nothing once the aura is gone.
			local object = not issecretvalue(duration) and duration > 0
				and ns.ReadAuras(C_UnitAuras.GetAuraDuration, unit, aura.auraInstanceID)
			if object then
				icon.cooldown:SetCooldownFromDurationObject(object)
				icon.native = true
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

local function begin(changed, unit, aura, spell)
	local id = aura.auraInstanceID
	started[id] = { start = GetTime(), duration = durationOf(spell, aura), unit = unit }
	changed[id] = true
end

-- Records when short buffs are added, re-cast or gone, from UNIT_AURA's update info, and restarts the swipe of any icon
-- timed by KSUI that already shows that aura (the frames' own UNIT_AURA handlers may have drawn before this one ran).
local function track(unit, info)
	if issecretvalue(unit) or issecretvalue(info) or type(info) ~= "table" or not canaccesstable(info)
		or C_Secrets.ShouldAurasBeSecret() then
		return
	end
	-- A full update says nothing about what changed; this unit's starts can't be trusted past it.
	local full = info.isFullUpdate
	if not issecretvalue(full) and full then
		for id, entry in pairs(started) do
			if entry.unit == unit then
				started[id] = nil
			end
		end
	end
	local changed = {}
	for _, aura in ipairs(readable(info.addedAuras)) do
		-- The event doesn't say which list the aura is in; a debuff is matched by its ID where it can be.
		local spell = shortBuffOf(aura, false) or shortBuffOf(aura, true)
		if spell then
			begin(changed, unit, aura, spell)
		end
	end
	for _, id in ipairs(readable(info.updatedAuraInstanceIDs)) do
		if not issecretvalue(id) then
			-- Only a heal's update is a re-cast; it also times one first seen before the re-cast.
			local aura = ns.ReadAuras(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, id)
			local spell = shortBuffOf(aura, false)
			if spell and not spell[3] then
				begin(changed, unit, aura, spell)
			end
		end
	end
	for _, id in ipairs(readable(info.removedAuraInstanceIDs)) do
		if not issecretvalue(id) then
			started[id] = nil
		end
	end
	if next(changed) then
		for icons in pairs(iconRows) do
			for i, aura in ipairs(icons.auras or {}) do
				if changed[aura.auraInstanceID] and not icons[i].native then
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
