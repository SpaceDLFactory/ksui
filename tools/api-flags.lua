-- Loads Blizzard's generated API docs and lists, for every API the addon source calls, the flags that matter for
-- secret values: Requires* (raises an error when not allowed), SecretReturns / SecretWhen* / ConditionalSecret*
-- (may return secrets), SecretArguments. Usage: luajit api-audit.lua <docs dir> <addon dir>
local docsDir, addonDir = arg[1], arg[2]
local api = {}
local function walk(tbl)
	local ns = tbl.Namespace
	for _, fn in ipairs(tbl.Functions or {}) do
		local name = ns and (ns .. "." .. fn.Name) or fn.Name
		api[name] = fn
	end
	for _, ev in ipairs(tbl.Events or {}) do api["event:" .. ev.LiteralName] = ev end
	if tbl.Type == "ScriptObject" then
		for _, fn in ipairs(tbl.Functions or {}) do api["method:" .. fn.Name] = api["method:" .. fn.Name] or fn end
	end
end
APIDocumentation = { AddDocumentationTable = function(_, t) walk(t) end }
for file in io.popen('ls "' .. docsDir .. '"'):lines() do
	if file:match("%.lua$") then
		local chunk = loadfile(docsDir .. "/" .. file)
		if chunk then pcall(chunk) end
	end
end
local function flags(fn)
	local out = {}
	for k, v in pairs(fn) do
		if type(k) == "string" and (k:find("^Requires") or k:find("Secret") or k == "MayReturnNothing") then
			out[#out + 1] = k .. (v == true and "" or "=" .. tostring(v))
		end
	end
	for _, r in ipairs(fn.Returns or {}) do
		for k, v in pairs(r) do
			if type(k) == "string" and k:find("Secret") then out[#out + 1] = "ret." .. r.Name .. "." .. k .. (v == true and "" or "=" .. tostring(v)) end
		end
	end
	for _, a in ipairs(fn.Arguments or {}) do
		for k, v in pairs(a) do
			if type(k) == "string" and k:find("Secret") then out[#out + 1] = "arg." .. a.Name .. "." .. k end
		end
	end
	table.sort(out)
	return table.concat(out, " ")
end
local used = {}
for file in io.popen('ls "' .. addonDir .. '"'):lines() do
	if file:match("%.lua$") then
		local n = 0
		for line in io.lines(addonDir .. "/" .. file) do
			n = n + 1
			local code = line:gsub("%-%-.*", "")
			for name in code:gmatch("([%a_][%w_]*%.[%a_][%w_]*)%s*%(") do
				if api[name] then used[name] = used[name] or {}; table.insert(used[name], file .. ":" .. n) end
			end
			for name in code:gmatch("([%a_][%w_]*)%s*%(") do
				if api[name] then used[name] = used[name] or {}; table.insert(used[name], file .. ":" .. n) end
			end
		end
	end
end
local names = {}
for k in pairs(used) do names[#names + 1] = k end
table.sort(names)
for _, name in ipairs(names) do
	local f = flags(api[name])
	if f ~= "" and f ~= "SecretArguments=AllowedWhenUntainted" then
		print(name .. "  [" .. f .. "]\n    " .. table.concat(used[name], " "))
	end
end
