-- ================================================================================================
-- HappaTAS 3, phase 1: the frame pipeline (ordered, protected handlers per Roblox event)
-- ================================================================================================
-- (counts every coroutine.create: the pipeline must not make a new thread per handler call)
local realCo = coroutine
creates = 0
coroutine = setmetatable({ create = function(f) creates = creates + 1; return realCo.create(f) end }, { __index = realCo })
check(boot(3), "boots")
local Lifecycle = __T3("kernel/lifecycle")
local Errors = __T3("kernel/errors")
local Bus = __T3("kernel/bus")
local Pipeline = __T3("kernel/pipeline")
local RS = M.services.RunService

local printed = {}
local life = Lifecycle.new()
local errs = Errors.new(function(m) printed[#printed + 1] = m end)
local bus = Bus.new(errs)
local before = { RS.PreRender:Count(), RS.PreSimulation:Count(), RS.PostSimulation:Count() }
local pipe = Pipeline.new(life, errs, bus)
pipe:start()
local log = {}
local function logger(name) return function() log[#log + 1] = name end end

section("one runner thread per stage, not one per handler call")
do
	local c0 = creates
	M.steps(10)
	local base = creates - c0
	local removers = {}
	for i = 1, 10 do removers[i] = pipe:add("PreRender", 100 + i, "busy" .. i, function() end) end
	c0 = creates
	M.steps(10)
	local perFrame = (creates - c0 - base) / 10
	check(perFrame <= 1, "10 handlers in one stage make at most 1 thread a frame (" .. perFrame .. ")")
	c0 = creates
	M.steps(10)
	eq(creates - c0 - base, 0, "a runner is reused from frame to frame: no new thread once running")
	for _, rm in ipairs(removers) do rm() end
end

section("order: by stage, then by order number, ties in the order added")
local frame0 = pipe.frame
pipe:add("PreRender", 20, "b", logger("b"))
pipe:add("PreRender", 10, "a", logger("a"))
pipe:add("PreSimulation", 10, "c", logger("c"))
pipe:add("PostSimulation", 10, "d", logger("d"))
pipe:add("LateRender", 10, "e", logger("e"))
pipe:add("PreRender", 10, "a2", logger("a2"))
M.step(1 / 60)
local s = table.concat(log, ",")
check(s:find("a,a2,b", 1, true) ~= nil, "PreRender handlers in order (" .. s .. ")")
check(s:find("c,d", 1, true) ~= nil, "PreSimulation before PostSimulation (" .. s .. ")")
check(s:find("e", 1, true) ~= nil, "LateRender handler ran (" .. s .. ")")
check(s:find("b") < s:find("c"), "PreRender before PreSimulation")
eq(pipe.frame, frame0 + 1, "frame counter")

section("a frame without a physics step has no PreSimulation / PostSimulation")
log = {}
M.simDt = function() return 0 end
M.step(1 / 240)
M.simDt = nil
s = table.concat(log, ",")
check(s:find("c", 1, true) == nil and s:find("d", 1, true) == nil, "no physics handlers (" .. s .. ")")
check(s:find("a", 1, true) ~= nil, "render handlers still ran")

section("Heartbeat: after PostSimulation, every frame, also without a physics step")
do
	local hb = {}
	local rmA = pipe:add("PostSimulation", 10, "hbPost", function() hb[#hb + 1] = "post" end)
	local rmB = pipe:add("Heartbeat", 10, "hbBeat", function() hb[#hb + 1] = "beat" end)
	M.step(1 / 60)
	eq(table.concat(hb, ","), "post,beat", "Heartbeat handlers run after PostSimulation")
	hb = {}
	M.simDt = function() return 0 end
	M.step(1 / 240)
	M.simDt = nil
	eq(table.concat(hb, ","), "beat", "Heartbeat runs in a frame without a physics step")
	rmA(); rmB()
end

section("an erroring handler: others keep running, printed once, switched off after 5 frames in a row")
local disabled = {}
bus:on("moduleDisabled", function(name, err) disabled[#disabled + 1] = name end)
local bad = pipe:add("PreRender", 15, "bad", function() error("boom") end)
local flaky = 0
pipe:add("PreRender", 16, "flaky", function() flaky = flaky + 1; if flaky % 3 ~= 0 then error("sometimes") end end)
log = {}
for _ = 1, 4 do M.step(1 / 60) end
eq(#disabled, 0, "still on after 4 failing frames")
M.step(1 / 60)
eq(disabled[1], "bad", "switched off after the 5th failing frame")
local n = 0
for _, m in ipairs(printed) do if m:find("bad: ", 1, true) then n = n + 1 end end
eq(n, 1, "its error was printed once")
s = table.concat(log, ",")
check(select(2, s:gsub("b", "")) >= 5, "the handler after it kept running")
for _ = 1, 9 do M.step(1 / 60) end
local flakyOff = false
for _, d in ipairs(disabled) do if d == "flaky" then flakyOff = true end end
check(not flakyOff, "a handler that fails twice then works is not switched off")

section("switching off a failing module switches off all its handlers, in every stage")
local recPost = 0
pipe:add("PreRender", 40, "rec.capture", function() error("capture broke") end, "rec")
pipe:add("PostSimulation", 40, "rec.fill", function() recPost = recPost + 1 end, "rec")
local recOff = false
bus:on("moduleDisabled", function(name) if name == "rec" then recOff = true end end)
for _ = 1, 5 do M.step(1 / 60) end
check(recOff, "moduleDisabled names the module")
local recPostAt = recPost
M.steps(3)
eq(recPost, recPostAt, "the module's handler in another stage stopped too")

section("a handler that yields")
local afterYield = 0
pipe:add("PreSimulation", 5, "yielder", function() task.wait() end)
pipe:add("PreSimulation", 6, "afterYield", function() afterYield = afterYield + 1 end)
M.step(1 / 60)
eq(afterYield, 1, "the handler after it ran in the same frame")
local yieldMsg = false
for _, m in ipairs(printed) do if m:find("yielder: yielded (handlers must not yield)", 1, true) then yieldMsg = true end end
check(yieldMsg, "reported as yielded")

section("remove and stop")
local removeMe = 0
local rm = pipe:add("PreRender", 1, "removeMe", function() removeMe = removeMe + 1 end)
M.step(1 / 60)
rm()
M.step(1 / 60)
eq(removeMe, 1, "remove() stops a handler")
local afterStop = 0
pipe:add("PreRender", 2, "stopper", function() pipe:stop() end)
pipe:add("PreRender", 3, "afterStop", function() afterStop = afterStop + 1 end)
M.step(1 / 60)
eq(afterStop, 0, "stop() inside a handler skips the rest of that frame")
M.step(1 / 60)
eq(afterStop, 0, "and every frame after")

section("cleanup disconnects everything")
life:cleanup()
eq(RS.PreRender:Count(), before[1], "PreRender connections back to before")
eq(RS.PreSimulation:Count(), before[2], "PreSimulation connections back to before")
eq(RS.PostSimulation:Count(), before[3], "PostSimulation connections back to before")
local bound = false
for _, b in ipairs(M.binds) do if b.name == "HappaTAS3Late" then bound = true end end
check(not bound, "the late render-step bind is gone")
-- (the errors above were provoked on purpose: keep finish()'s log check about real runtime errors)
finish()
