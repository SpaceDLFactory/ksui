-- Lists every API and widget method guarded by a precondition that raises or reports an error, and where the
-- addon calls something by that name. Usage: luajit api-throws.lua <docs dir> <addon dir>
local docsDir, addonDir = arg[1], arg[2]
local THROWS = { RequiresUnitAuraAccess = true, RequiresIndexInRange = true, RequiresLimitedInput = true,
	RequiresAssignableScript = true, RequiresCanChangeHitTestPoints = true, RequiresTimedSignalMapAccess = true,
	RequiresValidAbbreviationBreakpoints = true, RequiresRestrictedAbbreviationBreakpoints = true,
	RequiresDeclassifiedUnitIdentity = true, RequiresScriptObjectAlphaAccess = true,
	RequiresScriptObjectDesaturationAccess = true, RequiresStatusBarDesaturationAccess = true,
	RequiresUnitIdentityAccess = true }
local guarded = {}
APIDocumentation = { AddDocumentationTable = function(_, t)
	for _, fn in ipairs(t.Functions or {}) do
		for k in pairs(fn) do
			if THROWS[k] then
				local short = fn.Name
				guarded[short] = guarded[short] or {}
				guarded[short][(t.Namespace or t.Name) .. ":" .. k] = true
			end
		end
	end
end }
for file in io.popen('ls "' .. docsDir .. '"'):lines() do
	if file:match("%.lua$") then local c = loadfile(docsDir .. "/" .. file); if c then pcall(c) end end
end
for file in io.popen('ls "' .. addonDir .. '"'):lines() do
	if file:match("%.lua$") then
		local n = 0
		for line in io.lines(addonDir .. "/" .. file) do
			n = n + 1
			local code = line:gsub("%-%-.*", "")
			for name in code:gmatch("[%.:]([%a_][%w_]*)%s*[%(,]") do
				if guarded[name] then
					local why = {}
					for k in pairs(guarded[name]) do why[#why + 1] = k end
					table.sort(why)
					print(file .. ":" .. n .. "  " .. name .. "  " .. table.concat(why, " "))
				end
			end
			for name in code:gmatch("pcall%(([%w_%.]+)") do print(file .. ":" .. n .. "  (pcall) " .. name) end
		end
	end
end
