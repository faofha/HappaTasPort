-- ================================================================================================
-- HappaTAS 3, phase 1: the platform layer (executor functions with fallbacks, services, game calls)
-- Variants (PRE sets VARIANT): plain, cloneref (cloneref counted), signals (only getsignals), bare (no
-- getgenv / cloneref / hookfunction: the script must still load), indexed (the executor's functions
-- reached through the environment's metatable, not raw globals: how many executors provide them)
-- ================================================================================================
VARIANT = VARIANT or "plain"
if VARIANT == "indexed" then
	-- the script's environment reaches the executor's functions through its metatable
	local chunkEnv = getfenv(1) -- (where this test's globals live; _G itself is read-only in the CLI)
	setfenv(__SCRIPT__, setmetatable({}, { __index = function(_, k)
		local v = hiddenFns[k]
		if v ~= nil then return v end
		return chunkEnv[k]
	end, __newindex = chunkEnv }))
end
check(boot(3), "boots (" .. VARIANT .. ")")
local Env = __T3("platform/env")
local GC = __T3("platform/gamecall")

section("lookup")
eq(Env.fn(nil, 5, print), print, "fn picks the first function")
eq(Env.fn(nil, false), nil, "fn: nil when none is a function")
check(Env.svc("RunService") ~= nil, "svc finds a service")
eq(Env.svc("NoSuchService"), nil, "svc: nil for an unknown service")
check(type(Env.executor) == "string" and Env.executor ~= "", "executor name (" .. tostring(Env.executor) .. ")")

if VARIANT == "plain" then
	eq(Env.getconnections, getconnections, "getconnections found")
	eq(Env.genv, getgenv(), "genv is getgenv()")
	check(Env.has("hooks"), "hooks available")
	check(Env.has("files"), "files available")
	eq(Env.executor, "MockExec", "identifyexecutor's name")
elseif VARIANT == "cloneref" then
	local before = cloneCalls
	Env.svc("Players")
	check(cloneCalls > before, "svc goes through cloneref")
elseif VARIANT == "signals" then
	check(Env.getconnections ~= nil and Env.getconnections == getsignals, "getconnections falls back to getsignals")
	check(Env.has("connections"), "connections available through the fallback")
elseif VARIANT == "indexed" then
	check(Env.getconnections ~= nil and Env.getconnections == hiddenFns.getconnections, "a function behind the environment's metatable is found")
	check(Env.has("hooks"), "hooks found behind the metatable")
elseif VARIANT == "bare" then
	eq(Env.genv, _G, "no getgenv: genv is _G")
	eq(Env.has("hooks"), false, "no hookfunction: hooks off")
	eq(Env.cloneref, nil, "no cloneref")
	check(Env.svc("RunService") ~= nil, "svc works without cloneref")
end

section("game calls run on a thread of their own")
local outer = coroutine.running()
local inner = nil
eq(GC.call(function() inner = coroutine.running() end), true, "call: finished")
check(inner ~= nil and inner ~= outer, "call: the function ran on another thread")
eq(GC.call(function() task.wait() end), false, "call: a function that yields reports false")
eq(GC.call(function() error("boom") end), false, "call: an error reports false")
local ok, v = GC.get(function() return 7 end)
eq(ok, true, "get: finished")
eq(v, 7, "get: the first result")
eq((GC.get(function() error("boom") end)), false, "get: an error reports false")
finish()
