-- ================================================================================================
--  PIPELINE  (HappaTAS 3 kernel): the one place that decides what runs in each Roblox event, in what
--  order. Stages, in the order measured in the client: PreRender, PreSimulation, physics,
--  PostSimulation, Heartbeat, then LateRender (BindToRenderStep at Last + 1). A frame without a physics
--  step has no PreSimulation / PostSimulation (Roblox steps physics at 240 Hz), so those handlers aren't
--  called; Heartbeat runs every frame.
--  Handlers run by ascending order number (ties in the order they were added), each on a thread of its
--  own: an error or a yield is reported and the next handler still runs; when a handler's last 5 calls
--  all failed, every handler of its module (all stages) is switched off (bus event "moduleDisabled" with
--  the module's name). Handlers must not yield.
-- ================================================================================================
local Env = import("platform/env")

local Pipeline = {}
Pipeline.__index = Pipeline
local STAGES = { "PreRender", "PreSimulation", "PostSimulation", "Heartbeat", "LateRender" }
local MAX_FAILS = 5
local LATE_BIND = "HappaTAS3Late"

function Pipeline.new(life, errs, bus)
	local stages = {}
	for _, s in ipairs(STAGES) do stages[s] = {} end
	return setmetatable({ life = life, errs = errs, bus = bus, stages = stages, runners = {}, seq = 0, stopped = false, frame = 0 }, Pipeline)
end

local function removeEntry(list, e)
	e.on = false
	local i = table.find(list, e)
	if i then table.remove(list, i) end
end

-- module: the module the handler belongs to (defaults to its name); switched off together
function Pipeline:add(stage, order, name, fn, module)
	local list = self.stages[stage]
	if not list then error("HappaTAS3: unknown pipeline stage " .. tostring(stage), 2) end
	self.seq = self.seq + 1
	local e = { order = order, seq = self.seq, name = name, fn = fn, fails = 0, on = true, module = module or name }
	local at = #list + 1
	for i, other in ipairs(list) do
		if other.order > order then at = i break end
	end
	table.insert(list, at, e)
	return function() removeEntry(list, e) end
end

function Pipeline:disableModule(module, err)
	for _, s in ipairs(STAGES) do
		local list = self.stages[s]
		for i = #list, 1, -1 do
			if list[i].module == module then removeEntry(list, list[i]) end
		end
	end
	self.bus:emit("moduleDisabled", module, err)
end

local function cancel(co)
	if not pcall(task.cancel, co) then pcall(coroutine.close, co) end
end

-- One runner thread per stage runs the handlers one after another: each handler is resumed in it and the
-- runner yields DONE when the handler returns (a new thread per call was ~12,000 threads a second at 240
-- FPS: garbage-collection lag). The runner is kept for the next frame. A handler that errors kills it, one
-- that yields leaves it suspended somewhere else: either way it is dropped and the next handler gets a new one.
local DONE = {}
local function runnerLoop(fn, dt)
	while true do
		fn(dt)
		fn, dt = coroutine.yield(DONE)
	end
end

function Pipeline:run(stage, dt)
	if self.stopped then return end
	if stage == "PreRender" then self.frame = self.frame + 1 end
	local list = self.stages[stage]
	if #list == 0 then return end
	local runner = self.runners[stage]
	self.runners[stage] = nil -- (taken while running: a nested run of the same stage makes its own)
	for _, e in ipairs(table.clone(list)) do
		if self.stopped then return end
		if e.on then
			if not runner then runner = coroutine.create(runnerLoop) end
			local ok, res = coroutine.resume(runner, e.fn, dt)
			local err = res
			if not ok then
				runner = nil
			elseif res ~= DONE then
				cancel(runner)
				runner = nil
				ok, err = false, "yielded (handlers must not yield)"
			end
			if ok then
				e.fails = 0
			else
				e.fails = e.fails + 1
				self.errs:report(e.name, err)
				if e.fails >= MAX_FAILS then self:disableModule(e.module, err) end
			end
		end
	end
	self.runners[stage] = runner
end

function Pipeline:start()
	local rs = Env.svc("RunService")
	local life = self.life
	life:connect(rs.PreRender, function(dt) self:run("PreRender", dt) end)
	life:connect(rs.PreSimulation, function(dt) self:run("PreSimulation", dt) end)
	life:connect(rs.PostSimulation, function(dt) self:run("PostSimulation", dt) end)
	life:connect(rs.Heartbeat, function(dt) self:run("Heartbeat", dt) end)
	local okB = pcall(function()
		rs:BindToRenderStep(LATE_BIND, Enum.RenderPriority.Last.Value + 1, function(dt) self:run("LateRender", dt) end)
	end)
	if okB then
		life:own(function() pcall(function() rs:UnbindFromRenderStep(LATE_BIND) end) end)
	end
end

function Pipeline:stop()
	self.stopped = true
end

return Pipeline
