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

-- (each name is a plain global reference: it goes through this script's environment and its metatable,
-- where many executors put their functions; a missing name is nil. getfenv / rawget are never used:
-- getfenv switches Luau's fast paths off for the whole environment)
local synT = type(syn) == "table" and syn or {}

local getgenvF = fn(getgenv)
Env.genv = (getgenvF and getgenvF()) or _G

Env.writefile, Env.readfile, Env.isfile = fn(writefile), fn(readfile), fn(isfile)
Env.isfolder, Env.makefolder, Env.listfiles = fn(isfolder), fn(makefolder), fn(listfiles)
Env.delfile, Env.appendfile = fn(delfile), fn(appendfile)
Env.lz4compress, Env.lz4decompress = fn(lz4compress), fn(lz4decompress)
Env.gethui = fn(gethui)
Env.cloneref = fn(cloneref, clonereference)
Env.getgc, Env.filtergc = fn(getgc), fn(filtergc)
Env.getconnections = fn(getconnections, getsignals, get_signal_cons)
Env.hookfunction = fn(hookfunction, replaceclosure)
Env.restorefunction = fn(restorefunction)
Env.iscclosure, Env.getloadedmodules = fn(iscclosure), fn(getloadedmodules)
Env.setreadonly, Env.isreadonly = fn(setreadonly), fn(isreadonly)
Env.isactive = fn(isrbxactive, isgameactive, iswindowactive)
Env.keypress, Env.keyrelease = fn(keypress, keydown), fn(keyrelease, keyup)
Env.mouse1press, Env.mouse1release = fn(mouse1press, mouse1down), fn(mouse1release, mouse1up)
Env.mouse2press, Env.mouse2release = fn(mouse2press, mouse2down), fn(mouse2release, mouse2up)
Env.mousemoveabs, Env.mousemoverel, Env.mousescroll = fn(mousemoveabs), fn(mousemoverel), fn(mousescroll)
Env.getcustomasset = fn(getcustomasset, getsynasset)
Env.identifyexecutor = fn(identifyexecutor, getexecutorname)
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
