-- Settings as one line of text to share or keep: the values from the settings panel (not logs, layout state or the
-- meter), CBOR-encoded, deflated and in base64, behind a version prefix. Importing checks every value against its
-- option before setting it the way the panel does, so a value from a newer or older KSUI, or a broken paste, can't
-- put anything into the saved variables that the panel couldn't.

local _, ns = ...

local PREFIX = "KSUI1:"

local function exportString()
	local values = {}
	for _, option in ipairs(ns.OPTIONS) do
		if option.key then
			values[option.key] = ns.db[option.key]
		end
	end
	local packed = C_EncodingUtil.CompressString(C_EncodingUtil.SerializeCBOR(values))
	return PREFIX .. C_EncodingUtil.EncodeBase64(packed)
end

local function decode(text)
	text = text:gsub("%s", "")
	if text:sub(1, #PREFIX) ~= PREFIX then
		return nil
	end
	local ok, values = pcall(function()
		local packed = C_EncodingUtil.DecodeBase64(text:sub(#PREFIX + 1))
		return C_EncodingUtil.DeserializeCBOR(C_EncodingUtil.DecompressString(packed))
	end)
	if ok and type(values) == "table" then
		return values
	end
end

-- The same checks the panel's controls make: the type of the default, a slider's range, a dropdown's choices,
-- a color as eight hex digits.
local function valid(option, value)
	if type(value) ~= type(option.default) then
		return false
	end
	if option.choices then
		for _, choice in ipairs(option.choices) do
			if choice[1] == value then
				return true
			end
		end
		return false
	end
	if type(value) == "number" then
		return value >= option.min and value <= option.max
	end
	if type(value) == "string" then
		return value:match("^%x%x%x%x%x%x%x%x$") ~= nil
	end
	return true
end

-- A slider's value goes onto its nearest step, as the slider would put it; printing to 6 decimals drops the float
-- noise that 0.1 steps leave behind.
local function onStep(option, value)
	-- Out of range stays as it is, so valid() turns it down instead of the rounding pulling it back in.
	if type(value) ~= "number" or not option.step or value ~= value or value < option.min or value > option.max then
		return value
	end
	local stepped = option.min + math.floor((value - option.min) / option.step + 0.5) * option.step
	return tonumber(("%.6f"):format(stepped))
end

-- Returns how many settings were applied, or nil when the text isn't a KSUI profile.
local function importString(text)
	local values = decode(text)
	if not values then
		return nil
	end
	local applied = 0
	for _, option in ipairs(ns.OPTIONS) do
		local value = option.key and onStep(option, values[option.key])
		if value ~= nil and valid(option, value) then
			if ns.db[option.key] ~= value then
				ns.optionSettings[option.key]:SetValue(value)
			end
			applied = applied + 1
		end
	end
	return applied
end

ns.ExportProfile, ns.ImportProfile = exportString, importString

StaticPopupDialogs.KSUI_EXPORT_PROFILE = {
	text = ns.T("설정 문자열을 복사하세요 (Ctrl+C)", "Copy your settings (Ctrl+C)"),
	button1 = CLOSE,
	hasEditBox = true,
	editBoxWidth = 320,
	-- 0 is no limit; without it the box keeps the limit of whichever dialog used it last.
	maxLetters = 0,
	OnShow = function(dialog)
		local editBox = dialog:GetEditBox()
		editBox:SetText(exportString())
		editBox:HighlightText()
		editBox:SetFocus()
	end,
	EditBoxOnEscapePressed = function(editBox)
		editBox:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local function finishImport(dialog)
	local applied = importString(dialog:GetEditBox():GetText())
	-- A string with nothing usable in it isn't a profile either.
	if applied and applied > 0 then
		print(ns.T("검성UI: 설정 %d개를 가져왔습니다. 위치 설정은 다음 접속이나 /reload 때 적용됩니다.",
			"KSUI: imported %d settings. Position settings apply at your next login or /reload."):format(applied))
	else
		print(ns.T("검성UI: 검성UI 설정 문자열이 아닙니다.", "KSUI: that is not a KSUI settings string."))
	end
end

StaticPopupDialogs.KSUI_IMPORT_PROFILE = {
	text = ns.T("설정 문자열을 붙여넣으세요 (Ctrl+V)", "Paste a settings string (Ctrl+V)"),
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = true,
	editBoxWidth = 320,
	maxLetters = 0,
	OnShow = function(dialog)
		dialog:GetEditBox():SetText("")
		dialog:GetEditBox():SetFocus()
	end,
	OnAccept = finishImport,
	EditBoxOnEnterPressed = function(editBox)
		local dialog = editBox:GetParent()
		finishImport(dialog)
		dialog:Hide()
	end,
	EditBoxOnEscapePressed = function(editBox)
		editBox:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

function ns.ShowExportProfile()
	StaticPopup_Show("KSUI_EXPORT_PROFILE")
end

function ns.ShowImportProfile()
	StaticPopup_Show("KSUI_IMPORT_PROFILE")
end
