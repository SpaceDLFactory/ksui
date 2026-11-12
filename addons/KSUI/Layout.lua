local _, ns = ...

local LAYOUT_NAME = "KSUI"
local FOCUS_ABOVE_TARGET = 110
local CAST_BAR_ABOVE_MINIMAP = 6
local BUFFS_ABOVE_FRAMES = 200
local DEBUFFS_ABOVE_FRAMES = 300
local BAR_SPACING = 4
local TRACKER_EDGE_GAP = 10
local BARS_BESIDE_MINIMAP = 8
local VIEWER_SPACING = 6

local function setValues(system, values)
	for _, info in ipairs(system.settings or {}) do
		if values[info.setting] ~= nil then
			info.value = values[info.setting]
		end
	end
end

-- Eight side-by-side groups of minimum-size cells take 576 x 194 in the top-left corner.
local function applyFortyPlayerSettings(system)
	local settings = Enum.EditModeUnitFrameSetting
	setValues(system, {
		[settings.RaidGroupDisplayType] = Enum.RaidGroupDisplayType.SeparateGroupsVertical,
		[settings.ViewRaidSize] = Enum.ViewRaidSize.Forty,
		-- Saved width and height count up from the minimum of 72 x 36.
		[settings.FrameWidth] = 0,
		[settings.FrameHeight] = 0,
	})
end

-- The right bars become horizontal rows on top of the bottom bars, so stance and pet bars move up one row.
-- Their empty slots stay hidden so a half-used row does not leave a block of empty squares.
local function horizontalBar(system)
	local settings = Enum.EditModeActionBarSetting
	setValues(system, {
		[settings.Orientation] = Enum.ActionBarOrientation.Horizontal,
		[settings.NumRows] = 1,
		[settings.NumIcons] = 12,
		[settings.AlwaysShowButtons] = 0,
	})
end

local function moveFrames(layout)
	local db = ns.db
	local function anchor(point, relativeTo, relativePoint, offsetX, offsetY)
		return { point = point, relativeTo = relativeTo, relativePoint = relativePoint, offsetX = offsetX, offsetY = offsetY }
	end
	local function above(frameName)
		return anchor("BOTTOMLEFT", frameName, "TOPLEFT", 0, BAR_SPACING)
	end
	local units = Enum.EditModeUnitFrameSystemIndices
	local bars = Enum.EditModeActionBarSystemIndices
	local auras = Enum.EditModeAuraFrameSystemIndices
	local viewers = Enum.EditModeCooldownViewerSystemIndices
	local kinds = Enum.EditModeSystem
	local unitFrame, actionBar, castBar = kinds.UnitFrame, kinds.ActionBar, kinds.CastBar
	local moves = {
		[unitFrame] = {
			[units.Player] = { anchor("BOTTOMRIGHT", "UIParent", "BOTTOM", -db.frameX, db.frameY) },
			[units.Target] = { anchor("BOTTOMLEFT", "UIParent", "BOTTOM", db.frameX, db.frameY) },
			[units.Focus] = { anchor("BOTTOMLEFT", "UIParent", "BOTTOM", db.frameX, db.frameY + FOCUS_ABOVE_TARGET) },
			-- Their default spot on the right edge is now under the quest tracker. They grow upwards from the
			-- tracker's top-left corner so they stay clear of the bars beside it.
			[units.Boss] = { anchor("BOTTOMRIGHT", "ObjectiveTrackerFrame", "TOPLEFT", -10, 0) },
			-- Party and raid are the only frames at the top. Blizzard requires a TOPLEFT anchor for them.
			[units.Party] = { anchor("TOPLEFT", "UIParent", "TOPLEFT", db.groupX, -db.groupTopGap) },
			[units.Raid] = { anchor("TOPLEFT", "UIParent", "TOPLEFT", db.groupX, -db.groupTopGap), applyFortyPlayerSettings },
		},
		-- Buffs and debuffs grow left and down from their top-right corner, above the player frame.
		[kinds.AuraFrame] = {
			[auras.BuffFrame] = { anchor("TOPRIGHT", "UIParent", "BOTTOM", -db.frameX, db.frameY + BUFFS_ABOVE_FRAMES) },
			[auras.DebuffFrame] = { anchor("TOPRIGHT", "UIParent", "BOTTOM", -db.frameX, db.frameY + DEBUFFS_ABOVE_FRAMES) },
		},
		-- The bottom row is split in two around the minimap: the main bar on its left, the micro menu and bags on
		-- its right, each with two bars stacked on top. The experience bars run underneath.
		[kinds.StatusTrackingBar] = {
			[1] = { anchor("BOTTOM", "UIParent", "BOTTOM", 0, 0) },
			[2] = { anchor("BOTTOM", "MainStatusTrackingBarContainer", "TOP", 0, 0) },
		},
		[kinds.Minimap] = { [0] = { anchor("BOTTOM", "SecondaryStatusTrackingBarContainer", "TOP", 0, BAR_SPACING) } },
		[kinds.MicroMenu] = { [0] = { anchor("BOTTOMLEFT", "MinimapCluster", "BOTTOMRIGHT", BARS_BESIDE_MINIMAP, 0) } },
		-- Moved up out of the way of the left bars.
		[kinds.ChatFrame] = { [0] = { anchor("BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 35, db.frameY) } },
		[kinds.ObjectiveTracker] = {
			-- A raw height of 0 is the 400 minimum; longer quest lists grow upwards from the corner.
			[0] = { anchor("BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -TRACKER_EDGE_GAP, TRACKER_EDGE_GAP), function(tracker)
				setValues(tracker, { [Enum.EditModeObjectiveTrackerSetting.Height] = 0 })
			end },
		},
		-- Above the tracker, clear of the right end of the bottom bars.
		[kinds.HudTooltip] = { [0] = { anchor("BOTTOMRIGHT", "ObjectiveTrackerFrame", "TOPRIGHT", 0, 10) } },
		-- The armor figure and its repair warning leave the middle of the right edge for the right end of the
		-- bars beside the minimap. A pet bar starts from the left end of that row, so the two stay apart.
		[kinds.DurabilityFrame] = { [0] = { anchor("BOTTOMRIGHT", "MultiBarLeft", "TOPRIGHT", 0, BAR_SPACING) } },
		[actionBar] = {
			[bars.MainBar] = { anchor("BOTTOMRIGHT", "MinimapCluster", "BOTTOMLEFT", -BARS_BESIDE_MINIMAP, 0) },
			[bars.Bar2] = { above("MainActionBar") },
			[bars.Bar3] = { above("MicroMenuContainer") },
			[bars.RightBar1] = { above("MultiBarBottomLeft"), horizontalBar },
			[bars.RightBar2] = { above("MultiBarBottomRight"), horizontalBar },
			[bars.StanceBar] = { above("MultiBarRight") },
			[bars.PetActionBar] = { above("MultiBarLeft") },
		},
		[castBar] = {
			-- On top of the minimap.
			[0] = { anchor("BOTTOM", "MinimapCluster", "TOP", 0, CAST_BAR_ABOVE_MINIMAP), function(system)
				setValues(system, { [Enum.EditModeCastBarSetting.LockToPlayerFrame] = 0 })
			end },
		},
		-- Blizzard's cooldown manager fills these per class and spec. They stack up the middle from the cast bar.
		[kinds.CooldownViewer] = {
			[viewers.Essential] = { anchor("BOTTOM", "PlayerCastingBarFrame", "TOP", 0, VIEWER_SPACING) },
			[viewers.Utility] = { anchor("BOTTOM", "EssentialCooldownViewer", "TOP", 0, VIEWER_SPACING) },
			[viewers.BuffIcon] = { anchor("BOTTOM", "UtilityCooldownViewer", "TOP", 0, VIEWER_SPACING) },
			[viewers.BuffBar] = { anchor("BOTTOM", "BuffIconCooldownViewer", "TOP", 0, VIEWER_SPACING) },
		},
	}
	for _, system in ipairs(layout.systems) do
		local move = moves[system.system] and moves[system.system][system.systemIndex or 0]
		if move then
			system.anchorInfo = move[1]
			system.anchorInfo2 = nil
			system.isInDefaultPosition = false
			if move[2] then
				move[2](system)
			end
		end
	end
end

-- Saves a copy of the active layout with the frames moved, then reloads to clear addon taint from Edit Mode.
function ns.ApplyLayout()
	if InCombatLockdown() then
		print("검성UI: 전투 중에는 레이아웃을 바꿀 수 없습니다.")
		return
	end

	-- GetLayouts omits presets, but saved indexes count them first.
	local info = C_EditMode.GetLayouts()
	local layouts = EditModePresetLayoutManager:GetCopyOfPresetLayouts()
	local presetCount = #layouts
	tAppendAll(layouts, info.layouts)

	local layout = CopyTable(layouts[info.activeLayout])
	layout.layoutIndex = nil
	layout.layoutName = LAYOUT_NAME
	layout.layoutType = Enum.EditModeLayoutType.Account
	moveFrames(layout)

	local accountLayouts = 0
	for i = #layouts, presetCount + 1, -1 do
		-- A Character layout that happens to share the name is the player's own, so it stays.
		if layouts[i].layoutType == Enum.EditModeLayoutType.Account then
			if layouts[i].layoutName == LAYOUT_NAME then
				table.remove(layouts, i)
			else
				accountLayouts = accountLayouts + 1
			end
		end
	end
	if accountLayouts >= Constants.EditModeConsts.EditModeMaxLayoutsPerType then
		print("검성UI: 계정 레이아웃이 가득 찼습니다. 편집 모드에서 하나를 지워주세요.")
		return
	end

	-- The game keeps Account layouts ahead of Character layouts.
	local slot = #layouts + 1
	for i = presetCount + 1, #layouts do
		if layouts[i].layoutType == Enum.EditModeLayoutType.Character then
			slot = i
			break
		end
	end
	table.insert(layouts, slot, layout)

	info.layouts = layouts
	info.activeLayout = slot
	C_EditMode.SaveLayouts(info)
	C_EditMode.SetActiveLayout(slot)
	ReloadUI()
end
