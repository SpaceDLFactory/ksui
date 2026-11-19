-- Party threat on your target, above the damage meter. Alone you only need the target frame's number, so this shows
-- in a group. Where threat values are restricted they arrive as secrets: they only go to setters that accept them,
-- and the rows keep party order instead of being sorted.

local _, ns = ...

local HEADER_HEIGHT, ROW_HEIGHT = 18, 16
local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local UNITS = { "player", "party1", "party2", "party3", "party4" }
local EVENTS = {
	"UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE",
}

local TOOLTIP_GAP = 10

local threat = CreateFrame("Frame", "KSUIThreatMeter", UIParent, "BackdropTemplate")

local function makeRow(index)
	local bar = CreateFrame("StatusBar", nil, threat)
	bar:SetStatusBarTexture(FLAT)
	bar:SetMinMaxValues(0, 100)
	bar:SetHeight(ROW_HEIGHT)
	bar:SetPoint("TOPLEFT", 1, -HEADER_HEIGHT - (index - 1) * ROW_HEIGHT)
	bar:SetPoint("RIGHT", -1, 0)
	bar.name = ns.OutlinedText(bar)
	bar.name:SetPoint("LEFT", 4, 0)
	bar.value = ns.OutlinedText(bar)
	bar.value:SetPoint("RIGHT", -4, 0)
	-- A white edge on the left marks whoever the target is attacking.
	bar.tanking = bar:CreateTexture(nil, "OVERLAY")
	bar.tanking:SetColorTexture(1, 1, 1)
	bar.tanking:SetWidth(3)
	bar.tanking:SetPoint("TOPLEFT")
	bar.tanking:SetPoint("BOTTOMLEFT")
	return bar
end

-- Each entry: unit, isTanking, scaled percentage. Units the target has no threat table entry for are left out.
local function readThreat()
	local entries, anySecret = {}, false
	for _, unit in ipairs(UNITS) do
		if UnitExists(unit) then
			local isTanking, _, percent = UnitDetailedThreatSituation(unit, "target")
			if issecretvalue(percent) then
				anySecret = true
			end
			if issecretvalue(percent) or percent ~= nil then
				entries[#entries + 1] = { unit = unit, isTanking = isTanking, percent = percent }
			end
		end
	end
	if not anySecret then
		table.sort(entries, function(a, b) return a.percent > b.percent end)
	end
	return entries
end

function ns.RefreshThreat()
	local active = ns.db.threatMeter and IsInGroup() and UnitExists("target") and UnitCanAttack("player", "target")
	threat:SetShown(active)
	if not active then
		return
	end
	local entries = readThreat()
	for i, bar in ipairs(threat.rows) do
		local entry = entries[i]
		bar:SetShown(entry ~= nil)
		if entry then
			bar:SetStatusBarColor(ns.UnitColor(entry.unit))
			bar:SetValue(entry.percent)
			-- Forever names carry a surname, joined as on the unit frames; either part may be secret.
			local name, surname = UnitName(entry.unit)
			if issecretvalue(surname) or surname then
				bar.name:SetFormattedText("%s%s%s", name, Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR,
					surname)
			else
				bar.name:SetText(name)
			end
			bar.value:SetFormattedText("%.0f%%", entry.percent)
			if issecretvalue(entry.isTanking) then
				bar.tanking:SetAlphaFromBoolean(entry.isTanking, 1, 0)
			else
				bar.tanking:SetAlpha(entry.isTanking and 1 or 0)
			end
		end
	end
	threat:SetHeight(HEADER_HEIGHT + #entries * ROW_HEIGHT + 1)
end

-- Tooltips for whatever is under the mouse open on the quest tracker, where the meters now sit, so they move above
-- the top meter on show. With no meter showing they stay where Blizzard put them.
local function placeTooltip(tooltip)
	local top = threat:IsShown() and threat or KSUIDamageMeter:IsShown() and KSUIDamageMeter
	if top then
		tooltip:ClearAllPoints()
		tooltip:SetPoint("BOTTOMRIGHT", top, "TOPRIGHT", 0, TOOLTIP_GAP)
	end
end

function ns.InitThreat()
	hooksecurefunc("GameTooltip_SetDefaultAnchor", placeTooltip)
	threat:SetPoint("BOTTOMLEFT", KSUIDamageMeter, "TOPLEFT", 0, 6)
	threat:SetPoint("BOTTOMRIGHT", KSUIDamageMeter, "TOPRIGHT", 0, 6)
	threat:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
	threat:SetBackdropColor(0, 0, 0, 0.6)
	threat:SetBackdropBorderColor(0, 0, 0, 1)
	threat.title = ns.OutlinedText(threat)
	threat.title:SetPoint("TOPLEFT", 4, -3)
	threat.title:SetText(ns.T("위협", "Threat"))

	threat.rows = {}
	for i = 1, #UNITS do
		threat.rows[i] = makeRow(i)
	end

	local events = CreateFrame("Frame")
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	events:SetScript("OnEvent", ns.RefreshThreat)
	ns.RefreshThreat()
end
