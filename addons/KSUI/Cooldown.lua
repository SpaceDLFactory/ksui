-- Uses the client's own countdown, because addons cannot read cooldown times in combat.

local _, ns = ...

local FONT_NAME = "KSUICooldownFont"
local font = CreateFont(FONT_NAME)

function ns.RefreshCooldowns()
	font:SetFont(STANDARD_TEXT_FONT, ns.db.cooldownFontSize, "OUTLINE")
	-- A change made during combat is applied on PLAYER_REGEN_ENABLED.
	if not InCombatLockdown() then
		SetCVar("countdownForCooldowns", ns.db.cooldownNumbers and "1" or "0")
	end
	ns.ForEachActionButton(function(button)
		button.cooldown:SetCountdownFont(FONT_NAME)
	end)
end
