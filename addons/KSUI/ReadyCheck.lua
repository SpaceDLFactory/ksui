local _, ns = ...

-- Raid-wide buffs, each wanted only when its class is in the group. Spell IDs are Classic rank 1 of the
-- single and group versions; any rank matches because auras are compared by name.
-- Paladin blessings are left out: who gets which blessing is a raid assignment, not a missing buff.
local RAID_BUFFS = {
	{ class = "PRIEST", spells = { 1243, 21562 } },
	{ class = "DRUID", spells = { 1126, 21849 } },
	{ class = "MAGE", spells = { 1459, 23028 }, manaOnly = true },
}
local MAX_AURAS = 40

local function groupClasses()
	local classes = {}
	local prefix, count = "party", GetNumGroupMembers() - 1
	if IsInRaid() then
		prefix, count = "raid", GetNumGroupMembers()
	end
	local units = { "player" }
	for i = 1, count do
		units[#units + 1] = prefix .. i
	end
	for _, unit in ipairs(units) do
		local _, class = UnitClass(unit)
		-- Secrecy is checked before the class is tested, as in Skin.lua.
		if not issecretvalue(class) and class then
			classes[class] = true
		end
	end
	return classes
end

-- Returns nil when the game hides your auras from addons.
local function playerBuffNames()
	local names = {}
	for i = 1, MAX_AURAS do
		local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
		-- The result itself is checked before it is tested or indexed.
		if issecretvalue(aura) then
			return nil
		end
		if not aura then
			break
		end
		if not canaccesstable(aura) or issecretvalue(aura.name) then
			return nil
		end
		names[aura.name] = true
	end
	return names
end

local function missingBuffs()
	local have = playerBuffNames()
	if not have then
		return nil
	end
	local classes = groupClasses()
	local usesMana = UnitPowerType("player") == Enum.PowerType.Mana
	local missing = {}
	for _, buff in ipairs(RAID_BUFFS) do
		if classes[buff.class] and (usesMana or not buff.manaOnly) then
			local found, label = false, nil
			for _, spell in ipairs(buff.spells) do
				local name = C_Spell.GetSpellName(spell)
				label = label or name
				found = found or (name ~= nil and have[name] == true)
			end
			if label and not found then
				missing[#missing + 1] = label
			end
		end
	end
	return missing
end

function ns.OnReadyCheck()
	if not ns.db.buffCheck then
		return
	end
	local missing = missingBuffs()
	if not missing then
		print("검성UI: 지금은 버프를 확인할 수 없습니다.")
	elseif #missing > 0 then
		print("검성UI 준비 확인: 빠진 버프 - " .. table.concat(missing, ", "))
	end
end
