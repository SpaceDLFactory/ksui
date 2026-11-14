local addonName, ns = ...

local ACTION_BARS = {
	"ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarLeftButton",
	"MultiBarRightButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}

function ns.ForEachActionButton(callback)
	for _, prefix in ipairs(ACTION_BARS) do
		for i = 1, 12 do
			local button = _G[prefix .. i]
			if button then
				callback(button)
			end
		end
	end
end

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	KSUIDB = KSUIDB or {}
	ns.db = KSUIDB
	ns.RegisterOptions()
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("READY_CHECK")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
events:RegisterUnitEvent("UNIT_FACTION", "target")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		ns.InitSkin()
		ns.InitMinimap()
		ns.InitCombat()
		ns.InitInterrupt()
		ns.RefreshSkin()
		ns.RefreshCooldowns()
		ns.RefreshCVars()
		ns.RefreshBarFade()
		ns.InitGear()
		ns.RefreshTracking()
	elseif event == "BAG_UPDATE_DELAYED" then
		ns.OnBagUpdate()
	elseif event == "LEARNED_SPELL_IN_SKILL_LINE" then
		ns.RefreshTracking()
	elseif event == "PLAYER_TARGET_CHANGED" then
		ns.RefreshTargetColor()
		ns.RefreshBarFade()
	elseif event == "UNIT_FACTION" then
		ns.RefreshTargetColor()
	elseif event == "PLAYER_REGEN_DISABLED" then
		ns.SetCombat(true)
	elseif event == "MERCHANT_SHOW" then
		ns.OnMerchantShow()
	elseif event == "READY_CHECK" then
		ns.OnReadyCheck()
	else
		ns.RefreshCooldowns()
		ns.RefreshCVars()
		ns.SetCombat(false)
	end
end)

SLASH_KSUI1 = "/ksui"
SlashCmdList.KSUI = function(message)
	if message == "layout" then
		ns.ApplyLayout()
	elseif message == "stats" then
		ns.PrintGearStats()
	else
		Settings.OpenToCategory(ns.category:GetID())
	end
end
