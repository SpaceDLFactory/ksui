local _, ns = ...

local T = ns.T

local OPTIONS = {
	{ header = T("외형", "Look") },
	{ key = "darkUnitFrames", label = T("유닛프레임 어둡게", "Darken unit frames"), default = true, refresh = "RefreshSkin" },
	{ key = "darkActionBars", label = T("액션바 어둡게", "Darken action bars"), default = true, refresh = "RefreshSkin" },
	{ key = "artColor", label = T("테두리 색", "Border color"), default = "ff474752", refresh = "RefreshSkin" },
	{ key = "classColorBars", label = T("체력바 직업색", "Class-colored health bars"), default = true, refresh = "RefreshSkin" },
	{ key = "healthPercent", label = T("체력바에 퍼센트 표시", "Show percent on health bars"), default = true, refresh = "RefreshHealthPercent" },
	{ key = "cropIcons", label = T("아이콘 테두리 잘라내기", "Crop icon borders"), default = true, refresh = "RefreshSkin" },
	{ key = "squareMinimap", label = T("미니맵 네모로", "Square minimap"), default = true, refresh = "RefreshMinimap" },
	{ key = "customUnitFrames", label = T("내/대상/주시/소환수/대상의 대상 프레임 네모로", "Square player, target, focus, pet and target-of-target frames"), default = true, refresh = "RefreshUnitFrames", layout = true },
	{ key = "animatedPortraits", label = T("움직이는 초상화", "Animated portraits"), default = true, refresh = "RefreshUnitFrames" },
	{ key = "ammoCount", label = T("내 체력바에 남은 탄약 (사냥꾼)", "Ammo left on your health bar (hunters)"), default = true, refresh = "RefreshUnitFrames" },
	-- Blizzard's own look comes back only when it restyles a plate, so turning this off needs a reload.
	{ key = "flatNameplates", label = T("이름표 납작하게 (끌 때는 /reload)", "Flat nameplates (/reload after turning off)"), default = true },
	{ header = T("쿨다운", "Cooldowns") },
	{ key = "cooldownNumbers", label = T("쿨다운 숫자 표시", "Cooldown numbers"), default = true, refresh = "RefreshCooldowns" },
	{ key = "cooldownFontSize", label = T("숫자 크기", "Number size"), default = 16, min = 10, max = 32, step = 1, refresh = "RefreshCooldowns" },
	{ header = T("파티/공격대", "Party/raid") },
	{ key = "raidClassColors", label = T("공격대 프레임 직업색", "Class colors on raid frames"), default = true, refresh = "RefreshCVars" },
	-- Off by default: debuffs nobody can remove, like a priest's Weakened Soul, matter too.
	{ key = "raidStyleParty", label = T("파티를 블리자드 공격대 스타일로", "Blizzard raid-style party frames"), default = false, layout = true },
	{ key = "dispellableOnly", label = T("해제할 수 있는 디버프만 표시", "Show only debuffs you can dispel"), default = false, refresh = "RefreshCVars" },
	{ header = T("전투 보조", "Combat") },
	{ key = "cooldownManager", label = T("직업별 쿨다운·버프 표시 (쿨다운 관리자)", "Class cooldowns and buffs (cooldown manager)"), default = true, refresh = "RefreshCVars" },
	{ key = "cooldownCast", label = T("쿨다운 관리자 아이콘을 눌러 스킬 사용", "Click cooldown manager icons to cast"), default = true, refresh = "RefreshCooldownCast" },
	{ key = "rangeColor", label = T("사거리 밖 버튼 빨갛게", "Red buttons when out of range"), default = true, refresh = "RefreshRange" },
	{ key = "threatNumbers", label = T("대상 프레임에 위협 수치", "Threat number on the target frame"), default = true, refresh = "RefreshCVars" },
	{ key = "interruptHelper", label = T("대상 프레임 옆에 대상 시전바와 내 차단기", "Target cast bar and your interrupt beside the target frame"), default = true, refresh = "RefreshInterrupt" },
	-- Off by default: a caster's staff would fill an idle bar in every fight.
	{ key = "swingTimer", label = T("자동 공격 타이머 (전투 중, 쿨다운 관리자 위)", "Swing timers (in combat, above the cooldown manager)"), default = false, refresh = "RefreshSwingTimer" },
	{ key = "damageMeter", label = T("딜미터 (제목 좌클릭: 종류, 우클릭: 현재/전체, /ksui reset: 초기화)", "Damage meter (title left-click: type, right-click: fight, /ksui reset: clear)"), default = true, refresh = "RefreshMeter" },
	{ key = "threatMeter", label = T("파티 위협 미터 (파티일 때)", "Party threat meter (in a party)"), default = true, refresh = "RefreshThreat" },
	{ key = "fadeBars", label = T("비전투 시 액션바 흐리게", "Fade action bars out of combat"), default = true, refresh = "RefreshBarFade" },
	{ key = "fadeAlpha", label = T("흐릴 때 불투명도", "Faded opacity"), default = 0.4, min = 0.1, max = 1, step = 0.05, refresh = "RefreshBarFade" },
	{ header = T("편의", "Conveniences") },
	{ key = "autoRepair", label = T("상인에서 자동 수리", "Repair at vendors"), default = true },
	{ key = "sellJunk", label = T("상인에서 잡템 자동 판매", "Sell junk at vendors"), default = true },
	{ key = "buffCheck", label = T("준비 확인 때 빠진 버프 알림", "Report missing buffs on ready checks"), default = true },
	{ key = "gearSuggest", label = T("더 좋은 장비가 생기면 알림", "Tell me about better gear in my bags"), default = true },
	{ key = "gearRole", label = T("장비 추천 기준", "Gear suggestions for"), default = "AUTO", choices = {
		{ "AUTO", T("자동 (특성)", "Automatic (talents)") }, { "TANK", T("탱커", "Tank") }, { "MELEE", T("근접 딜러", "Melee damage") }, { "CASTER", T("주문 딜러", "Spell damage") }, { "HEALER", T("힐러", "Healer") },
	} },
	{ key = "gatherTracking", label = T("전문 기술 채집 추적 자동 켜기", "Track herbs, ore and fish for your professions"), default = true, refresh = "RefreshTracking" },
	{ key = "questArrow", label = T("미니맵에 퀘스트 길안내 화살표", "Quest arrow on the minimap"), default = true, refresh = "RefreshQuestGuide" },
	{ key = "questNearest", label = T("가장 가까운 퀘스트로 자동 길안내", "Guide to the nearest quest"), default = true, refresh = "RefreshQuestNearest" },
	{ key = "chatTimestamps", label = T("채팅에 시간 표시", "Timestamps in chat"), default = true, refresh = "RefreshCVars" },
	{ key = "shortChannels", label = T("채팅 채널 이름 줄이기 ([1. 공개 - 지역] → [공개])", "Short channel names ([1. General - Zone] → [General])"), default = true },
	{ key = "chatLinks", label = T("채팅의 웹 주소를 눌러 복사", "Click web addresses in chat to copy"), default = true },
	{ key = "whisperSound", label = T("귓속말 알림음", "Sound on whispers"), default = true },
	{ key = "autoQuest", label = T("퀘스트 자동 수락·완료 (Shift를 누르고 말 걸면 건너뜀)", "Accept and turn in quests (hold Shift to skip)"), default = true },
	{ key = "fastLoot", label = T("빠른 전리품 줍기 (자동 줍기일 때)", "Fast looting (with auto loot)"), default = true },
	{ key = "tooltipExtras", label = T("툴팁에 직업색 이름과 그 유닛의 대상", "Class-colored names and targets in tooltips"), default = true },
	{ key = "autoInvite", label = T("친구·길드원 파티 초대 자동 수락", "Accept group invites from friends and guild"), default = true },
	{ key = "xpText", label = T("경험치바에 남은 경험치 표시", "Experience left on the experience bar"), default = true, refresh = "RefreshXPText" },
	{ key = "skipSeenMovies", label = T("한 번 본 영상 자동 넘기기", "Skip movies you have seen"), default = true },
	{ header = T("프레임 위치", "Frame positions") },
	-- Shares of the screen, so a different screen size or UI scale keeps the same arrangement. The defaults are the
	-- old 130, 220, 20 and 20 UI units on the 2133 x 1200 screen KSUI was tuned on.
	{ key = "frameXPct", label = T("내/대상 프레임 중앙 거리 (화면 폭 %)", "Player and target distance from center (% of width)"), default = 6.1, min = 0, max = 30, step = 0.1, layout = true },
	{ key = "frameYPct", label = T("내/대상 프레임 높이 (화면 높이 %)", "Player and target height (% of height)"), default = 18.3, min = 5, max = 50, step = 0.1, layout = true },
	{ key = "groupXPct", label = T("파티/공격대 왼쪽 여백 (화면 폭 %)", "Party and raid left margin (% of width)"), default = 0.9, min = 0, max = 50, step = 0.1, layout = true },
	{ key = "groupTopPct", label = T("파티/공격대 위쪽 여백 (화면 높이 %)", "Party and raid top margin (% of height)"), default = 1.7, min = 0, max = 50, step = 0.1, layout = true },
}

ns.OPTIONS = OPTIONS
ns.optionSettings = {}

local VAR_TYPES = { boolean = "Boolean", number = "Number", string = "String" }

local function addControl(category, setting, option)
	local kind = type(option.default)
	if option.choices then
		Settings.CreateDropdown(category, setting, function()
			local container = Settings.CreateControlTextContainer()
			for _, choice in ipairs(option.choices) do
				container:Add(choice[1], choice[2])
			end
			return container:GetData()
		end)
	elseif kind == "boolean" then
		Settings.CreateCheckbox(category, setting)
	elseif kind == "string" then
		Settings.CreateColorSwatch(category, setting)
	else
		local options = Settings.CreateSliderOptions(option.min, option.max, option.step)
		-- As many decimals as the step has, so a converted 6.09374... shows as 6.1.
		local decimals = option.step >= 1 and 0 or math.ceil(-math.log10(option.step) - 1e-9)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
			return ("%." .. decimals .. "f"):format(value)
		end)
		Settings.CreateSlider(category, setting, options)
	end
end

function ns.RegisterOptions()
	local category, layout = Settings.RegisterVerticalLayoutCategory(T("검성UI", "Kumsung UI"))

	-- The two things done most after changing settings, at the top where they are found first.
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(T("빠른 실행", "Quick actions")))
	layout:AddInitializer(CreateSettingsButtonInitializer(
		T("화면 배치 적용", "Apply layout"), T("적용", "Apply"), ns.ApplyLayout,
		T("현재 편집 모드 레이아웃을 KSUI로 복사해 아래 위치로 옮기고 UI를 다시 불러옵니다. (/ksui layout)", "Copies your Edit Mode layout as KSUI, moves the frames to the positions below and reloads the UI. (/ksui layout)"), true))
	layout:AddInitializer(CreateSettingsButtonInitializer(
		T("UI 다시 불러오기", "Reload UI"), T("다시 불러오기", "Reload"), ReloadUI, T("UI를 다시 불러옵니다. (/reload)", "Reloads the UI. (/reload)"), true))
	layout:AddInitializer(CreateSettingsButtonInitializer(
		T("설정 내보내기", "Export settings"), T("내보내기", "Export"), ns.ShowExportProfile,
		T("지금 설정을 한 줄 문자열로 만듭니다. 다른 캐릭터나 친구에게 붙여넣으면 됩니다. (/ksui export)",
			"Turns your settings into one line of text to paste on another character or share. (/ksui export)"), true))
	layout:AddInitializer(CreateSettingsButtonInitializer(
		T("설정 가져오기", "Import settings"), T("가져오기", "Import"), ns.ShowImportProfile,
		T("내보낸 설정 문자열을 붙여넣어 적용합니다. (/ksui import)", "Applies a pasted settings string. (/ksui import)"), true))

	for _, option in ipairs(OPTIONS) do
		if option.header then
			layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(option.header))
		else
			local varType = Settings.VarType[VAR_TYPES[type(option.default)]]
			local setting = Settings.RegisterAddOnSetting(
				category, "KSUI_" .. option.key, option.key, ns.db, varType, option.label, option.default)
			-- Profile.lua sets imported values through these, so their refreshes run as from the panel.
			ns.optionSettings[option.key] = setting
			if option.refresh or option.layout then
				setting:SetValueChangedCallback(function(...)
					if option.refresh then
						ns[option.refresh](...)
					end
					-- Positions and party style go through Edit Mode, applied when the settings window closes.
					if option.layout then
						ns.LayoutSettingChanged()
					end
				end)
			end
			addControl(category, setting, option)
		end
	end

	Settings.RegisterAddOnCategory(category)
	ns.category = category
end
