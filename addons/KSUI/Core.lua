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

-- The screen KSUI was tuned on: 4K at the automatic UI scale's floor of 0.64, so 768 / 0.64 = 1200 UI units tall.
ns.REFERENCE_WIDTH, ns.REFERENCE_HEIGHT = 1200 * 16 / 9, 1200
local POSITIONS_VERSION = 2
-- Old UI-unit key, new share key, and the reference length it is a share of.
local OLD_POSITIONS = {
	{ "frameX", "frameXPct", ns.REFERENCE_WIDTH }, { "frameY", "frameYPct", ns.REFERENCE_HEIGHT },
	{ "groupX", "groupXPct", ns.REFERENCE_WIDTH }, { "groupTopGap", "groupTopPct", ns.REFERENCE_HEIGHT },
}

-- Positions used to be saved in UI units; they become shares of the reference screen, so nothing moves on it.
-- UIParent is still 1365 x 768 when saved variables load, before the UI scale applies, so nothing is measured then.
-- Version 1 did measure, which made every share 1200 / 768 times too large; those are scaled back once.
local function convertPositions(db)
	local version = db.positionsVersion
	for _, entry in ipairs(OLD_POSITIONS) do
		local old, key, length = entry[1], entry[2], entry[3]
		if db[old] ~= nil and db[key] == nil then
			db[key] = db[old] / length * 100
		elseif version == nil and db[key] ~= nil then
			db[key] = db[key] * 768 / ns.REFERENCE_HEIGHT
		end
		db[old] = nil
	end
	db.positionsVersion = POSITIONS_VERSION
end

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	KSUIDB = KSUIDB or {}
	convertPositions(KSUIDB)
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
		ns.PlaceAlerts()
		ns.InitQuestGuide()
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
