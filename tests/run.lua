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
	function t:SetTexture(v) self.file = v end
	function t:SetColorTexture(r, g, b) self.fill = { r, g, b } end
	function t:SetAlpha(a) self.alpha = a end
	function t:SetAlphaFromBoolean(v, yes, no) self.alphaFrom = { v, yes, no } end
	function t:SetPoint(...) self.point = { ... } end
	function t:SetAllPoints() end
	function t:SetSize() end
	function t:SetVertexColorFromBoolean(v, yes, no) self.colorFrom = { v, yes, no } end
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
		if init.buttonClick then state.button = init else state.headers[#state.headers + 1] = init.name end
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
		CreateSliderOptions = function(min, max, step)
			return { min = min, max = max, step = step, SetLabelFormatter = function(self, f) self.formatter = f end }
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
	local env = { ipairs = ipairs, pairs = pairs, type = type, setmetatable = setmetatable, error = error, table = table, math = math, string = string }
	env._G = env
	local handlers = {}
	env.events = handlers

	function env.CreateFrame(kind, _, parent, template)
		local f = { registered = {}, scripts = {}, kind = kind, parent = parent, template = template }
		state.frames = state.frames or {}
		state.frames[#state.frames + 1] = f
		function f:RegisterEvent(e) self.registered[e] = true end
		function f:RegisterUnitEvent(e, unit)
			assert(unit == "target")
			self.registered[e] = true
		end
		function f:SetScript(name, fn)
			self.scripts[name] = fn
			if name == "OnEvent" then handlers[#handlers + 1] = { frame = f, fn = fn } end
		end
		function f:SetSize(w, h) self.size = { w, h } end
		function f:SetPoint(...) self.point = { ... } end
		function f:SetText(t) self.text = t end
		function f:SetAllPoints() end
		function f:SetShown(v) self.shown = v end
		function f:CreateTexture() return texture() end
		function f:SetCooldownFromDurationObject(d) self.duration = d end
		function f:CreateFontString() local t = texture(); function t:SetText(v) self.text = v end; return t end
		function f:Show() self.shown = true end
		function f:Hide() self.shown = false end
		function f:SetStatusBarTexture() self.fill = texture() end
		function f:GetStatusBarTexture() return self.fill end
		function f:SetMinMaxValues(a, b) self.range = { a, b } end
		function f:SetValue(v) self.value = v end
		function f:SetBackdrop(b) self.backdrop = b end
		function f:SetBackdropBorderColor(r, g, b, a) self.borderColor = { r, g, b, a } end
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
	function env.GetCVarBool(name) assert(name == "rotateMinimap"); return state.rotate end
	function env.issecretvalue(v) return v == SECRET end
	function env.canaccesstable(t) assert(t ~= SECRET, "secret passed to canaccesstable"); return not t.locked end
	function env.UnitExists(u) return state.units[u] ~= nil end
	function env.UnitIsPlayer(u) return state.units[u].player end
	function env.UnitClass(u) return "Localized", state.units[u] and state.units[u].class end
	function env.UnitAffectingCombat() return state.combat end
	function env.UnitPowerType() return state.powerType or 0 end
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
		[853] = "심판의 망치", [5588] = "심판의 망치", [20271] = "심판" }
	env.C_Spell = { GetSpellName = function(id) return SPELLS[id] end }
	env.C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter)
		assert(unit == "player" and filter == "HELPFUL")
		local name = (state.auras or {})[i]
		if name == "SECRET_RESULT" then return SECRET end
		if name == "LOCKED" then return { name = "x", locked = true } end
		return name and { name = name } or nil
	end }
	state.sold, state.repaired = 0, 0
	env.C_MerchantFrame = {
		IsSellAllJunkEnabled = function() return true end,
		GetNumJunkItems = function() return state.junk or 0 end,
		SellAllJunkItems = function() state.sold = state.sold + 1 end,
	}
	function env.CanMerchantRepair() return state.canRepair end
	function env.GetRepairAllCost() return state.repairCost or 0, true end
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
	env.SlashCmdList = {}
	env.Enum = {
		EditModeSystem = { ActionBar = 0, CastBar = 1, Minimap = 2, UnitFrame = 3, AuraFrame = 6, ChatFrame = 8, HudTooltip = 11,
			ObjectiveTracker = 12, MicroMenu = 13, Bags = 14, StatusTrackingBar = 15, DurabilityFrame = 16, CooldownViewer = 20,
			MainActionBarEndCap = 26 },
		EditModeCooldownViewerSystemIndices = { Essential = 1, Utility = 2, BuffIcon = 3, BuffBar = 4 },
		EditModeActionBarSystemIndices = { MainBar = 1, Bar2 = 2, Bar3 = 3, RightBar1 = 4, RightBar2 = 5, StanceBar = 11, PetActionBar = 12 },
		EditModeActionBarSetting = { Orientation = 0, NumRows = 1, NumIcons = 2, IconSize = 3, AlwaysShowButtons = 9 },
		EditModeMainActionBarEndCapSetting = { Hidden = 0 },
		EditModeMainActionBarEndCapSystemIndices = { EndCapLeft = 1, EndCapRight = 2 },
		ActionBarOrientation = { Horizontal = 0, Vertical = 1 },
		EditModeCastBarSetting = { BarSize = 0, LockToPlayerFrame = 1 },
		EditModeAuraFrameSystemIndices = { BuffFrame = 1, DebuffFrame = 2 },
		EditModeObjectiveTrackerSetting = { Height = 0, Opacity = 1 },
		EditModeUnitFrameSystemIndices = { Player = 1, Target = 2, Focus = 3, Party = 4, Raid = 5, Boss = 6 },
		EditModeLayoutType = { Preset = 0, Account = 1, Character = 2 },
		EditModeUnitFrameSetting = { ViewRaidSize = 9, FrameWidth = 10, FrameHeight = 11, RaidGroupDisplayType = 13, RowSize = 15 },
		RaidGroupDisplayType = { SeparateGroupsVertical = 0, CombineGroupsHorizontal = 3 },
		PowerType = { Mana = 0, Rage = 1 },
		ViewRaidSize = { Ten = 0, Forty = 2 },
	}
	env.Constants = { EditModeConsts = { EditModeMaxLayoutsPerType = 2 } }
	env.EditModePresetLayoutManager = {
		GetCopyOfPresetLayouts = function() return copy(state.presets) end,
	}
	env.C_EditMode = {
		GetLayouts = function() return { activeLayout = state.active, layouts = copy(state.layouts) } end,
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

	env.PlayerFrame = {
		PlayerFrameContainer = {
			FrameTexture = texture(), VehicleFrameTexture = texture(), AlternatePowerFrameTexture = texture(),
		},
		PlayerFrameContent = { PlayerFrameContentMain = { HealthBarsContainer = { HealthBar = bar() } } },
	}
	local spellbar = { alpha = 1 }
	function spellbar:ApplyAlpha(a) self:SetAlpha(a) end
	spellbar.HoldFadeOutAnim = { Stop = function(self) self.stopped = true end }
	function spellbar:PlayInterruptAnims() self.HoldFadeOutAnim.stopped = false; self:SetAlpha(1) end
	function spellbar:SetAlpha(a) self.alpha = a end
	function env.CreateColor(r, g, b) return { r = r, g = g, b = b } end
	function env.GetTime() return 100 end
	env.TargetFrame = {
		spellbar = spellbar,
		TargetFrameContainer = { FrameTexture = texture() },
		TargetFrameContent = { TargetFrameContentMain = { HealthBarsContainer = { HealthBar = bar() } } },
	}
	local function alphaFrame(f)
		f = f or {}
		function f:SetAlpha(a) self.alpha = a end
		return f
	end
	env.MainActionBar = alphaFrame({
		EndCaps = { LeftEndCap = { Texture = texture() }, RightEndCap = { Texture = texture() } },
	})
	-- StanceBar and PetActionBar are left out on purpose: a missing bar must be skipped.
	for _, name in ipairs({ "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft", "MultiBar7" }) do
		env[name] = alphaFrame()
	end
	env.FocusFrame = { TargetFrameContainer = { FrameTexture = texture() } }
	env.MAX_BOSS_FRAMES = 5
	for i = 1, env.MAX_BOSS_FRAMES do
		env["Boss" .. i .. "TargetFrame"] = { TargetFrameContainer = { FrameTexture = texture() } }
	end
	local partyMembers = state.noParty and {} or { { Texture = texture() }, { Texture = texture() } }
	env.partyMembers = partyMembers
	env.newPartyTexture = texture
	env.PartyFrame = { InitializePartyMemberFrames = function() end, PartyMemberFramePool = {
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

local function fire(env, event)
	for _, h in ipairs(env.events) do
		if h.frame.registered[event] then h.fn(h.frame, event) end
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
	check("defaults saved", env.KSUIDB.darkUnitFrames == true and env.KSUIDB.frameY == 220)
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
	check("slider range", state.controls.KSUI_frameX.options.max == 500 and state.controls.KSUI_frameX.options.formatter == 1)
	check("sections", #state.headers == 6)
	check("button present", state.button and state.button.buttonClick == ns.ApplyLayout)

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
	check("saved value not overwritten", env.KSUIDB.frameX == 50)
	check("missing value defaulted", env.KSUIDB.frameY == 220)
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
	env.partyMembers[1] = { Texture = env.newPartyTexture() }
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
		{ system = 3, systemIndex = 1, anchorInfo = { point = "TOPLEFT", offsetX = playerX }, isInDefaultPosition = true },
		{ system = 3, systemIndex = 2, anchorInfo = { point = "TOPLEFT", offsetX = 250 }, isInDefaultPosition = true },
		{ system = 3, systemIndex = 3, anchorInfo = { point = "CENTER", offsetX = 7 }, isInDefaultPosition = true },
		{ system = 0, systemIndex = 1, anchorInfo = { point = "BOTTOM", offsetX = 1 }, isInDefaultPosition = false },
		{ system = 3, systemIndex = 4, anchorInfo = { point = "TOPLEFT", offsetX = 0 }, isInDefaultPosition = true },
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
		{ system = 2, anchorInfo = { point = "TOPRIGHT" }, isInDefaultPosition = true },
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
		{ system = 13, anchorInfo = { point = "BOTTOM", offsetX = 116.5 }, isInDefaultPosition = true },
		{ system = 14, anchorInfo = { point = "BOTTOMLEFT", relativeTo = "MicroMenuContainer" }, isInDefaultPosition = true },
		{ system = 15, systemIndex = 1, anchorInfo = { point = "BOTTOM" }, isInDefaultPosition = true },
		{ system = 15, systemIndex = 2, anchorInfo = { point = "BOTTOM", offsetY = 17 }, isInDefaultPosition = true },
		{ system = 8, anchorInfo = { point = "BOTTOMLEFT", offsetX = 35, offsetY = 145 }, isInDefaultPosition = true },
		{ system = 20, systemIndex = 1, anchorInfo = { point = "BOTTOM", offsetY = 310 }, isInDefaultPosition = true },
		{ system = 20, systemIndex = 2, anchorInfo = { point = "BOTTOM", offsetY = 240 }, isInDefaultPosition = true },
		{ system = 20, systemIndex = 3, anchorInfo = { point = "BOTTOM", offsetY = 370 }, isInDefaultPosition = true },
		{ system = 20, systemIndex = 4, anchorInfo = { point = "BOTTOM", offsetX = 420, offsetY = 430 }, isInDefaultPosition = true },		{ system = 26, systemIndex = 1, anchorInfo = { point = "RIGHT", relativeTo = "MainActionBar" }, isInDefaultPosition = true,
			settings = { { setting = 0, value = 0 } } },
		{ system = 26, systemIndex = 2, anchorInfo = { point = "LEFT", relativeTo = "MainActionBar" }, isInDefaultPosition = true,
			settings = { { setting = 0, value = 0 } } },
		{ system = 16, anchorInfo = { point = "RIGHT" }, isInDefaultPosition = true },
	}
end

local function layoutState(extra)
	local state = {
		units = { player = mage }, active = 2, layouts = {},
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
		and party.anchorInfo.offsetX == 20 and party.anchorInfo.offsetY == -20 and not party.isInDefaultPosition)
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
	check("stance bar above the new row", above(stance, "MultiBarRight"))
	check("pet bar above the new row", above(pet, "MultiBarLeft"))
	local durability = layout.systems[#layout.systems]
	check("durability figure on the right end of the bar row", durability.system == 16
		and durability.anchorInfo.point == "BOTTOMRIGHT" and durability.anchorInfo.relativeTo == "MultiBarLeft"
		and durability.anchorInfo.relativePoint == "TOPRIGHT" and durability.anchorInfo.offsetY == 4 and not durability.isInDefaultPosition)
	local cast = layout.systems[12]
	check("cast bar on top of the minimap", cast.anchorInfo.point == "BOTTOM" and cast.anchorInfo.relativeTo == "MinimapCluster"
		and cast.anchorInfo.relativePoint == "TOP" and cast.anchorInfo.offsetX == 0 and cast.anchorInfo.offsetY == 6 and not cast.isInDefaultPosition)
	check("cast bar unlocked from player frame", values(cast)[1] == 0 and values(cast)[0] == 3)
	local buffs, debuffs = layout.systems[13], layout.systems[14]
	check("buffs above the player frame", buffs.anchorInfo.point == "TOPRIGHT" and buffs.anchorInfo.relativePoint == "BOTTOM"
		and buffs.anchorInfo.offsetX == -130 and buffs.anchorInfo.offsetY == 420 and not buffs.isInDefaultPosition)
	check("debuffs above the buffs", debuffs.anchorInfo.point == "TOPRIGHT" and debuffs.anchorInfo.offsetX == -130
		and debuffs.anchorInfo.offsetY == 520 and not debuffs.isInDefaultPosition)
	local minimap, tracker, tooltip = layout.systems[15], layout.systems[16], layout.systems[17]
	check("minimap sits on the experience bars", minimap.anchorInfo.point == "BOTTOM"
		and minimap.anchorInfo.relativeTo == "SecondaryStatusTrackingBarContainer" and minimap.anchorInfo.relativePoint == "TOP"
		and minimap.anchorInfo.offsetX == 0 and minimap.anchorInfo.offsetY == 4 and not minimap.isInDefaultPosition)
	local s = layout.systems
	local mainBar, bar2, bar3, micro, bags, xp1, xp2, chat = s[4], s[18], s[19], s[20], s[21], s[22], s[23], s[24]
	check("main bar left of the minimap", mainBar.anchorInfo.point == "BOTTOMRIGHT" and mainBar.anchorInfo.relativeTo == "MinimapCluster"
		and mainBar.anchorInfo.relativePoint == "BOTTOMLEFT" and mainBar.anchorInfo.offsetX == -8 and mainBar.anchorInfo.offsetY == 0
		and not mainBar.isInDefaultPosition)
	check("micro menu right of the minimap", micro.anchorInfo.point == "BOTTOMLEFT" and micro.anchorInfo.relativeTo == "MinimapCluster"
		and micro.anchorInfo.relativePoint == "BOTTOMRIGHT" and micro.anchorInfo.offsetX == 8 and not micro.isInDefaultPosition)
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
	check("tooltip above the tracker", tooltip.anchorInfo.point == "BOTTOMRIGHT" and tooltip.anchorInfo.relativeTo == "ObjectiveTrackerFrame"
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
	state.settings.frameX:SetValue(200)
	state.settings.frameY:SetValue(300)
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
	check("dispellable only on", state.cvars.raidFramesDisplayOnlyDispellableDebuffs == "1")
	check("threat numbers on", state.cvars.threatShowNumeric == "1")
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
	state.settings.sellJunk:SetValue(false)
	state.settings.autoRepair:SetValue(false)
	state.canRepair = true
	fire(env, "MERCHANT_SHOW")
	check("toggles off", state.sold == 2 and state.repaired == 1)
end

-- Ready check
do
	local units = { player = { player = true, class = "PALADIN" } }
	units.raid1 = units.player
	units.raid2 = { player = true, class = "MAGE" }
	units.raid3 = { player = true, class = "PRIEST" }
	units.raid4 = { player = true, class = SECRET }
	local state = { units = units, raid = true, groupSize = 4, auras = { "인내의 기원", "축복" } }
	local env = boot(state)
	state.printed = nil
	fire(env, "READY_CHECK")
	check("missing mage buff reported", state.printed ~= nil and state.printed:find("신비한 지능", 1, true) ~= nil)
	check("group version counts as the buff", not state.printed:find("인내", 1, true))
	check("class not in raid not asked for", not state.printed:find("야생", 1, true))
	state.auras = { "신비한 총명함", "신의 권능: 인내" }
	state.printed = nil
	fire(env, "READY_CHECK")
	check("all buffs present stays quiet", state.printed == nil)
	state.auras = {}
	state.powerType = 1
	fire(env, "READY_CHECK")
	check("intellect skipped without mana", state.printed ~= nil and not state.printed:find("지능", 1, true)
		and state.printed:find("인내", 1, true) ~= nil)
	state.auras = { SECRET }
	fire(env, "READY_CHECK")
	check("secret auras reported as unreadable", state.printed:find("확인할 수 없", 1, true) ~= nil)
	state.auras, state.printed = { "SECRET_RESULT" }, nil
	fire(env, "READY_CHECK")
	check("secret aura result not tested", state.printed ~= nil and state.printed:find("확인할 수 없", 1, true) ~= nil)
	state.auras, state.printed = { "LOCKED" }, nil
	fire(env, "READY_CHECK")
	check("locked aura table not indexed", state.printed ~= nil and state.printed:find("확인할 수 없", 1, true) ~= nil)
	state.printed = nil
	state.settings.buffCheck:SetValue(false)
	fire(env, "READY_CHECK")
	check("buff check toggle off", state.printed == nil)
end

do
	local state = { units = { player = { player = true, class = "DRUID" } }, groupSize = 0, auras = {} }
	local env = boot(state)
	fire(env, "READY_CHECK")
	check("solo checks own class buff", state.printed ~= nil and state.printed:find("야생의 징표", 1, true) ~= nil)
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
	local state = gearState({ spec = { role = "DAMAGER", primary = 4 } })
	local _, ns = boot(state)
	local bySlot = suggested(ns.GearSuggestions())
	check("caster picks the intellect helm", bySlot[1] == "[cloth helm]")
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
		and castBar.range[1] == 99000 and castBar.range[2] == 102000 and castBar.value == 100000)
	check("interruptible cast colored", castBar.fill.color[1] == 1 and castBar.fill.color[2] == 0.7)
	castBar.value = nil
	castBar.scripts.OnUpdate(castBar)
	check("bar follows the clock", castBar.value == 100000)
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

print(string.format("%d checks, %d failures", count, failures))
os.exit(failures == 0 and 0 or 1)
