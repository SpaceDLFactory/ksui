-- Small conveniences: faster looting, more in unit tooltips, group invites from friends and guild accepted, the
-- experience still needed written on the bar, and movies and cutscenes skipped once seen.

local _, ns = ...

-- Looting --------------------------------------------------------------------------------------------------------------

-- With auto loot on, everything is taken as the window opens instead of slot by slot behind it.
local function onLootReady(autoLoot)
	if not ns.db.fastLoot or not autoLoot then
		return
	end
	for slot = GetNumLootItems(), 1, -1 do
		LootSlot(slot)
	end
end

-- Tooltips -------------------------------------------------------------------------------------------------------------

-- A player's name in their class color, and whom the unit is targeting. Names and classes can be secret in instances;
-- then the tooltip stays as Blizzard made it.
local function onUnitTooltip(tooltip)
	if not ns.db.tooltipExtras or tooltip ~= GameTooltip then
		return
	end
	local _, unit = tooltip:GetUnit()
	if not unit or issecretvalue(unit) then
		return
	end
	local _, class = UnitClass(unit)
	if UnitIsPlayer(unit) and not issecretvalue(class) and class then
		local color = C_ClassColor.GetClassColor(class)
		GameTooltipTextLeft1:SetTextColor(color.r, color.g, color.b)
	end
	local target = unit .. "target"
	if not UnitExists(target) then
		return
	end
	local isPlayer = UnitIsUnit(target, "player")
	if issecretvalue(isPlayer) then
		return
	elseif isPlayer then
		tooltip:AddLine(ns.T("대상: >> 나 <<", "Target: >> YOU <<"), 1, 0.2, 0.2)
	else
		local name = UnitName(target)
		if not issecretvalue(name) then
			tooltip:AddLine(ns.T("대상: ", "Target: ") .. name, 1, 1, 1)
		end
	end
end

-- Group invites --------------------------------------------------------------------------------------------------------

local function isKnown(guid)
	return C_FriendList.IsFriend(guid) or IsGuildMember(guid) or C_BattleNet.GetAccountInfoByGUID(guid) ~= nil
end

-- Blizzard's invite dialog declines when it hides unaccepted, so it is marked accepted before it goes.
local function onInvite(_, _, _, _, _, _, _, guid)
	if not ns.db.autoInvite or not guid or not isKnown(guid) then
		return
	end
	AcceptGroup()
	local dialog = StaticPopup_FindVisible("PARTY_INVITE")
	if dialog then
		dialog.inviteAccepted = 1
		StaticPopup_Hide("PARTY_INVITE")
	end
end

-- Experience text ------------------------------------------------------------------------------------------------------

-- The last few quests' experience gives a rough "quests to go".
local QUESTS_REMEMBERED = 10
local XP_TEXT_CHECK = 0.1
local xpText

local function questsToGo(remaining)
	local gains = ns.db.questXP or {}
	if #gains == 0 then
		return nil
	end
	local sum = 0
	for _, xp in ipairs(gains) do
		sum = sum + xp
	end
	return math.ceil(remaining / (sum / #gains))
end

local function updateXP()
	local shown = ns.db.xpText and not GameRulesUtil.IsPlayerAtEffectiveMaxLevel() and not IsXPUserDisabled()
	xpText:SetShown(shown)
	if not shown then
		return
	end
	local current, max = UnitXP("player"), UnitXPMax("player")
	local remaining = max - current
	local text = ns.T("남은 경험치 %s (%.0f%%)", "%s XP to go (%.0f%%)"):format(BreakUpLargeNumbers(remaining), remaining / max * 100)
	local rested = GetXPExhaustion()
	if rested and rested > 0 then
		text = text .. ns.T(" · 휴식 %s", " · rested %s"):format(BreakUpLargeNumbers(rested))
	end
	local quests = questsToGo(remaining)
	if quests then
		text = text .. ns.T(" · 퀘스트 약 %d개", " · about %d quests"):format(quests)
	end
	xpText:SetText(text)
end

local function onQuestTurnedIn(_, xp)
	if xp and xp > 0 then
		local gains = ns.db.questXP or {}
		table.insert(gains, xp)
		while #gains > QUESTS_REMEMBERED do
			table.remove(gains, 1)
		end
		ns.db.questXP = gains
		updateXP()
	end
end

-- Movies and cutscenes -------------------------------------------------------------------------------------------------

-- Movies have IDs. Cutscenes don't, so one is known by where it starts.
local function cutsceneKey()
	return ("%s:%s"):format(C_Map.GetBestMapForUnit("player") or 0, GetSubZoneText() or "")
end

local function onMovie(frame, movieID)
	if not ns.db.skipSeenMovies or not movieID then
		return
	end
	ns.db.seenMovies = ns.db.seenMovies or {}
	if ns.db.seenMovies[movieID] then
		frame:OnMovieFinished(true)
	else
		ns.db.seenMovies[movieID] = true
	end
end

local function onCutscene(canBeCancelled)
	if not ns.db.skipSeenMovies or not canBeCancelled then
		return
	end
	ns.db.seenCutscenes = ns.db.seenCutscenes or {}
	local key = cutsceneKey()
	if ns.db.seenCutscenes[key] then
		-- After Blizzard has opened its cutscene frame for this start.
		C_Timer.After(0, CinematicFrame_CancelCinematic)
	else
		ns.db.seenCutscenes[key] = true
	end
end

------------------------------------------------------------------------------------------------------------------------

local EVENTS = {
	LOOT_READY = onLootReady,
	PARTY_INVITE_REQUEST = onInvite,
	PLAYER_XP_UPDATE = updateXP,
	UPDATE_EXHAUSTION = updateXP,
	PLAYER_LEVEL_UP = updateXP,
	QUEST_TURNED_IN = onQuestTurnedIn,
	CINEMATIC_START = onCutscene,
}

ns.RefreshXPText = function()
	updateXP()
end

function ns.InitConvenience()
	-- Above the bars inside the container, which would otherwise cover the text.
	local holder = CreateFrame("Frame", nil, MainStatusTrackingBarContainer)
	holder:SetAllPoints()
	holder:SetFrameLevel(MainStatusTrackingBarContainer:GetFrameLevel() + 10)
	xpText = ns.OutlinedText(holder)
	xpText:SetPoint("CENTER", holder, "CENTER", 0, 1)
	-- Blizzard shows its own bar text on mouseover (or always, by its option), in the same spot. Its bars are made
	-- before KSUI loads, so instead of hooking them this checks a few times a second and steps aside meanwhile.
	local elapsed = 0
	holder:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed < XP_TEXT_CHECK then
			return
		end
		elapsed = 0
		local blizzardText = false
		for _, bar in ipairs({ MainStatusTrackingBarContainer:GetChildren() }) do
			local overlay = bar.OverlayFrame
			blizzardText = blizzardText or (overlay ~= nil and overlay.Text ~= nil and overlay.Text:IsVisible())
		end
		holder:SetAlpha(blizzardText and 0 or 1)
	end)

	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, onUnitTooltip)
	hooksecurefunc(MovieFrame, "PlayMovie", onMovie)

	local events = CreateFrame("Frame")
	for event in pairs(EVENTS) do
		events:RegisterEvent(event)
	end
	events:SetScript("OnEvent", function(_, event, ...)
		EVENTS[event](...)
	end)
	updateXP()
end
