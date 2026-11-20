-- Shields and heals over time as small icons, whoever cast them, on KSUI's party rows, Blizzard's own party frames and
-- Blizzard's raid frames (also used for raid-style party frames). Forever reports other players' auras with no
-- duration and ignores the aura filters, so they are picked by name from this list (Classic rank 1 spell IDs; any
-- rank matches by name), which leaves the long group buffs out. The time left shows as a cooldown swipe when the game
-- gives one. When an aura's name is secret, as in instances, it is left out.

local _, ns = ...

local COUNT = 4
local SHORT_BUFF_SPELLS = {
	17, 139, 552, -- Power Word: Shield, Renew, Abolish Disease
	774, 8936, 2893, -- Rejuvenation, Regrowth, Abolish Poison
	1022, -- Blessing of Protection
}
local RAID_SIZE = 11
local shortBuffNames

local function isShortBuff(aura)
	if not shortBuffNames then
		shortBuffNames = {}
		for _, spell in ipairs(SHORT_BUFF_SPELLS) do
			local name = C_Spell.GetSpellName(spell)
			if name then
				shortBuffNames[name] = true
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
	return shortBuffNames[name] == true
end

-- Icons in a row from the given corner of the parent, growing towards "RIGHT" or "LEFT", above the parent's children
-- up to the given frame level.
function ns.CreateShortBuffIcons(parent, size, corner, x, y, grow, level)
	local icons = {}
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
				icon.cooldown:Clear()
			end
		end
	end
end

-- Blizzard's raid frames, and its party frames in raid style, are named CompactRaid... and CompactParty...; the same
-- code also draws frames that addons may not touch, which are left alone.
local compactFrames = {}

local function isGroupFrame(frame)
	if frame:IsForbidden() then
		return false
	end
	local name = frame:GetName()
	return name ~= nil and (name:find("^CompactRaid") ~= nil or name:find("^CompactParty") ~= nil)
end

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
		local all = event == "GROUP_ROSTER_UPDATE" or issecretvalue(unit)
		for frame, icons in pairs(compactFrames) do
			local shown = frame.displayedUnit
			if all or shown == unit then
				ns.UpdateShortBuffIcons(icons, shown)
			end
		end
	end)
end
