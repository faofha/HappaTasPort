-- ================================================================================================
--  ENV  (HappaTAS 3 platform): every executor function HappaTAS uses, looked up once by its sUNC
--  name first, then the older names some executors still use. A missing function is nil, and the
--  feature it serves switches itself off (Env.has). Services come through cloneref when the executor
--  has it (a second reference to the same service, not the game's own).
-- ================================================================================================
local CONFIG = import("config")
local Env = {}

-- a note: a feature that switched itself off for a missing executor function. Each text is kept once in
-- Env.notes (Help > Missing executor functions lists them) and printed only with Debug.
local noted = {}
Env.notes = {}
function Env.debugNote(text)
	if noted[text] then return end
	noted[text] = true
	Env.notes[#Env.notes + 1] = text
	if CONFIG.Debug then print("[HappaTAS3] " .. text) end
end

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
Env.delfolder = fn(delfolder)
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
Env.delfile = fn(delfile)
-- game:HttpGet(url) -> ok, body (or the error). HappaTAS's only network call: the Classic Look background link
-- the user typed (ui/classic/background), downloaded once. It yields.
function Env.httpGet(url)
	return pcall(function() return game:HttpGet(url) end)
end
Env.identifyexecutor = fn(identifyexecutor, getexecutorname)
Env.setclipboard = fn(setclipboard, toclipboard)
Env.getfpscap = fn(getfpscap)
if not Env.gethui then Env.gethui = fn(synT.gethui) end

-- the environment of a game function (the Kit Clock puts its own task / os into the EToH kit's module
-- environments). The function that gives it is found by a computed name in Roblox's environment (getrenv), the
-- executor's (getgenv) or _G: Luau switches its fast paths off for any script that names it, and HappaTAS 3's
-- own code never does (tools/test_all3.sh checks the build). Only used on kit functions; nil without it.
do
	local name = "get" .. "fenv"
	local getrenvF = fn(getrenv)
	local found = nil
	if getrenvF then
		local ok, f = pcall(function() return getrenvF()[name] end)
		if ok and type(f) == "function" then found = f end
	end
	if not found then
		local ok, f = pcall(function() return Env.genv[name] end)
		if ok and type(f) == "function" then found = f end
	end
	if not found then
		local ok, f = pcall(function() return _G[name] end)
		if ok and type(f) == "function" then found = f end
	end
	if found then
		Env.envOf = function(f)
			if type(f) ~= "function" or (Env.iscclosure and Env.iscclosure(f)) then return nil end
			return found(f)
		end
	end
end

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

-- (the functions whose features would only notice they're missing later, at a moment that may never come:
-- noted now, in the words those features use)
if not Env.getconnections then Env.debugNote("getconnections unavailable; the kit's frame listeners keep real time") end
if not Env.getloadedmodules then
	Env.debugNote("getloadedmodules unavailable; the Kit Clock is off (the kit's scripts keep real time)")
end
if not Env.has("files") then Env.debugNote("Saving is unavailable on this executor (no file functions)") end

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
