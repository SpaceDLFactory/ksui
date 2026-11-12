local _, ns = ...

-- Find Herbs, Find Minerals (both ranks, as Blizzard_Minimap lists them) and Find Fish. The minimap only lists
-- the ones your professions taught you, so turning on whatever is listed matches your professions.
local GATHERING = { [2383] = true, [8387] = true, [2580] = true, [8388] = true, [43308] = true }

-- Only turns tracking on. Turning it off stays a choice in the minimap's tracking menu.
function ns.RefreshTracking()
	if not ns.db.gatherTracking then
		return
	end
	for i = 1, C_Minimap.GetNumTrackingTypes() do
		local info = C_Minimap.GetTrackingInfo(i)
		if info and info.spellID and GATHERING[info.spellID] and not info.active then
			C_Minimap.SetTracking(i, true)
		end
	end
end
