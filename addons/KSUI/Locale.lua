-- Text shown in the game, in Korean on a Korean client and in English everywhere else. Each entry is
-- { Korean, English }; ns.L holds the one for this client.

local _, ns = ...

local STRINGS = {
	AMMO = { "탄약 %s", "Ammo %s" },

	PROFILE_EXPORT_BUTTON = { "설정 내보내기", "Export settings" },
	PROFILE_EXPORT_BUTTON_TEXT = { "내보내기", "Export" },
	PROFILE_EXPORT_TOOLTIP = { "지금 설정을 한 줄 문자열로 만듭니다. 다른 캐릭터나 친구에게 붙여넣으면 됩니다. (/ksui export)",
		"Turns your settings into one line of text to paste on another character or share. (/ksui export)" },
	PROFILE_IMPORT_BUTTON = { "설정 가져오기", "Import settings" },
	PROFILE_IMPORT_BUTTON_TEXT = { "가져오기", "Import" },
	PROFILE_IMPORT_TOOLTIP = { "내보낸 설정 문자열을 붙여넣어 적용합니다. (/ksui import)",
		"Applies a pasted settings string. (/ksui import)" },
	PROFILE_EXPORT = { "설정 문자열을 복사하세요 (Ctrl+C)", "Copy your settings (Ctrl+C)" },
	PROFILE_IMPORT = { "설정 문자열을 붙여넣으세요 (Ctrl+V)", "Paste a settings string (Ctrl+V)" },
	PROFILE_IMPORTED = { "검성UI: 설정 %d개를 가져왔습니다. 위치 설정은 다음 접속이나 /reload 때 적용됩니다.",
		"KSUI: imported %d settings. Position settings apply at your next login or /reload." },
	PROFILE_INVALID = { "검성UI: 검성UI 설정 문자열이 아닙니다.", "KSUI: that is not a KSUI settings string." },
}

local column = GetLocale() == "koKR" and 1 or 2
ns.L = {}
for key, texts in pairs(STRINGS) do
	ns.L[key] = texts[column]
end
