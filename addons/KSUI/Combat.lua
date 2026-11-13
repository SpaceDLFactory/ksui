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

-- Your interrupt sits beside the target frame with the target's cast bar after it. Blizzard's own target cast bar
-- can't be moved by an addon once the target has had auras, so KSUI draws its own and keeps Blizzard's at zero alpha.
-- In instances the cast and cooldown values can be secret, so they only go to setters that accept secrets and are
-- never tested here.
local INTERRUPT_SIZE = 36
local CAST_BAR_WIDTH, CAST_BAR_HEIGHT = 160, 18
local CAN_INTERRUPT = CreateColor(1, 0.7, 0)
local SHIELDED = CreateColor(0.6, 0.6, 0.6)
local CAST_EVENTS = {
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP",
	"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
	-- Pushback and channel changes move the end time.
	"UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_EMPOWER_UPDATE",
}

-- A stun stands in until the class learns a real interrupt, since it stops casts too. Matched by name so any rank works.
local STAND_IN = { PALADIN = 853 } -- Hammer of Justice

local interrupt, interruptSlot, castBar

local function readCast()
	local name, text, texture, startMs, endMs, _, _, notInterruptible = UnitCastingInfo("target")
	if not issecretvalue(name) and name == nil then
		name, text, texture, startMs, endMs, _, notInterruptible = UnitChannelInfo("target")
	end
	return name, text, texture, startMs, endMs, notInterruptible
end

-- The bar fills from the cast's start to its end time; OnUpdate only feeds it the clock, so no secret is computed on.
local function refreshCast()
	local name, text, texture, startMs, endMs, notInterruptible = readCast()
	if not ns.db.interruptHelper or (not issecretvalue(name) and name == nil) then
		interrupt.glow:SetAlpha(0)
		castBar:Hide()
		return
	end
	castBar.icon:SetTexture(texture)
	castBar.text:SetText(text)
	castBar:SetMinMaxValues(startMs, endMs)
	castBar:SetValue(GetTime() * 1000)
	local fill = castBar:GetStatusBarTexture()
	if issecretvalue(notInterruptible) then
		interrupt.glow:SetAlphaFromBoolean(notInterruptible, 0, 1)
		fill:SetVertexColorFromBoolean(notInterruptible, SHIELDED, CAN_INTERRUPT)
	else
		interrupt.glow:SetAlpha(notInterruptible and 0 or 1)
		local color = notInterruptible and SHIELDED or CAN_INTERRUPT
		fill:SetVertexColor(color.r, color.g, color.b)
	end
	castBar:Show()
end

local function refreshInterruptCooldown()
	if interruptSlot then
		interrupt.cooldown:SetCooldownFromDurationObject(C_ActionBar.GetActionCooldownDuration(interruptSlot, true))
	end
end

-- Blizzard sets the alpha back to 1 at every cast start. Its fade-out only plays above zero alpha, so none shows.
-- An interrupted cast instead plays a hold at full alpha, which is stopped.
local function hideBlizzardCastBar(bar)
	if ns.db.interruptHelper then
		if bar.HoldFadeOutAnim then
			bar.HoldFadeOutAnim:Stop()
		end
		bar:SetAlpha(0)
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
	refreshCast()
	TargetFrame.spellbar:SetAlpha(ns.db.interruptHelper and 0 or 1)
end

-- Both are children of the target frame, so they hide along with it when there is no target.
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

	-- Anchored to the interrupt even when that is hidden, so the bar keeps one spot.
	castBar = CreateFrame("StatusBar", nil, TargetFrame)
	castBar:SetSize(CAST_BAR_WIDTH, CAST_BAR_HEIGHT)
	castBar:SetPoint("LEFT", interrupt, "RIGHT", CAST_BAR_HEIGHT + 8, 0)
	castBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	castBar.background = castBar:CreateTexture(nil, "BACKGROUND")
	castBar.background:SetAllPoints()
	castBar.background:SetColorTexture(0, 0, 0, 0.6)
	castBar.icon = castBar:CreateTexture(nil, "ARTWORK")
	castBar.icon:SetSize(CAST_BAR_HEIGHT, CAST_BAR_HEIGHT)
	castBar.icon:SetPoint("RIGHT", castBar, "LEFT", -4, 0)
	castBar.text = castBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	castBar.text:SetPoint("CENTER")
	castBar:SetScript("OnUpdate", function(self)
		self:SetValue(GetTime() * 1000)
	end)
	castBar:Hide()
	hooksecurefunc(TargetFrame.spellbar, "ApplyAlpha", hideBlizzardCastBar)
	hooksecurefunc(TargetFrame.spellbar, "PlayInterruptAnims", hideBlizzardCastBar)

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
			refreshCast()
		end
	end)
	ns.RefreshInterrupt()
end
