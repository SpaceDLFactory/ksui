-- Recolors and fades Blizzard's action buttons. Neither touches protected state, so both work in combat.

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
