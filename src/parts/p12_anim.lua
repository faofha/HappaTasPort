-- ================================================================================================
--  ANIMATE ENGINE  (the original HappaTAS R6 Animate script, recorded per frame)
-- ================================================================================================
AnimEngine.current, AnimEngine.disabledAnimate, AnimEngine.emotesWereEnabled = nil, nil, nil
do
	local function loaderOf(humanoid)
		return humanoid:FindFirstChildOfClass("Animator") or humanoid
	end
	local function A(id) return "http://www.roblox.com/asset/?id=" .. id end
	local ANIM_DEFS = {
		idle      = { { id = A(180435571), weight = 9 }, { id = A(180435792), weight = 1 } },
		walk      = { { id = A(180426354), weight = 1 } },
		run       = { { id = A(180426354), weight = 1 } },
		jump      = { { id = A(125750702), weight = 1 } },
		fall      = { { id = A(180436148), weight = 1 } },
		climb     = { { id = A(180436334), weight = 1 } },
		sit       = { { id = A(178130996), weight = 1 } },
		toolnone  = { { id = A(182393478), weight = 1 } },
		toolslash = { { id = A(129967390), weight = 10 } },
		toollunge = { { id = A(129967478), weight = 10 } },
		wave      = { { id = A(128777973), weight = 10 } },
		point     = { { id = A(128853357), weight = 10 } },
		dance1    = { { id = A(182435998), weight = 10 }, { id = A(182491037), weight = 10 }, { id = A(182491065), weight = 10 } },
		dance2    = { { id = A(182436842), weight = 10 }, { id = A(182491248), weight = 10 }, { id = A(182491277), weight = 10 } },
		dance3    = { { id = A(182436935), weight = 10 }, { id = A(182491368), weight = 10 }, { id = A(182491423), weight = 10 } },
		laugh     = { { id = A(129423131), weight = 10 } },
		cheer     = { { id = A(129423030), weight = 10 } },
	}
	local dances = { "dance1", "dance2", "dance3" }
	local emoteNames = { wave = false, point = false, dance1 = true, dance2 = true, dance3 = true, laugh = false, cheer = false }

	local AnimToNumber = {
		idle = 1, walk = 2, fall = 3, jump = 4, climb = 5, sit = 6, dance = 7, dance1 = 7, dance2 = 8, dance3 = 9,
		wave = 10, cheer = 11, point = 12, laugh = 13,
	}
	local NumberToAnim = { "idle", "walk", "fall", "jump", "climb", "sit", "dance1", "dance2", "dance3", "wave", "cheer", "point", "laugh" }

	local PoseToNumber = {
		Running = 1, Standing = 2, Jumping = 3, Climbing = 4, GettingUp = 5, FreeFall = 6, FallingDown = 7,
		Seated = 8, PlatformStanding = 9,
	}
	local NumberToPose = { "Running", "Standing", "Jumping", "Climbing", "GettingUp", "FreeFall", "FallingDown", "Seated", "PlatformStanding" }

	local EMOTE_TRANSITION_TIME = 0.1

	local function newEngine(Figure, Humanoid, Torso)
		local self = { alive = true }
		local conns = {}
		local function connect(sig, fn)
			local cn = sig:Connect(fn)
			conns[#conns + 1] = cn
			return cn
		end

		local RightShoulder = Torso:FindFirstChild("Right Shoulder")
		local LeftShoulder = Torso:FindFirstChild("Left Shoulder")
		local RightHip = Torso:FindFirstChild("Right Hip")
		local LeftHip = Torso:FindFirstChild("Left Hip")
		if not (RightShoulder and LeftShoulder and RightHip and LeftHip) then return nil end

		local FrameAnims = {}
		local handedOut = false -- FrameAnims went into a recorded frame: the next frame needs a new table
		local function useFrameAnims() handedOut = true return FrameAnims end
		local LockAnimations = false

		local pose = "Standing"
		local userAnimateScaleRun = false
		pcall(function() userAnimateScaleRun = UserSettings():IsUserFeatureEnabled("UserAnimateScaleRun") end)
		local function getRigScale()
			if userAnimateScaleRun then
				local ok, s = pcall(function() return Figure:GetScale() end)
				if ok and s then return s end
			end
			return 1
		end

		local currentAnim = ""
		local currentAnimInstance = nil
		local currentAnimTrack = nil
		local currentAnimKeyframeHandler = nil
		local currentAnimSpeed = 1.0

		local animTable = {}
		for name, list in pairs(ANIM_DEFS) do
			local t = { count = 0, totalWeight = 0 }
			for i, a in ipairs(list) do
				local anim = Instance.new("Animation")
				anim.Name = name
				anim.AnimationId = a.id
				t[i] = { anim = anim, weight = a.weight }
				t.count = t.count + 1
				t.totalWeight = t.totalWeight + a.weight
			end
			animTable[name] = t
		end

		local animator = Humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				pcall(function() track:Stop(0) track:Destroy() end)
			end
		end

		local toolAnim = "None"
		local toolAnimTime = 0
		local jumpAnimTime = 0
		local jumpAnimDuration = 0.3
		local toolTransitionTime = 0.1
		local fallTransitionTime = 0.3

		local playAnimation, stopAllAnimations, setAnimationSpeed, keyFrameReachedFunc
		local playToolAnimation, stopToolAnimations, toolKeyFrameReachedFunc

		function stopAllAnimations()
			local oldAnim = currentAnim
			if emoteNames[oldAnim] ~= nil and emoteNames[oldAnim] == false then
				oldAnim = "idle"
			end
			currentAnim = ""
			currentAnimInstance = nil
			if currentAnimKeyframeHandler ~= nil then
				currentAnimKeyframeHandler:Disconnect()
				currentAnimKeyframeHandler = nil
			end
			if currentAnimTrack ~= nil then
				currentAnimTrack:Stop()
				currentAnimTrack:Destroy()
				currentAnimTrack = nil
			end
			return oldAnim
		end

		-- (the track always runs at currentAnimSpeed, so an equal speed needs no AdjustSpeed call)
		function setAnimationSpeed(speed, TASanim)
			if speed ~= currentAnimSpeed and (TASanim or LockAnimations == false) then
				currentAnimSpeed = speed
				if currentAnimTrack then currentAnimTrack:AdjustSpeed(currentAnimSpeed) end
			end
		end

		function keyFrameReachedFunc(frameName)
			if frameName == "End" then
				local repeatAnim = currentAnim
				if emoteNames[repeatAnim] ~= nil and emoteNames[repeatAnim] == false then
					repeatAnim = "idle"
				end
				local animSpeed = currentAnimSpeed
				playAnimation(repeatAnim, 0.0, Humanoid)
				setAnimationSpeed(animSpeed, false)
			end
		end

		-- one of the animations of animName, picked by weight (like the Animate script)
		local function pick(animName)
			local list = animTable[animName]
			local roll = math.random(1, list.totalWeight)
			local idx = 1
			while roll > list[idx].weight do
				roll = roll - list[idx].weight
				idx = idx + 1
			end
			return list[idx].anim
		end

		function playAnimation(animName, transitionTime, humanoid, TASanim)
			if not TASanim and LockAnimations then return end
			if not animTable[animName] then return end
			local anim = pick(animName)

			if anim ~= currentAnimInstance then
				if not TASanim and AnimToNumber[animName] then
					table.insert(FrameAnims, { AnimToNumber[animName], transitionTime })
				end
				if currentAnimTrack ~= nil then
					currentAnimTrack:Stop(transitionTime)
					currentAnimTrack:Destroy()
				end
				currentAnimSpeed = 1.0
				currentAnimTrack = loaderOf(humanoid):LoadAnimation(anim)
				currentAnimTrack.Priority = Enum.AnimationPriority.Core
				currentAnimTrack:Play(transitionTime)
				currentAnim = animName
				currentAnimInstance = anim
				if currentAnimKeyframeHandler ~= nil then
					currentAnimKeyframeHandler:Disconnect()
				end
				currentAnimKeyframeHandler = currentAnimTrack.KeyframeReached:Connect(keyFrameReachedFunc)
			end
		end

		local toolAnimName = ""
		local toolAnimTrack = nil
		local toolAnimInstance = nil
		local currentToolAnimKeyframeHandler = nil

		function toolKeyFrameReachedFunc(frameName)
			if frameName == "End" then playToolAnimation(toolAnimName, 0.0, Humanoid) end
		end

		function playToolAnimation(animName, transitionTime, humanoid, priority)
			if not animTable[animName] then return end
			local anim = pick(animName)
			if toolAnimInstance ~= anim then
				if toolAnimTrack ~= nil then
					toolAnimTrack:Stop()
					toolAnimTrack:Destroy()
					transitionTime = 0
				end
				toolAnimTrack = loaderOf(humanoid):LoadAnimation(anim)
				if priority then toolAnimTrack.Priority = priority end
				toolAnimTrack:Play(transitionTime)
				toolAnimName = animName
				toolAnimInstance = anim
				if currentToolAnimKeyframeHandler ~= nil then currentToolAnimKeyframeHandler:Disconnect() end
				currentToolAnimKeyframeHandler = toolAnimTrack.KeyframeReached:Connect(toolKeyFrameReachedFunc)
			end
		end

		function stopToolAnimations()
			local oldAnim = toolAnimName
			if currentToolAnimKeyframeHandler ~= nil then
				currentToolAnimKeyframeHandler:Disconnect()
				currentToolAnimKeyframeHandler = nil
			end
			toolAnimName = ""
			toolAnimInstance = nil
			if toolAnimTrack ~= nil then
				toolAnimTrack:Stop()
				toolAnimTrack:Destroy()
				toolAnimTrack = nil
			end
			return oldAnim
		end

		local function onRunning(speed)
			speed = speed / getRigScale()
			if speed > 0.01 then
				playAnimation("walk", 0.1, Humanoid)
				if currentAnimInstance and currentAnimInstance.AnimationId == "http://www.roblox.com/asset/?id=180426354" then
					setAnimationSpeed(speed / 14.5, false)
				end
				pose = "Running"
			else
				if emoteNames[currentAnim] == nil then
					playAnimation("idle", 0.1, Humanoid)
					pose = "Standing"
				end
			end
		end

		local function onDied() pose = "Dead" end
		local function onJumping() playAnimation("jump", 0.1, Humanoid); jumpAnimTime = jumpAnimDuration; pose = "Jumping" end
		local function onClimbing(speed) speed = speed / getRigScale(); playAnimation("climb", 0.1, Humanoid); setAnimationSpeed(speed / 12.0, false); pose = "Climbing" end
		local function onGettingUp() pose = "GettingUp" end
		local function onFreeFall() if jumpAnimTime <= 0 then playAnimation("fall", fallTransitionTime, Humanoid) end pose = "FreeFall" end
		local function onFallingDown() pose = "FallingDown" end
		local function onSeated() pose = "Seated" end
		local function onPlatformStanding() pose = "PlatformStanding" end
		local function onSwimming(speed) pose = (speed > 0) and "Running" or "Standing" end

		local function getTool() return Figure:FindFirstChildOfClass("Tool") end

		local function getToolAnim(tool)
			for _, ch in ipairs(tool:GetChildren()) do
				if ch.Name == "toolanim" and ch.ClassName == "StringValue" then return ch end
			end
			return nil
		end

		local function animateTool()
			if toolAnim == "None" then playToolAnimation("toolnone", toolTransitionTime, Humanoid, Enum.AnimationPriority.Idle) return end
			if toolAnim == "Slash" then playToolAnimation("toolslash", 0, Humanoid, Enum.AnimationPriority.Action) return end
			if toolAnim == "Lunge" then playToolAnimation("toollunge", 0, Humanoid, Enum.AnimationPriority.Action) return end
		end

		local function move(time)
			local amplitude, frequency, climbFudge = 1, 1, 0
			local setAngles = false

			if pose == "FreeFall" and jumpAnimTime <= 0 then
				playAnimation("fall", fallTransitionTime, Humanoid)
			elseif pose == "Seated" then
				playAnimation("sit", 0.5, Humanoid)
				return
			elseif pose == "Running" then
				playAnimation("walk", 0.1, Humanoid)
			elseif pose == "Dead" or pose == "GettingUp" or pose == "FallingDown" or pose == "Seated" or pose == "PlatformStanding" then
				stopAllAnimations()
				amplitude, frequency, setAngles = 0.1, 1, true
			end

			if setAngles then
				local desiredAngle = amplitude * math.sin(time * frequency)
				RightShoulder:SetDesiredAngle(desiredAngle + climbFudge)
				LeftShoulder:SetDesiredAngle(desiredAngle - climbFudge)
				RightHip:SetDesiredAngle(-desiredAngle)
				LeftHip:SetDesiredAngle(-desiredAngle)
			end

			local tool = getTool()
			if tool and tool:FindFirstChild("Handle") then
				local animStringValueObject = getToolAnim(tool)
				if animStringValueObject then
					toolAnim = animStringValueObject.Value
					animStringValueObject.Parent = nil
					toolAnimTime = time + .3
				end
				if time > toolAnimTime then toolAnimTime = 0; toolAnim = "None" end
				animateTool()
			else
				stopToolAnimations()
				toolAnim, toolAnimInstance, toolAnimTime = "None", nil, 0
			end
		end

		connect(Humanoid.Died, onDied)
		connect(Humanoid.Running, onRunning)
		connect(Humanoid.Jumping, onJumping)
		connect(Humanoid.Climbing, onClimbing)
		connect(Humanoid.GettingUp, onGettingUp)
		connect(Humanoid.FreeFalling, onFreeFall)
		connect(Humanoid.FallingDown, onFallingDown)
		connect(Humanoid.Seated, onSeated)
		connect(Humanoid.PlatformStanding, onPlatformStanding)
		connect(Humanoid.Swimming, onSwimming)

		connect(LocalPlayer.Chatted, function(msg)
			local emote = ""
			if msg == "/e dance" then emote = dances[math.random(1, #dances)]
			elseif string.sub(msg, 1, 3) == "/e " then emote = string.sub(msg, 4)
			elseif string.sub(msg, 1, 7) == "/emote " then emote = string.sub(msg, 8) end

			if pose == "Standing" and emoteNames[emote] ~= nil then
				playAnimation(emote, EMOTE_TRANSITION_TIME, Humanoid)
			end
		end)

		function self.Get(StartOfTAS)
			if currentAnimTrack ~= nil then
				return {
					Pose = PoseToNumber[pose] or 0,
					JumpTime = math.round(jumpAnimTime * 1000) / 1000,
					Speed = math.round(currentAnimSpeed * 1000) / 1000,
					Anims = StartOfTAS and { { AnimToNumber[currentAnim] or 1, 0 } } or useFrameAnims(),
				}
			end
			return nil
		end

		function self.Set(AnimData, anim, PlaybackSpeed, TimeDifference)
			if anim then
				for _, v in pairs(anim) do
					local name = NumberToAnim[v[1]]
					if name and name ~= currentAnim then
						playAnimation(name, v[2] or 0, Humanoid, true)
					end
				end
			end
			pose = NumberToPose[AnimData.Pose] or pose
			jumpAnimTime = AnimData.JumpTime or 0
			setAnimationSpeed((AnimData.Speed or 1) * (PlaybackSpeed or 1), true)
			if TimeDifference and currentAnimTrack then
				currentAnimTrack.TimePosition = TimeDifference
			end
		end

		function self.Lock(lock) LockAnimations = lock end

		function self.Destroy()
			if not self.alive then return end
			self.alive = false
			for _, cn in ipairs(conns) do pcall(function() cn:Disconnect() end) end
			conns = {}
			pcall(stopToolAnimations)
			pcall(function()
				if currentAnimKeyframeHandler then currentAnimKeyframeHandler:Disconnect() end
				if currentAnimTrack then currentAnimTrack:Stop(0) currentAnimTrack:Destroy() currentAnimTrack = nil end
			end)
		end

		playAnimation("idle", 0.1, Humanoid)
		pose = "Standing"
		local st = Humanoid:GetState()
		if st == Enum.HumanoidStateType.Running or st == Enum.HumanoidStateType.RunningNoPhysics then
			onRunning(Humanoid.RootPart and Vector3.new(Humanoid.RootPart.AssemblyLinearVelocity.X, 0, Humanoid.RootPart.AssemblyLinearVelocity.Z).Magnitude or 0)
		elseif st == Enum.HumanoidStateType.Freefall then
			onFreeFall()
		elseif st == Enum.HumanoidStateType.Climbing then
			onClimbing(0)
		end

		connect(RunService.Heartbeat, function(deltaTime)
			if handedOut or #FrameAnims > 0 then FrameAnims = {}; handedOut = false end
			if jumpAnimTime > 0 then jumpAnimTime = jumpAnimTime - deltaTime end
		end)

		task.spawn(function()
			while self.alive and Figure.Parent ~= nil do
				task.wait(0.1)
				if not self.alive then break end
				pcall(move, os.clock())
			end
		end)

		return self
	end

	function AnimEngine.Detach()
		if AnimEngine.current then
			pcall(AnimEngine.current.Destroy)
			AnimEngine.current = nil
		end
		local old = AnimEngine.disabledAnimate
		AnimEngine.disabledAnimate = nil
		if old and old.Parent then pcall(function() old.Disabled = false end) end
	end

	function AnimEngine.Attach(char)
		AnimEngine.Detach()
		if not CONFIG.TakeOverAnimate then return end
		task.spawn(function()
			local hum = char:WaitForChild("Humanoid", 10)
			if not hum or Janitor.unloading then return end
			if hum.RigType ~= Enum.HumanoidRigType.R6 then return end
			local torso = char:WaitForChild("Torso", 5)
			if not torso or Janitor.unloading or char.Parent == nil then return end

			local old = char:FindFirstChild("Animate")
			if old and old:IsA("LocalScript") then
				local okD = pcall(function() old.Disabled = true end)
				if okD then AnimEngine.disabledAnimate = old end
			end
			if AnimEngine.emotesWereEnabled == nil and StarterGui then
				local okG, enabled = pcall(function() return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu) end)
				if okG then
					AnimEngine.emotesWereEnabled = enabled
					pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false) end)
				end
			end

			local okE, engine = pcall(newEngine, char, hum, torso)
			if okE and engine then
				if Janitor.unloading or char.Parent == nil then engine.Destroy() return end
				AnimEngine.current = engine
			else
				local o = AnimEngine.disabledAnimate
				AnimEngine.disabledAnimate = nil
				if o and o.Parent then pcall(function() o.Disabled = false end) end
			end
		end)
	end

	function AnimEngine.Shutdown()
		AnimEngine.Detach()
		if AnimEngine.emotesWereEnabled ~= nil and StarterGui then
			local was = AnimEngine.emotesWereEnabled
			AnimEngine.emotesWereEnabled = nil
			pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, was) end)
		end
	end

	local EMPTY_ANIM = { Pose = 0, JumpTime = 0, Speed = 1, Anims = {} }
	function Bridge.GetAnimation(startOfTAS)
		local e = AnimEngine.current
		if e then
			local d = e.Get(startOfTAS)
			if d then return d end
		end
		return EMPTY_ANIM
	end
	function Bridge.SetAnimation(animData, anim, playbackSpeed, timeDifference)
		local e = AnimEngine.current
		if e and animData then e.Set(animData, anim, playbackSpeed, timeDifference) end
	end
	function Bridge.LockAnimations(lock)
		local e = AnimEngine.current
		if e then e.Lock(lock) end
	end
end

