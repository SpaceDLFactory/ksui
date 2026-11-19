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

-- Everyone in the group, you included. A raid's raidN units already include you.
local function groupUnits()
	if IsInRaid() then
		local units = {}
		for i = 1, GetNumGroupMembers() do
			units[#units + 1] = "raid" .. i
		end
		return units
	end
	local units = { "player" }
	for i = 1, GetNumGroupMembers() - 1 do
		units[#units + 1] = "party" .. i
	end
	return units
end

local function groupClasses(units)
	local classes = {}
	for _, unit in ipairs(units) do
		local _, class = UnitClass(unit)
		-- Secrecy is checked before the class is tested, as in Skin.lua.
		if not issecretvalue(class) and class then
			classes[class] = true
		end
	end
	return classes
end

-- Returns nil when the game hides the unit's auras from addons.
local function buffNames(unit)
	local names = {}
	for i = 1, MAX_AURAS do
		local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
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

-- For each buff wanted in this group, the names of those without it, and how many members couldn't be checked.
local function missingBuffs()
	local units = groupUnits()
	local classes = groupClasses(units)
	local missing, unreadable = {}, 0
	for _, unit in ipairs(units) do
		local name = UnitName(unit)
		-- Members who are offline or dead can't take a buff now.
		if UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
			local have = buffNames(unit)
			if not have or issecretvalue(name) then
				unreadable = unreadable + 1
			else
				local usesMana = UnitPowerType(unit) == Enum.PowerType.Mana
				for _, buff in ipairs(RAID_BUFFS) do
					if classes[buff.class] and (usesMana or not buff.manaOnly) then
						local found, label = false, nil
						for _, spell in ipairs(buff.spells) do
							local spellName = C_Spell.GetSpellName(spell)
							label = label or spellName
							found = found or (spellName ~= nil and have[spellName] == true)
						end
						if label and not found then
							missing[label] = missing[label] or {}
							table.insert(missing[label], name)
						end
					end
				end
			end
		end
	end
	return missing, unreadable
end

function ns.OnReadyCheck()
	if not ns.db.buffCheck then
		return
	end
	local missing, unreadable = missingBuffs()
	local lines = {}
	for _, buff in ipairs(RAID_BUFFS) do
		local label = C_Spell.GetSpellName(buff.spells[1])
		if label and missing[label] then
			lines[#lines + 1] = label .. ": " .. table.concat(missing[label], ", ")
		end
	end
	if #lines > 0 then
		print(ns.T("검성UI 준비 확인: 빠진 버프 - ", "KSUI ready check: missing buffs - ") .. table.concat(lines, " / "))
	end
	if unreadable > 0 then
		print(ns.T("검성UI 준비 확인: %d명은 지금 버프를 확인할 수 없습니다.",
			"KSUI ready check: %d players' buffs can't be read right now."):format(unreadable))
	end
end
