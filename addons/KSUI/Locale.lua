-- Text shown in the game, in Korean on a Korean client and in English everywhere else. Each entry is
-- { Korean, English }; ns.L holds the one for this client.

local _, ns = ...

local STRINGS = {
	AMMO = { "탄약 %s", "Ammo %s" },
}

local column = GetLocale() == "koKR" and 1 or 2
ns.L = {}
for key, texts in pairs(STRINGS) do
	ns.L[key] = texts[column]
end
