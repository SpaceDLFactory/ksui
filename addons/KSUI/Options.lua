local _, ns = ...

local OPTIONS = {
	{ header = "외형" },
	{ key = "darkUnitFrames", label = "유닛프레임 어둡게", default = true, refresh = "RefreshSkin" },
	{ key = "darkActionBars", label = "액션바 어둡게", default = true, refresh = "RefreshSkin" },
	{ key = "artColor", label = "테두리 색", default = "ff474752", refresh = "RefreshSkin" },
	{ key = "classColorBars", label = "체력바 직업색", default = true, refresh = "RefreshSkin" },
	{ key = "healthPercent", label = "체력바에 퍼센트 표시", default = true, refresh = "RefreshCVars" },
	{ key = "cropIcons", label = "아이콘 테두리 잘라내기", default = true, refresh = "RefreshSkin" },
	{ key = "squareMinimap", label = "미니맵 네모로", default = true, refresh = "RefreshMinimap" },
	{ header = "쿨다운" },
	{ key = "cooldownNumbers", label = "쿨다운 숫자 표시", default = true, refresh = "RefreshCooldowns" },
	{ key = "cooldownFontSize", label = "숫자 크기", default = 16, min = 10, max = 32, step = 1, refresh = "RefreshCooldowns" },
	{ header = "파티/공격대" },
	{ key = "raidClassColors", label = "공격대 프레임 직업색", default = true, refresh = "RefreshCVars" },
	{ key = "dispellableOnly", label = "해제할 수 있는 디버프만 표시", default = true, refresh = "RefreshCVars" },
	{ header = "전투 보조" },
	{ key = "cooldownManager", label = "직업별 쿨다운·버프 표시 (쿨다운 관리자)", default = true, refresh = "RefreshCVars" },
	{ key = "rangeColor", label = "사거리 밖 버튼 빨갛게", default = true, refresh = "RefreshRange" },
	{ key = "threatNumbers", label = "대상 프레임에 위협 수치", default = true, refresh = "RefreshCVars" },
	{ key = "interruptHelper", label = "대상 프레임 옆에 대상 시전바와 내 차단기", default = true, refresh = "RefreshInterrupt" },
	{ key = "fadeBars", label = "비전투 시 액션바 흐리게", default = true, refresh = "RefreshBarFade" },
	{ key = "fadeAlpha", label = "흐릴 때 불투명도", default = 0.4, min = 0.1, max = 1, step = 0.05, refresh = "RefreshBarFade" },
	{ header = "편의" },
	{ key = "autoRepair", label = "상인에서 자동 수리", default = true },
	{ key = "sellJunk", label = "상인에서 잡템 자동 판매", default = true },
	{ key = "buffCheck", label = "준비 확인 때 빠진 버프 알림", default = true },
	{ key = "gearSuggest", label = "더 좋은 장비가 생기면 알림", default = true },
	{ key = "gatherTracking", label = "전문 기술 채집 추적 자동 켜기", default = true, refresh = "RefreshTracking" },
	{ header = "프레임 위치" },
	{ key = "frameX", label = "내/대상 프레임 중앙 거리", default = 130, min = 0, max = 500, step = 5 },
	{ key = "frameY", label = "내/대상 프레임 높이", default = 220, min = 60, max = 600, step = 5 },
	{ key = "groupX", label = "파티/공격대 왼쪽 여백", default = 20, min = 0, max = 1000, step = 5 },
	{ key = "groupTopGap", label = "파티/공격대 위쪽 여백", default = 20, min = 0, max = 600, step = 5 },
}

local VAR_TYPES = { boolean = "Boolean", number = "Number", string = "String" }

local function addControl(category, setting, option)
	local kind = type(option.default)
	if kind == "boolean" then
		Settings.CreateCheckbox(category, setting)
	elseif kind == "string" then
		Settings.CreateColorSwatch(category, setting)
	else
		local options = Settings.CreateSliderOptions(option.min, option.max, option.step)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		Settings.CreateSlider(category, setting, options)
	end
end

function ns.RegisterOptions()
	local category, layout = Settings.RegisterVerticalLayoutCategory("검성UI")

	for _, option in ipairs(OPTIONS) do
		if option.header then
			layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(option.header))
		else
			local varType = Settings.VarType[VAR_TYPES[type(option.default)]]
			local setting = Settings.RegisterAddOnSetting(
				category, "KSUI_" .. option.key, option.key, ns.db, varType, option.label, option.default)
			if option.refresh then
				setting:SetValueChangedCallback(ns[option.refresh])
			end
			addControl(category, setting, option)
		end
	end

	layout:AddInitializer(CreateSettingsButtonInitializer(
		"프레임 위치 적용", "적용", ns.ApplyLayout,
		"현재 편집 모드 레이아웃을 KSUI로 복사해 위 위치로 옮기고 UI를 다시 불러옵니다.", true))

	Settings.RegisterAddOnCategory(category)
	ns.category = category
end
