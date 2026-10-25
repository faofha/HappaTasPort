-- ================================================================================================
-- HappaTAS 3, phase 4: an executor without filtergc / getconnections / getloadedmodules / hookfunction
-- (Review Focus 4). Run once per line of tests3/noexec.variants ("plain": everything there; "bare": those
-- four missing). Without them the Kit Clock, the kit objects' tables and the kit config scaling switch
-- themselves off with a Debug note each; client objects, lighting and time control still work; nothing errors.
-- (headless mock, a small world: a kit module stand-in, client object parts, a bounce pad's config table)
-- ================================================================================================
local RSt = M.services.ReplicatedStorage
local function folder(parent, name) local f = Instance.new("Folder"); f.Name = name; f.Parent = parent; return f end
local kitF = folder(folder(RSt, "Framework"), "Kit")
local physicsF = folder(folder(kitF, "Repository"), "Physics")
do
	local ms = Instance.new("ModuleScript"); ms.Name = "Timer"; ms.Parent = physicsF
	local env = setmetatable({ script = ms }, { __index = setmetatable({ os = os }, { __index = getfenv(1) }) })
	local chunk = loadstring("local T = { ticks = 0 } function T.Tick() end return T", "=" .. ms:GetFullName())
	setfenv(chunk, env)
	M.modules[ms] = chunk()
end
local CP = folder(workspace, "ClientParts")
local movers = {}
for i = 1, 6 do
	local p = Instance.new("Part"); p.Name = "P" .. i; p.Size = Vector3.new(4, 1, 4)
	p.CFrame = CFrame.new(i * 6, 3, 20); p.Anchored = true; p.Parent = CP
	movers[i] = p
end
local moveConn = M.services.RunService.Heartbeat:Connect(function()
	for k, p in ipairs(movers) do p.CFrame = p.CFrame * CFrame.Angles(0, 0.02 * k, 0) end
end)
local padInst = Instance.new("Configuration"); padInst.Name = "BouncePadConfiguration"
local padCfg = { __instance = padInst, __defaults = {}, Power = 100 }
M.gcTables[#M.gcTables + 1] = padCfg

local notes = {}
local realPrint = print
print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	notes[#notes + 1] = table.concat(parts, " ")
end
local bare = VARIANT == "bare"

check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
check(E.char:loaded(), "character loaded")
local G0 = workspace.Gravity
local function steps(n) for _ = 1, n do M.step(1 / 60) end end
local function noteWith(text)
	for _, n in ipairs(notes) do if n:find(text, 1, true) then return true end end
	return false
end

section("a run recorded and played (" .. tostring(VARIANT) .. ")")
E.settings:set("syncClientObjects", 1)
E.settings:set("speedHack", 1)
E.settings:set("speedHackSpeed", 0.5)
steps(2)
E.modes:request("create")
steps(2)
E.modes:request("unpause")
steps(30)
check(E.mode == 2 and not E.paused, "recording")
near(workspace.Gravity, G0 * 0.25, 1e-6, "time control: gravity x 0.25 at 0.5x")
local padWhile = padCfg.Power
E.modes:request("pause")
steps(2)
local n = E.tl:count()
check(n > 20, "frames recorded (" .. n .. ")")
local coFrames = 0
for i = 1, n do if type(E.tl:getList("v2CO", i)) == "string" then coFrames = coFrames + 1 end end
check(coFrames > 0, "client objects recorded (" .. coFrames .. " frames)")
check(E.tl:getList("LT", 1) ~= nil, "lighting: the first frame's snapshot")
E.modes:request("test")
steps(60)
E.modes:request("idle")
steps(2)
E.settings:set("speedHack", 0)
steps(2)

section("what switched itself off")
local KC = E.kitClock.KC
if bare then
	eq(KC.patched, 0, "Kit Clock: no kit module on the TAS clock")
	eq(padWhile, 100, "kit config scaling off: the pad's Power untouched")
	check(noteWith("getloadedmodules"), "Debug note: getloadedmodules unavailable")
	check(noteWith("filtergc unavailable; kit config"), "Debug note: filtergc unavailable (kit config scaling)")
	check(noteWith("filtergc unavailable; beat block"), "Debug note: filtergc unavailable (kit objects' tables)")
else
	check(KC.patched >= 1, "Kit Clock: the kit module on the TAS clock (" .. tostring(KC.patched) .. ")")
	eq(padWhile, 50, "kit config scaling: the pad's Power x 0.5 while slowed")
	check(not noteWith("unavailable"), "no 'unavailable' notes")
end
-- (each note once)
local counts = {}
for _, nt in ipairs(notes) do if nt:find("unavailable", 1, true) then counts[nt] = (counts[nt] or 0) + 1 end end
local twice = 0
for _, c in pairs(counts) do if c > 1 then twice = twice + 1 end end
eq(twice, 0, "each note printed once")

section("nothing errored, Unload clean")
getgenv().__HappaTAS3.Unload()
steps(2)
local errs = {}
for src, c in pairs(T.errs.counts) do errs[#errs + 1] = src .. " x" .. c end
eq(#errs, 0, "no errors reported (" .. table.concat(errs, ", ") .. ")")
near(workspace.Gravity, G0, 1e-9, "gravity back")
eq(padCfg.Power, 100, "the pad's Power back")
moveConn:Disconnect()
print = realPrint
finish()
