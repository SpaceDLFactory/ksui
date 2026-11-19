local _, ns = ...

local OPTIONS = {
	{ header = "외형" },
	{ key = "darkUnitFrames", label = "유닛프레임 어둡게", default = true, refresh = "RefreshSkin" },
	{ key = "darkActionBars", label = "액션바 어둡게", default = true, refresh = "RefreshSkin" },
	{ key = "artColor", label = "테두리 색", default = "ff474752", refresh = "RefreshSkin" },
	{ key = "classColorBars", label = "체력바 직업색", default = true, refresh = "RefreshSkin" },
	{ key = "healthPercent", label = "체력바에 퍼센트 표시", default = true, refresh = "RefreshHealthPercent" },
	{ key = "cropIcons", label = "아이콘 테두리 잘라내기", default = true, refresh = "RefreshSkin" },
	{ key = "squareMinimap", label = "미니맵 네모로", default = true, refresh = "RefreshMinimap" },
	{ key = "customUnitFrames", label = "내/대상/주시/소환수/대상의 대상 프레임 네모로", default = true, refresh = "RefreshUnitFrames", layout = true },
	{ key = "animatedPortraits", label = "움직이는 초상화", default = true, refresh = "RefreshUnitFrames" },
	{ key = "ammoCount", label = "내 체력바에 남은 탄약 (사냥꾼)", default = true, refresh = "RefreshUnitFrames" },
	-- Blizzard's own look comes back only when it restyles a plate, so turning this off needs a reload.
	{ key = "flatNameplates", label = "이름표 납작하게 (끌 때는 /reload)", default = true },
	{ header = "쿨다운" },
	{ key = "cooldownNumbers", label = "쿨다운 숫자 표시", default = true, refresh = "RefreshCooldowns" },
	{ key = "cooldownFontSize", label = "숫자 크기", default = 16, min = 10, max = 32, step = 1, refresh = "RefreshCooldowns" },
	{ header = "파티/공격대" },
	{ key = "raidClassColors", label = "공격대 프레임 직업색", default = true, refresh = "RefreshCVars" },
	-- Off by default: debuffs nobody can remove, like a priest's Weakened Soul, matter too.
	{ key = "raidStyleParty", label = "파티를 블리자드 공격대 스타일로", default = false, layout = true },
	{ key = "dispellableOnly", label = "해제할 수 있는 디버프만 표시", default = false, refresh = "RefreshCVars" },
	{ header = "전투 보조" },
	{ key = "cooldownManager", label = "직업별 쿨다운·버프 표시 (쿨다운 관리자)", default = true, refresh = "RefreshCVars" },
	{ key = "cooldownCast", label = "쿨다운 관리자 아이콘을 눌러 스킬 사용", default = true, refresh = "RefreshCooldownCast" },
	{ key = "rangeColor", label = "사거리 밖 버튼 빨갛게", default = true, refresh = "RefreshRange" },
	{ key = "threatNumbers", label = "대상 프레임에 위협 수치", default = true, refresh = "RefreshCVars" },
	{ key = "interruptHelper", label = "대상 프레임 옆에 대상 시전바와 내 차단기", default = true, refresh = "RefreshInterrupt" },
	-- Off by default: a caster's staff would fill an idle bar in every fight.
	{ key = "swingTimer", label = "자동 공격 타이머 (전투 중, 쿨다운 관리자 위)", default = false, refresh = "RefreshSwingTimer" },
	{ key = "damageMeter", label = "딜미터 (제목 좌클릭: 종류, 우클릭: 현재/전체, /ksui reset: 초기화)", default = true, refresh = "RefreshMeter" },
	{ key = "threatMeter", label = "파티 위협 미터 (파티일 때)", default = true, refresh = "RefreshThreat" },
	{ key = "fadeBars", label = "비전투 시 액션바 흐리게", default = true, refresh = "RefreshBarFade" },
	{ key = "fadeAlpha", label = "흐릴 때 불투명도", default = 0.4, min = 0.1, max = 1, step = 0.05, refresh = "RefreshBarFade" },
	{ header = "편의" },
	{ key = "autoRepair", label = "상인에서 자동 수리", default = true },
	{ key = "sellJunk", label = "상인에서 잡템 자동 판매", default = true },
	{ key = "buffCheck", label = "준비 확인 때 빠진 버프 알림", default = true },
	{ key = "gearSuggest", label = "더 좋은 장비가 생기면 알림", default = true },
	{ key = "gearRole", label = "장비 추천 기준", default = "AUTO", choices = {
		{ "AUTO", "자동 (특성)" }, { "TANK", "탱커" }, { "MELEE", "근접 딜러" }, { "CASTER", "주문 딜러" }, { "HEALER", "힐러" },
	} },
	{ key = "gatherTracking", label = "전문 기술 채집 추적 자동 켜기", default = true, refresh = "RefreshTracking" },
	{ key = "questArrow", label = "미니맵에 퀘스트 길안내 화살표", default = true, refresh = "RefreshQuestGuide" },
	{ key = "questNearest", label = "가장 가까운 퀘스트로 자동 길안내", default = true, refresh = "RefreshQuestNearest" },
	{ key = "chatTimestamps", label = "채팅에 시간 표시", default = true, refresh = "RefreshCVars" },
	{ key = "shortChannels", label = "채팅 채널 이름 줄이기 ([1. 공개 - 지역] → [공개])", default = true },
	{ key = "chatLinks", label = "채팅의 웹 주소를 눌러 복사", default = true },
	{ key = "whisperSound", label = "귓속말 알림음", default = true },
	{ key = "autoQuest", label = "퀘스트 자동 수락·완료 (Shift를 누르고 말 걸면 건너뜀)", default = true },
	{ key = "fastLoot", label = "빠른 전리품 줍기 (자동 줍기일 때)", default = true },
	{ key = "tooltipExtras", label = "툴팁에 직업색 이름과 그 유닛의 대상", default = true },
	{ key = "autoInvite", label = "친구·길드원 파티 초대 자동 수락", default = true },
	{ key = "xpText", label = "경험치바에 남은 경험치 표시", default = true, refresh = "RefreshXPText" },
	{ key = "skipSeenMovies", label = "한 번 본 영상 자동 넘기기", default = true },
	{ header = "프레임 위치" },
	-- Shares of the screen, so a different screen size or UI scale keeps the same arrangement. The defaults are the
	-- old 130, 220, 20 and 20 UI units on the 2133 x 1200 screen KSUI was tuned on.
	{ key = "frameXPct", label = "내/대상 프레임 중앙 거리 (화면 폭 %)", default = 6.1, min = 0, max = 30, step = 0.1, layout = true },
	{ key = "frameYPct", label = "내/대상 프레임 높이 (화면 높이 %)", default = 18.3, min = 5, max = 50, step = 0.1, layout = true },
	{ key = "groupXPct", label = "파티/공격대 왼쪽 여백 (화면 폭 %)", default = 0.9, min = 0, max = 50, step = 0.1, layout = true },
	{ key = "groupTopPct", label = "파티/공격대 위쪽 여백 (화면 높이 %)", default = 1.7, min = 0, max = 50, step = 0.1, layout = true },
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
	local category, layout = Settings.RegisterVerticalLayoutCategory("검성UI")

	-- The two things done most after changing settings, at the top where they are found first.
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("빠른 실행"))
	layout:AddInitializer(CreateSettingsButtonInitializer(
		"화면 배치 적용", "적용", ns.ApplyLayout,
		"현재 편집 모드 레이아웃을 KSUI로 복사해 아래 위치로 옮기고 UI를 다시 불러옵니다. (/ksui layout)", true))
	layout:AddInitializer(CreateSettingsButtonInitializer(
		"UI 다시 불러오기", "다시 불러오기", ReloadUI, "UI를 다시 불러옵니다. (/reload)", true))
	layout:AddInitializer(CreateSettingsButtonInitializer(
		ns.L.PROFILE_EXPORT_BUTTON, ns.L.PROFILE_EXPORT_BUTTON_TEXT, ns.ShowExportProfile, ns.L.PROFILE_EXPORT_TOOLTIP, true))
	layout:AddInitializer(CreateSettingsButtonInitializer(
		ns.L.PROFILE_IMPORT_BUTTON, ns.L.PROFILE_IMPORT_BUTTON_TEXT, ns.ShowImportProfile, ns.L.PROFILE_IMPORT_TOOLTIP, true))

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
