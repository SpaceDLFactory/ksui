-- Run with: luajit tests/run.lua (from the repository root)
-- Simulates the WoW API. It cannot prove in-game behavior; it catches logic and secret-value misuse.

local SECRET = newproxy(true)
local function secretError() error("secret value misused", 2) end
local secretMeta = getmetatable(SECRET)
secretMeta.__add, secretMeta.__sub, secretMeta.__lt, secretMeta.__le = secretError, secretError, secretError, secretError
secretMeta.__index, secretMeta.__concat, secretMeta.__len = secretError, secretError, secretError

local failures, count = 0, 0
local function check(name, condition)
	count = count + 1
	if not condition then
		failures = failures + 1
		print("FAIL " .. name)
	end
end

local function texture()
	local t = {}
	function t:SetDesaturated(v) self.desaturated = v end
	function t:SetVertexColor(r, g, b) self.color = { r, g, b } end
	function t:SetTexCoord(...) self.coords = { ... } end
	-- Wrap modes are strings; a number there means a multi-return call leaked into them.
	function t:SetTexture(v, h, w)
		assert((h == nil or type(h) == "string") and (w == nil or type(w) == "string"), "SetTexture given a non-string wrap mode")
		self.file = v
	end
	function t:SetColorTexture(r, g, b) self.fill = { r, g, b } end
	function t:SetAlpha(a) self.alpha = a end
	function t:GetAlpha() return self.alpha or 1 end
	function t:SetAlphaFromBoolean(v, yes, no) self.alphaFrom = { v, yes, no } end
	function t:SetPoint(...) self.point = { ... }; self.points = (self.points or 0) + 1 end
	function t:SetJustifyH(j) self.justify = j end
	function t:SetWordWrap(v) self.wrap = v end
	function t:SetWidth(w) self.width = w end
	function t:SetAtlas(a) self.atlas = a end
	function t:SetRotation(r) self.rotation = r end
	function t:SetTextColor(r, g, b) self.textColor = { r, g, b } end
	function t:ClearAllPoints() self.points = 0 end
	function t:SetDrawLayer(l, sub) self.layer = l; self.sublayer = sub end
	function t:SetParent(p) self.parent = p end
	function t:Show() self.shown = true end
	function t:Hide() self.shown = false end
	function t:SetText(v) self.text = v end
	function t:SetAllPoints() end
	function t:SetSize() end
	function t:SetVertexColorFromBoolean(v, yes, no)
		assert(type(v) == "boolean" or v == SECRET, "SetVertexColorFromBoolean needs a boolean")
		self.colorFrom = { v, yes, no }
		-- The client picks the color itself; a secret leaves the test unable to tell which.
		if v ~= SECRET then
			local c = v and yes or no
			self.color = { c.r, c.g, c.b }
		end
	end
	function t:SetShown(v) self.shown = v end
	function t:GetFont() return "Fonts\\font.ttf", 10 end
	function t:SetFont(path, size, flags) self.font = { path, size, flags } end
	return t
end

local function bar()
	local b = { sets = 0 }
	function b:SetStatusBarDesaturated(v) self.desaturated = v end
	function b:SetStatusBarColor(r, g, b2)
		self.color = { r, g, b2 }
		self.sets = self.sets + 1
	end
	return b
end

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for k, v in pairs(value) do result[k] = copy(v) end
	return result
end

local function mockSettings(env, state)
	state.settings, state.controls, state.headers = {}, {}, {}
	local layout = {}
	function layout:AddInitializer(init)
		if init.buttonClick then
			state.buttons = state.buttons or {}
			state.buttons[init.name] = init
			-- Most tests press the layout button.
			if init.name == "화면 배치 적용" then state.button = init end
		else
			state.headers[#state.headers + 1] = init.name
		end
	end
	local category = { GetID = function() return 42 end }
	local function control(kind)
		return function(cat, setting, options)
			assert(cat == category)
			state.controls[setting.variable] = { kind = kind, options = options }
		end
	end
	env.Settings = {
		VarType = { Boolean = "boolean", Number = "number", String = "string" },
		RegisterVerticalLayoutCategory = function(name) state.categoryName = name; return category, layout end,
		RegisterAddOnCategory = function(cat) state.registered = cat end,
		OpenToCategory = function(id) state.opened = id end,
		RegisterAddOnSetting = function(_, variable, key, tbl, varType, name, default)
			assert(type(default) == varType, "default type mismatch for " .. variable)
			assert(name ~= nil)
			if tbl[key] == nil then tbl[key] = default end
			local setting = { variable = variable }
			function setting:SetValueChangedCallback(cb) self.callback = cb end
			function setting:SetValue(v)
				tbl[key] = v
				if self.callback then self.callback(self, v) end
			end
			state.settings[key] = setting
			return setting
		end,
		CreateCheckbox = control("checkbox"),
		CreateColorSwatch = control("color"),
		CreateSlider = control("slider"),
		CreateDropdown = control("dropdown"),
		CreateControlTextContainer = function()
			local data = {}
			return { Add = function(_, value, label) data[#data + 1] = { value = value, label = label } end,
				GetData = function() return data end }
		end,
		CreateSliderOptions = function(min, max, step)
			return { min = min, max = max, step = step,
				SetLabelFormatter = function(self, label, format) self.formatter = label; self.format = format end }
		end,
	}
	env.MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
	function env.CreateSettingsListSectionHeaderInitializer(name) return { name = name } end
	function env.CreateSettingsButtonInitializer(name, text, click, tooltip, tags)
		assert(tags ~= nil and tooltip ~= nil)
		return { name = name, text = text, buttonClick = click }
	end
	function env.CreateColorFromHexString(hex)
		assert(#hex == 8, "hex must be AARRGGBB")
		local function part(i) return tonumber(hex:sub(i, i + 1), 16) / 255 end
		return { GetRGB = function() return part(3), part(5), part(7) end }
	end
end

local function world(state)
	local env = { ipairs = ipairs, pairs = pairs, type = type, tonumber = tonumber, tostring = tostring, setmetatable = setmetatable, error = error, table = table, math = math, string = string }
	env._G = env
	local handlers = {}
	env.events = handlers

	function env.CreateFrame(kind, _, parent, template)
		local f = { registered = {}, scripts = {}, kind = kind, parent = parent, template = template }
		state.frames = state.frames or {}
		state.frames[#state.frames + 1] = f
		function f:RegisterEvent(e) self.registered[e] = true end
		function f:UnregisterEvent(e) self.registered[e] = nil end
		function f:RegisterUnitEvent(e, unit)
			self.registered[e] = true
			self.units = self.units or {}
			self.units[e] = unit
		end
		function f:SetScript(name, fn)
			self.scripts[name] = fn
			if name == "OnEvent" then handlers[#handlers + 1] = { frame = f, fn = fn } end
		end
		function f:SetSize(w, h) self.size = { w, h } end
		function f:SetPoint(...)
			self.point = { ... }
			self.points = self.points or {}
			self.points[select(1, ...)] = { ... }
		end
		function f:SetText(t) self.text = t end
		function f:SetAllPoints() end
		function f:SetShown(v) self.shown = v end
		function f:CreateTexture() return texture() end
		function f:SetCooldownFromDurationObject(d) self.duration = d end
		function f:CreateFontString()
			local t = texture()
			function t:SetText(v) self.text = v end
			function t:SetFormattedText(fmt, ...) self.format = { fmt, ... } end
			function t:SetParent(p) self.parent = p end
			return t
		end
		function f:Show() self.shown = true end
		function f:Hide() self.shown = false end
		function f:SetStatusBarTexture() self.fill = texture() end
		function f:GetStatusBarTexture() return self.fill end
		function f:SetMinMaxValues(a, b) self.range = { a, b } end
		function f:SetValue(v) self.barValue = v end
		function f:SetBackdrop(b) self.backdrop = b end
		function f:SetBackdropBorderColor(r, g, b, a) self.borderColor = { r, g, b, a } end
		function f:SetBackdropColor(r, g, b, a) self.backdropColor = { r, g, b, a } end
		function f:SetAttribute(k, v) self.attributes = self.attributes or {}; self.attributes[k] = v end
		function f:RegisterForClicks(...) self.clicks = { ... } end
		function f:SetWidth(w) self.width = w end
		function f:ClearAllPoints() self.point = nil end
		function f:GetParent() return self.parent end
		function f:SetHeight(h) self.height = h end
		function f:EnableMouse(v) self.mouse = v end
		function f:SetFrameLevel(l) self.level = l end
		function f:SetHideCountdownNumbers(v) self.hideNumbers = v end
		function f:SetAlpha(v) self.alpha = v; self.alphaFrom = nil end
		function f:SetAlphaFromBoolean(v, yes, no) self.alphaFrom = { v, yes, no } end
		function f:Clear() self.duration = nil; self.timer = nil end
		function f:SetCooldown(start, duration) self.timer = { start, duration } end
		function f:GetFrameLevel() return self.level or 1 end
		function f:IsShown() return self.shown ~= false end
		function f:SetStatusBarColor(r, g, b) self.color = { r, g, b } end
		function f:SetClipsChildren(v) self.clips = v end
		function f:ClearModel() self.modelUnit = nil end
		function f:SetUnit(u) self.modelUnit = u; self.modelLoads = (self.modelLoads or 0) + 1 end
		function f:SetPortraitZoom(z) self.zoom = z end
		function f:SetPosition() end
		return f
	end
	env.CharacterFrame, env.PaperDollFrame = { name = "CharacterFrame" }, { name = "PaperDollFrame" }
	-- Items: link -> { id, loc, stats, usable }. Bags: bag -> { slot -> link }. Worn: slot -> link.
	state.items, state.bags, state.worn, state.equipped = state.items or {}, state.bags or {}, state.worn or {}, {}
	env.C_Container = {
		GetContainerNumSlots = function(bag) return state.bags[bag] and 16 or 0 end,
		GetContainerItemLink = function(bag, slot) return state.bags[bag][slot] end,
	}
	env.C_Item = {
		GetItemInfoInstant = function(link) local i = state.items[link]; return i.id, "Armor", "Plate", i.loc end,
		GetItemStats = function(link) local i = state.items[link]; return i.stats and copy(i.stats) or nil end,
		EquipItemByName = function(link, slot) state.equipped[#state.equipped + 1] = { link = link, slot = slot } end,
		IsBound = function(location) return not state.items[state.bags[location.bag][location.slot]].unbound end,
	}
	env.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
	env.C_PlayerInfo = { CanUseItem = function(id)
		for _, i in pairs(state.items) do if i.id == id then return i.usable ~= false end end
	end }
	function env.GetInventoryItemLink(unit, slot) assert(unit == "player"); return state.worn[slot] end
	env.C_SpecializationInfo = {
		GetSpecialization = function() return state.spec and 1 or nil end,
		GetSpecializationInfo = function(index)
			assert(index == 1)
			return 66, "Protection", "", 0, state.spec.role, state.spec.primary
		end,
	}
	-- state.talents = { spent per tree in the talent window's order }; nil before the talent config exists.
	env.C_ClassTalents = { GetActiveConfigID = function() return state.talents and 7 or nil end }
	function env.GetShapeshiftFormID() return state.form end
	-- Blizzard's raid frames: setting a unit, as in Blizzard_UnitFrame/Shared/CompactUnitFrame.lua.
	function env.CompactUnitFrame_SetUnit(frame, unit) frame.unit, frame.displayedUnit = unit, unit end
	env.C_Traits = {
		GetConfigInfo = function(id) assert(id == 7); return { treeIDs = { 70 } } end,
		-- Given out of order, as the window sorts them itself.
		GetGroupDisplayInfoByTreeID = function(tree)
			assert(tree == 70)
			return { { groupID = 103, orderIndex = 2 }, { groupID = 101, orderIndex = 0 }, { groupID = 102, orderIndex = 1 } }
		end,
		GetGroupCurrencyInfo = function(id, groupIDs)
			assert(id == 7 and #groupIDs == 3)
			local infos = {}
			for i, spent in ipairs(state.talents) do
				infos[i] = { traitNodeGroupID = 100 + i, currencyInfos = { { spent = spent } } }
			end
			return infos
		end,
	}
	state.tracking = state.tracking or {}
	env.C_Minimap = {
		GetNumTrackingTypes = function() return #state.tracking end,
		GetTrackingInfo = function(i) return copy(state.tracking[i]) end,
		SetTracking = function(i, on) state.tracking[i].active = on end,
	}
	function env.hooksecurefunc(obj, name, fn)
		if type(obj) == "string" then
			obj, name, fn = env, obj, name
		end
		local original = obj[name]
		obj[name] = function(...)
			local a, b, c, d = original(...)
			fn(...)
			return a, b, c, d
		end
	end
	state.addonLoaders = {}
	env.EventUtil = { ContinueOnAddOnLoaded = function(name, fn)
		if name == "KSUI" then state.loadedName = name; state.onLoaded = fn else state.addonLoaders[name] = fn end
	end }
	local function shownTexture() local t = texture(); function t:SetShown(v) self.shown = v end; return t end
	env.Minimap = { SetMaskTexture = function(self, m) self.mask = m end }
	env.MinimapCompassTexture, env.MinimapCompassTextureUnderlay = shownTexture(), shownTexture()
	local diel = { ClearAllPoints = function(self) self.point = nil end, SetPoint = function(self, ...) self.point = { ... } end }
	env.GameTimeFrame = {}
	env.MinimapCluster = { DielFrame = diel, MinimapContainer = { GetScale = function() return 2 end } }
	function env.MinimapCluster:UpdateMinimapConfig()
		env.Minimap:SetMaskTexture("ui-hud-minimap-frame-generic-mask")
		env.MinimapCompassTexture:SetShown(true)
	end
	function env.MinimapCluster:SetEditModeScale()
		diel:ClearAllPoints()
		diel:SetPoint("CENTER", 110, 172)
	end
	function env.GetCVarBool(name)
		if name == "showSwingTimer" then return state.blizzardSwingTimer == true end
		assert(name == "rotateMinimap")
		return state.rotate
	end
	function env.issecretvalue(v) return v == SECRET end
	function env.canaccesstable(t) assert(t ~= SECRET, "secret passed to canaccesstable"); return not t.locked end
	function env.UnitExists(u) return state.units[u] ~= nil end
	function env.UnitIsPlayer(u) return state.units[u].player end
	function env.UnitClass(u) return "Localized", state.units[u] and state.units[u].class end
	function env.UnitAffectingCombat() return state.combat end
	function env.UnitPowerType(u) return (u and state.units[u] and state.units[u].powerType) or state.powerType or 0,
		state.powerToken or "MANA" end
	function env.UnitIsConnected(u) return not state.units[u].offline end
	function env.UnitIsDeadOrGhost(u) return state.units[u].dead == true end
	-- state.units[u] may carry health, maxHealth, power, level, name, far, hiddenIdentity; SECRET stands in for any of them.
	local function field(u, key, default) local v = state.units[u][key]; if v == nil then return default end; return v end
	function env.UnitHealth(u) return field(u, "health", 80) end
	function env.UnitHealthMax(u) return field(u, "maxHealth", 100) end
	function env.UnitGetTotalAbsorbs(u) return field(u, "absorb", 0) end
	function env.UnitGetIncomingHeals(u) return field(u, "incomingHeal", nil) end
	-- state.myAuras[unit] = { { icon, auraInstanceID }, ... } or SECRET for a table that can't be read.
	env.C_UnitAuras = {
		GetUnitAuras = function(unit, filter, max)
			assert(filter == "HELPFUL" or filter == "HARMFUL")
			-- The client raises an error for addon code asking while auras are secret, or for a unit restricted on
			-- its own.
			if state.secretAuras or (state.auraBlocked or {})[unit] then
				error("GetUnitAuras(): Auras cannot be accessed when secret while tainted by 'KSUI'")
			end
			if filter == "HARMFUL" then return (state.myDebuffs or {})[unit] or {} end
			return (state.myAuras or {})[unit] or {}
		end,
		GetAuraDuration = function(unit, id) return { unit = unit, id = id } end,
		GetAuraDataByAuraInstanceID = function(unit, id)
			for _, list in ipairs({ (state.myAuras or {})[unit] or {}, (state.myDebuffs or {})[unit] or {} }) do
				for _, aura in ipairs(list) do
					if aura.auraInstanceID == id then return aura end
				end
			end
		end,
	}
	function env.UnitHealthPercent(u, predicted, curve)
		assert(predicted == true and curve == env.CurveConstants.ScaleTo100)
		local h = field(u, "health", 80)
		if h == SECRET then return SECRET end
		return h
	end
	-- state.locale is the client's language; KSUI was written on a Korean one.
	function env.GetLocale() return state.locale or "koKR" end
	-- state.ammo = count in your quiver, or nil for a class that uses none.
	env.INVSLOT_AMMO = 0
	function env.UnitUsesAmmo(u) assert(u == "player"); return state.ammo ~= nil end
	function env.GetInventoryItemCount(u, slot) assert(u == "player" and slot == 0); return state.ammo end
	function env.UnitPower(u) return field(u, "power", 50) end
	function env.UnitPowerMax(u) return field(u, "maxPower", 100) end
	function env.UnitLevel(u) return field(u, "level", 14) end
	-- Blizzard's own reshaping of the threat glow, as in Blizzard_UnitFrame/Camelot/PlayerFrame.lua.
	function env.PlayerFrame_UpdateFlashTextureVisuals()
		local glow = env.PlayerFrame.PlayerFrameContainer.FrameFlash
		glow:SetAtlas("UI-HUD-UnitFrame-Player-PortraitOn-InCombat")
		glow:SetPoint("CENTER", glow.parent, "CENTER", 0, 0)
	end
	function env.PlayerFrame_UpdateStatusTextureVisuals() state.statusPlaced = env.PlayerFrame.PlayerFrameContainer.FrameFlash.parent end
	function env.GetCreatureDifficultyColor(level) return level == 999 and { r = 1, g = 0.1, b = 0.1 } or { r = 0.5, g = 1, b = 0 } end
	function env.UnitName(u) return field(u, "name", "Name"), state.units[u].surname end
	function env.UnitIsVisible(u) return not state.units[u].far end
	-- state.units[u].outOfRange: true, or SECRET; unchecked = range not known.
	function env.UnitInRange(u)
		local unit = state.units[u]
		if unit.outOfRange == SECRET then return SECRET, SECRET end
		return not unit.outOfRange, not unit.unchecked
	end
	env.C_Secrets = { ShouldUnitIdentityBeSecret = function(u) return state.units[u].hiddenIdentity == true end,
		ShouldAurasBeSecret = function() return state.secretAuras == true end }
	function env.SetPortraitTexture(t, u, noMask) t.portraitOf = { u, noMask } end
	function env.AbbreviateNumbers(n) if n == SECRET then return SECRET end; return tostring(n) end
	env.tostring = tostring
	function env.date() return "11-15 20:09:00" end
	env.CurveConstants = { ScaleTo100 = {} }
	-- A curve records its points; UnitPowerPercent evaluates a step curve the way the client would.
	env.C_CurveUtil = { CreateCurve = function()
		local c = { points = {} }
		function c:SetType(t) self.type = t end
		function c:AddPoint(x, y) self.points[#self.points + 1] = { x, y } end
		return c
	end,
		EvaluateColorValueFromBoolean = function(b, yes, no)
			if b == SECRET then return SECRET end
			return b and yes or no
		end }
	function env.UnitPowerPercent(u, powerType, unmodified, curve)
		assert(powerType == nil and unmodified == false and curve.type == 1)
		local power, max = field(u, "power", 50), field(u, "maxPower", 100)
		if power == SECRET or max == SECRET then return SECRET end
		local share = max > 0 and power / max or 0
		local value = curve.points[1][2]
		for _, p in ipairs(curve.points) do if share >= p[1] then value = p[2] end end
		return value
	end
	-- state.plates = { unit -> plate }; a forbidden plate is simply missing, as GetNamePlateForUnit returns for addons.
	state.plates = state.plates or {}
	env.C_NamePlate = { GetNamePlateForUnit = function(unit, includeForbidden)
		assert(not includeForbidden)
		return state.plates[unit]
	end }
	env.NamePlateDriverFrame = { OnNamePlateAdded = function() end }
	-- state.meter = { available, session = { combatSources, maxAmount } or "LOCKED", calls }
	state.meter = state.meter or { available = true, session = { combatSources = {}, maxAmount = 0 } }
	env.C_DamageMeter = {
		IsDamageMeterAvailable = function() return state.meter.available, "" end,
		GetCombatSessionFromType = function(sessionType, meterType)
			state.meter.asked = { sessionType, meterType }
			if state.meter.session == "LOCKED" then return { locked = true } end
			return copy(state.meter.session)
		end,
		ResetAllCombatSessions = function() state.meter.reset = true end,
		GetAvailableCombatSessions = function() return copy(state.meter.past or {}) end,
		GetCombatSessionFromID = function(id, meterType)
			state.meter.asked = { "id", id, meterType }
			return copy(state.meter.session)
		end,
		GetCombatSessionSourceFromType = function(sessionType, meterType, guid, creatureID)
			assert(guid ~= SECRET and creatureID ~= SECRET, "secret passed to a source query")
			state.meter.sourceAsked = { sessionType, meterType, guid, creatureID }
			return copy(state.meter.spells)
		end,
		GetCombatSessionSourceFromID = function(id, meterType, guid, creatureID)
			state.meter.sourceAsked = { "id", id, meterType, guid }
			return copy(state.meter.spells)
		end,
	}
	function env.SecondsToClock(s) return string.format("%d:%02d", math.floor(s / 60), s % 60) end
	-- The context menu runs its generator at once and keeps the radios it was given.
	env.MenuUtil = { CreateContextMenu = function(owner, generator)
		local root = { radios = {} }
		function root:CreateRadio(text, isSelected, choose, data) self.radios[#self.radios + 1] = { text = text, isSelected = isSelected, choose = choose, data = data } end
		function root:CreateDivider() end
		function root:CreateTitle(text) self.title = text end
		generator(owner, root)
		state.menu = root
	end }
	function env.IsShiftKeyDown() return state.shift end
	-- state.screen = { width, height } of UIParent in UI units; the default is the 1200-tall reference screen.
	local screen = state.screen or { 2133, 1200 }
	env.UIParent = { name = "UIParent", GetWidth = function() return screen[1] end, GetHeight = function() return screen[2] end }
	env.ObjectiveTrackerFrame = { name = "ObjectiveTrackerFrame" }
	-- state.threat = { unit -> { isTanking, percent } }; a missing unit has no threat entry.
	state.threat = state.threat or {}
	function env.UnitDetailedThreatSituation(unit, mob)
		assert(mob == "target")
		local t = state.threat[unit]
		if t then return t[1], 3, t[2], t[2], 100 end
	end
	function env.IsInGroup() return state.group == true end
	function env.UnitCanAttack(a, b) assert(a == "player" and b == "target"); return state.units.target and state.units.target.hostile end
	env.BuffBarCooldownViewer = { name = "BuffBarCooldownViewer" }
	-- state.viewerSpells = { Essential = { spellID or false, ... }, Utility = {...} }; false is an icon with no spell.
	state.viewerSpells = state.viewerSpells or { Essential = { 20271, 853 }, Utility = { 642 } }
	state.viewerItems = {}
	for _, kind in ipairs({ "Essential", "Utility" }) do
		local viewer = { RefreshLayout = function() end, RefreshData = function() end, visibleSetting = 0 }
		function viewer:GetItemFrames()
			local items = {}
			for i, spell in ipairs(state.viewerSpells[kind]) do
				local key = kind .. i
				state.viewerItems[key] = state.viewerItems[key] or { GetFrameLevel = function() return 3 end }
				local item = state.viewerItems[key]
				item.GetBaseSpellID = function() return spell or nil end
				items[#items + 1] = item
			end
			return items
		end
		env[kind .. "CooldownViewer"] = viewer
	end
	env.GameTooltip = { lines = {} }
	function env.GameTooltip:GetUnit() return state.tooltipUnit and "Name", state.tooltipUnit end
	function env.GameTooltip:AddLine(text, r, g, b) self.lines[#self.lines + 1] = { text, r, g, b } end
	function env.GameTooltip_Hide() end
	env.GameTooltipTextLeft1 = texture()
	state.tooltipPostCalls = {}
	env.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) state.tooltipPostCalls[kind] = fn end }
	env.C_ClassColor = { GetClassColor = function(class) return env.RAID_CLASS_COLORS[class] end }
	-- Chat: each frame keeps what reached Blizzard's AddMessage.
	env.NUM_CHAT_WINDOWS = 2
	for i = 1, 2 do
		local frame = { received = {} }
		function frame:AddMessage(text) self.received[#self.received + 1] = text end
		env["ChatFrame" .. i] = frame
	end
	state.linkHandlers, state.popups, state.sounds = {}, {}, {}
	env.LinkUtil = { RegisterLinkHandler = function(kind, fn) state.linkHandlers[kind] = fn end }
	env.StaticPopupDialogs = {}
	function env.StaticPopup_Show(name, _, _, data) state.popups[#state.popups + 1] = { name, data } end
	function env.StaticPopup_FindVisible(name) return state.visiblePopup == name and state.popupDialog or nil end
	function env.StaticPopup_Hide(name) state.hiddenPopup = name end
	env.CLOSE, env.ACCEPT, env.CANCEL = "닫기", "수락", "취소"
	-- A stand-in for the client's encoders that round-trips and fails on anything it didn't make, as the real ones
	-- raise errors on broken input. state.blobs keeps every serialized table.
	state.blobs = state.blobs or {}
	local function unwrap(tag, s)
		if type(s) ~= "string" or s:sub(1, #tag) ~= tag then error("bad input") end
		return s:sub(#tag + 1)
	end
	env.C_EncodingUtil = {
		SerializeCBOR = function(value) state.blobs[#state.blobs + 1] = copy(value); return "cbor" .. #state.blobs end,
		DeserializeCBOR = function(s)
			local blob = state.blobs[tonumber(unwrap("cbor", s))]
			if blob == nil then error("bad input") end
			return copy(blob)
		end,
		CompressString = function(s) return "z" .. s end,
		DecompressString = function(s) return unwrap("z", s) end,
		EncodeBase64 = function(s) return "b" .. s end,
		DecodeBase64 = function(s) return unwrap("b", s) end,
	}
	env.pcall = pcall
	env.unpack, env.next = unpack, next
	env.SOUNDKIT = { TELL_MESSAGE = 3081 }
	function env.PlaySound(id) state.sounds[#state.sounds + 1] = id end
	-- Quests: state.npc = { gossipActive = {...}, gossipAvailable = {...}, active = {...}, available = {...},
	-- completable, choices, pvp }; picks land in state.picked.
	state.npc = state.npc or {}
	state.picked = {}
	local function pick(what) return function(arg) state.picked[#state.picked + 1] = { what, arg } end end
	env.C_GossipInfo = {
		GetActiveQuests = function() return state.npc.gossipActive or {} end,
		GetAvailableQuests = function() return state.npc.gossipAvailable or {} end,
		SelectActiveQuest = pick("active"), SelectAvailableQuest = pick("available"),
	}
	function env.GetNumActiveQuests() return #(state.npc.active or {}) end
	function env.GetActiveTitle(i) return "Quest", state.npc.active[i] end
	function env.GetNumAvailableQuests() return #(state.npc.available or {}) end
	-- Forever has no IsAvailableQuestTrivial; Blizzard's quest frame reads GetAvailableQuestInfo's first value.
	-- An entry is isTrivial, or { isTrivial, frequency, isRepeatable, isLegendary, questID }.
	function env.GetAvailableQuestInfo(i)
		local a = state.npc.available[i]
		if type(a) == "table" then return unpack(a) end
		return a
	end
	function env.GetActiveQuestID(i) return (state.npc.activeIDs or {})[i] or 0 end
	function env.GetQuestID() return state.npc.questID or 0 end
	function env.GetQuestMoneyToGet() return state.npc.money or 0 end
	env.SelectActiveQuest, env.SelectAvailableQuest = pick("greetingActive"), pick("greetingAvailable")
	env.AcceptQuest, env.CompleteQuest, env.GetQuestReward = pick("accept"), pick("complete"), pick("reward")
	function env.QuestFlagsPVP() return state.npc.pvp end
	function env.IsQuestCompletable() return state.npc.completable end
	function env.GetNumQuestChoices() return state.npc.choices or 0 end
	function env.IsShiftKeyDown() return state.shift end
	-- Loot, invites, experience, movies.
	state.looted = {}
	function env.GetNumLootItems() return state.lootCount or 0 end
	function env.LootSlot(slot) state.looted[#state.looted + 1] = slot end
	function env.IsGuildMember(guid) return guid == "guildie" end
	env.C_FriendList = { IsFriend = function(guid) return guid == "friend" end }
	env.C_BattleNet = { GetAccountInfoByGUID = function() return nil end }
	function env.AcceptGroup() state.acceptedGroup = true end
	env.GameRulesUtil = { IsPlayerAtEffectiveMaxLevel = function() return state.maxLevel end }
	function env.IsXPUserDisabled() return false end
	function env.UnitXP() return state.xp or 250 end
	function env.UnitXPMax() return 1000 end
	function env.GetXPExhaustion() return state.rested end
	function env.BreakUpLargeNumbers(n) return tostring(n) end
	env.MovieFrame = { finished = {} }
	function env.MovieFrame:PlayMovie() end
	function env.MovieFrame:OnMovieFinished(userCanceled) self.finished[#self.finished + 1] = userCanceled end
	function env.CinematicFrame_CancelCinematic() state.cutsceneCancelled = (state.cutsceneCancelled or 0) + 1 end
	function env.GetSubZoneText() return state.subzone or "" end
	function env.UnitIsUnit(a, b) return a == b end
	function env.UnitGroupRolesAssigned(u) return (state.roles or {})[u] or "NONE" end
	state.drivers = {}
	function env.RegisterStateDriver(frame, kind, rule) state.drivers[frame] = rule end
	function env.UnregisterStateDriver(frame) state.drivers[frame] = nil end
	env.MainStatusTrackingBarContainer = env.CreateFrame("Frame")
	-- Blizzard's experience bar, whose text shows on mouseover.
	state.blizzardXPText = { visible = false }
	function state.blizzardXPText:IsVisible() return self.visible end
	local xpBar = { OverlayFrame = { Text = state.blizzardXPText } }
	function env.MainStatusTrackingBarContainer:GetChildren() return xpBar, {} end
	function env.MainStatusTrackingBarContainer:GetFrameLevel() return 3 end
	-- state.quest = { map, player = {x, y} or nil, facing, supertracked, waypoint = {x, y}, onMap = {...}, log = {...} }
	-- World positions here are the map position scaled: north is -y on the map, west is -x.
	state.quest = state.quest or { map = 1420, player = { 0.5, 0.5 }, facing = 0, supertracked = 516,
		onMap = { { questID = 516, x = 0.5, y = 0.4 } }, log = {} }
	local function vec(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
	env.CreateVector2D = vec
	env.C_Map = { GetBestMapForUnit = function() return state.quest.map end,
		GetPlayerMapPosition = function() local p = state.quest.player; return p and vec(p[1], p[2]) end,
		GetMapWorldSize = function() return 1000, 1000 end }
	function env.GetPlayerFacing() return state.quest.facing end
	env.C_SuperTrack = { GetSuperTrackedQuestID = function() return state.quest.supertracked end,
		SetSuperTrackedQuestID = function(id) state.quest.supertracked = id end }
	env.C_Navigation = { GetDistance = function() return 2066.87 end }
	env.C_QuestLog = {
		IsQuestTrivial = function(id) return state.npc.trivialQuest == id end,
		IsRepeatableQuest = function(id) return (state.npc.repeatable or {})[id] == true end,
		GetNextWaypointForMap = function() local w = state.quest.waypoint; if w then return w[1], w[2] end end,
		GetQuestsOnMap = function() return state.quest.onMap end,
		GetNumQuestLogEntries = function() return #state.quest.log end,
		GetInfo = function(i) return state.quest.log[i] end,
		GetDistanceSqToQuest = function(id)
			for _, q in ipairs(state.quest.log) do if q.questID == id then return q.distanceSq, q.onContinent end end
		end,
	}
	state.timers = {}
	env.C_Timer = { After = function(_, fn) state.timers[#state.timers + 1] = fn end }
	env.AlertFrame = { ClearAllPoints = function(self) self.point = nil end, SetPoint = function(self, ...) self.point = { ... } end }
	env.KSUIDamageMeter = { name = "KSUIDamageMeter", IsShown = function() return state.meterShown ~= false end }
	function env.GameTooltip_SetDefaultAnchor() end
	env.PowerBarColor = { MANA = { r = 0, g = 0, b = 1 }, RAGE = { r = 1, g = 0, b = 0 } }
	function env.IsInRaid() return state.raid ~= nil end
	function env.GetNumGroupMembers() return state.groupSize or 0 end
	state.usable = {}
	env.C_ActionBar = {
		IsUsableAction = function(action)
			local u = state.usable[action] or "usable"
			return u == "usable", u == "mana"
		end,
		HasAction = function(slot) return slot == state.interruptSlot or slot == 1201 or (state.actions or {})[slot] ~= nil end,
		IsInterruptAction = function(slot) return slot == state.interruptSlot end,
		GetActionTexture = function(slot) return "icon" .. slot end,
		GetActionCooldownDuration = function(slot, ignoreGCD) return { slot = slot, ignoreGCD = ignoreGCD } end,
	}
	-- state.cast = { channel = bool, notInterruptible = bool or SECRET, secret = bool }
	local function castInfo(channel)
		local c = state.cast
		if not c or (c.channel or false) ~= channel then return nil end
		local name = c.secret and SECRET or "Fireball"
		if channel then return name, "Drain", 1, 99000, 102000, false, c.notInterruptible end
		return name, "Fireball", 1, 99000, 102000, false, 7, c.notInterruptible
	end
	-- state.actions = { slot -> spellID }
	function env.GetActionInfo(slot) local id = (state.actions or {})[slot]; if id then return "spell", id end end
	function env.UnitCastingInfo(unit) assert(unit == "target"); return castInfo(false) end
	function env.UnitChannelInfo(unit) assert(unit == "target"); return castInfo(true) end
	-- Real rank 1 IDs map to Korean names; an ID missing from the game returns nil.
	local SPELLS = { [1243] = "신의 권능: 인내", [21562] = "인내의 기원", [1126] = "야생의 징표", [21849] = "야생의 선물",
		[1459] = "신비한 지능", [23028] = "신비한 총명함",
		[853] = "심판의 망치", [5588] = "심판의 망치", [20271] = "심판",
		[17] = "신의 권능: 보호막", [139] = "소생", [774] = "회복", [1022] = "보호의 축복", [6788] = "약화된 영혼", [7812] = "희생" }
	env.C_Spell = { GetSpellName = function(id) return SPELLS[id] end,
		-- Like the client: icon, original icon, conditional icon.
		GetSpellTexture = function(id) return "tex" .. tostring(id), 1, 2 end }
	-- state.auras are your buffs; state.unitAuras[unit] anyone else's.
	function env.C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
		assert(filter == "HELPFUL")
		if state.secretAuras or (state.auraBlocked or {})[unit] then
			error("GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by 'KSUI'")
		end
		local list = (state.unitAuras or {})[unit] or (env.UnitIsUnit(unit, "player") and state.auras) or {}
		local name = list[i]
		if name == "SECRET_RESULT" then return SECRET end
		if name == "LOCKED" then return { name = "x", locked = true } end
		return name and { name = name } or nil
	end
	state.sold, state.repaired = 0, 0
	env.C_MerchantFrame = {
		IsSellAllJunkEnabled = function() return true end,
		GetNumJunkItems = function() return state.junk or 0 end,
		SellAllJunkItems = function() state.sold = state.sold + 1 end,
	}
	function env.CanMerchantRepair() return state.canRepair end
	function env.GetRepairAllCost() return state.repairCost or 0, not state.repairRefused end
	function env.GetMoney() return state.money or 0 end
	function env.RepairAllItems(guild) assert(guild == nil); state.repaired = state.repaired + 1 end
	env.C_CurrencyInfo = { GetCoinTextureString = function(amount) return amount .. "c" end }
	function env.ActionButton_UpdateRangeIndicator() end
	function env.UnitSelectionColor() return 0.9, 0.1, 0.1, 1 end
	function env.InCombatLockdown() return state.combat end
	state.cvars = {}
	function env.SetCVar(k, v) state.cvars[k] = v end
	function env.CreateFont(name)
		local f = {}
		function f:SetFont(path, size, flags) state.font = { name, path, size, flags } end
		return f
	end
	env.CopyTable = copy
	function env.tAppendAll(target, source)
		for _, v in ipairs(source) do target[#target + 1] = v end
	end
	state.log = {}
	function env.print(message) state.printed = message; state.log[#state.log + 1] = message end
	function env.ReloadUI() state.reloaded = true end
	env.C_AddOns = { GetAddOnMetadata = function(_, key) return key == "Version" and "0.11.0" or nil end }
	env.SlashCmdList = {}
	env.Enum = {
		LuaCurveType = { Linear = 0, Step = 1 },
		QuestFrequency = { Default = 0, Daily = 1, Weekly = 2 },
		TooltipDataType = { Unit = 2 },
		EditModeCooldownViewerSetting = { VisibleSetting = 6 },
		EditModeMinimapSetting = { HeaderUnderneath = 0 },
		EditModeMicroMenuSetting = { Size = 2 },
		EditModeBagsSetting = { Size = 2 },
		CooldownViewerVisibleSetting = { Always = 0, InCombat = 1, Hidden = 2 },
		EditModeSystem = { ActionBar = 0, CastBar = 1, Minimap = 2, UnitFrame = 3, AuraFrame = 6, ChatFrame = 8, HudTooltip = 11,
			ObjectiveTracker = 12, MicroMenu = 13, Bags = 14, StatusTrackingBar = 15, DurabilityFrame = 16, CooldownViewer = 20, VehicleLeaveButton = 9, GroupFinder = 27,
			MainActionBarEndCap = 26, DamageMeter = 23, SwingTimer = 29 },
		EditModeSwingTimerSystemIndices = { MainHand = 1, OffHand = 2, Ranged = 3 },
		EditModeSwingTimerSetting = { Scale = 0, Opacity = 1, Visibility = 2, Width = 3 },
		EditModeSwingTimerVisibility = { Always = 0, InCombat = 1, Hidden = 2 },
		DamageMeterType = { DamageDone = 0, HealingDone = 2, DamageTaken = 7 },
		DamageMeterSessionType = { Overall = 0, Current = 1 },
		EditModeDamageMeterSetting = { Visibility = 0 },
		DamageMeterVisibility = { Always = 0, Hidden = 2 },
		EditModeCooldownViewerSystemIndices = { Essential = 1, Utility = 2, BuffIcon = 3, BuffBar = 4 },
		EditModeActionBarSystemIndices = { MainBar = 1, Bar2 = 2, Bar3 = 3, RightBar1 = 4, RightBar2 = 5, StanceBar = 11, PetActionBar = 12 },
		EditModeActionBarSetting = { Orientation = 0, NumRows = 1, NumIcons = 2, IconSize = 3, HideBarArt = 6, AlwaysShowButtons = 9 },
		EditModeMainActionBarEndCapSetting = { Hidden = 0 },
		EditModeMainActionBarEndCapSystemIndices = { EndCapLeft = 1, EndCapRight = 2 },
		ActionBarOrientation = { Horizontal = 0, Vertical = 1 },
		EditModeCastBarSetting = { BarSize = 0, LockToPlayerFrame = 1 },
		EditModeAuraFrameSystemIndices = { BuffFrame = 1, DebuffFrame = 2 },
		EditModeObjectiveTrackerSetting = { Height = 0, Opacity = 1 },
		EditModeUnitFrameSystemIndices = { Player = 1, Target = 2, Focus = 3, Party = 4, Raid = 5, Boss = 6 },
		EditModeLayoutType = { Preset = 0, Account = 1, Character = 2 },
		EditModeUnitFrameSetting = { UseRaidStylePartyFrames = 4, ViewRaidSize = 9, FrameWidth = 10, FrameHeight = 11, RaidGroupDisplayType = 13, RowSize = 15, FrameSize = 16 },
		RaidGroupDisplayType = { SeparateGroupsVertical = 0, CombineGroupsHorizontal = 3 },
		PowerType = { Mana = 0, Rage = 1 },
		ViewRaidSize = { Ten = 0, Forty = 2 },
	}
	env.Constants = { EditModeConsts = { EditModeMaxLayoutsPerType = 2 },
		CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
	env.EditModePresetLayoutManager = {
		GetCopyOfPresetLayouts = function() return copy(state.presets or {}) end,
	}
	env.C_EditMode = {
		GetLayouts = function() return { activeLayout = state.active or 0, layouts = copy(state.layouts or {}) } end,
		SaveLayouts = function(info) state.saved = info end,
		SetActiveLayout = function(index) state.activated = index end,
	}
	env.STANDARD_TEXT_FONT = "Fonts\\2002.TTF"
	env.RAID_CLASS_COLORS = setmetatable({ MAGE = { r = 0.2, g = 0.8, b = 0.9 } }, {
		__index = function(_, key)
			if key == SECRET then error("secret value used as table key") end
		end,
	})
	mockSettings(env, state)

	local function alphaFrame(f)
		f = f or {}
		function f:SetAlpha(a) self.alpha = a end
		return f
	end
	env.PlayerFrame = {
		PlayerFrameContainer = alphaFrame({
			FrameTexture = texture(), VehicleFrameTexture = texture(), AlternatePowerFrameTexture = texture(), FrameFlash = texture(),
		}),
		PlayerFrameContent = { PlayerFrameContentMain = alphaFrame({ HealthBarsContainer = { HealthBar = bar() } }) },
	}
	local spellbar = { alpha = 1 }
	function spellbar:ApplyAlpha(a) self:SetAlpha(a) end
	spellbar.HoldFadeOutAnim = { Stop = function(self) self.stopped = true end }
	function spellbar:PlayInterruptAnims() self.HoldFadeOutAnim.stopped = false; self:SetAlpha(1) end
	function spellbar:SetAlpha(a) self.alpha = a end
	function env.CreateColor(r, g, b) return { r = r, g = g, b = b } end
	function env.GetTime() return state.now or 100 end
	-- Blizzard's target aura row: Blizzard puts it under its own art.
	local function withAuras(f)
		f.auras = { points = {}, mirrored = false }
		function f.auras:ClearAllPoints() self.points = {} end
		function f.auras:SetPoint(...) self.points[#self.points + 1] = { ... } end
		function f.auras:IsProtected() return false end
		function f.auras:IsFlowLayoutMirroredVertically() return self.mirrored end
		function f:GetAuraContainer() return self.auras end
		function f:AnchorAuraContainer() self.auras:ClearAllPoints(); self.auras:SetPoint("TOPLEFT", "blizzard art") end
		return f
	end
	env.TargetFrame = withAuras({
		spellbar = spellbar,
		TargetFrameContainer = alphaFrame({ FrameTexture = texture() }),
		TargetFrameContent = { TargetFrameContentMain = alphaFrame({ HealthBarsContainer = { HealthBar = bar() } }) },
	})
	env.MainActionBar = alphaFrame({
		EndCaps = { LeftEndCap = { Texture = texture() }, RightEndCap = { Texture = texture() } },
	})
	-- StanceBar and PetActionBar are left out on purpose: a missing bar must be skipped.
	for _, name in ipairs({ "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft", "MultiBar7" }) do
		env[name] = alphaFrame()
	end
	env.FocusFrame = withAuras({
		TargetFrameContainer = alphaFrame({ FrameTexture = texture() }),
		TargetFrameContent = { TargetFrameContentMain = alphaFrame() },
	})
	-- Blizzard_SwingTimer's bars; state.noSwingTimer leaves them out, as on a client without them.
	if not state.noSwingTimer then
		for _, name in ipairs({ "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }) do
			local border = texture()
			env[name] = { name = name, GetBorder = function() return border end }
		end
	end
	-- Your pet's frame and its parts, which are globals in Blizzard_UnitFrame/Mainline/PetFrame.xml.
	env.PetFrame = alphaFrame({ name = "PetFrame", hitInsets = { 7, 66, 6, 7 } })
	env.PetFrame.GetHitRectInsets = function(self) return unpack(self.hitInsets) end
	env.PetFrame.SetHitRectInsets = function(self, ...)
		assert(not state.combat, "PetFrame hit rect changed in combat")
		self.hitInsets = { ... }
	end
	for _, part in ipairs({ "PetFrameTexture", "PetPortrait", "PetName", "PetFrameHealthBar", "PetFrameManaBar",
		"PetFrameFlash", "PetAttackModeTexture" }) do
		env[part] = alphaFrame({ name = part })
	end
	-- The target's target frame, which Blizzard redraws from TargetFrame's updates.
	if not state.noToT then
		env.TargetFrameToT = alphaFrame({ name = "TargetFrameToT", FrameTexture = alphaFrame(), Portrait = alphaFrame(),
			Name = alphaFrame(), HealthBar = alphaFrame(), ManaBar = alphaFrame() })
		function env.TargetFrameToT:Update() state.totRedraws = (state.totRedraws or 0) + 1 end
	end
	env.MAX_BOSS_FRAMES = 5
	for i = 1, env.MAX_BOSS_FRAMES do
		env["Boss" .. i .. "TargetFrame"] = { TargetFrameContainer = { FrameTexture = texture() } }
	end
	local function partyMember(i)
		local member = { unitToken = "party" .. i, GetWidth = function() return 120 end, Texture = texture(), VehicleTexture = texture(), Flash = texture(),
			Portrait = texture(), Name = texture(), HealthBarContainer = alphaFrame(), ManaBar = alphaFrame(),
			AuraFrameContainer = texture(), GetFrameLevel = function() return 4 end }
		-- Blizzard's art update sets the glow back to its own spot, as in Blizzard_UnitFrame/Mainline/PartyMemberFrame.lua.
		function member:ToPlayerArt() self.Flash:SetAtlas("ui-hud-unitframe-party-portraiton-incombat"); self.Flash:SetPoint("TOPLEFT", self) end
		function member:ToVehicleArt() end
		function member:ToCharacterStyleArt() end
		function member:UpdateArt() self:ToPlayerArt() end
		return member
	end
	local partyMembers = state.noParty and {} or { partyMember(1), partyMember(2) }
	env.partyMembers = partyMembers
	env.newPartyMember = partyMember
	env.EditModeManagerFrame = { UseRaidStylePartyFrames = function() return state.raidStyleParty end }
	env.SettingsPanel = { hooks = {} }
	function env.SettingsPanel:HookScript(name, fn) self.hooks[name] = fn end
	env.PartyFrame = { InitializePartyMemberFrames = function() end, UpdatePartyFrames = function() end, PartyMemberFramePool = {
		EnumerateActive = function()
			local i = 0
			return function()
				i = i + 1
				return partyMembers[i]
			end
		end,
	} }
	-- MultiBar5Button and later are left out on purpose: those bars may not exist.
	for _, prefix in ipairs({ "ActionButton", "MultiBarBottomLeftButton" }) do
		for i = 1, 12 do
			local button = {
				NormalTexture = texture(), SlotArt = texture(), SlotBackground = texture(), icon = texture(),
				cooldown = { SetCountdownFont = function(self, f) self.font = f end },
				action = #prefix * 100 + i,
			}
			-- Same colors as Blizzard's ActionBarActionButtonMixin:UpdateUsable.
			function button:UpdateUsable()
				local usable, mana = env.C_ActionBar.IsUsableAction(self.action)
				if usable then self.icon:SetVertexColor(1, 1, 1)
				elseif mana then self.icon:SetVertexColor(0.5, 0.5, 1)
				else self.icon:SetVertexColor(0.4, 0.4, 0.4) end
			end
			env[prefix .. i] = button
		end
	end
	return env
end

local ADDON_DIR = "addons/KSUI/"

local function tocFiles()
	local files = {}
	for line in io.lines(ADDON_DIR .. "KSUI.toc") do
		if line ~= "" and line:sub(1, 2) ~= "##" then files[#files + 1] = line end
	end
	return files
end

-- Unit events reach only frames registered for that unit, as RegisterUnitEvent does. Older tests omit the target unit.
local function fire(env, event, unit, ...)
	for _, h in ipairs(env.events) do
		local wanted = h.frame.units and h.frame.units[event]
		if h.frame.registered[event] and (not wanted or wanted == (unit or "target")) then h.fn(h.frame, event, unit, ...) end
	end
end

-- Loads the addon the way the client does: TOC order, shared namespace, then saved variables.
local function boot(state, opts)
	local env = world(state)
	env.KSUIDB = state.savedDB
	local ns = {}
	for _, file in ipairs(tocFiles()) do
		local chunk = assert(loadfile(ADDON_DIR .. file))
		setfenv(chunk, env)
		chunk("KSUI", ns)
	end
	state.onLoaded()
	if not (opts and opts.noLogin) then fire(env, "PLAYER_LOGIN") end
	return env, ns
end

local function near(a, b) return math.abs(a - b) < 0.002 end
local mage = { player = true, class = "MAGE" }
local function hpOf(frame, content, main) return frame[content][main].HealthBarsContainer.HealthBar end
local function playerHp(env) return hpOf(env.PlayerFrame, "PlayerFrameContent", "PlayerFrameContentMain") end
local function targetHp(env) return hpOf(env.TargetFrame, "TargetFrameContent", "TargetFrameContentMain") end

do
	local state = { units = { player = mage } }
	local env = boot(state)
	local frame = env.PlayerFrame.PlayerFrameContainer.FrameTexture
	local hp = playerHp(env)
	local button = env.ActionButton1
	check("addon name", state.loadedName == "KSUI")
	check("defaults saved", env.KSUIDB.darkUnitFrames == true and env.KSUIDB.frameYPct == 18.3)
	check("player frame art darkened", frame.desaturated and near(frame.color[1], 0.278))
	check("end cap darkened", env.MainActionBar.EndCaps.LeftEndCap.Texture.desaturated)
	check("action button darkened", button.NormalTexture.desaturated and near(button.SlotArt.color[3], 0.322))
	check("second bar skinned", env.MultiBarBottomLeftButton12.NormalTexture.desaturated)
	check("icon cropped", near(button.icon.coords[1], 0.07) and near(button.icon.coords[2], 0.93))
	check("player bar class colored", hp.color[1] == 0.2 and hp.desaturated)
	check("target bar untouched without target", targetHp(env).color == nil or targetHp(env).color[1] == 1)

	local before = hp.sets
	hp:SetStatusBarColor(0, 1, 0)
	check("Blizzard recolor overridden", hp.color[1] == 0.2 and hp.color[2] == 0.8)
	check("recolor does not recurse", hp.sets == before + 2)
end

do
	local state = { units = { player = mage, target = { player = true, class = SECRET } } }
	local env = boot(state)
	fire(env, "PLAYER_TARGET_CHANGED")
	local hp = targetHp(env)
	check("secret class is not used as a table key", hp.color[1] == 0.6)
	state.units.target = { player = false }
	fire(env, "PLAYER_TARGET_CHANGED")
	check("NPC uses selection color", hp.color[1] == 0.9)
	state.units.target = { player = true, class = "MAGE" }
	fire(env, "PLAYER_TARGET_CHANGED")
	check("visible class colored", hp.color[1] == 0.2)
	state.units.target = { player = true, class = "NOT_A_CLASS" }
	fire(env, "PLAYER_TARGET_CHANGED")
	check("unknown class falls back to gray", hp.color[1] == 0.6)
end

do
	local state = { units = { player = mage } }
	local env = boot(state, { noLogin = true })
	fire(env, "PLAYER_TARGET_CHANGED")
	check("target event before login is safe", true)
end

-- Options panel
do
	local state = { units = { player = mage } }
	local env, ns = boot(state)
	check("category registered", state.registered == ns.category and state.categoryName == "검성UI")
	check("checkbox control", state.controls.KSUI_darkUnitFrames.kind == "checkbox")
	check("color control", state.controls.KSUI_artColor.kind == "color")
	check("slider control", state.controls.KSUI_cooldownFontSize.kind == "slider")
	check("slider range", state.controls.KSUI_frameXPct.options.max == 30 and state.controls.KSUI_frameXPct.options.formatter == 1)
	check("slider numbers rounded to the step", state.controls.KSUI_frameXPct.options.format(6.0937498183921) == "6.1"
		and state.controls.KSUI_fadeAlpha.options.format(0.4) == "0.40"
		and state.controls.KSUI_cooldownFontSize.options.format(14) == "14")
	check("button present", state.button and state.button.buttonClick == ns.ApplyLayout)
	check("quick buttons first", state.headers[1] == "빠른 실행")
	check("sections", #state.headers == 7)
	state.buttons["UI 다시 불러오기"].buttonClick()
	check("reload button reloads", state.reloaded == true)

	local frame = env.PlayerFrame.PlayerFrameContainer.FrameTexture
	state.settings.artColor:SetValue("ffff0000")
	check("color applies live", near(frame.color[1], 1) and near(frame.color[2], 0))
	check("color reaches action bars", near(env.ActionButton3.SlotArt.color[1], 1))

	state.settings.darkUnitFrames:SetValue(false)
	check("unit art restored", frame.desaturated == false and frame.color[1] == 1 and frame.color[2] == 1)
	check("action bars stay dark", env.ActionButton1.NormalTexture.desaturated)
	state.settings.darkActionBars:SetValue(false)
	check("action art restored", env.ActionButton1.NormalTexture.desaturated == false and env.MainActionBar.EndCaps.RightEndCap.Texture.color[1] == 1)

	state.settings.cropIcons:SetValue(false)
	check("icon crop removed", env.ActionButton1.icon.coords[1] == 0 and env.ActionButton1.icon.coords[2] == 1)

	local hp = playerHp(env)
	state.settings.classColorBars:SetValue(false)
	check("bar color restored", hp.desaturated == false and hp.color[1] == 1 and hp.color[3] == 1)
	hp:SetStatusBarColor(0, 1, 0)
	check("Blizzard color kept when disabled", hp.color[1] == 0 and hp.color[2] == 1)
	state.settings.classColorBars:SetValue(true)
	check("bar color returns", hp.color[1] == 0.2 and hp.desaturated)

	state.settings.cooldownFontSize:SetValue(24)
	check("font size live", state.font[3] == 24 and state.font[4] == "OUTLINE")
	state.settings.cooldownNumbers:SetValue(false)
	check("cooldown numbers off", state.cvars.countdownForCooldowns == "0")
	check("raid class colors default on", state.cvars.raidFramesDisplayClassColor == "1")
	state.settings.raidClassColors:SetValue(false)
	check("raid class colors off", state.cvars.raidFramesDisplayClassColor == "0")

	env.SlashCmdList.KSUI("")
	check("slash opens options", state.opened == 42)
end

-- Saved values
do
	local state = { units = { player = mage }, savedDB = { darkUnitFrames = false, artColor = "ff00ff00", frameX = 50, cooldownFontSize = 20 } }
	local env = boot(state)
	local frame = env.PlayerFrame.PlayerFrameContainer.FrameTexture
	check("saved toggle honored", frame.desaturated == false)
	check("saved color honored", near(env.ActionButton1.NormalTexture.color[2], 1))
	check("saved size honored", state.font[3] == 20)
	check("old position becomes the same share of the reference screen", near(env.KSUIDB.frameXPct, 50 / (1200 * 16 / 9) * 100)
		and env.KSUIDB.frameX == nil and env.KSUIDB.positionsVersion == 2)
	check("missing value defaulted", env.KSUIDB.frameYPct == 18.3)
end

do
	-- A damaged or hand-edited position doesn't stop the load.
	local state = { units = { player = mage }, savedDB = { frameX = "invalid", groupXPct = "x" } }
	local env = boot(state)
	check("a position that isn't a number is dropped", env.KSUIDB.frameXPct == 6.1 and env.KSUIDB.frameX == nil
		and type(env.KSUIDB.groupXPct) == "number")
end

-- Square minimap
do
	local state = { units = { player = mage }, rotate = true }
	local env = boot(state)
	local square = "Interface\\ChatFrame\\ChatFrameBackground"
	local border
	for _, f in ipairs(state.frames) do
		if f.parent == env.Minimap then border = f end
	end
	check("minimap square by default", env.Minimap.mask == square and env.MinimapCompassTexture.shown == false
		and env.MinimapCompassTextureUnderlay.shown == false)
	check("minimap border shown", border.shown == true and border.template == "BackdropTemplate" and border.borderColor[1] == 0)
	check("minimap shape reported", env.GetMinimapShape() == "SQUARE")
	local diel = env.MinimapCluster.DielFrame
	local function dielBesideClock() return diel.point[1] == "LEFT" and diel.point[2] == env.GameTimeFrame and diel.point[3] == "RIGHT" end
	check("day icon beside the clock", dielBesideClock())
	env.MinimapCluster:SetEditModeScale(2)
	check("day icon stays after resize", dielBesideClock())

	env.MinimapCluster:UpdateMinimapConfig()
	check("square kept after rotation toggle", env.Minimap.mask == square and env.MinimapCompassTexture.shown == false)

	env.HybridMinimap = { CircleMask = texture() }
	state.addonLoaders.Blizzard_HybridMinimap()
	check("hybrid minimap squared", env.HybridMinimap.CircleMask.file == square)

	state.settings.squareMinimap:SetValue(false)
	check("round minimap restored", env.Minimap.mask == "ui-hud-minimap-frame-generic-mask"
		and env.MinimapCompassTexture.shown == true and env.MinimapCompassTextureUnderlay.shown == true and border.shown == false)
	check("hybrid round restored", env.HybridMinimap.CircleMask.file == "Interface\\CharacterFrame\\TempPortraitAlphaMask")
	check("round shape reported", env.GetMinimapShape() == "ROUND")
	check("day icon back on the ring", diel.point[1] == "CENTER" and diel.point[2] == 110 and diel.point[3] == 172)
end

-- Cooldowns
do
	local state = { units = {} }
	local env = boot(state)
	check("CVar enabled", state.cvars.countdownForCooldowns == "1")
	check("font created", state.font[1] == "KSUICooldownFont" and state.font[3] == 16)
	check("font applied", env.ActionButton12.cooldown.font == "KSUICooldownFont")
end

do
	local state = { units = {}, combat = true }
	local env = boot(state)
	check("CVars untouched in combat", next(state.cvars) == nil)
	check("font applied in combat", env.ActionButton1.cooldown.font == "KSUICooldownFont")
	state.combat = false
	fire(env, "PLAYER_REGEN_ENABLED")
	check("CVars applied after combat", state.cvars.countdownForCooldowns == "1" and state.cvars.raidFramesDisplayClassColor == "1")
end

-- Group content
do
	local state = { units = { player = mage } }
	local env = boot(state)
	check("focus darkened", env.FocusFrame.TargetFrameContainer.FrameTexture.desaturated)
	check("boss darkened", env.Boss5TargetFrame.TargetFrameContainer.FrameTexture.desaturated)
	check("party darkened", env.partyMembers[2].Texture.desaturated)
	state.settings.darkUnitFrames:SetValue(false)
	check("party restored", env.partyMembers[1].Texture.desaturated == false)
	check("boss restored", env.Boss1TargetFrame.TargetFrameContainer.FrameTexture.color[1] == 1)
end

do
	local state = { units = { player = mage }, noParty = true }
	local env = boot(state)
	env.partyMembers[1] = env.newPartyMember(1)
	env.PartyFrame:InitializePartyMemberFrames()
	check("party joined after login is darkened", env.partyMembers[1].Texture.desaturated)
	state.settings.darkUnitFrames:SetValue(false)
	check("late party frame follows the toggle", env.partyMembers[1].Texture.desaturated == false)
end

do
	local state = { units = { player = mage, target = { player = false } } }
	local env = boot(state)
	env.UnitSelectionColor = function() return SECRET, SECRET, SECRET, 1 end
	fire(env, "PLAYER_TARGET_CHANGED")
	check("secret reaction color passes through to the bar", targetHp(env).color[1] == SECRET)
end

do
	local found = false
	for line in io.lines(ADDON_DIR .. "KSUI.toc") do
		found = found or line == "## SavedVariables: KSUIDB"
	end
	check("settings persist through the TOC", found)
end

-- Lua cannot intercept a boolean test on a mock secret, so the guard order is checked in the source.
do
	local source = assert(io.open(ADDON_DIR .. "Skin.lua")):read("*a")
	check("secrecy is checked before the class is tested", source:find("not issecretvalue(class) and class and", 1, true) ~= nil)
end

do
	local state = { units = { player = mage } }
	local env = boot(state)
	local container = env.PlayerFrame.PlayerFrameContainer
	check("vehicle art darkened", container.VehicleFrameTexture.desaturated)
	check("alternate power art darkened", container.AlternatePowerFrameTexture.desaturated)
end

do
	local state = { units = { player = mage, target = { player = false } } }
	local env = boot(state)
	fire(env, "PLAYER_TARGET_CHANGED")
	env.UnitSelectionColor = function() return 0.1, 0.9, 0.1, 1 end
	fire(env, "UNIT_FACTION")
	check("reaction change recolors the target bar", targetHp(env).color[1] == 0.1)
end

-- Layout
local function systems(playerX)
	return {
		{ system = 3, systemIndex = 1, anchorInfo = { point = "TOPLEFT", offsetX = playerX }, isInDefaultPosition = true,
			settings = { { setting = 16, value = 0 } } },
		{ system = 3, systemIndex = 2, anchorInfo = { point = "TOPLEFT", offsetX = 250 }, isInDefaultPosition = true,
			settings = { { setting = 16, value = 0 } } },
		{ system = 3, systemIndex = 3, anchorInfo = { point = "CENTER", offsetX = 7 }, isInDefaultPosition = true },
		{ system = 0, systemIndex = 1, anchorInfo = { point = "BOTTOM", offsetX = 1 }, isInDefaultPosition = false, settings = {
			{ setting = 6, value = 0 }, { setting = 9, value = 1 },
		} },
		{ system = 3, systemIndex = 4, anchorInfo = { point = "TOPLEFT", offsetX = 0 }, isInDefaultPosition = true, settings = {
			{ setting = 16, value = 0 }, { setting = 4, value = 0 } } },
		{ system = 3, systemIndex = 5, anchorInfo = { point = "TOPLEFT", offsetX = 0 }, isInDefaultPosition = true, settings = {
			{ setting = 9, value = 0 }, { setting = 10, value = 26 }, { setting = 11, value = 8 },
			{ setting = 13, value = 3 }, { setting = 15, value = 7 },
		} },
		{ system = 3, systemIndex = 6, anchorInfo = { point = "RIGHT", offsetX = 8 }, isInDefaultPosition = true },
		{ system = 0, systemIndex = 4, anchorInfo = { point = "RIGHT" }, isInDefaultPosition = true, settings = {
			{ setting = 0, value = 1 }, { setting = 1, value = 2 }, { setting = 2, value = 6 }, { setting = 3, value = 5 },
			{ setting = 9, value = 1 },
		} },
		{ system = 0, systemIndex = 5, anchorInfo = { point = "RIGHT" }, isInDefaultPosition = true, settings = {
			{ setting = 0, value = 1 }, { setting = 1, value = 1 }, { setting = 2, value = 12 },
		} },
		{ system = 0, systemIndex = 11, anchorInfo = { point = "BOTTOM" }, isInDefaultPosition = true },
		{ system = 0, systemIndex = 12, anchorInfo = { point = "BOTTOM" }, isInDefaultPosition = true },
		{ system = 1, anchorInfo = { point = "CENTER" }, isInDefaultPosition = true, settings = {
			{ setting = 0, value = 3 }, { setting = 1, value = 1 },
		} },
		{ system = 6, systemIndex = 1, anchorInfo = { point = "TOPRIGHT" }, isInDefaultPosition = true },
		{ system = 6, systemIndex = 2, anchorInfo = { point = "TOPRIGHT" }, isInDefaultPosition = true },
		{ system = 2, anchorInfo = { point = "TOPRIGHT" }, isInDefaultPosition = true, settings = { { setting = 0, value = 0 } } },
		{ system = 12, anchorInfo = { point = "TOPRIGHT" }, isInDefaultPosition = true, settings = {
			{ setting = 0, value = 40 }, { setting = 1, value = 0 },
		} },
		{ system = 11, anchorInfo = { point = "BOTTOMRIGHT" }, isInDefaultPosition = true },
		{ system = 0, systemIndex = 2, anchorInfo = { point = "BOTTOM" }, isInDefaultPosition = true, settings = {
			{ setting = 3, value = 5 }, { setting = 9, value = 1 },
		} },
		{ system = 0, systemIndex = 3, anchorInfo = { point = "BOTTOM" }, isInDefaultPosition = true, settings = {
			{ setting = 3, value = 5 }, { setting = 9, value = 1 },
		} },
		{ system = 13, anchorInfo = { point = "BOTTOM", offsetX = 116.5 }, isInDefaultPosition = true,
			settings = { { setting = 2, value = 6 } } },
		{ system = 14, anchorInfo = { point = "BOTTOMLEFT", relativeTo = "MicroMenuContainer" }, isInDefaultPosition = true,
			settings = { { setting = 2, value = 5 } } },
		{ system = 15, systemIndex = 1, anchorInfo = { point = "BOTTOM" }, isInDefaultPosition = true },
		{ system = 15, systemIndex = 2, anchorInfo = { point = "BOTTOM", offsetY = 17 }, isInDefaultPosition = true },
		{ system = 8, anchorInfo = { point = "BOTTOMLEFT", offsetX = 35, offsetY = 145 }, isInDefaultPosition = true },
		{ system = 20, systemIndex = 1, anchorInfo = { point = "BOTTOM", offsetY = 310 }, isInDefaultPosition = true,
			settings = { { setting = 6, value = 1 } } },
		{ system = 20, systemIndex = 2, anchorInfo = { point = "BOTTOM", offsetY = 240 }, isInDefaultPosition = true },
		{ system = 20, systemIndex = 3, anchorInfo = { point = "BOTTOM", offsetY = 370 }, isInDefaultPosition = true },
		{ system = 20, systemIndex = 4, anchorInfo = { point = "BOTTOM", offsetX = 420, offsetY = 430 }, isInDefaultPosition = true },
		{ system = 9, anchorInfo = { point = "BOTTOM", relativeTo = "MainActionBar" }, isInDefaultPosition = true },
		{ system = 27, anchorInfo = { point = "CENTER", relativeTo = "Minimap" }, isInDefaultPosition = true },
		-- Swing timers, as in Blizzard_EditMode/Mainline/EditModePresetLayouts.lua.
		{ system = 29, systemIndex = 1, anchorInfo = { point = "BOTTOM", offsetY = 450 }, isInDefaultPosition = true,
			settings = { { setting = 0, value = 5 }, { setting = 2, value = 0 }, { setting = 3, value = 213 } } },
		{ system = 29, systemIndex = 2, anchorInfo = { point = "BOTTOM", offsetY = 425 }, isInDefaultPosition = true,
			settings = { { setting = 0, value = 5 }, { setting = 2, value = 0 }, { setting = 3, value = 213 } } },
		{ system = 29, systemIndex = 3, anchorInfo = { point = "BOTTOM", offsetY = 400 }, isInDefaultPosition = true,
			settings = { { setting = 0, value = 5 }, { setting = 2, value = 0 }, { setting = 3, value = 213 } } },
		{ system = 23, anchorInfo = { point = "RIGHT" }, isInDefaultPosition = true, settings = { { setting = 0, value = 0 } } },
		{ system = 26, systemIndex = 1, anchorInfo = { point = "RIGHT", relativeTo = "MainActionBar" }, isInDefaultPosition = true,
			settings = { { setting = 0, value = 0 } } },
		{ system = 26, systemIndex = 2, anchorInfo = { point = "LEFT", relativeTo = "MainActionBar" }, isInDefaultPosition = true,
			settings = { { setting = 0, value = 0 } } },
		{ system = 16, anchorInfo = { point = "RIGHT" }, isInDefaultPosition = true },
	}
end

local function layoutState(extra)
	local state = {
		units = { player = mage }, active = 2, layouts = {},
		-- A 2000 x 1000 screen turns these shares into round UI units: 130, 220, 20 and 20.
		screen = { 2000, 1000 }, savedDB = { frameXPct = 6.5, frameYPct = 22, groupXPct = 1, groupTopPct = 2, positionsVersion = 2 },
		presets = {
			{ layoutName = "Modern", layoutType = 0, layoutIndex = 0, systems = systems(1) },
			{ layoutName = "Classic", layoutType = 0, layoutIndex = 1, systems = systems(2) },
			{ layoutName = "Gamepad", layoutType = 0, layoutIndex = 2, systems = systems(3) },
		},
	}
	for k, v in pairs(extra or {}) do state[k] = v end
	return state
end

local function runLayout(state)
	local env = boot(state)
	env.SlashCmdList.KSUI("layout")
	state.dbForGeometry = env.KSUIDB
	return env
end

do
	local state = layoutState()
	runLayout(state)
	local saved = state.saved.layouts
	local layout = saved[4]
	check("presets stay first", #saved == 4 and saved[2].layoutName == "Classic")
	check("new account layout", layout.layoutName == "KSUI" and layout.layoutType == 1 and layout.layoutIndex == nil)
	check("activated new slot", state.saved.activeLayout == 4 and state.activated == 4)
	check("reloaded after save", state.reloaded)
	local player, target = layout.systems[1], layout.systems[2]
	check("player moved", player.anchorInfo.point == "BOTTOMRIGHT" and player.anchorInfo.offsetX == -130
		and player.anchorInfo.offsetY == 220 and player.anchorInfo.relativePoint == "BOTTOM" and not player.isInDefaultPosition)
	check("target moved", target.anchorInfo.point == "BOTTOMLEFT" and target.anchorInfo.offsetX == 130
		and target.anchorInfo.offsetY == 220 and not target.isInDefaultPosition)
	local focus, party, raid, boss = layout.systems[3], layout.systems[5], layout.systems[6], layout.systems[7]
	check("focus above target", focus.anchorInfo.point == "BOTTOMLEFT" and focus.anchorInfo.offsetX == 130 and focus.anchorInfo.offsetY == 330)
	check("party in the top-left corner", party.anchorInfo.point == "TOPLEFT" and party.anchorInfo.relativePoint == "TOPLEFT"
		and party.anchorInfo.offsetX == 20 and near(party.anchorInfo.offsetY, -20 - 63 * 1.15) and not party.isInDefaultPosition)
	local partyValues = {}
	for _, info in ipairs(party.settings) do partyValues[info.setting] = info.value end
	check("party frames at 115%, raid-style off", partyValues[16] == 3 and partyValues[4] == 0)
	check("raid in the top-left corner", raid.anchorInfo.point == "TOPLEFT" and raid.anchorInfo.relativeTo == "UIParent"
		and raid.anchorInfo.relativePoint == "TOPLEFT" and raid.anchorInfo.offsetY == -20 and not raid.isInDefaultPosition)
	local raidValues = {}
	for _, info in ipairs(raid.settings) do raidValues[info.setting] = info.value end
	check("raid set up for forty players", raidValues[9] == 2 and raidValues[13] == 0)
	check("raid cells at minimum size", raidValues[10] == 0 and raidValues[11] == 0)
	check("raid row size untouched", raidValues[15] == 7)
	check("preset raid settings not mutated", saved[2].systems[6].settings[2].value == 26)
	local function values(system)
		local result = {}
		for _, info in ipairs(system.settings) do result[info.setting] = info.value end
		return result
	end
	local right1, right2, stance, pet = layout.systems[8], layout.systems[9], layout.systems[10], layout.systems[11]
	local function above(system, frameName)
		local a = system.anchorInfo
		return a.point == "BOTTOMLEFT" and a.relativeTo == frameName and a.relativePoint == "TOPLEFT"
			and a.offsetX == 0 and a.offsetY == 4 and not system.isInDefaultPosition
	end
	check("right bar 1 sits on bottom-left bar", above(right1, "MultiBarBottomLeft"))
	check("right bar 2 sits on bottom-right bar", above(right2, "MultiBarBottomRight"))
	local v1, v2 = values(right1), values(right2)
	check("right bars become one horizontal row of 12", v1[0] == 0 and v1[1] == 1 and v1[2] == 12 and v2[0] == 0 and v2[1] == 1)
	check("right bar icon size untouched", v1[3] == 5)
	check("moved right bar hides empty slots", v1[9] == 0)
	check("stance bar on the right end of the new row", stance.anchorInfo.point == "BOTTOMRIGHT"
		and stance.anchorInfo.relativeTo == "MultiBarRight" and stance.anchorInfo.relativePoint == "TOPRIGHT"
		and stance.anchorInfo.offsetX == 0 and stance.anchorInfo.offsetY == 4 and not stance.isInDefaultPosition)
	check("pet bar above the new row", above(pet, "MultiBarLeft"))
	local leave, eye
	for _, sys in ipairs(layout.systems) do
		if sys.system == 9 then leave = sys end
		if sys.system == 27 then eye = sys end
	end
	local blizzardMeter
	for _, sys in ipairs(layout.systems) do
		if sys.system == 23 then blizzardMeter = sys end
	end
	check("Blizzard's meter window hidden in place", blizzardMeter.settings[1].value == 2 and blizzardMeter.isInDefaultPosition)
	check("queue eye in the bottom-left corner", eye.anchorInfo.point == "BOTTOMLEFT" and eye.anchorInfo.relativeTo == "UIParent"
		and eye.anchorInfo.offsetX == 10 and eye.anchorInfo.offsetY == 10 and not eye.isInDefaultPosition)
	check("exit button beside the player frame", leave.system == 9 and leave.anchorInfo.point == "RIGHT"
		and leave.anchorInfo.relativeTo == "PlayerFrame" and leave.anchorInfo.relativePoint == "LEFT"
		and leave.anchorInfo.offsetX == -8 and not leave.isInDefaultPosition)
	local durability = layout.systems[#layout.systems]
	check("durability figure on the right end of the bar row", durability.system == 16
		and durability.anchorInfo.point == "BOTTOMRIGHT" and durability.anchorInfo.relativeTo == "MultiBarLeft"
		and durability.anchorInfo.relativePoint == "TOPRIGHT" and durability.anchorInfo.offsetY == 4 and not durability.isInDefaultPosition)
	local cast = layout.systems[12]
	check("cast bar on top of the minimap", cast.anchorInfo.point == "BOTTOM" and cast.anchorInfo.relativeTo == "MinimapCluster"
		and cast.anchorInfo.relativePoint == "TOP" and cast.anchorInfo.offsetX == 0 and cast.anchorInfo.offsetY == 6 and not cast.isInDefaultPosition)
	check("cast bar unlocked from player frame", values(cast)[1] == 0 and values(cast)[0] == 3)
	local buffs, debuffs = layout.systems[13], layout.systems[14]
	for _, sys in ipairs(layout.systems) do
		if sys.system == 20 and sys.systemIndex == 1 then
			check("cooldown spell row set to always show", sys.settings[1].value == 0)
		end
	end
	check("buffs left of the cooldown manager", buffs.anchorInfo.point == "TOPRIGHT"
		and buffs.anchorInfo.relativeTo == "EssentialCooldownViewer" and buffs.anchorInfo.relativePoint == "TOPLEFT"
		and buffs.anchorInfo.offsetX == -10 and buffs.anchorInfo.offsetY == 0 and not buffs.isInDefaultPosition)
	check("debuffs above the buffs", debuffs.anchorInfo.relativeTo == "EssentialCooldownViewer" and debuffs.anchorInfo.offsetX == -10
		and debuffs.anchorInfo.offsetY == 100 and not debuffs.isInDefaultPosition)
	local minimap, tracker, tooltip = layout.systems[15], layout.systems[16], layout.systems[17]
	check("minimap sits on the experience bars", minimap.anchorInfo.point == "BOTTOM"
		and minimap.anchorInfo.relativeTo == "SecondaryStatusTrackingBarContainer" and minimap.anchorInfo.relativePoint == "TOP"
		and minimap.anchorInfo.offsetX == 0 and minimap.anchorInfo.offsetY == 4 and not minimap.isInDefaultPosition)
	check("zone name and calendar under the minimap", minimap.settings[1].value == 1)
	for _, sys in ipairs(layout.systems) do
		if sys.system == 13 then check("micro menu at 75%", sys.settings[1].value == 1) end
		if sys.system == 14 then
			check("bags at 75%, left where Blizzard puts them", sys.settings[1].value == 0
				and sys.anchorInfo.relativeTo == "MicroMenuContainer" and sys.isInDefaultPosition)
		end
	end
	local s = layout.systems
	local mainBar, bar2, bar3, micro, bags, xp1, xp2, chat = s[4], s[18], s[19], s[20], s[21], s[22], s[23], s[24]
	check("main bar left of the minimap", mainBar.anchorInfo.point == "BOTTOMRIGHT" and mainBar.anchorInfo.relativeTo == "MinimapCluster"
		and mainBar.anchorInfo.relativePoint == "BOTTOMLEFT" and mainBar.anchorInfo.offsetX == -8 and mainBar.anchorInfo.offsetY == 0
		and not mainBar.isInDefaultPosition)
	check("micro menu right of the minimap", micro.anchorInfo.point == "BOTTOMLEFT" and micro.anchorInfo.relativeTo == "MinimapCluster"
		and micro.anchorInfo.relativePoint == "BOTTOMRIGHT" and micro.anchorInfo.offsetX == 8 and not micro.isInDefaultPosition)
	check("main bar art and empty slots hidden", values(mainBar)[6] == 1 and values(mainBar)[9] == 0)
	check("bags keep following the micro menu", bags.isInDefaultPosition and bags.anchorInfo.relativeTo == "MicroMenuContainer")
	check("bar 2 on the main bar", above(bar2, "MainActionBar"))
	local capLeft, capRight = layout.systems[#layout.systems - 2], layout.systems[#layout.systems - 1]
	check("both gargoyles hidden", capLeft.system == 26 and values(capLeft)[0] == 1 and values(capRight)[0] == 1)
	check("gargoyles keep their anchors", capLeft.isInDefaultPosition and capLeft.anchorInfo.relativeTo == "MainActionBar"
		and capRight.isInDefaultPosition)
	check("preset gargoyles untouched", saved[2].systems[#saved[2].systems - 2].settings[1].value == 0)
	check("bar 3 on the micro menu", above(bar3, "MicroMenuContainer"))
	check("bars 2 and 3 hide empty slots", values(bar2)[9] == 0 and values(bar3)[9] == 0)
	check("bars 2 and 3 keep their icon size", values(bar2)[3] == 5 and values(bar3)[3] == 5)
	check("experience bar at the bottom center", xp1.anchorInfo.point == "BOTTOM" and xp1.anchorInfo.relativeTo == "UIParent"
		and xp1.anchorInfo.offsetX == 0 and xp1.anchorInfo.offsetY == 0 and not xp1.isInDefaultPosition)
	check("second status bar on the first", xp2.anchorInfo.relativeTo == "MainStatusTrackingBarContainer"
		and xp2.anchorInfo.relativePoint == "TOP" and not xp2.isInDefaultPosition)
	check("chat raised to frame height", chat.anchorInfo.point == "BOTTOMLEFT" and chat.anchorInfo.offsetX == 35
		and chat.anchorInfo.offsetY == 220 and not chat.isInDefaultPosition)
	check("tracker in the bottom-right corner", tracker.anchorInfo.point == "BOTTOMRIGHT" and tracker.anchorInfo.relativeTo == "UIParent"
		and tracker.anchorInfo.relativePoint == "BOTTOMRIGHT" and tracker.anchorInfo.offsetX == -10 and tracker.anchorInfo.offsetY == 10
		and not tracker.isInDefaultPosition)
	check("tracker at minimum height", values(tracker)[0] == 0 and values(tracker)[1] == 0)
	check("tooltip anchor stays on Blizzard's tracker", tooltip.anchorInfo.point == "BOTTOMRIGHT" and tooltip.anchorInfo.relativeTo == "ObjectiveTrackerFrame"
		and tooltip.anchorInfo.relativePoint == "TOPRIGHT" and tooltip.anchorInfo.offsetY == 10 and not tooltip.isInDefaultPosition)
	check("preset bar settings not mutated", saved[2].systems[8].settings[1].value == 1)
	check("boss frames above-left of the quest tracker", boss.anchorInfo.point == "BOTTOMRIGHT" and boss.anchorInfo.relativeTo == "ObjectiveTrackerFrame"
		and boss.anchorInfo.relativePoint == "TOPLEFT" and boss.anchorInfo.offsetX == -10 and not boss.isInDefaultPosition)
	check("preset not mutated", saved[2].systems[1].anchorInfo.offsetX == 2)
	local function stacked(system, frameName)
		local a = system.anchorInfo
		return a.point == "BOTTOM" and a.relativeTo == frameName and a.relativePoint == "TOP"
			and a.offsetX == 0 and a.offsetY == 6 and not system.isInDefaultPosition
	end
	check("essential cooldowns on the cast bar", stacked(s[25], "PlayerCastingBarFrame"))
	check("utility cooldowns on essential", stacked(s[26], "EssentialCooldownViewer"))
	check("buff icons on utility", stacked(s[27], "UtilityCooldownViewer"))
	check("buff bars on buff icons", stacked(s[28], "BuffIconCooldownViewer"))
end

do
	local state = layoutState()
	local env = boot(state)
	check("frames stay at 100% on a screen shorter than the reference",
		(function() state.button.buttonClick(); return state.saved.layouts[4].systems[1].settings[1].value == 0 end)())
	state.reloaded = false
	state.settings.frameXPct:SetValue(10)
	state.settings.frameYPct:SetValue(30)
	check("sliders do not reload by themselves", not state.reloaded)
	state.button.buttonClick()
	local player = state.saved.layouts[4].systems[1]
	check("slider values used", player.anchorInfo.offsetX == -200 and player.anchorInfo.offsetY == 300)
	check("chat follows the frame height", state.saved.layouts[4].systems[24].anchorInfo.offsetY == 300)
	check("button reloads", state.reloaded)
	check("env kept", env ~= nil)
end

do
	local mine = { layoutName = "Mine", layoutType = 1, systems = systems(9) }
	local ksui = { layoutName = "KSUI", layoutType = 1, systems = systems(5) }
	local alt = { layoutName = "Alt", layoutType = 2, systems = systems(6) }
	local state = layoutState({ layouts = { mine, ksui, alt }, active = 5 })
	runLayout(state)
	local saved = state.saved.layouts
	check("rerun does not duplicate", #saved == 6)
	check("kept before character layouts", saved[5].layoutName == "KSUI" and saved[6].layoutName == "Alt" and state.activated == 5)
	check("user layout kept", saved[4].layoutName == "Mine" and saved[4].systems[1].anchorInfo.offsetX == 9)
end

do
	local state = layoutState({ layouts = { { layoutName = "KSUI", layoutType = 2, systems = systems(4) } } })
	runLayout(state)
	local saved = state.saved.layouts
	check("character layout with the same name survives", #saved == 5 and saved[4].layoutType == 1
		and saved[5].layoutType == 2 and saved[5].systems[1].anchorInfo.offsetX == 4)
end

do
	local state = layoutState()
	state.presets[2].systems[1].anchorInfo2 = { point = "TOP" }
	runLayout(state)
	check("second anchor cleared", state.saved.layouts[4].systems[1].anchorInfo2 == nil)
end

do
	local state = layoutState({ combat = true })
	runLayout(state)
	check("combat blocks save", state.saved == nil and not state.reloaded and state.printed ~= nil)
end

do
	local state = layoutState({ layouts = {
		{ layoutName = "A", layoutType = 1, systems = systems(1) },
		{ layoutName = "B", layoutType = 1, systems = systems(1) },
	} })
	runLayout(state)
	check("full account slots block save", state.saved == nil and not state.reloaded)
end

do
	local state = layoutState({ active = 4, layouts = {
		{ layoutName = "KSUI", layoutType = 1, systems = systems(5) },
		{ layoutName = "B", layoutType = 1, systems = systems(1) },
	} })
	runLayout(state)
	check("replacing own layout at the limit works", state.saved ~= nil and #state.saved.layouts == 5)
end

-- First install, and settings changed in the panel: saved while the UI loads or unloads, with no command or reload.
do
	local state = layoutState({ active = 2 })
	local env = boot(state)
	fire(env, "EDIT_MODE_LAYOUTS_UPDATED")
	for _, timer in ipairs(state.timers) do timer() end
	check("a first install lays out at load without a command or reload", state.saved ~= nil and not state.reloaded
		and #state.popups == 0)

	state = layoutState({ active = 4, layouts = { { layoutName = "KSUI", layoutType = 1, systems = systems(5) } } })
	state.savedDB.layoutVersion = "0.11.0"
	env = boot(state)
	state.settings.frameYPct:SetValue(25)
	state.settings.frameYPct:SetValue(26)
	env.SettingsPanel.hooks.OnHide()
	check("changing settings saves nothing yet", state.saved == nil and state.printed:find("다음 접속", 1, true) ~= nil)
	fire(env, "PLAYER_LOGOUT")
	check("logging out or reloading saves it", state.saved ~= nil and not state.reloaded and env.KSUIDB.layoutPending == true)

	-- The next load saves again in case the logout save didn't go through, then forgets it.
	local saved = env.KSUIDB
	state = layoutState({ active = 4, layouts = { { layoutName = "KSUI", layoutType = 1, systems = systems(5) } },
		savedDB = saved })
	env = boot(state)
	fire(env, "EDIT_MODE_LAYOUTS_UPDATED")
	for _, timer in ipairs(state.timers) do timer() end
	check("the next load saves it again and forgets it", state.saved ~= nil and env.KSUIDB.layoutPending == nil)
	state.saved = nil
	fire(env, "PLAYER_LOGOUT")
	check("nothing pending, nothing saved at logout", state.saved == nil)

	-- Loading into combat: saved when the UI unloads instead.
	do
		local cstate = layoutState({ active = 2 })
		local cenv = boot(cstate)
		cstate.combat = true
		fire(cenv, "EDIT_MODE_LAYOUTS_UPDATED")
		for _, timer in ipairs(cstate.timers) do timer() end
		check("a layout due while loading into combat waits", cstate.saved == nil and cenv.KSUIDB.layoutPending == true)
		cstate.combat = false
		fire(cenv, "PLAYER_LOGOUT")
		check("and is saved when the UI unloads", cstate.saved ~= nil)
	end
	state.settings.fadeAlpha:SetValue(0.5)
	fire(env, "PLAYER_LOGOUT")
	check("other settings don't touch the layout", state.saved == nil)
	env.SlashCmdList.KSUI("layout")
	check("the command still saves and reloads at once", state.saved ~= nil and state.reloaded)
end

-- Blizzard's raid-style party frames instead: they have you in them, so no room is left for KSUI's row.
do
	local state = layoutState()
	state.savedDB.raidStyleParty = true
	runLayout(state)
	local party = state.saved.layouts[4].systems[5]
	local values = {}
	for _, info in ipairs(party.settings) do values[info.setting] = info.value end
	check("raid-style when chosen, without the row's room", values[4] == 1 and near(party.anchorInfo.offsetY, -20))
end

-- Auto apply after an update
do
	local layouts = { { layoutName = "KSUI", layoutType = 1, systems = systems(5) } }
	local state = layoutState({ active = 4, layouts = layouts })
	state.savedDB.layoutVersion = "0.10.0"
	local env = boot(state)
	check("nothing before Edit Mode has the layouts", not state.reloaded)
	fire(env, "EDIT_MODE_LAYOUTS_UPDATED")
	for _, timer in ipairs(state.timers) do timer() end
	check("update re-applies the active KSUI layout", not state.reloaded and state.saved ~= nil
		and state.saved.layouts[4].layoutName == "KSUI" and state.savedDB.layoutVersion == "0.11.0")

	state = layoutState({ active = 4, layouts = layouts })
	state.savedDB.layoutVersion = "0.11.0"
	fire(boot(state), "EDIT_MODE_LAYOUTS_UPDATED")
	for _, timer in ipairs(state.timers) do timer() end
	check("same version leaves it alone", not state.reloaded and state.saved == nil)

	state = layoutState({ active = 4, layouts = { { layoutName = "Mine", layoutType = 1, systems = systems(5) } } })
	state.savedDB.layoutVersion = "0.10.0"
	fire(boot(state), "EDIT_MODE_LAYOUTS_UPDATED")
	for _, timer in ipairs(state.timers) do timer() end
	check("another active layout is left alone", not state.reloaded and state.saved == nil)
	check("a manual apply records the version", (function()
		runLayout(state)
		return state.savedDB.layoutVersion == "0.11.0"
	end)())
end

-- Range color
do
	local state = { units = { player = mage } }
	local env = boot(state)
	local button = env.ActionButton1
	local icon = button.icon
	env.ActionButton_UpdateRangeIndicator(button, true, false)
	check("out of range turns red", near(icon.color[1], 0.85) and near(icon.color[2], 0.15))
	button:UpdateUsable()
	check("red survives Blizzard usable update", near(icon.color[1], 0.85))
	env.ActionButton_UpdateRangeIndicator(button, true, true)
	check("back in range restores usable color", icon.color[1] == 1 and icon.color[3] == 1)
	state.usable[button.action] = "mana"
	env.ActionButton_UpdateRangeIndicator(button, true, false)
	env.ActionButton_UpdateRangeIndicator(button, false, false)
	check("no range check restores mana color", icon.color[1] == 0.5 and icon.color[3] == 1)
	env.ActionButton_UpdateRangeIndicator(button, true, false)
	state.settings.rangeColor:SetValue(false)
	check("toggle off clears red", icon.color[1] == 0.5)
	button:UpdateUsable()
	check("toggle off leaves Blizzard color", icon.color[1] == 0.5)
	state.settings.rangeColor:SetValue(true)
	check("toggle on brings red back", near(icon.color[1], 0.85))
	local pet = { icon = texture() }
	env.ActionButton_UpdateRangeIndicator(pet, true, false)
	check("pet buttons ignored", pet.icon.color == nil)
end

-- Bar fade
do
	local state = { units = { player = mage } }
	local env = boot(state)
	check("bars faded out of combat", near(env.MainActionBar.alpha, 0.4) and near(env.MultiBarLeft.alpha, 0.4))
	check("extra bars fade too", near(env.MultiBar7.alpha, 0.4))
	state.combat = true
	fire(env, "PLAYER_REGEN_DISABLED")
	check("bars full in combat", env.MainActionBar.alpha == 1 and env.MultiBarBottomRight.alpha == 1)
	state.combat = false
	fire(env, "PLAYER_REGEN_ENABLED")
	check("bars fade after combat", near(env.MainActionBar.alpha, 0.4))
	state.units.target = { player = false }
	fire(env, "PLAYER_TARGET_CHANGED")
	check("bars full with a target", env.MainActionBar.alpha == 1)
	state.units.target = nil
	fire(env, "PLAYER_TARGET_CHANGED")
	state.settings.fadeAlpha:SetValue(0.7)
	check("fade amount live", near(env.MultiBarRight.alpha, 0.7))
	state.settings.fadeBars:SetValue(false)
	check("fade off keeps bars full", env.MainActionBar.alpha == 1)
end

do
	local state = { units = { player = mage }, combat = true }
	local env = boot(state)
	check("login in combat keeps bars full", env.MainActionBar.alpha == 1)
end

-- CVars
do
	local state = { units = { player = mage } }
	boot(state)
	check("all debuffs shown by default", state.cvars.raidFramesDisplayOnlyDispellableDebuffs == "0")
	check("threat numbers on", state.cvars.threatShowNumeric == "1")
	state.settings.dispellableOnly:SetValue(true)
	check("dispellable only when chosen", state.cvars.raidFramesDisplayOnlyDispellableDebuffs == "1")
	check("prerequisite switches on", state.cvars.threatWarning == "3" and state.cvars.raidFramesDisplayDebuffs == "1")
	check("health percent on", state.cvars.statusTextDisplay == "BOTH" and state.cvars.statusText == "1")
	check("cooldown manager on", state.cvars.cooldownViewerEnabled == "1")
	state.settings.cooldownManager:SetValue(false)
	check("cooldown manager off", state.cvars.cooldownViewerEnabled == "0")
	state.settings.healthPercent:SetValue(false)
	check("health percent off keeps numbers", state.cvars.statusTextDisplay == "NUMERIC")
	state.settings.threatNumbers:SetValue(false)
	state.settings.dispellableOnly:SetValue(false)
	check("CVar toggles off", state.cvars.threatShowNumeric == "0" and state.cvars.raidFramesDisplayOnlyDispellableDebuffs == "0")
	state.cvars.threatWarning, state.cvars.raidFramesDisplayDebuffs = "0", "0"
	state.settings.threatNumbers:SetValue(false)
	check("toggling off leaves Blizzard switches alone", state.cvars.threatWarning == "0" and state.cvars.raidFramesDisplayDebuffs == "0")
end

-- Merchant
do
	local state = { units = { player = mage }, junk = 3, canRepair = true, repairCost = 500, money = 1000 }
	local env = boot(state)
	fire(env, "MERCHANT_SHOW")
	check("junk sold", state.sold == 1)
	check("repaired with own gold", state.repaired == 1 and state.printed:find("500c", 1, true) ~= nil)
	state.junk, state.repairCost = 0, 0
	fire(env, "MERCHANT_SHOW")
	check("nothing to do does nothing", state.sold == 1 and state.repaired == 1)
	state.repairCost, state.money = 2000, 100
	fire(env, "MERCHANT_SHOW")
	check("not enough gold skips repair", state.repaired == 1 and state.printed:find("모자", 1, true) ~= nil)
	state.canRepair, state.money, state.junk = false, 5000, 2
	fire(env, "MERCHANT_SHOW")
	check("vendor without repair only sells", state.repaired == 1 and state.sold == 2)
	state.canRepair, state.repairRefused, state.repairCost, state.junk = true, true, 300, 0
	fire(env, "MERCHANT_SHOW")
	check("gear this vendor won't repair is left alone", state.repaired == 1)
	state.repairRefused = nil
	state.settings.sellJunk:SetValue(false)
	state.settings.autoRepair:SetValue(false)
	state.canRepair = true
	fire(env, "MERCHANT_SHOW")
	check("toggles off", state.sold == 2 and state.repaired == 1)
end

-- Ready check: everyone's buffs, named by who is missing what.
do
	local units = {
		player = { player = true, class = "PALADIN", name = "Me" },
		raid2 = { player = true, class = "MAGE", name = "Mage" },
		raid3 = { player = true, class = "PRIEST", name = "Priest", powerType = 0 },
		raid4 = { player = true, class = "WARRIOR", name = "Warrior", powerType = 1 },
		raid5 = { player = true, class = SECRET, name = "Hidden" },
		raid6 = { player = true, class = "ROGUE", name = "Gone", offline = true },
	}
	units.raid1 = units.player
	local state = { units = units, raid = true, groupSize = 6, unitAuras = {
		raid1 = { "인내의 기원", "신비한 지능" },
		raid2 = { "인내의 기원" },
		raid3 = { "신의 권능: 인내", "신비한 총명함" },
		raid4 = {},
		raid5 = { SECRET },
	} }
	local env = boot(state)
	local printed = {}
	env.print = function(text) printed[#printed + 1] = text end
	fire(env, "READY_CHECK")
	local report = table.concat(printed, "\n")
	check("missing buffs named per member", report:find("인내: Warrior", 1, true) ~= nil
		and report:find("신비한 지능: Mage", 1, true) ~= nil)
	check("group versions count, and intellect isn't asked of a warrior", not report:find("Priest", 1, true)
		and not report:find("지능: Mage, Warrior", 1, true) and not report:find("Me", 1, true))
	check("class not in the group not asked for", not report:find("야생", 1, true))
	check("offline members skipped", not report:find("Gone", 1, true))
	check("unreadable members counted, not guessed", report:find("1명은 지금 버프를 확인할 수 없습니다", 1, true) ~= nil
		and not report:find("Hidden", 1, true))

	state.unitAuras.raid5 = { "SECRET_RESULT" }
	printed = {}
	fire(env, "READY_CHECK")
	check("secret aura result not tested", table.concat(printed):find("1명은", 1, true) ~= nil)
	state.unitAuras.raid5 = { "LOCKED" }
	printed = {}
	fire(env, "READY_CHECK")
	check("locked aura table not indexed", table.concat(printed):find("1명은", 1, true) ~= nil)
	state.unitAuras.raid5 = { "인내의 기원" }
	state.auraBlocked = { raid5 = true }
	printed = {}
	fire(env, "READY_CHECK")
	check("restricted unit counted as unreadable", table.concat(printed):find("1명은", 1, true) ~= nil)
	state.auraBlocked = nil
	state.secretAuras = true
	printed = {}
	fire(env, "READY_CHECK")
	check("no aura asked for while auras are secret", table.concat(printed):find("명은", 1, true) ~= nil)
	state.secretAuras = nil

	state.unitAuras = { raid1 = { "인내의 기원", "신비한 지능" }, raid2 = { "인내의 기원" },
		raid3 = { "인내의 기원", "신비한 지능" }, raid4 = { "인내의 기원" }, raid5 = { "인내의 기원" } }
	units.raid5.class = "PRIEST"
	printed = {}
	fire(env, "READY_CHECK")
	check("everyone buffed stays quiet", #printed == 1 and printed[1]:find("신비한 지능: Mage", 1, true) ~= nil)
	state.settings.buffCheck:SetValue(false)
	printed = {}
	fire(env, "READY_CHECK")
	check("buff check toggle off", #printed == 0)
end

do
	local state = { units = { player = { player = true, class = "DRUID", name = "Me" } }, groupSize = 0, auras = {} }
	local env = boot(state)
	fire(env, "READY_CHECK")
	check("solo checks own class buff", state.printed ~= nil and state.printed:find("야생의 징표: Me", 1, true) ~= nil)
end

-- Gear suggestions
local function gearState(extra)
	local S, I = "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_INTELLECT_SHORT"
	local state = {
		units = { player = { player = true, class = "PALADIN" } },
		spec = { role = "TANK", primary = 1 },
		items = {
			["[worn helm]"] = { id = 1, loc = "INVTYPE_HEAD", stats = { [S] = 10 } },
			["[stamina helm]"] = { id = 2, loc = "INVTYPE_HEAD", stats = { [S] = 20 } },
			["[cloth helm]"] = { id = 3, loc = "INVTYPE_HEAD", stats = { [I] = 50 } },
			["[worn ring]"] = { id = 4, loc = "INVTYPE_FINGER", stats = { [S] = 10 } },
			["[big ring]"] = { id = 5, loc = "INVTYPE_FINGER", stats = { [S] = 15 } },
			["[small ring]"] = { id = 6, loc = "INVTYPE_FINGER", stats = { [S] = 5 } },
			["[unusable chest]"] = { id = 7, loc = "INVTYPE_CHEST", stats = { [S] = 100 }, usable = false },
			["[uncached legs]"] = { id = 8, loc = "INVTYPE_LEGS" },
			["[trinket]"] = { id = 9, loc = "INVTYPE_TRINKET", stats = { [S] = 100 } },
			["[boe boots]"] = { id = 10, loc = "INVTYPE_FEET", stats = { [S] = 100 }, unbound = true },
			["[worn ring copy]"] = { id = 4, loc = "INVTYPE_FINGER", stats = { [S] = 10 } },
		},
		bags = { [0] = { "[stamina helm]", "[cloth helm]", "[big ring]" }, [1] = { "[small ring]", "[unusable chest]", "[uncached legs]", "[trinket]", "[boe boots]" } },
		worn = { [1] = "[worn helm]", [11] = "[worn ring]" },
	}
	for k, v in pairs(extra or {}) do state[k] = v end
	return state
end

local function suggested(list)
	local bySlot = {}
	for _, item in ipairs(list) do bySlot[item.slot] = item.link end
	return bySlot, #list
end

do
	local state = gearState()
	local env, ns = boot(state)
	local bySlot, n = suggested(ns.GearSuggestions())
	check("tank picks the stamina helm", bySlot[1] == "[stamina helm]")
	check("better ring fills the empty ring slot", bySlot[12] == "[big ring]" and bySlot[11] == nil)
	check("unusable, uncached, unbound and trinket items skipped", n == 2)
	fire(env, "BAG_UPDATE_DELAYED")
	check("new upgrades announced", state.printed ~= nil and state.printed:find("[stamina helm]", 1, true) ~= nil
		and state.printed:find("[big ring]", 1, true) ~= nil)
	state.printed = nil
	fire(env, "BAG_UPDATE_DELAYED")
	check("same upgrade announced once", state.printed == nil)
	local button = ns.gearButton
	check("button on the character tab", button.parent == env.PaperDollFrame and button.template == "UIPanelButtonTemplate"
		and button.point[2] == env.CharacterFrame and button.text ~= nil)
	state.combat = true
	button.scripts.OnClick(button, "LeftButton")
	check("no equipping in combat", #state.equipped == 0 and state.printed:find("전투", 1, true) ~= nil)
	state.combat = false
	button.scripts.OnClick(button, "LeftButton")
	check("button equips each upgrade into its slot", #state.equipped == 2 and state.equipped[1].link == "[stamina helm]"
		and state.equipped[1].slot == 1 and state.equipped[2].slot == 12)
end

do
	local state = gearState({ spec = { role = "DAMAGER", primary = 4 }, units = { player = { player = true, class = "MAGE" } } })
	local _, ns = boot(state)
	local bySlot = suggested(ns.GearSuggestions())
	check("caster picks the intellect helm", bySlot[1] == "[cloth helm]")
end

-- Measured in game: a protection paladin wore the stamina cloak over the strength one with health regeneration.
do
	local state = gearState({ spec = { role = "TANK", primary = 1 } })
	state.items["[long cloak]"] = { id = 20, loc = "INVTYPE_CLOAK", stats = { RESISTANCE0_NAME = 14, ITEM_MOD_STAMINA_SHORT = 2 } }
	state.items["[cave cloak]"] = { id = 21, loc = "INVTYPE_CLOAK",
		stats = { RESISTANCE0_NAME = 17, ITEM_MOD_STRENGTH_SHORT = 3, ITEM_MOD_HEALTH_REGEN_SHORT = 5 } }
	state.worn = { [15] = "[cave cloak]" }
	state.bags = { [0] = { "[long cloak]" } }
	local _, ns = boot(state)
	check("the strength cloak with regeneration stays on", suggested(ns.GearSuggestions())[15] == nil)
	state.worn, state.bags = { [15] = "[long cloak]" }, { [0] = { "[cave cloak]" } }
	check("and is suggested over the stamina one", suggested(ns.GearSuggestions())[15] == "[cave cloak]")
end

-- Forever reports a retribution or protection paladin with intellect as the main stat and may call it a damage
-- dealer; strength still counts, and the role can be set by hand.
do
	local state = gearState({ spec = { role = "DAMAGER", primary = 4 } })
	state.items["[long cloak]"] = { id = 20, loc = "INVTYPE_CLOAK", stats = { RESISTANCE0_NAME = 14, ITEM_MOD_STAMINA_SHORT = 2 } }
	state.items["[cave cloak]"] = { id = 21, loc = "INVTYPE_CLOAK",
		stats = { RESISTANCE0_NAME = 17, ITEM_MOD_STRENGTH_SHORT = 3, ITEM_MOD_HEALTH_REGEN_SHORT = 5 } }
	state.worn, state.bags = { [15] = "[long cloak]" }, { [0] = { "[cave cloak]" } }
	local _, ns = boot(state)
	check("a paladin's strength counts whatever the spec says", suggested(ns.GearSuggestions())[15] == "[cave cloak]")
	local control = state.controls.KSUI_gearRole
	check("role picked in a dropdown", control.kind == "dropdown" and ns.db.gearRole == "AUTO")
	state.settings.gearRole:SetValue("HEALER")
	check("picking healer scores for a healer", suggested(ns.GearSuggestions())[15] == nil)
	state.settings.gearRole:SetValue("TANK")
	check("picking tank scores for a tank", suggested(ns.GearSuggestions())[15] == "[cave cloak]")
end

-- Forever reports every spec as a damage dealer with intellect; the talent tree with the most points decides.
do
	local function header(state)
		local env, ns = boot(state)
		local printed = {}
		env.print = function(text) printed[#printed + 1] = text end
		ns.PrintGearStats()
		return printed[1]
	end
	check("most points in protection: a strength tank", header(gearState({ spec = { role = "DAMAGER", primary = 4 },
		talents = { 0, 14, 5 } })):find("TANK, 주 능력치 ITEM_MOD_STRENGTH_SHORT", 1, true) ~= nil)
	check("most points in holy: a healer", header(gearState({ spec = { role = "DAMAGER", primary = 4 },
		talents = { 9, 2, 0 } })):find("HEALER", 1, true) ~= nil)
	check("no points yet: the class default", header(gearState({ spec = { role = "DAMAGER", primary = 4 },
		talents = { 0, 0, 0 } })):find("DAMAGER, 주 능력치 ITEM_MOD_STRENGTH_SHORT", 1, true) ~= nil)
	local mage = gearState({ spec = { role = "DAMAGER", primary = 4 }, talents = { 5, 0, 0 } })
	mage.units.player.class = "MAGE"
	check("a class with one role keeps it", header(mage):find("DAMAGER, 주 능력치 ITEM_MOD_INTELLECT_SHORT", 1, true) ~= nil)
	local feral = gearState({ spec = { role = "DAMAGER", primary = 4 }, talents = { 0, 20, 0 } })
	feral.units.player.class = "DRUID"
	check("a feral druid out of bear form is an agility melee", header(feral):find("DAMAGER, 주 능력치 ITEM_MOD_AGILITY_SHORT", 1, true) ~= nil)
	feral.form = 5
	check("and a tank in bear form", header(feral):find("TANK, 주 능력치 ITEM_MOD_AGILITY_SHORT", 1, true) ~= nil)
	local chosen = gearState({ spec = { role = "DAMAGER", primary = 4 }, talents = { 0, 14, 5 } })
	chosen.savedDB = { gearRole = "MELEE" }
	check("a role picked in the settings wins", header(chosen):find("DAMAGER", 1, true) ~= nil)
end

-- A swap less than 10% better is not suggested.
do
	local state = gearState({ spec = { role = "TANK", primary = 1 } })
	local T = "ITEM_MOD_STAMINA_SHORT"
	state.items["[helm 10]"] = { id = 30, loc = "INVTYPE_HEAD", stats = { [T] = 10 } }
	state.items["[helm 105]"] = { id = 31, loc = "INVTYPE_HEAD", stats = { [T] = 10.5 } }
	state.worn, state.bags = { [1] = "[helm 10]" }, { [0] = { "[helm 105]" } }
	local _, ns = boot(state)
	check("near-tie left alone", suggested(ns.GearSuggestions())[1] == nil)
end

-- Heavier armor wins a tie for every role, not only tanks.
do
	local state = gearState({ spec = { role = "DAMAGER", primary = 1 } })
	local A, S = "RESISTANCE0_NAME", "ITEM_MOD_STRENGTH_SHORT"
	state.items["[leather helm]"] = { id = 12, loc = "INVTYPE_HEAD", stats = { [S] = 5, [A] = 100 } }
	state.items["[plate helm]"] = { id = 13, loc = "INVTYPE_HEAD", stats = { [S] = 5, [A] = 300 } }
	state.worn = { [1] = "[leather helm]" }
	state.bags = { [0] = { "[plate helm]" } }
	local _, ns = boot(state)
	check("melee counts armor", suggested(ns.GearSuggestions())[1] == "[plate helm]")
end

do
	local state = gearState({ worn = { [11] = "[worn ring]" } })
	state.bags = { [0] = { "[worn ring copy]", "[small ring]" } }
	local _, ns = boot(state)
	local bySlot = suggested(ns.GearSuggestions())
	check("same ring not suggested twice", bySlot[12] == "[small ring]")
end

do
	local state = gearState({ spec = false, units = { player = mage } })
	local _, ns = boot(state)
	check("class decides before a spec is chosen", suggested(ns.GearSuggestions())[1] == "[cloth helm]")
end

do
	local state = gearState({ worn = { [1] = "[stamina helm]", [11] = "[big ring]", [12] = "[worn ring]" } })
	state.bags = { [0] = { "[worn helm]", "[small ring]" } }
	local env, ns = boot(state)
	local _, n = suggested(ns.GearSuggestions())
	check("nothing worse is suggested", n == 0)
	ns.EquipBest()
	check("says when nothing is better", #state.equipped == 0 and state.printed:find("가장 좋습니다", 1, true) ~= nil)
	state.bags = { [0] = { "[stamina helm]", "[big ring]" } }
	state.worn = { [1] = "[uncached legs]" }
	check("uncached worn item is kept", suggested(ns.GearSuggestions())[1] == nil)
	state.settings.gearSuggest:SetValue(false)
	state.printed = nil
	fire(env, "BAG_UPDATE_DELAYED")
	check("announcements off", state.printed == nil)
end

do
	local state = gearState()
	state.items["[odd ring]"] = { id = 11, loc = "INVTYPE_FINGER", stats = { ITEM_MOD_STAMINA_SHORT = 4, ITEM_MOD_MADE_UP_SHORT = 3 } }
	state.worn = { [1] = "[worn helm]", [11] = "[odd ring]", [12] = "[uncached legs]" }
	local env, ns = boot(state)
	env.SlashCmdList.KSUI("stats")
	local text = table.concat(state.log, "\n")
	check("stats shows the role", text:find("TANK", 1, true) ~= nil)
	check("stats scores each worn item", text:find("[worn helm] 10.0", 1, true) ~= nil
		and text:find("[odd ring] 4.0", 1, true) ~= nil and text:find("[uncached legs] 정보 없음", 1, true) ~= nil)
	check("stats lists keys with no weight", state.printed:find("ITEM_MOD_MADE_UP_SHORT", 1, true) ~= nil
		and not state.printed:find("STAMINA", 1, true))
end

-- Interrupt and target cast bar
local function interruptParts(state, env)
	local icon, castBar
	for _, f in ipairs(state.frames) do
		if f.parent == env.TargetFrame and f.kind == "Frame" then icon = f end
		if f.parent == env.TargetFrame and f.kind == "StatusBar" then castBar = f end
	end
	return icon, castBar
end

do
	local state = { units = { player = mage }, interruptSlot = 1205 }
	local env = boot(state)
	local icon, castBar = interruptParts(state, env)
	local blizzard = env.TargetFrame.spellbar
	check("interrupt next to the target frame", icon.point[2] == env.TargetFrame and icon.point[3] == "RIGHT")
	check("cast bar after the interrupt", castBar.point[1] == "LEFT" and castBar.point[2] == icon)
	check("interrupt found on the bars", icon.shown == true and icon.icon.file == "icon1205")
	check("interrupt cooldown ignores the global cooldown", icon.cooldown.duration.slot == 1205 and icon.cooldown.duration.ignoreGCD == true)
	check("no glow or bar without a cast", icon.glow.alpha == 0 and castBar.shown == false)
	check("Blizzard target cast bar kept invisible", blizzard.alpha == 0)
	state.cast = { notInterruptible = false }
	fire(env, "UNIT_SPELLCAST_START")
	blizzard:ApplyAlpha(1)
	check("Blizzard bar stays invisible after a cast start", blizzard.alpha == 0)
	blizzard:PlayInterruptAnims()
	check("Blizzard interrupt hold stopped", blizzard.alpha == 0 and blizzard.HoldFadeOutAnim.stopped)
	state.cast = { notInterruptible = false }
	fire(env, "UNIT_SPELLCAST_DELAYED")
	check("pushback refreshes the bar", castBar.shown == true)
	check("glow on an interruptible cast", icon.glow.alpha == 1)
	check("cast bar shows the cast", castBar.shown == true and castBar.text.text == "Fireball" and castBar.icon.file == 1
		and castBar.range[1] == 99000 and castBar.range[2] == 102000 and castBar.barValue == 100000)
	check("interruptible cast colored", castBar.fill.color[1] == 1 and castBar.fill.color[2] == 0.7)
	castBar.barValue = nil
	castBar.scripts.OnUpdate(castBar)
	check("bar follows the clock", castBar.barValue == 100000)
	state.cast = { channel = true, notInterruptible = true }
	fire(env, "UNIT_SPELLCAST_CHANNEL_START")
	check("no glow on a shielded channel", icon.glow.alpha == 0 and castBar.text.text == "Drain" and castBar.fill.color[1] == 0.6)
	state.cast = { secret = true, notInterruptible = SECRET }
	fire(env, "UNIT_SPELLCAST_START")
	check("secret interrupt flag passed through untested", icon.glow.alphaFrom ~= nil and icon.glow.alphaFrom[1] == SECRET
		and icon.glow.alphaFrom[2] == 0 and icon.glow.alphaFrom[3] == 1 and castBar.fill.colorFrom[1] == SECRET
		and castBar.fill.colorFrom[2].r == 0.6 and castBar.shown == true)
	state.cast = nil
	fire(env, "UNIT_SPELLCAST_STOP")
	check("glow and bar off when the cast ends", icon.glow.alpha == 0 and castBar.shown == false)
	state.cast = { channel = true, notInterruptible = false }
	fire(env, "UNIT_SPELLCAST_EMPOWER_START")
	check("empowered cast lights the glow", icon.glow.alpha == 1)
	state.interruptSlot = nil
	fire(env, "ACTIONBAR_SLOT_CHANGED")
	check("no interrupt on the bars hides the icon", icon.shown == false)
	state.interruptSlot = 1205
	fire(env, "ACTIONBAR_PAGE_CHANGED")
	check("page change finds the interrupt again", icon.shown == true)
	state.settings.interruptHelper:SetValue(false)
	check("turned off gives Blizzard its bar back", blizzard.alpha == 1 and icon.shown == false and castBar.shown == false)
	blizzard:ApplyAlpha(1)
	check("Blizzard bar left alone when off", blizzard.alpha == 1)
end

do
	local paladin = { player = true, class = "PALADIN" }
	local state = { units = { player = paladin }, actions = { [1202] = 20271, [1207] = 5588 } }
	local env = boot(state)
	local icon = interruptParts(state, env)
	check("paladin without an interrupt shows the stun, any rank", icon.shown == true and icon.icon.file == "icon1207")
	state.interruptSlot = 2403
	fire(env, "ACTIONBAR_SLOT_CHANGED")
	check("a real interrupt takes over from the stun", icon.icon.file == "icon2403")
	state.interruptSlot, state.units.player = nil, mage
	state.actions = { [1207] = 5588 }
	fire(env, "ACTIONBAR_SLOT_CHANGED")
	check("other classes get no stand-in", icon.shown == false)
end

-- Gathering tracking
do
	local tracking = {
		{ spellID = 2383, active = false }, { spellID = 2580, active = true },
		{ active = false }, { spellID = 1494, active = false }, { spellID = 8388, active = false },
	}
	local state = { units = { player = mage }, tracking = tracking }
	local env = boot(state)
	check("herb tracking turned on", tracking[1].active == true and tracking[2].active == true)
	check("other tracking untouched", tracking[3].active == false and tracking[4].active == false)
	check("second rank of find minerals tracked", tracking[5].active == true)
	tracking[1].active = false
	state.settings.gatherTracking:SetValue(false)
	fire(env, "LEARNED_SPELL_IN_SKILL_LINE")
	check("tracking left alone when off", tracking[1].active == false)
	state.settings.gatherTracking:SetValue(true)
	check("turning the option on tracks again", tracking[1].active == true)
	tracking[#tracking + 1] = { spellID = 43308, active = false }
	fire(env, "LEARNED_SPELL_IN_SKILL_LINE")
	check("newly learned fishing tracked", tracking[6].active == true)
end

-- Quest guide
do
	local state = { units = { player = mage } }
	local env = boot(state)
	local guide
	for _, f in ipairs(state.frames) do
		if f.parent == env.Minimap and f.scripts.OnUpdate then guide = f end
	end
	guide.scripts.OnUpdate(guide, 1)
	check("arrow points up at a quest due north", near(guide.arrow.rotation, 0) and guide.arrow.shown ~= false
		and guide.distance.format[2] == 2066.87)
	state.quest.facing = math.pi
	guide.scripts.OnUpdate(guide, 1)
	check("on a north-up minimap your facing doesn't turn it", near(guide.arrow.rotation, 0))
	state.rotate = true
	state.quest.facing = math.pi / 2
	guide.scripts.OnUpdate(guide, 1)
	check("on a rotating minimap facing west turns it right", near(guide.arrow.rotation, -math.pi / 2))
	state.rotate = false
	state.quest.facing = 0
	state.quest.waypoint = { 0.4, 0.5 }
	guide.scripts.OnUpdate(guide, 1)
	check("a waypoint to the west is to the left", near(guide.arrow.rotation, math.pi / 2))
	state.quest.player = nil
	guide.scripts.OnUpdate(guide, 1)
	-- Measured in game: quest 451 south-southwest of you; on the north-up minimap the arrow points that way.
	state.quest.waypoint = nil
	state.quest.player = { 0.50326311588287, 0.71181857585907 }
	state.quest.onMap = { { questID = 516, x = 0.46502554416656, y = 0.86224073171616 } }
	state.quest.facing = 3.457793712616
	guide.scripts.OnUpdate(guide, 1)
	check("measured case points south-southwest", math.abs(math.deg(guide.arrow.rotation) - 165.7) < 0.5)
	state.quest.player = nil
	guide.scripts.OnUpdate(guide, 1)
	check("arrow hides without a player position", guide.arrow.shown == false and guide.distance.shown == false)
	state.settings.questArrow:SetValue(false)
	check("arrow off", guide.shown == false)

	state.quest.log = { { isHeader = true }, { questID = 1, distanceSq = 900 , onContinent = true },
		{ questID = 2, distanceSq = 100, onContinent = true }, { questID = 3, distanceSq = 1, onContinent = false } }
	fire(env, "QUEST_LOG_UPDATE")
	fire(env, "QUEST_ACCEPTED")
	check("quest events wait for one settled check", #state.timers == 1)
	state.timers[1]()
	check("nearest quest on this continent guided", state.quest.supertracked == 2)
	state.settings.questNearest:SetValue(false)
	state.quest.supertracked = 516
	fire(env, "QUEST_LOG_UPDATE")
	state.timers[2]()
	check("nearest guiding off leaves the choice alone", state.quest.supertracked == 516)
end

-- Target auras
do
	local state = { units = { player = mage } }
	local env = boot(state)
	local overlay
	for _, f in ipairs(state.frames) do
		if f.parent == env.TargetFrame and f.template == "BackdropTemplate" then overlay = f end
	end
	local p = env.TargetFrame.auras.points
	check("target auras start under our frame", #p == 1 and p[1][1] == "TOPLEFT" and p[1][2] == overlay
		and p[1][3] == "BOTTOMLEFT" and p[1][4] == 0 and p[1][5] == -3)
	env.TargetFrame.auras.mirrored = true
	env.TargetFrame:AnchorAuraContainer()
	p = env.TargetFrame.auras.points
	check("buffs on top go above it", #p == 1 and p[1][1] == "BOTTOMLEFT" and p[1][3] == "TOPLEFT" and p[1][5] == 3)
	state.settings.customUnitFrames:SetValue(false)
	check("option off gives Blizzard its spot back", env.TargetFrame.auras.points[1][2] == "blizzard art"
		and env.FocusFrame.auras.points[1][2] == "blizzard art")
end

-- Clickable cooldown manager
local function castButton(state, item)
	for _, f in ipairs(state.frames) do
		if f.parent == item and f.template == "SecureActionButtonTemplate" then return f end
	end
end

do
	local state = { units = { player = mage } }
	local env = boot(state)
	local judge = castButton(state, state.viewerItems.Essential1)
	check("a secure spell button on each icon", judge and judge.attributes.type == "spell" and judge.attributes.spell == 20271
		and castButton(state, state.viewerItems.Utility1).attributes.spell == 642 and judge.shown == true)
	check("casts on press or release, as the key-down option says", judge.clicks[1] == "AnyUp" and judge.clicks[2] == "AnyDown")

	state.viewerSpells.Essential = { 31884, 853 }
	state.combat = true
	env.EssentialCooldownViewer:RefreshLayout()
	check("left alone in combat", judge.attributes.spell == 20271)
	state.combat = false
	fire(env, "PLAYER_REGEN_ENABLED")
	check("caught up after combat, reusing the icon's button", judge.attributes.spell == 31884
		and castButton(state, state.viewerItems.Essential1) == judge)

	state.viewerSpells.Essential = { 20271, 853 }
	env.EssentialCooldownViewer:RefreshData()
	check("same icons with new cooldowns are caught up", judge.attributes.spell == 20271)
	env.EssentialCooldownViewer.visibleSetting = 1
	env.EssentialCooldownViewer:RefreshLayout()
	check("a row shown only in combat gets no buttons", judge.shown == false)
	env.EssentialCooldownViewer.visibleSetting = 0
	state.viewerSpells.Essential = { false, 853 }
	env.EssentialCooldownViewer:RefreshLayout()
	check("an icon without a spell gets no button", judge.shown == false)
	state.settings.cooldownCast:SetValue(false)
	check("option off hides the buttons", castButton(state, state.viewerItems.Essential2).shown == false)
end

-- Alerts
do
	local state = { units = { player = mage } }
	local env = boot(state)
	local p = env.AlertFrame.point
	check("alerts start above the cooldown manager, off the minimap", p[1] == "BOTTOM" and p[2] == env.BuffBarCooldownViewer
		and p[3] == "TOP" and p[5] == 10)
end

-- Swing timers: Blizzard's bars, switched on by their CVar and stacked on the cooldown manager by the layout.
-- The KSUI layout in use: no presets, one account layout named KSUI.
local function onKSUILayout(state)
	state.layouts, state.active = { { layoutName = "KSUI", layoutType = 1 } }, 1
	return state
end

do
	local state = onKSUILayout({ units = { player = mage } })
	local env = boot(state)
	check("swing timer starts from Blizzard's switch", env.KSUIDB.swingTimer == false)
	check("Blizzard's switch left alone at login", state.cvars.showSwingTimer == nil)
	check("swing timer border darkened", env.SwingTimerMainHandFrame:GetBorder().desaturated
		and near(env.SwingTimerRangedFrame:GetBorder().color[1], 0.278))
	state.settings.swingTimer:SetValue(true)
	check("swing timer on", state.cvars.showSwingTimer == "1")
	check("alerts start above the swing timers", env.AlertFrame.point[2] == env.SwingTimerRangedFrame)
	state.settings.swingTimer:SetValue(false)
	check("swing timer off again", state.cvars.showSwingTimer == "0" and env.AlertFrame.point[2] == env.BuffBarCooldownViewer)
	state.combat = true
	state.settings.swingTimer:SetValue(true)
	check("swing timer switch waits for combat to end", state.cvars.showSwingTimer == "0")
	state.combat = false
	fire(env, "PLAYER_REGEN_ENABLED")
	check("swing timer switched after combat", state.cvars.showSwingTimer == "1")
	-- Switched off in Blizzard's own settings: KSUI's option and the alerts follow.
	state.cvars.showSwingTimer = "0"
	state.blizzardSwingTimer = false
	fire(env, "CVAR_UPDATE", "showSwingTimer", "0")
	check("Blizzard's switch followed", env.KSUIDB.swingTimer == false and env.AlertFrame.point[2] == env.BuffBarCooldownViewer)
end

do
	-- Turned on in Blizzard's own settings before KSUI had the option: it stays on.
	local state = { units = { player = mage }, blizzardSwingTimer = true }
	local env = boot(state)
	check("Blizzard's swing timer kept on", env.KSUIDB.swingTimer == true and state.cvars.showSwingTimer == nil)
	check("alerts left above the cooldown manager under another layout", env.AlertFrame.point[2] == env.BuffBarCooldownViewer)
	-- Switching to the KSUI layout places them again.
	onKSUILayout(state)
	fire(env, "EDIT_MODE_LAYOUTS_UPDATED")
	-- The last timer queued places the alerts; the one before it is the load-time layout check.
	check("first update queues the layout check and the alerts", #state.timers == 2)
	state.timers[#state.timers]()
	fire(env, "EDIT_MODE_LAYOUTS_UPDATED")
	check("later updates only place the alerts", #state.timers == 3)
	check("alerts follow a switch to the KSUI layout", env.AlertFrame.point[2] == env.SwingTimerRangedFrame)
end

do
	local state = { units = { player = mage }, noSwingTimer = true, savedDB = { swingTimer = true } }
	local env = boot(state)
	check("alerts placed without Blizzard's swing timers", env.AlertFrame.point[2] == env.BuffBarCooldownViewer)
end

do
	local state = layoutState()
	runLayout(state)
	local systems = state.saved.layouts[4].systems
	local swing = {}
	for _, system in ipairs(systems) do if system.system == 29 then swing[system.systemIndex] = system end end
	local main, off, ranged = swing[1], swing[2], swing[3]
	local function visibility(system)
		for _, info in ipairs(system.settings) do if info.setting == 2 then return info.value end end
	end
	check("main hand timer on the cooldown manager", main.anchorInfo.point == "BOTTOM"
		and main.anchorInfo.relativeTo == "BuffBarCooldownViewer" and main.anchorInfo.relativePoint == "TOP"
		and main.anchorInfo.offsetY == 6 and not main.isInDefaultPosition)
	check("off hand and ranged timers stacked above", off.anchorInfo.relativeTo == "SwingTimerMainHandFrame"
		and ranged.anchorInfo.relativeTo == "SwingTimerOffHandFrame" and ranged.anchorInfo.offsetY == 4)
	check("swing timers only in combat", visibility(main) == 1 and visibility(off) == 1 and visibility(ranged) == 1)
	check("swing timer width left alone", main.settings[3].value == 213)
end

-- Settings as a string: exported from one character, imported on another.
local function editDialog(text)
	local box = { text = text }
	function box:GetText() return self.text end
	function box:SetText(t) self.text = t end
	function box:HighlightText() end
	function box:SetFocus() end
	local dialog = {}
	function dialog:GetEditBox() return box end
	function dialog:Hide() self.hidden = true end
	box.GetParent = function() return dialog end
	return dialog, box
end

do
	local blobs = {}
	local from = { units = { player = mage }, blobs = blobs }
	local env = boot(from)
	from.settings.dispellableOnly:SetValue(true)
	from.settings.cooldownFontSize:SetValue(24)
	from.settings.gearRole:SetValue("TANK")
	check("export buttons in the quick section", from.buttons["설정 내보내기"] ~= nil and from.buttons["설정 가져오기"] ~= nil)
	local dialog, box = editDialog("")
	env.StaticPopupDialogs.KSUI_EXPORT_PROFILE.OnShow(dialog)
	local text = box.text
	check("export string has its prefix", text:sub(1, 6) == "KSUI1:")
	check("export box has no length limit", env.StaticPopupDialogs.KSUI_EXPORT_PROFILE.maxLetters == 0
		and env.StaticPopupDialogs.KSUI_IMPORT_PROFILE.maxLetters == 0)
	local exported = blobs[#blobs]
	check("only panel settings exported", exported.cooldownFontSize == 24 and exported.positionsVersion == nil
		and exported.blockedLog == nil)

	local to = { units = { player = mage }, blobs = blobs }
	local env2 = boot(to)
	local importDialog = editDialog("  " .. text .. "\n")
	env2.StaticPopupDialogs.KSUI_IMPORT_PROFILE.OnAccept(importDialog)
	check("imported values saved", env2.KSUIDB.dispellableOnly == true and env2.KSUIDB.cooldownFontSize == 24
		and env2.KSUIDB.gearRole == "TANK")
	check("import ran the setting's refresh", to.cvars.raidFramesDisplayOnlyDispellableDebuffs == "1")
	check("import reported", to.printed:find("가져왔습니다") ~= nil)
end

do
	local blobs = { {
		cooldownFontSize = 99, fadeAlpha = 0.5, gearRole = "BARD", artColor = "red", autoRepair = "yes",
		chatLinks = false, unknownKey = true,
	} }
	local state = { units = { player = mage }, blobs = blobs }
	local env, ns = boot(state)
	local applied = ns.ImportProfile("KSUI1:bzcbor1")
	check("only valid values imported", applied == 2 and env.KSUIDB.fadeAlpha == 0.5 and env.KSUIDB.chatLinks == false)
	check("out of range, unknown choice, bad color and wrong type refused", env.KSUIDB.cooldownFontSize == 16
		and env.KSUIDB.gearRole == "AUTO" and env.KSUIDB.artColor == "ff474752" and env.KSUIDB.autoRepair == true)
	check("unknown keys left out of the saved variables", env.KSUIDB.unknownKey == nil)
	blobs[2] = { cooldownFontSize = 15.37, fadeAlpha = 0.33, frameXPct = 6.09374 }
	ns.ImportProfile("KSUI1:bzcbor2")
	check("imported slider values put on their step", env.KSUIDB.cooldownFontSize == 15 and env.KSUIDB.fadeAlpha == 0.35
		and env.KSUIDB.frameXPct == 6.1)
	check("garbage is not a profile", ns.ImportProfile("hello") == nil and ns.ImportProfile("KSUI1:@@@") == nil
		and ns.ImportProfile("KSUI1:bzcbor9") == nil)
	env.StaticPopupDialogs.KSUI_IMPORT_PROFILE.EditBoxOnEnterPressed(select(2, editDialog("nope")))
	check("bad paste reported", state.printed:find("설정 문자열이 아닙니다") ~= nil)
	blobs[3] = { cooldownFontSize = 9.9, frameXPct = 30.04 }
	ns.ImportProfile("KSUI1:bzcbor3")
	check("values just out of range refused, not rounded in", env.KSUIDB.cooldownFontSize == 15
		and env.KSUIDB.frameXPct == 6.1)
	blobs[4] = { cooldownFontSize = "bad" }
	state.printed = nil
	env.StaticPopupDialogs.KSUI_IMPORT_PROFILE.EditBoxOnEnterPressed(select(2, editDialog("KSUI1:bzcbor4")))
	check("a profile with nothing usable is reported as not a profile", state.printed:find("설정 문자열이 아닙니다") ~= nil)
	env.SlashCmdList.KSUI("export")
	env.SlashCmdList.KSUI("import")
	check("slash commands open the dialogs", state.popups[1][1] == "KSUI_EXPORT_PROFILE" and state.popups[2][1] == "KSUI_IMPORT_PROFILE")
end

-- On a client in any other language the text is English.
do
	local state = { units = { player = mage }, locale = "enUS" }
	local env = boot(state)
	check("settings category in English", state.categoryName == "Kumsung UI")
	check("option label in English", state.headers[2] == "Look" and state.buttons["Apply layout"] ~= nil)
	state.combat = true
	env.SlashCmdList.KSUI("layout")
	check("message in English", state.printed == "KSUI: the layout can't be changed in combat.")
end

do
	-- Every string shown in game goes through ns.T; a Korean literal outside it would show as boxes elsewhere.
	local stray = {}
	for _, file in ipairs(tocFiles()) do
		local n = 0
		for line in io.lines(ADDON_DIR .. file) do
			n = n + 1
			local code = line:gsub("%-%-.*", "")
			for literal in code:gmatch('"([^"]*)"') do
				if literal:find("[\234-\237]") and not code:find('T%("' .. literal:gsub("%p", "%%%0"), 1) then
					stray[#stray + 1] = file .. ":" .. n
				end
			end
		end
	end
	check("no Korean text outside ns.T: " .. table.concat(stray, ", "), #stray == 0)
end

-- Blocked actions
do
	local state = { units = { player = mage } }
	local env = boot(state)
	fire(env, "ADDON_ACTION_BLOCKED", "OtherAddon", "Foo()")
	check("other addons' blocks ignored", env.KSUIDB.blockedLog == nil)
	state.combat = true
	fire(env, "ADDON_ACTION_FORBIDDEN", "KSUI", "TargetUnit()")
	check("own block printed and kept", env.KSUIDB.blockedLog[1] == "11-15 20:09:00 ADDON_ACTION_FORBIDDEN TargetUnit() (전투 중)"
		and state.printed:find("TargetUnit", 1, true) ~= nil)
	state.combat = false
	for i = 1, 25 do fire(env, "ADDON_ACTION_BLOCKED", "KSUI", "Call" .. i) end
	check("log keeps the last 20", #env.KSUIDB.blockedLog == 20 and env.KSUIDB.blockedLog[20]:find("Call25", 1, true) ~= nil)
end

-- Chat timestamps
do
	local state = { units = { player = mage } }
	boot(state)
	check("chat timestamps on by default", state.cvars.showTimestamps == "|cff8c8c8c[%H:%M]|r "
		and os.date(state.cvars.showTimestamps, 0):match("^|cff8c8c8c%[%d%d:%d%d%]|r $") ~= nil)
	state.settings.chatTimestamps:SetValue(false)
	check("chat timestamps off", state.cvars.showTimestamps == "none")
end

-- Square unit frames
local function unitFrame(state, unit)
	for _, f in ipairs(state.frames) do
		if f.unit == unit then return f end
	end
end

-- Your own party row gets shield and HoT icons like the others.
do
	local state = { units = { player = mage } }
	local env = boot(state)
	local button, row
	for _, f in ipairs(state.frames) do
		if f.parent == env.PartyFrame and f.template == "SecureUnitButtonTemplate" then button = f end
		if button and f.unit == "player" and f.parent == button then row = f end
	end
	check("your party row has shield and HoT icons", row ~= nil and row.hots ~= nil and #row.hots == 4
		and row.blizzardHots == nil)
	state.myAuras = { player = { { name = "소생", icon = "renew", auraInstanceID = 7, duration = 0 } } }
	fire(env, "UNIT_AURA", "player")
	check("and they show your heals over time", row.hots[1].shown and row.hots[1].texture.file == "renew")
end

-- Your pet and your target's target
do
	local state = { units = { player = mage, pet = { player = false, name = "Wolf", health = 30, maxHealth = 60 },
		target = { player = false }, targettarget = mage } }
	local env = boot(state)
	local pet = unitFrame(state, "pet")
	check("square pet frame inside Blizzard's", pet.parent == env.PetFrame and pet.size[1] == 120 and pet.size[2] == 46)
	check("the whole square pet frame takes clicks", table.concat(env.PetFrame.hitInsets, ",") == "0,0,0,0")
	check("Blizzard's pet art faded", env.PetFrameTexture.alpha == 0 and env.PetFrameHealthBar.alpha == 0
		and env.PetPortrait.alpha == 0)
	fire(env, "UNIT_HEALTH", "pet")
	check("pet health shown", pet.health.barValue == 30 and pet.health.range[2] == 60)
	local tot = unitFrame(state, "targettarget")
	check("square target of target inside Blizzard's", tot.parent == env.TargetFrameToT
		and env.TargetFrameToT.FrameTexture.alpha == 0)
	state.units.targettarget = { player = true, class = "MAGE", health = 12 }
	local loads = tot.model.modelLoads or 0
	env.TargetFrameToT:Update()
	check("target of target follows Blizzard's redraws", state.totRedraws == 1 and tot.health.barValue == 12)
	check("no model reload on a redraw", (tot.model.modelLoads or 0) == loads)
	fire(env, "UNIT_TARGET", "target")
	check("model reloads when the target picks a new target", tot.model.modelLoads == loads + 1)
	-- Blizzard's bars follow health from OnUpdate between redraws; ours read it a few times a second.
	state.units.targettarget.health = 8
	tot.scripts.OnUpdate(tot, 0.1)
	check("target of target health not read every frame", tot.health.barValue == 12)
	tot.scripts.OnUpdate(tot, 0.15)
	check("target of target health followed between redraws", tot.health.barValue == 8)
	state.settings.customUnitFrames:SetValue(false)
	check("Blizzard's pet and target of target art back", env.PetFrameTexture.alpha == 1 and env.TargetFrameToT.Portrait.alpha == 1)
	check("Blizzard's pet click area back", table.concat(env.PetFrame.hitInsets, ",") == "7,66,6,7")
	state.units.targettarget.health = 5
	env.TargetFrameToT:Update()
	check("no redraw while switched off", tot.health.barValue == 8)
end

-- A secure part can't fade in combat; it does when combat ends.
do
	local state = { units = { player = mage, targettarget = mage } }
	local env = boot(state)
	local bar = env.TargetFrameToT.HealthBar
	function bar:IsProtected() return true end
	state.combat = true
	state.settings.customUnitFrames:SetValue(false)
	check("secure part left alone in combat", bar.alpha == 0 and env.TargetFrameToT.Portrait.alpha == 1)
	state.combat = false
	fire(env, "PLAYER_REGEN_ENABLED")
	check("secure part caught up after combat", bar.alpha == 1)
	check("pet click area and auras put back after combat", table.concat(env.PetFrame.hitInsets, ",") == "7,66,6,7")
end

do
	local state = { units = { player = mage }, noToT = true }
	boot(state)
	check("works without a target of target frame", unitFrame(state, "targettarget") == nil)
end

-- Ammo on your health bar
do
	local state = { units = { player = mage } }
	boot(state)
	local player = unitFrame(state, "player")
	local text = player.ammo
	check("ammo text on the player health bar", text.parent == player.health.texts and text.point[1] == "BOTTOMLEFT")
	check("no ammo text for a class without ammo", text.shown == false)
end

do
	local state = { units = { player = { player = true, class = "HUNTER" } }, ammo = 1200 }
	local env = boot(state)
	local text = unitFrame(state, "player").ammo
	check("ammo count shown", text.shown == true and text.format[1] == "탄약 %s" and text.format[2] == 1200
		and text.textColor[2] == 1)
	state.ammo = 40
	fire(env, "BAG_UPDATE")
	check("low ammo in red", text.format[2] == 40 and text.textColor[1] == 1 and text.textColor[2] == 0.2)
	state.ammo = SECRET
	fire(env, "UNIT_INVENTORY_CHANGED", "player")
	check("secret ammo count passed through", text.format[2] == SECRET and text.textColor[2] == 1)
	state.settings.ammoCount:SetValue(false)
	check("ammo count switched off", text.shown == false)
end

do
	local state = { units = { player = { player = true, class = "HUNTER" } }, ammo = 1200, locale = "enUS" }
	boot(state)
	check("ammo count in English", unitFrame(state, "player").ammo.format[1] == "Ammo %s")
end

do
	local state = { units = { player = mage, target = { player = false, level = -1, name = "Boss" } } }
	local env = boot(state)
	local player, target = unitFrame(state, "player"), unitFrame(state, "target")
	check("Blizzard player art faded", env.PlayerFrame.PlayerFrameContainer.alpha == 0
		and env.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.alpha == 0)
	check("Blizzard target and focus art faded", env.TargetFrame.TargetFrameContainer.alpha == 0
		and env.FocusFrame.TargetFrameContent.TargetFrameContentMain.alpha == 0)
	check("own frames are children of Blizzard's", player.parent == env.PlayerFrame and target.parent == env.TargetFrame
		and unitFrame(state, "focus").parent == env.FocusFrame)
	check("player portrait on the left", player.portrait.point[1] == "TOPLEFT")
	check("target portrait on the right", target.portrait.point[1] == "TOPRIGHT")
	check("player health filled", player.health.range[2] == 100 and player.health.barValue == 80)
	check("no shield, no shield number", player.absorb.barValue == 0 and player.health.absorbValue.shown == false)
	check("heal bar starts where the health fill ends, the shield bar where the heal ends, clipped by the bar",
		player.heal.points.TOPLEFT[2] == player.health.fill and player.heal.points.TOPLEFT[3] == "TOPRIGHT"
		and player.absorb.points.TOPLEFT[2] == player.heal.fill and player.health.clips == true)
	player.health.scripts.OnSizeChanged(player.health, 150)
	check("both as wide as the health bar", player.heal.width == 150 and player.absorb.width == 150)
	local holder = player.health.value.parent
	check("bar text drawn above the shield bar", holder and holder.level > player.absorb:GetFrameLevel()
		and player.health.name.parent == holder and player.health.absorbValue.parent == holder)
	state.units.player.absorb = 1500
	fire(env, "UNIT_ABSORB_AMOUNT_CHANGED", "player")
	check("shield on the health scale with its number", player.absorb.range[2] == 100 and player.absorb.barValue == 1500
		and player.health.absorbValue.shown == true and player.health.absorbValue.text == "|cff8cd8ff+1500|r")
	state.units.player.incomingHeal = 300
	fire(env, "UNIT_HEAL_PREDICTION", "player")
	check("incoming heal on the health scale, its amount first", player.heal.range[2] == 100 and player.heal.barValue == 300
		and player.health.absorbValue.text == "|cff59e559+300|r |cff8cd8ff+1500|r")
	check("health text with percent", player.health.value.format[2] == "80" and player.health.value.format[3] == 80)
	check("player class colored", player.health.color[1] == 0.2)
	check("bar text outlined at its own size", player.health.name.font[3] == "OUTLINE" and player.health.name.font[2] == 10
		and player.health.value.font[3] == "OUTLINE" and player.power.value.font[3] == "OUTLINE")
	check("mana colored", player.power.color[3] == 1 and player.power.barValue == 50)
	check("player name with level", player.health.name.format[2] == 14 and player.health.name.format[3] == "Name")
	check("player model loaded", player.model.modelUnit == "player" and player.model.zoom == 1 and player.picture.shown == false)

	fire(env, "PLAYER_TARGET_CHANGED")
	check("boss level shown as ??", target.health.name.format[2] == "??" and target.health.name.format[3] == "Boss")

	state.units.player.surname = "광이"
	state.units.player.level = 15
	fire(env, "PLAYER_LEVEL_CHANGED")
	local name = player.health.name.format
	check("level-up and surname shown", name[2] == 15 and name[3] == "Name" and name[4] == " " and name[5] == "광이")
	state.units.player.surname = nil
	state.units.player.level = nil
	local loadsBefore = player.model.modelLoads
	fire(env, "PORTRAITS_UPDATED")
	check("global portrait refresh reloads the model", player.model.modelLoads == loadsBefore + 1)
	check("NPC target uses selection color", target.health.color[1] == 0.9)
	check("power number shown when there is power", target.power.value.alpha == 1)
	state.units.target.maxPower = 0
	state.units.target.power = 0
	fire(env, "UNIT_MAXPOWER")
	check("power number hidden without power", target.power.value.alpha == 0)
	state.units.target.maxPower = 100
	fire(env, "UNIT_POWER_UPDATE")
	check("empty rage hides its number too", target.power.value.alpha == 0)
	state.units.target.power = 30
	fire(env, "UNIT_POWER_UPDATE")
	check("number back once rage builds", target.power.value.alpha == 1)

	local loads = player.model.modelLoads
	state.units.player.health = 40
	fire(env, "UNIT_HEALTH", "player")
	check("health event updates the bar", player.health.barValue == 40)
	check("health event leaves the model alone", player.model.modelLoads == loads)
	fire(env, "UNIT_MODEL_CHANGED", "player")
	check("model change reloads it", player.model.modelLoads == loads + 1)

	state.settings.healthPercent:SetValue(false)
	check("percent text off", player.health.value.text == "40")
	state.settings.classColorBars:SetValue(false)
	check("plain green without class colors", player.health.color[1] == 0.1 and player.health.color[2] == 0.8)

	state.settings.animatedPortraits:SetValue(false)
	check("still portrait when animation is off", player.model.shown == false and player.picture.shown == true
		and player.picture.portraitOf[1] == "player" and player.picture.portraitOf[2] == true)

	state.settings.customUnitFrames:SetValue(false)
	check("Blizzard art back when off", env.PlayerFrame.PlayerFrameContainer.alpha == 1
		and env.TargetFrame.TargetFrameContent.TargetFrameContentMain.alpha == 1)
	check("own frames hidden when off", player.shown == false and target.shown == false)
	state.units.player.health = 10
	fire(env, "UNIT_HEALTH", "player")
	check("no updates while off", player.health.barValue == 40)
end

-- In instances health, power, names and power type can be secret; they must reach only secret-safe setters.
do
	local target = { player = false, health = SECRET, maxHealth = SECRET, power = SECRET, maxPower = SECRET,
		name = SECRET, surname = SECRET, level = SECRET, hiddenIdentity = true }
	local state = { units = { player = mage, target = target }, powerToken = SECRET }
	local env = boot(state)
	env.UnitSelectionColor = function() return SECRET, SECRET, SECRET, 1 end
	fire(env, "PLAYER_TARGET_CHANGED")
	local frame = unitFrame(state, "target")
	check("secret health reaches the bar", frame.health.barValue == SECRET and frame.health.range[2] == SECRET)
	check("secret health reaches the text", frame.health.value.format[2] == SECRET and frame.health.value.format[3] == SECRET)
	target.absorb = SECRET
	fire(env, "UNIT_ABSORB_AMOUNT_CHANGED", "target")
	check("secret shield reaches only the bar", frame.absorb.barValue == SECRET and frame.health.absorbValue.shown == false)
	check("secret power type falls back to mana", frame.power.color[3] == 1)
	check("secret power decides the number's alpha itself", frame.power.value.alpha == SECRET)
	check("secret name and level pass through", frame.health.name.format[2] == SECRET and frame.health.name.format[3] == SECRET
		and frame.health.name.format[5] == SECRET)
	check("secret bar color passes through", frame.health.color[1] == SECRET)
	check("hidden identity uses the still portrait", frame.model.shown == false and frame.picture.portraitOf[1] == "target")
end

do
	local state = { units = { player = mage, target = { player = true, class = "MAGE", far = true } } }
	local env = boot(state)
	fire(env, "PLAYER_TARGET_CHANGED")
	check("far target uses the still portrait", unitFrame(state, "target").picture.shown == true)
end

-- Party frames
local function countUnit(state, unit)
	local n = 0
	for _, f in ipairs(state.frames) do
		if f.unit == unit then n = n + 1 end
	end
	return n
end

do
	local state = { units = { player = mage, party1 = { player = true, class = "MAGE", name = "Friend" },
		party2 = { player = true, class = "MAGE" } } }
	local env = boot(state)
	local member = env.partyMembers[1]
	local frame = unitFrame(state, "party1")
	check("party frame drawn on the member", frame and frame.parent == member and frame.size[1] == 200 and frame.size[2] == 52)
	check("party frame grows right from Blizzard's", frame.point[1] == "LEFT")
	check("names stay on one line", frame.health.name.wrap == false)
	local clicker = frame.clicker
	check("bars past Blizzard's frame are clickable", clicker and clicker.template == "SecureUnitButtonTemplate"
		and clicker.parent == member and clicker.width == 80 and clicker.attributes.unit == "party1"
		and clicker.attributes.type1 == "target" and clicker.attributes.type2 == "togglemenu" and clicker.shown == true)
	-- The mock counts every SetPoint; the party name's right end is set again to stop short of the role icon.
	check("long names cut before the role icon", frame.health.name.points == 3 and frame.health.name.point[1] == "TOPRIGHT"
		and frame.health.name.point[2] == -18 and frame.health.name.justify == "LEFT"
		and unitFrame(state, "target").health.name.justify == "RIGHT")
	check("party portrait on the left", frame.portrait.point[1] == "TOPLEFT" and frame.portrait.size[1] == 50)
	check("party art faded", member.Texture.alpha == 0 and member.Portrait.alpha == 0 and member.Name.alpha == 0
		and member.HealthBarContainer.alpha == 0 and member.ManaBar.alpha == 0)
	check("Blizzard's aggro glow becomes the row's edge", member.Flash.parent == frame
		and member.Flash.file == "Interface\\ChatFrame\\ChatFrameBackground" and member.Flash.point[1] == "BOTTOMRIGHT")
	check("Blizzard's debuff icons sit right of the row", member.AuraFrameContainer.point[1] == "TOPLEFT"
		and member.AuraFrameContainer.point[2] == frame and member.AuraFrameContainer.point[3] == "TOPRIGHT")
	state.combat = true
	member:ToPlayerArt()
	check("squared off again after Blizzard redraws its art, in combat too", member.Flash.parent == frame
		and member.Flash.point[1] == "BOTTOMRIGHT" and member.Flash.file == "Interface\\ChatFrame\\ChatFrameBackground")
	state.combat = false
	-- Measured in game: every party aura comes with duration 0, and long group buffs come along.
	state.myAuras = { party1 = {
		{ name = "신의 권능: 인내", icon = "fortitude", auraInstanceID = 1, duration = 0 },
		{ name = "왕의 축복", icon = "kings", auraInstanceID = 2, duration = 0 },
		{ name = "소생", icon = "renew", auraInstanceID = 7, duration = 15 },
		{ name = SECRET, icon = "hidden", auraInstanceID = 3, duration = 0 },
		{ name = "신의 권능: 보호막", icon = "shield", auraInstanceID = 8, duration = 0 },
	} }
	fire(env, "UNIT_AURA", "party1")
	check("only shields and heals over time, by name", frame.hots[1].shown and frame.hots[1].texture.file == "renew"
		and frame.hots[2].texture.file == "shield" and frame.hots[3].shown == false)
	check("time shown when the game gives one", frame.hots[1].cooldown.duration.id == 7 and frame.hots[2].cooldown.duration == nil)
	-- A readable list can hold an aura that isn't, and the duration query can be refused on its own.
	table.insert(state.myAuras.party1, 1, { locked = true })
	local getDuration = env.C_UnitAuras.GetAuraDuration
	env.C_UnitAuras.GetAuraDuration = function() error("GetAuraDuration(): Auras cannot be accessed when secret") end
	fire(env, "UNIT_AURA", "party1")
	check("an unreadable aura in the list is skipped", frame.hots[1].shown and frame.hots[1].texture.file == "renew")
	check("a refused duration leaves the icon without a timer", frame.hots[1].cooldown.duration == nil)
	env.C_UnitAuras.GetAuraDuration = getDuration
	state.myAuras = { party1 = SECRET }
	fire(env, "UNIT_AURA", "party1")
	check("an unreadable aura list hides them", frame.hots[1].shown == false)
	-- In instances asking at all is an error for addon code; KSUI doesn't ask then.
	state.myAuras = { party1 = { { name = "소생", icon = "renew", auraInstanceID = 7, duration = 15 } } }
	state.secretAuras = true
	fire(env, "UNIT_AURA", "party1")
	check("auras not asked for while secret", frame.hots[1].shown == false)
	state.secretAuras = nil
	state.auraBlocked = { party1 = true }
	fire(env, "UNIT_AURA", "party1")
	check("a unit restricted on its own is skipped", frame.hots[1].shown == false)
	state.auraBlocked = nil
	fire(env, "UNIT_AURA", "party1")
	check("shown again once readable", frame.hots[1].shown == true)
	-- No duration from the game: KSUI times what UNIT_AURA reports added, for the spell's length in its list.
	local renew = { name = "소생", icon = "renew", auraInstanceID = 20, duration = 0, spellId = 6074 }
	local shield = { name = "신의 권능: 보호막", icon = "shield", auraInstanceID = 21, duration = 0, spellId = 10901 }
	local bop = { name = "보호의 축복", icon = "bop", auraInstanceID = 22, duration = 0, spellId = 10278 }
	local old = { name = "회복", icon = "rejuv", auraInstanceID = 23, duration = 0, spellId = 774 }
	state.myAuras = { party1 = { renew, shield, bop, old } }
	fire(env, "UNIT_AURA", "party1", { addedAuras = { renew, shield, bop } })
	check("an added heal over time is timed from now", frame.hots[1].cooldown.timer[1] == 100
		and frame.hots[1].cooldown.timer[2] == 15)
	check("shields too", frame.hots[2].cooldown.timer[2] == 30)
	check("a rank's own length", frame.hots[3].cooldown.timer[2] == 10)
	check("one already there when KSUI first saw it gets no timer", frame.hots[4].shown
		and frame.hots[4].cooldown.timer == nil)
	state.now = 105
	fire(env, "UNIT_AURA", "party1", { updatedAuraInstanceIDs = { 20, 21, 23 } })
	check("a re-cast heal over time starts again", frame.hots[1].cooldown.timer[1] == 105)
	check("a shield's update is its amount, not a re-cast", frame.hots[2].cooldown.timer[1] == 100)
	check("a heal's update is a re-cast, timing one first seen earlier", frame.hots[4].cooldown.timer[1] == 105)
	-- A start that comes after the icon was drawn still reaches it.
	local late = { name = "회복", icon = "rejuv", auraInstanceID = 24, duration = 0, spellId = 774 }
	state.myAuras = { party1 = { late } }
	fire(env, "UNIT_AURA", "party1")
	check("drawn untimed before the start is known", frame.hots[1].cooldown.timer == nil)
	for _, h in ipairs(env.events) do
		if h.frame.registered.UNIT_AURA then h.fn(h.frame, "UNIT_AURA", "party1", { addedAuras = { late } }); break end
	end
	check("the tracker restarts an icon already showing the aura", frame.hots[1].cooldown.timer[1] == 105
		and frame.hots[1].cooldown.timer[2] == 12)
	fire(env, "UNIT_AURA", "party1", { removedAuraInstanceIDs = { 24 } })
	state.myAuras = { party1 = { late } }
	fire(env, "UNIT_AURA", "party1")
	check("a removed aura's start is forgotten", frame.hots[1].cooldown.timer == nil)
	-- Weakened Soul is a debuff; it follows the buffs, timed the same way.
	local weakened = { name = "약화된 영혼", icon = "weakened", auraInstanceID = 25, duration = 0, spellId = 6788 }
	state.myAuras = { party1 = { shield } }
	state.myDebuffs = { party1 = { { name = "독", icon = "poison", auraInstanceID = 26 }, weakened } }
	fire(env, "UNIT_AURA", "party1", { addedAuras = { weakened } })
	check("Weakened Soul shows after the shield, timed", frame.hots[2].shown and frame.hots[2].texture.file == "weakened"
		and frame.hots[2].cooldown.timer[2] == 15 and frame.hots[3].shown == false)
	-- Renewed Hope shortens Weakened Soul with an update; that isn't a new one.
	state.now = 110
	fire(env, "UNIT_AURA", "party1", { updatedAuraInstanceIDs = { 25 } })
	check("a lockout's update doesn't restart it", frame.hots[2].cooldown.timer[1] == 105)
	state.myAuras = { party1 = { renew, shield, bop, old } }
	fire(env, "UNIT_AURA", "party1")
	check("a full row keeps the lockout's place", frame.hots[4].texture.file == "weakened"
		and frame.hots[3].texture.file == "bop")
	-- The Voidwalker's Sacrifice shares its name with a stun.
	state.myAuras = { party1 = {} }
	state.myDebuffs = { party1 = { { name = "희생", icon = "stun", auraInstanceID = 27, duration = 0, spellId = 22651 } } }
	fire(env, "UNIT_AURA", "party1")
	check("a harmful aura with a buff's name isn't shown", frame.hots[1].shown == false)
	-- A full update drops the unit's starts; a time that is over is dropped too.
	state.myAuras = { party1 = { renew } }
	state.myDebuffs = nil
	fire(env, "UNIT_AURA", "party1", { addedAuras = { renew } })
	check("timed before the full update", frame.hots[1].cooldown.timer ~= nil)
	fire(env, "UNIT_AURA", "party1", { isFullUpdate = true })
	check("a full update drops the unit's starts", frame.hots[1].cooldown.timer == nil)
	fire(env, "UNIT_AURA", "party1", { addedAuras = { renew } })
	state.now = 200
	fire(env, "UNIT_AURA", "party1")
	check("a start whose time is over is dropped", frame.hots[1].cooldown.timer == nil)
	-- The game's own duration wins over a late start from the tracker.
	local own = { name = "소생", icon = "renew", auraInstanceID = 28, duration = 18, spellId = 139 }
	state.myAuras = { party1 = { own } }
	fire(env, "UNIT_AURA", "party1")
	for _, h in ipairs(env.events) do
		if h.frame.registered.UNIT_AURA then h.fn(h.frame, "UNIT_AURA", "party1", { addedAuras = { own } }); break end
	end
	check("a late start doesn't replace the game's duration", frame.hots[1].cooldown.duration.id == 28
		and frame.hots[1].cooldown.timer == nil)
	fire(env, "UNIT_AURA", "party1", { addedAuras = SECRET, updatedAuraInstanceIDs = SECRET, removedAuraInstanceIDs = SECRET })
	check("secret lists in a readable update are skipped", frame.hots[1].shown)
	state.myDebuffs = nil
	state.now = nil
	fire(env, "UNIT_AURA", SECRET, SECRET)
	check("a secret update is ignored", true)
	state.myAuras = { party1 = { { name = "소생", icon = "renew", auraInstanceID = 7, duration = 15 } } }
	fire(env, "UNIT_AURA", "party1")
	check("party member filled", frame.health.barValue == 80 and frame.health.name.format[3] == "Friend")
	member.Portrait:SetAlpha(0.7)
	check("Blizzard's portrait pulse stays hidden", member.Portrait.alpha == 0)
	state.units.party1.health = 30
	fire(env, "UNIT_HEALTH", "party1")
	check("party health event", frame.health.barValue == 30 and unitFrame(state, "party2").health.barValue == 80)
	state.units.party1.outOfRange = true
	fire(env, "UNIT_IN_RANGE_UPDATE", "party1", false)
	check("an out of range member's row fades", frame.alphaFrom[1] == true and frame.alphaFrom[2] < 1
		and frame.alphaFrom[3] == 1)
	state.units.party1.outOfRange = SECRET
	fire(env, "UNIT_IN_RANGE_UPDATE", "party1", SECRET)
	check("secret answers go to the secret-safe calls", frame.alphaFrom[1] == SECRET and frame.alphaFrom[2] == SECRET)
	state.units.party1.outOfRange, state.units.party1.unchecked = true, true
	fire(env, "UNIT_IN_RANGE_UPDATE", "party1", false)
	check("an unchecked range leaves the row lit", frame.alphaFrom[1] == false and frame.alphaFrom[3] == 1)
	state.units.party1.outOfRange, state.units.party1.unchecked = nil, nil
	fire(env, "UNIT_IN_RANGE_UPDATE", "party1", true)
	check("back in range, lit again", frame.alphaFrom[1] == true and frame.alphaFrom[2] == 1)
	check("only the fading rows listen for range", frame.events.registered.UNIT_IN_RANGE_UPDATE
		and not unitFrame(state, "target").events.registered.UNIT_IN_RANGE_UPDATE)

	member.unitToken = "party3"
	state.units.party3 = { player = true, class = "MAGE" }
	env.PartyFrame:InitializePartyMemberFrames()
	check("rebuilt pool reuses the frame with the new unit", frame.unit == "party3" and frame.events.units.UNIT_HEALTH == "party3"
		and frame.clicker.attributes.unit == "party3")
	member.unitToken = "party4"
	state.units.party4 = { player = true, class = "MAGE" }
	state.combat = true
	env.PartyFrame:InitializePartyMemberFrames()
	check("clicker left alone in combat", frame.clicker.attributes.unit == "party3")
	state.combat = false
	fire(env, "PLAYER_REGEN_ENABLED")
	check("clicker follows after combat", frame.clicker.attributes.unit == "party4")
	check("no second frame on rebuild", countUnit(state, "party4") == 1 and countUnit(state, "party2") == 1)

	state.settings.customUnitFrames:SetValue(false)
	member.Portrait:SetAlpha(0.5)
	check("party art back when off", member.Texture.alpha == 1 and member.Portrait.alpha == 0.5 and frame.shown == false
		and frame.clicker.shown == false)
end

do
	local state = { units = { player = mage, party1 = { player = true, class = "MAGE" } }, noParty = true }
	local env = boot(state)
	env.partyMembers[1] = env.newPartyMember(1)
	env.PartyFrame:InitializePartyMemberFrames()
	local frame = unitFrame(state, "party1")
	check("party joined after login gets a frame", frame ~= nil and env.partyMembers[1].Texture.alpha == 0
		and frame.health.barValue == 80)
end

-- You in the party
do
	local state = { units = { player = mage } }
	local env, ns = boot(state)
	-- This mock has no Edit Mode layouts to apply; the layout side is tested on its own.
	ns.LayoutSettingChanged = function() end
	local row
	for _, f in ipairs(state.frames) do
		if f.template == "SecureUnitButtonTemplate" and f.parent == env.PartyFrame then row = f end
	end
	check("a secure row for you on top of the party", row and row.attributes.unit == "player"
		and row.attributes.type1 == "target" and row.attributes.type2 == "togglemenu"
		and row.point[1] == "BOTTOMLEFT" and row.point[2] == env.PartyFrame and row.point[3] == "TOPLEFT" and row.point[5] == 10)
	check("shown in a party, not in a raid", state.drivers[row] == "[group:raid] hide; [group:party] show; hide")
	local drawn
	for _, f in ipairs(state.frames) do
		if f.unit == "player" and f.parent == row then drawn = f end
	end
	check("drawn like the party rows", drawn ~= nil and drawn.size[1] == 200)
	state.units.player.outOfRange = true
	fire(env, "UNIT_IN_RANGE_UPDATE", "player", false)
	check("your own row doesn't fade", drawn.alphaFrom == nil)
	state.units.player.outOfRange = nil
	state.roles = { player = "HEALER" }
	fire(env, "PLAYER_ROLES_ASSIGNED")
	check("role icon shown", drawn.role.atlas == "roleicon-tiny-healer" and drawn.role.shown == true)
	state.roles = { player = "NONE" }
	fire(env, "PLAYER_ROLES_ASSIGNED")
	check("no role, no icon", drawn.role.shown == false)
	state.roles = { player = SECRET }
	fire(env, "PLAYER_ROLES_ASSIGNED")
	check("a secret role hides the icon", drawn.role.shown == false)
	state.raidStyleParty = true
	env.PartyFrame:UpdatePartyFrames()
	check("raid-style party frames have you already", state.drivers[row] == nil and row.shown == false)
	state.raidStyleParty = false
	state.combat = true
	state.settings.customUnitFrames:SetValue(true)
	check("not touched in combat", state.drivers[row] == nil)
	state.combat = false
	fire(env, "PLAYER_REGEN_ENABLED")
	check("caught up after combat", state.drivers[row] ~= nil)
	state.settings.customUnitFrames:SetValue(false)
	check("option off removes it", state.drivers[row] == nil and row.shown == false)
end

-- Shield icons on Blizzard's frames: raid frames (and raid-style party frames), and its party frames with KSUI's rows off.
do
	local state = { units = { player = mage, party1 = { player = true, class = "PRIEST" }, raid3 = { player = true } } }
	local env = boot(state)
	local function compact(name, forbidden)
		return { GetName = function() return name end, IsForbidden = function() return forbidden end,
			GetFrameLevel = function() return 2 end }
	end
	local shield = { name = "신의 권능: 보호막", icon = "shield", auraInstanceID = 9, duration = 0 }
	local kings = { name = "왕의 축복", icon = "kings", auraInstanceID = 10, duration = 0 }
	state.myAuras = { raid3 = { kings, shield }, party1 = { shield } }
	local raid, plate = compact("CompactRaidFrame3"), compact("NamePlate1", false)
	env.CompactUnitFrame_SetUnit(raid, "raid3")
	env.CompactUnitFrame_SetUnit(plate, "raid3")
	env.CompactUnitFrame_SetUnit(compact("CompactPartyFrameMember1", true), "party1")
	local raidIcons, plateIcons = {}, {}
	for _, f in ipairs(state.frames) do
		if f.parent == raid and f.size then raidIcons[#raidIcons + 1] = f end
		if f.parent == plate then plateIcons[#plateIcons + 1] = f end
	end
	check("raid frames get the shield, not the blessing", #raidIcons == 4 and raidIcons[1].shown
		and raidIcons[1].texture.file == "shield" and raidIcons[2].shown == false)
	check("other frames that code draws are left alone", #plateIcons == 0)
	-- Where auras are restricted the event's unit can be secret; it is not compared then, and every frame is redrawn,
	-- clearing the icons that can't be read any more.
	state.secretAuras = true
	fire(env, "UNIT_AURA", SECRET)
	check("a secret aura event unit clears what can't be read", raidIcons[1].shown == false)
	state.secretAuras = nil
	fire(env, "UNIT_AURA", "raid3")
	check("icons come back when auras can be read", raidIcons[1].shown == true)
	state.myAuras.raid3 = {}
	fire(env, "UNIT_AURA", "raid3")
	check("they follow the unit's auras", raidIcons[1].shown == false)

	local member = env.partyMembers[1]
	state.settings.customUnitFrames:SetValue(false)
	fire(env, "UNIT_AURA", "party1")
	local blizzardIcons = {}
	for _, f in ipairs(state.frames) do
		if f.parent == member and f.size and f.size[1] == 14 then blizzardIcons[#blizzardIcons + 1] = f end
	end
	check("with KSUI's rows off, Blizzard's party frame gets them", #blizzardIcons == 4 and blizzardIcons[1].shown
		and blizzardIcons[1].texture.file == "shield")
	state.settings.customUnitFrames:SetValue(true)
	check("and they go when the rows are back", blizzardIcons[1].shown == false)
end

-- Threat glow
do
	local state = { units = { player = mage } }
	local env = boot(state)
	local player = unitFrame(state, "player")
	local glow = env.PlayerFrame.PlayerFrameContainer.FrameFlash
	check("threat glow moves onto our frame, squared just outside it", glow.parent == player
		and glow.file == "Interface\\ChatFrame\\ChatFrameBackground" and glow.point[1] == "BOTTOMRIGHT" and glow.point[2] == 3
		and glow.layer == "BACKGROUND")
	env.PlayerFrame_UpdateFlashTextureVisuals()
	check("Blizzard reshaping it is squared off again", glow.parent == player and glow.point[1] == "BOTTOMRIGHT")
	state.settings.customUnitFrames:SetValue(false)
	check("option off hands it back to Blizzard", glow.parent == env.PlayerFrame.PlayerFrameContainer
		and glow.atlas == "UI-HUD-UnitFrame-Player-PortraitOn-InCombat" and glow.layer == "OVERLAY"
		and glow.point[1] == "CENTER" and glow.points == 1 and state.statusPlaced == env.PlayerFrame.PlayerFrameContainer)
end

-- Auto quest
do
	local state = { units = { player = mage }, npc = {
		gossipActive = { { questID = 11, isComplete = false }, { questID = 12, isComplete = true } },
		gossipAvailable = { { questID = 21, isTrivial = true }, { questID = 22, isTrivial = false } },
	} }
	local env = boot(state)
	fire(env, "GOSSIP_SHOW")
	check("a finished quest is turned in first", state.picked[1][1] == "active" and state.picked[1][2] == 12)
	state.npc.gossipActive = {}
	fire(env, "GOSSIP_SHOW")
	check("then a new one, skipping gray ones", state.picked[2][1] == "available" and state.picked[2][2] == 22)
	state.npc.active, state.npc.available = { false }, { true, false }
	fire(env, "QUEST_GREETING")
	check("the old greeting window too", state.picked[3][1] == "greetingAvailable" and state.picked[3][2] == 2)
	fire(env, "QUEST_DETAIL")
	check("accepted", state.picked[4][1] == "accept")
	state.npc.pvp = true
	fire(env, "QUEST_DETAIL")
	check("a PvP quest's confirmation stays yours", #state.picked == 4)
	state.npc.pvp, state.npc.questID, state.npc.trivialQuest = false, 31, 31
	fire(env, "QUEST_DETAIL")
	check("a gray quest opened straight away is not picked up", #state.picked == 4)
	state.npc.completable = true
	fire(env, "QUEST_PROGRESS")
	check("handed in", state.picked[5][1] == "complete")
	state.npc.choices = 3
	fire(env, "QUEST_COMPLETE")
	check("a choice of rewards is left to you", #state.picked == 5)
	state.npc.choices = 1
	fire(env, "QUEST_COMPLETE")
	check("a single reward is taken", state.picked[6][1] == "reward" and state.picked[6][2] == 1)
	state.npc.money = 500
	fire(env, "QUEST_COMPLETE")
	check("a quest that costs gold waits for Blizzard's confirmation", #state.picked == 6)
	state.npc.money = nil
	state.shift = true
	fire(env, "QUEST_PROGRESS")
	check("Shift skips it all", #state.picked == 6)
	state.shift = nil
	-- Repeatable quests stay yours, however the window shows them.
	state.npc.gossipActive = { { questID = 41, isComplete = true, repeatable = true } }
	state.npc.gossipAvailable = { { questID = 42, isTrivial = false, frequency = 1 } }
	fire(env, "GOSSIP_SHOW")
	check("a repeatable or daily quest isn't picked from the list", #state.picked == 6)
	state.npc.repeatable = { [43] = true, [44] = true }
	state.npc.gossipActive, state.npc.gossipAvailable = {}, { { questID = 43, isTrivial = false } }
	fire(env, "GOSSIP_SHOW")
	check("nor one only the quest log knows is repeatable", #state.picked == 6)
	state.npc.active, state.npc.activeIDs = { true }, { 44 }
	state.npc.available = { { false, 2, false, false, 45 } }
	fire(env, "QUEST_GREETING")
	check("the greeting window leaves them too", #state.picked == 6)
	state.npc.questID = 44
	fire(env, "QUEST_DETAIL")
	fire(env, "QUEST_PROGRESS")
	fire(env, "QUEST_COMPLETE")
	check("and the quest windows", #state.picked == 6)
	state.npc.questID = 46
	fire(env, "QUEST_PROGRESS")
	check("an ordinary quest still goes", state.picked[7][1] == "complete")
end

-- Chat
do
	local state = { units = { player = mage } }
	local env = boot(state)
	local frame = env.ChatFrame1
	frame:AddMessage("|Hchannel:channel:1|h[1. 공개 - 티리스팔 숲]|h |Hplayer:Way|h[Way]|h: www.example.com 가세요")
	local line = frame.received[1]
	check("channel cut to its name", line:find("|Hchannel:channel:1|h[공개]|h", 1, true) ~= nil)
	check("the sender's link stays", line:find("|Hplayer:Way|h[Way]|h", 1, true) ~= nil)
	check("an address becomes a copy link", line:find("|Hksuiurl:www.example.com|h[www.example.com]|h", 1, true) ~= nil)
	frame:AddMessage("https://www.example.com")
	check("one link for an address with www in it", select(2, frame.received[2]:gsub("|Hksuiurl:", "")) == 1)
	table.remove(frame.received, 2)
	frame:AddMessage("|Hitem:6948|h[https://in.an/item]|h")
	check("addresses inside other links are left alone", frame.received[2] == "|Hitem:6948|h[https://in.an/item]|h")
	frame:AddMessage(SECRET)
	check("secret lines pass untouched", frame.received[3] == SECRET)
	state.linkHandlers.ksuiurl("ksuiurl:https://a.b/c")
	check("clicking opens the copy box", state.popups[1][1] == "KSUI_COPY_URL" and state.popups[1][2] == "https://a.b/c")
	fire(env, "CHAT_MSG_WHISPER")
	check("a whisper plays a sound", state.sounds[1] == 3081)
	state.settings.shortChannels:SetValue(false)
	frame:AddMessage("|Hchannel:channel:2|h[2. 거래]|h")
	check("channels kept when off", frame.received[4] == "|Hchannel:channel:2|h[2. 거래]|h")
end

-- Conveniences
do
	local state = { units = { player = mage, mouseover = { player = true, class = "MAGE" }, mouseovertarget = { name = "Bob" } },
		lootCount = 3, rested = 300, visiblePopup = "PARTY_INVITE", popupDialog = {} }
	local env, ns = boot(state)
	fire(env, "LOOT_READY", true)
	check("auto loot takes every slot at once", #state.looted == 3)
	fire(env, "LOOT_READY", false)
	check("not when auto loot is off", #state.looted == 3)

	state.tooltipUnit = "mouseover"
	state.tooltipPostCalls[2](env.GameTooltip)
	check("a player's name in class color", env.GameTooltipTextLeft1.textColor[1] == 0.2)
	check("and whom they target", env.GameTooltip.lines[1][1] == "대상: Bob")
	-- Blizzard's GetUnit tests a unit token that can be secret, which raises when run from addon code.
	local getUnit = env.GameTooltip.GetUnit
	env.GameTooltip.GetUnit = function() error("attempt to perform boolean test on a secret value") end
	local lines = #env.GameTooltip.lines
	state.tooltipPostCalls[2](env.GameTooltip)
	check("a tooltip whose unit can't be read is left as it is", #env.GameTooltip.lines == lines)
	env.GameTooltip.GetUnit = function() return nil, SECRET end
	state.tooltipPostCalls[2](env.GameTooltip)
	check("a secret tooltip unit is not tested", #env.GameTooltip.lines == lines)
	env.GameTooltip.GetUnit = getUnit

	-- name, isTank, isHealer, isDamage, isNativeRealm, isCrossShard, allowMultipleRoles, inviterGUID
	fire(env, "PARTY_INVITE_REQUEST", "Guy", false, false, false, true, false, false, "stranger")
	fire(env, "PARTY_INVITE_REQUEST", "Guy", false, false, false, true, false, "guildie", "stranger")
	check("strangers' invites stay yours", not state.acceptedGroup)
	fire(env, "PARTY_INVITE_REQUEST", "Guy", false, false, false, true, false, false, "guildie")
	check("a guild member's invite is accepted, and the dialog won't decline it",
		state.acceptedGroup and state.popupDialog.inviteAccepted == 1 and state.hiddenPopup == "PARTY_INVITE")

	local holder
	for _, f in ipairs(state.frames) do
		if f.parent == env.MainStatusTrackingBarContainer and f.scripts.OnUpdate then holder = f end
	end
	state.blizzardXPText.visible = true
	holder.scripts.OnUpdate(holder, 1)
	check("KSUI's experience text steps aside while Blizzard's shows", holder.alpha == 0)
	state.blizzardXPText.visible = false
	holder.scripts.OnUpdate(holder, 1)
	check("and comes back after", holder.alpha == 1)
	fire(env, "QUEST_TURNED_IN", 1, 150)
	fire(env, "QUEST_TURNED_IN", 2, 50)
	check("quests remembered for the estimate", #ns.db.questXP == 2)

	env.MovieFrame:PlayMovie(5)
	check("a new movie plays", #env.MovieFrame.finished == 0 and ns.db.seenMovies[5])
	env.MovieFrame:PlayMovie(5)
	check("a seen one is skipped", env.MovieFrame.finished[1] == true)
	fire(env, "CINEMATIC_START", true)
	fire(env, "CINEMATIC_START", true)
	for _, timer in ipairs(state.timers) do timer() end
	check("a seen cutscene is cancelled", state.cutsceneCancelled == 1)
end

-- Nameplates
local function plate()
	local bar = { barTexture = texture(), bgTexture = texture(), selectedBorder = texture() }
	bar.selectedBorder.shown = false
	function bar.selectedBorder:IsShown() return self.shown end
	-- Blizzard shows its rounded border on the target, as in Blizzard_NamePlateHealthBar.lua.
	function bar:UpdateSelectionBorder() self.selectedBorder:SetShown(self.isTarget) end
	function bar:CreateFontString() return texture() end
	function bar:CreateTexture() local t = texture(); function t:SetSize(w, h) self.size = { w, h } end; return t end
	local unitFrame = { unit = "nameplate1", HealthBarsContainer = { healthBar = bar }, PlayerLevelDiffFrame = texture() }
	-- Blizzard's classic style puts its border art back on every call.
	function unitFrame:UpdateAnchors()
		bar.barTexture:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
		bar.bgTexture:SetTexture("Interface\\Tooltips\\Nameplate-Border")
		self.PlayerLevelDiffFrame:SetAlpha(1)
	end
	return { UnitFrame = unitFrame }
end

do
	local state = { units = { player = mage, nameplate1 = { level = 23 } }, plates = { nameplate1 = plate() } }
	local env = boot(state)
	check("nameplate hook waits for Blizzard_NamePlates", state.addonLoaders.Blizzard_NamePlates ~= nil)
	state.addonLoaders.Blizzard_NamePlates()
	env.NamePlateDriverFrame:OnNamePlateAdded("nameplate1")
	local unitFrame = state.plates.nameplate1.UnitFrame
	local bar = unitFrame.HealthBarsContainer.healthBar
	check("nameplate bar flat", bar.barTexture.file == "Interface\\ChatFrame\\ChatFrameBackground")
	check("nameplate border is a thin black box", bar.bgTexture.file == "Interface\\ChatFrame\\ChatFrameBackground"
		and bar.bgTexture.color[1] == 0 and bar.bgTexture.points == 2 and bar.bgTexture.point[4] == 1)
	check("nameplate level box hidden", unitFrame.PlayerLevelDiffFrame.alpha == 0)
	check("level written at the bar's end in its difficulty color", unitFrame.ksuiLevel.text == 23
		and unitFrame.ksuiLevel.point[1] == "RIGHT" and unitFrame.ksuiLevel.textColor[1] == 0.5 and unitFrame.ksuiLevel.shown)
	state.units.nameplate1.level = -1
	unitFrame:UpdateAnchors()
	check("boss gets the skull instead of a number", unitFrame.ksuiSkull.shown == true and unitFrame.ksuiLevel.shown == false
		and unitFrame.ksuiSkull.atlas == "ui-hud-nameplates-levelindicator-skull")
	state.units.nameplate1.level = SECRET
	unitFrame:UpdateAnchors()
	check("secret level shown as is, in white", unitFrame.ksuiLevel.text == SECRET and unitFrame.ksuiLevel.textColor[1] == 1
		and unitFrame.ksuiLevel.shown == true and unitFrame.ksuiSkull.shown == false)
	unitFrame:UpdateAnchors()
	bar.isTarget = true
	bar:UpdateSelectionBorder()
	check("the target gets a white thin border, not Blizzard's rounded one", bar.bgTexture.color[1] == 1
		and bar.selectedBorder.alpha == 0)
	bar.isTarget = false
	bar:UpdateSelectionBorder()
	check("back to black when no longer the target", bar.bgTexture.color[1] == 0)
	-- In instances Blizzard's UnitIsUnit(plate, "target") can be secret, and so the border's shown state.
	bar.isTarget = SECRET
	bar:UpdateSelectionBorder()
	check("a secret target state goes to the color setter untested", bar.bgTexture.colorFrom[1] == SECRET)
	bar.isTarget = false
	bar:UpdateSelectionBorder()
	check("inside the edge the bar stays black", bar.ksuiBackground.fill[1] == 0 and bar.ksuiBackground.shown ~= false)
	unitFrame.unit = nil
	unitFrame:UpdateAnchors()
	check("a plate restyled before it has a unit shows no level", unitFrame.ksuiLevel.shown == false
		and unitFrame.ksuiSkull.shown == false)
	unitFrame.unit = "nameplate1"
	check("Blizzard restyle is overridden", bar.bgTexture.file == "Interface\\ChatFrame\\ChatFrameBackground"
		and unitFrame.PlayerLevelDiffFrame.alpha == 0)
	env.NamePlateDriverFrame:OnNamePlateAdded("nameplate2")
	check("forbidden plate skipped", true)
	state.settings.flatNameplates:SetValue(false)
	unitFrame:UpdateAnchors()
	check("Blizzard look returns when off", bar.bgTexture.file == "Interface\\Tooltips\\Nameplate-Border"
		and unitFrame.PlayerLevelDiffFrame.alpha == 1 and unitFrame.ksuiLevel.shown == false and unitFrame.ksuiSkull.shown == false
		and bar.selectedBorder.alpha == 1 and bar.bgTexture.color[1] == 1 and bar.ksuiBackground.shown == false)
end

-- Screen-relative positions and sizes
do
	-- Saved UI units from before become shares of the reference screen, so on it the frames land exactly where they were.
	-- UIParent may not have its real size yet at this point; the mock's 768-tall screen stands for that.
	local state = layoutState({ screen = { 2133.333, 1200 }, savedDB = { frameX = 130, frameY = 220, groupX = 20, groupTopGap = 20 } })
	local env = boot(state)
	local db = env.KSUIDB
	check("all four old positions converted", db.frameX == nil and db.frameY == nil and db.groupX == nil and db.groupTopGap == nil
		and near(db.frameYPct, 220 / 1200 * 100) and near(db.groupTopPct, 20 / 1200 * 100))
	state.button.buttonClick()
	local player, party = state.saved.layouts[4].systems[1], state.saved.layouts[4].systems[5]
	check("converted positions land where they were", near(player.anchorInfo.offsetX, -130) and near(player.anchorInfo.offsetY, 220)
		and near(party.anchorInfo.offsetX, 20) and near(party.anchorInfo.offsetY, -20 - 63 * 1.15))
	check("reference screen keeps 100%", player.settings[1].value == 0)
end

do
	-- A screen half again as tall in UI units shows everything two thirds the size, so the frames grow to 150%.
	local state = layoutState({ screen = { 3200, 1800 } })
	boot(state)
	state.button.buttonClick()
	local systems = state.saved.layouts[4].systems
	local player, target, focus = systems[1], systems[2], systems[3]
	local buffs = systems[13]
	check("player and target grow to 150%", player.settings[1].value == 10 and target.settings[1].value == 10)
	check("gaps above the frames grow too", near(focus.anchorInfo.offsetY, 22 / 100 * 1800 + 110 * 1.5)
		and near(systems[14].anchorInfo.offsetY, 100 * 1.5))
	check("positions follow the screen", near(player.anchorInfo.offsetX, -6.5 / 100 * 3200))
end

do
	local state = layoutState({ screen = { 6000, 3438 } })
	boot(state)
	state.button.buttonClick()
	check("frame size capped at 200%", state.saved.layouts[4].systems[1].settings[1].value == 20)
end

do
	-- Version 1 measured a 1365 x 768 UIParent while loading; its shares are scaled back once and then left alone.
	local state = layoutState({ screen = { 2133.333, 1200 },
		savedDB = { frameXPct = 130 / 1365.333 * 100, frameYPct = 220 / 768 * 100, groupXPct = 20 / 1365.333 * 100,
			groupTopPct = 20 / 768 * 100 } })
	local env = boot(state)
	state.button.buttonClick()
	local player, party = state.saved.layouts[4].systems[1], state.saved.layouts[4].systems[5]
	check("version 1 shares repaired", near(player.anchorInfo.offsetX, -130) and near(player.anchorInfo.offsetY, 220)
		and near(party.anchorInfo.offsetX, 20) and near(party.anchorInfo.offsetY, -20 - 63 * 1.15) and env.KSUIDB.positionsVersion == 2)
	local frameY = env.KSUIDB.frameYPct
	local again = layoutState({ savedDB = env.KSUIDB })
	boot(again)
	check("repair runs once", again.savedDB.frameYPct == frameY)
end

do
	local state = { units = { player = mage } }
	local env = boot(state)
	check("fresh install keeps the defaults", env.KSUIDB.frameYPct == 18.3 and env.KSUIDB.positionsVersion == 2)
end

do
	local past = {}
	for i = 1, 30 do past[i] = { sessionID = i, name = "몹" .. i } end
	local state = { units = { player = mage }, meter = { available = true, past = past,
		session = { combatSources = {}, maxAmount = 0 } } }
	boot(state)
	local button
	for _, f in ipairs(state.frames) do
		if f.kind == "Button" and f.scripts.OnClick and f.parent and f.parent.rows and #f.parent.rows == 8 then button = f end
	end
	button.scripts.OnClick(button, "RightButton")
	check("menu keeps the latest 15 fights", #state.menu.radios == 17 and state.menu.radios[1].text == "몹30"
		and state.menu.radios[15].text == "몹16")
end

-- Damage meter
local function meterFrame(state)
	for _, f in ipairs(state.frames) do
		if f.rows then return f end
	end
end

do
	local mageSource = { classFilename = "MAGE", name = "Me", totalAmount = 900, amountPerSecond = 30 }
	local wolf = { classFilename = "", name = "Wolf", totalAmount = 300, amountPerSecond = 10 }
	local state = { units = { player = mage },
		meter = { available = true, session = { combatSources = { mageSource, wolf }, maxAmount = 900 } } }
	local env = boot(state)
	local meter = meterFrame(state)
	check("meter as wide as the tracker, above it", meter.points.BOTTOMLEFT[2] == env.ObjectiveTrackerFrame
		and meter.points.BOTTOMLEFT[3] == "TOPLEFT" and meter.points.BOTTOMRIGHT[3] == "TOPRIGHT"
		and meter.points.BOTTOMRIGHT[5] == 10 and meter.width == nil and meter.shown ~= false)
	check("damage done, current fight by default", state.meter.asked[1] == 1 and state.meter.asked[2] == 0
		and meter.title.format[2] == "피해량" and meter.title.format[3] == "현재")
	local first, second = meter.rows[1], meter.rows[2]
	check("rows in Blizzard's order", first.name.format[3] == "Me" and second.name.format[3] == "Wolf" and first.name.format[2] == 1)
	check("row bar and numbers", first.range[2] == 900 and first.barValue == 900 and first.value.format[2] == "900"
		and first.value.format[1] == "%s (%.1f)" and first.value.format[3] == 30)
	check("class color, creature gray", first.color[1] == 0.2 and second.color[1] == 0.6)
	check("unused rows hidden and window fits", meter.rows[3].shown == false and meter.height == 18 + 2 * 16 + 1)
	check("Blizzard's data source switched on", state.cvars.damageMeterEnabled == "1")
	state.cvars.damageMeterEnabled = nil
	state.settings.damageMeter:SetValue(false)
	state.settings.damageMeter:SetValue(true)
	check("switching the meter on switches the data source on", state.cvars.damageMeterEnabled == "1")

	local button, reset
	for _, f in ipairs(state.frames) do
		if f.kind == "Button" and f.parent == meter then button = f end
	end
	for _, f in ipairs(state.frames) do
		if f.kind == "Button" and f.parent == button then reset = f end
	end
	check("reset button on the title's right", reset and reset.point[1] == "BOTTOMRIGHT" and reset.label.text == "초기화")
	button.scripts.OnClick(button, "LeftButton")
	check("left-click cycles to healing", state.meter.asked[2] == 2 and meter.title.format[2] == "치유량")
	state.meter.past = { { sessionID = 7, name = "나이트래쉬", durationSeconds = 75 }, { sessionID = 8, name = "" } }
	fire(env, "DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 7)
	button.scripts.OnClick(button, "RightButton")
	local radios = state.menu.radios
	check("menu titled, newest fight first, then current and all", state.menu.title == "전투 선택"
		and radios[1].text == "전투 8" and radios[2].text == "11-15 20:09:00 나이트래쉬 [1:15]"
		and radios[3].text == "현재" and radios[4].text == "전체" and radios[3].isSelected(radios[3].data))
	radios[2].choose(radios[2].data)
	check("past fight read by id", state.meter.asked[1] == "id" and state.meter.asked[2] == 7
		and meter.title.format[3] == "11-15 20:09:00 나이트래쉬 [1:15]")
	fire(env, "PLAYER_REGEN_DISABLED")
	check("a new fight brings the meter back to the current one", meter.title.format[3] == "현재")
	radios[2].choose(radios[2].data)
	local kept = state.meter.past
	state.meter.past = {}
	fire(env, "DAMAGE_METER_CURRENT_SESSION_UPDATED")
	check("a dropped past fight falls back to the current one", meter.title.format[3] == "현재")
	state.meter.past = kept
	button.scripts.OnClick(button, "RightButton")
	state.menu.radios[2].choose(state.menu.radios[2].data)
	button.scripts.OnClick(button, "RightButton")
	state.menu.radios[4].choose(state.menu.radios[4].data)
	check("right-click menu switches to all fights", state.meter.asked[1] == 0 and meter.title.format[3] == "전체")
	-- Spell detail for the first row.
	state.meter.spells = { totalAmount = 900, maxAmount = 600, combatSpells = {
		{ spellID = 20271, totalAmount = 600, amountPerSecond = 20 }, { spellID = 853, totalAmount = 300, amountPerSecond = 10 } } }
	first.source.guid = "Player-1"
	first.scripts.OnMouseUp(first, "LeftButton")
	local detail
	for _, f in ipairs(state.frames) do
		if f.rows and #f.rows == 10 then detail = f end
	end
	check("row click opens the spell detail", detail.shown == true and state.meter.sourceAsked[3] == "Player-1"
		and detail.title.format[2] == "Me")
	local spell = detail.rows[1]
	check("spell rows with icon, name and share", spell.icon.file == "tex20271" and spell.name.text == "심판"
		and spell.value.format[1] == "%s (%.1f) %.0f%%" and spell.value.format[4] == 600 / 900 * 100
		and detail.rows[3].shown == false)
	first.scripts.OnMouseUp(first, "LeftButton")
	check("second click closes the detail", detail.shown == false)
	first.source.guid = SECRET
	first.scripts.OnMouseUp(first, "LeftButton")
	check("secret unit asks to wait for combat to end", detail.shown == false and state.printed:find("전투가 끝나면", 1, true) ~= nil)
	first.source.guid = "Player-1"

	reset.scripts.OnClick(reset)
	check("reset button clears the meter", state.meter.reset == true and meter.title.format[3] == "현재")
	state.meter.reset = nil
	env.SlashCmdList.KSUI("reset")
	check("/ksui reset clears the meter", state.meter.reset == true)

	-- In combat the session can be locked, or its values secret.
	state.meter.session = "LOCKED"
	fire(env, "DAMAGE_METER_CURRENT_SESSION_UPDATED")
	check("locked session keeps the last picture", first.name.format[3] == "Me")
	state.meter.session = { combatSources = { { classFilename = "MAGE", name = SECRET, totalAmount = SECRET,
		amountPerSecond = SECRET } }, maxAmount = SECRET }
	fire(env, "DAMAGE_METER_COMBAT_SESSION_UPDATED")
	check("secret values reach only secret-safe setters", first.barValue == SECRET and first.range[2] == SECRET
		and first.name.format[3] == SECRET and first.value.format[2] == SECRET and second.shown == false)

	state.settings.damageMeter:SetValue(false)
	check("meter off", meter.shown == false)
end

do
	local state = { units = { player = mage }, meter = { available = false, session = { combatSources = {}, maxAmount = 0 } } }
	boot(state)
	check("meter hidden when Blizzard's is unavailable", meterFrame(state).shown == false)
end

-- Threat meter
local function threatFrame(state)
	for _, f in ipairs(state.frames) do
		if f.rows and #f.rows == 5 then return f end
	end
end

do
	local state = { units = { player = mage, party1 = { player = true, class = "MAGE", name = "Tank" },
		target = { player = false, hostile = true } }, group = true,
		threat = { player = { false, 40 }, party1 = { true, 100 } } }
	local env = boot(state)
	local threat = threatFrame(state)
	check("threat meter as wide as the damage meter, above it", threat.points.BOTTOMLEFT[2] == env.KSUIDamageMeter
		and threat.points.BOTTOMRIGHT[3] == "TOPRIGHT" and threat.width == nil)
	check("threat shown in a group on a hostile target", threat.shown == true)
	local first, second = threat.rows[1], threat.rows[2]
	check("threat sorted high to low", first.name.text == "Tank" and first.barValue == 100 and second.barValue == 40
		and first.value.format[2] == 100)
	state.units.party1.surname = "방패"
	fire(env, "UNIT_THREAT_LIST_UPDATE")
	check("threat names carry the surname", first.name.format[2] == "Tank" and first.name.format[4] == "방패")
	state.units.party1.surname = nil
	check("tank marked", first.tanking.alpha == 1 and second.tanking.alpha == 0)
	check("rows without threat hidden", threat.rows[3].shown == false and threat.height == 18 + 2 * 16 + 1)

	state.threat = { player = { SECRET, SECRET }, party1 = { SECRET, SECRET } }
	fire(env, "UNIT_THREAT_LIST_UPDATE")
	check("secret threat keeps party order", first.name.text == "Name" and first.barValue == SECRET
		and first.value.format[2] == SECRET)
	check("secret tanking flag via boolean setter", first.tanking.alphaFrom[1] == SECRET)

	state.group = false
	fire(env, "GROUP_ROSTER_UPDATE")
	check("threat hidden when alone", threat.shown == false)
	state.group = true
	state.units.target.hostile = false
	fire(env, "PLAYER_TARGET_CHANGED")
	check("threat hidden on a friendly target", threat.shown == false)
	state.units.target.hostile = true
	fire(env, "PLAYER_TARGET_CHANGED")
	local tooltip = { ClearAllPoints = function(self) self.point = nil end, SetPoint = function(self, ...) self.point = { ... } end }
	env.GameTooltip_SetDefaultAnchor(tooltip, env.UIParent)
	check("tooltip above the threat meter while it shows", tooltip.point[2] == threat and tooltip.point[3] == "TOPRIGHT"
		and tooltip.point[5] == 10)
	state.settings.threatMeter:SetValue(false)
	check("threat meter off", threat.shown == false)
	env.GameTooltip_SetDefaultAnchor(tooltip, env.UIParent)
	check("tooltip above the damage meter otherwise", tooltip.point[2] == env.KSUIDamageMeter)
	state.meterShown = false
	tooltip.point = { "Blizzard" }
	env.GameTooltip_SetDefaultAnchor(tooltip, env.UIParent)
	check("tooltip left alone with no meter", tooltip.point[1] == "Blizzard")
end

print(string.format("%d checks, %d failures", count, failures))
os.exit(failures == 0 and 0 or 1)
