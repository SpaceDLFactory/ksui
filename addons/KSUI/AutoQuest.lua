-- Accepts and turns in quests as their windows open. Holding Shift while talking to the NPC skips it all, a reward
-- with more than one choice is left to you, and gray (trivial) quests are not picked up.

local _, ns = ...

local function skip()
	return not ns.db.autoQuest or IsShiftKeyDown()
end

-- An NPC's quest list, in the gossip window.
local function onGossip()
	if skip() then
		return
	end
	for _, quest in ipairs(C_GossipInfo.GetActiveQuests()) do
		if quest.isComplete then
			C_GossipInfo.SelectActiveQuest(quest.questID)
			return
		end
	end
	for _, quest in ipairs(C_GossipInfo.GetAvailableQuests()) do
		if not quest.isTrivial then
			C_GossipInfo.SelectAvailableQuest(quest.questID)
			return
		end
	end
end

-- The same list in the older quest greeting window.
local function onGreeting()
	if skip() then
		return
	end
	for i = 1, GetNumActiveQuests() do
		local _, isComplete = GetActiveTitle(i)
		if isComplete then
			SelectActiveQuest(i)
			return
		end
	end
	for i = 1, GetNumAvailableQuests() do
		if not IsAvailableQuestTrivial(i) then
			SelectAvailableQuest(i)
			return
		end
	end
end

local EVENTS = {
	GOSSIP_SHOW = onGossip,
	QUEST_GREETING = onGreeting,
	QUEST_DETAIL = function()
		-- PvP quests ask for a confirmation, which stays yours.
		if not skip() and not QuestFlagsPVP() then
			AcceptQuest()
		end
	end,
	QUEST_PROGRESS = function()
		if not skip() and IsQuestCompletable() then
			CompleteQuest()
		end
	end,
	QUEST_COMPLETE = function()
		if not skip() and GetNumQuestChoices() <= 1 then
			GetQuestReward(GetNumQuestChoices())
		end
	end,
}

function ns.InitAutoQuest()
	local events = CreateFrame("Frame")
	for event in pairs(EVENTS) do
		events:RegisterEvent(event)
	end
	events:SetScript("OnEvent", function(_, event)
		EVENTS[event]()
	end)
end
