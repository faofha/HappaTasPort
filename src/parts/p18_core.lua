-- ================================================================================================
--  TAS CORE   (modes, recording, playback)
--  1 = Idle, 2 = Create (paused / recording), 3 = Test (playback)
--
--  Recording, per frame:   PreRender      new frame: camera, velocity, zoom, inputs, mouse, times
--                          PreSimulation  root CFrame, state, animation, client objects, tools,
--                                         buttons, death   (before physics moves anything)
--                          Heartbeat      bookkeeping, stats
--  Playback: Heartbeat advances the timer and poses the character for physics, PreRender poses
--  it again for rendering at the same time, the end of the render step re-asserts client objects.
--  Speed hack (slow motion): a frame recorded while it is on stores its time x the factor and the
--  velocity / the factor (C.recScale = the factor the frame's physics ran with), so the TAS is saved
--  in normal time.
-- ================================================================================================
local C = {
	data = {}, mode = 1, frame = 1, paused = true, back = false, forw = false,
	LastPause = 1, FirstFrameRecord = false, LastFrameTime = 0, LookAround = false,
	TestingTimer = 0, CurrentFrameInput = false, InputDebounce = 0, FreezeTimeRemaining = 0,
	merge = false, mergeBefore = {}, mergeAfter = {}, oldTAS = {}, mergeReqDist = nil, mergeCFrame = nil,
	mergeCanComplete = false, mergeBaseHeld = nil, hitboxes = {},
	Humanoid = nil, Char = nil, HRP = nil, IsMobile = UIS.TouchEnabled, QuitTestEvent = nil,
	dataVersion = 0, inputs = {}, poseT = nil, pose = nil, guardFrames = 0, recScale = 1,
}
Core.State = C

do
	local NumberToState = {
		[0] = "FallingDown", [8] = "Running", [10] = "RunningNoPhysics", [12] = "Climbing",
		[11] = "StrafingNoPhysics", [1] = "Ragdoll", [2] = "GettingUp", [3] = "Jumping", [7] = "Landed",
		[6] = "Flying", [5] = "Freefall", [13] = "Seated", [14] = "PlatformStanding", [15] = "Dead",
		[4] = "Swimming", [16] = "Physics", [18] = "None",
	}
	C.NumberToState = NumberToState

	local function GetSetting(name) return Settings.Get(name) end
	C.GetSetting = GetSetting

	function C.SetCam()
		return (C.mode == 3 and Settings.On("Lock Camera (Test)")) or (C.mode == 2 and Settings.On("Lock Camera (Paused)"))
	end

	function C.DataChanged()
		C.dataVersion = C.dataVersion + 1
		ClientObjects.Invalidate()
		Buttons.Invalidate()
		KitObjects.Invalidate()
	end

	local function changeState(hum, st) hum:ChangeState(st) end
	C.ChangeState = function(st) if C.Humanoid then pcall(changeState, C.Humanoid, st) end end

	function C.CharLoaded()
		local h = C.HRP
		return C.Char ~= nil and h ~= nil and h.Parent ~= nil and C.Humanoid ~= nil
	end

	function C.NotDead()
		if Settings.On("Record Death & Respawn") then return true end
		return C.Humanoid ~= nil and C.Humanoid:GetState() ~= Enum.HumanoidStateType.Dead
	end

	-- ------------------------------------------------------------------------------------ conversions
	function C.Vector3ToTable(V) return { r(V.X, 1000), r(V.Y, 1000), r(V.Z, 1000) } end
	function C.TableToVector3(t) return Vector3.new(t[1] or 0, t[2] or 0, t[3] or 0) end
	function C.CFrameToTable(cf)
		local x, y, z, a, b, c2, d, e, f, g, h, i = cf:GetComponents()
		return { r(x, 1000), r(y, 1000), r(z, 1000), r(a, 1000), r(b, 1000), r(c2, 1000), r(d, 1000), r(e, 1000), r(f, 1000), r(g, 1000), r(h, 1000), r(i, 1000) }
	end
	function C.TableToCFrame(t)
		if not t then return CFrame.new() end
		return CFrame.new(t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], t[10], t[11], t[12])
	end

	function C.ToTime(t)
		t = tonumber(t) or 0
		local mins = math.floor(t / 60)
		local secs = r(t - mins * 60, 1000)
		local s = tostring(secs)
		local intPart = s:match("^%-?(%d+)") or "0"
		if #intPart < 2 then s = "0" .. s end
		return mins .. ":" .. s
	end

	-- ------------------------------------------------------------------------------------ status text
	local statusToken = 0
	function C.SetStatus(text, inverse)
		local gui = C.Gui
		if not gui then return end
		local status = gui:FindFirstChild("Status")
		if not status then return end
		statusToken = statusToken + 1
		local my = statusToken
		status.Text = tostring(text)
		if not inverse then
			status.TextTransparency = 0
			for i = 0, 1.05, 0.05 do
				if statusToken ~= my or Janitor.unloading then return end
				status.TextTransparency = i
				task.wait(0.05)
			end
		else
			status.TextTransparency = 0
			task.wait(2)
			for i = 0, 1.05, 0.05 do
				if statusToken ~= my or Janitor.unloading then return end
				status.TextTransparency = i
				task.wait(0.05)
			end
		end
	end
	Core.SetStatus = function(text, inverse) return C.SetStatus(text, inverse) end

	-- ------------------------------------------------------------------------------------ stats panels
	-- Only these functions write the panels, so what was written last is remembered in Lua instead of
	-- being read back from the instances every frame (each read is a call into the engine).
	local lastText = setmetatable({}, { __mode = "k" })
	local lastVis = setmetatable({}, { __mode = "k" })
	local labelCache = setmetatable({}, { __mode = "k" })
	local function setText(lbl, text)
		if lbl and lastText[lbl] ~= text then
			lastText[lbl] = text
			lbl.Text = text
		end
	end
	local function setVisible(f, v)
		if not f then return end
		local cur = lastVis[f]
		if cur == nil then cur = f.Visible end
		if cur ~= v then f.Visible = v end
		lastVis[f] = v
	end
	-- the rows of a panel by name (the panels never change their children)
	local function labels(f)
		local t = labelCache[f]
		if not t then
			t = setmetatable({}, { __index = function(tt, k)
				local ch = f:FindFirstChild(k)
				rawset(tt, k, ch or false)
				return ch or false
			end })
			labelCache[f] = t
		end
		return t
	end
	local statsTick = 0
	local keysCache = { frame = -1, data = nil, text = "-", t = 0 }

	local function PausedKeysText(frameNo)
		if keysCache.data ~= C.data or keysCache.frame ~= frameNo then
			local now = os.clock()
			if keysCache.data ~= C.data or now - keysCache.t > 0.1 then
				keysCache.data, keysCache.frame, keysCache.t = C.data, frameNo, now
				keysCache.text = InputSys.Describe(InputSys.HeldAt(C.data, frameNo))
			end
		end
		return keysCache.text
	end
	local function MouseText(fr)
		if fr and fr.MX then return fr.MX .. ", " .. fr.MY end
		local x, y = InputSys.Mouse()
		return x .. ", " .. y
	end
	local function v3txt(v) return r(v.X, 1000) .. ", " .. r(v.Y, 1000) .. ", " .. r(v.Z, 1000) end
	local function degTxt(x, y, z) return r(math.deg(x), 1000) .. ", " .. r(math.deg(y), 1000) .. ", " .. r(math.deg(z), 1000) end
	-- rows that show the live character: position, rotation, velocities, camera, state (row names in n)
	local function liveRows(f, root, n)
		setText(f[n[1]], " Root Position: " .. v3txt(root.Position))
		setText(f[n[2]], " Root Rotation: " .. v3txt(root.Orientation))
		setText(f[n[3]], " Root Linear Velocity: " .. v3txt(root.AssemblyLinearVelocity))
		setText(f[n[4]], " Root Angular Velocity: " .. v3txt(root.AssemblyAngularVelocity))
		setText(f[n[5]], " Camera Rotation: " .. degTxt(workspace.CurrentCamera.CFrame:ToEulerAnglesYXZ()))
		setText(f[n[6]], " Humanoid State: " .. (C.Humanoid and C.Humanoid:GetState().Name or "None"))
	end
	local IDLE_ROWS, CREATE_ROWS = { "2", "3", "4", "5", "6", "7" }, { "4", "5", "6", "7", "8", "9" }

	local SS = {}
	local function showPanel(panel) -- one stats panel (or none) is visible
		setVisible(C.IdleStatsF, panel == C.IdleStatsF)
		setVisible(C.CreateStatsF, panel == C.CreateStatsF)
		setVisible(C.TestStatsF, panel == C.TestStatsF)
	end
	function SS.Hide() showPanel(nil) end

	function SS.Idle(FrameTime, zoom)
		local root = C.HRP
		local panel = C.IdleStatsF
		if not root or not panel then return end
		showPanel(panel)
		local f = labels(panel)
		setText(f["1"], " Frame Time: " .. r(FrameTime or 0, 1000000))
		liveRows(f, root, IDLE_ROWS)
		setText(f["8"], " Zoom: " .. r(zoom or 12.5, 1000))
	end

	local lastBT, lastStatFD, lastStatFN, lastStatPaused, lastStatSH = nil, nil, nil, nil, nil
	function SS.Create(pausedNow, frameNo, FrameData)
		local panel = C.CreateStatsF
		showPanel(panel)
		local bt = pausedNow and 0.1 or 0.2
		if lastBT == nil then lastBT = panel.BackgroundTransparency end
		if lastBT ~= bt then panel.BackgroundTransparency = bt; lastBT = bt end
		local f = labels(panel)
		local sh = SpeedHack.Wanted()
		if pausedNow and FrameData and lastStatPaused and lastStatFD == FrameData and lastStatFN == frameNo and lastStatSH == sh then
			return
		end
		lastStatPaused, lastStatFD, lastStatFN, lastStatSH = pausedNow, FrameData, frameNo, sh
		setText(f["1"], " Frame: " .. frameNo .. ((sh < 1) and ("   (Speed Hack " .. r(sh, 1000) .. "x)") or ""))
		if FrameData and FrameData.FrameTime and FrameData.Cframe and NumberToState[FrameData.State] then
			local cf, lin, ang = FrameData.Cframe, FrameData.Velocity.Linear, FrameData.Velocity.Angular
			setText(f["2"], " Frame Time: " .. FrameData.FrameTime)
			setText(f["3"], " Total Time: " .. C.ToTime(FrameData.TotalTime))
			setText(f["4"], " Root Position: " .. r(cf[1], 1000) .. ", " .. r(cf[2], 1000) .. ", " .. r(cf[3], 1000))
			setText(f["5"], " Root Rotation: " .. degTxt(C.TableToCFrame(cf):ToEulerAnglesYXZ()))
			setText(f["6"], " Root Linear Velocity: " .. lin[1] .. ", " .. lin[2] .. ", " .. lin[3])
			setText(f["7"], " Root Angular Velocity: " .. ang[1] .. ", " .. ang[2] .. ", " .. ang[3])
			setText(f["8"], " Camera Rotation: " .. degTxt(C.TableToCFrame(FrameData.CamCframe):ToEulerAnglesYXZ()))
			setText(f["9"], " Humanoid State: " .. NumberToState[FrameData.State])
			setText(f["91"], " Zoom: " .. tostring(FrameData.Zoom))
			setText(f["92"], " Keys: " .. (pausedNow and PausedKeysText(frameNo) or InputSys.Describe(InputSys.Live.held)))
			setText(f["93"], " Mouse: " .. MouseText(FrameData))
		else
			local root = C.HRP
			if not root then return end
			setText(f["2"], " Frame Time: 0")
			setText(f["3"], " Total Time: 0")
			liveRows(f, root, CREATE_ROWS)
			setText(f["91"], " Zoom: " .. r(Bridge.GetZoom(), 1000))
			setText(f["92"], " Keys: " .. InputSys.Describe(InputSys.Live.held))
			setText(f["93"], " Mouse: " .. MouseText(nil))
		end
	end

	function SS.Merge(reqDist, goalCFrame, FrameData)
		local m = labels(C.MergeStats)
		if type(FrameData) == "table" and FrameData.Cframe and goalCFrame then
			local dist = (Vector3.new(FrameData.Cframe[1], FrameData.Cframe[2], FrameData.Cframe[3]) - Vector3.new(goalCFrame[1], goalCFrame[2], goalCFrame[3])).Magnitude
			setText(m["1"], " Current Distance: " .. r(dist, 1000))
			if dist < reqDist then
				setText(m["3"], " Click here to complete merge")
				C.MergeStats.BackgroundColor3 = Color3.fromRGB(0, 80, 0)
				C.mergeCanComplete = true
			else
				setText(m["3"], " Click here to cancel merge")
				C.MergeStats.BackgroundColor3 = Color3.fromRGB(100, 0, 0)
				C.mergeCanComplete = false
			end
		end
		setText(m["2"], " Distance Required: " .. r(reqDist or 0, 1000))
	end

	function SS.Test(Timer, Speed)
		local panel = C.TestStatsF
		showPanel(panel)
		local f = labels(panel)
		setText(f["1"], " Time: " .. C.ToTime(r(Timer or 0, 1000000)))
		setText(f["2"], " Playback Speed: " .. tostring(Speed or 1))
		setText(f["3"], " Keys: " .. InputSys.Describe(InputSys.Replay.state))
		setText(f["4"], " Mouse: " .. MouseText(C.data[C.frame]))
	end

	local STAT_SETTING = { Idle = "Show Stats (Idle)", Create = "Show Stats (Create)", Test = "Show Stats (Test)" }
	-- every frame while paused (values change on scrub), ~30 times a second otherwise
	function C.SetStats(statMode, FrameData, FrameTime, frameNo)
		statsTick = statsTick + 1
		local mode3speed = (statMode == "Test" and Settings.Get("Playback Speed") ~= 1)
		if Settings.On(STAT_SETTING[statMode]) or mode3speed then
			if statMode == "Create" and C.paused then
				SS.Create(true, frameNo, FrameData)
			elseif statsTick % 2 == 0 then
				Profiler.Begin("Stats UI")
				if statMode == "Idle" then SS.Idle(FrameTime, Bridge.GetZoom())
				elseif statMode == "Create" then SS.Create(C.paused, frameNo, FrameData)
				elseif statMode == "Test" then SS.Test(C.TestingTimer, Settings.Get("Playback Speed")) end
				Profiler.End("Stats UI")
			end
		else
			SS.Hide()
		end
		if C.merge then
			SS.Merge(C.mergeReqDist, C.mergeCFrame, FrameData)
			setVisible(C.MergeStats, true)
		else
			setVisible(C.MergeStats, false)
		end
	end

	-- ------------------------------------------------------------------------------------ character
	-- moves the whole character (the root moves the assembly; the torso is aligned through the
	-- root joint so the limbs never trail a frame behind)
	function C.SyncCharacter(hrpCF, linVel, angVel)
		local HRP = C.HRP -- (every caller has checked C.CharLoaded() this frame)
		if not HRP then return end
		HRP.CFrame = hrpCF
		HRP.AssemblyLinearVelocity = linVel
		HRP.AssemblyAngularVelocity = angVel
		local torso = C.Torso
		local rj = C.RootJoint
		if torso and torso.Parent and rj and rj.Parent then
			torso.CFrame = hrpCF * rj.C0 * rj.Transform * rj.C1:Inverse()
		end
	end

	function C.UpdateCamera(FrameData, UnlockShift)
		if not C.SetCam() then return end
		local cam = workspace.CurrentCamera
		if FrameData.CamCF then
			cam.CFrame = FrameData.CamCF
		else
			cam.CFrame = C.TableToCFrame(FrameData.CamCframe)
		end
		local hrp, hum = C.HRP, C.Humanoid
		if hrp and hrp.Parent then
			local off = hum and hum.CameraOffset or ZERO3
			cam.Focus = CFrame.new(hrp.CFrame.Position + hrp.CFrame:VectorToWorldSpace(Vector3.new(0, 1.5, 0) + off))
		end
		if not UnlockShift then
			local IsShiftLock = Bridge.IsShiftlocked() and 1 or 0
			if IsShiftLock ~= FrameData.ShiftLock then Bridge.ShiftlockSwitch() end
		end
		local z = tonumber(FrameData.Zoom) or 12.5
		Bridge.SetZoom(z, true)
	end

	-- the character exactly on a recorded frame
	function C.SyncFrame(fr)
		C.SyncCharacter(C.TableToCFrame(fr.Cframe), C.TableToVector3(fr.Velocity.Linear), C.TableToVector3(fr.Velocity.Angular))
	end

	function C.anchor(value)
		if C.HRP then C.HRP.Anchored = value end
		local allowAutoRotate = (not value) and (C.mode ~= 3)
		if C.Humanoid then
			pcall(function() C.Humanoid.AutoRotate = allowAutoRotate end)
		end
		Bridge.ShiftlockRotation(allowAutoRotate)
	end

	function C.LoadFrame(FrameData, unpausing, backtrack)
		local data = C.data
		if #data == 0 or not FrameData then return end
		if not FrameData.Cframe or not FrameData.State or not FrameData.Velocity then return end
		if not C.CharLoaded() then return end
		local HRP = C.HRP

		if not unpausing then
			if HRP.Anchored ~= (C.mode ~= 3) then C.anchor(C.mode ~= 3) end
			C.SyncFrame(FrameData)
			C.UpdateCamera(FrameData)
			if C.mode == 2 then
				if C.SetCam() and not C.LookAround then
					Bridge.UpdateGhost(FrameData.Zoom, 0, true)
				end
				ClientObjects.ShowFrame(data, C.frame)
				Buttons.ShowFrame(data, C.frame)
				Lighting.ShowFrame(data, C.frame)
			end
		else
			ClientObjects.RestoreUnpause(data, C.frame)
			if C.SetCam() then
				Bridge.SetZoom(FrameData.Zoom, true)
				Bridge.UpdateGhost(FrameData.Zoom, 0, true)
			end
			Bridge.ResetGhost(true)
			C.LastPause = C.frame
			C.anchor(false)
		end

		HRP.AssemblyLinearVelocity = C.TableToVector3(FrameData.Velocity.Linear)
		HRP.AssemblyAngularVelocity = C.TableToVector3(FrameData.Velocity.Angular)
		C.ChangeState(FrameData.State)

		local BacktrackAnim, BacktrackAnimSpeed
		local AnimTime = 0
		if backtrack and C.frame > 2 then
			for i = C.frame, 1, -1 do
				local fr = data[i]
				if not fr or not fr.Anim then break end
				local anims = fr.Anim.Anims or {}
				local speed = fr.Anim.Speed or 1
				AnimTime = AnimTime + (fr.FrameTime or 0) * speed
				if #anims > 0 then
					BacktrackAnim = { anims[#anims] }
					BacktrackAnimSpeed = speed
					break
				end
			end
		end
		if not BacktrackAnimSpeed then BacktrackAnimSpeed = 1 end
		if FrameData.Anim and C.mode == 2 then
			Bridge.SetAnimation(FrameData.Anim, BacktrackAnim, (not unpausing) and 0 or BacktrackAnimSpeed, backtrack and AnimTime or nil)
		end
	end

	function C.RemoveCutFrames()
		local data = C.data
		if #data > C.frame then
			for _ = C.frame + 1, #data do data[#data] = nil end
			C.DataChanged()
			Lighting.Trim(C.frame)
		end
	end
	local af1, af2, afCF1, afCF2, afCam1, afCam2

	-- interpolated pose between two frames at playback time t (proper rotation interpolation)
	function C.AveragedFrame(f1, f2, t)
		if not f1 or not f2 or not f1.Cframe or not f2.Cframe then
			local f = f1 or f2
			if f and f.Cframe then
				return C.TableToCFrame(f.Cframe), C.TableToCFrame(f.CamCframe or f.Cframe),
					C.TableToVector3(f.Velocity.Linear), C.TableToVector3(f.Velocity.Angular), f.Zoom or 12.5
			end
			return CFrame.new(), CFrame.new(), ZERO3, ZERO3, 12.5
		end
		if f1 ~= af1 or f2 ~= af2 then
			if f1 == af2 then
				afCF1, afCam1 = afCF2, afCam2
			else
				afCF1, afCam1 = C.TableToCFrame(f1.Cframe), C.TableToCFrame(f1.CamCframe)
			end
			afCF2, afCam2 = C.TableToCFrame(f2.Cframe), C.TableToCFrame(f2.CamCframe)
			af1, af2 = f1, f2
		end
		local t1, t2 = f1.TotalTime or 0, f2.TotalTime or 0
		local w = (t2 > t1) and clampn((t - t1) / (t2 - t1), 0, 1) or 0
		local rootCF = afCF1:Lerp(afCF2, w)
		local camCF = afCam1:Lerp(afCam2, w)
		local l1, l2 = f1.Velocity.Linear, f2.Velocity.Linear
		local a1, a2 = f1.Velocity.Angular, f2.Velocity.Angular
		local lin = Vector3.new(l1[1] + (l2[1] - l1[1]) * w, l1[2] + (l2[2] - l1[2]) * w, l1[3] + (l2[3] - l1[3]) * w)
		local ang = Vector3.new(a1[1] + (a2[1] - a1[1]) * w, a1[2] + (a2[2] - a1[2]) * w, a1[3] + (a2[3] - a1[3]) * w)
		local zoom = (f1.Zoom or 12.5) + ((f2.Zoom or 12.5) - (f1.Zoom or 12.5)) * w
		return rootCF, camCF, lin, ang, zoom
	end

	-- pose for the current TestingTimer, computed once and used by Heartbeat and PreRender
	function C.PlaybackPose()
		local data, frame = C.data, C.frame
		if C.poseT == C.TestingTimer and C.poseFrame == frame and C.poseData == data and C.pose then return C.pose end
		local rootCF, camCF, lin, ang, zoom = C.AveragedFrame(data[frame], data[frame + 1], C.TestingTimer)
		local p = C.pose or {}
		p.root, p.CamCF, p.lin, p.ang, p.Zoom = rootCF, camCF, lin, ang, zoom
		p.ShiftLock = data[frame] and data[frame].ShiftLock or 0
		C.pose, C.poseT, C.poseFrame, C.poseData = p, C.TestingTimer, frame, data
		return p
	end

	function C.CanCoyoteJump()
		local data, frame = C.data, C.frame
		return C.Humanoid:GetState() == Enum.HumanoidStateType.Running and data[frame] and data[frame - 1] and
			data[frame].State == Enum.HumanoidStateType.Running.Value and
			data[frame - 1].State == Enum.HumanoidStateType.Running.Value
	end

	function C.DoubleInput()
		C.CurrentFrameInput = true
		return false
	end

	function C.JumpedOffLader()
		local data, frame = C.data, C.frame
		return data[frame] and data[frame - 1] and data[frame].State == Enum.HumanoidStateType.Jumping.Value
			and data[frame - 1].State == Enum.HumanoidStateType.Climbing.Value
	end

	-- ------------------------------------------------------------------------------------ mobile
	local touchCache = { tcf = nil, t = 0 }
	local function touchFrame()
		local now = os.clock()
		if touchCache.tcf and touchCache.tcf.Parent and now - touchCache.t < 2 then return touchCache.tcf end
		touchCache.t = now
		local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
		local tg = pg and pg:FindFirstChild("TouchGui")
		touchCache.tcf = tg and tg:FindFirstChild("TouchControlFrame")
		return touchCache.tcf
	end
	C.TouchFrame = touchFrame

	function C.ReadMobile()
		local ok, res = pcall(function()
			local tcf = touchFrame()
			if not tcf then return nil end
			local jb = tcf:FindFirstChild("JumpButton")
			local M = { Jumping = (jb and jb.ImageRectOffset.X == 146) and 1 or 0 }
			local tf = tcf:FindFirstChild("ThumbstickFrame")
			local stick = tf and tf.Visible and tf:FindFirstChild("StickImage")
			if stick then
				M.JoystickX = r(stick.Position.X.Offset, 1)
				M.JoystickY = r(stick.Position.Y.Offset, 1)
			end
			local dtf = tcf:FindFirstChild("DynamicThumbstickFrame")
			if dtf and dtf.Visible then
				local sImg = dtf:FindFirstChild("ThumbstickStart")
				local eImg = dtf:FindFirstChild("ThumbstickEnd")
				if sImg and eImg and sImg.Visible then
					local mids = {}
					for _, ch in ipairs(dtf:GetChildren()) do
						if ch.Name == "ThumbstickMiddle" and ch:IsA("ImageLabel") and ch.Visible then
							local szX = ch.Size.X.Offset > 0 and ch.Size.X.Offset or ch.AbsoluteSize.X
							local szY = ch.Size.Y.Offset > 0 and ch.Size.Y.Offset or ch.AbsoluteSize.Y
							mids[#mids + 1] = { r(ch.Position.X.Offset, 1), r(ch.Position.Y.Offset, 1), r(ch.ImageTransparency, 100), r(szX, 1), r(szY, 1) }
						end
					end
					M.Dynamic = {
						Start = { r(sImg.Position.X.Offset, 1), r(sImg.Position.Y.Offset, 1), r(sImg.ImageTransparency, 100) },
						End = { r(eImg.Position.X.Offset, 1), r(eImg.Position.Y.Offset, 1), r(eImg.ImageTransparency, 100) },
						Middles = mids,
					}
				end
			end
			return M
		end)
		if ok and res then return res end
		return { Jumping = 0 }
	end

	function C.ReplayMobile(mob)
		if type(mob) ~= "table" then return end
		pcall(function()
			local tcf = touchFrame()
			if not tcf then return end
			local jb = tcf:FindFirstChild("JumpButton")
			if jb then jb.ImageRectOffset = Vector2.new((mob.Jumping or 0) * 145 + 1, 146) end
			if mob.JoystickX and mob.JoystickY then
				local tf = tcf:FindFirstChild("ThumbstickFrame")
				local stick = tf and tf:FindFirstChild("StickImage")
				if stick then stick.Position = UDim2.new(0, mob.JoystickX, 0, mob.JoystickY) end
			end
			local dtf = tcf:FindFirstChild("DynamicThumbstickFrame")
			if not dtf then return end
			local dyn = mob.Dynamic
			local sImg = dtf:FindFirstChild("ThumbstickStart")
			local eImg = dtf:FindFirstChild("ThumbstickEnd")
			local mids = {}
			for _, ch in ipairs(dtf:GetChildren()) do
				if ch.Name == "ThumbstickMiddle" and ch:IsA("ImageLabel") then mids[#mids + 1] = ch end
			end
			if dyn and dyn.Start and sImg and eImg then
				sImg.Position = UDim2.new(0, dyn.Start[1], 0, dyn.Start[2])
				sImg.ImageTransparency = dyn.Start[3]
				sImg.Visible = true
				eImg.Position = UDim2.new(0, dyn.End[1], 0, dyn.End[2])
				eImg.ImageTransparency = dyn.End[3]
				eImg.Visible = true
				local list = dyn.Middles or {}
				for i, m in ipairs(list) do
					local img = mids[i]
					if img then
						img.Position = UDim2.new(0, m[1], 0, m[2])
						img.ImageTransparency = m[3]
						if m[4] and m[5] and m[4] > 0 and m[5] > 0 then img.Size = UDim2.new(0, m[4], 0, m[5]) end
						img.Visible = true
					end
				end
				for i = #list + 1, #mids do mids[i].Visible = false end
			else
				if sImg then sImg.Visible = false end
				if eImg then eImg.Visible = false end
				for _, img in ipairs(mids) do img.Visible = false end
			end
		end)
	end
end

do
	local inputs = C.inputs
	local rs = RunService

	local function camType(t)
		pcall(function()
			local cam = workspace.CurrentCamera
			if cam and cam.CameraType ~= t then cam.CameraType = t end
		end)
	end

	-- the frame the TAS is on is held still while paused (Create)
	local function frameTime(f)
		local fr = C.data[f]
		return fr and fr.TotalTime or 0
	end

	-- --------------------------------------------------------------------------------------------- modes
	function inputs.Idle()
		Bridge.ResetGhost()
		camType(Enum.CameraType.Custom)
		C.mode, C.frame = 1, 1
		C.pausedCamCF, C.pausedZoom = nil, nil
		C.anchor(false)
		Bridge.SetCameraFreeze(false, false)
		Bridge.LockShiftlock(false)
		Bridge.LockAnimations(false)
		Bridge.SetFreeMouse(false)
		Buttons.Release()
		Lighting.Release()
		KitObjects.Release()
		ToolSync.ReplayEnd()
		Cursor.Reset()
		Bridge.RefreshMouse(Menu.IsModalOpen and Menu.IsModalOpen())
		C.guardFrames = 45
	end

	function inputs.Create(force)
		if C.DoubleInput() and not force then return end
		if InputSys.IsReplaying() then InputSys.ReplayEnd() end
		if ClientObjects.IsTesting() then ClientObjects.EndPlayback() end
		ToolSync.ReplayEnd()
		camType(Enum.CameraType.Custom)
		local data = C.data
		C.frame = #data
		C.mode = 2
		C.paused = true
		C.LookAround = false
		if #data > 0 and data[#data] then
			local last = data[#data]
			C.LoadFrame(last, false, true)
			Bridge.SetZoom(last.Zoom, true)
			if C.SetCam() then
				Bridge.UpdateGhost(last.Zoom, 0, true)
			else
				Bridge.ResetGhost(true)
			end
		else
			Bridge.ResetGhost(true)
			Buttons.Pause(0)
			Lighting.Pause()
		end
		C.anchor(true)
		Bridge.LockShiftlock(#data > 0)
		Bridge.LockAnimations(true)
	end

	function inputs.Test()
		if C.DoubleInput() then return end
		local data = C.data
		if #data < 2 then task.spawn(C.SetStatus, "There is not enough TAS data to test.", true) return end
		local speed = Settings.Get("Playback Speed")
		if Settings.On("Restart When Testing") then
			C.frame = (speed > 0) and 1 or #data - 1
			C.TestingTimer = (speed > 0) and 0 or (data[#data - 1].TotalTime or 0)
			if speed > 0 and data[C.frame].Anim then
				Bridge.SetAnimation(data[C.frame].Anim, data[C.frame].Anim.Anims, speed)
			end
		else
			C.frame = clampn(C.frame, 1, #data - 1)
			C.TestingTimer = data[C.frame].TotalTime or 0
		end
		camType(Settings.On("Lock Camera (Test)") and Enum.CameraType.Scriptable or Enum.CameraType.Custom)
		C.mode = 3
		if data[C.frame] then
			C.UpdateCamera(data[C.frame], false)
			Bridge.SetZoom(data[C.frame].Zoom, true)
		end
		C.anchor(false)
		Bridge.LockShiftlock(true)
		Bridge.LockAnimations("ReplayAnimationsOnly")
		C.poseT = nil
		if speed > 0 then
			InputSys.ReplayBegin(data, C.frame)
			ClientObjects.PlaybackBegin(data, C.frame)
		end
		Buttons.PlaybackBegin(data, C.frame)
		Lighting.PlaybackBegin(data, C.frame)
		ToolSync.ReplayBegin(data, C.frame, C.Char)
	end

	local function beginRecordingAt()
		local data = C.data
		C.lastVX, C.lastVY = nil, nil
		InputSys.BeginRecording(data, C.merge and C.mergeBaseHeld or nil)
		ClientObjects.BeginRecording(data[#data])
		ToolSync.Clear()
		Buttons.Resume(data, #data)
		Lighting.Resume(data, #data)
	end
	-- unpausing: cut the frames after the current one, camera back on the last frame
	local function unpauseFrom(data)
		C.RemoveCutFrames()
		KitObjects.Unpause(data, #data)
		C.LookAround = false
		Bridge.LockAnimations(false)
		if #data > 0 then
			C.UpdateCamera(data[#data], true)
			Bridge.SetZoom(data[#data].Zoom, true)
		end
	end
	-- no jump on the first recorded frame (one Heartbeat + render step)
	local function noJumpOneFrame()
		local hum = C.Humanoid
		if hum then hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false) end
		rs.Heartbeat:Wait()
		rs.RenderStepped:Wait()
		if hum and hum.Parent then hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end
	end

	function inputs.Unpause()
		if C.DoubleInput() then return end
		local data = C.data
		if #data > 1 and C.frame > 1 and C.JumpedOffLader() then C.frame = C.frame - 1 end
		unpauseFrom(data)
		C.LoadFrame(data[#data], true)
		C.anchor(false)
		Bridge.SetCameraFreeze(false, false)
		Bridge.LockShiftlock(false)
		beginRecordingAt()
		C.FirstFrameRecord = true
		C.paused = false
		Bridge.SetFreeMouse(false)
		noJumpOneFrame()
		C.FirstFrameRecord = false
		-- old camera scripts only re-lock the mouse on events: ask again now (first person fix)
		Bridge.RefreshMouse(Menu.IsModalOpen and Menu.IsModalOpen())
		C.guardFrames = 45
	end

	function inputs.Pause()
		if C.DoubleInput() then return end
		Bridge.LockAnimations(true)
		C.paused = true
		local cam = workspace.CurrentCamera
		C.pausedCamCF = cam and cam.CFrame or C.pausedCamCF
		C.pausedZoom = Bridge.GetZoom()
		local data = C.data
		if #data > 0 and data[#data].Cframe == nil then data[#data] = nil end
		C.frame = #data
		Bridge.LockShiftlock(#data > 0)
		C.LoadFrame(data[#data])
		KitClock.Rewind(data, #data) -- (the step after the last frame is thrown away: the kit's clock too)
		Buttons.Pause(frameTime(#data))
		Lighting.Pause()
	end

	function inputs.Unpause1F()
		if C.DoubleInput() then return end
		local data = C.data
		local FrameCount = 1
		if #data > 1 and C.frame > 1 and C.JumpedOffLader() then C.frame = C.frame - 1; FrameCount = 2 end
		if #data > 1 and data[C.frame] and data[C.frame].State == Enum.HumanoidStateType.Landed.Value then FrameCount = 2 end
		unpauseFrom(data)
		C.anchor(false)
		Bridge.SetCameraFreeze(false, false)
		Bridge.LockShiftlock(false)
		beginRecordingAt()
		C.FirstFrameRecord = true
		C.LoadFrame(data[#data], true)
		noJumpOneFrame()
		C.paused = false
		Bridge.SetFreeMouse(false)
		C.FirstFrameRecord = false
		for _ = 1, FrameCount do rs.RenderStepped:Wait() end
		Bridge.LockAnimations(true)
		C.paused = true
		C.frame = #data
		Bridge.LockShiftlock(#data > 0)
		C.LoadFrame(C.data[#C.data], false, true)
		KitClock.Rewind(C.data, #C.data)
		Buttons.Pause(frameTime(#C.data))
		Lighting.Pause()
	end

	-- paused on frame f (Back / Forward hold it while the key is down)
	local function holdAt(f)
		C.frame = f
		C.paused = true
		Bridge.LockShiftlock(#C.data > 0)
		Bridge.LockAnimations(true)
		C.LoadFrame(C.data[f], false, true)
	end
	function inputs.Return()
		if C.DoubleInput() then return end
		C.frame = C.LastPause
		C.RemoveCutFrames()
		holdAt(C.frame)
	end
	function inputs.Back1F() if not C.DoubleInput() then holdAt(C.frame - 1) end end
	function inputs.Forward1F() if not C.DoubleInput() then holdAt(C.frame + 1) end end
	function inputs.Back() if not C.DoubleInput() then C.back = true; holdAt(C.frame) end end
	function inputs.Forward() if not C.DoubleInput() then C.forw = true; holdAt(C.frame) end end

	local ConfirmDelete, ConfirmOptimize = false, false
	function inputs.Delete(mobile)
		if ConfirmDelete then
			C.data = {}
			C.DataChanged()
			if Buttons.Reset then pcall(Buttons.Reset) end
			Lighting.Clear()
			C.LastPause = 1
			C.frame = 0
			task.spawn(C.SetStatus, "TAS Deleted")
			ConfirmDelete = false
		else
			ConfirmDelete = true
			C.SetStatus(mobile and "Delete TAS? Click To Confirm" or "Delete TAS? [" .. tostring(Controls.Get("Delete TAS")) .. "] To Confirm")
			ConfirmDelete = false
		end
	end

	function inputs.Optimize(mobile)
		if C.mode ~= 1 then
			task.spawn(C.SetStatus, "Switch to idle to optimize TAS")
			return
		end
		if ConfirmOptimize then
			ConfirmOptimize = false
			local data = C.data
			local NewData = {}
			local prev, prevMX, prevMY
			-- frame 1 is always kept: it holds the starting pose and the client object / button snapshots
			for i = 1, #data do
				local v = data[i]
				local values = v.CamCframe
				local SameCount = 0
				local mouseMoved = v.MX ~= nil and (v.MX ~= prevMX or v.MY ~= prevMY)
				prevMX, prevMY = v.MX, v.MY
				if prev then
					for y, z in pairs(values) do
						if prev[y] == z then SameCount = SameCount + 1 end
					end
				end
				prev = values
				if i == 1 or SameCount < 12 or (v.Anim and v.Anim.Anims and #v.Anim.Anims > 0) or (v.Input and #v.Input > 0) or mouseMoved
					or v.CO ~= nil or v.BT ~= nil or v.Tools ~= nil or v.Died then
					NewData[#NewData + 1] = v
					if #NewData > 1 then
						v.TotalTime = r(NewData[#NewData - 1].TotalTime + v.FrameTime, 1000000)
					else
						v.TotalTime = r(v.FrameTime, 1000000)
					end
				end
			end
			C.data = NewData
			C.DataChanged()
			task.spawn(C.SetStatus, "TAS Optimized")
		else
			ConfirmOptimize = true
			C.SetStatus(mobile and "Optimize TAS? Click To Confirm" or "Optimize TAS? [" .. tostring(Controls.Get("Optimize TAS")) .. "] To Confirm")
			ConfirmOptimize = false
		end
	end

	function inputs.LookAround()
		C.LookAround = not C.LookAround
		C.guardFrames = 45
	end

	-- --------------------------------------------------------------------------------------------- merge
	function C.DestroyMergeHitboxes()
		for _, hitbox in ipairs(C.hitboxes) do pcall(function() hitbox:Destroy() end) end
		C.hitboxes = {}
	end

	function C.CreateMergeHitboxes()
		C.DestroyMergeHitboxes()
		local mb, ma = C.mergeBefore, C.mergeAfter
		if not mb or #mb == 0 or not ma or #ma == 0 or not mb[#mb].Cframe or not ma[1].Cframe then return end
		for _, hitboxName in ipairs({ "startHitbox", "endHitbox" }) do
			local hitbox = Instance.new("Part")
			hitbox.Name = hitboxName
			local cfTable = (hitboxName == "startHitbox") and mb[#mb].Cframe or ma[1].Cframe
			hitbox.CFrame = C.TableToCFrame(cfTable)
			hitbox.Anchored = true
			hitbox.Color = (hitboxName == "startHitbox") and Color3.fromRGB(205, 10, 0) or Color3.fromRGB(0, 185, 8)
			hitbox.Transparency = 0.5
			hitbox.CanCollide, hitbox.CanQuery, hitbox.CanTouch = false, false, false
			hitbox.Size = Vector3.new(2.1, 2.1, 1.1)
			hitbox.TopSurface = Enum.SurfaceType.Smooth
			hitbox.Parent = workspace.CurrentCamera or workspace
			C.hitboxes[#C.hitboxes + 1] = hitbox
		end
	end

	-- --------------------------------------------------------------------------------------------- public
	function Core.GetTAS(length) return length and #C.data or C.data end

	function Core.SetTAS(LoadedTAS, whenMerge)
		if whenMerge then
			C.oldTAS = C.data
			if whenMerge == "after" then C.mergeBefore = C.data; C.mergeAfter = LoadedTAS
			else C.mergeBefore = LoadedTAS; C.mergeAfter = C.data end
			local mb, ma = C.mergeBefore, C.mergeAfter
			if not mb or #mb == 0 or not ma or #ma == 0 then
				task.spawn(C.SetStatus, "Cannot merge: one of the TAS runs is empty", true)
				C.merge = false
				return
			end
			if not mb[#mb].Cframe or not ma[1].Cframe then
				task.spawn(C.SetStatus, "Cannot merge: missing frame data", true)
				C.merge = false
				return
			end
			C.data = { mb[#mb] }
			C.DataChanged()
			C.mergeBaseHeld = InputSys.HeldAt(mb, #mb - 1)
			C.merge = true
			inputs.Create()
			C.CreateMergeHitboxes()
			local t1 = mb[#mb].FrameTime or 0.016
			local t2 = ma[1].FrameTime or 0.016
			C.mergeReqDist = 16 * (t1 + t2) / 2
			C.mergeCFrame = ma[1].Cframe
		else
			C.data = LoadedTAS or {}
			C.DataChanged()
			Lighting.Clear()
			Lighting.LoadFromData(C.data)
			if C.mode == 2 then
				C.frame = #C.data
				if #C.data > 0 then
					C.LoadFrame(C.data[#C.data])
					if C.data[#C.data].Zoom then Bridge.SetZoom(C.data[#C.data].Zoom, true) end
				end
			end
		end
	end

	function Core.GetMode() return C.mode end
	function Core.GetFrame() return C.frame end
	function Core.IsPaused() return C.paused end
	function Core.IsMerging() return C.merge end
	function Core.DataVersion() return C.dataVersion end

	function Core.Shutdown()
		pcall(function()
			if C.HRP and C.HRP.Parent and C.mode ~= 1 then inputs.Idle() end
			if C.HRP and C.HRP.Parent then C.HRP.Anchored = false end
		end)
		pcall(C.DestroyMergeHitboxes)
		pcall(InputSys.ReplayEnd)
		pcall(ClientObjects.EndPlayback)
		pcall(Buttons.Release)
		pcall(Lighting.Release)
		pcall(KitObjects.Release)
		pcall(Bridge.LockShiftlock, false)
		pcall(Bridge.LockAnimations, false)
		pcall(Bridge.SetFreeMouse, false)
	end

	function Core.CharLoad(char)
		local hum = char:WaitForChild("Humanoid", 30)
		local root = char:WaitForChild("HumanoidRootPart", 30)
		if not hum or not root or Janitor.unloading then return end
		C.Humanoid, C.HRP, C.Char = hum, root, char
		C.Torso = char:FindFirstChild("Torso")
		C.RootJoint = root:FindFirstChild("RootJoint")
		on(hum.Died, function()
			if Settings.On("Record Death & Respawn") then return end -- the recording / replay keeps going
			if C.mode == 2 and not C.paused and #C.data > 0 then
				C.data[#C.data] = nil
				C.DataChanged()
			end
			if C.mode ~= 1 then inputs.Idle() end
		end)
	end
end

do
	local inputs = C.inputs
	local rs = RunService
	local uis = UIS
	local RENDER_BIND = "HappaTASLate"

	local function finishTest()
		local data = C.data
		local lastFr = (#data > 0) and (data[#data] or data[C.frame]) or nil
		local endZoom = (lastFr and tonumber(lastFr.Zoom)) or (C.pose and C.pose.Zoom) or Bridge.GetZoom()
		local endShift = lastFr and lastFr.ShiftLock or nil
		Bridge.ResetGhost()
		pcall(function() workspace.CurrentCamera.CameraType = Enum.CameraType.Custom end)
		InputSys.ReplayEnd()
		ClientObjects.EndPlayback()
		Buttons.Release()
		Lighting.Release()
		KitObjects.Release()
		ToolSync.ReplayEnd()
		C.mode, C.frame = 1, 1
		C.anchor(false)
		Bridge.SetCameraFreeze(false, false)
		Bridge.LockShiftlock(false)
		Bridge.LockAnimations(false)
		Bridge.SetFreeMouse(false)
		Bridge.RestoreCameraAfterTest(endZoom, endShift)
		C.guardFrames = 45
		Cursor.Reset()
		local data = C.data
		if not C.QuitTestEvent and #data > 0 and data[#data] and data[#data].TotalTime and Settings.On("Show Completion Message") then
			task.spawn(C.SetStatus, "TAS Completed [Time: " .. C.ToTime(data[#data].TotalTime) .. "]")
		end
		if uis.TouchEnabled and C.MobileUI then
			for _, v in pairs(C.MobileUI.MobileModes:GetChildren()) do v.Visible = true end
			C.MobileUI.MenuOpener.Visible = true
			C.MobileUI.More.Visible = true
		end
		if C.QuitTestEvent then C.QuitTestEvent:Disconnect(); C.QuitTestEvent = nil end
	end

	local function menuOpen()
		return Menu.IsModalOpen ~= nil and Menu.IsModalOpen()
	end
	local function isMode2MouseLocked()
		if C.mode == 2 and C.paused and not C.FirstFrameRecord and #C.data > 0 and C.SetCam() and not C.LookAround then
			local fr = C.data[C.frame]
			if fr and fr.Cframe then
				return fr.ShiftLock == 1 or (tonumber(fr.Zoom) or 99) <= 0.55
			end
		end
		return Bridge.IsInFirstPerson() or Bridge.IsShiftlocked()
	end
	local function holdPausedCamera()
		if C.mode ~= 2 or not C.paused or C.FirstFrameRecord or C.LookAround or not C.SetCam() then return end
		local fr = C.data[C.frame]
		if fr and fr.CamCframe then
			C.UpdateCamera(fr, false)
		end
	end

	-- mouse lock rules: free while paused with a locked camera / testing with a scriptable camera.
	-- For a short time after HappaTAS hands the camera back, the camera's mouse lock is checked
	-- every frame (stale first person state from older camera scripts), never longer.
	local function updateMouseMode()
		local modal = menuOpen()
		local camFreeze = (C.mode == 2 and C.paused and not C.FirstFrameRecord and #C.data > 0 and C.SetCam() and not C.LookAround)
		local freezeZoom = camFreeze
		local lockedView = (C.mode == 2 and not modal) and isMode2MouseLocked() or false
		local forceLock = camFreeze and lockedView
		Bridge.SetCameraFreeze(camFreeze, forceLock, freezeZoom)
		local free = false
		if modal then
			free = true
		elseif C.mode == 3 and Settings.On("Lock Camera (Test)") then
			free = true
		elseif camFreeze and not lockedView then
			free = true
		end
		Bridge.SetFreeMouse(free)
		if not free and C.mode ~= 3 then
			if C.mode == 2 or C.guardFrames > 0 then
				if C.guardFrames > 0 then C.guardFrames = C.guardFrames - 1 end
				Bridge.GuardMouse(modal, forceLock)
			end
		end
	end

	-- ---------------------------------------------------------------------------------------- PreRender
	local function preRender(dt)
		Profiler.FrameBegin(dt)
		Profiler.Begin("HappaTAS")
		local data, mode = C.data, C.mode
		if not (mode == 2 and (not C.paused or C.FirstFrameRecord)) then InputSys.Clear() end

		if mode == 2 and C.CharLoaded() then
			if not C.paused and C.NotDead() and not C.FirstFrameRecord then
				Profiler.Begin("Record")
				local HRP = C.HRP
				local n = #data
				-- (speed hack: this frame's physics ran recScale times slower than normal)
				local k = C.recScale
				local dtN = C.LastFrameTime * k
				local ft = r(dtN, 1000000)
				local total = (n >= 1 and data[n].TotalTime) and r(data[n].TotalTime + dtN, 1000000) or ft
				local lin, ang = HRP.AssemblyLinearVelocity, HRP.AssemblyAngularVelocity
				if k ~= 1 then lin, ang = lin / k, ang / k end
				local mx, my, uvx, uvy, vx, vy = InputSys.Mouse()
				local vpChanged = (n == 0 or vx ~= C.lastVX or vy ~= C.lastVY)
				if vpChanged then C.lastVX, C.lastVY = vx, vy end
				local curZoom = r(Bridge.GetZoom(), 1000)
				-- the simulation and wall clocks of this frame: client objects move on them (see ClientObjects)
				C.recSim, C.recWall = time(), os.clock()
				data[n + 1] = {
					Velocity = { Linear = C.Vector3ToTable(lin), Angular = C.Vector3ToTable(ang) },
					CamCframe = C.CFrameToTable(workspace.CurrentCamera.CFrame),
					ShiftLock = Bridge.IsShiftlocked() and 1 or 0,
					Mobile = C.IsMobile and C.ReadMobile() or nil,
					Zoom = curZoom,
					FrameTime = ft,
					TotalTime = total,
					Input = InputSys.Take(),
					MX = mx, MY = my, UVX = uvx, UVY = uvy,
					VX = vpChanged and vx or nil, VY = vpChanged and vy or nil,
					-- (slow motion: the factor this frame's physics ran with, see ClientObjects.RestoreUnpause)
					SK = (k ~= 1) and r(k, 10000) or nil,
				}
				KitClock.Mark(data, n + 1) -- (the kit's time of this frame: a pause goes back to it)
				Profiler.End("Record")
			end
			if C.paused then
				holdPausedCamera()
			end
			updateMouseMode()
		elseif mode == 3 and C.CharLoaded() and data[C.frame + 1] and C.TestingTimer >= 0 then
			Profiler.Begin("Playback")
			local p = C.PlaybackPose()
			C.SyncCharacter(p.root, p.lin, p.ang)
			C.UpdateCamera(p)
			if C.SetCam() then
				Bridge.UpdateGhost(p.Zoom, dt, false)
			end
			Profiler.End("Playback")
		end
		-- speed hack: on while the character records (Create, unpaused or the first frame of an unpause,
		-- alive), for the physics step that comes next
		local hum = C.Humanoid
		local recording = mode == 2 and (not C.paused or C.FirstFrameRecord) and C.CharLoaded() and hum.Health > 0
		C.recScale = SpeedHack.Update(recording, hum, C.HRP, mode ~= 3)
		-- the kit's objects on the TAS time of the frame shown (beat blocks, bullets...), and the kit's clock:
		-- the TAS clock while recording (x the speed hack), stopped while paused, the playback speed in Test
		Profiler.Begin("Kit")
		local kitRate = 1
		if mode == 2 then
			local rec = not C.paused or C.FirstFrameRecord
			local f = rec and #data or C.frame
			local fr = data[f]
			KitObjects.Frame(2, data, f, fr and fr.TotalTime or 0, rec and #data > 0)
			kitRate = rec and C.recScale or 0
		elseif mode == 3 then
			KitObjects.Frame(3, data, C.frame, C.TestingTimer, false)
			kitRate = math.max(0, Settings.Get("Playback Speed"))
		else
			KitObjects.Frame(1, data, 0, 0, false)
		end
		KitClock.SetRate(kitRate)
		Profiler.End("Kit")
		Profiler.End("HappaTAS")
		Profiler.FrameEnd() -- the end of this frame's jobs as far as a script can see (Jobs Wall Time)
	end

	-- ---------------------------------------------------------------------------------------- PreSimulation
	-- the frame made in the last render step gets the character's state, client objects, tools and buttons.
	-- Normally in PreSimulation (before the frame's physics). Roblox steps physics at 240 Hz and a frame
	-- without a physics step has no PreSimulation (measured: at 240 FPS one frame in five), so then it is
	-- done in Heartbeat (nothing has moved since)
	local function fillFrame(data)
		local fd = data[#data]
		if not (fd and fd.Cframe == nil) then return end
		Profiler.Begin("Record")
		local HRP, hum = C.HRP, C.Humanoid
		local state = hum:GetState()
		fd.Cframe = C.CFrameToTable(HRP.CFrame)
		fd.State = state.Value
		fd.Anim = Bridge.GetAnimation(#data == 2)
		Profiler.End("Record")
		Profiler.Begin("Client Objects")
		fd.CO = ClientObjects.Record(HRP.Position, fd.TotalTime, C.recSim, C.recWall, fd, data)
		Profiler.End("Client Objects")
		fd.Tools = ToolSync.Take()
		Profiler.Begin("Buttons")
		fd.BT = Buttons.RecordFrame(fd.TotalTime, #data == 1)
		Profiler.End("Buttons")
		fd.LT = Lighting.RecordFrame(#data, fd.TotalTime, #data == 1)
		if state == Enum.HumanoidStateType.Dead or hum.Health <= 0 then fd.Died = true end
	end

	local function preSimulation()
		Profiler.Begin("HappaTAS")
		KitObjects.Reassert()
		local data = C.data
		if C.mode == 2 and C.CharLoaded() and not C.paused and not C.FirstFrameRecord and C.NotDead() then
			fillFrame(data)
		elseif C.mode == 3 and C.CharLoaded() and data[C.frame + 1] and C.TestingTimer >= 0 then
			if Settings.On("Interpolate Playback") then
				local p = C.PlaybackPose()
				C.SyncCharacter(p.root, p.lin, p.ang)
			elseif data[C.frame] and data[C.frame].Cframe and data[C.frame].Velocity then
				C.SyncFrame(data[C.frame])
			end
			C.Humanoid:Move(C.HRP.AssemblyLinearVelocity)
		end
		Profiler.End("HappaTAS")
	end

	-- ---------------------------------------------------------------------------------------- Heartbeat
	-- the character, camera and animation stay on frame fr (no blending)
	local function holdPose(fr)
		if fr.Cframe and fr.Velocity then C.SyncFrame(fr) end
		C.UpdateCamera(fr)
		if fr.Anim and fr.Anim.Anims then Bridge.SetAnimation(fr.Anim, fr.Anim.Anims, 0) end
	end
	local function playbackStep(dt)
		local data = C.data
		local speed = Settings.Get("Playback Speed")
		C.TestingTimer = C.TestingTimer + C.LastFrameTime * speed

		if Settings.On("Interpolate Playback") then
			local prevFrame = C.frame
			while data[C.frame + 1] and C.TestingTimer > (data[C.frame + 1].TotalTime or 0) do C.frame = C.frame + 1 end
			while C.frame > 1 and data[C.frame - 1] and C.TestingTimer < (data[C.frame - 1].TotalTime or 0) do C.frame = C.frame - 1 end
			local frame = C.frame
			if frame > 0 then InputSys.ReplayTo(data, frame) end
			if not data[frame + 1] or frame == 0 or not data[frame] then return end
			InputSys.ReplayMouse(data[frame])
			Profiler.Begin("Client Objects")
			ClientObjects.PlaybackTo(data, frame, C.TestingTimer)
			Profiler.End("Client Objects")
			Profiler.Begin("Buttons")
			Buttons.PlaybackTo(data, frame, C.TestingTimer)
			Profiler.End("Buttons")
			Lighting.PlaybackTo(data, frame)

			if data[frame + 1].FrameTime and data[frame + 1].FrameTime > 0.1 then
				holdPose(data[frame]) -- a lag spike was recorded here: hold the frame instead of sliding through it
				return
			end

			local p = C.PlaybackPose()
			C.SyncCharacter(p.root, p.lin, p.ang)
			if data[frame].State then C.ChangeState(data[frame].State) end
			C.UpdateCamera(p)
			local lo, hi = prevFrame + 1, frame
			if lo > hi then lo, hi = frame, frame end
			for f = lo, hi do
				local fr = data[f]
				if fr and f > prevFrame then
					if fr.Anim and fr.Anim.Anims then
						Bridge.SetAnimation(fr.Anim, { fr.Anim.Anims[#fr.Anim.Anims] }, speed)
					end
					if fr.Tools then ToolSync.ReplayFrame(fr.Tools, C.Char) end
				end
			end
			if data[frame].Died then C.ChangeState(Enum.HumanoidStateType.Dead) end
			ToolSync.Step(C.Char, C.Humanoid)
			C.SetStats("Test")
		else
			C.frame = C.frame + 1
			local frame = C.frame
			local fr = data[frame]
			if not fr then return end
			InputSys.ReplayTo(data, frame)
			InputSys.ReplayMouse(fr)
			ClientObjects.PlaybackTo(data, frame, nil)
			Buttons.PlaybackTo(data, frame, fr.TotalTime)
			Lighting.PlaybackTo(data, frame)
			local FrameTime = fr.FrameTime or 0
			if C.FreezeTimeRemaining > dt then
				holdPose(fr)
				C.FreezeTimeRemaining = C.FreezeTimeRemaining - dt
				return
			end
			if FrameTime > 2 * dt then
				C.FreezeTimeRemaining = FrameTime - dt
				return
			end
			C.LoadFrame(fr)
			if fr.Anim and fr.Anim.Anims then Bridge.SetAnimation(fr.Anim, fr.Anim.Anims, speed) end
			if fr.Tools then ToolSync.ReplayFrame(fr.Tools, C.Char) end
			ToolSync.Step(C.Char, C.Humanoid)
			C.SetStats("Test")
		end

		local fr = data[C.frame]
		if fr and type(fr.Mobile) == "table" and uis.TouchEnabled then C.ReplayMobile(fr.Mobile) end
	end

	local function heartbeat(dt)
		Profiler.Heartbeat()
		Profiler.Begin("HappaTAS")
		local mode, data = C.mode, C.data
		if mode ~= 3 and InputSys.IsReplaying() then InputSys.ReplayEnd() end
		if mode ~= 3 and ClientObjects.IsTesting() then ClientObjects.EndPlayback() end
		if mode == 1 and ClientObjects.IsHolding() then ClientObjects.Release() end

		if C.CharLoaded() then
			if mode == 1 then
				C.SetStats("Idle", nil, dt)
			elseif mode == 2 then
				if C.paused then
					ClientObjects.Tick()
					if #data > 1 and C.back and C.frame > 1 then
						C.frame = C.frame - 1
						if data[C.frame] then C.LoadFrame(data[C.frame], false, true) end
					end
					if C.frame < #data and C.forw then
						C.frame = C.frame + 1
						if data[C.frame] then C.LoadFrame(data[C.frame], false, true) end
					end
					Buttons.Step(data[C.frame] and data[C.frame].TotalTime or 0)
				else
					if C.FirstFrameRecord and #data == 1 then
						data[1].FrameTime = r(C.LastFrameTime * C.recScale, 1000000)
						data[1].TotalTime = r(C.LastFrameTime * C.recScale, 1000000)
					end
					-- a frame without a physics step had no PreSimulation: filled here (it used to be dropped,
					-- with its time and inputs: a TAS recorded at 240 FPS replayed about 12 % too fast)
					if #data > 0 and data[#data].Cframe == nil and not C.FirstFrameRecord and C.NotDead() then fillFrame(data) end
					if #data > 0 and data[#data].Cframe == nil then data[#data] = nil end
					C.frame = #data
					if #data > 0 and not C.FirstFrameRecord then KitObjects.AfterPhysics(data, #data) end
					Buttons.Step(data[#data] and data[#data].TotalTime or 0)
				end
				C.SetStats("Create", data[C.frame], dt, C.frame)
			elseif mode == 3 and data[C.frame + 1] and C.TestingTimer >= 0 then
				Profiler.Begin("Playback")
				playbackStep(dt)
				Profiler.End("Playback")
			elseif mode == 3 then
				finishTest()
			end
		end
		C.LastFrameTime = dt

		if C.CurrentFrameInput then
			C.InputDebounce = C.InputDebounce + 1
			if C.InputDebounce == 3 then C.InputDebounce = 0; C.CurrentFrameInput = false end
		end
		Profiler.End("HappaTAS")
	end

	-- ---------------------------------------------------------------------------------------- end of render step
	local function lateRender()
		Profiler.Begin("HappaTAS")
		if C.mode == 2 then
			if C.paused and not C.FirstFrameRecord and #C.data > 0 and C.SetCam() and not C.LookAround then
				holdPausedCamera()
				local fr = C.data[C.frame]
				if fr then Bridge.UpdateGhost(fr.Zoom, C.LastFrameTime, true) end
			else
				Bridge.ResetGhost(true)
			end
		elseif C.mode == 3 and C.SetCam() then
			local fr = C.data[C.frame]
			local z = (C.pose and C.pose.Zoom) or (fr and fr.Zoom) or Bridge.GetZoom()
			Bridge.UpdateGhost(z, C.LastFrameTime, false)
		end
		ClientObjects.RenderStep()
		Buttons.RenderStep()
		Lighting.RenderStep()
		KitObjects.Reassert()
		updateMouseMode()
		Profiler.Begin("Cursor")
		Cursor.Update(C.mode, (C.mode == 3 or (C.mode == 2 and C.paused and #C.data > 0 and C.SetCam() and not C.LookAround)) and C.data[C.frame] or nil, menuOpen)
		Profiler.End("Cursor")
		Profiler.End("HappaTAS")
	end

	-- ---------------------------------------------------------------------------------------- start
	function Core.Start(gui)
		C.Gui = gui
		C.MobileUI = gui.Mobile
		C.MergeStats = gui.MergeStats
		C.IdleStatsF = gui.IdleStats
		C.CreateStatsF = gui.CreateStats
		C.TestStatsF = gui.TestStats
		local MobileUI = C.MobileUI

		on(rs.PreRender, function(dt)
			local ok, err = pcall(preRender, dt)
			if not ok then reportError("PreRender", err) end
		end)
		on(rs.PreSimulation, function()
			local ok, err = pcall(preSimulation)
			if not ok then reportError("PreSimulation", err) end
		end)
		on(rs.Heartbeat, function(dt)
			local ok, err = pcall(heartbeat, dt)
			if not ok then reportError("Heartbeat", err) end
		end)
		pcall(function()
			rs:BindToRenderStep(RENDER_BIND, Enum.RenderPriority.Last.Value + 1, function()
				local ok, err = pcall(lateRender)
				if not ok then reportError("render step", err) end
			end)
		end)
		Janitor.add(function() pcall(function() rs:UnbindFromRenderStep(RENDER_BIND) end) end)

		-- MicroProfiler: TAS timeline data + scrubbing (Create while paused, or Test)
		Profiler.GetTAS = function() return C.data, C.frame, C.dataVersion end
		Profiler.OnScrub = function(target)
			local data = C.data
			target = clampn(math.floor(target), 1, math.max(1, #data))
			if C.mode == 2 and C.paused and data[target] then
				C.frame = target
				C.LoadFrame(data[target], false, true)
			elseif C.mode == 3 and data[target] and data[target + 1] then
				C.frame = target
				C.TestingTimer = data[target].TotalTime or 0
				InputSys.ReplayTo(data, target)
				C.poseT = nil
			end
		end

		on(uis.JumpRequest, function()
			if C.Humanoid and C.mode == 2 and C.frame > 1 and C.CanCoyoteJump() then
				C.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			end
		end)

		on(uis.InputBegan, function(inp, proc)
			if Typing.Active(inp) then return end -- typing in chat / a text box, the Roblox menu, binding a key
			-- the MicroProfiler key works even when the game processed the input
			if CheckInput(inp, "MicroProfiler") then
				Settings.Set("Show MicroProfiler", Settings.On("Show MicroProfiler") and 0 or 1)
				return
			end
			if inp.KeyCode == Enum.KeyCode.P and Profiler.active and (uis:IsKeyDown(Enum.KeyCode.LeftControl) or uis:IsKeyDown(Enum.KeyCode.RightControl)) then
				Profiler.TogglePause()
				return
			end
			if InputSys.ClickOnOwnUI(inp) then return end -- a click on the HappaTAS menu is for the menu
			if proc and not Settings.On("Ignore Game Processed") then return end
			if not C.Humanoid then return end
			local mode, paused, data, merge = C.mode, C.paused, C.data, C.merge
			if CheckInput(inp, "Idle") and not merge then inputs.Idle()
			elseif CheckInput(inp, "Create") and not merge then inputs.Create()
			elseif CheckInput(inp, "Test") and #data > 0 and not merge then inputs.Test()
			elseif CheckInput(inp, "Unpause") and mode == 2 and paused then inputs.Unpause()
			elseif CheckInput(inp, "Pause") and mode == 2 and not paused then inputs.Pause()
			elseif CheckInput(inp, "Unpause 1 Frame") and mode == 2 and paused then inputs.Unpause1F()
			elseif CheckInput(inp, "Return") and mode == 2 and #data > 0 then inputs.Return()
			elseif CheckInput(inp, "Back 1 Frame") and mode == 2 and #data > 1 and C.frame > 1 then inputs.Back1F()
			elseif CheckInput(inp, "Forward 1 Frame") and mode == 2 and C.frame < #data then inputs.Forward1F()
			elseif CheckInput(inp, "Back") and mode == 2 then inputs.Back()
			elseif CheckInput(inp, "Forward") and mode == 2 then inputs.Forward()
			elseif CheckInput(inp, "Delete TAS") and not merge then inputs.Delete()
			elseif CheckInput(inp, "Optimize TAS") then inputs.Optimize()
			elseif CheckInput(inp, "Look Around") and mode == 2 and paused and Settings.On("Lock Camera (Paused)") then inputs.LookAround()
			elseif CheckInput(inp, "Toggle Speed Hack") then Settings.Set("Speed Hack", Settings.On("Speed Hack") and 0 or 1) end
		end)

		on(uis.InputEnded, function(inp)
			if CheckInput(inp, "Back") then C.back = false end
			if CheckInput(inp, "Forward") then C.forw = false end
		end)

		-- mobile buttons
		local function SetPauseButton(pausedNow)
			local icon = MobileUI.MobileCreate.Pause.Icon
			if pausedNow then
				icon.Image = "rbxassetid://10392248278"
				icon.Size = UDim2.new(0.285, 0, 0.7, 0)
				icon.Position = UDim2.new(0.357, 0, 0.132, 0)
			else
				icon.Image = "rbxassetid://4458862490"
				icon.Size = UDim2.new(0.471, 0, 1, 0)
				icon.Position = UDim2.new(0.262, 0, 0, 0)
			end
		end
		local function ShowCreateButtons(visible)
			for _, b in pairs(MobileUI.MobileCreate:GetChildren()) do b.Visible = visible end
		end
		on(MobileUI.MobileModes.Mode1Mobile.MouseButton1Click, function() inputs.Idle(); ShowCreateButtons(false) end)
		on(MobileUI.MobileModes.Mode2Mobile.MouseButton1Click, function() inputs.Create(); ShowCreateButtons(true); SetPauseButton(true) end)
		on(MobileUI.MobileModes.Mode3Mobile.MouseButton1Click, function()
			if #C.data < 1 then return end
			inputs.Test()
			for _, v in pairs(MobileUI:GetChildren()) do
				if v:IsA("Folder") then
					for _, z in pairs(v:GetChildren()) do z.Visible = false end
				else v.Visible = false end
			end
			task.wait(0.1)
			local ConfirmQuit = false
			if C.QuitTestEvent then C.QuitTestEvent:Disconnect() end
			C.QuitTestEvent = uis.TouchTap:Connect(function()
				if ConfirmQuit then C.frame = #C.data; task.spawn(C.SetStatus, "Test Quit")
				else ConfirmQuit = true; C.SetStatus("Tap Again to Quit Test"); ConfirmQuit = false end
			end)
			Janitor.add(C.QuitTestEvent)
		end)
		on(MobileUI.MobileCreate.Pause.MouseButton1Click, function()
			if C.paused then inputs.Unpause(); SetPauseButton(false) else inputs.Pause(); SetPauseButton(true) end
		end)
		on(MobileUI.MobileCreate.Unpause1Frame.MouseButton1Click, function() if C.paused then inputs.Unpause1F() end end)
		on(MobileUI.MobileCreate.Return.MouseButton1Click, function() if #C.data > 0 then inputs.Return(); SetPauseButton(true) end end)
		on(MobileUI.MobileCreate.Back1Frame.MouseButton1Click, function() if #C.data > 1 and C.frame > 1 then inputs.Back1F(); SetPauseButton(true) end end)
		on(MobileUI.MobileCreate.Forward1Frame.MouseButton1Click, function() if C.frame < #C.data then inputs.Forward1F(); SetPauseButton(true) end end)
		on(MobileUI.MobileCreate.Back.MouseButton1Down, function() inputs.Back(); SetPauseButton(true) end)
		on(MobileUI.MobileCreate.Forward.MouseButton1Down, function() inputs.Forward(); SetPauseButton(true) end)
		on(MobileUI.MobileCreate.Back.MouseButton1Up, function() C.back = false end)
		on(MobileUI.MobileCreate.Forward.MouseButton1Up, function() C.forw = false end)
		on(MobileUI.MobileOptions.Delete.MouseButton1Click, function() inputs.Delete(true) end)
		on(MobileUI.MobileOptions.Optimize.MouseButton1Click, function() inputs.Optimize(true) end)
		on(MobileUI.MobileCreate.LookAround.MouseButton1Click, function()
			if C.paused and Settings.On("Lock Camera (Paused)") then inputs.LookAround() end
		end)

		on(C.MergeStats.MouseButton1Click, function()
			if C.mergeCanComplete then
				C.merge = false
				inputs.Idle()
				C.DestroyMergeHitboxes()
				local newData = {}
				local mb, ma = C.mergeBefore, C.mergeAfter
				local beginRetiming = #mb
				table.move(mb, 1, #mb, 1, newData)
				table.move(C.data, 2, #C.data, #newData + 1, newData)
				table.move(ma, 1, #ma, #newData + 1, newData)
				for i = math.max(2, beginRetiming), #newData do
					newData[i].TotalTime = r(newData[i].FrameTime + newData[i - 1].TotalTime, 1000000)
				end
				C.oldTAS, C.mergeBefore, C.mergeAfter, C.mergeBaseHeld = {}, {}, {}, nil
				C.data = newData
				C.DataChanged()
				task.spawn(C.SetStatus, "Merge Complete")
			else
				C.merge = false
				inputs.Idle()
				C.DestroyMergeHitboxes()
				C.data = C.oldTAS
				C.DataChanged()
				C.oldTAS, C.mergeBefore, C.mergeAfter, C.mergeBaseHeld = {}, {}, {}, nil
				task.spawn(C.SetStatus, "Merge Cancelled")
			end
		end)

		Settings.Changed("Lock Camera (Paused)", function()
			if C.mode == 2 and C.paused and C.data[C.frame] then C.LoadFrame(C.data[C.frame]) end
		end)
	end
end

