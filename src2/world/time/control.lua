-- ================================================================================================
--  TIME CONTROL  (HappaTAS 3 world plugin, order 57): the speed hack, slow / fast motion while recording in
--  Create mode (V2.38.17 p16_speedhack.lua, both blocks function by function; the other systems are reached
--  through the engine: E.co, E.kitClock, E.anim, E.settings).
--  While a TAS is recorded (Create mode, unpaused) the game runs at s times its normal speed (s = "Speed Hack
--  Speed", 0.1 - 1: slow motion only), like a video played slower: Frame Step (below). No value is scaled:
--  Roblox's normal physics runs on some steps and everything is held for the others, the humanoid itself too
--  (frozen: its state machine and timers stand still), so every step that runs is Roblox's own physics and
--  nothing runs in real time. Each recorded frame stores the simulated time of its step, so the TAS is in normal
--  time and Test plays it at normal speed. (Fast motion above 1x, which scaled gravity, walking, jumps, the world
--  and the humanoid's controllers, was taken out: it could only be close, never exact.)
--  The coyote timer (the second block, SH.Humanoid) is kept with each frame and runs on the game clock again
--  after a pause.
-- ================================================================================================
local Env = import("platform/env")
local Util = import("engine/util")

local Players = Env.svc("Players")
local engine = nil -- (the engine, set by TimeControl.new)
local SpeedHack = {}
local function clampn(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

do
	local SH = SpeedHack
	SH.scale = 1 -- the factor the physics is scaled by (always 1: nothing is scaled since fast motion went)
	SH.anim = 1  -- how fast the TAS clock runs against real time (animations, the camera's zoom spring)
	-- the parts to look at: HappaTAS's client objects, or the EToH kit's ClientParts folder without them
	local function eachWorldPart(fn)
		if engine.co:isReady() then
			engine.co:eachPart(fn)
			return
		end
		local cp = workspace:FindFirstChild("ClientParts")
		if cp then
			for _, d in ipairs(cp:GetDescendants()) do
				if d:IsA("BasePart") then fn(d) end
			end
		end
	end
	local function charOf(p)
		local ch = Players.LocalPlayer and Players.LocalPlayer.Character
		return ch ~= nil and p:IsDescendantOf(ch)
	end

	-- the factor the settings ask for (1 = off)
	function SH.Wanted()
		if not engine.settings:on("speedHack") then return 1 end
		local s = clampn(tonumber(engine.settings:get("speedHackSpeed")) or 0.5, 0.1, 1) -- (slow motion only)
		if math.abs(s - 1) < 0.001 then return 1 end
		return s
	end

	local function rescaleAnimations()
		engine.anim.physScale = SH.scale
		engine.anim:rescale()
	end
	local function setAnim(k)
		if SH.anim == k then return end
		SH.anim = k
		engine.anim.rate = k
		rescaleAnimations()
	end

	-- ----------------------------------------------------------------------------------------- frame step
	-- "Speed Hack Frame Step" (speeds below 1): no scaling at all. Roblox runs its normal physics on some
	-- frames only, and everything that moves is held still for the physics step of the frames in between
	-- (by time, adapted from Eternal Obbying's fixed-step loop, Client/Session.lua: acc += real dt x s, a step
	-- runs when acc holds the time it simulates; counting events instead ran 0.5x at 0.25x when frames had 1 and 3
	-- physics steps in turn). Only frames whose physics step ran are recorded, each with the simulated time of that step,
	-- so walking, jumping and falling are exactly normal-speed physics (checked in the client: same heights,
	-- states and times), and a platform you push yourself (the kit's Pushing Platform) speeds up at the normal
	-- rate (~158 stud/s^2), which the scaling above can't do (Roblox's walking force can't be slowed). A loose
	-- part the character pushes or stands on is held with it like everything else. (Before the humanoid was
	-- frozen with the held steps that broke their contact, 0.42 studs pushed by 0.3 s at 0.5x against 3.5 - 4.9
	-- at 1x, so every step ran while they touched: full speed on any loose platform. Frozen, live at 0.25x and
	-- 0.1x: the kit's Pushing Platform 2.4 - 5.1 studs by 0.3 s in 12 runs, none stalled, against 2.2 - 5.1 and
	-- 2 stalls in 8 runs at 1x; the push starts at 0.07 s as at 1x, in half of the runs at 0.10 - 0.14 s; standing
	-- on the kit's Falling Platform it sinks at the same rate.)
	-- Held = the character's root and every free assembly of the world's parts anchored from PreSimulation to
	-- PostSimulation of that frame, then put back with the velocities they had: outside the physics step
	-- nothing is held, so pausing, testing and Idle never see it. The kit's clock moves on by each step that ran
	-- (KitClock.Advance), the client objects' physics clock skips the held steps (ClientObjects.SkipSim).
	-- The humanoid is frozen with the held steps: Humanoid.EvaluateStateMachine off for them. Anchored alone, it
	-- kept its own timers running in real time (live: no coyote jump even 0.05 s after the edge at 0.1x, Landed over
	-- in 49 ms of real time whatever the speed), so every step of a jump's push, of Landed and of the coyote time
	-- used to be run at full speed: a stall and a snap before each landing. Roblox works the humanoid out (state
	-- machine, timers, the walking / floor / jump forces) between PreAnimation and PreSimulation (live: switched on
	-- only from PreRender to PreSimulation the character stands, switched off there it sinks 2 studs; switched off
	-- only from PreAnimation to PreSimulation of the held frames its timers stand still), so whether the next step
	-- runs is decided at the start of PreRender (planStep, from SH.FrameStart) with the last step's time as the
	-- guess for the next one's, the humanoid is frozen at PreAnimation and let go again at PreSimulation. Only that
	-- long: a frozen humanoid's GetState() says Jumping whatever its state is (live).
	-- A new frame is made and filled only on a frame whose step runs (SH.StepTime), right before that step, as
	-- every frame is at 1x: its state and animation are what Roblox worked out for that step (made on the first
	-- held frame after the step before, they were one frame old: live, Freefall and Landed came a frame late), and
	-- the keys pressed and let go while the steps were held are in it.
	-- Live, a jump at 0.1x and 0.25x: Running > Jumping > Freefall > Landed > Running at the same game times as at
	-- 1x (Landed 50 ms, 7.27 studs high, 0.26 studs of sink), with every held step held. A jump tapped while the
	-- steps are held is made on the next step that runs (the game's control script writes Humanoid.Jump from the
	-- key every frame: a short tap was gone again).
	local FS = { on = false, s = 1, acc = 0, pending = 0, ranDt = 0, held = false, n = 0, saved = {}, parts = {}, scanIn = 0,
		root = nil, hum = nil, plan = nil, est = nil, frozen = nil, latch = false }
	SH.FS = FS

	-- ---------------------------------------------------------------------------------------- smooth view
	-- Frame Step shows the same picture on every held frame: at 0.25x the world moves on one frame in four, so
	-- slow motion looks choppy at any frame rate. The smooth view ("Smooth Slow Motion") draws the frames in
	-- between, the way a game with fixed physics steps draws its frames: the picture is the world a short, fixed
	-- game time ago (SV.lag), on the way between the real poses the last steps left. The game time shown moves on
	-- with the real time x the slider on every frame (it is the time bank: the simulated time + FS.acc), so the
	-- picture moves on every frame at the game's own speed x the slider, whichever frames ran a step and whether
	-- a frame's step simulated 1/240 s or 2/240 s. (Live at 165 frames a second both happen in turn. A first
	-- version that went from one step's pose to the next by the bank alone moved on 74 % of the frames at 0.25x
	-- and 50 % at 0.1x, in jumps of up to a whole step.)
	-- What is drawn there: the character's root, the loose parts that moved in the last steps, and the camera (by
	-- what the root's picture is off its real place).
	-- Only the picture: the camera goes there in PreRender before the interface's Frost places its panes by it, the
	-- parts at the very end of PreRender, after everything of HappaTAS read the real poses, and at PreAnimation, the
	-- first thing after the picture was drawn, everything is back. Roblox works the humanoid out after that and
	-- the physics step comes after that; nothing was simulated in between, and a frame is recorded from the real
	-- poses. (A frame without a physics step has no PreAnimation, live: there everything is back at Heartbeat, and
	-- in any case before the next picture is worked out.) A part somebody else moved while its picture was up (a
	-- teleport) stays where they put it, and a move too long for one step isn't glided over: the picture is on the
	-- new place at once.
	-- Shift lock: Roblox turns a shift locked character to the camera after each frame is drawn, before
	-- PreAnimation, outside the physics step (live: with UserGameSettings.RotationType CameraRelative the Y angle of
	-- the root's orientation becomes the camera's there, a tilt - its X and Z angles - is kept). That turn lands on
	-- the picture. Put back with the picture it was lost on every frame, and the body followed the camera only by
	-- the slow turn of a character that isn't shift locked (found in a recording: up to 95 degrees behind; live,
	-- walking at 0.1x: off the camera on 183 of 216 frames, none with the smooth view off). So a part turned while
	-- its picture was up keeps the turn on its real pose (the Y angle when only that changed, else the whole
	-- rotation), and while the rotation type is CameraRelative the root's picture has the real pose's Y angle: the
	-- picture's body faces the camera on every frame as it does at 1x, and a turn of the picture is exactly the
	-- turn the real pose would have got.
	local UserGameSettings = nil
	pcall(function() UserGameSettings = UserSettings():GetService("UserGameSettings") end)
	local TURNED = 1e-4 -- (the look or up vector moved by more than this: the part was turned)
	local function turned(a, b)
		return (a.LookVector - b.LookVector).Magnitude > TURNED or (a.UpVector - b.UpVector).Magnitude > TURNED
	end
	local HIST = 4 -- (real poses kept: the picture's time is never more than 3 steps back)
	local RING = 16 -- (step times the lag is taken from)
	-- rp / ht: the root's real poses and their game times, a ring (head = the newest, hn = how many count);
	-- T: the game time simulated so far; D: the game time shown; ents[part] = { p = part, [1 .. HIST] = its poses in
	-- the same ring, still = steps since it last moved, at = the push it was last seen in }
	local SV = { root = nil, rp = {}, ht = {}, head = 1, hn = 0, T = 0, D = nil, stepped = false, pushN = 0,
		go = false, pose = nil, a = 1, b = 1, f = 0,
		ents = setmetatable({}, { __mode = "k" }), moving = {}, nMoving = 0, shown = {}, nShown = 0, cam = nil, camT = {},
		dts = {}, di = 0, lag = 1 / 240 }
	SH.SV = SV
	local SAME = 0.01 -- (studs: a part within this of where its picture was put is still on its picture)
	local JUMP = 1 -- (studs: a move this long that no physics step made is a teleport)
	-- (a step that took a part further than 600 studs a second would, or 2 studs: a teleport inside the step.
	-- Live, a 9.7 stud teleport slid across the screen for 14 frames at 0.1x when this said 10 studs)
	local function tooFar(a, b)
		return (a.Position - b.Position).Magnitude > math.max(2, 600 * (FS.est or 1 / 240))
	end
	local function off(a, b) -- (worth drawing elsewhere: not the same place or facing)
		return (a.Position - b.Position).Magnitude > 1e-5 or (a.LookVector - b.LookVector).Magnitude > 1e-4
	end
	local function smoothReset()
		SV.root, SV.head, SV.hn, SV.T, SV.D, SV.stepped, SV.go, SV.pose = nil, 1, 0, 0, nil, false, false, nil
		SV.nMoving, SV.di, SV.lag, SV.clock = 0, 0, 1 / 240, nil
		table.clear(SV.rp)
		table.clear(SV.ht)
		table.clear(SV.dts)
		table.clear(SV.moving)
		table.clear(SV.ents)
	end
	-- every physics step's time (held or run): the lag is the longest step of the last RING, at most twice the
	-- shortest (one long frame doesn't hold the picture back). The bank is never more than that ahead of the
	-- simulated time, so the time shown is never ahead of the newest real pose
	local function smoothDt(dt)
		local dts = SV.dts
		local i = SV.di % RING + 1
		SV.di = i
		dts[i] = dt
		local lo, hi = dt, dt
		for k = 1, #dts do
			local v = dts[k]
			if v < lo then lo = v elseif v > hi then hi = v end
		end
		SV.lag = math.min(hi, 2 * lo)
	end
	-- everything drawn elsewhere is back on its real pose (PreAnimation, and wherever Frame Step ends)
	local function smoothRestore()
		local n = SV.nShown
		local c = SV.cam
		if n == 0 and not c then return end
		SV.nShown, SV.cam = 0, nil
		local shown = SV.shown
		for i = 1, n do
			local e = shown[i]
			local p, real, pic = e[1], e[2], e[3]
			e[1], e[2], e[3] = nil, nil, nil
			pcall(function()
				if not p.Parent then return end
				local cur = p.CFrame
				if (cur.Position - pic.Position).Magnitude > SAME then return end -- (moved by somebody else: theirs)
				if turned(cur, pic) then
					-- (turned while its picture was up: the real pose gets the turn, see "Shift lock" above)
					local cx, cy, cz = cur:ToOrientation()
					local px, _, pz = pic:ToOrientation()
					if math.abs(cx - px) < TURNED and math.abs(cz - pz) < TURNED then
						local rx, _, rz = real:ToOrientation()
						real = CFrame.new(real.Position) * CFrame.fromOrientation(rx, cy, rz)
					else
						real = CFrame.new(real.Position) * cur.Rotation
					end
				end
				p.CFrame = real
			end)
		end
		if c then
			pcall(function()
				local cam = c[1]
				if (cam.CFrame.Position - c[4]).Magnitude <= SAME then
					cam.CFrame = c[2]
					cam.Focus = c[3]
				end
			end)
			c[1], c[2], c[3], c[4] = nil, nil, nil, nil
		end
	end
	-- a step ran: the loose parts' real poses join the ring; the ones that moved in the last steps are the ones
	-- to draw
	local function smoothParts(head, was)
		local parts, ents, moving, m = FS.parts, SV.ents, SV.moving, 0
		local push = SV.pushN + 1
		SV.pushN = push
		for i = 1, #parts do
			local p = parts[i]
			local cf = p.CFrame
			local e = ents[p]
			if not e then
				e = { p = p, still = HIST, at = push }
				for k = 1, HIST do e[k] = cf end
				ents[p] = e
			else
				local last = e[was]
				if e.at ~= push - 1 or tooFar(last, cf) then
					-- (not seen at the step before, or moved too far for one step: nothing to glide from)
					for k = 1, HIST do e[k] = cf end
					e.still = HIST
				else
					e[head] = cf
					if cf ~= last then e.still = 0 else e.still = e.still + 1 end
				end
				e.at = push
				if e.still < HIST - 1 then
					m = m + 1
					moving[m] = e
				end
			end
		end
		for i = m + 1, SV.nMoving do moving[i] = nil end
		SV.nMoving = m
	end
	-- PreRender, before the interface's Frost: the real poses are taken (root: every frame; loose parts: after a
	-- step that ran), the picture's game time and place are worked out and the camera goes there
	local function smoothPlan()
		SV.go, SV.pose = false, nil
		-- (a second look, should a frame ever come without a Heartbeat too: a picture is never taken for the real
		-- pose. Live, a frame without a physics step left the last one up, the next frame read it as the root's
		-- place and a jump came out 0.07 - 0.26 studs lower)
		if SV.nShown > 0 or SV.cam then smoothRestore() end
		local root = FS.root
		if not FS.on or FS.acc == nil or not (root and root.Parent) or not engine.settings:on("smoothSlowMotion") then
			if SV.root then smoothReset() end
			SV.stepped = false
			return
		end
		local now = root.CFrame
		local stepped = SV.stepped
		SV.stepped = false
		local rp, ht = SV.rp, SV.ht
		local head = SV.head
		if root ~= SV.root then
			local T = SV.T
			smoothReset()
			SV.root, SV.T, SV.hn = root, T, 1
			head = 1
			rp[1], ht[1] = now, T
		elseif stepped then
			local was = head
			head = head % HIST + 1
			SV.head = head
			rp[head], ht[head] = now, SV.T
			if tooFar(rp[was], now) then
				SV.hn, SV.D = 1, nil -- (a teleport: nothing to glide from)
			else
				SV.hn = math.min(SV.hn + 1, HIST)
			end
			smoothParts(head, was)
		elseif now ~= rp[head] then
			-- (moved without a step, by the game: a turn or a nudge glides on, a teleport doesn't)
			local moved = (now.Position - rp[head].Position).Magnitude
			rp[head] = now
			if moved > JUMP then SV.hn, SV.D = 1, nil end
		end
		local hn = SV.hn
		local T = ht[head]
		-- the time shown runs on its own clock: real time x the slider on every frame, 50 - 150 % of that to
		-- close in on where it should be (the bank, which only moves on when a step runs, minus the lag). Live at
		-- 0.1x and 240 FPS, following the bank itself stood the picture still on each frame without a step and
		-- doubled the next, and every change of the lag (one step's time or two) jumped it a whole step or held it
		-- for about ten frames
		local nowC = os.clock()
		local rdt = SV.clock and math.max(0, nowC - SV.clock) or 0
		SV.clock = nowC
		local target = T + FS.acc - 1.5 * SV.lag -- (half a step's margin: the picture doesn't catch the real pose up)
		local D = target
		if SV.D then
			local err = target - SV.D
			if err > 6 * SV.lag or err < -6 * SV.lag then
				D = target -- (far off: a reset or a long gap)
			else
				local c = err / (4 * SV.lag)
				if c > 0.5 then c = 0.5 elseif c < -0.5 then c = -0.5 end
				D = SV.D + rdt * FS.s * (1 + c)
			end
		end
		if SV.D and D < SV.D then D = SV.D end -- (never back)
		if D >= T or hn < 2 then
			SV.D = math.min(D, T) -- (the picture is the real pose)
			return
		end
		SV.D = D
		-- the two real poses the time shown lies between (before the oldest one kept: on it)
		local b = head
		local a = (b - 2) % HIST + 1
		local k = 1
		while D < ht[a] and k < hn - 1 do
			b = a
			a = (a - 2) % HIST + 1
			k = k + 1
		end
		local ta, tb = ht[a], ht[b]
		local f = (tb > ta) and (D - ta) / (tb - ta) or 1
		if f < 0 then f = 0 end
		SV.a, SV.b, SV.f, SV.go = a, b, f, true
		local pa, pb = rp[a], rp[b]
		local pose = (pa == pb or f <= 0) and pa or pa:Lerp(pb, f)
		-- (shift locked: the body faces where the real one does, see "Shift lock" above)
		if UserGameSettings and UserGameSettings.RotationType == Enum.RotationType.CameraRelative then
			local x, _, z = pose:ToOrientation()
			local _, y = now:ToOrientation()
			pose = CFrame.new(pose.Position) * CFrame.fromOrientation(x, y, z)
		end
		if not off(pose, now) then return end -- (the character stands where its picture is: loose parts may not)
		SV.pose = pose
		local d = pose.Position - now.Position
		local cam = workspace.CurrentCamera
		if cam and d.Magnitude > 1e-5 then
			local c0, f0 = cam.CFrame, cam.Focus
			local to = c0 + d
			local c = SV.camT
			c[1], c[2], c[3], c[4] = cam, c0, f0, to.Position
			SV.cam = c
			cam.CFrame = to
			cam.Focus = f0 + d
		end
	end
	-- the end of PreRender: the picture's poses are written
	local function smoothShow()
		if not SV.go then return end
		SV.go = false
		local shown, n = SV.shown, SV.nShown
		local head = SV.head
		local root, pose = SV.root, SV.pose
		if pose and root and root.Parent then
			n = n + 1
			local e = shown[n]
			if not e then e = {}; shown[n] = e end
			e[1], e[2], e[3] = root, SV.rp[head], pose
			SV.nShown = n
			root.CFrame = pose
		end
		local a, b, f = SV.a, SV.b, SV.f
		local moving = SV.moving
		for i = 1, SV.nMoving do
			local m = moving[i]
			local p = m.p
			local now = p.CFrame
			if now ~= m[head] then
				-- (the game moved it itself since the step: a nudge glides on, a teleport doesn't)
				if (now.Position - m[head].Position).Magnitude > JUMP then
					for k = 1, HIST do m[k] = now end
					m.still = HIST
				else
					m[head] = now
				end
			elseif p.Parent then
				local pa, pb = m[a], m[b]
				local to = (pa == pb or f <= 0) and pa or pa:Lerp(pb, f)
				if off(to, now) then
					n = n + 1
					local e = shown[n]
					if not e then e = {}; shown[n] = e end
					e[1], e[2], e[3] = p, now, to
					SV.nShown = n
					p.CFrame = to
				end
			end
		end
	end

	local function setFrozen(on)
		local f = FS.frozen
		if on then
			local h = FS.hum
			if f == h then return end
			if f then
				FS.frozen = nil
				pcall(function() f.EvaluateStateMachine = true end)
			end
			pcall(function()
				-- (a game that switched it off itself: left alone)
				if h and h.Parent and h.EvaluateStateMachine ~= false then
					h.EvaluateStateMachine = false
					FS.frozen = h
				end
			end)
		elseif f then
			FS.frozen = nil
			pcall(function() f.EvaluateStateMachine = true end)
		end
	end
	-- the start of PreSimulation (before the frame is filled) and the end of the step: the humanoid is let go
	function SH.Thaw()
		if SV.nShown > 0 or SV.cam then smoothRestore() end -- (a frame PreAnimation didn't come for)
		if FS.frozen then setFrozen(false) end
	end
	local function collectStepParts()
		local list, done = {}, {}
		eachWorldPart(function(p)
			if p.Anchored or charOf(p) then return end
			local rootP = p.AssemblyRootPart or p
			if done[rootP] or rootP.Anchored then return end
			done[rootP] = true
			list[#list + 1] = rootP
		end)
		FS.parts = list
	end
	local function hold(p)
		local n = FS.n + 1
		local e = FS.saved[n]
		if not e then e = {}; FS.saved[n] = e end
		e[1], e[2], e[3] = p, p.AssemblyLinearVelocity, p.AssemblyAngularVelocity
		p.Anchored = true
		FS.n = n
	end
	-- the start of PreRender: does this frame's step run, by the time bank with the last step's time as the guess
	-- for its own (acc == nil: the first step runs); the humanoid is frozen for a held one at PreAnimation
	local function planStep()
		local est = FS.est or (1 / 240)
		local run = FS.acc == nil or FS.acc + FS.s * est >= est - 1e-9
		FS.plan = run
		local h = FS.hum
		if run then
			setFrozen(false)
			if FS.latch and h then pcall(function() h.Jump = true end) end
		elseif h and not FS.latch then
			local okJ, j = pcall(function() return h.Jump end)
			if okJ and j then FS.latch = true end
		end
	end
	-- PreSimulation (after the frame was filled): true = this physics step runs, false = everything is held for
	-- it. dt = the time the step simulates
	function SH.StepBegin(dt)
		if not FS.on then return true end
		dt = tonumber(dt) or 0
		if dt > 0 then
			FS.est = dt
			smoothDt(dt)
		end
		if FS.acc == nil then FS.acc = dt else FS.acc = FS.acc + FS.s * dt end -- (the first step runs)
		-- (as planned: the humanoid was frozen or let go for exactly that. No plan yet: it runs)
		if FS.plan ~= false then
			-- (a step that took more than the bank held, its time was a guess, is paid back: the game time follows the
			-- slider)
			FS.acc = FS.acc - dt
			FS.latch = false
			SV.stepped, SV.T = true, SV.T + dt
			FS.pending = FS.pending + dt
			FS.ranDt = FS.ranDt + dt
			FS.frameDt = dt
			engine.kitClock:advance(dt)
			return true
		end
		FS.scanIn = FS.scanIn - 1
		if FS.scanIn <= 0 then
			FS.scanIn = 30
			local ok, err = pcall(collectStepParts)
			if not ok then engine.errs:report("speed hack frame step", err) end
		end
		FS.n = 0
		FS.held = true
		local root = FS.root
		if root and root.Parent and not root.Anchored then pcall(hold, root) end
		local parts = FS.parts
		for i = 1, #parts do
			local p = parts[i]
			if p.Parent and not p.Anchored then pcall(hold, p) end
		end
		engine.co:skipSim(dt)
		return false
	end
	-- PostSimulation: the held parts go on as they were
	function SH.StepEnd()
		-- (a frame with no physics step has no PreAnimation and no PreSimulation, live: 2 frames in 1980 at 165 FPS)
		if SV.nShown > 0 or SV.cam then smoothRestore() end
		if FS.frozen then setFrozen(false) end -- (a frame with no physics step: no PreSimulation let it go)
		if not FS.held then return end
		FS.held = false
		for i = 1, FS.n do
			local e = FS.saved[i]
			local p = e[1]
			e[1] = nil
			if p and p.Parent then
				pcall(function()
					p.Anchored = false
					p.AssemblyLinearVelocity = e[2]
					p.AssemblyAngularVelocity = e[3]
				end)
			end
		end
		FS.n = 0
	end
	-- the recording takes the simulated time of the step that ran since its last frame, on a frame whose own step
	-- runs (0 = no new frame now; nil = not frame stepping)
	function SH.StepTime()
		if not FS.on then return nil end
		if FS.plan == false then return 0 end
		local t = FS.pending
		FS.pending = 0
		return t
	end
	function SH.Stepping() return FS.on end
	-- the time the physics step of this frame simulated while frame stepping (0 = held, or no step yet: the core
	-- calls SH.FrameStart in PreRender)
	function SH.StepDt() return FS.frameDt or 0 end
	function SH.FrameStart()
		FS.frameDt = 0
		if FS.on then planStep() end
	end
	-- the game time the animations move on by this frame (Heartbeat): the real dt x the factor, or with Frame Step
	-- exactly the time of the physics step that ran (0 when everything was held)
	function SH.GameDt(dt)
		if not FS.on then return dt * SH.anim end
		local d = FS.ranDt
		FS.ranDt = 0
		return d
	end
	local function stopStep()
		if not FS.on then return end
		if FS.addConn then FS.addConn:Disconnect(); FS.addConn = nil end
		if FS.freezeConn then FS.freezeConn:Disconnect(); FS.freezeConn = nil end
		if FS.viewOff then
			for _, off in ipairs(FS.viewOff) do off() end
			FS.viewOff = nil
		end
		SH.StepEnd() -- (the pictures off, the humanoid let go, the held parts on their way)
		smoothReset()
		setFrozen(false)
		FS.on, FS.pending, FS.ranDt, FS.root, FS.hum, FS.parts = false, 0, 0, nil, nil, {}
		FS.plan, FS.est, FS.latch = nil, nil, false
	end

	-- back to normal: Frame Step off, the animations at normal speed
	function SH.Restore()
		stopStep()
		setAnim(1)
	end

	-- once a frame, at the end of PreRender. active = the character records in Create mode (free and alive).
	-- Returns the factor the physics runs with (always 1: Frame Step scales nothing)
	function SH.Update(active, h, part)
		local s = 1
		if active and h and part then s = SH.Wanted() end
		if s == 1 then
			if FS.on or SH.anim ~= 1 then SH.Restore() end
			return 1
		end
		if not FS.on then
			FS.on, FS.pending, FS.ranDt, FS.scanIn = true, 0, 0, 0
			FS.acc = nil -- (the first step runs)
			-- (a part the game adds, a pushbox or a bullet, is held from the next held step: the scan otherwise
			-- runs every 30 held steps, and the part moved at full speed until then)
			FS.addConn = workspace.DescendantAdded:Connect(function(d)
				if d:IsA("BasePart") then FS.scanIn = 0 end
			end)
			FS.freezeConn = Env.svc("RunService").PreAnimation:Connect(function()
				smoothRestore() -- (first: the humanoid and the physics get the real poses)
				if FS.on and FS.plan == false then setFrozen(true) end
			end)
			-- (the smooth view's two moments of PreRender, only while Frame Step is on: see "smooth view")
			FS.viewOff = {
				engine.pipe:add("PreRender", 205, "time.smoothCamera", smoothPlan, "time.smooth"),
				engine.pipe:add("PreRender", 1000, "time.smoothView", smoothShow, "time.smooth"),
			}
		end
		FS.s, FS.root, FS.hum = s, part, h
		setAnim(s)
		return 1
	end

end

do
	local SH = SpeedHack
	local HC = {}
	SH.Humanoid = HC
	local COYOTE = 0.13           -- s of game time after the floor is lost
	local GRACE = 0.125           -- s after the floor is lost before Running turns into Freefall
	HC.COYOTE = COYOTE
	local Air = Enum.Material.Air
	local JUMPING = Enum.HumanoidStateType.Jumping
	local FREEFALL = Enum.HumanoidStateType.Freefall
	local cy = { off = nil, jumped = false, restored = false, disabled = false, noFall = false } -- off = game time since the floor was lost
	HC.coyote = cy

	-- ------------------------------------------------------------------------------------------- coyote time
	-- Roblox's rule (V2.38.17, measured live): a jump from Running while the floor was lost <= COYOTE s ago,
	-- Running turns into Freefall GRACE s after it. Roblox times it in real time; after a pause the recording goes on
	-- with the time it had (CoyoteRestore), and from there this rule is the game's
	local function setFreefall(hum, on)
		if on then
			if cy.noFall then
				cy.noFall = false
				pcall(function() hum:SetStateEnabled(FREEFALL, true) end)
			end
		elseif not cy.noFall then
			cy.noFall = true
			pcall(function() hum:SetStateEnabled(FREEFALL, false) end)
		end
	end
	local function setJumping(hum, on)
		if on then
			if cy.disabled then
				cy.disabled = false
				pcall(function() hum:SetStateEnabled(JUMPING, true) end)
			end
		elseif not cy.disabled then
			cy.disabled = true
			pcall(function() hum:SetStateEnabled(JUMPING, false) end)
		end
	end
	-- the timer's state for a recorded frame (nil = on the floor)
	function HC.CoyoteState()
		if cy.off == nil then return nil end
		return { cy.off, cy.jumped and 1 or 0 }
	end
	-- unpausing from a recorded frame: its timer as it was
	function HC.CoyoteRestore(state)
		if type(state) == "table" then
			cy.off, cy.jumped, cy.restored = tonumber(state[1]) or 0, state[2] == 1, true
		else
			cy.off, cy.jumped, cy.restored = nil, false, false
		end
	end
	function HC.CoyoteReset(hum)
		cy.off, cy.jumped, cy.restored = nil, false, false
		if hum then
			setJumping(hum, true)
			setFreefall(hum, true)
		end
	end

	-- PreSimulation while recording: the coyote rule for the step that comes
	function HC.Pre(dt, hum, root)
		cy.vy0 = nil
		if not (hum and root and root.Parent) or root.Anchored then return end
		cy.vy0 = root.AssemblyLinearVelocity.Y
		local enforce = cy.restored
		cy.enforce = enforce
		if cy.off ~= nil and enforce then
			if hum:GetState() == JUMPING then cy.jumped = true end
			-- (the engine decides on a jump at the end of the step: the game's window then; a jump the engine
			-- would no longer make is made in HC.Post)
			setJumping(hum, (not cy.jumped) and cy.off + dt <= COYOTE)
			-- Running turns into Freefall GRACE seconds after the floor is lost, in game time too: not by the
			-- engine's real-time grace (HC.Post switches it, after the step's jump, like Roblox's state table)
			local st = hum:GetState()
			setFreefall(hum, not (st == Enum.HumanoidStateType.Running or st == Enum.HumanoidStateType.RunningNoPhysics))
		else
			if cy.disabled then setJumping(hum, true) end
			if cy.noFall then setFreefall(hum, true) end
		end
	end

	-- PostSimulation: the coyote timer moves on (recording)
	function HC.Post(dt, hum, root, recording)
		if not (recording and hum and root and root.Parent and not root.Anchored) then return end
		-- the floor is lost when gravity alone changed the vertical speed this frame (on something, the floor holds
		-- it): that frame exactly. FloorMaterial turns Air ~3.2 frames later, a fallback.
		local vy1 = root.AssemblyLinearVelocity.Y
		local gEff = workspace.Gravity
		local falling = cy.vy0 ~= nil and math.abs(vy1) > 1e-3
			and math.abs((vy1 - cy.vy0) + gEff * dt) < 0.05 * gEff * dt + 1e-3
		if hum.FloorMaterial ~= Air and not falling then
			if cy.off ~= nil then
				cy.off, cy.jumped, cy.restored = nil, false, false
				setJumping(hum, true)
				setFreefall(hum, true)
			end
			return
		end
		-- (lost during this frame: FloorMaterial turns Air on that frame too, measured)
		cy.off = (cy.off or 0) + dt
		if hum:GetState() == JUMPING then cy.jumped = true end
		-- the engine's own window is over (after a pause): a jump inside the game's window is made here, at the end
		-- of the step like the engine's own (only from Running, like Roblox's state table: once Running has turned
		-- into Freefall there is no jump)
		local stJ = hum:GetState()
		if cy.enforce and not cy.jumped and cy.off <= COYOTE and hum.Jump
			and (stJ == Enum.HumanoidStateType.Running or stJ == Enum.HumanoidStateType.RunningNoPhysics) then
			cy.jumped = true
			setJumping(hum, true)
			pcall(function() hum:ChangeState(JUMPING) end)
		end
		-- no jump on this step and the grace is over: Freefall (Roblox checks the jump first)
		stJ = hum:GetState()
		if cy.enforce and cy.off > GRACE and (stJ == Enum.HumanoidStateType.Running or stJ == Enum.HumanoidStateType.RunningNoPhysics) then
			setFreefall(hum, true)
			pcall(function() hum:ChangeState(FREEFALL) end)
		end
	end
end

-- ------------------------------------------------------------------------------------------------ the plugin
local SH = SpeedHack
local TimeControl = { name = "time", order = 57 }
TimeControl.__index = TimeControl

local function announce()
	local s = SH.Wanted()
	local text = "Speed Hack: Off"
	if s ~= 1 then
		-- (where it works: "Speed Hack In")
		local st = engine.settings
		local idle, create = st:has("speedHackModes", "Idle"), st:has("speedHackModes", "Create")
		local where = (idle and create and "in Idle and while recording") or (idle and "in Idle") or (create and "while recording")
		text = where and ("Speed Hack: " .. tostring(Util.round(s, 1000)) .. "x " .. where) or "Speed Hack: on, but no mode is ticked in Speed Hack In"
	end
	engine.modes:status(text, true)
end

function TimeControl.new(E)
	engine = E
	local self = setmetatable({ E = E, scale = 1, anim = 1, SH = SH }, TimeControl)
	E.tl:addColumn("v2SK", "list", 1, { key = "SK", keep = true })
	-- (the coyote timer at the start of each frame: in memory only, like V2)
	E.tl:addColumn("CY", "list", 1, { key = "CY", save = false })
	-- (the animations' game time: the real dt x the factor, or with Frame Step the time of the step that ran)
	E.anim.gameDt = function(_, dt) return SH.GameDt(dt) end
	E.life:own(E.settings:changed("speedHack", function() announce() end))
	-- (a slider drag changes the speed on every mouse move: the speed follows at once, the notification comes
	-- once the value has settled for SETTLE seconds, so a drag shows one)
	local SETTLE, token = 0.3, 0
	E.life:own(E.settings:changed("speedHackSpeed", function()
		token = token + 1
		local mine = token
		task.delay(SETTLE, function()
			if mine == token and not E.life.unloading and E.settings:on("speedHack") then announce() end
		end)
	end))
	E.life:own(E.settings:changed("speedHackModes", function()
		if E.settings:on("speedHack") then announce() end
	end))
	E.life:own(function() SH.Restore(); self:sync() end)
	return self
end

-- (the factors the engine and the animations read)
function TimeControl:sync()
	self.scale, self.anim = SH.scale, SH.anim
	local anim = self.E.anim
	anim.physScale, anim.rate = SH.scale, SH.anim
end

function TimeControl:wanted() return SH.Wanted() end
function TimeControl:update(recording, hum, root)
	local k = SH.Update(recording, hum, root)
	if SH.scale ~= self.scale or SH.anim ~= self.anim then self:sync() end
	return k
end
function TimeControl:restore()
	SH.Restore()
	self:sync()
end
function TimeControl:stepTime() return SH.StepTime() end
function TimeControl:stepping() return SH.Stepping() end
function TimeControl:stepDt() return SH.StepDt() end
function TimeControl:gameDt(dt) return SH.GameDt(dt) end
function TimeControl:frameStart() SH.FrameStart() end
function TimeControl:stepBegin(dt) return SH.StepBegin(dt) end
function TimeControl:stepEnd() SH.StepEnd() end
function TimeControl:thaw() SH.Thaw() end
function TimeControl:humanoidPre(dt, hum, root) SH.Humanoid.Pre(dt, hum, root) end
function TimeControl:humanoidPost(dt, hum, root, recording) SH.Humanoid.Post(dt, hum, root, recording) end

-- the coyote timer (V2.38.17): kept with each frame, restored when the recording goes on from a frame, reset
-- by Idle and every pause
function TimeControl:coyoteReset(hum) SH.Humanoid.CoyoteReset(hum) end
function TimeControl:fill(tl, n) tl:setList("CY", n, SH.Humanoid.CoyoteState()) end
function TimeControl:onBeginRecording(tl, n)
	SH.Humanoid.CoyoteRestore((n >= 1 and n <= tl:count()) and tl:getList("CY", n) or nil)
end

-- the frame's factor (V2: SK = the factor its physics ran with, r(k, 10000), nil at 1x)
function TimeControl:begin(tl, i)
	local k = self.E.recScale
	tl:setList("v2SK", i, (k ~= 1) and Util.round(k, 10000) or nil)
end

return TimeControl
