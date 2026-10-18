-- ================================================================================================
--  KIT CLOCK  (the EToH kit's own scripts on the TAS clock, "Kit Scripts On TAS Clock")
--
--  The kit's client objects time themselves with task.wait, task.delay, os.clock and the kit's tween helper
--  (Utility.Functions.tween). Every kit ModuleScript runs in a global environment table of its own, and a
--  global the script reads is looked up in that table when it runs. So HappaTAS puts its own task (wait,
--  delay) and os (clock) into the environments of the kit's modules (checked in the live client: the
--  BeatBlock loop's next task.wait went through it), and its own tween into Utility.Functions. Their clock:
--      Idle: real time.  Create: the TAS clock (stopped while paused, x s with the speed hack).
--      Test: the playback speed.
--  So a jump launcher's 0.125 s push, a moving platform's wait, a vanisher, a falling platform, a speed
--  boost, a pushbox spawner's cooldown... stop while the TAS is paused and slow down with the speed hack,
--  the way Eternal Obbying's TAS does it: its whole game runs on one clock (the session's pace = the TAS
--  speed x the time warp feeds the fixed simulation steps), so slowing the clock slows everything.
--  Frame events: kit scripts that move things by the dt of RunService.Heartbeat / PostSimulation (the Zipline
--  ride, the Sequencer's timeline, KeyGroup's keys) get the kit clock's time for the frame
--  too: while the clock doesn't run at 1x, the kit's own listeners on those signals (found with getconnections:
--  their function's environment is a kit module's) are disabled and HappaTAS calls them every frame with
--  dt x the rate (Frame Step: the time of the physics step that ran, 0 when it was held).
--  Not covered: tweens a kit script makes with TweenService directly. The kit's Button script keeps the real os.clock:
--  Sync Button Timers already moves its timers onto the TAS clock.
--  Undone on Unload: the environments get their own task / os back, waiting kit threads finish their wait
--  in real time, running tweens jump to their end.
-- ================================================================================================
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

	local function kitRoots()
		local RS = svc("ReplicatedStorage")
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
		local okE, env = pcall(getfenv, fn)
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
		if not (Env.getloadedmodules and type(getfenv) == "function") then return 0 end
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
		local ok, env = pcall(getfenv, f)
		local p = ok and patched[env]
		return p ~= nil and p ~= false and not SKIP_FRAME[p.name]
	end
	-- the kit's time for this frame (dt = the signal's real dt)
	function KC.FrameDt(dt)
		if SpeedHack.Stepping() then return SpeedHack.StepDt() end
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
		local wantNow = enabled and Env.getconnections ~= nil and (rate ~= 1 or SpeedHack.Stepping())
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
				if not okS then reportError("kit clock", err) end
			end
		end
	end
	KC.FrameEvents = taken

	function KC.Enable()
		if enabled then return end
		enabled = true
		local ok, err = pcall(scan)
		if not ok then reportError("kit clock", err) end
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
						if not ok then reportError("kit clock", err) end
					end
				end
			end
		end
		stepTweens()
	end

	function KC.Start()
		local function want() return Settings.On("Kit Scripts On TAS Clock") end
		if want() then KC.Enable() end
		Settings.Changed("Kit Scripts On TAS Clock", function(v)
			if v ~= 0 then KC.Enable() else KC.Disable() end
		end)
		on(RunService.Heartbeat, function(dt)
			local ok, err = pcall(KC.Step)
			if not ok then reportError("kit clock", err) end
			ok, err = pcall(runFrame, "Heartbeat", dt)
			if not ok then reportError("kit clock", err) end
		end)
		on(RunService.PostSimulation, function(dt)
			local ok, err = pcall(runFrame, "PostSimulation", dt)
			if not ok then reportError("kit clock", err) end
		end)
		-- the kit may still be loading when HappaTAS starts (and towers can add repository modules later):
		-- look again now and then for modules that aren't on the clock yet
		task.spawn(function()
			local waitFor = 2
			while not Janitor.unloading do
				task.wait(waitFor)
				if Janitor.unloading then break end
				if enabled then
					local ok, err = pcall(scan)
					if not ok then reportError("kit clock", err) end
				end
				waitFor = math.min(waitFor * 2, 30)
			end
		end)
		Janitor.add(function() KC.Disable() end)
	end
end

-- ================================================================================================
--  KIT OBJECTS  (EToH kit v6.1.3 objects whose state comes from time, "Sync Kit Objects")
--
--  Beat blocks (Repository/Visual/BeatBlock): the kit switches the groups with a task.wait loop that started
--  whenever the script did, so a recording and its playback never had the same beat, and a paused TAS kept
--  beating. HappaTAS works the beat out from the TAS time instead, with the kit's own rules: group
--  floor(t / Interval) mod N + 1 is on, the next group shows the indicator for the last IndicatorInterval
--  of a beat (the kit's displayNext), t = 0 is where the TAS starts. Eternal Obbying's beat blocks are the
--  same function of its run clock (Objects/Kinds beat_at). CanCollide, CanTouch, Transparency, Size,
--  Material and the children (ToggleChildren) are written whenever the kit writes its own; the kit's ding
--  plays on HappaTAS's beat instead. Music synced beat blocks are left to the kit.
--
--  Turrets (Interactables/Turret): the kit still decides when to fire (its loop runs on the kit clock above),
--  but its bullet is replaced by HappaTAS's: a copy of the kit's bullet that moves on the TAS clock
--  (start + LookVector x Speed x time, like the kit's LinearVelocity) and is saved in the TAS (fire and end
--  events), so the same bullets play back, freeze while paused and come back when you go back in time.
--  A bullet ends where the kit's would (Blockcast along its path every frame: a CanCollide part, or a limb of
--  your character, which takes the kit's damage through the kit's own CharacterManager:Damage), or after
--  MaxLifetime.
--
--  Pushbox spawners: the spawn is saved; a box spawned later in the TAS is hidden (no collision) when you go
--  back to before it was spawned, until the kit spawns one again.
--
--  Bounce pads and jump launchers: their effect (sound, particle burst) is saved when the kit plays it and
--  played again while testing (the kit only plays it on a real touch, and playback poses the character).
--
--  Your character: forces a kit script puts on it (the jump launcher's LinearVelocity...) are switched off
--  while testing (the replay already moves the character), and removed when you unpause at a frame from
--  before they were added.
--
--  A TAS remembers whether it was made with this on (TAS.KitVersion 1): older TAS files keep the kit's own
--  behaviour, so they play back the way they were recorded.
-- ================================================================================================
do
	local KO = KitObjects
	KO.CURRENT = 1
	local CS = svc("CollectionService")
	local V3, CF = Vector3.new, CFrame.new
	local floor = math.floor

	local reg = { keyToId = {}, idToKey = {}, nextId = 1 }
	local function idFor(key)
		local id = reg.keyToId[key]
		if id then return id end
		id = reg.nextId
		reg.nextId = id + 1
		reg.keyToId[key], reg.idToKey[id] = id, key
		return id
	end
	KO.Reg = reg

	-- the rules of a TAS (nil = a TAS being made now: decided by the setting when it starts recording)
	function KO.VersionOf(data)
		local v = data and rawget(data, "KitVersion")
		if v == nil then return Settings.On("Sync Kit Objects") and KO.CURRENT or 0 end
		return v
	end

	local cur = { mode = 1, data = nil, f = 0, t = 0, rec = false, on = false }
	KO.cur = cur

	local holder -- folder for HappaTAS's own bullets (under the camera: game scripts that look through the
	-- tower's parts never see them)
	local function getHolder()
		local cam = workspace.CurrentCamera
		if holder and holder.Parent == cam and cam then return holder end
		if holder then pcall(function() holder:Destroy() end) end
		holder = Instance.new("Folder")
		holder.Name = "HappaTASKit"
		holder.Parent = cam or workspace
		return holder
	end

	local function attr(inst, name, def)
		local v = inst and inst:GetAttribute(name)
		if v == nil then return def end
		if typeof(def) == "EnumItem" and type(v) == "string" then
			local ok, e = pcall(function() return def.EnumType[v] end)
			return (ok and e) or def
		end
		if typeof(v) ~= typeof(def) then return def end
		return v
	end

	-- sounds the kit plays itself are muted while HappaTAS plays them on its own time
	local muted = {}
	local function mute(snd)
		if not snd then return end
		local m = muted[snd]
		if m then m.n = m.n + 1 return end
		muted[snd] = { n = 1, vol = snd.Volume }
		pcall(function() snd.Volume = 0 end)
	end
	local function unmuteAll()
		for snd, m in pairs(muted) do pcall(function() snd.Volume = m.vol end) end
		muted = {}
	end
	local ownSounds = setmetatable({}, { __mode = "k" }) -- the copies HappaTAS plays itself
	local function playCopy(snd, parent)
		if not (snd and parent and parent.Parent) then return end
		local m = muted[snd]
		local vol = m and m.vol or snd.Volume
		if vol <= 0 then return end
		pcall(function()
			local c = snd:Clone()
			ownSounds[c] = true
			c.Volume = vol
			c.Parent = parent
			c:Play()
			local len = (c.TimeLength > 0 and c.TimeLength or 2) / math.max(c.PlaybackSpeed, 0.01)
			task.delay(len + 0.1, function() pcall(function() c:Destroy() end) end)
		end)
	end

	local function charRoot()
		local ch = LocalPlayer.Character
		return ch, ch and ch:FindFirstChild("HumanoidRootPart")
	end

	-- --------------------------------------------------------------------------------------------- beat blocks
	local AFFECTED = { Decal = "Transparency", Texture = "Transparency", SelectionBox = "Transparency",
		SelectionSphere = "Transparency", SurfaceGui = "Enabled", BillboardGui = "Enabled", Beam = "Enabled",
		ParticleEmitter = "Enabled", Fire = "Enabled", Sparkles = "Enabled", Smoke = "Enabled", Trail = "Enabled",
		PointLight = "Enabled", SpotLight = "Enabled", SurfaceLight = "Enabled", Highlight = "Enabled" }
	local beats, beatOf = {}, {}

	local function beatConf(cfg)
		return {
			indicator = attr(cfg, "Indicator", true),
			indSize = attr(cfg, "IndicatorSize", V3(3, 3, 3)),
			indMul = attr(cfg, "IndicatorScaleMultiplier", 1),
			indMat = attr(cfg, "MaterialIndicator", Enum.Material.SmoothPlastic),
			offCC = attr(cfg, "OffCanCollide", false), offTr = attr(cfg, "OffTransparency", 0.5), offCT = attr(cfg, "OffCanTouch", false),
			onCC = attr(cfg, "OnCanCollide", true), onTr = attr(cfg, "OnTransparency", 1), onCT = attr(cfg, "OnCanTouch", true),
			interval = attr(cfg, "Interval", 1), indInterval = attr(cfg, "IndicatorInterval", 0.5),
			children = attr(cfg, "ToggleChildren", false),
		}
	end

	-- the kit's own table of the group's parts with their sizes and materials (Visual/BeatBlock: the
	-- toggleBeatBlock closure of the group's loop keeps it), so a group caught showing its indicator still
	-- gets its real size back
	local function kitBeatTables()
		local out = {}
		if not Env.filtergc then return out end
		local ok, fns = pcall(Env.filtergc, "function", { Constants = { "IndicatorInterval" } })
		if not ok or type(fns) ~= "table" then return out end
		for _, fn in ipairs(fns) do
			pcall(function()
				local cfgInst, tbl = nil, nil
				for _, up in pairs(debug.getupvalues(fn)) do
					if type(up) == "table" and typeof(rawget(up, "__instance")) == "Instance" and rawget(up, "Interval") ~= nil then
						cfgInst = rawget(up, "__instance")
					elseif type(up) == "function" then
						for _, up2 in pairs(debug.getupvalues(up)) do
							if type(up2) == "table" then
								local _, first = next(up2)
								if type(first) == "table" and type(first[1]) == "table" and typeof(first[1].part) == "Instance" then tbl = up2 end
							end
						end
					end
				end
				if cfgInst and tbl then out[cfgInst] = tbl end
			end)
		end
		return out
	end

	local function looksLikeIndicator(g, p)
		local c = g.conf
		return c.indicator and c.indMul == 1 and p.Material == c.indMat and (p.Size - c.indSize).Magnitude < 1e-3
	end

	local function addBeat(cfg, kitTables)
		if beatOf[cfg] then return end
		local folder = cfg.Parent
		if not (folder and folder:IsA("Folder")) then return end
		local ms = cfg:FindFirstChild("MusicSyncConfiguration")
		if ms and ms:GetAttribute("SyncEnabled") == true and type(ms:GetAttribute("ZoneName")) == "string" then return end
		local g = { cfg = cfg, groups = {}, parts = {}, orig = {}, kids = {}, conf = beatConf(cfg), n = 0, dirty = true, conns = {},
			last = nil }
		for _, p in ipairs(folder:GetDescendants()) do
			if p:IsA("BasePart") then
				local num = tonumber(p.Name:match("%d+"))
				if num then
					local list = g.groups[num]
					if not list then list = {}; g.groups[num] = list end
					list[#list + 1] = p
					g.parts[#g.parts + 1] = p
				end
			end
		end
		while g.groups[g.n + 1] do g.n = g.n + 1 end
		if g.n == 0 then return end
		local kitT = kitTables and kitTables[cfg]
		for _, p in ipairs(g.parts) do
			local o = nil
			if kitT then
				for _, list in pairs(kitT) do
					for _, d in ipairs(list) do
						if d.part == p and typeof(d.size) == "Vector3" then o = { size = d.size, material = d.material } end
					end
				end
			end
			if not o and not looksLikeIndicator(g, p) then o = { size = p.Size, material = p.Material } end
			g.orig[p] = o
			local kids = {}
			for _, ch in ipairs(p:GetChildren()) do
				if AFFECTED[ch.ClassName] then kids[#kids + 1] = ch end
			end
			g.kids[p] = kids
			for _, prop in ipairs({ "CanCollide", "CanTouch", "Transparency", "Size", "Material" }) do
				g.conns[#g.conns + 1] = p:GetPropertyChangedSignal(prop):Connect(function()
					g.dirty = true
					-- learned while HappaTAS doesn't drive the group: the kit gives every part its own size and
					-- material back at each beat
					if not g.driving and (prop == "Size" or prop == "Material") and not looksLikeIndicator(g, p) then
						g.orig[p] = { size = p.Size, material = p.Material }
					end
				end)
			end
		end
		g.conns[#g.conns + 1] = cfg.AttributeChanged:Connect(function() g.conf = beatConf(cfg); g.dirty = true end)
		local snd = cfg:FindFirstChild("DingSound")
		if not (snd and snd:IsA("Sound")) then
			local ok, s = pcall(function()
				return svc("ReplicatedStorage").Framework.Kit.Repository.Visual.BeatBlock:FindFirstChild("DefaultDingSound")
			end)
			snd = (ok and s and s:IsA("Sound")) and s or nil
		end
		g.ding = snd
		beatOf[cfg] = g
		beats[#beats + 1] = g
	end

	local function dropBeat(g)
		for _, c in ipairs(g.conns) do c:Disconnect() end
		beatOf[g.cfg] = nil
		for i = #beats, 1, -1 do if beats[i] == g then table.remove(beats, i) end end
	end

	-- the kit's loop: toggle(k) [wait Interval - IndicatorInterval] displayNext(k + 1) [wait IndicatorInterval]
	local function beatAt(g, t)
		local c = g.conf
		local ii = c.indicator and math.max(c.indInterval, 0) or 0
		local first = math.max(c.interval - ii, 0)
		local len = first + ii
		if len <= 1e-6 then len = 1e-6 end
		local cycle = floor(t / len)
		local active = cycle % g.n + 1
		local phase = t - cycle * len
		local ind = nil
		if c.indicator and phase >= first then ind = active % g.n + 1 end
		return active, ind, cycle
	end

	local function setIf(p, prop, v)
		if p[prop] ~= v then p[prop] = v end
	end
	local function beatWrite(g, active, ind)
		local c = g.conf
		for num, list in pairs(g.groups) do
			local on = num == active
			local isInd = num == ind
			for _, p in ipairs(list) do
				local o = g.orig[p] or { size = p.Size, material = p.Material }
				g.orig[p] = o
				pcall(function()
					if isInd then
						setIf(p, "Size", (c.indMul ~= 1) and o.size * c.indMul or c.indSize)
						setIf(p, "Material", c.indMat)
						setIf(p, "CanCollide", c.offCC)
						setIf(p, "CanTouch", c.offCT)
						setIf(p, "Transparency", c.offTr)
					else
						local cc, ct, tr = c.offCC, c.offCT, c.offTr
						if on then cc, ct, tr = c.onCC, c.onCT, c.onTr end
						setIf(p, "Size", o.size)
						setIf(p, "Material", o.material)
						setIf(p, "CanCollide", cc)
						setIf(p, "CanTouch", ct)
						setIf(p, "Transparency", tr)
						if c.children then
							for _, ch in ipairs(g.kids[p]) do
								if AFFECTED[ch.ClassName] == "Transparency" then setIf(ch, "Transparency", tr)
								else setIf(ch, "Enabled", on) end
							end
						end
					end
				end)
			end
		end
	end

	-- a group is written when its beat changed or a write touched it since (dirty); beatWrite only writes the
	-- properties that differ
	local function beatStep(t, advancing)
		for _, g in ipairs(beats) do
			if not (g.cfg.Parent) then
				dropBeat(g)
			else
				local active, ind, cycle = beatAt(g, t)
				local key = active * 1000 + (ind or 0)
				if g.dirty or g.lastKey ~= key then
					if advancing and g.lastCycle ~= nil and cycle ~= g.lastCycle and g.ding then
						local _, root = charRoot()
						local best, bd = nil, math.huge
						for _, p in ipairs(g.groups[active] or {}) do
							local d = root and (p.Position - root.Position).Magnitude or 0
							if d < bd then best, bd = p, d end
						end
						playCopy(g.ding, best)
					end
					g.driving = true
					beatWrite(g, active, ind)
					g.dirty = false
					g.lastKey = key
				end
				g.lastCycle = cycle
			end
		end
	end

	-- --------------------------------------------------------------------------------------------- turrets
	local turrets, turretOf = {}, {}
	-- the bullets of the TAS in memory (fire order), built from its events; firstSpawn[spawner id] = the first
	-- frame a pushbox spawn event of that spawner is saved on
	local idx = { data = nil, list = {}, bySeq = {}, nextSeq = 1, valid = false, maxLife = 0, firstSpawn = {} }
	local shown = {}   -- bullet record -> model on screen
	local damageEvent  -- the kit's CharacterManager (for its Damage)

	local function stripBullet(m)
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("LuaSourceContainer") or d:IsA("Constraint") or d:IsA("BodyMover") or d:IsA("TouchTransmitter") then
				pcall(function() d:Destroy() end)
			elseif d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d:SetAttribute("HappaTASIgnore", true)
			end
		end
		m:SetAttribute("HappaTASBullet", true)
		return m
	end
	local function mainPartOf(m)
		return m.PrimaryPart or m:FindFirstChild("Bullet") or m:FindFirstChildWhichIsA("BasePart", true)
	end

	-- the kit's bullet templates (Interactables/Turret keeps each one in its fireBullet closure, out of the game)
	local function kitBulletTemplates()
		local out = {}
		if not Env.filtergc then return out end
		local ok, fns = pcall(Env.filtergc, "function", { Constants = { "BulletOffset" } })
		if not ok or type(fns) ~= "table" then return out end
		for _, fn in ipairs(fns) do
			pcall(function()
				local tpl, model = nil, nil
				for _, up in pairs(debug.getupvalues(fn)) do
					if typeof(up) == "Instance" then
						if up:IsA("Model") and up.Parent == nil and up:FindFirstChildWhichIsA("BasePart", true) then tpl = up
						elseif up:IsA("BasePart") and up.Name == "Turret" and up.Parent then model = up.Parent end
					end
				end
				if tpl and model then out[model] = tpl end
			end)
		end
		return out
	end

	local function fallbackBullet()
		local m = Instance.new("Model")
		m.Name = "Bullet"
		local p
		local ok, def = pcall(function()
			return svc("ReplicatedStorage").Framework.Kit.Repository.Interactables.Turret:FindFirstChild("Bullet")
		end)
		if ok and def and def:IsA("BasePart") then
			p = def:Clone()
		else
			p = Instance.new("Part")
			p.Shape = Enum.PartType.Ball
			p.Size = V3(1, 1, 1)
			p.Material = Enum.Material.Neon
			p.Color = Color3.fromRGB(255, 0, 0)
		end
		p.Name = "Bullet"
		p.Parent = m
		m.PrimaryPart = p
		return m
	end

	local function turretTemplate(t)
		if t.template then return t.template end
		local kitT = kitBulletTemplates()
		local src = kitT[t.model]
		local ok, m = pcall(function() return src and src:Clone() end)
		t.template = stripBullet((ok and m) or fallbackBullet())
		return t.template
	end

	local onKitBullet -- (below)

	local function addTurret(cfg)
		local model = cfg.Parent
		if not model or turretOf[model] then return end
		local part = model:FindFirstChild("Turret")
		if not (part and part:IsA("BasePart")) then return end
		local key = ClientObjects.KeyOf(model)
		if not key then return end
		local t = { model = model, part = part, cfg = cfg, key = key, id = idFor(key), conns = {} }
		local snd = part:FindFirstChild("Fire")
		t.fireSnd = (snd and snd:IsA("Sound")) and snd or nil
		t.conns[#t.conns + 1] = model.ChildAdded:Connect(function(child)
			if child:IsA("Model") and not child:GetAttribute("HappaTASBullet") then onKitBullet(t, child) end
		end)
		turretOf[model] = t
		turrets[#turrets + 1] = t
		idx.valid = false -- (bullets saved for this turret before it was found)
		-- (the kit loads its objects again on respawn: a turret taken out of the game is forgotten)
		t.conns[#t.conns + 1] = model.AncestryChanged:Connect(function()
			if model:IsDescendantOf(workspace) then return end
			for _, c in ipairs(t.conns) do c:Disconnect() end
			turretOf[model] = nil
			for i = #turrets, 1, -1 do if turrets[i] == t then table.remove(turrets, i) end end
			idx.valid = false
		end)
	end

	local function rotVec(cf)
		local axis, angle = cf:ToAxisAngle()
		return axis * angle
	end
	local function vecRot(x, y, z)
		local v = V3(x, y, z)
		local a = v.Magnitude
		if a < 1e-9 then return CF() end
		return CFrame.fromAxisAngle(v / a, a)
	end

	local function makeBullet(e, f, tFire)
		-- e = { 1, turretId, seq, ox, oy, oz, rx, ry, rz, vx, vy, vz, life }
		local key = reg.idToKey[e[2]]
		local tur = nil
		for _, t in ipairs(turrets) do if t.key == key then tur = t break end end
		return { seq = e[3], f = f, t = tFire, tur = tur, turId = e[2], pos = V3(e[4], e[5], e[6]), rot = vecRot(e[7], e[8], e[9]),
			v = V3(e[10], e[11], e[12]), life = e[13], endF = nil, dmg = 0 }
	end

	local function buildIndex(data)
		idx.data, idx.list, idx.bySeq, idx.nextSeq, idx.valid, idx.maxLife, idx.firstSpawn = data, {}, {}, 1, true, 0, {}
		if not data then return end
		for f = 1, #data do
			local fr = data[f]
			local ke = fr and fr.KE
			if ke then
				for _, e in ipairs(ke) do
					if e[1] == 1 then
						local b = makeBullet(e, f, fr.TotalTime or 0)
						idx.list[#idx.list + 1] = b
						idx.bySeq[b.seq] = b
						if b.seq >= idx.nextSeq then idx.nextSeq = b.seq + 1 end
						if b.life > idx.maxLife then idx.maxLife = b.life end
					elseif e[1] == 2 then
						local b = idx.bySeq[e[2]]
						if b then b.endF = f; b.dmg = e[3] or 0 end
					elseif e[1] == 3 then
						if not idx.firstSpawn[e[2]] then idx.firstSpawn[e[2]] = f end
					end
				end
			end
		end
	end
	-- the first bullet that can still be flying at TAS time t (the list is in fire order)
	local function firstFlying(I, t)
		local list = I.list
		local lo, hi, from = 1, #list, #list + 1
		local tMin = t - I.maxLife - 1e-6
		while lo <= hi do
			local mid = floor((lo + hi) / 2)
			if list[mid].t >= tMin then from = mid; hi = mid - 1 else lo = mid + 1 end
		end
		return from
	end
	local function index(data)
		if not idx.valid or idx.data ~= data then buildIndex(data) end
		return idx
	end

	local function addEvent(fr, e)
		local ke = fr.KE
		if not ke then ke = {}; fr.KE = ke end
		ke[#ke + 1] = e
	end

	local function hideBullet(b)
		local m = shown[b]
		if m then
			shown[b] = nil
			pcall(function() m:Destroy() end)
		end
	end
	local function hideAllBullets()
		for b in pairs(shown) do hideBullet(b) end
	end

	local function bulletAt(b, t)
		return b.pos + b.v * math.max(0, t - b.t)
	end

	local function showBullets(data, f, t)
		local I = index(data)
		local alive = {}
		local list = I.list
		for i = firstFlying(I, t), #list do
			local b = list[i]
			if b.f >= f then break end
			if (b.endF == nil or b.endF >= f) and (t - b.t) <= b.life + 1e-6 then
				alive[b] = true
				local m = shown[b]
				if not m then
					local tur = b.tur
					if tur then
						local ok, c = pcall(function() return turretTemplate(tur):Clone() end)
						if ok and c then
							m = c
							c.Parent = getHolder()
							shown[b] = m
						end
					end
				end
				if m then
					pcall(function() m:PivotTo(CF(bulletAt(b, t)) * b.rot) end)
				end
			end
		end
		for b in pairs(shown) do
			if not alive[b] then hideBullet(b) end
		end
	end

	-- the kit's bullet appeared (its loop fired, on the kit clock): recording -> HappaTAS's bullet takes its
	-- place in the TAS; paused / testing -> the TAS already has its bullets, the kit's is removed
	onKitBullet = function(t, child)
		if not cur.on then return end
		if cur.rec and cur.data and #cur.data > 0 then
			local data = cur.data
			local n = #data
			local fr = data[n]
			if not t.template then
				local ok, c = pcall(function() return child:Clone() end)
				if ok and c then t.template = stripBullet(c) end
			end
			local cfg = t.cfg
			local spawn = t.part.CFrame * attr(cfg, "BulletOffset", CF())
			local vel = t.part.CFrame.LookVector * attr(cfg, "Speed", 50)
			local r3 = rotVec(spawn)
			local I = index(data)
			local seq = I.nextSeq
			I.nextSeq = seq + 1
			local e = { 1, t.id, seq, spawn.X, spawn.Y, spawn.Z, r3.X, r3.Y, r3.Z, vel.X, vel.Y, vel.Z, attr(cfg, "MaxLifetime", 15) }
			addEvent(fr, e)
			local b = makeBullet(e, n, fr.TotalTime or 0)
			b.tur = t
			I.list[#I.list + 1] = b
			I.bySeq[seq] = b
			if b.life > I.maxLife then I.maxLife = b.life end
			playCopy(t.fireSnd, t.part)
		end
		pcall(function() child:Destroy() end)
	end

	local function dealDamage(amount)
		if amount <= 0 then return end
		if damageEvent == nil then
			damageEvent = false
			pcall(function()
				local cm = require(svc("ReplicatedStorage").Framework.Kit.Managers.CharacterManager)
				if type(cm) == "table" and type(cm.Damage) == "function" then damageEvent = cm end
			end)
		end
		if damageEvent then
			-- (a call into the game's script runs in a thread of its own, see gameCall in the bridge)
			task.spawn(pcall, damageEvent.Damage, damageEvent, amount)
		end
	end

	-- what the kit's isValidHit would say about a part the bullet ran into
	local function verdict(b, part, ch)
		if not part:IsA("BasePart") then return nil end
		if b.tur and part == b.tur.part then return nil end
		if CS and part:HasTag("IgnoreBullets") then return nil end
		if not part.CanTouch then return nil end
		local owner = Players:GetPlayerFromCharacter(part.Parent)
		if owner then
			if owner ~= LocalPlayer or part.Name == "Torso" then return nil end
			local tc = b.tur and b.tur.cfg:FindFirstChild("TouchConfiguration")
			if tc and tc:GetAttribute("player") == false then return nil end
			return "player"
		end
		if part.CanCollide then return "solid" end
		return nil
	end

	local castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Exclude
	castParams.RespectCanCollide = false
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.RespectCanCollide = false
	-- the first thing the bullet runs into from p0 to p1 ("player" / "solid"); a Blockcast doesn't see what
	-- already overlaps its start, so what overlaps the end (a limb that moved into the bullet) counts too
	local function castBullet(b, p0, p1, size, ch)
		local ex = { getHolder() }
		if b.tur then ex[#ex + 1] = b.tur.model end
		local dir = p1 - p0
		if dir.Magnitude >= 1e-5 then
			for _ = 1, 8 do
				castParams.FilterDescendantsInstances = ex
				local ok, res = pcall(workspace.Blockcast, workspace, CF(p0) * b.rot, size, dir, castParams)
				if not ok or not res then break end
				local v = verdict(b, res.Instance, ch)
				if v then return v end
				ex[#ex + 1] = res.Instance
			end
		end
		overlapParams.FilterDescendantsInstances = ex
		local ok, list = pcall(workspace.GetPartBoundsInBox, workspace, CF(p1) * b.rot, size, overlapParams)
		if ok and type(list) == "table" then
			local best = nil
			for _, part in ipairs(list) do
				local v = verdict(b, part, ch)
				if v == "player" then return v end
				best = best or v
			end
			return best
		end
		return nil
	end

	local function turretHits(data, n)
		local I = index(data)
		local fr, prev = data[n], data[n - 1]
		if not fr then return end
		local t1 = fr.TotalTime or 0
		local t0 = prev and prev.TotalTime or t1
		local ch = LocalPlayer.Character
		local list = I.list
		for i = firstFlying(I, t0), #list do
			local b = list[i]
			if b.f < n and b.endF == nil then
				local dmg = nil
				if t1 - b.t >= b.life - 1e-6 then
					dmg = 0
				else
					local size = V3(1, 1, 1)
					local m = shown[b] or (b.tur and turretTemplate(b.tur))
					local mp = m and mainPartOf(m)
					if mp then size = mp.Size end
					local hit = castBullet(b, bulletAt(b, math.max(t0, b.t)), bulletAt(b, t1), size, ch)
					if hit == "player" then
						dmg = (mp == nil or mp.Name == "Bullet") and attr(b.tur and b.tur.cfg, "Damage", 5) or 0
					elseif hit == "solid" then
						dmg = 0
					end
					if hit and b.tur and not attr(b.tur.cfg, "DestroyOnTouch", true) then
						-- (the kit leaves such a bullet flying; only the damage happens)
						if dmg > 0 then dealDamage(dmg) end
						dmg = nil
					end
				end
				if dmg then
					addEvent(fr, { 2, b.seq, dmg })
					b.endF, b.dmg = n, dmg
					if dmg > 0 then dealDamage(dmg) end
				end
			end
		end
	end

	-- --------------------------------------------------------------------------------------------- effects
	-- Bounce pads (Interactables/BouncePad) and jump launchers (Interactables/JumpLauncher) play their effect from
	-- their Touched handler: a sound (the kit's playSoundFromInstance puts a copy of it into the part), a particle
	-- burst and a flash the kit tweens back. Playback moves the character itself, so the kit never sees a touch
	-- and nothing showed: the effect is saved as an event when the kit's sound copy appears while recording
	-- (event 4: the object, which sound) and Test plays it again (the sound, the BounceParticle burst; the flash
	-- comes back with Sync Client Objects, which records the part's colour / transparency / size). A sound the
	-- kit plays itself while testing is muted (the TAS has its own).
	local FX_SOUNDS = { "BounceSound", "Tick", "Bounce" } -- event code = index
	local FX_CODE = { BounceSound = 1, Tick = 2, Bounce = 3 }
	local FX_PARTICLE = { BounceSound = true, Bounce = true } -- (the launcher's Tick is only a sound)
	local fxObjects, fxOf = {}, {}
	local function addFx(cfg)
		local part = cfg.Parent
		if not (part and part:IsA("BasePart")) or fxOf[part] then return end
		local key = ClientObjects.KeyOf(part)
		if not key then return end
		local o = { part = part, cfg = cfg, key = key, id = idFor(key), conns = {} }
		o.conns[1] = part.ChildAdded:Connect(function(child)
			if not (FX_CODE[child.Name] and child:IsA("Sound")) or ownSounds[child] or not cur.on then return end
			if cur.mode == 3 then
				pcall(function() child.Volume = 0 end)
			elseif cur.rec and cur.data and #cur.data > 0 then
				addEvent(cur.data[#cur.data], { 4, o.id, FX_CODE[child.Name] })
			end
		end)
		o.conns[2] = part.AncestryChanged:Connect(function()
			if part:IsDescendantOf(workspace) then return end
			for _, c in ipairs(o.conns) do c:Disconnect() end
			fxOf[part] = nil
			for i = #fxObjects, 1, -1 do if fxObjects[i] == o then table.remove(fxObjects, i) end end
		end)
		fxOf[part] = o
		fxObjects[#fxObjects + 1] = o
	end
	local function playFx(id, code)
		local key, name = reg.idToKey[id], FX_SOUNDS[code]
		if not (key and name) then return end
		for _, o in ipairs(fxObjects) do
			if o.key == key and o.part.Parent then
				local snd, burst = nil, nil
				for _, d in ipairs(o.part:GetDescendants()) do
					-- (the kit's sound: in the pad's configuration / the launcher's Sounds folder, not a copy)
					if not snd and d.Name == name and d:IsA("Sound") and d.Parent ~= o.part then snd = d end
					if not burst and d.Name == "BounceParticle" and d:IsA("ParticleEmitter") then burst = d end
				end
				if snd then playCopy(snd, o.part) end
				if burst and FX_PARTICLE[name] then pcall(function() burst:Emit(1) end) end
			end
		end
	end

	-- testing: the frames playback went through since last time (fire sounds and the damage of the TAS)
	local replayedTo = nil
	local function replayEvents(data, f)
		if replayedTo == nil or f < replayedTo then replayedTo = f - 1 end
		if f - replayedTo > 600 then replayedTo = f - 1 end
		for i = replayedTo + 1, f do
			local fr = data[i]
			if fr and fr.KE then
				for _, e in ipairs(fr.KE) do
					if e[1] == 1 then
						local key = reg.idToKey[e[2]]
						for _, t in ipairs(turrets) do if t.key == key then playCopy(t.fireSnd, t.part) end end
					elseif e[1] == 2 and (e[3] or 0) > 0 then
						dealDamage(e[3])
					elseif e[1] == 4 then
						playFx(e[2], e[3])
					end
				end
			end
		end
		replayedTo = f
	end

	-- --------------------------------------------------------------------------------------------- pushboxes
	local spawners, spawnerOf = {}, {}
	local function boxParts(box)
		local list = {}
		if box:IsA("BasePart") then list[1] = box end
		for _, d in ipairs(box:GetDescendants()) do if d:IsA("BasePart") then list[#list + 1] = d end end
		return list
	end
	local function hideBox(s)
		if s.hidden or not (s.box and s.box.Parent) then return end
		s.hidden = {}
		for _, p in ipairs(boxParts(s.box)) do
			s.hidden[p] = { p.Transparency, p.CanCollide, p.CanTouch, p.CanQuery }
			pcall(function() p.Transparency = 1; p.CanCollide = false; p.CanTouch = false; p.CanQuery = false end)
		end
	end
	local function unhideBox(s)
		if not s.hidden then return end
		for p, v in pairs(s.hidden) do
			if p.Parent then pcall(function() p.Transparency = v[1]; p.CanCollide = v[2]; p.CanTouch = v[3]; p.CanQuery = v[4] end) end
		end
		s.hidden = nil
	end
	local function addSpawner(cfg)
		local model = cfg.Parent
		if not (model and model:IsA("Model")) or spawnerOf[model] then return end
		local key = ClientObjects.KeyOf(model)
		if not key then return end
		local s = { model = model, cfg = cfg, key = key, id = idFor(key), conns = {}, box = nil, boxF = nil }
		s.box = model:FindFirstChild("Pushbox")
		s.conns[#s.conns + 1] = model.ChildAdded:Connect(function(child)
			if child.Name ~= "Pushbox" then return end
			unhideBox(s)
			s.box = child
			s.boxF = nil
			if cur.on and cur.data then
				if cur.rec and #cur.data > 0 then
					s.boxF = #cur.data
					addEvent(cur.data[#cur.data], { 3, s.id, 1 })
					local I = index(cur.data)
					if not I.firstSpawn[s.id] or I.firstSpawn[s.id] > s.boxF then I.firstSpawn[s.id] = s.boxF end
				elseif cur.mode == 3 then
					s.boxF = cur.f
				end
			end
		end)
		spawnerOf[model] = s
		spawners[#spawners + 1] = s
		s.conns[#s.conns + 1] = model.AncestryChanged:Connect(function()
			if model:IsDescendantOf(workspace) then return end
			for _, c in ipairs(s.conns) do c:Disconnect() end
			spawnerOf[model] = nil
			for i = #spawners, 1, -1 do if spawners[i] == s then table.remove(spawners, i) end end
		end)
	end
	-- a spawn (or "there at the start") of this spawner is saved on frame f or before
	local function spawnedBy(data, s, f)
		local first = index(data).firstSpawn[s.id]
		return first ~= nil and first <= f
	end
	local function boxesAt(data, f)
		for _, s in ipairs(spawners) do
			if s.box and not s.box.Parent then s.box, s.boxF = nil, nil end
			if s.box and s.boxF and s.boxF > f and not spawnedBy(data, s, f) then hideBox(s) else unhideBox(s) end
		end
	end

	-- --------------------------------------------------------------------------------------------- character forces
	local FORCE = { LinearVelocity = true, VectorForce = true, AngularVelocity = true, AlignPosition = true,
		AlignOrientation = true, LineForce = true, Torque = true, BodyVelocity = true, BodyForce = true, BodyThrust = true,
		BodyPosition = true, BodyGyro = true, BodyAngularVelocity = true }
	local forces = setmetatable({}, { __mode = "k" }) -- force -> frame it was added on (recording) or false
	local charConn
	local function watchCharacter(ch)
		if charConn then charConn:Disconnect(); charConn = nil end
		if not ch then return end
		charConn = ch.DescendantAdded:Connect(function(d)
			if not FORCE[d.ClassName] then return end
			if cur.on and cur.rec and cur.data then forces[d] = #cur.data else forces[d] = false end
			if cur.on and cur.mode == 3 then pcall(function() d.Enabled = false end) end
		end)
	end

	-- --------------------------------------------------------------------------------------------- finding objects
	local CONFIGS = { BeatBlockConfiguration = addBeat, TurretConfiguration = addTurret, PushboxSpawnConfiguration = addSpawner,
		BouncePadConfiguration = addFx, LauncherConfiguration = addFx }
	local TAGS = { ["CO_Visual/BeatBlock"] = addBeat, ["CO_Interactables/Turret"] = addTurret,
		["CO_Interactables/PushboxSpawn"] = addSpawner, ["CO_Interactables/BouncePad"] = addFx,
		["CO_Interactables/JumpLauncher"] = addFx }

	local function consider(inst, kitTables)
		local add = CONFIGS[inst.Name]
		if not add and CS then
			for tag, f in pairs(TAGS) do
				if inst:HasTag(tag) then add = f break end
			end
		end
		if add then
			if add == addBeat then add(inst, kitTables) else add(inst) end
		end
	end

	local function scanAll()
		local kitTables = kitBeatTables()
		local seen = {}
		if CS then
			for tag in pairs(TAGS) do
				local ok, list = pcall(CS.GetTagged, CS, tag)
				if ok then
					for _, inst in ipairs(list) do
						if inst:IsDescendantOf(workspace) and not seen[inst] then seen[inst] = true; consider(inst, kitTables) end
					end
				end
			end
		end
		local cp = workspace:FindFirstChild("ClientParts")
		for _, d in ipairs((cp or workspace):GetDescendants()) do
			if CONFIGS[d.Name] and not seen[d] then seen[d] = true; consider(d, kitTables) end
		end
	end

	-- --------------------------------------------------------------------------------------------- the frame
	local enabled = false

	local function release()
		if cur.on then
			cur.on = false
			for _, g in ipairs(beats) do g.driving = false; g.lastKey = nil; g.lastCycle = nil end
			hideAllBullets()
			for _, s in ipairs(spawners) do unhideBox(s) end
			unmuteAll()
		end
		replayedTo = nil
	end
	KO.Release = release

	function KO.Invalidate()
		idx.valid = false
	end

	-- every PreRender after the frame was recorded. mode: 1 Idle, 2 Create, 3 Test; f / t: the frame shown and
	-- its TAS time (testing: the playback time); rec: frame f is being recorded now
	function KO.Frame(mode, data, f, t, rec)
		cur.mode, cur.data, cur.f, cur.t, cur.rec = mode, data, f, t, rec
		if not enabled or (mode ~= 2 and mode ~= 3) or not data then release() return end
		if rec and rawget(data, "KitVersion") == nil then data.KitVersion = KO.VersionOf(data) end
		if KO.VersionOf(data) < 1 or not Settings.On("Sync Kit Objects") then release() return end
		if not cur.on then
			cur.on = true
			for _, g in ipairs(beats) do mute(g.ding); g.dirty = true end
			for _, tt in ipairs(turrets) do mute(tt.fireSnd) end
			replayedTo = nil
		end
		local advancing = rec or (mode == 3)
		if rec and #data == 1 then
			-- a box that is already there when the TAS starts (so it isn't hidden before a later spawn)
			for _, s in ipairs(spawners) do
				if s.box and s.box.Parent and not spawnedBy(data, s, 1) then
					addEvent(data[1], { 3, s.id, 0 })
					index(data).firstSpawn[s.id] = 1
				end
			end
		end
		beatStep(t, advancing)
		showBullets(data, f, t)
		boxesAt(data, f)
		if mode == 3 then replayEvents(data, f) end
	end

	-- every Heartbeat while recording, after the frame got its character state: the bullets' hits
	function KO.AfterPhysics(data, n)
		if not (enabled and cur.on and cur.rec and data and data[n]) then return end
		turretHits(data, n)
	end

	-- before the physics step and at the end of the render step: what the kit (or anything else) wrote since
	-- is undone. Only groups a write touched since are looked at (their change signals mark them dirty; Roblox
	-- fires those signals a little later, still before the next render step / physics step)
	function KO.Reassert()
		if not (enabled and cur.on) or #beats == 0 then return end
		beatStep(cur.t, false)
	end

	-- unpausing at frame f: forces a kit script put on the character after f belong to the cut frames
	function KO.Unpause(data, f)
		for d, fr in pairs(forces) do
			if fr and fr > f then
				forces[d] = nil
				pcall(function() d:Destroy() end)
			end
		end
		idx.valid = false
	end

	-- ------------------------------------------------------------------------------------- save / load
	function KO.Export(frames)
		local used = {}
		for _, fr in ipairs(frames) do
			if fr.KE then
				for _, e in ipairs(fr.KE) do
					if e[1] == 1 or e[1] == 3 or e[1] == 4 then used[e[2]] = true end
				end
			end
		end
		local keys = {}
		for id in pairs(used) do keys[#keys + 1] = { id = id, key = reg.idToKey[id] or "" } end
		table.sort(keys, function(a, b) return a.id < b.id end)
		return { version = KO.VersionOf(frames), keys = keys }
	end
	-- ids inside a file belong to the session that saved it: translate them to this session's
	function KO.Import(frames, kit)
		if not kit then frames.KitVersion = 0 return end
		frames.KitVersion = kit.version or 0
		local map = {}
		for _, k in ipairs(kit.keys or {}) do map[k.id] = idFor(k.key) end
		for _, fr in ipairs(frames) do
			if fr.KE then
				for _, e in ipairs(fr.KE) do
					if (e[1] == 1 or e[1] == 3 or e[1] == 4) and map[e[2]] then e[2] = map[e[2]] end
				end
			end
		end
		idx.valid = false
	end

	function KO.Counts()
		local live = 0
		for _ in pairs(shown) do live = live + 1 end
		return #beats, #turrets, #spawners, live
	end

	function KO.Enable()
		if enabled then return end
		enabled = true
		pcall(scanAll)
	end
	function KO.Disable()
		if not enabled then return end
		release()
		enabled = false
	end

	function KO.Start()
		on(workspace.DescendantAdded, function(d)
			if CONFIGS[d.Name] then
				task.defer(function()
					if d.Parent then pcall(consider, d, (d.Name == "BeatBlockConfiguration") and kitBeatTables() or nil) end
				end)
			end
		end)
		if LocalPlayer.Character then watchCharacter(LocalPlayer.Character) end
		on(LocalPlayer.CharacterAdded, watchCharacter)
		if Settings.On("Sync Kit Objects") then KO.Enable() end
		Settings.Changed("Sync Kit Objects", function(v)
			if v ~= 0 then KO.Enable() else KO.Disable() end
		end)
		Janitor.add(function()
			KO.Disable()
			if charConn then charConn:Disconnect() end
			for _, g in ipairs(beats) do for _, c in ipairs(g.conns) do c:Disconnect() end end
			for _, t in ipairs(turrets) do for _, c in ipairs(t.conns) do c:Disconnect() end end
			for _, s in ipairs(spawners) do for _, c in ipairs(s.conns) do c:Disconnect() end end
			for _, o in ipairs(fxObjects) do for _, c in ipairs(o.conns) do c:Disconnect() end end
			if holder then pcall(function() holder:Destroy() end) end
		end)
	end
end
