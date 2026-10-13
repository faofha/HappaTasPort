-- ================================================================================================
--  CURSOR  (NohBoard fake cursor)
--
--  While the camera has the mouse locked (right click, shift lock, first person) a fake cursor
--  image stays where the cursor was and the real cursor is hidden.
--   * Creating: the fake cursor is shown on the same pixel as the real one FIRST, the real cursor is
--     hidden two frames later. The real cursor is drawn by the OS straight away while GUI changes
--     reach the screen a frame or two later, so hiding both at once used to leave a gap.
--   * Testing: the real cursor stays hidden for the whole replay, the fake one shows the recorded
--     cursor. While the recording had the camera locked, the hidden real cursor is moved the way the
--     mouse moved the camera, so NohBoard shows the mouse movement.
-- ================================================================================================
do
	local ARROW = { "rbxasset://textures/Cursors/KeyboardMouse/ArrowFarCursor.png", 64 }
	local LOCKED = { "rbxasset://textures/MouseLockedCursor.png", 32 }
	local HIDE_DELAY = 2 -- frames the real and fake cursor overlap before the real one is hidden
	local Default = Enum.MouseBehavior.Default

	local UserGameSettings
	pcall(function() UserGameSettings = UserSettings():GetService("UserGameSettings") end)

	local sg, img
	local st = {
		fake = false, realHidden = false, hideAt = nil, icon = nil, prevIcon = true,
		test = false, wasLocked = false, anchorX = 0, anchorY = 0, virtX = 0, virtY = 0,
		lastYaw = nil, lastPitch = nil, lastFrame = nil,
	}
	local frameNo = 0

	local function ensure()
		if img and img.Parent then return true end
		sg = sg or UI.Overlay("HappaCursor", 2147483000)
		if not sg then return false end
		img = Instance.new("ImageLabel")
		img.Name = "Cursor"
		img.BackgroundTransparency = 1
		img.BorderSizePixel = 0
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.ZIndex = 10
		img.Active = false
		img.Visible = false
		img.Parent = sg
		st.icon = nil
		return true
	end

	local function setIcon(which)
		if st.icon == which then return end
		st.icon = which
		img.Image = which[1]
		img.Size = UDim2.fromOffset(which[2], which[2])
	end

	local lastPX, lastPY
	local function showFakeAt(x, y)
		x, y = math.floor(x + 0.5), math.floor(y + 0.5)
		if x ~= lastPX or y ~= lastPY then
			lastPX, lastPY = x, y
			img.Position = UDim2.fromOffset(x, y)
		end
		if not st.fake then
			st.fake = true
			img.Visible = true
		end
	end
	local function hideFake()
		if st.fake then
			st.fake = false
			if img then img.Visible = false end
		end
	end
	local function hideReal()
		if st.realHidden then return end
		st.prevIcon = UIS.MouseIconEnabled
		st.realHidden = true
		pcall(function() UIS.MouseIconEnabled = false end)
	end
	local function showReal()
		if not st.realHidden then return end
		st.realHidden = false
		pcall(function() UIS.MouseIconEnabled = st.prevIcon ~= false end)
	end

	function Cursor.Reset()
		showReal()
		hideFake()
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

	-- camera yaw / pitch (radians) from a recorded camera CFrame table
	local function yawPitch(cc)
		local yaw = math.atan2(cc[6], cc[12])
		local pitch = math.asin(clampn(-cc[9], -1, 1))
		return yaw, pitch
	end

	local function sensitivity()
		local s = 1
		if UserGameSettings then pcall(function() s = UserGameSettings.MouseSensitivity end) end
		if type(s) ~= "number" or s <= 0 then s = 1 end
		return s
	end

	local function testStep(fr)
		if not st.test then
			st.test = true
			st.wasLocked = false
			st.lastYaw, st.lastPitch, st.lastFrame = nil, nil, nil
			st.hideAt = nil
			hideReal()
		end
		if not fr then return end
		local cx, cy, vp = viewportCenter()
		local px, py = InputSys.FramePoint(fr)
		local locked = InputSys.FrameLocked(fr)
		local centered = fr.ShiftLock == 1 or (fr.Zoom or 99) < 1
		if locked then
			if not st.wasLocked then
				if centered then st.anchorX, st.anchorY = cx, cy
				else st.anchorX, st.anchorY = px or cx, py or cy end
				st.virtX, st.virtY = px or st.anchorX, py or st.anchorY
				st.lastYaw = nil
			end
			if centered then st.anchorX, st.anchorY = cx, cy end
			setIcon(fr.ShiftLock == 1 and LOCKED or ARROW)
			showFakeAt(st.anchorX, st.anchorY)
			-- the hidden real cursor follows the camera like the mouse did (NohBoard)
			if fr ~= st.lastFrame and type(fr.CamCframe) == "table" then
				local yaw, pitch = yawPitch(fr.CamCframe)
				if st.lastYaw then
					local dy, dp = yaw - st.lastYaw, pitch - st.lastPitch
					if dy > math.pi then dy = dy - 2 * math.pi elseif dy < -math.pi then dy = dy + 2 * math.pi end
					local mult = Settings.Get("Invisible Mouse Speed Multiplier")
					if mult <= 0 then mult = 1 end
					local sens = sensitivity()
					-- Roblox camera: 0.002*pi rad per pixel horizontally, 0.0015*pi vertically (x sensitivity)
					local mx = -dy / (0.002 * math.pi * sens) * mult
					local my = -dp / (0.0015 * math.pi * sens) * mult
					if math.abs(mx) > 0.05 or math.abs(my) > 0.05 then
						st.virtX = clampn(st.virtX + mx, 2, vp.X - 2)
						st.virtY = clampn(st.virtY + my, 2, vp.Y - 2)
						if Settings.On("Replay Mouse Movement") then InputSys.MoveRealMouse(st.virtX, st.virtY) end
					end
				end
				st.lastYaw, st.lastPitch = yaw, pitch
			end
		else
			setIcon(ARROW)
			if px then showFakeAt(px, py) end
			st.lastYaw = nil
		end
		st.lastFrame = fr
		st.wasLocked = locked
	end

	-- called once per frame after the camera has updated
	function Cursor.Update(mode, fr, menuOpen)
		frameNo = frameNo + 1
		if not Settings.On("NohBoard Cursor") or not UIS.MouseEnabled then
			if st.fake or st.realHidden then Cursor.Reset() end
			return
		end
		if mode == 3 then
			if not ensure() then return end
			testStep(fr)
			return
		end
		if st.test then Cursor.Reset() end
		if mode ~= 2 then
			if st.fake or st.realHidden then Cursor.Reset() end
			return
		end
		local mb = UIS.MouseBehavior
		local locked = mb ~= Default and not Bridge.IsMouseFree() and not menuOpen
		if locked then
			if not ensure() then return end
			local m = UIS:GetMouseLocation()
			setIcon(Bridge.IsShiftlocked() and LOCKED or ARROW)
			if not st.fake then
				st.hideAt = frameNo + HIDE_DELAY
			end
			showFakeAt(m.X, m.Y)
			if st.hideAt and frameNo >= st.hideAt then
				st.hideAt = nil
				hideReal()
			end
		elseif st.fake or st.realHidden then
			-- the real cursor comes back instantly (OS), the fake one disappears a frame later on screen
			showReal()
			hideFake()
			st.hideAt = nil
		end
	end

	Janitor.add(function() Cursor.Reset() end)
end

