-- Writes an EllesmereUI import string that sets the UI accent to the player's class color.
-- Usage: luajit tools/make_ellesmere_profile.lua <path to LibDeflate.lua> <output file>

local libPath, outPath = arg[1], arg[2]
local LibDeflate = dofile(libPath)

-- Matches EllesmereUI's Serializer format, emitted with sorted keys for reproducible output.
local function serialize(value, parts)
	local kind = type(value)
	if kind == "string" then
		parts[#parts + 1] = "s" .. #value .. ":" .. value
	elseif kind == "number" then
		parts[#parts + 1] = "n" .. tostring(value) .. ";"
	elseif kind == "boolean" then
		parts[#parts + 1] = value and "T" or "F"
	elseif kind == "table" then
		local keys = {}
		for key in pairs(value) do keys[#keys + 1] = key end
		table.sort(keys)
		parts[#parts + 1] = "{"
		for _, key in ipairs(keys) do
			parts[#parts + 1] = "K"
			serialize(key, parts)
			serialize(value[key], parts)
		end
		parts[#parts + 1] = "}"
	end
end

local parts = {}
serialize({
	version = 3,
	type = "full",
	client = "forever",
	data = { addons = {}, euiAccent = { useClass = true } },
}, parts)

local encoded = LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(table.concat(parts)))
local file = assert(io.open(outPath, "w"))
file:write("!EUI_" .. encoded)
file:close()
