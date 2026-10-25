-- ================================================================================================
--  KIT CLOCK  (HappaTAS 3 world plugin, order 60, "Kit Scripts On TAS Clock"): the EToH kit's own scripts on
--  the TAS clock (V2.38.17 p16_kit.lua 1-506, function by function; the speed hack is reached through E.time).
--  The kit's client objects time themselves with task.wait, task.delay, os.clock and the kit's tween helper
--  (Utility.Functions.tween). Every kit ModuleScript runs in a global environment table of its own, so
--  HappaTAS puts its own task (wait, delay) and os (clock) into the environments of the kit's modules, and its
--  own tween into Utility.Functions. Their clock: Idle: real time. Create: the TAS clock (stopped while paused,
--  x s with the speed hack). Test: the playback speed.
--  Frame events: kit scripts that move things by the dt of RunService.Heartbeat / PostSimulation get the kit
--  clock's time for the frame too (their listeners, found with getconnections, are disabled and called by
--  HappaTAS while the clock doesn't run at 1x). The kit's Button script keeps the real os.clock (Sync Button
--  Timers moves its timers). Undone on Unload: the environments get their own task / os back, waiting kit
--  threads finish their wait in real time, running tweens jump to their end.
--  The environments come from Env.envOf (a computed-name lookup: HappaTAS 3's own code never names it, see
--  platform/env).
-- ================================================================================================
local Env = import("platform/env")

local RunService = Env.svc("RunService")
local TweenService = Env.svc("TweenService")
local engine = nil -- (the engine, set by KitClockPlugin.new)
local KitClock = {}

do
	local KC = KitClock
	local realTask = task
	local clock = os.clock
	local K0, R0, rate = clock(), clock(), 1
	KC.rate = 1
	KC.patched = 0 -- number of kit module environments using the clock

	-- the kit's time (seconds). Starts equal to os.clock, then lags behind it by the pauses / slow motion
	function KC.Now() return K0 + (clock() - R0) * rate end
	function KC.SetRate(r)
		r = tonumber(r) or 1
		if r ~= r or r < 0 then r = 0 end
		if r == rate then return end
		local now = clock()
		K0 = K0 + (now - R0) * rate
		R0 = now
		rate = r
		KC.rate = r
	end

	-- the speed hack's Frame Step: the clock is stopped (rate 0) and moves on by each physics step that ran
	function KC.Advance(d)
		d = tonumber(d) or 0
		if d > 0 then K0 = K0 + d end
	end

	-- Pausing in Create mode puts the character back on the last recorded frame: the physics step after it
	-- is thrown away. The kit's clock goes back to that frame's time too (KC.Mark = the kit's time when a
	-- frame is recorded, the last two are kept), so a pause gives the kit no extra frame (before: a jump
	-- launcher's push ended one frame early after a pause). It never goes forward this way, never more than a
	-- second back, and only on the TAS (data table) the frame was recorded in.
	local marks = { {}, {} }
	function KC.Mark(data, n)
		local m1 = marks[1]
		if not (m1.data == data and m1.n == n) then marks[2] = m1; m1 = {}; marks[1] = m1 end
		m1.data, m1.n, m1.k = data, n, KC.Now()
	end
	function KC.Rewind(data, n)
		local now = clock()
		local cur = K0 + (now - R0) * rate
		local k = nil
		for _, m in ipairs(marks) do
			if m.data == data and m.n == n then k = m.k end
		end
		if k and k < cur and cur - k <= 1 then cur = k end
		K0, R0, rate, KC.rate = cur, now, 0, 0
	end

	-- ------------------------------------------------------------------------------------- task.wait / delay
	-- A waiting kit thread is resumed by KC.Step (Heartbeat, like task.wait) once the kit's clock passed its
	-- time, at least one frame later. waitingFor[thread] = its entry: a thread resumed by anything else (or
	-- cancelled) is simply dropped, never resumed twice.
	local waiting = {}
	local waitingFor = setmetatable({}, { __mode = "k" })
	local frameNo = 0
	local function kitWait(d)
		d = tonumber(d) or 0
		if d ~= d or d < 0 then d = 0 end
		local co = coroutine.running()
		local now = KC.Now()
		local e = { co = co, target = now + d, start = now, frame = frameNo }
		waitingFor[co] = e
		waiting[#waiting + 1] = e
		local res = table.pack(coroutine.yield())
		if waitingFor[co] == e then waitingFor[co] = nil end
		return table.unpack(res, 1, res.n)
	end
	local function kitDelay(d, f, ...)
		local args = table.pack(...)
		return realTask.spawn(function()
			kitWait(d)
			if type(f) == "thread" then
				realTask.spawn(f, table.unpack(args, 1, args.n))
			else
				f(table.unpack(args, 1, args.n))
			end
		end)
	end
	KC.Wait, KC.Delay = kitWait, kitDelay

	function KC.Waiting() return #waiting end

	-- ------------------------------------------------------------------------------------- tweens
	-- Utility.Functions.tween on the kit's clock: same easing (TweenService:GetValue), same end values, a
	-- Tween-like object (Completed with Connect / Once / Wait, PlaybackState, Play / Pause / Cancel /
	-- Destroy). Tweens that repeat, reverse or start late, and properties it can't blend, still go to the
	-- real TweenService.
	local tweens = {}
	local TWEENABLE = { number = true, Vector3 = true, Vector2 = true, CFrame = true, Color3 = true, UDim2 = true, UDim = true }
	local function blend(a, b, x)
		local ta = typeof(a)
		if ta == "number" then return a + (b - a) * x end
		if ta == "UDim" then return UDim.new(a.Scale + (b.Scale - a.Scale) * x, a.Offset + (b.Offset - a.Offset) * x) end
		return a:Lerp(b, x)
	end
	local function newSignal()
		local s = { list = {} }
		function s.Connect(self, fn)
			local c = { Connected = true }
			function c.Disconnect(cc) cc.Connected = false end
			c.fn = fn
			self.list[#self.list + 1] = c
			return c
		end
		function s.Once(self, fn)
			local c
			c = self:Connect(function(...) c:Disconnect(); fn(...) end)
			return c
		end
		function s.Wait(self)
			local co = coroutine.running()
			self:Once(function(...) realTask.spawn(co, ...) end)
			return coroutine.yield()
		end
		function s.Fire(self, ...)
			local list = self.list
			self.list = {}
			for _, c in ipairs(list) do
				if c.Connected then
					self.list[#self.list + 1] = c
					realTask.spawn(c.fn, ...)
				end
			end
		end
		return s
	end
	local tweenMt = {}
	tweenMt.__index = tweenMt
	local function finishTween(tw, state)
		for i = #tweens, 1, -1 do if tweens[i] == tw then table.remove(tweens, i) end end
		tw.PlaybackState = state
		tw.Completed:Fire(state)
	end
	local function writeTween(tw, x)
		local inst = tw.Instance
		for prop, to in pairs(tw.goal) do
			local from = tw.from[prop]
			if from ~= nil then
				local v = (x >= 1) and to or blend(from, to, x)
				pcall(function() inst[prop] = v end)
			end
		end
	end
	function tweenMt.Play(tw)
		if tw.PlaybackState == Enum.PlaybackState.Playing then return end
		if tw.PlaybackState == Enum.PlaybackState.Paused and tw.pausedAt then
			tw.startK = KC.Now() - tw.pausedAt
		else
			tw.from = {}
			for prop in pairs(tw.goal) do
				local ok, v = pcall(function() return tw.Instance[prop] end)
				if ok and typeof(v) == typeof(tw.goal[prop]) then tw.from[prop] = v end
			end
			tw.startK = KC.Now()
		end
		tw.pausedAt = nil
		tw.PlaybackState = Enum.PlaybackState.Playing
		tweens[#tweens + 1] = tw
	end
	function tweenMt.Pause(tw)
		if tw.PlaybackState ~= Enum.PlaybackState.Playing then return end
		for i = #tweens, 1, -1 do if tweens[i] == tw then table.remove(tweens, i) end end
		tw.pausedAt = KC.Now() - tw.startK
		tw.PlaybackState = Enum.PlaybackState.Paused
	end
	function tweenMt.Cancel(tw)
		if tw.PlaybackState == Enum.PlaybackState.Playing or tw.PlaybackState == Enum.PlaybackState.Paused then
			finishTween(tw, Enum.PlaybackState.Cancelled)
		end
	end
	function tweenMt.Destroy(tw)
		for i = #tweens, 1, -1 do if tweens[i] == tw then table.remove(tweens, i) end end
		tw.destroyed = true
	end
	local function stepTweens()
		if #tweens == 0 then return end
		local now = KC.Now()
		local list = table.clone(tweens)
		for _, tw in ipairs(list) do
			local info = tw.TweenInfo
			local len = info.Time
			local a = (len > 0) and (now - tw.startK) / len or 1
			if a >= 1 then
				writeTween(tw, 1)
				finishTween(tw, Enum.PlaybackState.Completed)
			elseif a > 0 then
				local ok, x = pcall(TweenService.GetValue, TweenService, a, info.EasingStyle, info.EasingDirection)
				writeTween(tw, ok and x or a)
			end
		end
	end
	local function endTweens()
		local list = tweens
		tweens = {}
		for _, tw in ipairs(list) do
			writeTween(tw, 1)
			tw.PlaybackState = Enum.PlaybackState.Completed
			tw.Completed:Fire(Enum.PlaybackState.Completed)
		end
	end

	local fnTable, origTween, fnWasReadonly = nil, nil, false
	local function kitTween(instance, config, goal, easingStyle, easingDirection, ...)
		local extra = table.pack(...)
		local okI, info = pcall(function()
			if typeof(config) == "number" then
				return TweenInfo.new(config,
					(typeof(easingStyle) == "EnumItem") and easingStyle or Enum.EasingStyle.Linear,
					(typeof(easingDirection) == "EnumItem") and easingDirection or Enum.EasingDirection.Out,
					table.unpack(extra, 1, extra.n))
			end
			return TweenInfo.new(config.Time, config.Style, config.Direction)
		end)
		local plain = okI and typeof(info) == "TweenInfo" and info.RepeatCount == 0 and not info.Reverses
			and info.DelayTime <= 0 and typeof(goal) == "table" and typeof(instance) == "Instance"
		if plain then
			for _, v in pairs(goal) do
				if not TWEENABLE[typeof(v)] then plain = false break end
			end
		end
		if not plain or not origTween then
			return origTween(instance, config, goal, easingStyle, easingDirection, table.unpack(extra, 1, extra.n))
		end
		local tw = setmetatable({ Instance = instance, TweenInfo = info, PlaybackState = Enum.PlaybackState.Begin,
			Completed = newSignal(), goal = goal, from = {} }, tweenMt)
		tw:Play()
		return tw
	end
	KC.Tween = kitTween

	-- ------------------------------------------------------------------------------------- environments
	local fakeTask = setmetatable({ wait = kitWait, delay = kitDelay }, { __index = task })
	local fakeOs = setmetatable({ clock = KC.Now }, { __index = os })
	local patched = {} -- env -> { task, os } (what the environment had itself before)
	local SKIP_CLOCK = { Button = true } -- Repository.Interactables.Button: Sync Button Timers owns its clock

	-- the full names of the kit modules on the clock: a frame listener is only looked into when its source
	-- (debug.info) is one of them
	local kitSources = {}
	local function kitRoots()
		local RS = Env.svc("ReplicatedStorage")
		if not RS then return {} end
		local roots = {}
		local fw = RS:FindFirstChild("Framework")
		local kit = fw and fw:FindFirstChild("Kit")
		if kit then roots[#roots + 1] = kit end
		local ext = RS:FindFirstChild("ExternalRepositories")
		if ext then roots[#roots + 1] = ext end
		return roots
	end

	-- the global environment of a ModuleScript the game already ran: any Lua function it returned lives in it
	local function envOf(ms)
		local ok, ret = pcall(require, ms)
		if not ok then return nil end
		local fn = nil
		if type(ret) == "function" then
			fn = ret
		elseif type(ret) == "table" then
			for _, v in pairs(ret) do
				if type(v) == "function" and not (Env.iscclosure and Env.iscclosure(v)) then fn = v break end
			end
		end
		if not fn then return nil end
		local okE, env = pcall(Env.envOf, fn)
		if not okE or type(env) ~= "table" or rawget(env, "script") ~= ms then return nil end
		return env
	end

	local function patchEnv(env, withClock, name)
		if patched[env] then return end
		patched[env] = { task = rawget(env, "task"), os = rawget(env, "os"), name = name }
		rawset(env, "task", fakeTask)
		if withClock then rawset(env, "os", fakeOs) end
		KC.patched = KC.patched + 1
	end

	local function patchTween(kit)
		if fnTable then return end
		local util = kit:FindFirstChild("Utility")
		local fm = util and util:FindFirstChild("Functions")
		if not fm then return end
		local ok, F = pcall(require, fm)
		if not ok or type(F) ~= "table" or type(rawget(F, "tween")) ~= "function" then return end
		local ro = table.isfrozen(F) or (Env.isreadonly ~= nil and Env.isreadonly(F) == true)
		if ro and not (Env.setreadonly and pcall(Env.setreadonly, F, false)) then return end
		local orig = rawget(F, "tween")
		local okW = pcall(rawset, F, "tween", kitTween)
		if ro then pcall(Env.setreadonly, F, true) end
		if okW then fnTable, origTween, fnWasReadonly = F, orig, ro end
	end
	local function unpatchTween()
		if not fnTable then return end
		if fnWasReadonly then pcall(Env.setreadonly, fnTable, false) end
		pcall(rawset, fnTable, "tween", origTween)
		if fnWasReadonly then pcall(Env.setreadonly, fnTable, true) end
		fnTable = nil
	end

	-- the kit's modules the game already loaded (getloadedmodules: requiring a module the game never ran
	-- would run it a second time in HappaTAS's thread)
	local function scan()
		if not (Env.getloadedmodules and Env.envOf) then return 0 end
		local okL, list = pcall(Env.getloadedmodules)
		if not okL or type(list) ~= "table" then return 0 end
		local loaded = {}
		for _, m in ipairs(list) do loaded[m] = true end
		local n = 0
		for _, root in ipairs(kitRoots()) do
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("ModuleScript") and loaded[d] then
					local env = envOf(d)
					if env and not patched[env] then
						patchEnv(env, not SKIP_CLOCK[d.Name], d.Name)
						n = n + 1
					end
					if env then kitSources[d:GetFullName()] = true end
				end
			end
			if root.Name == "Kit" then patchTween(root) end
		end
		return n
	end

	local function releaseWaits()
		local now = KC.Now()
		local list = waiting
		waiting = {}
		for _, e in ipairs(list) do
			if waitingFor[e.co] == e then
				waitingFor[e.co] = nil
				if coroutine.status(e.co) == "suspended" then
					-- the rest of the wait in real time
					local rem = math.max(0, e.target - now)
					pcall(realTask.delay, rem, e.co, rem + (now - e.start))
				end
			end
		end
	end

	local enabled = false
	-- ------------------------------------------------------------------------------------- frame events
	local SIGNALS = { "Heartbeat", "PostSimulation" }
	-- left on Roblox's own call: the Morpher turns a lerp step into a velocity (distance / the frame's real dt,
	-- the velocity the physics needs, also slowed down), DistanceCulling does no time maths
	local SKIP_FRAME = { Morpher = true, DistanceCulling = true }
	local taken = { Heartbeat = {}, PostSimulation = {} } -- signal name -> { function -> the kit's connection }
	local function kitFunction(f)
		if type(f) ~= "function" or (Env.iscclosure and Env.iscclosure(f)) then return false end
		-- (only a kit module's function: see kitSources)
		local okS, src = pcall(debug.info, f, "s")
		if not (okS and type(src) == "string" and kitSources[src]) then return false end
		local ok, env = pcall(Env.envOf, f)
		local p = ok and patched[env]
		return p ~= nil and p ~= false and not SKIP_FRAME[p.name]
	end
	-- the kit's time for this frame (dt = the signal's real dt)
	function KC.FrameDt(dt)
		if engine.time:stepping() then return engine.time:stepDt() end
		return (tonumber(dt) or 0) * rate
	end
	local function giveBack(name)
		for _, c in pairs(taken[name]) do pcall(function() c:Enable() end) end
		taken[name] = {}
	end
	-- the kit's listeners on the signal (newly connected ones are taken over, disconnected ones dropped), then
	-- each one called with the kit's dt
	local function runFrame(name, dt)
		local mine = taken[name]
		-- (Frame Step's flag read straight from time control: this runs twice a frame)
		local wantNow = enabled and Env.getconnections ~= nil and (rate ~= 1 or (KC.timeFS ~= nil and KC.timeFS.on))
		if not wantNow then
			if next(mine) then giveBack(name) end
			return
		end
		local okL, list = pcall(Env.getconnections, RunService[name])
		if not okL or type(list) ~= "table" then return end
		local seen = {}
		for _, c in ipairs(list) do
			local okF, f = pcall(function() return c.Function end)
			if okF and f and (mine[f] or kitFunction(f)) then
				if not mine[f] then
					if not pcall(function() c:Disable() end) then f = nil end
					if f then mine[f] = c end
				end
				if f then seen[f] = true end
			end
		end
		local kdt = KC.FrameDt(dt)
		for f in pairs(mine) do
			if not seen[f] then
				mine[f] = nil -- (the kit disconnected it)
			else
				-- (a kit function runs on a thread of its own: game code would take this thread's CoreGui access)
				local okS, err = pcall(realTask.spawn, f, kdt)
				if not okS then engine.errs:report("kit clock", err) end
			end
		end
	end
	KC.FrameEvents = taken

	function KC.Enable()
		if enabled then return end
		enabled = true
		local ok, err = pcall(scan)
		if not ok then engine.errs:report("kit clock", err) end
	end
	function KC.Disable()
		if not enabled then return end
		enabled = false
		for env, old in pairs(patched) do
			pcall(rawset, env, "task", old.task)
			pcall(rawset, env, "os", old.os)
		end
		patched = {}
		KC.patched = 0
		for _, name in ipairs(SIGNALS) do giveBack(name) end
		unpatchTween()
		endTweens()
		releaseWaits()
	end
	function KC.IsEnabled() return enabled end

	-- every Heartbeat: waiting kit threads whose time came, then the tweens
	function KC.Step()
		frameNo = frameNo + 1
		local n = #waiting
		if n > 0 then
			local now = KC.Now()
			local due, keep = nil, 0
			for i = 1, n do
				local e = waiting[i]
				if waitingFor[e.co] ~= e then
					-- (cancelled, or resumed by something else)
				elseif now >= e.target - 1e-9 and frameNo > e.frame then
					due = due or {}
					due[#due + 1] = e
				else
					keep = keep + 1
					waiting[keep] = e
				end
			end
			for i = keep + 1, n do waiting[i] = nil end
			if due then
				for _, e in ipairs(due) do
					waitingFor[e.co] = nil
					if coroutine.status(e.co) == "suspended" then
						local ok, err = pcall(realTask.spawn, e.co, now - e.start)
						if not ok then engine.errs:report("kit clock", err) end
					end
				end
			end
		end
		stepTweens()
	end

	-- (V2 KC.Start: every Heartbeat the waiting kit threads whose time came and the tweens, then the kit's frame
	-- listeners; PostSimulation's listeners; a look for new kit modules now and then)
	function KC.StartLoops()
		-- (in the pipeline, after the engine's handlers of those stages: where V2's own connections ran)
		engine.pipe:add("Heartbeat", 95, "kitclock.step", function(dt)
			local ok, err = pcall(KC.Step)
			if not ok then engine.errs:report("kit clock", err) end
			ok, err = pcall(runFrame, "Heartbeat", dt)
			if not ok then engine.errs:report("kit clock", err) end
		end, "kitclock")
		engine.pipe:add("PostSimulation", 95, "kitclock.frame", function(dt)
			local ok, err = pcall(runFrame, "PostSimulation", dt)
			if not ok then engine.errs:report("kit clock", err) end
		end, "kitclock")
		-- the kit may still be loading when HappaTAS starts (and towers can add repository modules later):
		-- look again now and then for modules that aren't on the clock yet
		task.spawn(function()
			local waitFor = 2
			while not engine.life.unloading do
				task.wait(waitFor)
				if engine.life.unloading then break end
				if enabled then
					local ok, err = pcall(scan)
					if not ok then engine.errs:report("kit clock", err) end
				end
				waitFor = math.min(waitFor * 2, 30)
			end
		end)
	end
end

-- ------------------------------------------------------------------------------------------------ the plugin
local KC = KitClock
local KitClockPlugin = { name = "kitclock", order = 60 }
KitClockPlugin.__index = KitClockPlugin

function KitClockPlugin.new(E)
	engine = E
	local self = setmetatable({ E = E, KC = KC, rate = 1 }, KitClockPlugin)
	KC.timeFS = E.time.SH and E.time.SH.FS
	E.life:own(function() KC.Disable() end)
	E.life:own(E.settings:changed("kitScriptsOnTasClock", function(v)
		if v ~= 0 then KC.Enable() else KC.Disable() end
	end))
	if E.settings:on("kitScriptsOnTasClock") then KC.Enable() end
	KC.StartLoops()
	return self
end

function KitClockPlugin:now() return KC.Now() end
function KitClockPlugin:setRate(r)
	KC.SetRate(r)
	self.rate = KC.rate
end
function KitClockPlugin:advance(d) KC.Advance(d) end
function KitClockPlugin:frameDt(dt) return KC.FrameDt(dt) end
function KitClockPlugin:waiting() return KC.Waiting() end
function KitClockPlugin:isEnabled() return KC.IsEnabled() end
function KitClockPlugin:wait(d) return KC.Wait(d) end
function KitClockPlugin:delay(d, f, ...) return KC.Delay(d, f, ...) end
function KitClockPlugin:tween(...) return KC.Tween(...) end
-- (the kit's time of each recorded frame: a pause goes back to the last one)
function KitClockPlugin:begin(tl, i) KC.Mark(tl, i) end
function KitClockPlugin:onRewind(tl, n) KC.Rewind(tl, n) end

return KitClockPlugin
