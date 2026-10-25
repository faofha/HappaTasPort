-- ================================================================================================
-- Headless Roblox mock: signals, scheduler, Instance tree (with GUI absolute layout)
-- ================================================================================================
M.now = 0
M.frame = 0
M.clockTicks = 0
M.viewport = Vector2.new(1920, 1080)
M.inset = 36
M.propWrites = 0
M.writeLog = nil -- set to a table to record {inst, prop}
M.logs = {}

M.clockStep = 1e-6 -- simulated CPU time per os.clock() call
-- M.jobMs: when set, os.clock() runs (frame - jobMs) ahead from PreAnimation to the end of the frame, so the
-- jobs (PreAnimation .. the next PreRender) take jobMs, like the wait between render and jobs in the client
M.jobMs = nil
M.clockOff = 0
function M.clock()
	M.clockTicks = M.clockTicks + 1
	return M.now + M.clockOff + M.clockTicks * M.clockStep
end

-- ------------------------------------------------------------------------------------------------ Signal
local sigMt = { __type = "RBXScriptSignal" }
sigMt.__index = sigMt
local connMt = { __type = "RBXScriptConnection" }
connMt.__index = connMt
function connMt.Disconnect(c)
	if not c.Connected then return end
	c.Connected = false
	local list = c._sig._conns
	for i = #list, 1, -1 do if list[i] == c then table.remove(list, i) end end
end
local function newSignal(name) return setmetatable({ _conns = {}, _name = name }, sigMt) end
M.newSignal = newSignal
function sigMt.Connect(s, fn)
	assert(type(fn) == "function", "Connect expects a function")
	local c = setmetatable({ Connected = true, _sig = s, _fn = fn }, connMt)
	s._conns[#s._conns + 1] = c
	return c
end
function sigMt.Once(s, fn)
	local c
	c = s:Connect(function(...) c:Disconnect(); fn(...) end)
	return c
end
function sigMt.ConnectParallel(s, fn) return s:Connect(fn) end
function sigMt.Wait(s)
	local co = coroutine.running()
	local c
	c = s:Connect(function(...)
		c:Disconnect()
		M.resume(co, ...)
	end)
	return coroutine.yield()
end
-- like Roblox, every handler runs in its own thread, so it may yield (Wait / task.wait)
-- M.reverseSignals = true runs the newest connection first (Roblox doesn't promise an order)
function sigMt.Fire(s, ...)
	local list = table.clone(s._conns)
	if M.reverseSignals then
		local n = #list
		for i = 1, math.floor(n / 2) do list[i], list[n - i + 1] = list[n - i + 1], list[i] end
	end
	for _, c in ipairs(list) do
		if c.Connected and not c._disabled then
			local co = coroutine.create(c._fn)
			local ok, err = coroutine.resume(co, ...)
			if not ok then
				M.logs[#M.logs + 1] = "SIGNAL ERROR [" .. tostring(s._name) .. "]: " .. tostring(err)
				if M.strictSignals then error(err, 0) end
			end
		end
	end
end
function sigMt.Count(s) return #s._conns end

-- ------------------------------------------------------------------------------------------------ scheduler
local sleeping = {}  -- {co, wake, args}
local deferred = {}
function M.resume(co, ...)
	if coroutine.status(co) ~= "suspended" then return end
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		M.logs[#M.logs + 1] = "THREAD ERROR: " .. tostring(err)
		if M.onThreadError then M.onThreadError(err, co) end
	end
end
local function spawnFn(f, ...)
	if type(f) == "thread" then M.resume(f, ...); return f end
	local co = coroutine.create(f)
	M.resume(co, ...)
	return co
end
task = {}
task.spawn = spawnFn
function task.defer(f, ...)
	local co = type(f) == "thread" and f or coroutine.create(f)
	deferred[#deferred + 1] = { co, table.pack(...) }
	return co
end
function task.delay(t, f, ...)
	local co = type(f) == "thread" and f or coroutine.create(f)
	sleeping[#sleeping + 1] = { co = co, wake = M.now + (t or 0), args = table.pack(...) }
	return co
end
function task.wait(t)
	local co, main = coroutine.running()
	if main or co == nil then error("task.wait called from the main thread (mock)") end
	local start = M.now
	sleeping[#sleeping + 1] = { co = co, wake = M.now + (t or 0), args = nil, start = start }
	coroutine.yield()
	return M.now - start
end
function task.cancel(co)
	for i = #sleeping, 1, -1 do if sleeping[i].co == co then table.remove(sleeping, i) end end
	for i = #deferred, 1, -1 do if deferred[i][1] == co then table.remove(deferred, i) end end
	-- (Roblox: a cancelled thread is closed, whatever it was waiting on)
	if type(co) == "thread" and coroutine.status(co) == "suspended" then coroutine.close(co) end
end
function task.synchronize() end
function task.desynchronize() end
wait = function(t) task.wait(t); return t or 0, M.now end
spawn = function(f) task.defer(f) end
delay = function(t, f) task.delay(t, f) end
tick = function() return M.now end
time = function() return M.simNow or M.now end
elapsedTime = function() return M.now end

function M.runDeferred()
	local guard = 0
	while #deferred > 0 and guard < 1000 do
		guard = guard + 1
		local d = table.remove(deferred, 1)
		M.resume(d[1], table.unpack(d[2], 1, d[2].n))
	end
end
function M.resumeDue()
	local due = {}
	for i = #sleeping, 1, -1 do
		if sleeping[i].wake <= M.now + 1e-9 then
			table.insert(due, 1, table.remove(sleeping, i))
		end
	end
	for _, s in ipairs(due) do
		if s.args then M.resume(s.co, table.unpack(s.args, 1, s.args.n)) else M.resume(s.co, M.now - (s.start or M.now)) end
	end
	M.runDeferred()
end
function M.sleepingCount() return #sleeping end

-- ------------------------------------------------------------------------------------------------ classes
local Classes = {}
local function class(name, super, defaults, methods, events)
	local c = { Name = name, Super = super and Classes[super], Defaults = defaults or {}, Methods = methods or {}, Events = events or {} }
	Classes[name] = c
	return c
end
M.Classes = Classes

local GUI_EVENTS = { "MouseEnter", "MouseLeave", "MouseMoved", "InputBegan", "InputChanged", "InputEnded", "MouseWheelForward",
	"MouseWheelBackward", "SelectionGained", "SelectionLost", "TouchTap", "TouchPan", "TouchLongPress" }
local BTN_EVENTS = { "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseButton2Click", "MouseButton2Down",
	"MouseButton2Up", "Activated" }

local function guiDefaults(extra)
	local d = {
		Active = false, AnchorPoint = Vector2.new(0, 0), AutomaticSize = Enum.AutomaticSize.None,
		BackgroundColor3 = Color3.fromRGB(163, 162, 165), BackgroundTransparency = 0, BorderColor3 = Color3.fromRGB(27, 42, 53),
		BorderMode = Enum.BorderMode.Outline, BorderSizePixel = 1, ClipsDescendants = false, LayoutOrder = 0,
		Position = UDim2.new(0, 0, 0, 0), Rotation = 0, Selectable = false, Size = UDim2.new(0, 100, 0, 100),
		SizeConstraint = Enum.SizeConstraint.RelativeXY, Visible = true, ZIndex = 1, Interactable = true,
		GuiState = Enum.GuiState and nil,
	}
	for k, v in pairs(extra or {}) do d[k] = v end
	return d
end
local textDefaults = {
	Font = Enum.Font.Legacy, FontFace = nil, LineHeight = 1, MaxVisibleGraphemes = -1, RichText = false, Text = "Label",
	TextColor3 = Color3.fromRGB(27, 42, 53), TextScaled = false, TextSize = 8, TextStrokeColor3 = Color3.new(0, 0, 0),
	TextStrokeTransparency = 1, TextTransparency = 0, TextTruncate = Enum.TextTruncate.None, TextWrapped = false,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, TextEditable = true,
	PlaceholderText = "", PlaceholderColor3 = Color3.fromRGB(178, 178, 178), ClearTextOnFocus = true, MultiLine = false,
	AutoButtonColor = true, Modal = false, Selected = false, Style = nil, CursorPosition = 1,
}
local imageDefaults = {
	Image = "", ImageColor3 = Color3.new(1, 1, 1), ImageTransparency = 0, ImageRectOffset = Vector2.new(0, 0),
	ImageRectSize = Vector2.new(0, 0), ResampleMode = Enum.ResamplerMode.Default, ScaleType = Enum.ScaleType.Stretch, ImageContent = nil,
	SliceCenter = Rect.new(0, 0, 0, 0), SliceScale = 1, TileSize = UDim2.new(1, 0, 1, 0), AutoButtonColor = true,
	HoverImage = "", PressedImage = "",
}
local function merge(...)
	local out = {}
	for i = 1, select("#", ...) do
		for k, v in pairs(select(i, ...)) do out[k] = v end
	end
	return out
end

class("Instance", nil, { Archivable = true, Name = "Instance" })
class("Folder", "Instance")
class("Model", "Instance", { PrimaryPart = nil, WorldPivot = CFrame.new() })
class("Configuration", "Instance")
class("ValueBase", "Instance")
class("BoolValue", "ValueBase", { Value = false })
class("NumberValue", "ValueBase", { Value = 0 })
class("IntValue", "ValueBase", { Value = 0 })
class("StringValue", "ValueBase", { Value = "" })
class("ObjectValue", "ValueBase", { Value = nil })
class("CFrameValue", "ValueBase", { Value = CFrame.new() })
class("Vector3Value", "ValueBase", { Value = Vector3.zero })
class("Color3Value", "ValueBase", { Value = Color3.new() })
class("LuaSourceContainer", "Instance")
class("BaseScript", "LuaSourceContainer", { Disabled = false, Enabled = true })
class("Script", "BaseScript")
class("LocalScript", "Script")
class("ModuleScript", "LuaSourceContainer")
class("GuiBase", "Instance")
class("GuiBase2d", "GuiBase", { AutoLocalize = true })
class("LayerCollector", "GuiBase2d", { Enabled = true, ResetOnSpawn = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
class("ScreenGui", "LayerCollector", { DisplayOrder = 0, IgnoreGuiInset = false, ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, ClipToDeviceSafeArea = true, SafeAreaCompatibility = nil })
class("GuiObject", "GuiBase2d", guiDefaults(), {}, GUI_EVENTS)
class("Frame", "GuiObject", { Style = nil })
class("CanvasGroup", "GuiObject", { GroupTransparency = 0, GroupColor3 = Color3.new(1, 1, 1) })
class("ScrollingFrame", "GuiObject", { CanvasSize = UDim2.new(0, 0, 2, 0), CanvasPosition = Vector2.new(0, 0), ScrollBarThickness = 12,
	ScrollingEnabled = true, ScrollingDirection = Enum.ScrollingDirection.XY, AutomaticCanvasSize = Enum.AutomaticSize.None,
	ScrollBarImageColor3 = Color3.new(1, 1, 1), ScrollBarImageTransparency = 0, ElasticBehavior = nil, VerticalScrollBarInset = nil,
	TopImage = "", MidImage = "", BottomImage = "" })
class("TextLabel", "GuiObject", textDefaults)
class("TextBox", "GuiObject", textDefaults, {}, { "FocusLost", "Focused", "ReturnPressedFromOnScreenKeyboard" })
class("GuiButton", "GuiObject", { AutoButtonColor = true, Modal = false, Selected = false }, {}, BTN_EVENTS)
class("TextButton", "GuiButton", textDefaults)
class("ImageLabel", "GuiObject", imageDefaults)
class("ImageButton", "GuiButton", imageDefaults)
class("ViewportFrame", "GuiObject", { CurrentCamera = nil, Ambient = Color3.new(), LightColor = Color3.new(), ImageColor3 = Color3.new(1, 1, 1) })
class("UIComponent", "Instance")
class("UIBase", "UIComponent")
class("UICorner", "UIComponent", { CornerRadius = UDim.new(0, 8) })
class("UIStroke", "UIComponent", { Color = Color3.new(), Thickness = 1, Transparency = 0, Enabled = true, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, LineJoinMode = Enum.LineJoinMode.Round })
class("UIPadding", "UIComponent", { PaddingTop = UDim.new(), PaddingBottom = UDim.new(), PaddingLeft = UDim.new(), PaddingRight = UDim.new() })
class("UIGradient", "UIComponent", { Color = ColorSequence.new(Color3.new(1, 1, 1)), Offset = Vector2.new(), Rotation = 0, Transparency = NumberSequence.new(0), Enabled = true })
class("UIScale", "UIComponent", { Scale = 1 })
class("UILayout", "UIComponent")
class("UIGridStyleLayout", "UILayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.Name,
	HorizontalAlignment = Enum.HorizontalAlignment.Left, VerticalAlignment = Enum.VerticalAlignment.Top, AbsoluteContentSize = Vector2.new() })
class("UIListLayout", "UIGridStyleLayout", { Padding = UDim.new(), Wraps = false, HorizontalFlex = nil, VerticalFlex = nil, ItemLineAlignment = nil })
class("UIGridLayout", "UIGridStyleLayout", { CellPadding = UDim2.new(0, 5, 0, 5), CellSize = UDim2.new(0, 100, 0, 100), FillDirectionMaxCells = 0, StartCorner = nil })
class("UIConstraint", "UIComponent")
class("UIAspectRatioConstraint", "UIConstraint", { AspectRatio = 1, AspectType = nil, DominantAxis = nil })
class("UISizeConstraint", "UIConstraint", { MinSize = Vector2.new(), MaxSize = Vector2.new(math.huge, math.huge) })
class("UITextSizeConstraint", "UIConstraint", { MinTextSize = 1, MaxTextSize = 100 })
class("GetTextBoundsParams", "Instance", { Text = "", Font = nil, Size = 14, Width = math.huge, RichText = false })
class("PVInstance", "Instance")
class("BasePart", "PVInstance", {
	Anchored = false, CanCollide = true, CanTouch = true, CanQuery = true, CastShadow = true, Massless = false, Locked = false,
	Transparency = 0, LocalTransparencyModifier = 0, Reflectance = 0, Color = Color3.fromRGB(163, 162, 165),
	Material = Enum.Material.Plastic, Size = Vector3.new(4, 1, 2), CFrame = CFrame.new(), AssemblyLinearVelocity = Vector3.zero,
	AssemblyAngularVelocity = Vector3.zero, Velocity = Vector3.zero, RotVelocity = Vector3.zero, CollisionGroup = "Default",
	TopSurface = Enum.SurfaceType.Smooth, BottomSurface = Enum.SurfaceType.Smooth, BrickColor = BrickColor.new("Medium stone grey"),
	CustomPhysicalProperties = nil, RootPriority = 0, Shape = Enum.PartType.Block,
})
class("Part", "BasePart")
class("MeshPart", "BasePart", { MeshId = "", TextureID = "" })
class("WedgePart", "BasePart")
class("TrussPart", "BasePart")
class("SpawnLocation", "Part")
class("UnionOperation", "BasePart")
class("Terrain", "BasePart")
class("Attachment", "Instance", { CFrame = CFrame.new(), Position = Vector3.zero, Visible = false })
class("JointInstance", "Instance", { Part0 = nil, Part1 = nil, C0 = CFrame.new(), C1 = CFrame.new(), Enabled = true, Active = true })
class("Motor6D", "JointInstance", { Transform = CFrame.new(), CurrentAngle = 0, DesiredAngle = 0, MaxVelocity = 0 })
class("Weld", "JointInstance")
class("WeldConstraint", "Instance", { Part0 = nil, Part1 = nil, Enabled = true })
class("Humanoid", "Instance", {
	Health = 100, MaxHealth = 100, WalkSpeed = 16, JumpPower = 50, JumpHeight = 7.2, UseJumpPower = true, HipHeight = 0,
	AutoRotate = true, AutoJumpEnabled = true, PlatformStand = false, Sit = false, Jump = false, MoveDirection = Vector3.zero,
	RigType = Enum.HumanoidRigType.R6, FloorMaterial = Enum.Material.Plastic, RootPart = nil, CameraOffset = Vector3.zero,
	DisplayDistanceType = nil, BreakJointsOnDeath = true, RequiresNeck = true, EvaluateStateMachine = true, WalkToPoint = Vector3.zero,
	MaxSlopeAngle = 89, NameDisplayDistance = 100, HealthDisplayDistance = 100,
}, {}, { "StateChanged", "Died", "Running", "Jumping", "FreeFalling", "Climbing", "HealthChanged", "MoveToFinished",
	"Seated", "Touched", "AnimationPlayed", "GettingUp", "FallingDown", "Landed", "Swimming", "PlatformStanding", "Strafing", "Ragdoll" })
class("Animator", "Instance", {}, {}, { "AnimationPlayed" })
class("Animation", "Instance", { AnimationId = "" })
class("AnimationTrack", "Instance", { IsPlaying = false, Length = 1, Looped = false, Priority = Enum.AnimationPriority.Core,
	Speed = 1, TimePosition = 0, WeightCurrent = 1, WeightTarget = 1, Animation = nil }, {}, { "Stopped", "Ended", "DidLoop", "KeyframeReached" })
class("Sound", "Instance", { SoundId = "", Volume = 0.5, Playing = false, Looped = false, PlaybackSpeed = 1, TimePosition = 0,
	TimeLength = 0, IsLoaded = true, IsPlaying = false, RollOffMaxDistance = 10000, PlayOnRemove = false }, {}, { "Ended", "Loaded", "Played", "Stopped" })
class("Camera", "PVInstance", { CFrame = CFrame.new(0, 10, 20), Focus = CFrame.new(), FieldOfView = 70, CameraType = Enum.CameraType.Custom,
	CameraSubject = nil, NearPlaneZ = -0.1, HeadLocked = true, HeadScale = 1, DiagonalFieldOfView = 0, MaxAxisFieldOfView = 0 })
class("Player", "Instance", { UserId = 1, DisplayName = "Player1", Character = nil, Team = nil, CameraMaxZoomDistance = 128,
	CameraMinZoomDistance = 0.5, CameraMode = Enum.CameraMode.Classic, DevComputerCameraMode = Enum.DevComputerCameraMovementMode.UserChoice,
	DevEnableMouseLock = true, AccountAge = 100, MembershipType = nil, AutoJumpEnabled = true }, {}, { "CharacterAdded", "CharacterRemoving", "Idled", "Chatted" })
class("PlayerGui", "Instance", { ScreenOrientation = nil, SelectionImageObject = nil })
class("Backpack", "Instance")
class("PlayerScripts", "Instance")
class("Tool", "Instance", { Enabled = true, RequiresHandle = true, CanBeDropped = true, ManualActivationOnly = false, ToolTip = "" },
	{}, { "Equipped", "Unequipped", "Activated", "Deactivated" })
class("Decal", "Instance", { Texture = "", Transparency = 0, Color3 = Color3.new(1, 1, 1) })
class("Texture", "Decal")
class("SpecialMesh", "Instance", { MeshId = "", Scale = Vector3.one })
class("ClickDetector", "Instance", { MaxActivationDistance = 32 }, {}, { "MouseClick", "MouseHoverEnter", "MouseHoverLeave" })
class("ProximityPrompt", "Instance", { Enabled = true, ActionText = "", HoldDuration = 0 }, {}, { "Triggered", "PromptShown", "PromptHidden" })
class("BodyVelocity", "Instance", { Velocity = Vector3.zero, MaxForce = Vector3.zero, P = 1250 })
class("BodyGyro", "Instance", { CFrame = CFrame.new(), MaxTorque = Vector3.zero, P = 3000, D = 500 })
class("AlignPosition", "Instance", { Enabled = true })
class("Highlight", "Instance", { Enabled = true })
class("BindableEvent", "Instance", {}, {}, { "Event" })
class("RemoteEvent", "Instance", {}, {}, { "OnClientEvent" })
class("Accessory", "Instance")
class("Shirt", "Instance")
class("Pants", "Instance")
class("BodyColors", "Instance")
class("HumanoidDescription", "Instance")
class("ParticleEmitter", "Instance", { Enabled = true })
class("Beam", "Instance", { Enabled = true })
class("Trail", "Instance", { Enabled = true })

M.ReadOnly = { ClassName = true, AbsolutePosition = true, AbsoluteSize = true, AbsoluteRotation = true, TextBounds = true,
	TextFits = true, AbsoluteContentSize = true, AbsoluteCanvasSize = true, AbsoluteWindowSize = true, ViewportSize = true }

local function isA(cls, name)
	local c = cls
	while c do
		if c.Name == name then return true end
		c = c.Super
	end
	return false
end

local function findDefault(cls, k)
	local c = cls
	while c do
		local v = c.Defaults[k]
		if v ~= nil then return v, true end
		c = c.Super
	end
	return nil, false
end
local function hasEvent(cls, k)
	local c = cls
	while c do
		for _, e in ipairs(c.Events) do if e == k then return true end end
		c = c.Super
	end
	return false
end
local function findMethod(cls, k)
	local c = cls
	while c do
		local m = c.Methods[k]
		if m then return m end
		c = c.Super
	end
	return nil
end
local function defaultKnown(cls, k)
	local c = cls
	while c do
		if c.Defaults[k] ~= nil then return true end
		c = c.Super
	end
	return false
end

-- generic properties that exist with a nil default (so reading them does not error)
local NIL_PROPS = { Parent = true, PrimaryPart = true, Value = true, Part0 = true, Part1 = true, CameraSubject = true, Character = true,
	FontFace = true, RootPart = true, Animation = true, CurrentCamera = true, Team = true, Adornee = true, SelectedObject = true,
	Font = false, Style = true, CustomPhysicalProperties = true, SoundGroup = true, LocalPlayer = true, NextSelectionDown = true,
	NextSelectionUp = true, NextSelectionLeft = true, NextSelectionRight = true, Tool = true, ElasticBehavior = true,
	VerticalScrollBarInset = true, HorizontalFlex = true, VerticalFlex = true, ItemLineAlignment = true, AspectType = true, DominantAxis = true,
	StartCorner = true, DisplayDistanceType = true, MembershipType = true, ScreenOrientation = true, SelectionImageObject = true,
	SafeAreaCompatibility = true, GuiState = true }

local instMt = { __type = "Instance" }
local Inst = {}
M.Inst = Inst

local function rawInst(self) return rawget(self, "_d") end

local function fireProp(self, k)
	local d = rawInst(self)
	local ps = d.propSignals and d.propSignals[k]
	if ps then ps:Fire() end
	local ch = d.events and d.events.Changed
	if ch then ch:Fire(k) end
end

local abs -- forward
M.propReads = 0 -- every Instance index (property read or method lookup = one Lua/C++ bridge crossing in Roblox)
instMt.__index = function(self, k)
	M.propReads = M.propReads + 1
	local d = rawInst(self)
	if M.readLog then M.readLog[#M.readLog + 1] = d.class.Name .. "." .. tostring(k) end
	if k == "ClassName" then return d.class.Name end
	if k == "Parent" then return d.parent end
	if k == "Name" then return d.props.Name end
	local v = d.props[k]
	if v ~= nil then return v end
	if k == "AbsolutePosition" or k == "AbsoluteSize" then return abs(self, k) end
	if d.isPart then
		local cf = d.props.CFrame or CFrame.new()
		if k == "Position" then return cf.Position end
		if k == "Orientation" or k == "Rotation" then
			local x, y, z = cf:ToEulerAnglesYXZ()
			return Vector3.new(math.deg(x), math.deg(y), math.deg(z))
		end
		if k == "PivotOffset" then return CFrame.new() end
		if k == "Mass" or k == "AssemblyMass" then local s = d.props.Size or Vector3.new(4, 1, 2); return s.X * s.Y * s.Z * 0.7 end
		if k == "AssemblyRootPart" then return self end
		if k == "AssemblyCenterOfMass" then return cf.Position end
		if k == "ExtentsCFrame" then return cf end
	end
	if k == "TextBounds" then return M.textBounds(self) end
	if k == "TextFits" then return true end
	if k == "AbsoluteRotation" then return 0 end
	local m = Inst[k] or findMethod(d.class, k)
	if m then return m end
	if k == "Changed" or k == "ChildAdded" or k == "ChildRemoved" or k == "DescendantAdded" or k == "DescendantRemoving"
		or k == "AncestryChanged" or k == "Destroying" or k == "AttributeChanged" or hasEvent(d.class, k) then
		d.events = d.events or {}
		local s = d.events[k]
		if not s then s = newSignal(d.class.Name .. "." .. k); d.events[k] = s end
		return s
	end
	if d.class.Dynamic then
		local dyn = d.class.Dynamic(self, k)
		if dyn ~= nil then return dyn end
	end
	local child = d.childByName[k]
	if child then return child end
	for _, c in ipairs(d.children) do
		if rawInst(c).props.Name == k then return c end
	end
	local dv, known = findDefault(d.class, k)
	if known then return dv end
	if NIL_PROPS[k] then return nil end
	if d.class.Name == "Camera" and k == "ViewportSize" then return M.viewport end -- follows M.viewport (a resize)
	error(tostring(k) .. " is not a valid member of " .. d.class.Name .. " \"" .. tostring(d.props.Name) .. "\"", 2)
end

local function setParent(self, p)
	local d = rawInst(self)
	if d.destroyed then error("The Parent property of " .. tostring(d.props.Name) .. " is locked", 3) end
	if p == self then error("Attempt to set parent to self", 3) end
	local old = d.parent
	if old == p then return end
	if p ~= nil then
		-- cycle check
		local a = p
		while a do
			if a == self then error("Attempt to set parent of " .. d.props.Name .. " to a descendant", 3) end
			a = rawInst(a).parent
		end
	end
	if old then
		local od = rawInst(old)
		for i = #od.children, 1, -1 do if od.children[i] == self then table.remove(od.children, i) end end
		if od.childByName[d.props.Name] == self then
			od.childByName[d.props.Name] = nil
			for _, c in ipairs(od.children) do
				if rawInst(c).props.Name == d.props.Name then od.childByName[d.props.Name] = c; break end
			end
		end
		if od.events and od.events.ChildRemoved then od.events.ChildRemoved:Fire(self) end
		-- like Roblox: every ancestor gets DescendantRemoving for the instance and each of its descendants
		local removed = { self }
		for _, desc in ipairs(self:GetDescendants()) do removed[#removed + 1] = desc end
		local a = old
		while a do
			local ad = rawInst(a)
			if ad.events and ad.events.DescendantRemoving then
				for _, r in ipairs(removed) do ad.events.DescendantRemoving:Fire(r) end
			end
			a = ad.parent
		end
	end
	d.parent = p
	if p then
		local pd = rawInst(p)
		pd.children[#pd.children + 1] = self
		if pd.childByName[d.props.Name] == nil then pd.childByName[d.props.Name] = self end
		if pd.events and pd.events.ChildAdded then pd.events.ChildAdded:Fire(self) end
		local function fireDesc(inst)
			local a = p
			while a do
				local ad = rawInst(a)
				if ad.events and ad.events.DescendantAdded then ad.events.DescendantAdded:Fire(inst) end
				a = ad.parent
			end
		end
		fireDesc(self)
		for _, desc in ipairs(self:GetDescendants()) do fireDesc(desc) end
	end
	if d.events and d.events.AncestryChanged then d.events.AncestryChanged:Fire(self, p) end
	fireProp(self, "Parent")
end

instMt.__newindex = function(self, k, v)
	local d = rawInst(self)
	if k == "Parent" then
		if v ~= nil and typeof(v) ~= "Instance" then error("Parent must be an Instance", 2) end
		setParent(self, v)
		return
	end
	if M.ReadOnly[k] then error(k .. " is read-only (mock)", 2) end
	if k == "Name" then
		v = tostring(v)
		local p = d.parent
		if p then
			local pd = rawInst(p)
			if pd.childByName[d.props.Name] == self then pd.childByName[d.props.Name] = nil end
			if pd.childByName[v] == nil then pd.childByName[v] = self end
		end
	end
	if k == "FontFace" and typeof(v) ~= "Font" then error("FontFace expects a Font", 2) end
	if k == "Font" and typeof(v) == "EnumItem" then
		d.props.FontFace = Font.fromEnum(v)
	elseif k == "FontFace" and typeof(v) == "Font" then
		d.props.Font = Enum.Font.Unknown
	end
	if (k == "Size" or k == "Position") and d.isGui and typeof(v) ~= "UDim2" then error(k .. " expects UDim2 on " .. d.class.Name, 2) end
	if k == "Text" and v ~= nil then v = tostring(v) end
	-- (Roblox keeps workspace.Gravity at 1000 or less, measured in the client)
	if k == "Gravity" and d.class.Name == "Workspace" and type(v) == "number" and v > 1000 then v = 1000 end
	if d.isPart and (k == "Position" or k == "Orientation" or k == "Rotation") then
		local cf = d.props.CFrame or CFrame.new()
		if k == "Position" then
			cf = CFrame.new(v) * cf.Rotation
		else
			cf = CFrame.new(cf.Position) * CFrame.fromOrientation(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
		end
		k, v = "CFrame", cf
	end
	M.propWrites = M.propWrites + 1
	if M.writeLog then M.writeLog[#M.writeLog + 1] = { self, k } end
	local old = d.props[k]
	d.props[k] = v
	if old ~= v then fireProp(self, k) end
end
instMt.__tostring = function(self) return rawInst(self).props.Name end

function Instance_new(className, parent)
	local cls = Classes[className]
	if not cls then error("Unable to create an Instance of type \"" .. tostring(className) .. "\"", 2) end
	local d = { class = cls, props = { Name = className }, children = {}, childByName = {}, parent = nil, attrs = {},
		isGui = isA(cls, "GuiObject"), isPart = isA(cls, "BasePart") }
	local self = setmetatable({ _d = d }, instMt)
	if cls.Name == "Humanoid" then d.state = Enum.HumanoidStateType.Running end
	if parent then self.Parent = parent end
	return self
end
Instance = { new = Instance_new }
function Instance.fromExisting(i) return i:Clone() end

-- ------------------------------------------------------------------------------------------------ generic methods
function Inst.IsA(self, name) return isA(rawInst(self).class, name) end
function Inst.GetChildren(self) return table.clone(rawInst(self).children) end
function Inst.GetDescendants(self)
	local out = {}
	local function rec(i)
		for _, c in ipairs(rawInst(i).children) do
			out[#out + 1] = c
			rec(c)
		end
	end
	rec(self)
	return out
end
function Inst.FindFirstChild(self, name, recursive)
	local d = rawInst(self)
	for _, c in ipairs(d.children) do
		if rawInst(c).props.Name == name then return c end
	end
	if recursive then
		for _, c in ipairs(d.children) do
			local r = c:FindFirstChild(name, true)
			if r then return r end
		end
	end
	return nil
end
function Inst.FindFirstChildOfClass(self, cn)
	for _, c in ipairs(rawInst(self).children) do if rawInst(c).class.Name == cn then return c end end
	return nil
end
function Inst.FindFirstChildWhichIsA(self, cn, recursive)
	for _, c in ipairs(rawInst(self).children) do if c:IsA(cn) then return c end end
	if recursive then
		for _, c in ipairs(rawInst(self).children) do
			local r = c:FindFirstChildWhichIsA(cn, true)
			if r then return r end
		end
	end
	return nil
end
function Inst.FindFirstAncestor(self, name)
	local a = rawInst(self).parent
	while a do
		if rawInst(a).props.Name == name then return a end
		a = rawInst(a).parent
	end
	return nil
end
function Inst.FindFirstAncestorOfClass(self, cn)
	local a = rawInst(self).parent
	while a do
		if rawInst(a).class.Name == cn then return a end
		a = rawInst(a).parent
	end
	return nil
end
function Inst.FindFirstAncestorWhichIsA(self, cn)
	local a = rawInst(self).parent
	while a do
		if a:IsA(cn) then return a end
		a = rawInst(a).parent
	end
	return nil
end
function Inst.WaitForChild(self, name, timeout)
	local c = self:FindFirstChild(name)
	if c then return c end
	local co, main = coroutine.running()
	if main then return nil end
	local t0 = M.now
	while not c do
		if timeout and M.now - t0 >= timeout then return nil end
		task.wait()
		c = self:FindFirstChild(name)
		if M.now - t0 > 30 then return nil end
	end
	return c
end
function Inst.IsDescendantOf(self, a)
	local p = rawInst(self).parent
	while p do
		if p == a then return true end
		p = rawInst(p).parent
	end
	return false
end
function Inst.IsAncestorOf(self, d) return d:IsDescendantOf(self) end
function Inst.GetFullName(self)
	local parts = {}
	local a = self
	while a and rawInst(a).class.Name ~= "DataModel" do
		table.insert(parts, 1, rawInst(a).props.Name)
		a = rawInst(a).parent
	end
	return table.concat(parts, ".")
end
function Inst.ClearAllChildren(self)
	for _, c in ipairs(self:GetChildren()) do c:Destroy() end
end
function Inst.Destroy(self)
	local d = rawInst(self)
	if d.destroyed then return end
	if d.events and d.events.Destroying then d.events.Destroying:Fire() end
	for _, c in ipairs(self:GetChildren()) do c:Destroy() end
	if d.parent then setParent(self, nil) end
	d.destroyed = true
	if d.events then
		for _, s in pairs(d.events) do
			for _, c in ipairs(table.clone(s._conns)) do c:Disconnect() end
		end
	end
	if d.propSignals then
		for _, s in pairs(d.propSignals) do
			for _, c in ipairs(table.clone(s._conns)) do c:Disconnect() end
		end
	end
end
Inst.Remove = function(self) self.Parent = nil end
local function cloneInto(self, map)
	local d = rawInst(self)
	if d.props.Archivable == false then return nil end
	local c = Instance_new(d.class.Name)
	map[self] = c
	local cd = rawInst(c)
	for k, v in pairs(d.props) do cd.props[k] = v end
	for k, v in pairs(d.attrs) do cd.attrs[k] = v end
	for _, ch in ipairs(d.children) do
		local cc = cloneInto(ch, map)
		if cc then cc.Parent = c end
	end
	return c
end
function Inst.Clone(self)
	local map = {}
	local c = cloneInto(self, map)
	-- (like Roblox: a property pointing inside the cloned tree, e.g. a Model's PrimaryPart, points at the copy)
	for _, cc in pairs(map) do
		local props = rawInst(cc).props
		for k, v in pairs(props) do
			if typeof(v) == "Instance" and map[v] then props[k] = map[v] end
		end
	end
	return c
end
function Inst.GetPropertyChangedSignal(self, k)
	local d = rawInst(self)
	d.propSignals = d.propSignals or {}
	local s = d.propSignals[k]
	if not s then s = newSignal(d.class.Name .. ":" .. k); d.propSignals[k] = s end
	return s
end
function Inst.GetAttribute(self, k) return rawInst(self).attrs[k] end
function Inst.SetAttribute(self, k, v)
	rawInst(self).attrs[k] = v
	local d = rawInst(self)
	if d.events and d.events.AttributeChanged then d.events.AttributeChanged:Fire(k) end
end
function Inst.GetAttributes(self) return table.clone(rawInst(self).attrs) end
function Inst.GetAttributeChangedSignal(self, k) return self:GetPropertyChangedSignal("@" .. k) end
function Inst.GetTags() return {} end
function Inst.HasTag() return false end
function Inst.AddTag() end
function Inst.RemoveTag() end
function Inst.GetDebugId(self) return tostring(rawInst(self)):sub(8) end
function Inst.GetActor() return nil end
M.isDestroyed = function(i) return rawInst(i).destroyed == true end
M.rawProps = function(i) return rawInst(i).props end

-- ------------------------------------------------------------------------------------------------ GUI absolute layout
local function uiScaleOf(inst)
	local d = rawInst(inst)
	for _, c in ipairs(d.children) do
		local cd = rawInst(c)
		if cd.class.Name == "UIScale" then return cd.props.Scale or 1 end
	end
	return 1
end
-- returns absPos, absSize, accumulated scale for children offsets
local function layout(inst)
	local d = rawInst(inst)
	local cls = d.class
	if isA(cls, "LayerCollector") then
		-- Roblox: AbsolutePosition uses the CoreUISafeInsets space, whose origin is the bottom-left
		-- corner of the top bar (GuiBase2d.AbsolutePosition docs). A ScreenGui that ignores the inset
		-- starts at the top of the screen, so its AbsolutePosition.Y is -inset.
		local ins = d.props.ScreenInsets
		local ign = d.props.IgnoreGuiInset or (ins ~= nil and ins ~= Enum.ScreenInsets.CoreUISafeInsets)
		if ign then return Vector2.new(0, -M.inset), M.viewport, 1 end
		return Vector2.new(0, 0), Vector2.new(M.viewport.X, M.viewport.Y - M.inset), 1
	end
	if not d.isGui then
		return Vector2.new(0, 0), M.viewport, 1
	end
	local p = d.parent
	local pPos, pSize, pScale
	if p and (rawInst(p).isGui or isA(rawInst(p).class, "LayerCollector")) then
		pPos, pSize, pScale = layout(p)
	else
		pPos, pSize, pScale = Vector2.new(0, 0), M.viewport, 1
	end
	local own = uiScaleOf(inst)
	local size = d.props.Size or cls.Defaults.Size or UDim2.new(0, 100, 0, 100)
	local pos = d.props.Position or UDim2.new()
	local ap = d.props.AnchorPoint or Vector2.new()
	local w = (size.X.Scale * pSize.X + size.X.Offset * pScale) * own
	local h = (size.Y.Scale * pSize.Y + size.Y.Offset * pScale) * own
	local x = pPos.X + pos.X.Scale * pSize.X + pos.X.Offset * pScale - ap.X * w
	local y = pPos.Y + pos.Y.Scale * pSize.Y + pos.Y.Offset * pScale - ap.Y * h
	return Vector2.new(x, y), Vector2.new(w, h), pScale * own
end
function abs(inst, k)
	local p, s = layout(inst)
	if k == "AbsolutePosition" then return p end
	return s
end
M.layout = layout

function M.fontAdvance(inst)
	local d = rawInst(inst)
	local ff = d.props.FontFace
	local fam = ff and ff.Family or ""
	local name = fam:match("families/(.-)%.json") or ""
	return (M.fontFamilyAdvance[name] or 0.5) * (M.emScale and M.emScale(name) or 1)
end
function M.textBounds(inst)
	local d = rawInst(inst)
	local t = d.props.Text or ""
	local size = d.props.TextSize or 8
	local adv = M.fontAdvance(inst)
	local w = 0
	for line in (t .. "\n"):gmatch("(.-)\n") do w = math.max(w, utf8.len(line) or #line) end
	local lines = select(2, t:gsub("\n", "")) + 1
	return Vector2.new(w * size * adv, lines * size)
end

-- visible = Visible on itself and all GuiObject ancestors, and attached to an enabled ScreenGui
function M.isShown(inst)
	local a = inst
	while a do
		local d = rawInst(a)
		if d.isGui and d.props.Visible == false then return false end
		if isA(d.class, "LayerCollector") then return d.props.Enabled ~= false end
		if d.isGui == false and not isA(d.class, "LayerCollector") and d.class.Name ~= "Folder" then
			-- non gui container in between
		end
		a = d.parent
	end
	return false
end
