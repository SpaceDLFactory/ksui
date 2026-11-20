-- Blizzard's cooldown manager only shows cooldowns. A secure button on each icon of its two spell rows casts that
-- spell on click. Each button is a child of its icon, so it shows and hides with it. Secure buttons can't be changed
-- in combat, and Blizzard reuses its icon frames in any order when it lays a row out again; a row that only shows in
-- combat is laid out again at every pull, which would leave buttons on the wrong spells. So the buttons only work on a
-- row set to always show, which the layout sets, and any change in combat is caught up afterwards. The buff rows show
-- auras, not spells, and are left alone.

local _, ns = ...

local VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer" }

-- Blizzard reuses its icon frames, so each keeps one button.
local buttons = {}
local pending = false

local function showTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetSpellByID(self:GetAttribute("spell"))
	GameTooltip:Show()
end

local function buttonFor(item)
	local button = buttons[item]
	if not button then
		button = CreateFrame("Button", nil, item, "SecureActionButtonTemplate")
		button:SetAllPoints()
		button:SetFrameLevel(item:GetFrameLevel() + 5)
		-- Both, so it casts whichever way the "cast on key down" option is set.
		button:RegisterForClicks("AnyUp", "AnyDown")
		button:SetAttribute("type", "spell")
		button:SetScript("OnEnter", showTooltip)
		button:SetScript("OnLeave", GameTooltip_Hide)
		buttons[item] = button
	end
	return button
end

local function sync()
	if InCombatLockdown() then
		pending = true
		return
	end
	pending = false
	for _, name in ipairs(VIEWERS) do
		local viewer = _G[name]
		local active = ns.db.cooldownCast and viewer.visibleSetting == Enum.CooldownViewerVisibleSetting.Always
		for _, item in ipairs(viewer:GetItemFrames()) do
			-- No secure button goes on Blizzard's icons until the option is used.
			local button = buttons[item] or (active and buttonFor(item))
			if button then
				local spellID = item:GetBaseSpellID()
				button:SetAttribute("spell", spellID)
				button:SetShown(active and spellID ~= nil)
			end
		end
	end
end

ns.RefreshCooldownCast = sync

function ns.InitCooldownCast()
	-- RefreshData hands the same icons new cooldowns when their number stays the same.
	for _, name in ipairs(VIEWERS) do
		hooksecurefunc(_G[name], "RefreshLayout", sync)
		hooksecurefunc(_G[name], "RefreshData", sync)
	end
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:SetScript("OnEvent", function()
		if pending then
			sync()
		end
	end)
	sync()
end
