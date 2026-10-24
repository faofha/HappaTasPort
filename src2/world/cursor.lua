-- ================================================================================================
--  CURSOR  (HappaTAS 3 world plugin, order 60): the NohBoard fake cursor (V2.38.16 p11_cursor).
--  While the camera has the mouse locked (right click, shift lock, first person) a fake cursor image stays
--  where the cursor was and the real cursor is hidden.
--   * Creating: the fake cursor is shown on the same pixel as the real one FIRST, the real cursor is hidden
--     two frames later (the OS draws the real cursor at once, GUI changes reach the screen a frame or two
--     later: hiding both at once left a gap).
--   * Testing: the real cursor stays hidden for the whole replay, the fake one shows the recorded cursor.
--     While the recording had the camera locked, the hidden real cursor is moved the way the mouse moved
--     the camera, so NohBoard shows the mouse movement.
--  Its overlay is a ScreenGui of its own (CoreGui, else gethui()), owned by the engine's lifecycle.
-- ================================================================================================
local Env = import("platform/env")
local Util = import("engine/util")

local clamp = Util.clamp
local Cursor = { name = "cursor", order = 60 }
Cursor.__index = Cursor

local ARROW = { "rbxasset://textures/Cursors/KeyboardMouse/ArrowFarCursor.png", 64 }
local LOCKED = { "rbxasset://textures/MouseLockedCursor.png", 32 }
local HIDE_DELAY = 2 -- frames the real and fake cursor overlap before the real one is hidden
local DISPLAY_ORDER = 2147483000

function Cursor.new(E)
	local self = setmetatable({ E = E, sg = nil, img = nil, frameNo = 0, lastPX = nil, lastPY = nil,
		uis = Env.svc("UserInputService"),
		st = { fake = false, realHidden = false, hideAt = nil, icon = nil, prevIcon = true, test = false, wasLocked = false,
			anchorX = 0, anchorY = 0, virtX = 0, virtY = 0, lastYaw = nil, lastPitch = nil, lastFrame = nil, lastVersion = nil } }, Cursor)
	pcall(function() self.ugs = UserSettings():GetService("UserGameSettings") end)
	E.life:own(function() self:cursorReset() end)
	return self
end

function Cursor:ensure()
	local img = self.img
	if img and img.Parent then return true end
	if not self.sg then
		local sg = Instance.new("ScreenGui")
		sg.Name = "HappaCursor"
		sg.ResetOnSpawn = false
		sg.IgnoreGuiInset = true
		pcall(function() sg.AutoLocalize = false end)
		pcall(function() sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
		pcall(function() sg.DisplayOrder = DISPLAY_ORDER end)
		local parent = Env.svc("CoreGui")
		if not (parent and pcall(function() sg.Parent = parent end)) then
			local hui = Env.gethui and Env.gethui()
			if not (hui and pcall(function() sg.Parent = hui end)) then
				sg:Destroy()
				return false
			end
		end
		self.sg = self.E.life:own(sg)
	end
	img = Instance.new("ImageLabel")
	img.Name = "Cursor"
	img.BackgroundTransparency = 1
	img.BorderSizePixel = 0
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.ZIndex = 10
	img.Active = false
	img.Visible = false
	img.Parent = self.sg
	self.img = img
	self.st.icon = nil
	return true
end

function Cursor:setIcon(which)
	local st = self.st
	if st.icon == which then return end
	st.icon = which
	self.img.Image = which[1]
	self.img.Size = UDim2.fromOffset(which[2], which[2])
end

function Cursor:showFakeAt(x, y)
	x, y = math.floor(x + 0.5), math.floor(y + 0.5)
	if x ~= self.lastPX or y ~= self.lastPY then
		self.lastPX, self.lastPY = x, y
		self.img.Position = UDim2.fromOffset(x, y)
	end
	if not self.st.fake then
		self.st.fake = true
		self.img.Visible = true
	end
end
function Cursor:hideFake()
	if self.st.fake then
		self.st.fake = false
		if self.img then self.img.Visible = false end
	end
end
function Cursor:hideReal()
	local st = self.st
	if st.realHidden then return end
	st.prevIcon = self.uis.MouseIconEnabled
	st.realHidden = true
	pcall(function() self.uis.MouseIconEnabled = false end)
end
function Cursor:showReal()
	local st = self.st
	if not st.realHidden then return end
	st.realHidden = false
	pcall(function() self.uis.MouseIconEnabled = st.prevIcon ~= false end)
end

function Cursor:cursorReset()
	self:showReal()
	self:hideFake()
	local st = self.st
	st.hideAt = nil
	st.test = false
	st.wasLocked = false
	st.lastYaw, st.lastPitch, st.lastFrame = nil, nil, nil
end

local function viewportCenter()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	return vp.X / 2, vp.Y / 2, vp
end

function Cursor:sensitivity()
	local s = 1
	if self.ugs then pcall(function() s = self.ugs.MouseSensitivity end) end
	if type(s) ~= "number" or s <= 0 then s = 1 end
	return s
end

function Cursor:testStep(tl, f)
	local st, inputs = self.st, self.E.inputs
	if not st.test then
		st.test = true
		st.wasLocked = false
		st.lastYaw, st.lastPitch, st.lastFrame = nil, nil, nil
		st.hideAt = nil
		self:hideReal()
	end
	if not f then return end
	local cx, cy, vp = viewportCenter()
	local px, py = inputs:framePoint(tl, f)
	local locked = inputs:frameLocked(tl, f)
	local centered = tl:get("ShiftLock", f, 1) == 1 or tl:get("Zoom", f, 1) <= 0.55
	if locked then
		if not st.wasLocked then
			if centered then st.anchorX, st.anchorY = cx, cy
			else st.anchorX, st.anchorY = px or cx, py or cy end
			st.virtX, st.virtY = px or st.anchorX, py or st.anchorY
			st.lastYaw = nil
		end
		if centered then st.anchorX, st.anchorY = cx, cy end
		self:setIcon(tl:get("ShiftLock", f, 1) == 1 and LOCKED or ARROW)
		self:showFakeAt(st.anchorX, st.anchorY)
		-- the hidden real cursor follows the camera like the mouse did (NohBoard)
		if f ~= st.lastFrame or tl.version ~= st.lastVersion then
			-- camera yaw / pitch from the recorded camera CFrame
			local yaw = math.atan2(tl:get("CamCframe", f, 6), tl:get("CamCframe", f, 12))
			local pitch = math.asin(clamp(-tl:get("CamCframe", f, 9), -1, 1))
			if st.lastYaw then
				local dy, dp = yaw - st.lastYaw, pitch - st.lastPitch
				if dy > math.pi then dy = dy - 2 * math.pi elseif dy < -math.pi then dy = dy + 2 * math.pi end
				local mult = self.E.settings:get("invisibleMouseSpeed")
				if mult <= 0 then mult = 1 end
				local sens = self:sensitivity()
				-- Roblox camera: 0.002 pi rad a pixel horizontally, 0.0015 pi vertically (x sensitivity)
				local mx = -dy / (0.002 * math.pi * sens) * mult
				local my = -dp / (0.0015 * math.pi * sens) * mult
				if math.abs(mx) > 0.05 or math.abs(my) > 0.05 then
					st.virtX = clamp(st.virtX + mx, 2, vp.X - 2)
					st.virtY = clamp(st.virtY + my, 2, vp.Y - 2)
					if self.E.settings:on("replayMouseMovement") then inputs:moveRealMouse(st.virtX, st.virtY) end
				end
			end
			st.lastYaw, st.lastPitch = yaw, pitch
		end
	else
		self:setIcon(ARROW)
		if px then self:showFakeAt(px, py) end
		st.lastYaw = nil
	end
	st.lastFrame, st.lastVersion = f, tl.version
	st.wasLocked = locked
end

-- once a frame after the camera has updated: f = the frame shown (Test, or paused with a locked camera)
function Cursor:update(tl, f)
	local E, st = self.E, self.st
	self.frameNo = self.frameNo + 1
	if not E.settings:on("nohboardCursor") or not self.uis.MouseEnabled then
		if st.fake or st.realHidden then self:cursorReset() end
		return
	end
	local mode = E.mode
	if mode == 3 then
		if not self:ensure() then return end
		self:testStep(tl, f)
		return
	end
	if st.test then self:cursorReset() end
	if mode ~= 2 then
		if st.fake or st.realHidden then self:cursorReset() end
		return
	end
	local cs = E.cs
	local isShift = (f and tl:get("ShiftLock", f, 1) == 1) or cs:isShiftlocked()
	local isFP = (f and tl:get("Zoom", f, 1) <= 0.55) or cs:isFirstPerson()
	local mb = self.uis.MouseBehavior
	local centered = isShift or isFP or mb == Enum.MouseBehavior.LockCenter
	local locked = (centered or mb ~= Enum.MouseBehavior.Default) and not cs:isMouseFree() and not (E.modalOpen and E.modalOpen())
	if locked then
		if not self:ensure() then return end
		if centered then
			local cx, cy = viewportCenter()
			st.anchorX, st.anchorY = cx, cy
		elseif not st.wasLocked then
			local m = self.uis:GetMouseLocation()
			st.anchorX, st.anchorY = m.X, m.Y
		end
		st.wasLocked = true
		self:setIcon(isShift and LOCKED or ARROW)
		if centered then
			st.hideAt = nil
			self:hideReal()
		elseif not st.fake then
			st.hideAt = self.frameNo + HIDE_DELAY
		end
		self:showFakeAt(st.anchorX, st.anchorY)
		if st.hideAt and self.frameNo >= st.hideAt then
			st.hideAt = nil
			self:hideReal()
		end
	else
		st.wasLocked = false
		if st.fake or st.realHidden then
			self:showReal()
			self:hideFake()
			st.hideAt = nil
		end
	end
end

return Cursor
