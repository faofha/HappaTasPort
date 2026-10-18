-- ================================================================================================
--  ENV  (HappaTAS 3 platform): every executor function HappaTAS uses, looked up once by its sUNC
--  name first, then the older names some executors still use. A missing function is nil, and the
--  feature it serves switches itself off (Env.has). Services come through cloneref when the executor
--  has it (a second reference to the same service, not the game's own).
-- ================================================================================================
local Env = {}

local function fn(...)
	for i = 1, select("#", ...) do
		local f = select(i, ...)
		if type(f) == "function" then return f end
	end
	return nil
end
Env.fn = fn

-- (globals read through this script's own environment with a normal lookup: many executors provide
-- their functions through the environment's metatable, which rawget would miss; a missing name is nil)
local G = getfenv(1)
local function g(name)
	local ok, v = pcall(function() return G[name] end)
	if ok then return v end
	return nil
end
local synT = type(g("syn")) == "table" and g("syn") or {}

local getgenvF = fn(g("getgenv"))
Env.genv = (getgenvF and getgenvF()) or _G

local LOOKUP = {
	writefile = { "writefile" }, readfile = { "readfile" }, isfile = { "isfile" }, isfolder = { "isfolder" },
	makefolder = { "makefolder" }, listfiles = { "listfiles" }, delfile = { "delfile" }, appendfile = { "appendfile" },
	lz4compress = { "lz4compress" }, lz4decompress = { "lz4decompress" },
	gethui = { "gethui" }, cloneref = { "cloneref", "clonereference" },
	getgc = { "getgc" }, filtergc = { "filtergc" },
	getconnections = { "getconnections", "getsignals", "get_signal_cons" },
	hookfunction = { "hookfunction", "replaceclosure" }, restorefunction = { "restorefunction" },
	iscclosure = { "iscclosure" }, getloadedmodules = { "getloadedmodules" },
	setreadonly = { "setreadonly" }, isreadonly = { "isreadonly" },
	isactive = { "isrbxactive", "isgameactive", "iswindowactive" },
	keypress = { "keypress", "keydown" }, keyrelease = { "keyrelease", "keyup" },
	mouse1press = { "mouse1press", "mouse1down" }, mouse1release = { "mouse1release", "mouse1up" },
	mouse2press = { "mouse2press", "mouse2down" }, mouse2release = { "mouse2release", "mouse2up" },
	mousemoveabs = { "mousemoveabs" }, mousemoverel = { "mousemoverel" }, mousescroll = { "mousescroll" },
	getcustomasset = { "getcustomasset", "getsynasset" }, identifyexecutor = { "identifyexecutor", "getexecutorname" },
}
for field, names in pairs(LOOKUP) do
	local found = nil
	for _, n in ipairs(names) do
		found = fn(g(n))
		if found then break end
	end
	Env[field] = found
end
if not Env.gethui then Env.gethui = fn(synT.gethui) end

local FEATURES = {
	files = { "writefile", "readfile", "isfile", "isfolder", "makefolder" },
	lz4 = { "lz4compress", "lz4decompress" },
	hooks = { "hookfunction", "restorefunction" },
	connections = { "getconnections" },
	filtergc = { "filtergc" },
	hui = { "gethui" },
}
function Env.has(feature)
	local need = FEATURES[feature]
	if not need then return false end
	for _, f in ipairs(need) do
		if not Env[f] then return false end
	end
	return true
end

Env.executor = "unknown"
if Env.identifyexecutor then
	local ok, name = pcall(Env.identifyexecutor)
	if ok and type(name) == "string" and name ~= "" then Env.executor = name end
end

function Env.svc(name)
	local ok, s = pcall(game.GetService, game, name)
	if not ok or s == nil then return nil end
	if Env.cloneref then
		local ok2, c = pcall(Env.cloneref, s)
		if ok2 and c ~= nil then return c end
	end
	return s
end

return Env
