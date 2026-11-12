-- Recolors and fades Blizzard's action buttons and shows your interrupt by the target. None of it calls protected
-- functions on secure frames.

local _, ns = ...

local OUT_OF_RANGE = { 0.85, 0.15, 0.15 }
local BARS = {
	"MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
	"MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar",
}

local buttons, outOfRange = {}, {}
local inCombat = false

-- Blizzard's UpdateUsable colors, with out of range on top.
local function colorIcon(button)
	if ns.db.rangeColor and outOfRange[button] then
		button.icon:SetVertexColor(OUT_OF_RANGE[1], OUT_OF_RANGE[2], OUT_OF_RANGE[3])
		return
	end
	local isUsable, notEnoughMana = C_ActionBar.IsUsableAction(button.action)
	if isUsable then
		button.icon:SetVertexColor(1, 1, 1)
	elseif notEnoughMana then
		button.icon:SetVertexColor(0.5, 0.5, 1)
	else
		button.icon:SetVertexColor(0.4, 0.4, 0.4)
	end
end

function ns.InitCombat()
	ns.ForEachActionButton(function(button)
		buttons[button] = true
		-- Blizzard resets the icon color whenever usability changes, so red goes back on afterwards.
		hooksecurefunc(button, "UpdateUsable", function()
			if ns.db.rangeColor and outOfRange[button] then
				colorIcon(button)
			end
		end)
	end)
	-- The pet bar shares this function, but only action buttons are recolored.
	hooksecurefunc("ActionButton_UpdateRangeIndicator", function(button, checksRange, inRange)
		if not buttons[button] then
			return
		end
		local now = checksRange and not inRange or nil
		if now ~= outOfRange[button] then
			outOfRange[button] = now
			colorIcon(button)
		end
	end)
	inCombat = UnitAffectingCombat("player")
end

function ns.RefreshRange()
	for button in pairs(buttons) do
		colorIcon(button)
	end
end

function ns.SetCombat(state)
	inCombat = state
	ns.RefreshBarFade()
end

-- Bars stay fully visible in combat or with a target, when you are about to press them.
function ns.RefreshBarFade()
	local alpha = 1
	if ns.db.fadeBars and not inCombat and not UnitExists("target") then
		alpha = ns.db.fadeAlpha
	end
	for _, name in ipairs(BARS) do
		local bar = _G[name]
		if bar then
			bar:SetAlpha(alpha)
		end
	end
end

-- The target's cast bar sits beside the target frame with your interrupt in front of it. In instances the cast and
-- cooldown values can be secret, so they only go to setters that accept secrets and are never tested here.
local INTERRUPT_SIZE = 36
local CAST_BAR_GAP = 28
local CAST_EVENTS = {
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP",
	"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

-- A stun stands in until the class learns a real interrupt, since it stops casts too. Matched by name so any rank works.
local STAND_IN = { PALADIN = 853 } -- Hammer of Justice

local interrupt, interruptSlot

-- Lit while the target casts something that can be interrupted.
local function refreshGlow()
	local name, _, _, _, _, _, _, notInterruptible = UnitCastingInfo("target")
	if not issecretvalue(name) and name == nil then
		name, _, _, _, _, _, notInterruptible = UnitChannelInfo("target")
	end
	if not issecretvalue(name) and name == nil then
		interrupt.glow:SetAlpha(0)
	elseif issecretvalue(notInterruptible) then
		interrupt.glow:SetAlphaFromBoolean(notInterruptible, 0, 1)
	else
		interrupt.glow:SetAlpha(notInterruptible and 0 or 1)
	end
end

local function refreshInterruptCooldown()
	if interruptSlot then
		interrupt.cooldown:SetCooldownFromDurationObject(C_ActionBar.GetActionCooldownDuration(interruptSlot, true))
	end
end

local function placeCastBar(castBar)
	if ns.db.interruptHelper then
		castBar:ClearAllPoints()
		castBar:SetPoint("LEFT", interrupt, "RIGHT", CAST_BAR_GAP, 0)
	end
end

local function findSlot(matches)
	local found
	ns.ForEachActionButton(function(button)
		local slot = button.action
		if not found and slot and C_ActionBar.HasAction(slot) and matches(slot) then
			found = slot
		end
	end)
	return found
end

-- The interrupt is whichever spell on your bars the game marks as one, so no list of interrupts is kept.
function ns.RefreshInterrupt()
	interruptSlot = findSlot(C_ActionBar.IsInterruptAction)
	local _, class = UnitClass("player")
	local standIn = STAND_IN[class] and C_Spell.GetSpellName(STAND_IN[class])
	if not interruptSlot and standIn then
		interruptSlot = findSlot(function(slot)
			local kind, id = GetActionInfo(slot)
			return kind == "spell" and C_Spell.GetSpellName(id) == standIn
		end)
	end
	interrupt:SetShown(ns.db.interruptHelper and interruptSlot ~= nil)
	if interruptSlot then
		interrupt.icon:SetTexture(C_ActionBar.GetActionTexture(interruptSlot))
		refreshInterruptCooldown()
	end
	refreshGlow()
	if ns.db.interruptHelper then
		placeCastBar(TargetFrame.spellbar)
	else
		TargetFrame.spellbar:AdjustPosition()
	end
end

-- A child of the target frame, so it hides along with it when there is no target.
function ns.InitInterrupt()
	interrupt = CreateFrame("Frame", nil, TargetFrame)
	interrupt:SetSize(INTERRUPT_SIZE, INTERRUPT_SIZE)
	interrupt:SetPoint("LEFT", TargetFrame, "RIGHT", 4, 0)
	interrupt.glow = interrupt:CreateTexture(nil, "BACKGROUND")
	interrupt.glow:SetPoint("TOPLEFT", -3, 3)
	interrupt.glow:SetPoint("BOTTOMRIGHT", 3, -3)
	interrupt.glow:SetColorTexture(1, 0.8, 0.1)
	interrupt.icon = interrupt:CreateTexture(nil, "ARTWORK")
	interrupt.icon:SetAllPoints()
	interrupt.cooldown = CreateFrame("Cooldown", nil, interrupt, "CooldownFrameTemplate")
	interrupt.cooldown:SetAllPoints()
	hooksecurefunc(TargetFrame.spellbar, "AdjustPosition", placeCastBar)

	local events = CreateFrame("Frame")
	for _, event in ipairs(CAST_EVENTS) do
		events:RegisterUnitEvent(event, "target")
	end
	events:RegisterEvent("PLAYER_TARGET_CHANGED")
	-- Paging and stance changes swap which actions the buttons hold.
	events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
	events:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
	events:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
	events:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
	events:SetScript("OnEvent", function(_, event)
		if event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_BONUS_ACTIONBAR" then
			ns.RefreshInterrupt()
		elseif event == "ACTIONBAR_UPDATE_COOLDOWN" then
			refreshInterruptCooldown()
		else
			refreshGlow()
		end
	end)
	ns.RefreshInterrupt()
end
