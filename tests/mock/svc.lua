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
-- Lighting: the properties HappaTAS's Sync Lighting reads (Roblox's defaults for a new place)
cls("Lighting", "Instance", { ClockTime = 14, Brightness = 2, GlobalShadows = true, EnvironmentDiffuseScale = 1,
	EnvironmentSpecularScale = 1, ExposureCompensation = 0, FogStart = 0, FogEnd = 100000, GeographicLatitude = 0,
	ShadowSoftness = 0.2, Ambient = Color3.new(0, 0, 0), OutdoorAmbient = Color3.fromRGB(128, 128, 128),
	ColorShift_Bottom = Color3.new(0, 0, 0), ColorShift_Top = Color3.new(0, 0, 0), FogColor = Color3.fromRGB(192, 192, 192) })
cls("ReplicatedStorage", "Instance")
cls("ReplicatedFirst", "Instance")
cls("SoundService", "Instance", { RespectFilteringEnabled = true })
cls("ContentProvider", "Instance", { RequestQueueSize = 0 })
cls("ContextActionService", "Instance")
cls("Teams", "Instance")
cls("Chat", "Instance")
cls("TextChatService", "Instance")
cls("ChatInputBarConfiguration", "Instance", { IsFocused = false, Enabled = true, TargetTextChannel = nil })
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

-- AssetService:CreateEditableImage (Roblox docs: RGBA bytes from the top-left corner, at most 1024 x 1024,
-- shown with ImageLabel.ImageContent = Content.fromObject(image)). Off unless M.editableImages = true, like
-- a client without EditableImage. M.eiWrites counts WritePixelsBuffer calls, M.eiImages the live images.
M.editableImages = false
M.eiWrites = 0
M.eiImages = {}
local eiMt = {}
eiMt.__index = eiMt
M.eiFail = false -- true: every write errors (an image that stopped working)
function eiMt.WritePixelsBuffer(self, pos, size, buf)
	if M.eiFail then error("EditableImage write failed (mock)", 2) end
	assert(not self.destroyed, "EditableImage was destroyed")
	assert(typeof(pos) == "Vector2" and typeof(size) == "Vector2", "WritePixelsBuffer(Vector2, Vector2, buffer)")
	local x0, y0, w, h = pos.X, pos.Y, size.X, size.Y
	assert(x0 >= 0 and y0 >= 0 and x0 + w <= self.Size.X and y0 + h <= self.Size.Y, "region outside the image")
	assert(buffer.len(buf) == w * h * 4, "buffer must be size.X * size.Y * 4 bytes")
	for r = 0, h - 1 do
		buffer.copy(self.px, ((y0 + r) * self.Size.X + x0) * 4, buf, r * w * 4, w * 4)
	end
	M.eiWrites = M.eiWrites + 1
end
function eiMt.ReadPixelsBuffer(self, pos, size)
	local out = buffer.create(size.X * size.Y * 4)
	for r = 0, size.Y - 1 do
		buffer.copy(out, r * size.X * 4, self.px, ((pos.Y + r) * self.Size.X + pos.X) * 4, size.X * 4)
	end
	return out
end
-- r, g, b, a of one pixel
function eiMt.Pixel(self, x, y)
	local o = (y * self.Size.X + x) * 4
	return buffer.readu8(self.px, o), buffer.readu8(self.px, o + 1), buffer.readu8(self.px, o + 2), buffer.readu8(self.px, o + 3)
end
function eiMt.Destroy(self) self.destroyed = true; M.eiImages[self] = nil end
cls("AssetService", "Instance", {}, {
	CreateEditableImage = function(_, opts)
		if not M.editableImages then error("EditableImage is not available (mock)", 2) end
		local size = opts and opts.Size or Vector2.new(512, 512)
		assert(size.X >= 1 and size.Y >= 1 and size.X <= 1024 and size.Y <= 1024, "EditableImage size must be 1..1024")
		local img = setmetatable({ Size = size, px = buffer.create(size.X * size.Y * 4) }, eiMt)
		M.eiImages[img] = true
		return img
	end,
})
-- VirtualInputManager:SendKeyEvent hands Roblox a key with its exact KeyCode (seen in the client: InputBegan /
-- InputEnded fire with it). M.vimFail makes it error (like a client where it isn't allowed)
cls("VirtualInputManager", "Instance", {}, {
	SendKeyEvent = function(_, down, keyCode, isRepeat, layer)
		if M.vimFail then error("VirtualInputManager:SendKeyEvent is not allowed (mock)", 2) end
		M.inputLog[#M.inputLog + 1] = { "vimkey", down, keyCode.Name }
		if down then M.pressKey(keyCode) else M.releaseKey(keyCode) end
	end,
})
Content = {
	none = { SourceType = "None" },
	fromObject = function(o) return { SourceType = "Object", Object = o } end,
	fromUri = function(u) return { SourceType = "Uri", Uri = u } end,
}

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
	VirtualUser = "VirtualUser", Debris = "Debris", LogService = "LogService", AssetService = "AssetService",
	VirtualInputManager = "VirtualInputManager" }
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
-- M.coreGuiLocked: CoreGui can't be had (like an executor without the access)
C.DataModel.Methods.GetService = function(self, name)
	if name == "CoreGui" and M.coreGuiLocked then error("The current thread cannot access 'CoreGui' (mock)", 2) end
	return getService(name)
end
C.DataModel.Methods.FindService = function(self, name) return services[name] end
C.DataModel.Methods.IsLoaded = function() return true end
C.DataModel.Methods.BindToClose = function() end
C.DataModel.Events = { "Loaded" }
UserSettings = function()
	local us = { GetService = function(_, n) return getService(n) end, IsUserFeatureEnabled = function() return false end }
	return us
end
for name in pairs(SERVICE_CLASS) do if name ~= "UserGameSettings" then getService(name) end end
do -- TextChatService's chat bar settings (IsFocused = the player is typing in the new chat)
	local bar = Instance.new("ChatInputBarConfiguration")
	bar.Name = "ChatInputBarConfiguration"
	bar.Parent = services.TextChatService
	M.chatBar = bar
end
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
-- like the Roblox client, GetFocusedTextBox() doesn't report a text box inside CoreGui (the new chat
-- bar, interfaces under gethui()). M.focus(box) focuses a text box (nil = none) and fires its events.
local function inCoreGui(inst)
	local a = inst
	while a do
		if a == services.CoreGui then return true end
		a = a.Parent
	end
	return false
end
U.GetFocusedTextBox = function()
	local b = M.focusedBox
	if b and inCoreGui(b) then return nil end
	return b
end
function M.focus(box)
	local old = M.focusedBox
	if old == box then return end
	M.focusedBox = box
	if old then old.FocusLost:Fire(false, nil) end
	if box then box.Focused:Fire() end
end
C.TextBox.Methods.IsFocused = function(self) return M.focusedBox == self end
C.TextBox.Methods.CaptureFocus = function(self) M.focus(self) end
C.TextBox.Methods.ReleaseFocus = function(self) if M.focusedBox == self then M.focus(nil) end end
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
-- Roblox: "the linear velocity of the part's assembly at the given position" = the centre of mass's velocity
-- + angular velocity x (position - centre of mass)
C.BasePart.Methods.GetVelocityAtPosition = function(self, pos)
	local v, w = self.AssemblyLinearVelocity, self.AssemblyAngularVelocity
	if not pos or w.Magnitude == 0 then return v end
	return v + w:Cross(pos - self.AssemblyCenterOfMass)
end
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
	-- M.refuseScriptFreefall: a script can't end a jump (Jumping -> Freefall outside the physics step)
	if M.refuseScriptFreefall and not M.inPhysics and old == Enum.HumanoidStateType.Jumping and st == Enum.HumanoidStateType.Freefall then return end
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
C.Sound.Methods.Play = function(self) self.Playing = true; self.IsPlaying = true; M.soundPlays = (M.soundPlays or 0) + 1 end
C.Sound.Methods.Stop = function(self) self.Playing = false; self.IsPlaying = false end
-- (M.emits = particles emitted, M.emitLog = { emitter, count })
C.ParticleEmitter.Methods.Emit = function(self, n)
	M.emits = (M.emits or 0) + (n or 16)
	M.emitLog = M.emitLog or {}
	M.emitLog[#M.emitLog + 1] = { self, n }
end
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
-- M.humanoidPhysics = true: a small humanoid model (speed hack tests). On the floor (root at M.floorY + 3)
-- the horizontal velocity is MoveDirection x WalkSpeed (Roblox's humanoid reaches it at once), the Running
-- event reports the speed when it changes; M.jumpNow starts a jump with JumpPower (UseJumpPower) or
-- sqrt(2 x Gravity x JumpHeight) (Roblox docs: the jump is worked out from JumpHeight and the gravity);
-- workspace.Gravity pulls down (semi-implicit Euler)
M.humanoidPhysics = false
M.floorY = 0
M.jumpNow = false
local lastRunSpeed = nil
function M.resetHumanoidModel() lastRunSpeed = nil; M.jumpNow = false end
local function humanoidStep(hrp, hum, dt)
	local g = workspace.Gravity
	local v = hrp.AssemblyLinearVelocity
	local pos = hrp.Position
	local y0 = M.floorY + 3
	local onFloor = pos.Y <= y0 + 1e-6 and v.Y <= 1e-9
	local md = hum.MoveDirection
	local hv = md * hum.WalkSpeed
	local vy = v.Y
	if onFloor then
		vy = 0
		if M.jumpNow then
			M.jumpNow = false
			vy = hum.UseJumpPower and hum.JumpPower or math.sqrt(2 * g * hum.JumpHeight)
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
			hum.Jumping:Fire(true)
			lastRunSpeed = nil
		end
	end
	vy = vy - g * dt
	local np = pos + Vector3.new(hv.X, vy, hv.Z) * dt
	if np.Y <= y0 then
		np = Vector3.new(np.X, y0, np.Z)
		vy = 0
		if hum:GetState() ~= Enum.HumanoidStateType.Running then hum:ChangeState(Enum.HumanoidStateType.Running) end
		local sp = Vector3.new(hv.X, 0, hv.Z).Magnitude
		if lastRunSpeed == nil or math.abs(sp - lastRunSpeed) > 1e-6 then
			lastRunSpeed = sp
			hum.Running:Fire(sp)
		end
	elseif hum:GetState() == Enum.HumanoidStateType.Jumping and vy < 0 then
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
		hum.FreeFalling:Fire(true)
	end
	hrp.CFrame = hrp.CFrame.Rotation + np
	hrp.AssemblyLinearVelocity = Vector3.new(hv.X, vy, hv.Z)
end
-- M.robloxController = true (with M.humanoidPhysics): Roblox's humanoid controllers as measured in the client
-- (V2.38.17): walking closes 62.5 % of the speed gap per 1/240 s step (a fraction of a step for the rest of the
-- frame), at most 741.6 studs/s^2 on the floor and 143 in the air; AutoRotate turns towards the move direction
-- (a PD controller with spin, see the turning below); a jump works from Running until 0.13 s after the floor is
-- lost (real time), Running turns into Freefall after 0.125 s; FloorMaterial turns Air when the floor is lost; the
-- jump input turns the state Jumping after the step, the Jumping state pushes the vertical speed up to the jump speed at each step's start until a step starts there (then Freefall). Everything in Roblox's 1/240 s
-- steps (the velocity changes at a step's start, then the position moves at it; a frame that isn't whole steps
-- ends with a fraction of one). M.floorEdgeX: no floor at x >= edge.
M.robloxController = false
M.floorEdgeX = nil
local RC = { engOff = 0, jumpedAir = false, applied = false }
function M.resetRobloxController() RC.engOff, RC.jumpedAir, RC.applied, RC.lastRun, RC.prev, RC.finish = 0, false, true, nil, "reset", false end
local function robloxStep(hrp, hum, dt)
	local JUMPING = Enum.HumanoidStateType.Jumping
	-- (whole steps up to a few nanoseconds of noise, like the client's dt, are whole steps)
	local steps = dt * 240
	if math.abs(steps - math.floor(steps + 0.5)) < 1e-3 then steps = math.floor(steps + 0.5); dt = steps / 240 end
	local g = workspace.Gravity
	local v = hrp.AssemblyLinearVelocity
	local pos = hrp.Position
	local y0 = M.floorY + 3
	local look = hrp.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local hasFloor = (M.floorEdgeX == nil) or pos.X < M.floorEdgeX
	local onFloor = hasFloor and pos.Y <= y0 + 1e-6 and v.Y <= 1e-9
	if onFloor then RC.engOff, RC.jumpedAir, RC.applied = 0, false, false end
	if M.jumpNow then M.jumpNow, hum.Jump = false, true end -- (the jump button: Jump stays set until a jump takes it)
	local st = hum:GetState()
	if RC.prev == "reset" then
		RC.prev, RC.finish = st, false
		-- (a state left from before a reset is not a jump)
		if st == JUMPING then hum:ChangeState(Enum.HumanoidStateType.Running); st = hum:GetState() end
	end
	local vy = onFloor and 0 or v.Y
	-- (a jump finished at a step's start: Freefall from the next frame, measured in the client)
	if RC.finish then
		RC.finish = false
		if st == JUMPING then hum:ChangeState(Enum.HumanoidStateType.Freefall); st = hum:GetState() end
	end
	-- walking (fractional steps of 1/240 s)
	local md = hum.MoveDirection
	local target = Vector3.new(md.X, 0, md.Z) * hum.WalkSpeed
	local hv = Vector3.new(v.X, 0, v.Z)
	local disp = Vector3.zero
	local cap = onFloor and 741.6 or 143
	local left = steps
	while left > 1e-9 do
		local f = math.min(1, left)
		local err = target - hv
		local m = err.Magnitude
		if m > 1e-9 then hv = hv + err * (math.min(m * 0.625 * f, cap / 240 * f) / m) end
		disp = disp + hv * (f / 240)
		left = left - f
	end
	-- turning (AutoRotate, measured in the client): each step the spin becomes 0.58312 x spin + 10/3 x the angle
	-- left (the angle at the frame's start, at most 1 rad in the air), then the yaw moves at it
	local spin = hrp.AssemblyAngularVelocity.Y
	if hum.AutoRotate then
		local e = 0
		if md.Magnitude > 1e-6 then
			local want = math.atan2(-md.X, -md.Z)
			e = (want - yaw + math.pi) % (2 * math.pi) - math.pi
		end
		if st == JUMPING or st == Enum.HumanoidStateType.Freefall then e = math.max(-1, math.min(1, e)) end
		local left = steps
		while left > 1e-9 do
			local f = math.min(1, left)
			spin = spin + f * ((0.58312 - 1) * spin + 10 / 3 * e)
			yaw = yaw + spin * f / 240
			left = left - f
		end
	end
	-- vertical, Roblox's stepping (1/240 s steps, a fraction for the last one: the velocity changes at a step's
	-- start, then the position moves at it). Roblox's Jumping state (Eternal Obbying's copy: jumpingComputeForce,
	-- jumpFinished): a step that starts below the jump speed is pushed up to it and held there for the step; one that
	-- starts at it finishes the jump
	local dyv = 0
	if not onFloor or st == JUMPING then
		local jv = hum.UseJumpPower and hum.JumpPower or math.sqrt(2 * g * hum.JumpHeight)
		local left = steps
		while left > 1e-9 do
			local f = math.min(1, left)
			if hum:GetState() == JUMPING and not RC.finish and jv - vy > 1e-3 then
				if not RC.jumpedAir then hum.Jumping:Fire(true) end
				RC.jumpedAir = true
				M.jumpPushes = (M.jumpPushes or 0) + 1
				vy, onFloor = jv, false
			else
				if hum:GetState() == JUMPING then RC.finish = true end
				vy = vy - g * f / 240
			end
			dyv = dyv + vy * f / 240
			left = left - f
		end
	end
	local ny = pos.Y + dyv
	local np = Vector3.new(pos.X + disp.X, ny, pos.Z + disp.Z)
	if not onFloor then RC.engOff = RC.engOff + dt end
	if hasFloor and ny <= y0 and pos.Y >= y0 - 1e-6 then
		np = Vector3.new(np.X, y0, np.Z)
		vy = 0
		if hum:GetState() ~= Enum.HumanoidStateType.Running then hum:ChangeState(Enum.HumanoidStateType.Running) end
		RC.engOff, RC.jumpedAir, RC.applied = 0, false, false
	elseif not onFloor or not hasFloor then
		if not hasFloor and onFloor == false and RC.engOff == 0 then RC.engOff = dt end
	end
	-- the jump input turns the state Jumping after the step (the client shows Jumping in PreSimulation before the
	-- jump's first push, measured). Roblox's state table (Eternal Obbying's copy): from Running (not Freefall) a jump
	-- works until 0.13 s off the floor (JUMP_MAX_TIME_OFF_FLOOR), checked before Running turns into Freefall once
	-- it is more than 0.125 s off the floor (OFF_FLOOR_GRACE)
	local wants = hum.Jump
	local grounded = hasFloor and np.Y <= y0 + 1e-6 and vy <= 1e-9
	local stEnd = hum:GetState()
	local canJump = stEnd == Enum.HumanoidStateType.Running or stEnd == Enum.HumanoidStateType.RunningNoPhysics or stEnd == Enum.HumanoidStateType.Landed
	if wants and canJump and hum:GetStateEnabled(JUMPING) and not RC.jumpedAir and (grounded or RC.engOff <= 0.13) then
		hum.Jump = false
		hum:ChangeState(JUMPING)
	elseif not grounded and stEnd == Enum.HumanoidStateType.Running and RC.engOff > 0.125 and hum:GetStateEnabled(Enum.HumanoidStateType.Freefall) then
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	-- the Running event reports the speed on the floor when it changes (like the plain model)
	if np.Y <= y0 + 1e-6 and vy == 0 and hasFloor then
		local sp = hv.Magnitude
		if RC.lastRun == nil or math.abs(sp - RC.lastRun) > 1e-6 then
			RC.lastRun = sp
			hum.Running:Fire(sp)
		end
	else
		RC.lastRun = nil
	end
	-- (FloorMaterial turns Air on the frame the fall starts, measured in the client)
	hum.FloorMaterial = RC.engOff > 0 and Enum.Material.Air or Enum.Material.Plastic
	RC.prev = hum:GetState()
	hrp.CFrame = CFrame.new(np) * CFrame.Angles(0, yaw, 0)
	hrp.AssemblyLinearVelocity = Vector3.new(hv.X, vy, hv.Z)
	hrp.AssemblyAngularVelocity = Vector3.new(0, spin, 0)
end
-- M.freeParts: parts that move on by their velocity while they are not anchored (M.physicsLog gets
-- { part, anchored } for each of them every physics step: what the physics saw)
M.freeParts = {}
function M.physics(dt)
	for _, p in ipairs(M.freeParts) do
		if M.physicsLog then M.physicsLog[#M.physicsLog + 1] = { p, p.Anchored } end
		if p.Parent and not p.Anchored then p.CFrame = p.CFrame + p.AssemblyLinearVelocity * dt end
	end
	local ch = player.Character
	if not ch then return end
	local hrp = ch:FindFirstChild("HumanoidRootPart")
	if M.physicsLog and hrp then M.physicsLog[#M.physicsLog + 1] = { hrp, hrp.Anchored } end
	if not hrp or hrp.Anchored then return end
	if M.humanoidPhysics then
		local hum = ch:FindFirstChildOfClass("Humanoid")
		M.inPhysics = true
		if hum and M.robloxController then robloxStep(hrp, hum, dt) elseif hum then humanoidStep(hrp, hum, dt) end
		M.inPhysics = false
		return
	end
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
gethui = function() if M.noHui then return nil end return hui end
-- hookfunction / restorefunction (Real docs: the target keeps its identity and runs the replacement, the
-- returned copy runs the original). Plain Lua can't change a function in place, so the mock keeps the
-- replacement in M.hooks[target] (M.callHooked runs a function the way the hooked client would);
-- M.hookFail makes hookfunction error
M.hooks = {}
hookfunction = function(target, replacement)
	if M.hookFail then error("hookfunction failed (mock)", 2) end
	M.hooks[target] = replacement
	return function(...) return target(...) end
end
restorefunction = function(target) M.hooks[target] = nil end
function M.callHooked(f, ...) return (M.hooks[f] or f)(...) end
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
-- Real's mouse as measured in the client, when M.realMouse = { w = screen width, h = height, ox, oy = client
-- origin on the screen }: mousemoveabs scales with integer maths (the factor 65535 / (size - 1) cut to a whole
-- number), and Roblox reports where the cursor was before the latest mouse event (a move shows up when the
-- next event comes; a 1 px relative step back and forth moves nothing at that speed)
M.realMouse, M.osMouse = nil, nil
local function realAxis(v, o, size)
	local n = (v + o) * math.floor(65535 / (size - 1))
	return math.floor(n * size / 65536) - o
end
mousemoveabs = function(x, y)
	M.inputLog[#M.inputLog + 1] = { "mousemoveabs", x, y }
	local r = M.realMouse
	if not r then M.mouse = Vector2.new(x, y) return end
	local nx, ny = realAxis(x, r.ox, r.w), realAxis(y, r.oy, r.h)
	local cur = M.osMouse or M.mouse
	if cur.X ~= nx or cur.Y ~= ny then -- a mouse event: Roblox now shows where the cursor was before it
		M.mouse = cur
		M.osMouse = Vector2.new(nx, ny)
	end
end
mousemoverel = function(dx, dy)
	M.inputLog[#M.inputLog + 1] = { "mousemoverel", dx, dy }
	if M.realMouse and M.osMouse then M.mouse = M.osMouse end
end
mousescroll = logInput("mousescroll")
-- the garbage collector: M.gcTables (tests add tables); getgc(true) returns them all, filtergc the ones with
-- every key in options.Keys (Real docs)
M.gcTables, M.gcCalls = {}, { getgc = 0, filtergc = 0 }
getgc = function(includeTables)
	M.gcCalls.getgc = M.gcCalls.getgc + 1
	return includeTables and table.clone(M.gcTables) or {}
end
filtergc = function(kind, options, one)
	M.gcCalls.filtergc = M.gcCalls.filtergc + 1
	local out = {}
	if kind == "table" then
		for _, t in ipairs(M.gcTables) do
			local match = true
			for _, k in ipairs(options.Keys or {}) do
				if rawget(t, k) == nil then match = false break end
			end
			if match then
				if one then return t end
				out[#out + 1] = t
			end
		end
	end
	if one then return nil end
	return out
end
identifyexecutor = function() return "MockExec", "1.0" end
-- getconnections (Real docs: connection objects with Enabled, Function, Disable, Enable...; a new object for
-- each call, like Real's). M.noGetConnections hides it
getconnections = function(sig)
	if M.noGetConnections then error("getconnections is not available") end
	local out = {}
	for _, c in ipairs(sig._conns or {}) do
		out[#out + 1] = {
			Function = c._fn, Enabled = not c._disabled,
			Disable = function() c._disabled = true end,
			Enable = function() c._disabled = false end,
			Disconnect = function() c:Disconnect() end,
		}
	end
	M.getconnectionsCalls = (M.getconnectionsCalls or 0) + 1
	return out
end

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
-- M.simDt: nil = the simulation moves on with the frame's dt, or a function(dt) -> the simulated time of the
-- frame (Roblox steps physics in 1/240 s steps, so at high frame rates a frame simulates 0, 1 or 2 steps).
-- time() returns the simulation clock M.simNow
M.simNow = 0
function M.step(dt)
	dt = dt or (1 / 60)
	local sdt = dt
	if M.simDt then sdt = M.simDt(dt) end
	M.clockTicks = 0
	M.clockOff = 0
	M.now = M.now + dt
	M.simNow = M.simNow + sdt
	M.frame = M.frame + 1
	-- (measured in the Roblox client: RenderStepped, its waiting threads first, then PreRender)
	RS.RenderStepped:Fire(dt)
	RS.PreRender:Fire(dt)
	for _, b in ipairs(table.clone(binds)) do
		local ok, err = pcall(b.fn, dt)
		if not ok then M.logs[#M.logs + 1] = "BIND ERROR " .. b.name .. ": " .. tostring(err) end
	end
	-- PreAnimation starts at a fixed point of the frame (like Roblox: shortly after the frame starts), so the
	-- time from one PreAnimation to the next is exactly the frame's dt; with M.jobMs the jobs take jobMs
	M.clockOff = M.jobMs and math.max(0, dt - M.jobMs / 1000) or 0
	M.clockTicks = 0
	RS.PreAnimation:Fire(dt)
	-- (measured in the Roblox client: a frame without a physics step has no PreSimulation / Stepped)
	if sdt > 0 then
		RS.PreSimulation:Fire(sdt)
		RS.Stepped:Fire(M.simNow, sdt)
		M.physics(sdt)
		RS.PostSimulation:Fire(sdt)
	end
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

-- ------------------------------------------------------------------------------------------------ V2.38.14 kit tests
-- constraints / body movers with the properties the speed hack's world scales (Roblox's defaults)
cls("Constraint", "Instance", { Attachment0 = nil, Attachment1 = nil, Enabled = true, Visible = false, Color = BrickColor.new("Medium stone grey") })
cls("HingeConstraint", "Constraint", { ActuatorType = Enum.ActuatorType.None, AngularVelocity = 0, MotorMaxTorque = 0,
	MotorMaxAcceleration = math.huge, AngularSpeed = 0, ServoMaxTorque = 0, AngularResponsiveness = 45, TargetAngle = 0 })
cls("PrismaticConstraint", "Constraint", { ActuatorType = Enum.ActuatorType.None, Velocity = 0, MotorMaxForce = 0,
	MotorMaxAcceleration = math.huge, Speed = 0, ServoMaxForce = 0, LinearResponsiveness = 45, TargetPosition = 0 })
cls("AlignPosition", "Constraint", { MaxVelocity = math.huge, Responsiveness = 10, MaxForce = 10000, MaxAxesForce = Vector3.new(10000, 10000, 10000),
	RigidityEnabled = false, Position = Vector3.zero, Mode = nil })
cls("AlignOrientation", "Constraint", { MaxAngularVelocity = math.huge, Responsiveness = 10, MaxTorque = 10000, RigidityEnabled = false, CFrame = CFrame.new() })
cls("LinearVelocity", "Constraint", { VectorVelocity = Vector3.zero, LineVelocity = 0, PlaneVelocity = Vector2.zero, MaxForce = 1000,
	MaxAxesForce = Vector3.new(1000, 1000, 1000), MaxPlanarAxesForce = Vector2.new(1000, 1000), ForceLimitsEnabled = true,
	ForceLimitMode = nil, VelocityConstraintMode = nil })
cls("VectorForce", "Constraint", { Force = Vector3.zero, ApplyAtCenterOfMass = false, RelativeTo = nil })
cls("RopeConstraint", "Constraint", { Length = 5, WinchEnabled = false, WinchSpeed = 2, WinchForce = 10000, WinchResponsiveness = 45 })
cls("SpringConstraint", "Constraint", { Stiffness = 0, Damping = 0, MaxForce = math.huge, FreeLength = 1 })
cls("BodyMover", "Instance")
cls("BodyVelocity", "BodyMover", { Velocity = Vector3.zero, MaxForce = Vector3.new(4000, 4000, 4000), P = 1250 })

-- tags (CollectionService)
do
	local function tagsOf(i) local d = i._d; d.tags = d.tags or {}; return d.tags end
	M.Inst.HasTag = function(self, t) return tagsOf(self)[t] == true end
	M.Inst.AddTag = function(self, t) tagsOf(self)[t] = true end
	M.Inst.RemoveTag = function(self, t) tagsOf(self)[t] = nil end
	M.Inst.GetTags = function(self) local o = {} for t in pairs(tagsOf(self)) do o[#o + 1] = t end return o end
	C.CollectionService.Methods.GetTagged = function(_, t)
		local o = {}
		for _, d in ipairs(game:GetDescendants()) do if d:HasTag(t) then o[#o + 1] = d end end
		return o
	end
	local added = {}
	C.CollectionService.Methods.GetInstanceAddedSignal = function(_, t)
		added[t] = added[t] or M.newSignal("TagAdded:" .. t)
		return added[t]
	end
end

-- distance from the character's head (Roblox docs), 0 without a character
C.Player.Methods.DistanceFromCharacter = function(self, p)
	local ch = self.Character
	local h = ch and (ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart"))
	if not h then return 0 end
	return (h.Position - p).Magnitude
end

-- spatial queries on axis-aligned boxes (rotations ignored): the parts' boxes against a box / a swept box
do
	local function excluded(part, params)
		if params and params.FilterType ~= Enum.RaycastFilterType.Include then
			for _, x in ipairs(params.FilterDescendantsInstances or {}) do
				if part == x or part:IsDescendantOf(x) then return true end
			end
		end
		return false
	end
	local function candidates(params)
		local out = {}
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("BasePart") and d.CanQuery ~= false and d.ClassName ~= "Terrain" and not excluded(d, params) then
				if not (params and params.RespectCanCollide and not d.CanCollide) then out[#out + 1] = d end
			end
		end
		return out
	end
	local function overlap(c1, h1, c2, h2)
		return math.abs(c1.X - c2.X) <= h1.X + h2.X and math.abs(c1.Y - c2.Y) <= h1.Y + h2.Y and math.abs(c1.Z - c2.Z) <= h1.Z + h2.Z
	end
	M.boxQueries = 0
	C.Workspace.Methods.GetPartBoundsInBox = function(_, cf, size, params)
		M.boxQueries = M.boxQueries + 1
		local out, h = {}, size / 2
		for _, p in ipairs(candidates(params)) do
			if overlap(cf.Position, h, p.Position, p.Size / 2) then out[#out + 1] = p end
		end
		return out
	end
	M.casts = 0
	-- a box from cf along dir: the first part it touches (slab test of the ray against each part's box grown by
	-- the cast box); parts the box already overlaps at the start are not hit (like Roblox's shapecasts)
	C.Workspace.Methods.Blockcast = function(_, cf, size, dir, params)
		M.casts = M.casts + 1
		local o, h = cf.Position, size / 2
		local best, bestT = nil, math.huge
		for _, p in ipairs(candidates(params)) do
			local ph = p.Size / 2 + h
			local c = p.Position
			if not overlap(o, h, c, p.Size / 2) then
				local tmin, tmax = 0, 1
				local ok = true
				for _, ax in ipairs({ "X", "Y", "Z" }) do
					local d0, lo, hi = dir[ax], c[ax] - ph[ax], c[ax] + ph[ax]
					if math.abs(d0) < 1e-12 then
						if o[ax] < lo or o[ax] > hi then ok = false break end
					else
						local t1, t2 = (lo - o[ax]) / d0, (hi - o[ax]) / d0
						if t1 > t2 then t1, t2 = t2, t1 end
						tmin = math.max(tmin, t1); tmax = math.min(tmax, t2)
						if tmin > tmax then ok = false break end
					end
				end
				if ok and tmin < bestT then best, bestT = p, tmin end
			end
		end
		if not best then return nil end
		return { Instance = best, Position = o + dir * bestT, Distance = dir.Magnitude * bestT, Normal = Vector3.yAxis, Material = best.Material }
	end
end

-- ModuleScripts the "game" ran (tests set M.modules[ms] = what it returned), require / getloadedmodules
M.modules = {}
local realRequire = require
require = function(m)
	if typeof(m) == "Instance" then
		local v = M.modules[m]
		if v == nil then error("mock: module " .. m:GetFullName() .. " was never run", 2) end
		return v
	end
	return realRequire(m)
end
getloadedmodules = function()
	local o = {}
	for m in pairs(M.modules) do o[#o + 1] = m end
	return o
end
iscclosure = function(f) return debug.info(f, "s") == "[C]" end
-- read-only tables (the kit's Utility tables are frozen): rawset still works in the mock, the flag is checked
M.readonly = setmetatable({}, { __mode = "k" })
isreadonly = function(t) return M.readonly[t] == true end
setreadonly = function(t, v) M.readonly[t] = v and true or nil end
