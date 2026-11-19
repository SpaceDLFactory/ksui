local addonName, ns = ...

local LAYOUT_NAME = "KSUI"
local FOCUS_ABOVE_TARGET = 110
local CAST_BAR_ABOVE_MINIMAP = 6
-- Debuffs sit this far above the buffs' top edge.
local DEBUFFS_ABOVE_BUFFS = 100
local AURAS_BESIDE_COOLDOWNS = 10
local BAR_SPACING = 4
local TRACKER_EDGE_GAP = 10
local BARS_BESIDE_MINIMAP = 8
local VIEWER_SPACING = 6
-- Edit Mode saves the party frame size in 5% steps from 100%, so 3 steps is 115%.
local PARTY_SIZE_STEPS = 3
-- Blizzard's raid-style party frames, if chosen in the settings. Their width and height are saved as steps up from
-- 72 x 36.
local PARTY_RAID_STYLE_WIDTH, PARTY_RAID_STYLE_HEIGHT = 144 - 72, 64 - 36
-- Without them KSUI puts a row for you above the party (UnitFrames.lua): Blizzard's 53-tall member frame and its 10
-- spacing, at the party's size.
local PARTY_PLAYER_ROW = (53 + 10) * (1 + PARTY_SIZE_STEPS / 20)
-- A screen taller in UI units than the reference (measured: the 224-unit player frame is 405 pixels on it) makes
-- everything smaller, so the player and target frames grow by the same ratio, up to Edit Mode's 200%.
local MAX_SIZE_STEPS = 20

-- Edit Mode frame size steps (5% each from 100%) that keep the frames the same share of the screen. Edit Mode has
-- no size below 100%, so a shorter screen stays at 100%.
local function frameSizeSteps()
	local steps = math.floor((UIParent:GetHeight() / ns.REFERENCE_HEIGHT - 1) * 20 + 0.5)
	return math.max(0, math.min(MAX_SIZE_STEPS, steps))
end

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

-- The bars stacked on the main bar and the bags leave no grid of empty squares when only partly filled.
local function hideEmptySlots(system)
	setValues(system, { [Enum.EditModeActionBarSetting.AlwaysShowButtons] = 0 })
end

local function alwaysVisible(system)
	setValues(system, { [Enum.EditModeCooldownViewerSetting.VisibleSetting] = Enum.CooldownViewerVisibleSetting.Always })
end

local function hideEndCap(system)
	setValues(system, { [Enum.EditModeMainActionBarEndCapSetting.Hidden] = 1 })
end

-- Out of combat the swing timers would sit idle over the middle of the screen.
local function swingInCombat(system)
	setValues(system, { [Enum.EditModeSwingTimerSetting.Visibility] = Enum.EditModeSwingTimerVisibility.InCombat })
end

local function moveFrames(layout)
	local db = ns.db
	-- Positions are saved as a share of the screen and turned into UI units for this screen.
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	local frameX, frameY = db.frameXPct / 100 * width, db.frameYPct / 100 * height
	local groupX, groupTop = db.groupXPct / 100 * width, db.groupTopPct / 100 * height
	local sizeSteps = frameSizeSteps()
	-- Gaps above the frames grow with them.
	local grow = 1 + sizeSteps / 20
	local function frameSize(system)
		setValues(system, { [Enum.EditModeUnitFrameSetting.FrameSize] = sizeSteps })
	end
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
	local timers = Enum.EditModeSwingTimerSystemIndices
	local kinds = Enum.EditModeSystem
	local unitFrame, actionBar, castBar = kinds.UnitFrame, kinds.ActionBar, kinds.CastBar
	local moves = {
		[unitFrame] = {
			[units.Player] = { anchor("BOTTOMRIGHT", "UIParent", "BOTTOM", -frameX, frameY), frameSize },
			[units.Target] = { anchor("BOTTOMLEFT", "UIParent", "BOTTOM", frameX, frameY), frameSize },
			-- Its size setting only applies to the larger focus frame, so it keeps Blizzard's size.
			[units.Focus] = { anchor("BOTTOMLEFT", "UIParent", "BOTTOM", frameX, frameY + FOCUS_ABOVE_TARGET * grow) },
			-- Their default spot on the right edge is now under the quest tracker. They grow upwards from the
			-- tracker's top-left corner so they stay clear of the bars beside it.
			[units.Boss] = { anchor("BOTTOMRIGHT", "ObjectiveTrackerFrame", "TOPLEFT", -10, 0) },
			-- Party and raid are the only frames at the top. Blizzard requires a TOPLEFT anchor for them.
			[units.Party] = { anchor("TOPLEFT", "UIParent", "TOPLEFT", groupX,
				-groupTop - ((db.customUnitFrames and not db.raidStyleParty) and PARTY_PLAYER_ROW or 0)), function(system)
				local settings = Enum.EditModeUnitFrameSetting
				setValues(system, {
					[settings.FrameSize] = PARTY_SIZE_STEPS,
					[settings.UseRaidStylePartyFrames] = db.raidStyleParty and 1 or 0,
					[settings.FrameWidth] = PARTY_RAID_STYLE_WIDTH,
					[settings.FrameHeight] = PARTY_RAID_STYLE_HEIGHT,
				})
			end },
			[units.Raid] = { anchor("TOPLEFT", "UIParent", "TOPLEFT", groupX, -groupTop), applyFortyPlayerSettings },
		},
		-- Buffs and debuffs grow left and down from their top-right corner, which sits left of the cooldown manager's
		-- main row, so the row can widen as spells are learned without running into them.
		[kinds.AuraFrame] = {
			[auras.BuffFrame] = { anchor("TOPRIGHT", "EssentialCooldownViewer", "TOPLEFT", -AURAS_BESIDE_COOLDOWNS, 0) },
			[auras.DebuffFrame] = { anchor("TOPRIGHT", "EssentialCooldownViewer", "TOPLEFT", -AURAS_BESIDE_COOLDOWNS,
				DEBUFFS_ABOVE_BUFFS * grow) },
		},
		-- The bottom row is split in two around the minimap: the main bar on its left, the micro menu and bags on
		-- its right, each with two bars stacked on top. The experience bars run underneath.
		[kinds.StatusTrackingBar] = {
			[1] = { anchor("BOTTOM", "UIParent", "BOTTOM", 0, 0) },
			[2] = { anchor("BOTTOM", "MainStatusTrackingBarContainer", "TOP", 0, 0) },
		},
		-- The zone name and calendar row goes under the map.
		[kinds.Minimap] = { [0] = { anchor("BOTTOM", "SecondaryStatusTrackingBarContainer", "TOP", 0, BAR_SPACING), function(system)
			setValues(system, { [Enum.EditModeMinimapSetting.HeaderUnderneath] = 1 })
		end } },
		-- The micro menu and bags shrink to 75%; Edit Mode saves sizes as 5% steps up from 70% and 75%.
		[kinds.MicroMenu] = { [0] = { anchor("BOTTOMLEFT", "MinimapCluster", "BOTTOMRIGHT", BARS_BESIDE_MINIMAP, 0), function(system)
			setValues(system, { [Enum.EditModeMicroMenuSetting.Size] = 1 })
		end } },
		[kinds.Bags] = { [0] = { false, function(system)
			setValues(system, { [Enum.EditModeBagsSetting.Size] = 0 })
		end } },
		-- Moved up out of the way of the left bars.
		[kinds.ChatFrame] = { [0] = { anchor("BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 35, frameY) } },
		[kinds.ObjectiveTracker] = {
			-- A raw height of 0 is the 400 minimum; longer quest lists grow upwards from the corner.
			[0] = { anchor("BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -TRACKER_EDGE_GAP, TRACKER_EDGE_GAP), function(tracker)
				setValues(tracker, { [Enum.EditModeObjectiveTrackerSetting.Height] = 0 })
			end },
		},
		-- Above the tracker, clear of the right end of the bottom bars. KSUI's meters on the tracker move tooltips up
		-- themselves, so the saved layout never depends on an addon frame.
		[kinds.HudTooltip] = { [0] = { anchor("BOTTOMRIGHT", "ObjectiveTrackerFrame", "TOPRIGHT", 0, 10) } },
		-- KSUI draws its own meter above the quest tracker from the same data.
		[kinds.DamageMeter] = { [0] = { false, function(system)
			setValues(system, { [Enum.EditModeDamageMeterSetting.Visibility] = Enum.DamageMeterVisibility.Hidden })
		end } },
		-- The armor figure and its repair warning leave the middle of the right edge for the right end of the
		-- bars beside the minimap. A pet bar starts from the left end of that row, so the two stay apart.
		[kinds.DurabilityFrame] = { [0] = { anchor("BOTTOMRIGHT", "MultiBarLeft", "TOPRIGHT", 0, BAR_SPACING) } },
		-- The flight and vehicle exit button would otherwise sit on the main bar's buttons; beside your frame it is
		-- still at hand.
		[kinds.VehicleLeaveButton] = { [0] = { anchor("RIGHT", "PlayerFrame", "LEFT", -BARS_BESIDE_MINIMAP, 0) } },
		-- The queue eye would sit on the minimap's corner; the bottom-left corner under the chat is empty.
		[kinds.GroupFinder] = { [0] = { anchor("BOTTOMLEFT", "UIParent", "BOTTOMLEFT", TRACKER_EDGE_GAP, TRACKER_EDGE_GAP) } },
		[actionBar] = {
			-- Without its border art and empty squares the main bar matches the bars stacked on it.
			[bars.MainBar] = { anchor("BOTTOMRIGHT", "MinimapCluster", "BOTTOMLEFT", -BARS_BESIDE_MINIMAP, 0), function(system)
				setValues(system, { [Enum.EditModeActionBarSetting.HideBarArt] = 1 })
				hideEmptySlots(system)
			end },
			[bars.Bar2] = { above("MainActionBar"), hideEmptySlots },
			[bars.Bar3] = { above("MicroMenuContainer"), hideEmptySlots },
			[bars.RightBar1] = { above("MultiBarBottomLeft"), horizontalBar },
			[bars.RightBar2] = { above("MultiBarBottomRight"), horizontalBar },
			-- Right-aligned so it grows towards the middle, clear of the chat's edit box on the left.
			[bars.StanceBar] = { anchor("BOTTOMRIGHT", "MultiBarRight", "TOPRIGHT", 0, BAR_SPACING) },
			[bars.PetActionBar] = { above("MultiBarLeft") },
		},
		-- Forever's gargoyles are their own systems. Split around the minimap they end up at the far left of the main
		-- bar and past the bags, so both are hidden where they stand.
		[kinds.MainActionBarEndCap] = {
			[Enum.EditModeMainActionBarEndCapSystemIndices.EndCapLeft] = { false, hideEndCap },
			[Enum.EditModeMainActionBarEndCapSystemIndices.EndCapRight] = { false, hideEndCap },
		},
		[castBar] = {
			-- On top of the minimap.
			[0] = { anchor("BOTTOM", "MinimapCluster", "TOP", 0, CAST_BAR_ABOVE_MINIMAP), function(system)
				setValues(system, { [Enum.EditModeCastBarSetting.LockToPlayerFrame] = 0 })
			end },
		},
		-- Blizzard's cooldown manager fills these per class and spec. They stack up the middle from the cast bar.
		[kinds.CooldownViewer] = {
			-- The two spell rows always show, so KSUI's click-to-cast buttons stay on the right icons (CooldownCast.lua).
			[viewers.Essential] = { anchor("BOTTOM", "PlayerCastingBarFrame", "TOP", 0, VIEWER_SPACING), alwaysVisible },
			[viewers.Utility] = { anchor("BOTTOM", "EssentialCooldownViewer", "TOP", 0, VIEWER_SPACING), alwaysVisible },
			[viewers.BuffIcon] = { anchor("BOTTOM", "UtilityCooldownViewer", "TOP", 0, VIEWER_SPACING) },
			[viewers.BuffBar] = { anchor("BOTTOM", "BuffIconCooldownViewer", "TOP", 0, VIEWER_SPACING) },
		},
		-- Blizzard_SwingTimer's bars (shown with the swingTimer option) go on top of that column, in the middle of the
		-- screen where an eye on the fight finds them. Below the player frame are a shaman's totems, above it the buffs.
		[kinds.SwingTimer] = {
			[timers.MainHand] = { anchor("BOTTOM", "BuffBarCooldownViewer", "TOP", 0, VIEWER_SPACING), swingInCombat },
			[timers.OffHand] = { anchor("BOTTOM", "SwingTimerMainHandFrame", "TOP", 0, BAR_SPACING), swingInCombat },
			[timers.Ranged] = { anchor("BOTTOM", "SwingTimerOffHandFrame", "TOP", 0, BAR_SPACING), swingInCombat },
		},
	}
	for _, system in ipairs(layout.systems) do
		local move = moves[system.system] and moves[system.system][system.systemIndex or 0]
		if move then
			if move[1] then
				system.anchorInfo = move[1]
				system.anchorInfo2 = nil
				system.isInDefaultPosition = false
			end
			if move[2] then
				move[2](system)
			end
		end
	end
end

-- Blizzard's alerts (a new recipe, an achievement, loot) stack up from a point 128 above the bottom of the screen
-- (Blizzard_FrameXML/Mainline/AlertFrames.xml), where the minimap now sits, so they start above the cooldown manager.
-- Nothing in Blizzard's code moves that point again.
local ALERTS_ABOVE_COOLDOWNS = 10

function ns.PlaceAlerts()
	AlertFrame:ClearAllPoints()
	-- The swing timers stack on top of the cooldown manager, so alerts start above them while they're on.
	local below = ns.db.swingTimer and SwingTimerRangedFrame or BuffBarCooldownViewer
	AlertFrame:SetPoint("BOTTOM", below, "TOP", 0, ALERTS_ABOVE_COOLDOWNS)
end

function ns.RefreshSwingTimer()
	ns.RefreshCVars()
	ns.PlaceAlerts()
end

-- Saves a copy of the active layout with the frames moved. From the command or the settings button it reloads at once,
-- which clears addon taint from Edit Mode. On its own it runs while the UI loads or unloads instead, so Blizzard
-- reads the saved layout itself at the next load: no command, no reload button.
local function applyLayout(reload)
	if InCombatLockdown() then
		print(ns.T("검성UI: 전투 중에는 레이아웃을 바꿀 수 없습니다.", "KSUI: the layout can't be changed in combat."))
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
		print(ns.T("검성UI: 계정 레이아웃이 가득 찼습니다. 편집 모드에서 하나를 지워주세요.",
			"KSUI: your account layouts are full. Delete one in Edit Mode."))
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
	ns.db.layoutVersion = C_AddOns.GetAddOnMetadata(addonName, "Version")
	ns.db.layoutPending = nil
	if reload then
		ReloadUI()
	end
end

function ns.ApplyLayout()
	applyLayout(true)
end

-- While the UI loads, the layout is saved on a first install, after an update (while the KSUI layout is the active one:
-- a player who switched to another layout keeps it), and after layout settings changed. The saved layouts arrive
-- with EDIT_MODE_LAYOUTS_UPDATED, which Edit Mode handles first; this waits a frame after it.
local function applyAtLoad()
	local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
	if InCombatLockdown() then
		return
	end
	if ns.db.layoutVersion == nil or ns.db.layoutPending then
		applyLayout(false)
		return
	end
	if ns.db.layoutVersion == version then
		return
	end
	local info = C_EditMode.GetLayouts()
	local active = info.layouts[info.activeLayout - #EditModePresetLayoutManager:GetCopyOfPresetLayouts()]
	if active and active.layoutName == LAYOUT_NAME and active.layoutType == Enum.EditModeLayoutType.Account then
		applyLayout(false)
	end
end

-- Settings that change the layout are saved when the UI unloads (logging out or /reload), and again at the next load
-- in case that save didn't go through, not at every slider step.
local changedNow = false

function ns.LayoutSettingChanged()
	ns.db.layoutPending = true
	changedNow = true
end

function ns.InitLayoutSettings()
	SettingsPanel:HookScript("OnHide", function()
		if changedNow then
			changedNow = false
			print(ns.T("검성UI: 바뀐 위치 설정은 다음 접속이나 /reload 때 적용됩니다.",
				"KSUI: changed positions apply at your next login or /reload."))
		end
	end)
	local unload = CreateFrame("Frame")
	unload:RegisterEvent("PLAYER_LOGOUT")
	unload:SetScript("OnEvent", function()
		if ns.db.layoutPending then
			applyLayout(false)
			-- Kept until the next load has seen it saved.
			ns.db.layoutPending = true
		end
	end)
end

local layoutsLoaded = CreateFrame("Frame")
layoutsLoaded:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
layoutsLoaded:SetScript("OnEvent", function(self)
	self:UnregisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
	C_Timer.After(0, applyAtLoad)
end)
