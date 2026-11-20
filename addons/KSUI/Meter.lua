-- KSUI's damage meter, drawn from Blizzard's C_DamageMeter data; the game no longer hands addons the combat log.
-- In combat the amounts and names arrive as secrets, so they only go to setters that accept secrets and the sources
-- keep the order Blizzard sends. Blizzard's own meter window is hidden by the layout.

local _, ns = ...

local HEADER_HEIGHT, ROW_HEIGHT, ROWS = 18, 16, 8
local DETAIL_WIDTH, DETAIL_ROWS, DETAIL_GAP = 280, 10, 6
-- Solo, every pull is its own fight, so the menu keeps to the latest ones.
local MENU_FIGHTS = 15
local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local UNKNOWN = { r = 0.6, g = 0.6, b = 0.6 }
-- Left-click on the title cycles these; right-click picks the fight: the current one, all of them, or one of the past
-- fights Blizzard keeps. The reset button on the title's right clears every fight. Clicking a row opens that unit's
-- spells beside the meter.
local MODES = {
	{ type = Enum.DamageMeterType.DamageDone, label = ns.T("피해량", "Damage") },
	{ type = Enum.DamageMeterType.HealingDone, label = ns.T("치유량", "Healing") },
	{ type = Enum.DamageMeterType.DamageTaken, label = ns.T("받은 피해", "Damage taken") },
}
local CURRENT = { type = Enum.DamageMeterSessionType.Current, label = ns.T("현재", "Current") }
local OVERALL = { type = Enum.DamageMeterSessionType.Overall, label = ns.T("전체", "Overall") }
local EVENTS = {
	"DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET",
	-- A session that was locked during combat can be read again afterwards.
	"PLAYER_REGEN_ENABLED",
	-- A new fight brings the meter back from a past one.
	"PLAYER_REGEN_DISABLED",
}

local mode = 1
-- Either CURRENT, OVERALL or a past fight: { id, label }.
local selected = CURRENT
-- The unit whose spells the detail window shows: { guid, creatureID, name }.
local detailSource
-- When KSUI first heard of each fight, by session id. Blizzard keeps no start time, and fights from before a reload
-- have none.
local startedAt = {}

-- Named so the threat meter can stack on it.
local meter = CreateFrame("Frame", "KSUIDamageMeter", UIParent, "BackdropTemplate")

local detail = CreateFrame("Frame", nil, meter, "BackdropTemplate")

local function makeRow(parent, index)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(FLAT)
	bar:SetHeight(ROW_HEIGHT)
	bar:SetPoint("TOPLEFT", 1, -HEADER_HEIGHT - (index - 1) * ROW_HEIGHT)
	bar:SetPoint("RIGHT", -1, 0)
	bar.name = ns.OutlinedText(bar)
	bar.name:SetPoint("LEFT", 4, 0)
	bar.value = ns.OutlinedText(bar)
	bar.value:SetPoint("RIGHT", -4, 0)
	return bar
end

local function readSession()
	if selected.id then
		return C_DamageMeter.GetCombatSessionFromID(selected.id, MODES[mode].type)
	end
	return C_DamageMeter.GetCombatSessionFromType(selected.type, MODES[mode].type)
end

local function readSource(source)
	if selected.id then
		return C_DamageMeter.GetCombatSessionSourceFromID(selected.id, MODES[mode].type, source.guid, source.creatureID)
	end
	return C_DamageMeter.GetCombatSessionSourceFromType(selected.type, MODES[mode].type, source.guid, source.creatureID)
end

-- The spells of one unit, in the order Blizzard sends them.
local function refreshDetail()
	if not detailSource then
		detail:Hide()
		return
	end
	detail:Show()
	detail.title:SetFormattedText("%s - %s", detailSource.name, MODES[mode].label)
	local data = readSource(detailSource)
	if not canaccesstable(data) or not canaccesstable(data.combatSpells) then
		return
	end
	local spells, total = data.combatSpells, data.totalAmount
	local shown = math.min(#spells, DETAIL_ROWS)
	for i, bar in ipairs(detail.rows) do
		local spell = spells[i]
		bar:SetShown(i <= shown)
		if i <= shown and canaccesstable(spell) then
			bar:SetStatusBarColor(detailSource.color.r, detailSource.color.g, detailSource.color.b)
			bar:SetMinMaxValues(0, data.maxAmount)
			bar:SetValue(spell.totalAmount)
			-- Only the first of the three icon returns; the others would land in SetTexture's wrap-mode arguments.
			bar.icon:SetTexture((C_Spell.GetSpellTexture(spell.spellID)))
			bar.name:SetText(C_Spell.GetSpellName(spell.spellID))
			-- A share needs arithmetic, which secrets don't allow, so it only shows outside combat.
			if issecretvalue(spell.totalAmount) or issecretvalue(total) or total <= 0 then
				bar.value:SetFormattedText("%s (%.1f)", AbbreviateNumbers(spell.totalAmount), spell.amountPerSecond)
			else
				bar.value:SetFormattedText("%s (%.1f) %.0f%%", AbbreviateNumbers(spell.totalAmount), spell.amountPerSecond,
					spell.totalAmount / total * 100)
			end
		end
	end
	detail:SetHeight(HEADER_HEIGHT + shown * ROW_HEIGHT + 1)
end

-- Asking for one unit's spells takes its GUID, which can't be passed on while it is secret in combat.
local function openDetail(row)
	local source = row.source
	if not source then
		return
	end
	if issecretvalue(source.guid) or issecretvalue(source.creatureID) then
		print(ns.T("검성UI: 전투 중에는 스킬 상세를 열 수 없습니다. 전투가 끝나면 다시 눌러주세요.",
			"KSUI: spell details can't open in combat. Click again when the fight is over."))
		return
	end
	if detailSource and detailSource.guid == source.guid and detailSource.creatureID == source.creatureID then
		detailSource = nil
	else
		detailSource = source
	end
	refreshDetail()
end

local function sessionMenu(owner, root)
	local function isSelected(option)
		return selected.id == option.id and selected.type == option.type
	end
	local function choose(option)
		selected = option
		ns.RefreshMeter()
	end
	root:CreateTitle(ns.T("전투 선택", "Choose a fight"))
	-- Newest first; ids grow with each fight.
	local fights = C_DamageMeter.GetAvailableCombatSessions()
	table.sort(fights, function(a, b) return a.sessionID > b.sessionID end)
	for i = 1, math.min(#fights, MENU_FIGHTS) do
		local past = fights[i]
		-- Blizzard names a fight after its main enemy.
		local label = past.name and past.name ~= "" and past.name or (ns.T("전투 ", "Fight ") .. past.sessionID)
		if past.durationSeconds then
			label = ("%s [%s]"):format(label, SecondsToClock(past.durationSeconds))
		end
		if startedAt[past.sessionID] then
			label = startedAt[past.sessionID] .. " " .. label
		end
		root:CreateRadio(label, isSelected, choose, { id = past.sessionID, label = label })
	end
	root:CreateDivider()
	root:CreateRadio(CURRENT.label, isSelected, choose, CURRENT)
	root:CreateRadio(OVERALL.label, isSelected, choose, OVERALL)
end

function ns.RefreshMeter()
	local available = C_DamageMeter.IsDamageMeterAvailable()
	meter:SetShown(ns.db.damageMeter and available)
	if not meter:IsShown() then
		return
	end
	-- A past fight Blizzard has dropped (a reset, a new dungeon) would leave an empty meter; back to the current one.
	if selected.id then
		local kept = false
		for _, past in ipairs(C_DamageMeter.GetAvailableCombatSessions()) do
			kept = kept or past.sessionID == selected.id
		end
		if not kept then
			selected = CURRENT
			detailSource = nil
		end
	end
	meter.title:SetFormattedText("%s (%s)", MODES[mode].label, selected.label)
	local data = readSession()
	-- In combat the whole session may come back locked; the last picture stays until it can be read.
	if not canaccesstable(data) or not canaccesstable(data.combatSources) then
		return
	end
	local sources = data.combatSources
	local shown = math.min(#sources, ROWS)
	for i, bar in ipairs(meter.rows) do
		local source = sources[i]
		bar:SetShown(i <= shown)
		-- A locked row keeps what it showed.
		if i <= shown and canaccesstable(source) then
			-- The class is never secret; creatures have none and stay gray.
			local color = RAID_CLASS_COLORS[source.classFilename] or UNKNOWN
			bar:SetStatusBarColor(color.r, color.g, color.b)
			bar:SetMinMaxValues(0, data.maxAmount)
			bar:SetValue(source.totalAmount)
			bar.name:SetFormattedText("%d. %s", i, source.name)
			bar.source = { guid = source.sourceGUID, creatureID = source.sourceCreatureID, name = source.name, color = color }
			-- AbbreviateNumbers leaves anything under a thousand alone, so the per-second figure gets one decimal like
			-- Blizzard's meter.
			bar.value:SetFormattedText("%s (%.1f)", AbbreviateNumbers(source.totalAmount), source.amountPerSecond)
		end
	end
	meter:SetHeight(HEADER_HEIGHT + shown * ROW_HEIGHT + 1)
	refreshDetail()
end

-- The past fights are gone afterwards, so the current one is shown.
function ns.ResetMeter()
	selected = CURRENT
	detailSource = nil
	C_DamageMeter.ResetAllCombatSessions()
	ns.RefreshMeter()
end

function ns.InitMeter()
	-- As wide as the quest tracker it sits on, following it if Edit Mode resizes it.
	meter:SetPoint("BOTTOMLEFT", ObjectiveTrackerFrame, "TOPLEFT", 0, 10)
	meter:SetPoint("BOTTOMRIGHT", ObjectiveTrackerFrame, "TOPRIGHT", 0, 10)
	meter:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
	meter:SetBackdropColor(0, 0, 0, 0.6)
	meter:SetBackdropBorderColor(0, 0, 0, 1)

	local header = CreateFrame("Button", nil, meter)
	header:SetHeight(HEADER_HEIGHT)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	header:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			MenuUtil.CreateContextMenu(self, sessionMenu)
			return
		end
		mode = mode % #MODES + 1
		ns.RefreshMeter()
	end)
	meter.title = ns.OutlinedText(header)
	meter.title:SetPoint("LEFT", 4, 0)

	local reset = CreateFrame("Button", nil, header)
	reset:SetPoint("TOPRIGHT")
	reset:SetPoint("BOTTOMRIGHT")
	reset:SetWidth(48)
	reset.label = ns.OutlinedText(reset)
	reset.label:SetPoint("RIGHT", -4, 0)
	reset.label:SetText(ns.T("초기화", "Reset"))
	reset.label:SetTextColor(0.7, 0.7, 0.7)
	reset:SetScript("OnClick", ns.ResetMeter)

	meter.rows = {}
	for i = 1, ROWS do
		local row = makeRow(meter, i)
		row:EnableMouse(true)
		row:SetScript("OnMouseUp", openDetail)
		meter.rows[i] = row
	end

	-- To the left of the meter, bottoms lined up; a click on its title closes it.
	detail:SetWidth(DETAIL_WIDTH)
	detail:SetPoint("BOTTOMRIGHT", meter, "BOTTOMLEFT", -DETAIL_GAP, 0)
	detail:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
	detail:SetBackdropColor(0, 0, 0, 0.6)
	detail:SetBackdropBorderColor(0, 0, 0, 1)
	local detailHeader = CreateFrame("Button", nil, detail)
	detailHeader:SetHeight(HEADER_HEIGHT)
	detailHeader:SetPoint("TOPLEFT")
	detailHeader:SetPoint("TOPRIGHT")
	detailHeader:SetScript("OnClick", function()
		detailSource = nil
		refreshDetail()
	end)
	detail.title = ns.OutlinedText(detailHeader)
	detail.title:SetPoint("LEFT", 4, 0)
	detail.rows = {}
	for i = 1, DETAIL_ROWS do
		local row = makeRow(detail, i)
		row.icon = row:CreateTexture(nil, "OVERLAY")
		row.icon:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
		row.icon:SetPoint("LEFT", 1, 0)
		row.name:SetPoint("LEFT", ROW_HEIGHT + 2, 0)
		detail.rows[i] = row
	end
	detail:Hide()

	local events = CreateFrame("Frame")
	for _, event in ipairs(EVENTS) do
		events:RegisterEvent(event)
	end
	events:SetScript("OnEvent", function(_, event, _, sessionID)
		if event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" and not issecretvalue(sessionID) and sessionID
			and not startedAt[sessionID] then
			startedAt[sessionID] = date("%H:%M")
		elseif event == "PLAYER_REGEN_DISABLED" and selected.id then
			selected = CURRENT
			detailSource = nil
		end
		ns.RefreshMeter()
	end)
	ns.RefreshMeter()
end

-- The meter reads Blizzard's damage meter data, whose switch is one of KSUI's CVars, so both follow the option.
function ns.RefreshDamageMeter()
	ns.RefreshCVars()
	ns.RefreshMeter()
end
