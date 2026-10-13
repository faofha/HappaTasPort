-- ================================================================================================
-- Headless Roblox mock: DataModel, services, local player + R6 character, executor API, frame driver
-- ================================================================================================
local C = M.Classes
local function cls(name, super, defaults, methods, events)
	local c = { Name = name, Super = super and C[super], Defaults = defaults or {}, Methods = methods or {}, Events = events or {} }
	C[name] = c
	return c
end

-- ------------------------------------------------------------------------------------------------ service classes
M.stats = {
	FrameTime = 1 / 60, HeartbeatTime = 0.0012, PhysicsStepTime = 0.0008, RenderCPUFrameTime = 0.0021, RenderGPUFrameTime = 0.0015,
	InstanceCount = 12345, PrimitivesCount = 321, MovingPrimitivesCount = 12, ContactsCount = 40, DataReceiveKbps = 3.5,
	DataSendKbps = 1.25, PhysicsReceiveKbps = 0.5, PhysicsSendKbps = 0.25, SceneDrawcallCount = 210, SceneTriangleCount = 150000,
	ShadowsDrawcallCount = 50, ShadowsTriangleCount = 40000, UI2DDrawcallCount = 30, UI2DTriangleCount = 2000, UI3DDrawcallCount = 0,
	UI3DTriangleCount = 0, HeartbeatTimeMs = 16.6, PhysicsStepTimeMs = 0.8, MemoryTrackingEnabled = true,
}
M.memMb = 1234.5
cls("Stats", "Instance", {}, {
	GetTotalMemoryUsageMb = function() return M.memMb end,
	GetMemoryUsageMbForTag = function() return 10 end,
})
C.Stats.Dynamic = function(_, k) return M.stats[k] end

cls("DataModel", "Instance", { PlaceId = 1234567, GameId = 7654321, JobId = "mock-job", PlaceVersion = 1, CreatorId = 1 })
cls("Workspace", "Model", { Gravity = 196.2, CurrentCamera = nil, DistributedGameTime = 0, StreamingEnabled = false,
	FallenPartsDestroyHeight = -500, SignalBehavior = nil, AllowThirdPartySales = false })
cls("Players", "Instance", { LocalPlayer = nil, MaxPlayers = 10, RespawnTime = 5 }, {}, { "PlayerAdded", "PlayerRemoving" })
cls("RunService", "Instance", {}, {}, { "PreRender", "RenderStepped", "PreAnimation", "PreSimulation", "Stepped",
	"PostSimulation", "Heartbeat" })
cls("UserInputService", "Instance", { MouseBehavior = Enum.MouseBehavior.Default, MouseIconEnabled = true, MouseDeltaSensitivity = 1,
	TouchEnabled = false, KeyboardEnabled = true, MouseEnabled = true, GamepadEnabled = false, VREnabled = false,
	AccelerometerEnabled = false, GyroscopeEnabled = false, OnScreenKeyboardVisible = false, ModalEnabled = false,
	PreferredInput = nil, MouseIcon = "" }, {}, { "InputBegan", "InputChanged", "InputEnded", "JumpRequest",
	"TextBoxFocused", "TextBoxFocusReleased", "TouchStarted", "TouchMoved", "TouchEnded", "TouchTap", "WindowFocused",
	"WindowFocusReleased", "LastInputTypeChanged", "GamepadConnected", "GamepadDisconnected", "PointerAction" })
cls("TweenService", "Instance")
cls("HttpService", "Instance", { HttpEnabled = false })
cls("StarterGui", "Instance", { ShowDevelopmentGui = true })
cls("GuiService", "Instance", { MenuIsOpen = false, SelectedObject = nil, AutoSelectGuiEnabled = true, GuiNavigationEnabled = true,
	TouchControlsEnabled = true, IsModalDialog = false, PreferredTransparency = 1, ReducedMotionEnabled = false },
	{}, { "MenuOpened", "MenuClosed", "UiMessageChanged" })
cls("TextService", "Instance")
cls("CoreGui", "Instance", { SelectionImageObject = nil, Version = 1 })
cls("Lighting", "Instance", { ClockTime = 14, Brightness = 2 })
cls("ReplicatedStorage", "Instance")
cls("ReplicatedFirst", "Instance")
cls("SoundService", "Instance", { RespectFilteringEnabled = true })
cls("ContentProvider", "Instance", { RequestQueueSize = 0 })
cls("ContextActionService", "Instance")
cls("Teams", "Instance")
cls("Chat", "Instance")
cls("TextChatService", "Instance")
cls("StarterPlayer", "Instance", { CameraMaxZoomDistance = 128, CameraMinZoomDistance = 0.5, CharacterWalkSpeed = 16 })
cls("StarterPack", "Instance")
cls("CollectionService", "Instance")
cls("PhysicsService", "Instance")
cls("UserGameSettings", "Instance", { MouseSensitivity = 1, RotationType = Enum.RotationType.MovementRelative,
	ComputerCameraMovementMode = Enum.ComputerCameraMovementMode.Default, SavedQualityLevel = nil, MasterVolume = 1,
	GamepadCameraSensitivity = 1, ComputerMovementMode = nil, ControlMode = nil }, {}, { "FullscreenChanged" })
cls("MarketplaceService", "Instance")
cls("VirtualUser", "Instance")
cls("Debris", "Instance")
cls("LogService", "Instance", {}, {}, { "MessageOut" })

-- ------------------------------------------------------------------------------------------------ DataModel
game = Instance.new("DataModel")
game.Name = "Game"
local services = {}
local SERVICE_CLASS = { Workspace = "Workspace", Players = "Players", RunService = "RunService", UserInputService = "UserInputService",
	TweenService = "TweenService", HttpService = "HttpService", StarterGui = "StarterGui", GuiService = "GuiService", Stats = "Stats",
	TextService = "TextService", CoreGui = "CoreGui", Lighting = "Lighting", ReplicatedStorage = "ReplicatedStorage",
	ReplicatedFirst = "ReplicatedFirst", SoundService = "SoundService", ContentProvider = "ContentProvider",
	ContextActionService = "ContextActionService", Teams = "Teams", Chat = "Chat", TextChatService = "TextChatService",
	StarterPlayer = "StarterPlayer", StarterPack = "StarterPack", CollectionService = "CollectionService",
	PhysicsService = "PhysicsService", UserGameSettings = "UserGameSettings", MarketplaceService = "MarketplaceService",
	VirtualUser = "VirtualUser", Debris = "Debris", LogService = "LogService" }
local function getService(name)
	local s = services[name]
	if s then return s end
	local cn = SERVICE_CLASS[name]
	if not cn then error("'" .. tostring(name) .. "' is not a valid Service name", 2) end
	s = Instance.new(cn)
	s.Name = name
	if name ~= "UserGameSettings" then s.Parent = game end
	services[name] = s
	return s
end
C.DataModel.Methods.GetService = function(self, name) return getService(name) end
C.DataModel.Methods.FindService = function(self, name) return services[name] end
C.DataModel.Methods.IsLoaded = function() return true end
C.DataModel.Methods.BindToClose = function() end
C.DataModel.Events = { "Loaded" }
UserSettings = function()
	local us = { GetService = function(_, n) return getService(n) end, IsUserFeatureEnabled = function() return false end }
	return us
end
for name in pairs(SERVICE_CLASS) do if name ~= "UserGameSettings" then getService(name) end end
workspace = services.Workspace
Workspace = workspace
do local t = Instance.new("Terrain"); t.Name = "Terrain"; t.Anchored = true; t.Parent = workspace end
M.services = services

-- ------------------------------------------------------------------------------------------------ service methods
local TS = C.TweenService.Methods
TS.Create = function(_, inst, info, goals)
	local tw = { Completed = M.newSignal("Tween.Completed"), PlaybackState = nil }
	function tw:Play()
		for k, v in pairs(goals) do inst[k] = v end
		task.defer(function() tw.Completed:Fire(Enum.PlaybackState and Enum.PlaybackState.Completed) end)
	end
	function tw:Cancel() end
	function tw:Pause() end
	function tw:Destroy() end
	return setmetatable(tw, { __type = "Instance" })
end
TS.GetValue = function(_, a) return a end

C.HttpService.Methods.JSONEncode = function(_, v) return M.JSON.encode(v) end
C.HttpService.Methods.JSONDecode = function(_, s) return M.JSON.decode(s) end
local guidN = 0
C.HttpService.Methods.GenerateGUID = function(_, wrap)
	guidN = guidN + 1
	local g = string.format("%08x-0000-4000-8000-%012x", guidN, guidN)
	return wrap == false and g or ("{" .. g .. "}")
end

M.coreSet = {}
C.StarterGui.Methods.SetCore = function(_, k, v) M.coreSet[k] = v end
C.StarterGui.Methods.GetCore = function(_, k) return M.coreSet[k] end
M.coreGuiEnabled = {}
C.StarterGui.Methods.SetCoreGuiEnabled = function(_, t, v) M.coreGuiEnabled[t] = v end
C.StarterGui.Methods.GetCoreGuiEnabled = function(_, t) local v = M.coreGuiEnabled[t]; if v == nil then return true end return v end

C.GuiService.Methods.GetGuiInset = function() return Vector2.new(0, M.inset), Vector2.new(0, 0) end
C.GuiService.Methods.IsTenFootInterface = function() return false end
C.GuiService.Methods.CloseInspectMenu = function() end

local function textWidth(text, size, adv)
	local w = 0
	for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do w = math.max(w, utf8.len(line) or #line) end
	return w * size * adv
end
M.enumFontAdvance = { Code = 0.5, RobotoMono = 0.6001, Arcade = 1.0 }
-- text model. Default: the em is TextSize and a line is TextSize tall. M.textLineModel = true: a line
-- (TextSize) holds the font's whole ascender..descender, so the em is TextSize * upm / (asc + desc)
-- (Roboto Mono 2048 / 2701), the way Roblox's text engine sizes fonts.
M.textLineModel = false
M.fontEmPerLine = { RobotoMono = 2048 / 2701, Inconsolata = 1000 / 1049 }
local ENUM_FAMILY = { Code = "Inconsolata", RobotoMono = "RobotoMono" }
function M.emScale(family)
	if not M.textLineModel then return 1 end
	return M.fontEmPerLine[family or ""] or 0.8
end
C.TextService.Methods.GetTextSize = function(_, text, size, font, frame)
	local fname = font and font.Name or ""
	local adv = (M.enumFontAdvance[fname] or 0.5) * M.emScale(ENUM_FAMILY[fname])
	local lines = select(2, tostring(text):gsub("\n", "")) + 1
	return Vector2.new(textWidth(text, size, adv), lines * size)
end
C.TextService.Methods.GetTextBoundsAsync = function(_, params)
	local fam = params.Font and params.Font.Family or ""
	local name = fam:match("families/(.-)%.json") or ""
	local adv = (M.fontFamilyAdvance[name] or 0.5) * M.emScale(name)
	local lines = select(2, tostring(params.Text):gsub("\n", "")) + 1
	return Vector2.new(textWidth(params.Text, params.Size, adv), lines * params.Size)
end

C.ContentProvider.Methods.PreloadAsync = function() end
C.ContextActionService.Methods.BindAction = function() end
C.ContextActionService.Methods.BindActionAtPriority = function() end
C.ContextActionService.Methods.UnbindAction = function() end
C.ContextActionService.Methods.SetTitle = function() end
C.CollectionService.Methods.GetTagged = function() return {} end
C.CollectionService.Methods.GetInstanceAddedSignal = function() return M.newSignal("tag") end
C.CollectionService.Methods.GetInstanceRemovedSignal = function() return M.newSignal("tag") end
C.SoundService.Methods.PlayLocalSound = function() end
C.Debris.Methods.AddItem = function() end

-- RunService
local binds = {}
M.binds = binds
C.RunService.Methods.BindToRenderStep = function(_, name, prio, fn)
	for i = #binds, 1, -1 do if binds[i].name == name then table.remove(binds, i) end end
	binds[#binds + 1] = { name = name, prio = prio, fn = fn }
	table.sort(binds, function(a, b) return a.prio < b.prio end)
end
C.RunService.Methods.UnbindFromRenderStep = function(_, name)
	for i = #binds, 1, -1 do if binds[i].name == name then table.remove(binds, i) end end
end
C.RunService.Methods.IsClient = function() return true end
C.RunService.Methods.IsServer = function() return false end
C.RunService.Methods.IsStudio = function() return false end
C.RunService.Methods.IsRunning = function() return true end
C.RunService.Methods.IsRunMode = function() return false end

-- UserInputService
M.mouse = Vector2.new(960, 540)
M.mouseDelta = Vector2.new(0, 0)
M.keysDown = {}
M.buttonsDown = {}
M.focusedBox = nil
local U = C.UserInputService.Methods
U.GetMouseLocation = function() return M.mouse end
U.GetMouseDelta = function() return M.mouseDelta end
U.IsKeyDown = function(_, kc) return M.keysDown[kc] == true end
U.IsMouseButtonPressed = function(_, t) return M.buttonsDown[t] == true end
U.GetFocusedTextBox = function() return M.focusedBox end
U.GetKeysPressed = function()
	local out = {}
	for k, v in pairs(M.keysDown) do if v then out[#out + 1] = { KeyCode = k } end end
	return out
end
U.GetLastInputType = function() return Enum.UserInputType.Keyboard end
U.GetMouseButtonsPressed = function() return {} end
U.GetConnectedGamepads = function() return {} end
U.GetNavigationGamepads = function() return {} end
U.GetStringForKeyCode = function(_, kc) return kc.Name end
U.GetImageForKeyCode = function() return "" end
U.GetPlatform = function() return Enum.Platform and Enum.Platform.Windows end
U.GetDeviceAcceleration = function() return nil end

-- Workspace / Camera
C.Workspace.Methods.Raycast = function() return nil end
C.Workspace.Methods.GetPartBoundsInRadius = function() return {} end
C.Workspace.Methods.GetPartBoundsInBox = function() return {} end
C.Workspace.Methods.GetPartsInPart = function() return {} end
C.Workspace.Methods.GetServerTimeNow = function() return M.now end
C.Workspace.Methods.GetRealPhysicsFPS = function() return 60 end
C.Workspace.Methods.FindPartOnRay = function() return nil, Vector3.zero end
C.Workspace.Methods.FindPartOnRayWithIgnoreList = function() return nil, Vector3.zero end
C.Workspace.Methods.Blockcast = function() return nil end
C.Workspace.Methods.Spherecast = function() return nil end
C.Workspace.Methods.Shapecast = function() return nil end
C.Workspace.Methods.BulkMoveTo = function(_, parts, cfs)
	for i, p in ipairs(parts) do p.CFrame = cfs[i] end
end
C.Model.Methods.GetPivot = function(self)
	local pp = self.PrimaryPart
	if pp then return pp.CFrame end
	for _, d in ipairs(self:GetDescendants()) do if d:IsA("BasePart") then return d.CFrame end end
	return CFrame.new()
end
C.Model.Methods.PivotTo = function(self, cf)
	local cur = self:GetPivot()
	local delta = cf * cur:Inverse()
	for _, d in ipairs(self:GetDescendants()) do if d:IsA("BasePart") then d.CFrame = delta * d.CFrame end end
end
C.Model.Methods.GetBoundingBox = function(self) return self:GetPivot(), Vector3.new(4, 5, 2) end
C.Model.Methods.GetExtentsSize = function() return Vector3.new(4, 5, 2) end
C.Model.Methods.SetPrimaryPartCFrame = function(self, cf) self:PivotTo(cf) end
C.Model.Methods.GetPrimaryPartCFrame = function(self) return self:GetPivot() end
C.Model.Methods.BreakJoints = function() end
C.BasePart.Methods.GetPivot = function(self) return self.CFrame end
C.BasePart.Methods.PivotTo = function(self, cf) self.CFrame = cf end
C.BasePart.Methods.GetTouchingParts = function() return {} end
C.BasePart.Methods.GetConnectedParts = function(self) return { self } end
C.BasePart.Methods.GetJoints = function() return {} end
C.BasePart.Methods.GetMass = function(self) local s = self.Size; return s.X * s.Y * s.Z * 0.7 end
C.BasePart.Methods.GetRootPart = function(self) return self end
C.BasePart.Methods.ApplyImpulse = function() end
C.BasePart.Methods.SetNetworkOwner = function() end
C.BasePart.Methods.GetNetworkOwner = function() return nil end
C.BasePart.Methods.CanSetNetworkOwnership = function() return false end
C.BasePart.Methods.GetVelocityAtPosition = function(self) return self.AssemblyLinearVelocity end
C.BasePart.Events = { "Touched", "TouchEnded" }
local function project(cam, v)
	local cf = cam.CFrame
	local rel = cf:PointToObjectSpace(v)
	local depth = -rel.Z
	local vp = M.viewport
	local f = (vp.Y / 2) / math.tan(math.rad(cam.FieldOfView) / 2)
	if depth <= 0 then return Vector3.new(0, 0, depth), false end
	local x = vp.X / 2 + rel.X / depth * f
	local y = vp.Y / 2 - rel.Y / depth * f
	local on = x >= 0 and x <= vp.X and y >= 0 and y <= vp.Y
	return Vector3.new(x, y, depth), on
end
C.Camera.Methods.WorldToViewportPoint = function(self, v) return project(self, v) end
C.Camera.Methods.WorldToScreenPoint = function(self, v)
	local p, on = project(self, v)
	return Vector3.new(p.X, p.Y - M.inset, p.Z), on
end
local function ray(self, x, y)
	local vp = M.viewport
	local f = (vp.Y / 2) / math.tan(math.rad(self.FieldOfView) / 2)
	local dir = Vector3.new((x - vp.X / 2) / f, -(y - vp.Y / 2) / f, -1).Unit
	local cf = self.CFrame
	return Ray.new(cf.Position, cf:VectorToWorldSpace(dir))
end
C.Camera.Methods.ViewportPointToRay = function(self, x, y) return ray(self, x, y) end
C.Camera.Methods.ScreenPointToRay = function(self, x, y) return ray(self, x, y + M.inset) end
C.Camera.Methods.GetPartsObscuringTarget = function() return {} end
C.Camera.Methods.ZoomToExtents = function() end
C.Camera.Methods.Interpolate = function() end
C.Camera.Methods.GetRenderCFrame = function(self) return self.CFrame end
C.Camera.Methods.GetRoll = function() return 0 end

-- Humanoid
C.Humanoid.Methods.GetState = function(self) return rawget(self, "_d").state end
C.Humanoid.Methods.ChangeState = function(self, st)
	-- Roblox converts a number / name argument to the EnumItem
	if type(st) == "number" then st = Enum.HumanoidStateType:FromValue(st) elseif type(st) == "string" then st = Enum.HumanoidStateType[st] end
	local d = rawget(self, "_d")
	local old = d.state
	d.state = st
	if old ~= st then self.StateChanged:Fire(old, st) end
end
C.Humanoid.Methods.SetStateEnabled = function(self, st, v)
	local d = rawget(self, "_d")
	d.stateEnabled = d.stateEnabled or {}
	d.stateEnabled[st] = v
end
C.Humanoid.Methods.GetStateEnabled = function(self, st)
	local d = rawget(self, "_d")
	local v = d.stateEnabled and d.stateEnabled[st]
	if v == nil then return true end
	return v
end
M.moveCalls = 0
C.Humanoid.Methods.Move = function(self, dir, rel) M.moveCalls = M.moveCalls + 1; rawget(self, "_d").props.MoveDirection = dir end
C.Humanoid.Methods.MoveTo = function() end
C.Humanoid.Methods.TakeDamage = function(self, n) self.Health = self.Health - n end
C.Humanoid.Methods.EquipTool = function(self, tool) tool.Parent = self.Parent end
C.Humanoid.Methods.UnequipTools = function(self)
	local ch = self.Parent
	local bp = M.player and M.player:FindFirstChildOfClass("Backpack")
	for _, t in ipairs(ch:GetChildren()) do if t:IsA("Tool") and bp then t.Parent = bp end end
end
C.Humanoid.Methods.GetPlayingAnimationTracks = function(self)
	local a = self:FindFirstChildOfClass("Animator")
	return a and a:GetPlayingAnimationTracks() or {}
end
C.Humanoid.Methods.ApplyDescription = function() end
C.Humanoid.Methods.GetAppliedDescription = function() return Instance.new("HumanoidDescription") end
C.Humanoid.Methods.BuildRigFromAttachments = function() end
local function loadAnim(self, anim)
	local d = rawget(self, "_d")
	d.tracks = d.tracks or {}
	local tr = Instance.new("AnimationTrack")
	tr.Animation = anim
	tr.Name = anim and anim.Name or "Track"
	local td = rawget(tr, "_d")
	td.owner = self
	d.tracks[#d.tracks + 1] = tr
	return tr
end
C.Humanoid.Methods.LoadAnimation = loadAnim
C.Animator.Methods.LoadAnimation = loadAnim
C.Animator.Methods.GetPlayingAnimationTracks = function(self)
	local d = rawget(self, "_d")
	local out = {}
	for _, t in ipairs(d.tracks or {}) do if t.IsPlaying then out[#out + 1] = t end end
	return out
end
C.Animator.Methods.StepAnimations = function() end
C.Animator.Methods.ApplyJointVelocities = function() end
C.AnimationTrack.Methods.Play = function(self, fade, weight, speed)
	self.IsPlaying = true
	if speed then self.Speed = speed end
	local owner = rawget(self, "_d").owner
	if owner and owner.AnimationPlayed then owner.AnimationPlayed:Fire(self) end
end
C.AnimationTrack.Methods.Stop = function(self) self.IsPlaying = false; self.Stopped:Fire() end
C.AnimationTrack.Methods.AdjustSpeed = function(self, s) self.Speed = s end
C.AnimationTrack.Methods.AdjustWeight = function(self, w) self.WeightTarget = w end
C.AnimationTrack.Methods.GetMarkerReachedSignal = function() return M.newSignal("marker") end
C.AnimationTrack.Methods.GetTimeOfKeyframe = function() return 0 end
C.Sound.Methods.Play = function(self) self.Playing = true; self.IsPlaying = true end
C.Sound.Methods.Stop = function(self) self.Playing = false; self.IsPlaying = false end
C.Sound.Methods.Pause = function(self) self.Playing = false end
C.Sound.Methods.Resume = function(self) self.Playing = true end
C.Tool.Methods.Activate = function(self) self.Activated:Fire() end
C.Tool.Methods.Deactivate = function(self) self.Deactivated:Fire() end
C.Player.Methods.GetMouse = function(self)
	return { Hit = CFrame.new(), Target = nil, X = M.mouse.X, Y = M.mouse.Y - M.inset, Icon = "", ViewSizeX = M.viewport.X,
		ViewSizeY = M.viewport.Y, Move = M.newSignal("mouse.Move"), Button1Down = M.newSignal("b1d"), Button1Up = M.newSignal("b1u"),
		Button2Down = M.newSignal("b2d"), Button2Up = M.newSignal("b2u"), WheelForward = M.newSignal("wf"), WheelBackward = M.newSignal("wb") }
end
C.Player.Methods.Kick = function() error("kicked (mock)") end
C.Player.Methods.LoadCharacter = function() end
C.Player.Methods.GetNetworkPing = function() return 0.05 end
C.Player.Methods.IsInGroup = function() return false end
C.Player.Methods.GetRankInGroup = function() return 0 end
C.Player.Methods.HasAppearanceLoaded = function() return true end
C.Player.Methods.DistanceFromCharacter = function() return 0 end
C.Players.Methods.GetPlayers = function(self)
	local out = {}
	for _, c in ipairs(self:GetChildren()) do if c:IsA("Player") then out[#out + 1] = c end end
	return out
end
C.Players.Methods.GetPlayerFromCharacter = function(self, ch)
	for _, p in ipairs(self:GetPlayers()) do if p.Character == ch then return p end end
	return nil
end
C.Players.Methods.GetPlayerByUserId = function(self, id)
	for _, p in ipairs(self:GetPlayers()) do if p.UserId == id then return p end end
	return nil
end
C.Players.Methods.GetUserThumbnailAsync = function() return "rbxasset://thumb.png", true end
C.Players.Methods.GetNameFromUserIdAsync = function() return "Player1" end

-- ------------------------------------------------------------------------------------------------ local player + character
local camera = Instance.new("Camera")
camera.Name = "Camera"
camera.Parent = workspace
workspace.CurrentCamera = camera
M.camera = camera

local player = Instance.new("Player")
player.Name = "Player1"
player.Parent = services.Players
services.Players.LocalPlayer = player
M.player = player
local pg = Instance.new("PlayerGui"); pg.Name = "PlayerGui"; pg.Parent = player
local bp = Instance.new("Backpack"); bp.Name = "Backpack"; bp.Parent = player
local ps = Instance.new("PlayerScripts"); ps.Name = "PlayerScripts"; ps.Parent = player

function M.makeCharacter(pos)
	pos = pos or Vector3.new(0, 3, 0)
	local ch = Instance.new("Model")
	ch.Name = "Player1"
	local function part(name, size, offset)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = CFrame.new(pos + offset)
		p.Parent = ch
		return p
	end
	local hrp = part("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.zero)
	hrp.Transparency = 1
	local torso = part("Torso", Vector3.new(2, 2, 1), Vector3.zero)
	local head = part("Head", Vector3.new(2, 1, 1), Vector3.new(0, 1.5, 0))
	local la = part("Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 0, 0))
	local ra = part("Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 0, 0))
	local ll = part("Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.5, -2, 0))
	local rl = part("Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.5, -2, 0))
	ch.PrimaryPart = hrp
	local function motor(name, parent, p0, p1, c0, c1)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = p0
		m.Part1 = p1
		m.C0 = c0 or CFrame.new()
		m.C1 = c1 or CFrame.new()
		m.Parent = parent
		return m
	end
	motor("RootJoint", hrp, hrp, torso)
	motor("Neck", torso, torso, head, CFrame.new(0, 1, 0), CFrame.new(0, -0.5, 0))
	motor("Left Shoulder", torso, torso, la, CFrame.new(-1, 0.5, 0), CFrame.new(0.5, 0.5, 0))
	motor("Right Shoulder", torso, torso, ra, CFrame.new(1, 0.5, 0), CFrame.new(-0.5, 0.5, 0))
	motor("Left Hip", torso, torso, ll, CFrame.new(-1, -1, 0), CFrame.new(-0.5, 1, 0))
	motor("Right Hip", torso, torso, rl, CFrame.new(1, -1, 0), CFrame.new(0.5, 1, 0))
	local hum = Instance.new("Humanoid")
	hum.Name = "Humanoid"
	hum.RootPart = hrp
	hum.Parent = ch
	local an = Instance.new("Animator"); an.Name = "Animator"; an.Parent = hum
	local animate = Instance.new("LocalScript"); animate.Name = "Animate"; animate.Parent = ch
	for _, n in ipairs({ "idle", "walk", "run", "jump", "fall", "climb", "sit", "toolnone", "toolslash", "toollunge" }) do
		local sv = Instance.new("StringValue"); sv.Name = n; sv.Parent = animate
		local a = Instance.new("Animation"); a.Name = n:sub(1, 1):upper() .. n:sub(2) .. "Anim"; a.AnimationId = "rbxassetid://" .. (#n * 1000); a.Parent = sv
	end
	ch.Parent = workspace
	player.Character = ch
	camera.CameraSubject = hum
	camera.CFrame = CFrame.lookAt(pos + Vector3.new(0, 5, 12), pos)
	return ch
end
M.makeCharacter()

-- simple physics for the character root (so recording sees movement)
function M.physics(dt)
	local ch = player.Character
	if not ch then return end
	local hrp = ch:FindFirstChild("HumanoidRootPart")
	if not hrp or hrp.Anchored then return end
	local v = hrp.AssemblyLinearVelocity
	if v.Magnitude > 0 then
		hrp.CFrame = hrp.CFrame + v * dt
	end
end

-- ------------------------------------------------------------------------------------------------ executor API
M.fs = {}      -- path -> contents
M.folders = { [""] = true }
local function norm(p) return (tostring(p):gsub("\\", "/"):gsub("/+$", "")) end
writefile = function(p, c)
	p = norm(p)
	local dir = p:match("^(.*)/[^/]*$")
	if dir and not M.folders[dir] then error("writefile: folder does not exist: " .. dir) end
	assert(type(c) == "string", "writefile expects a string")
	M.fs[p] = c
end
readfile = function(p)
	p = norm(p)
	local c = M.fs[p]
	if c == nil then error("readfile: file does not exist: " .. p) end
	return c
end
isfile = function(p) return M.fs[norm(p)] ~= nil end
isfolder = function(p) return M.folders[norm(p)] == true end
makefolder = function(p)
	p = norm(p)
	local acc = ""
	for part in p:gmatch("[^/]+") do
		acc = (acc == "") and part or (acc .. "/" .. part)
		M.folders[acc] = true
	end
end
listfiles = function(p)
	p = norm(p)
	local out = {}
	for path in pairs(M.fs) do
		local dir = path:match("^(.*)/[^/]*$") or ""
		if dir == p then out[#out + 1] = path end
	end
	for f in pairs(M.folders) do
		local dir = f:match("^(.*)/[^/]*$") or ""
		if dir == p and f ~= p then out[#out + 1] = f end
	end
	table.sort(out)
	return out
end
delfile = function(p) M.fs[norm(p)] = nil end
delfolder = function(p) M.folders[norm(p)] = nil end
appendfile = function(p, c) M.fs[norm(p)] = (M.fs[norm(p)] or "") .. c end
lz4compress = function(s) return M.LZ4.compress(s) end
lz4decompress = function(s, n) return M.LZ4.decompress(s, n) end
getcustomasset = function(p) return "rbxasset://custom/" .. norm(p) end
local genvT = {}
getgenv = function() return genvT end
M.genv = genvT
cloneref = function(x) return x end
local hui = Instance.new("Folder")
hui.Name = "HiddenUI"
hui.Parent = services.CoreGui
gethui = function() return hui end
M.hui = hui
M.windowActive = true
isrbxactive = function() return M.windowActive end
M.inputLog = {}
local function logInput(kind) return function(...) M.inputLog[#M.inputLog + 1] = { kind, ... } end end
keypress = logInput("keypress")
keyrelease = logInput("keyrelease")
mouse1press = logInput("mouse1press")
mouse1release = logInput("mouse1release")
mouse2press = logInput("mouse2press")
mouse2release = logInput("mouse2release")
mousemoveabs = function(x, y) M.inputLog[#M.inputLog + 1] = { "mousemoveabs", x, y }; M.mouse = Vector2.new(x, y) end
mousemoverel = logInput("mousemoverel")
mousescroll = logInput("mousescroll")
getgc = function() return {} end
identifyexecutor = function() return "MockExec", "1.0" end

-- print / warn capture
local realPrint = print
M.realPrint = realPrint
print = function(...)
	local t = {}
	for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
	M.logs[#M.logs + 1] = table.concat(t, " ")
	if M.echo then realPrint(...) end
end
warn = function(...)
	local t = {}
	for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
	M.logs[#M.logs + 1] = "WARN " .. table.concat(t, " ")
	if M.echo then realPrint("WARN", ...) end
end

-- ------------------------------------------------------------------------------------------------ frame driver
local RS = services.RunService
function M.step(dt)
	dt = dt or (1 / 60)
	M.clockTicks = 0
	M.now = M.now + dt
	M.frame = M.frame + 1
	RS.PreRender:Fire(dt)
	RS.RenderStepped:Fire(dt)
	for _, b in ipairs(table.clone(binds)) do
		local ok, err = pcall(b.fn, dt)
		if not ok then M.logs[#M.logs + 1] = "BIND ERROR " .. b.name .. ": " .. tostring(err) end
	end
	RS.PreAnimation:Fire(dt)
	RS.PreSimulation:Fire(dt)
	RS.Stepped:Fire(M.now, dt)
	M.physics(dt)
	RS.PostSimulation:Fire(dt)
	RS.Heartbeat:Fire(dt)
	M.resumeDue()
end
function M.steps(n, dt)
	for _ = 1, n do M.step(dt) end
end

-- input helpers
local inputMt = { __type = "Instance" }
function M.input(kind, kc, state, pos)
	return setmetatable({ UserInputType = kind, KeyCode = kc or Enum.KeyCode.Unknown, UserInputState = state or Enum.UserInputState.Begin,
		Position = pos or Vector3.new(M.mouse.X, M.mouse.Y - M.inset, 0), Delta = Vector3.zero, IsA = function(_, n) return n == "InputObject" end }, inputMt)
end
function M.pressKey(kc, proc)
	M.keysDown[kc] = true
	services.UserInputService.InputBegan:Fire(M.input(Enum.UserInputType.Keyboard, kc, Enum.UserInputState.Begin), proc or false)
end
function M.releaseKey(kc, proc)
	M.keysDown[kc] = nil
	services.UserInputService.InputEnded:Fire(M.input(Enum.UserInputType.Keyboard, kc, Enum.UserInputState.End), proc or false)
end

-- mouse: x, y are screen pixels (UIS:GetMouseLocation space). The InputObjects carry
-- InputObject.Position space (the top bar inset taken off), like the Roblox client.
function M.moveMouse(x, y)
	M.mouse = Vector2.new(x, y)
	services.UserInputService.InputChanged:Fire(M.input(Enum.UserInputType.MouseMovement, nil, Enum.UserInputState.Change), false)
end
local BUTTON = { "MouseButton1", "MouseButton2", "MouseButton3" }
-- proc = gameProcessedEvent (true when the click lands on a GUI button, like the profiler's)
function M.mouseDown(b, proc)
	local t = Enum.UserInputType[BUTTON[b or 1]]
	M.buttonsDown[t] = true
	if proc == nil then proc = true end
	services.UserInputService.InputBegan:Fire(M.input(t, nil, Enum.UserInputState.Begin), proc)
end
function M.mouseUp(b, proc)
	local t = Enum.UserInputType[BUTTON[b or 1]]
	M.buttonsDown[t] = nil
	if proc == nil then proc = true end
	services.UserInputService.InputEnded:Fire(M.input(t, nil, Enum.UserInputState.End), proc)
end
function M.click(b, proc)
	M.mouseDown(b, proc)
	M.mouseUp(b, proc)
end
function M.wheel(z)
	services.UserInputService.InputChanged:Fire(M.input(Enum.UserInputType.MouseWheel, nil, Enum.UserInputState.Change,
		Vector3.new(M.mouse.X, M.mouse.Y - M.inset, z)), false)
end
-- one finger: state "begin" / "move" / "end" at screen pixels x, y (the same InputObject all along)
local touchObj = nil
function M.touch(state, x, y)
	local pos = Vector3.new(x, y - M.inset, 0)
	local U = services.UserInputService
	if state == "begin" then
		touchObj = M.input(Enum.UserInputType.Touch, nil, Enum.UserInputState.Begin, pos)
		U.InputBegan:Fire(touchObj, true)
	elseif touchObj then
		touchObj.Position = pos
		if state == "move" then
			touchObj.UserInputState = Enum.UserInputState.Change
			U.InputChanged:Fire(touchObj, true)
		else
			touchObj.UserInputState = Enum.UserInputState.End
			U.InputEnded:Fire(touchObj, true)
			touchObj = nil
		end
	end
end
