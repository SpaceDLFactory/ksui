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
-- Blizzard's "interface action failed because of an AddOn" message names neither the addon nor the call; these do.
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
local MAX_BLOCKED_LOG = 20

-- Kept in saved variables too, so a blocked call can be read after logging out.
local function noteBlocked(event, addon, call)
	if addon ~= addonName then
		return
	end
	local entry = date("%m-%d %H:%M:%S") .. " " .. event .. " " .. tostring(call)
		.. (InCombatLockdown() and " (전투 중)" or "")
	print("검성UI: 막힌 동작 - " .. entry)
	local log = ns.db.blockedLog or {}
	table.insert(log, entry)
	while #log > MAX_BLOCKED_LOG do
		table.remove(log, 1)
	end
	ns.db.blockedLog = log
end

events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		noteBlocked(event, ...)
	elseif event == "PLAYER_LOGIN" then
		ns.InitSkin()
		ns.InitUnitFrames()
		ns.InitNameplates()
		ns.InitMeter()
		ns.InitThreat()
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
	elseif message == "reset" then
		ns.ResetMeter()
	elseif message == "stats" then
		ns.PrintGearStats()
	else
		Settings.OpenToCategory(ns.category:GetID())
	end
end
