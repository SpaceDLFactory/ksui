local _, ns = ...

-- Forever has no Blizzard upgrade check, so KSUI scores items itself with stat weights for the current spec's role.
-- Keys are what C_Item.GetItemStats returns. The weights are rough starting points, not tuned for Forever.
local TANK = {
	ITEM_MOD_STAMINA_SHORT = 1, RESISTANCE0_NAME = 0.05, ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 1,
	ITEM_MOD_DODGE_RATING_SHORT = 0.9, ITEM_MOD_PARRY_RATING_SHORT = 0.8, ITEM_MOD_BLOCK_RATING_SHORT = 0.5,
	ITEM_MOD_BLOCK_VALUE_SHORT = 0.3, ITEM_MOD_HIT_RATING_SHORT = 0.4, ITEM_MOD_EXPERTISE_RATING_SHORT = 0.4,
	ITEM_MOD_ATTACK_POWER_SHORT = 0.1,
}
local MELEE = {
	ITEM_MOD_ATTACK_POWER_SHORT = 0.5, ITEM_MOD_HIT_RATING_SHORT = 0.8, ITEM_MOD_CRIT_RATING_SHORT = 0.7,
	ITEM_MOD_HASTE_RATING_SHORT = 0.6, ITEM_MOD_EXPERTISE_RATING_SHORT = 0.6,
	ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = 0.5, ITEM_MOD_STAMINA_SHORT = 0.2, RESISTANCE0_NAME = 0.02,
}
local CASTER = {
	ITEM_MOD_SPELL_POWER_SHORT = 1, ITEM_MOD_INTELLECT_SHORT = 0.6, ITEM_MOD_HIT_RATING_SHORT = 0.8,
	ITEM_MOD_HASTE_RATING_SHORT = 0.7, ITEM_MOD_CRIT_RATING_SHORT = 0.6, ITEM_MOD_SPIRIT_SHORT = 0.2,
	ITEM_MOD_STAMINA_SHORT = 0.2, RESISTANCE0_NAME = 0.02,
}
local HEALER = {
	ITEM_MOD_SPELL_POWER_SHORT = 1, ITEM_MOD_INTELLECT_SHORT = 0.8, ITEM_MOD_MANA_REGENERATION_SHORT = 0.8,
	ITEM_MOD_HASTE_RATING_SHORT = 0.6, ITEM_MOD_SPIRIT_SHORT = 0.5, ITEM_MOD_CRIT_RATING_SHORT = 0.5,
	ITEM_MOD_STAMINA_SHORT = 0.2, RESISTANCE0_NAME = 0.02,
}
-- Primary stat indexes as returned by GetSpecializationInfo: 1 strength, 2 agility, 4 intellect.
local PRIMARY_KEY = { [1] = "ITEM_MOD_STRENGTH_SHORT", [2] = "ITEM_MOD_AGILITY_SHORT", [4] = "ITEM_MOD_INTELLECT_SHORT" }
local PRIMARY_WEIGHT = { TANK = 0.6, DAMAGER = 1 }
-- Used before a spec is chosen.
local CLASS_PRIMARY = {
	WARRIOR = 1, PALADIN = 1, DEATHKNIGHT = 1, ROGUE = 2, HUNTER = 2, MONK = 2,
	DRUID = 4, SHAMAN = 4, MAGE = 4, PRIEST = 4, WARLOCK = 4,
}

-- Weapons, shields and trinkets are left alone: their value is in damage, set-ups and on-use effects.
local GROUP_OF = {
	INVTYPE_HEAD = "head", INVTYPE_NECK = "neck", INVTYPE_SHOULDER = "shoulder", INVTYPE_CLOAK = "back",
	INVTYPE_CHEST = "chest", INVTYPE_ROBE = "chest", INVTYPE_WRIST = "wrist", INVTYPE_HAND = "hands",
	INVTYPE_WAIST = "waist", INVTYPE_LEGS = "legs", INVTYPE_FEET = "feet", INVTYPE_FINGER = "finger",
}
local GROUPS = {
	{ name = "head", slots = { 1 } }, { name = "neck", slots = { 2 } }, { name = "shoulder", slots = { 3 } },
	{ name = "back", slots = { 15 } }, { name = "chest", slots = { 5 } }, { name = "wrist", slots = { 9 } },
	{ name = "hands", slots = { 10 } }, { name = "waist", slots = { 6 } }, { name = "legs", slots = { 7 } },
	{ name = "feet", slots = { 8 } }, { name = "finger", slots = { 11, 12 } },
}
local LAST_BAG = 4

local announced = {}

local function currentWeights()
	local role, primary
	local spec = C_SpecializationInfo.GetSpecialization()
	if spec then
		local _
		_, _, _, _, role, primary = C_SpecializationInfo.GetSpecializationInfo(spec)
	end
	if not PRIMARY_KEY[primary] then
		local _, class = UnitClass("player")
		primary = CLASS_PRIMARY[class] or 1
	end
	local base
	if role == "TANK" then
		base = TANK
	elseif role == "HEALER" then
		base = HEALER
	elseif primary == 4 then
		base = CASTER
	else
		base = MELEE
	end
	local weights = CopyTable(base)
	local extra = PRIMARY_WEIGHT[role or "DAMAGER"]
	if extra and primary ~= 4 then
		weights[PRIMARY_KEY[primary]] = extra
	end
	return weights, role
end

-- Returns nil when the item is not in the client's cache yet.
local function score(link, weights)
	local stats = C_Item.GetItemStats(link)
	if not stats then
		return nil
	end
	local total = 0
	for key, value in pairs(stats) do
		total = total + (weights[key] or 0) * value
	end
	return total
end

-- Bag items that beat what is worn, as { slot, link } in a fixed slot order.
function ns.GearSuggestions()
	local weights = currentWeights()
	local candidates = {}
	for bag = 0, LAST_BAG do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local link = C_Container.GetContainerItemLink(bag, slot)
			if link then
				local itemID, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
				local group = GROUP_OF[equipLoc]
				-- Unbound items are left out: equipping one asks to bind it, and it may be meant for selling.
				if group and C_PlayerInfo.CanUseItem(itemID) and C_Item.IsBound(ItemLocation:CreateFromBagAndSlot(bag, slot)) then
					local value = score(link, weights)
					if value then
						candidates[group] = candidates[group] or {}
						table.insert(candidates[group], { link = link, id = itemID, score = value })
					end
				end
			end
		end
	end

	local result = {}
	for _, group in ipairs(GROUPS) do
		local list = candidates[group.name]
		if list then
			table.sort(list, function(a, b) return a.score > b.score end)
			local worn, ids, taken = {}, {}, {}
			for _, slot in ipairs(group.slots) do
				local link = GetInventoryItemLink("player", slot)
				-- A worn item that is not cached yet is never replaced on a guess. An empty slot takes anything.
				worn[slot] = link and (score(link, weights) or math.huge) or -1
				ids[slot] = link and C_Item.GetItemInfoInstant(link)
			end
			for _, item in ipairs(list) do
				local weakest
				for _, slot in ipairs(group.slots) do
					if not taken[slot] and (not weakest or worn[slot] < worn[weakest]) then
						weakest = slot
					end
				end
				if not weakest or item.score <= worn[weakest] then
					break
				end
				-- Two of the same ring are never suggested, since many rings are unique-equipped.
				local duplicate = false
				for _, slot in ipairs(group.slots) do
					duplicate = duplicate or (slot ~= weakest and ids[slot] == item.id)
				end
				if not duplicate then
					taken[weakest], ids[weakest] = true, item.id
					result[#result + 1] = { slot = weakest, link = item.link }
				end
			end
		end
	end
	return result
end

-- /ksui stats: shows how worn gear scores and which stat keys have no weight,
-- so the assumed key names can be checked against what the game returns.
function ns.PrintGearStats()
	local weights, role = currentWeights()
	print("검성UI 장비 점수 (" .. (role or "전문화 없음") .. "):")
	local seen, unknown = {}, {}
	for _, group in ipairs(GROUPS) do
		for _, slot in ipairs(group.slots) do
			local link = GetInventoryItemLink("player", slot)
			if link then
				local value = score(link, weights)
				print("  " .. link .. " " .. (value and string.format("%.1f", value) or "정보 없음"))
				for key in pairs(C_Item.GetItemStats(link) or {}) do
					if not weights[key] and not seen[key] then
						seen[key] = true
						unknown[#unknown + 1] = key
					end
				end
			end
		end
	end
	table.sort(unknown)
	print("  가중치 없는 능력치: " .. (#unknown > 0 and table.concat(unknown, ", ") or "없음"))
end

function ns.OnBagUpdate()
	if not ns.db.gearSuggest then
		return
	end
	local fresh = {}
	for _, item in ipairs(ns.GearSuggestions()) do
		if not announced[item.link] then
			announced[item.link] = true
			fresh[#fresh + 1] = item.link
		end
	end
	if #fresh > 0 then
		print("검성UI: 더 좋은 장비 - " .. table.concat(fresh, ", ") .. ". 캐릭터 창의 '추천 장비 착용'으로 입을 수 있습니다.")
	end
end

function ns.EquipBest()
	if InCombatLockdown() then
		print("검성UI: 전투 중에는 장비를 바꿀 수 없습니다.")
		return
	end
	local list = ns.GearSuggestions()
	if #list == 0 then
		print("검성UI: 지금 입은 장비가 가장 좋습니다.")
		return
	end
	local links = {}
	for _, item in ipairs(list) do
		C_Item.EquipItemByName(item.link, item.slot)
		links[#links + 1] = item.link
	end
	print("검성UI: 착용 요청 - " .. table.concat(links, ", "))
end

-- Shown under the character window, only while the character tab is open.
function ns.InitGear()
	local button = CreateFrame("Button", nil, PaperDollFrame, "UIPanelButtonTemplate")
	button:SetSize(140, 24)
	button:SetPoint("TOPLEFT", CharacterFrame, "BOTTOMLEFT", 0, -4)
	button:SetText("추천 장비 착용")
	button:SetScript("OnClick", ns.EquipBest)
	ns.gearButton = button
end
