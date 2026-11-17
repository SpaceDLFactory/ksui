-- An arrow on the minimap's corner pointing at the quest Blizzard's navigation guides to, with the distance. It can
-- also keep that quest the nearest one in the log. Positions come from Blizzard's quest data; in instances the
-- player's position is withheld, so the arrow hides there.

local _, ns = ...

local SIZE = 34
local UPDATE_EVERY = 0.1
-- Picking the nearest quest waits for a burst of quest log events to settle.
local NEAREST_DELAY = 1
local NEAREST_EVENTS = { "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "ZONE_CHANGED_NEW_AREA" }

local guide, elapsed, nearestPending = nil, 0, false

-- The quest's next waypoint on this map, or its spot among the map's quest markers.
local function targetOnMap(questID, mapID)
	local x, y = C_QuestLog.GetNextWaypointForMap(questID, mapID)
	if x then
		return x, y
	end
	for _, quest in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
		if quest.questID == questID then
			return quest.x, quest.y
		end
	end
end

-- On the map x runs east and y runs south; scaled by the map's size in yards, the step to the target gives a bearing
-- measured the way GetPlayerFacing measures facing: from north, counterclockwise.
local function bearing(mapID, x, y)
	local player = C_Map.GetPlayerMapPosition(mapID, "player")
	if not player then
		return
	end
	local px, py = player:GetXY()
	local width, height = C_Map.GetMapWorldSize(mapID)
	local east, south = (x - px) * width, (y - py) * height
	return math.atan2(-east, -south)
end

local function update()
	local questID = C_SuperTrack.GetSuperTrackedQuestID()
	local mapID = C_Map.GetBestMapForUnit("player")
	local facing = GetPlayerFacing()
	local angle
	if questID and questID ~= 0 and mapID and facing then
		local x, y = targetOnMap(questID, mapID)
		angle = x and bearing(mapID, x, y)
	end
	guide.arrow:SetShown(angle ~= nil)
	guide.distance:SetShown(angle ~= nil)
	if angle then
		guide.arrow:SetRotation(angle - facing)
		guide.distance:SetFormattedText("%.0f", C_Navigation.GetDistance())
	end
end

function ns.RefreshQuestGuide()
	guide:SetShown(ns.db.questArrow)
	if guide:IsShown() then
		update()
	end
end

-- The nearest quest on this continent becomes Blizzard's navigation target.
local function guideNearest()
	nearestPending = false
	if not ns.db.questNearest then
		return
	end
	local best, bestDistance
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and not info.isHidden then
			local distanceSq, onContinent = C_QuestLog.GetDistanceSqToQuest(info.questID)
			if onContinent and distanceSq and (not bestDistance or distanceSq < bestDistance) then
				best, bestDistance = info.questID, distanceSq
			end
		end
	end
	if best and best ~= C_SuperTrack.GetSuperTrackedQuestID() then
		C_SuperTrack.SetSuperTrackedQuestID(best)
	end
end

function ns.InitQuestGuide()
	guide = CreateFrame("Frame", nil, Minimap)
	guide:SetSize(SIZE, SIZE)
	guide:SetPoint("TOPLEFT", 4, -4)
	guide.arrow = guide:CreateTexture(nil, "OVERLAY")
	guide.arrow:SetAtlas("Navigation-Tracked-Arrow")
	guide.arrow:SetAllPoints()
	guide.distance = ns.OutlinedText(guide)
	guide.distance:SetPoint("TOP", guide, "BOTTOM", 0, -1)
	guide:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed >= UPDATE_EVERY then
			elapsed = 0
			update()
		end
	end)

	local events = CreateFrame("Frame")
	for _, event in ipairs(NEAREST_EVENTS) do
		events:RegisterEvent(event)
	end
	events:SetScript("OnEvent", function()
		if not nearestPending then
			nearestPending = true
			C_Timer.After(NEAREST_DELAY, guideNearest)
		end
	end)
	ns.RefreshQuestGuide()
end

function ns.RefreshQuestNearest()
	guideNearest()
end
