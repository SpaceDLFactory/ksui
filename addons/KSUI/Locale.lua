-- Text shown in the game: Korean on a Korean client, English everywhere else. Each string is written where it is
-- used as ns.T("한국어", "English"), so the two stay side by side.

local _, ns = ...

local korean = GetLocale() == "koKR"

function ns.T(ko, en)
	if korean then
		return ko
	end
	return en
end
