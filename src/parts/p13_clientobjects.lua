-- ================================================================================================
--  CLIENT OBJECTS   (parts that only exist / move on your client: EToH kit objects etc.)
--
--  Recording: KEYFRAME + VELOCITY. A part is written when the velocity model stops explaining it,
--  so spinners / sliders cost a record every few frames and static parts cost nothing.
--  Everything is measured on the TAS clock (frame TotalTime), the same clock playback uses, so the
--  model that was checked while recording is exactly what plays back.
--  Playback: the pose at time t comes from the model, blended towards the next keyframe over one
--  frame ("Smooth Client Objects", same idea as Tasability's render segments). Poses are written in
--  Heartbeat (physics) and again at the end of the render step (so game scripts can't override them).
--  A part costs nothing while it is still as it was when it was registered; when it changes for the first
--  time, its start state goes into the full snapshots recorded before it (V2.38.15, see starts.add), so
--  playback shows it there even when the part is somewhere else now (a pressed morph, a fallen platform).
--
--  record layout (v3):  frame byte = 4 (delta) / 5 (full snapshot) + 8 / 16 / 32 when the frame carries
--      clock 1 / 2 / 3, + 64 on the full snapshot that starts a new recording (its clocks start again
--      from 0: playback doesn't blend the clocks into it), then those clocks (zigzag, the change since the
--      last frame that carried them; a full snapshot starts again from 0), then records: varint id, varint
--      flags, payload
--  clocks: 0 = TAS clock (TotalTime, never stored), 1 = simulation time without the pauses (whole 1/240 s
--      steps; physics parts, HappaTAS holds them while paused), 2 = wall clock (20 us units, the change is
--      stored minus the frame's FrameTime), 3 = simulation time with the pauses (steps; scripts that run on
--      game time keep going while paused). A frame carries the clocks its moving parts use (or used in the
--      frame before)
--  flags: 1 key (pos), 2 rotation, 4 linear velocity, 8 angular velocity, 16 transparency,
--         32 can-collide (64 = its value), 128 colour, 256 size, 512 material, 1024 dropped,
--         2048 + 4096 the key's clock (2048 = 1, 4096 = 2, both = 3, none = 0)
--  v3 keys move by a screw motion on their own clock, the velocity is the one at the part's position.
--  v2 data (frame byte 2 / 3: no clocks, straight-line model on the TAS clock) and v1 data (0 / 1) still
--  play the way they were recorded.
-- ================================================================================================
do
	local CO = ClientObjects
	local CFG = CONFIG.ClientObjects
	local floor, abs, sqrt = math.floor, math.abs, math.sqrt
	local byte, sub = string.byte, string.sub
	local putVar, putZig, bufToString = Codec.PutVar, Codec.PutZig, Codec.BufToString
	local V3, CF = Vector3.new, CFrame.new
	local ZV = Vector3.zero
	local hasMask, addMask = bit32.btest, bit32.bor -- flag tests (masks are small positive integers)

	local RADIUS         = CFG.Radius or 300
	local ALWAYS         = CFG.AlwaysRadius or 30
	local FULL_EVERY     = CFG.FullEvery or 2400
	local FULL_SECS      = CFG.FullSeconds or 10
	local VIS_EVERY      = CFG.VisEvery or 6
	local POS_TOL        = CFG.PosTolerance or 0.015
	local POS_TOL2       = POS_TOL * POS_TOL
	local ROT_TOL        = CFG.RotTolerance or 0.0015
	local MAX_AGE        = CFG.MaxModelAge or 1.0
	local MAX_REG        = CFG.MaxRegistered or 8000
	local MAX_WATCH      = CFG.MaxWatched or 30000
	local WATCH_ANCHORED = CFG.WatchAnchored ~= false
	local MAX_EXTRAP     = 2.0
	local CK, MAX_CK     = 120, 64
	local V_MIN, W_MIN   = 0.05, 0.005

	-- playback state layout (shared by v1 and v2):
	--   1-3 position (x1000)  4-12 rotation (x1000)  13 transparency  14 can-collide  15-17 colour
	--   18-20 size  21 material  23 mask  36-38 linear vel (x1000)  39-41 angular vel (x1000)
	--   42-44 v1 spin  45 keyframe time (on its clock)  46 v1 spin flag  47 clock (0 TAS, 1 simulation,
	--   2 wall)  48 "moves by velocity"  49 model (3 = screw motion, v3)  50 version (new number on every
	--   change, so a pose / property write can be skipped while the state is the same)
	local I_TR, I_CC, I_COL, I_SZ, I_MAT, I_MASK, I_VER = 13, 14, 15, 18, 21, 23, 50
	local F_CF, F_TR, F_CC, F_CCV, F_COL, F_SZ, F_MAT, F_ROT = 1, 2, 4, 8, 16, 32, 64, 128
	local F_VEL, F_SPIN, F_SKIP = 256, 512, 1024
	local K_KEY, K_ROT, K_LV, K_AV = 1, 2, 4, 8
	local K_TR, K_CC, K_CCV, K_COL, K_SZ, K_MAT, K_DROP = 16, 32, 64, 128, 256, 512, 1024
	local K_CK1, K_CK2 = 2048, 4096

	local Reg = { keyToId = {}, idToKey = {}, nextId = 1, used = {} }
	CO.Reg = Reg
	CO.dataVersion = 0
	CO.shown = {}

	local parts, ids, S = {}, {}, {}
	local partByKey = {}
	local plist, pidx = {}, {}
	local actArr, actPos = {}, {}
	local dropQ = {}
	local conParts = setmetatable({}, { __mode = "k" })
	local watchConns, nWatched = {}, 0
	local nRegistered = 0
	local enabled, scanDone, scanning = false, false, false
	local descConn, remConn
	local orig, origVel = {}, {}
	local frozen = false
	local frameNo, chainNo, forceFull = 0, 0, true
	local newChain = true -- the next full snapshot starts new clocks (marked with + 64)
	local recGen, visCursor = 0, 1
	local lastFullF, lastFullT = 0, -1e9 -- frame number / TotalTime of the last full snapshot
	-- start states of parts that change later (see starts.add; one table: the module is at Luau's 200 locals
	-- limit). log = the full snapshots recorded in this session, data = the TAS being recorded
	local starts = { log = {}, data = nil }

	local play = {
		cur = {}, dyn = {}, dropped = {}, active = false, kind = "test",
		data = nil, version = -1, frame = nil, sweep = 0,
		ck = {}, ckN = 0, ckData = nil, ckVer = -1,
		t = 0, curT = 0, nextT = 0, next = {}, nextFor = nil,
		-- v3 clocks: run = the stored values as of the current frame (like the recorder's), cv / nv = the
		-- clocks of the current / next frame in seconds, ckRun = run at each checkpoint
		run = { 0, 0, 0 }, cv = { 0, 0, 0 }, nv = { 0, 0, 0 }, ckRun = {},
		lost = {}, -- held parts a game script let go since the last pass (see fixLost)
	}
	CO.play = play

	local function status(text)
		if CO.OnStatus then task.spawn(CO.OnStatus, text) end
	end

	function CO.Counts()
		local n = 0
		for _ in pairs(play.cur) do n = n + 1 end
		return nRegistered, #actArr, n
	end

	-- --------------------------------------------------------------------------------------------- keys / ids
	local sibCache = setmetatable({}, { __mode = "k" })
	local function siblingIndex(inst)
		local parent = inst.Parent
		local map = sibCache[parent]
		if map and map[inst] then return map[inst] end
		-- (re)build: also when siblings were added after the map was made
		map = {}
		local counts = {}
		for _, ch in ipairs(parent:GetChildren()) do
			local n = ch.Name
			local k = (counts[n] or 0) + 1
			counts[n] = k
			map[ch] = k
		end
		sibCache[parent] = map
		return map[inst] or 1
	end

	-- workspace path with "#n" for siblings that share a name (stable between sessions)
	local function keyOf(part)
		local segs, n = {}, 0
		local inst = part
		while inst and inst ~= workspace do
			if not inst.Parent then return nil end
			local name = (inst.Name:gsub("[/#]", "_"))
			local idx = siblingIndex(inst)
			n = n + 1
			segs[n] = idx > 1 and (name .. "#" .. idx) or name
			inst = inst.Parent
		end
		if inst ~= workspace then return nil end
		local out = {}
		for i = n, 1, -1 do out[#out + 1] = segs[i] end
		return table.concat(out, "/")
	end
	CO.KeyOf = keyOf

	local function idForKey(key, preferred)
		local id = Reg.keyToId[key]
		if id then return id end
		id = preferred
		if not id or Reg.idToKey[id] then id = Reg.nextId end
		Reg.keyToId[key] = id
		Reg.idToKey[id] = key
		if id >= Reg.nextId then Reg.nextId = id + 1 end
		return id
	end

	-- --------------------------------------------------------------------------------------------- which parts
	local function insideCharacter(part)
		local inst = part.Parent
		while inst and inst ~= workspace do
			if inst:IsA("Model") and inst:FindFirstChildOfClass("Humanoid") then return true end
			inst = inst.Parent
		end
		return false
	end

	local KIT_FOLDERS = {
		ClientObjects = true, ClientParts = true, PClientParts = true,
		Client_Parts = true, Mechanics = true, MovingParts = true,
		Moving_Parts = true, ["Moving Platforms"] = true, MovingPlatforms = true,
		Pushers = true, Pusher = true, ["X Pushers"] = true, ["X Pusher"] = true, XPusher = true,
		["Z Pushers"] = true, ["Z Pusher"] = true, ["Y Pushers"] = true, ["Y Pusher"] = true,
		Spinners = true, Spinner = true, Spinning = true, SpinningParts = true,
		Conveyors = true, Conveyor = true, Obstacles = true, Traps = true, Hazards = true,
		KillBricks = true, KillParts = true, BeatBlocks = true, ["Beat Blocks"] = true,
		BeatBlock = true, ["Beat Block"] = true, BeatParts = true, ["Beat Parts"] = true, Beats = true,
		Buttons = true, ButtonPlatforms = true, ButtonDeactivator = true,
		Morpher = true, Morphers = true, Morph = true, Morphs = true,
		MorphButton = true, MorphButtons = true, ["Morph Button"] = true, ["Morph Buttons"] = true,
		MorphPart = true, MorphParts = true, ["Morph Part"] = true, ["Morph Parts"] = true,
		LightChanger = true, LightChangers = true, ["Light Changer"] = true, ["Light Changers"] = true,
		LightingChanger = true, LightingChangers = true, ["Lighting Changer"] = true, ["Lighting Changers"] = true,
		LightingReverter = true, ["Lighting Reverter"] = true, LightReverter = true, ["Light Reverter"] = true,
		Vanishers = true, Vanisher = true, ["VanisherGroup"] = true, Vanish = true,
		FadingParts = true, FadingPart = true, ["Fading Parts"] = true, ["Fading Part"] = true,
		FadingPlatforms = true, FadingPlatform = true, ["Fading Platforms"] = true, ["Fading Platform"] = true,
		Fading = true, Disappearing = true, DisappearingPlatforms = true, ["Disappearing Platforms"] = true,
		Client = true,
	}

	local function nameHint(n)
		return n:find("[Pp]usher") or n:find("[Ss]pinner") or n:find("[Cc]onveyor")
			or n:find("[Mm]oving") or n:find("[Bb]eat") or n:find("[Mm]orph")
			or n:find("[Ll]ight.*[Cc]hanger") or n:find("[Ll]ighting.*[Cc]hanger")
			or n:find("[Ll]ight.*[Rr]everter")
			or n:find("[Vv]anish") or n:find("[Ff]ad") or n:find("[Dd]isappear")
	end

	local function isCandidate(part)
		if not part or not part:IsA("BasePart") then return false end
		if part == workspace.Terrain or part:GetAttribute("HappaTASIgnore") then return false end
		if insideCharacter(part) then return false end
		if not part.Anchored then return true end
		if CFG.Groups and CFG.Groups[part.CollisionGroup] == true then return true end
		if conParts[part] then return true end
		if part:FindFirstChildWhichIsA("Constraint") or part:FindFirstChildWhichIsA("BodyMover") then return true end
		if part:GetAttribute("Beat") or part:GetAttribute("OnTransparency") or part:GetAttribute("OffTransparency")
			or part:FindFirstChild("OnTransparency") or part:FindFirstChild("OffTransparency")
			or part:FindFirstChild("Beat") then
			return true
		end
		if part:FindFirstChild("VanisherConfiguration")
			or (part.Parent and part.Parent:FindFirstChild("VanisherConfiguration"))
			or part:GetAttribute("VanishMode") or part:GetAttribute("FadeTime") or part:GetAttribute("RespawnTime")
			or part:FindFirstChild("VanisherSelectionBox") then
			return true
		end
		if nameHint(part.Name) then return true end
		local parent = part.Parent
		while parent and parent ~= workspace do
			local pn = parent.Name
			if KIT_FOLDERS[pn] or nameHint(pn) or pn:find("[Oo]bstacle") then return true end
			parent = parent.Parent
		end
		return false
	end

	local register

	-- anchored parts that may be unanchored later (falling platforms...)
	local function watch(part)
		if not WATCH_ANCHORED or watchConns[part] or nWatched >= MAX_WATCH then return end
		if not part.Anchored then return end
		local cn
		cn = part:GetPropertyChangedSignal("Anchored"):Connect(function()
			if not part.Anchored then
				if cn then cn:Disconnect() end
				if watchConns[part] then watchConns[part] = nil; nWatched = nWatched - 1 end
				if enabled and orig[part] == nil then register(part) end
			end
		end)
		watchConns[part] = cn
		nWatched = nWatched + 1
	end

	local function unwatch(part)
		local cn = watchConns[part]
		if cn then
			cn:Disconnect()
			watchConns[part] = nil
			nWatched = nWatched - 1
		end
	end

	local function noteConstraint(c)
		local ok, a0, a1 = pcall(function() return c.Attachment0, c.Attachment1 end)
		if not ok then return end
		for _, a in ipairs({ a0 or false, a1 or false }) do
			if a then
				local p = a.Parent
				if p and p:IsA("BasePart") then conParts[p] = true end
			end
		end
	end

	local function readProps(part, t)
		t[1] = floor(part.Transparency * 1000 + 0.5)
		t[2] = part.CanCollide and 1 or 0
		local col = part.Color
		t[3], t[4], t[5] = floor(col.R * 255 + 0.5), floor(col.G * 255 + 0.5), floor(col.B * 255 + 0.5)
		local sz = part.Size
		t[6], t[7], t[8] = floor(sz.X * 1000 + 0.5), floor(sz.Y * 1000 + 0.5), floor(sz.Z * 1000 + 0.5)
		t[9] = part.Material.Value
	end

	-- Change signals instead of reading every frame: the 5 recorded properties are re-read when one
	-- of them changed (pd = for the recorder, vd = for the visibility test), Anchored is kept in s.an
	local PROP_NAMES = { "Transparency", "CanCollide", "Color", "Size", "Material" }
	local function watchProps(part, s)
		local list = {}
		local function dirty() s.pd, s.vd = true, true end
		local function anchoredChanged()
			s.an = part.Anchored
			-- a game script let go of a part HappaTAS holds (the EToH kit's DistanceCulling sets the
			-- PrimaryPart's Anchored every 0.2 s): anchor it again and write its pose on the next pass
			-- (physics may have moved it meanwhile, found in the live client with the Tilting Platform)
			if not s.an and orig[part] ~= nil then
				s.lost = true
				play.lost[part] = true
			end
		end
		for _, n in ipairs(PROP_NAMES) do
			local ok, cn = pcall(function() return part:GetPropertyChangedSignal(n):Connect(dirty) end)
			if ok and cn then list[#list + 1] = cn end
		end
		local ok, cn = pcall(function() return part:GetPropertyChangedSignal("Anchored"):Connect(anchoredChanged) end)
		if ok and cn then list[#list + 1] = cn end
		s.cn = list
	end
	local function unwatchProps(s)
		if not s or not s.cn then return end
		for _, cn in ipairs(s.cn) do cn:Disconnect() end
		s.cn = nil
	end

	local function newRecState(part)
		local cp = {}
		readProps(part, cp)
		local rv = {}
		for i = 1, 9 do rv[i] = cp[i] end
		local cf0 = part.CFrame
		return {
			rc = { cf0:GetComponents() }, rcf = cf0, pd = false, vd = true, an = part.Anchored, rad = 0, tr = 0,
			propsOff = false,
			rv = rv, cp = cp,
			kp = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
			lq = { 0, 0, 0 }, aq = { 0, 0, 0 },
			pv = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
			dyn = false, kT = 0, clk = 3, moved = false, needBase = true, chain = -1, gen = 0,
			prevCF = nil, prevFrame = -10,
			-- scripted parts: clock fitness / speed per clock, the last poses with their clock readings
			fit = { 0, 0, 0, 0 }, esp = { 0, 0, 0, 0 }, hcf = {}, h1 = {}, h3 = {}, h4 = {}, hp = 0, hn = 0,
		}
	end

	-- removes id from a list kept with its positions (the last entry takes its place)
	local function listRemove(arr, pos, id)
		local i = pos[id]
		if not i then return end
		local last = arr[#arr]
		arr[i] = last
		pos[last] = i
		arr[#arr] = nil
		pos[id] = nil
	end

	local function setActive(id, active)
		local was = actPos[id] ~= nil
		if active == was then return end
		if active then
			actArr[#actArr + 1] = id
			actPos[id] = #actArr
		else
			listRemove(actArr, actPos, id)
			local s = S[id]
			if s and s.moved and not s.needBase then
				dropQ[id] = true
				s.needBase = true
			end
		end
	end

	function register(part)
		if ids[part] or nRegistered >= MAX_REG then return end
		if not isCandidate(part) then
			if part.Anchored and part ~= workspace.Terrain then watch(part) end
			return
		end
		local key = keyOf(part)
		if not key then return end
		local old = partByKey[key]
		if old and old ~= part and old.Parent then return end
		local id = idForKey(key)
		parts[id], ids[part], partByKey[key] = part, id, part
		plist[#plist + 1] = id
		pidx[id] = #plist
		local s = newRecState(part)
		s.regN = frameNo -- (frames recorded before it was registered)
		S[id] = s
		watchProps(part, s)
		nRegistered = nRegistered + 1
		unwatch(part)
	end

	local function unregister(part)
		unwatch(part)
		local id = ids[part]
		if not id then return end
		listRemove(actArr, actPos, id)
		listRemove(plist, pidx, id)
		unwatchProps(S[id])
		ids[part], parts[id], S[id], dropQ[id] = nil, nil, nil, nil
		orig[part], origVel[part] = nil, nil
		local key = Reg.idToKey[id]
		if key and partByKey[key] == part then partByKey[key] = nil end
		nRegistered = nRegistered - 1
	end

	local function startScan()
		if scanning or scanDone then return end
		scanning = true
		task.spawn(function()
			local list = workspace:GetDescendants()
			for i = 1, #list do
				if not enabled then scanning = false return end
				local inst = list[i]
				if inst:IsA("Constraint") then noteConstraint(inst) end
				if i % 1500 == 0 then task.wait() end
			end
			for i = 1, #list do
				if not enabled then scanning = false return end
				local inst = list[i]
				if inst:IsA("BasePart") then register(inst) end
				if i % 300 == 0 then task.wait() end
			end
			scanning = false
			if enabled then
				scanDone = true
				status("Client objects ready (" .. nRegistered .. " parts)")
			end
		end)
	end

	function CO.IsEnabled() return enabled end
	function CO.IsReady() return enabled and scanDone end
	-- every registered part that is still in the game (the speed hack's world uses it)
	function CO.EachPart(fn)
		for _, part in pairs(parts) do
			if part.Parent then fn(part) end
		end
	end

	function CO.Enable()
		if enabled then return end
		enabled = true
		forceFull = true
		descConn = workspace.DescendantAdded:Connect(function(inst)
			if inst:IsA("Constraint") then
				task.defer(function()
					noteConstraint(inst)
					local ok, a0, a1 = pcall(function() return inst.Attachment0, inst.Attachment1 end)
					if ok then
						for _, a in ipairs({ a0 or false, a1 or false }) do
							if a and a.Parent and a.Parent:IsA("BasePart") then register(a.Parent) end
						end
					end
				end)
			elseif inst:IsA("BasePart") then
				register(inst)
			end
		end)
		remConn = workspace.DescendantRemoving:Connect(function(inst)
			if inst:IsA("BasePart") then unregister(inst) end
		end)
		status("Scanning client objects...")
		startScan()
	end

	-- --------------------------------------------------------------------------------------------- releasing
	-- a part HappaTAS anchored goes back to how it was (Anchored + the velocity it had)
	local function restorePart(part, was)
		if not part.Parent then return end
		pcall(function()
			part.Anchored = was
			local ov = origVel[part]
			if ov then
				part.AssemblyLinearVelocity = ov[1]
				part.AssemblyAngularVelocity = ov[2]
			end
		end)
	end
	local function releasePart(id)
		local part = parts[id]
		if part then
			local s = S[id]
			if s and s.rcf and s.rv and play.active then
				pcall(function()
					part.CFrame = s.rcf
					part.Transparency = s.rv[1] / 1000
					part.CanCollide = s.rv[2] == 1
					part.Color = Color3.fromRGB(s.rv[3], s.rv[4], s.rv[5])
					part.Size = V3(s.rv[6] / 1000, s.rv[7] / 1000, s.rv[8] / 1000)
					local okM, mat = pcall(function() return Enum.Material:FromValue(s.rv[9]) end)
					if okM and mat then part.Material = mat end
				end)
			end
			if orig[part] ~= nil then restorePart(part, orig[part]) end
			orig[part], origVel[part] = nil, nil
		end
		CO.shown[id] = nil
	end

	function CO.Release()
		play.active = false
		for part, was in pairs(orig) do restorePart(part, was) end
		orig, origVel = {}, {}
		frozen = false
		CO.shown = {}
		play.lost = {}
		play.next, play.nextFor = {}, nil
	end

	function CO.Disable()
		if not enabled then return end
		enabled = false
		CO.Release()
		if descConn then descConn:Disconnect(); descConn = nil end
		if remConn then remConn:Disconnect(); remConn = nil end
		for _, cn in pairs(watchConns) do cn:Disconnect() end
		watchConns, nWatched = {}, 0
		for _, s in pairs(S) do unwatchProps(s) end
		parts, ids, S, partByKey = {}, {}, {}, {}
		plist, pidx, actArr, actPos, dropQ = {}, {}, {}, {}, {}
		nRegistered = 0
		scanDone, scanning = false, false
		play.cur, play.dyn, play.dropped, play.ck, play.ckN = {}, {}, {}, {}, 0
		play.data, play.frame = nil, nil
		starts.log, starts.data = {}, nil
	end

	-- --------------------------------------------------------------------------------------------- visibility
	local function isVisible(part, s, ppos, cam, camPos, vpX, vpY, tanHalf, strict)
		if s.vd then -- size / transparency changed (or never read)
			s.vd = false
			s.rad = part.Size.Magnitude * 0.5
			s.tr = part.Transparency
		end
		local pos = part.Position
		local dx, dy, dz = pos.X - ppos.X, pos.Y - ppos.Y, pos.Z - ppos.Z
		local d2 = dx * dx + dy * dy + dz * dz
		local rad = s.rad
		local maxR = RADIUS + rad
		if d2 > maxR * maxR then return false end
		if strict then
			-- Frustum Culling CO: close parts always, otherwise only visible parts on screen
			if d2 <= 625 then return true end
			if s.tr >= 1 and part.LocalTransparencyModifier >= 1 then return false end
			if not cam then return true end
			local sp, onScreen = cam:WorldToViewportPoint(pos)
			return onScreen and sp.Z > 0
		end
		local d = sqrt(d2)
		if d - rad <= ALWAYS then return true end
		if not cam then return true end
		if (pos - camPos).Magnitude <= rad * 1.2 + 6 then return true end
		local sp = cam:WorldToViewportPoint(pos)
		local z = sp.Z
		if z <= 0 then return false end
		local rpx = rad * vpY / (2 * tanHalf * z)
		local mx, my = vpX * 0.25 + rpx, vpY * 0.25 + rpx
		return sp.X >= -mx and sp.X <= vpX + mx and sp.Y >= -my and sp.Y <= vpY + my
	end

	local function updateVisibility(ppos, full)
		local n = #plist
		if n == 0 then return end
		local cam = workspace.CurrentCamera
		local camPos, vpX, vpY, tanHalf
		if cam then
			camPos = cam.CFrame.Position
			local vp = cam.ViewportSize
			vpX, vpY = vp.X, vp.Y
			tanHalf = math.tan(math.rad(cam.FieldOfView) * 0.5)
			if tanHalf < 0.01 then tanHalf = 0.01 end
		end
		local strict = Settings.On("Frustum Culling CO")
		local count = full and n or math.min(n, math.ceil(n / VIS_EVERY))
		for _ = 1, count do
			if visCursor > #plist then visCursor = 1 end
			local id = plist[visCursor]
			visCursor = visCursor + 1
			if id then
				local part, s = parts[id], S[id]
				if part and s and part.Parent then
					setActive(id, isVisible(part, s, ppos, cam, camPos, vpX, vpY, tanHalf, strict))
				else
					setActive(id, false)
				end
			end
		end
	end

	local function playerPosNow()
		local char = LocalPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		return root and root.Position or ZV
	end

	-- --------------------------------------------------------------------------------------------- pose model
	-- v2 records (older files): the keyframe pose moved on by its velocity for dt seconds, in a straight line
	-- (one CFrame when it doesn't turn)
	local function buildPose(x, y, z, r1, r2, r3, r4, r5, r6, r7, r8, r9, lx, ly, lz, wx, wy, wz, dt)
		if dt and dt > 0 then
			if dt > MAX_EXTRAP then dt = MAX_EXTRAP end
			local px, py, pz = x + lx * dt, y + ly * dt, z + lz * dt
			local mag = sqrt(wx * wx + wy * wy + wz * wz)
			if mag > 1e-5 then
				local rot = CF(0, 0, 0, r1, r2, r3, r4, r5, r6, r7, r8, r9)
				return CFrame.fromAxisAngle(V3(wx / mag, wy / mag, wz / mag), mag * dt) * rot + V3(px, py, pz)
			end
			return CF(px, py, pz, r1, r2, r3, r4, r5, r6, r7, r8, r9)
		end
		return CF(x, y, z, r1, r2, r3, r4, r5, r6, r7, r8, r9)
	end

	-- v3 records: the keyframe pose moved on by a constant twist (a screw motion). l = the velocity at the
	-- part's position, w = the angular velocity (world space). The part turns by w around the axis through
	-- the point where its velocity is only along w, so a part going round a spinner's centre stays on its
	-- circle (a straight line leaves it within a frame or two), a part spinning in place stays in place and
	-- a slider (w = 0) moves in a straight line
	local function buildPose3(x, y, z, r1, r2, r3, r4, r5, r6, r7, r8, r9, lx, ly, lz, wx, wy, wz, dt)
		if dt and dt > 0 then
			if dt > MAX_EXTRAP then dt = MAX_EXTRAP end
			local w2 = wx * wx + wy * wy + wz * wz
			if w2 > 1e-10 then
				local mag = sqrt(w2)
				local turn = CFrame.fromAxisAngle(V3(wx / mag, wy / mag, wz / mag), mag * dt)
				-- the part's offset from the screw axis: (l x w) / |w|^2; its speed along the axis: (l . w) / |w|^2
				local ox, oy, oz = (ly * wz - lz * wy) / w2, (lz * wx - lx * wz) / w2, (lx * wy - ly * wx) / w2
				local along = (lx * wx + ly * wy + lz * wz) / w2 * dt
				local q = turn * V3(ox, oy, oz)
				return turn * CF(0, 0, 0, r1, r2, r3, r4, r5, r6, r7, r8, r9)
					+ V3(x - ox + q.X + wx * along, y - oy + q.Y + wy * along, z - oz + q.Z + wz * along)
			end
			return CF(x + lx * dt, y + ly * dt, z + lz * dt, r1, r2, r3, r4, r5, r6, r7, r8, r9)
		end
		return CF(x, y, z, r1, r2, r3, r4, r5, r6, r7, r8, r9)
	end

	-- playback time t (TAS clock) on clock c of a v3 keyframe (0 = TAS clock, 1-3 see the header comment):
	-- the clock's values in the current and the next frame (play.cv / play.nv), blended like the time itself
	local function objTime(c, t)
		if c == 0 then return t end
		local v0, v1 = play.cv[c], play.nv[c]
		local span = play.nextT - play.curT
		local a = 0
		if span > 1e-6 then
			a = (t - play.curT) / span
			if a < 0 then a = 0 elseif a > 1 then a = 1 end
		end
		return v0 + (v1 - v0) * a
	end

	local function poseAt(s, t)
		local dt = nil
		if t and s[48] == 1 then dt = objTime(s[47], t) - s[45] end
		local build = buildPose
		if s[49] == 3 then build = buildPose3 end
		return build(
			s[1] / 1000, s[2] / 1000, s[3] / 1000,
			s[4] / 1000, s[5] / 1000, s[6] / 1000, s[7] / 1000, s[8] / 1000, s[9] / 1000, s[10] / 1000, s[11] / 1000, s[12] / 1000,
			s[36] / 1000, s[37] / 1000, s[38] / 1000, s[39] / 1000, s[40] / 1000, s[41] / 1000, dt)
	end

	-- the constant twist that turns pose c0 into pose c1 in dt seconds: the velocity at c1's position and the
	-- angular velocity (screw motion: turning around an axis while moving along it)
	local function twistFrom(c0, c1, dt)
		if not dt or dt <= 1e-5 then return ZV, ZV end
		local d = c1 * c0:Inverse()
		local tr = d.Position
		local axis, ang = d:ToAxisAngle()
		if ang == ang and ang > 1e-6 and axis.X == axis.X and axis.Magnitude > 0.5 then
			local n = axis.Unit
			local w = n * (ang / dt)
			local tpar = n * tr:Dot(n)
			local tperp = tr - tpar
			-- a point on the screw axis: (t + cot(ang / 2) n x t) / 2 (t = the move across the axis)
			local ctr = (tperp + n:Cross(tperp) / math.tan(ang * 0.5)) * 0.5
			return tpar / dt + w:Cross(c1.Position - ctr), w
		end
		return tr / dt, ZV
	end

	-- --------------------------------------------------------------------------------------------- recorder
	local A, P, K = {}, {}, {}
	-- the clocks of the frame being recorded, in seconds, exactly as playback rebuilds them: CLK[c + 1] for
	-- clock c (see the header comment). DCLK = their change since the frame before (haveD: that frame was
	-- recorded too). base = the raw readings taken off (skip moves on by every pause, rawS = the simulation
	-- time of the last recorded frame)
	local CLK, DCLK, lastCLK, haveD = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, false
	local base = { skip = 0, real = 0, wall = 0, rawS = nil }
	local run = { 0, 0, 0 } -- clocks 1-3 as last stored (since the last full snapshot), like the decoder keeps them
	local usedPrev = { false, false, false }
	local lastRec, lastRecVer = nil, -1 -- the frame table recorded last, and the data version then
	local CLOCK_FLAG = { 0, K_CK1, K_CK2, K_CK1 + K_CK2 }
	local H_N = 4 -- poses kept per moving scripted part (its twist is measured over them)
	local SIM_HZ, WALL_HZ = 240, 50000
	local CARRY_BIT = { 8, 16, 32 }

	-- A part is skipped while it is still on the pose and properties it had when it was registered. When it
	-- changes for the first time, the frames before had nothing for it, and playback left it wherever it was
	-- (the EToH kit's Morph stayed pressed when the script was run again or the TAS was loaded later). Its
	-- start state now goes into the full snapshots recorded before in this session since it was registered
	-- (starts.log: their frame tables), and the change is recorded as a change from it. Only for a part that was
	-- seen on its start state while recording (s.atStart): one that changed before the recording isn't on it.
	-- the record of a part's start state, as a full snapshot holds it (whole values: from nothing)
	function starts.record(id, s)
		local out, rc, rvv = {}, s.rc, s.rv
		putVar(out, id)
		putVar(out, K_KEY + K_ROT + K_TR + K_CC + (rvv[2] == 1 and K_CCV or 0) + K_COL + K_SZ + K_MAT)
		for i = 1, 12 do putZig(out, floor(rc[i] * 1000 + 0.5)) end
		putZig(out, rvv[1])
		out[#out + 1] = rvv[3] % 256; out[#out + 1] = rvv[4] % 256; out[#out + 1] = rvv[5] % 256
		for i = 6, 8 do putZig(out, rvv[i]) end
		putVar(out, rvv[9])
		return bufToString(out)
	end
	function starts.add(id, s)
		local log, data = starts.log, starts.data
		local rec, inChain = nil, false
		for i = #log, 1, -1 do
			local e = log[i]
			local fr = e.fr
			if e.data ~= data or data[e.i] ~= fr or type(fr.CO) ~= "string" then
				table.remove(log, i) -- (cut frames, an optimized TAS or another TAS)
			elseif e.n > s.regN and e.n ~= frameNo then
				rec = rec or starts.record(id, s)
				fr.CO = fr.CO .. rec
				if e.n == lastFullF then inChain = true end
			end
		end
		if not rec then return end
		Reg.used[id] = true
		-- (playback's checkpoints were made from these frames)
		play.ck, play.ckN, play.ckRun, play.ckData = {}, 0, {}, nil
		play.data, play.nextFor, play.hasData = nil, nil, nil
		if inChain then
			-- this chain starts with the start state now: the part's records go on from it
			local kp, pv, rc, rvv = s.kp, s.pv, s.rc, s.rv
			for i = 1, 12 do kp[i] = floor(rc[i] * 1000 + 0.5) end
			for i = 1, 9 do pv[i] = rvv[i] end
			s.lq[1], s.lq[2], s.lq[3], s.aq[1], s.aq[2], s.aq[3] = 0, 0, 0, 0, 0, 0
			s.dyn, s.chain, s.needBase = false, chainNo, false
		end
	end

	local function ringPush(s, cf, c1, c3, c4)
		local i = s.hp % H_N + 1
		s.hp = i
		s.hcf[i], s.h1[i], s.h3[i], s.h4[i] = cf, c1, c3, c4
		if s.hn < H_N then s.hn = s.hn + 1 end
	end

	-- scripted (anchored) parts: their last poses with the clock readings, and how steady each clock makes
	-- the part's motion (the speed measured on the clock its script uses barely changes, on the others it
	-- jumps with every frame's timing)
	local function trackScripted(s, cf)
		local prev = s.prevCF
		if not (prev and haveD and s.prevFrame == frameNo - 1) then
			s.hn = 0
			ringPush(s, cf, CLK[1], CLK[3], CLK[4])
			return
		end
		local m = 0
		if cf ~= prev then
			local d = cf * prev:Inverse()
			local _, ang = d:ToAxisAngle()
			if ang == ang and ang > 1e-6 then
				local r = s.rad
				if r < 1 then r = 1 end
				m = ang * r
			end
			m = m + d.Position.Magnitude
		end
		-- (scripted parts: TAS clock, wall clock or game time; game time with or without the pauses changes the
		-- same from frame to frame, the one with them is used)
		local fit, esp = s.fit, s.esp
		for c = 1, 4 do
			local dt = DCLK[c]
			if dt > 1e-6 and dt < 0.25 then
				local sp = m / dt
				local e = esp[c]
				if e > 0 then
					local dev = (sp - e) / e
					if dev > 1 then dev = 1 elseif dev < -1 then dev = -1 end
					fit[c] = fit[c] * 0.9 + dev * dev * 0.1
					esp[c] = e * 0.7 + sp * 0.3
				elseif sp > 0 then
					esp[c] = sp
				end
			elseif m > 0 and dt <= 1e-6 then
				fit[c] = fit[c] * 0.9 + 0.1 -- it moved while this clock stood still: not its clock
			end
		end
		if s.hn == 0 then ringPush(s, prev, lastCLK[1], lastCLK[3], lastCLK[4]) end
		ringPush(s, cf, CLK[1], CLK[3], CLK[4])
	end

	-- the clock with the steadiest motion (another one has to be clearly better to take over)
	local SCRIPT_CLOCKS = { 1, 3, 4 }
	local function bestClock(s)
		local fit, cur = s.fit, s.clk
		if cur == 2 then cur = 3 end
		local best = cur
		for _, c in ipairs(SCRIPT_CLOCKS) do
			if fit[c] < fit[best] then best = c end
		end
		if best ~= cur and fit[best] < fit[cur] * 0.7 then return best end
		return cur
	end

	-- a scripted part's twist over the poses it was seen in (the oldest kept one to now) on clock c
	local function scriptedTwist(s, cf, c)
		local n = s.hn
		if n < 2 then return ZV, ZV end
		local j = (s.hp - n) % H_N + 1
		local hc = s.h3
		if c == 1 then hc = s.h1 elseif c == 4 then hc = s.h4 end
		return twistFrom(s.hcf[j], cf, CLK[c] - hc[j])
	end

	local function recordObject(out, id, part, s)
		if s.gen ~= recGen then
			s.gen = recGen
			s.prevCF, s.hn = nil, 0
		end

		local cf = part.CFrame
		local cp = s.cp
		-- the properties are read on the same frames as always (every 2nd), but only when one of them
		-- changed since the last read (or every 16th frame, in case a change was not reported)
		if s.pd then
			s.pd = false
			readProps(part, cp)
			local rvv, off = s.rv, false
			for i = 1, 9 do
				if cp[i] ~= rvv[i] then off = true break end
			end
			s.propsOff = off
		end

		-- most parts never move: still exactly on the start CFrame with the properties they started with,
		-- so only the bookkeeping is kept (no maths, no velocity reads)
		local anchored = s.an
		if not s.moved and not s.propsOff and cf == s.rcf then
			s.prevCF, s.prevFrame, s.hn = cf, frameNo, 0
			s.atStart = true
			return
		end
		if anchored then trackScripted(s, cf) end
		s.prevCF, s.prevFrame = cf, frameNo

		local filled = false
		if not s.moved then
			local dev = false
			if cf ~= s.rcf then -- the exact start CFrame can't be outside the tolerance
				A[1], A[2], A[3], A[4], A[5], A[6], A[7], A[8], A[9], A[10], A[11], A[12] = cf:GetComponents()
				filled = true
				local rcv = s.rc
				local dx, dy, dz = A[1] - rcv[1], A[2] - rcv[2], A[3] - rcv[3]
				dev = dx * dx + dy * dy + dz * dz > POS_TOL2
				if not dev then
					for i = 4, 12 do
						if abs(A[i] - rcv[i]) > ROT_TOL then dev = true break end
					end
				end
			end
			if not dev then
				local rvv = s.rv
				for i = 1, 9 do
					if cp[i] ~= rvv[i] then dev = true break end
				end
			end
			if not dev then
				s.atStart = true
				return
			end
			s.moved = true
			if s.atStart and starts.data then starts.add(id, s) end
		end
		if not filled then
			A[1], A[2], A[3], A[4], A[5], A[6], A[7], A[8], A[9], A[10], A[11], A[12] = cf:GetComponents()
		end
		local x, y, z = A[1], A[2], A[3]

		local first = s.needBase or s.chain ~= chainNo
		local kp, lq, aq, pv = s.kp, s.lq, s.aq, s.pv
		if first then
			for i = 1, 12 do kp[i] = 0 end
			lq[1], lq[2], lq[3], aq[1], aq[2], aq[3] = 0, 0, 0, 0, 0, 0
			for i = 1, 9 do pv[i] = 0 end
			s.dyn = false
		end

		-- does the model still explain the part? (the same maths and clock as playback)
		local needKey = first
		if not first then
			if s.dyn then
				local age = CLK[s.clk] - s.kT
				if age > MAX_AGE then
					needKey = true
				else
					local pc = buildPose3(
						kp[1] / 1000, kp[2] / 1000, kp[3] / 1000,
						kp[4] / 1000, kp[5] / 1000, kp[6] / 1000, kp[7] / 1000, kp[8] / 1000, kp[9] / 1000, kp[10] / 1000, kp[11] / 1000, kp[12] / 1000,
						lq[1] / 1000, lq[2] / 1000, lq[3] / 1000, aq[1] / 1000, aq[2] / 1000, aq[3] / 1000, age)
					P[1], P[2], P[3], P[4], P[5], P[6], P[7], P[8], P[9], P[10], P[11], P[12] = pc:GetComponents()
				end
			else
				for i = 1, 12 do P[i] = kp[i] / 1000 end
			end
			if not needKey then
				local dx, dy, dz = x - P[1], y - P[2], z - P[3]
				if dx * dx + dy * dy + dz * dz > POS_TOL2 then
					needKey = true
				else
					for i = 4, 12 do
						if abs(A[i] - P[i]) > ROT_TOL then needKey = true break end
					end
				end
			end
		end

		local trD  = first or cp[1] ~= pv[1]
		local ccD  = first or cp[2] ~= pv[2]
		local colD = first or cp[3] ~= pv[3] or cp[4] ~= pv[4] or cp[5] ~= pv[5]
		local szD  = first or cp[6] ~= pv[6] or cp[7] ~= pv[7] or cp[8] ~= pv[8]
		local matD = first or cp[9] ~= pv[9]
		if not (needKey or trD or ccD or colD or szD or matD) then return end

		local flags = 0
		local rotChanged = false
		local l1, l2, l3, a1, a2, a3 = 0, 0, 0, 0, 0, 0
		local clk = s.clk
		if needKey then
			for i = 1, 12 do K[i] = floor(A[i] * 1000 + 0.5) end
			rotChanged = first
			if not first then
				for i = 4, 12 do
					if K[i] ~= kp[i] then rotChanged = true break end
				end
			end
			-- physics parts move on the simulation clock (without the pauses: HappaTAS holds them) and report
			-- their velocity: the one at the part's position (an assembly's own velocity is its centre of
			-- mass's). Scripted parts: measured over the last frames on the clock their motion follows
			local L, W
			if anchored then
				clk = bestClock(s)
				L, W = scriptedTwist(s, cf, clk)
			else
				clk = 2
				W = part.AssemblyAngularVelocity
				L = part:GetVelocityAtPosition(cf.Position)
			end
			local lm, wm = L.Magnitude, W.Magnitude
			if lm >= V_MIN and lm < 5000 then
				l1, l2, l3 = floor(L.X * 1000 + 0.5), floor(L.Y * 1000 + 0.5), floor(L.Z * 1000 + 0.5)
			end
			if wm >= W_MIN and wm < 500 then
				a1, a2, a3 = floor(W.X * 1000 + 0.5), floor(W.Y * 1000 + 0.5), floor(W.Z * 1000 + 0.5)
			end
			flags = K_KEY
			if rotChanged then flags = flags + K_ROT end
			if l1 ~= 0 or l2 ~= 0 or l3 ~= 0 then flags = flags + K_LV end
			if a1 ~= 0 or a2 ~= 0 or a3 ~= 0 then flags = flags + K_AV end
			-- (the clock only matters for a part that moves on its own)
			if flags >= K_LV then flags = flags + CLOCK_FLAG[clk] end
		end
		if trD then flags = flags + K_TR end
		if ccD then flags = flags + K_CC + (cp[2] == 1 and K_CCV or 0) end
		if colD then flags = flags + K_COL end
		if szD then flags = flags + K_SZ end
		if matD then flags = flags + K_MAT end

		putVar(out, id)
		putVar(out, flags)
		if needKey then
			for i = 1, 3 do putZig(out, K[i] - kp[i]); kp[i] = K[i] end
			if rotChanged then
				for i = 4, 12 do putZig(out, K[i] - kp[i]); kp[i] = K[i] end
			end
			if l1 ~= 0 or l2 ~= 0 or l3 ~= 0 then putZig(out, l1); putZig(out, l2); putZig(out, l3) end
			if a1 ~= 0 or a2 ~= 0 or a3 ~= 0 then putZig(out, a1); putZig(out, a2); putZig(out, a3) end
			lq[1], lq[2], lq[3], aq[1], aq[2], aq[3] = l1, l2, l3, a1, a2, a3
			s.dyn = (l1 ~= 0 or l2 ~= 0 or l3 ~= 0 or a1 ~= 0 or a2 ~= 0 or a3 ~= 0)
			s.clk = clk
			s.kT = CLK[clk]
		end
		if trD then putZig(out, cp[1] - pv[1]); pv[1] = cp[1] end
		if ccD then pv[2] = cp[2] end
		if colD then
			out[#out + 1] = cp[3] % 256; out[#out + 1] = cp[4] % 256; out[#out + 1] = cp[5] % 256
			pv[3], pv[4], pv[5] = cp[3], cp[4], cp[5]
		end
		if szD then
			for i = 6, 8 do putZig(out, cp[i] - pv[i]); pv[i] = cp[i] end
		end
		if matD then putVar(out, cp[9]); pv[9] = cp[9] end

		s.needBase = false
		s.chain = chainNo
		Reg.used[id] = true
	end

	-- lastFrame = the TAS's last frame when recording starts (after cut frames were removed).
	-- Unpausing (1 frame or not) right where the recorder stopped keeps every chain going: the parts were
	-- put back on their recorded poses with their recorded velocities, and the clocks skip the pause. After
	-- cut frames, a loaded or edited TAS or the first recording, every part starts again (full snapshot)
	function CO.BeginRecording(lastFrame)
		recGen = recGen + 1
		dropQ = {}
		haveD = false
		local cont = lastFrame ~= nil and lastFrame == lastRec and lastRecVer == CO.dataVersion and base.rawS ~= nil
		local rawS, rawW = time(), os.clock()
		if cont then
			-- physics parts were held while paused: their clock skips the pause; scripts ran on: the other
			-- clocks don't
			base.skip = base.skip + (rawS - base.rawS)
		else
			forceFull = true
			newChain = true
			base.skip, base.real, base.wall = rawS, rawS, rawW
		end
		if enabled and scanDone then updateVisibility(playerPosNow(), true) end
	end

	-- a physics step the speed hack's Frame Step held everything for: like a pause, physics parts didn't move
	function CO.SkipSim(dt)
		base.skip = base.skip + (tonumber(dt) or 0)
	end

	-- tNow = TotalTime of the frame being recorded (TAS clock); simNow / wallNow = time() and os.clock()
	-- when that frame started (its render step); frame = the frame table the result goes into
	function CO.Record(playerPos, tNow, simNow, wallNow, frame, data)
		if not (enabled and scanDone) then return nil end
		frameNo = frameNo + 1
		starts.data = data
		tNow = tNow or 0
		simNow, wallNow = simNow or tNow, wallNow or tNow
		local val = {
			floor((simNow - base.skip) * SIM_HZ + 0.5),
			floor((wallNow - base.wall) * WALL_HZ + 0.5),
			floor((simNow - base.real) * SIM_HZ + 0.5),
		}
		CLK[1], CLK[2], CLK[3], CLK[4] = tNow, val[1] / SIM_HZ, val[2] / WALL_HZ, val[3] / SIM_HZ
		for c = 1, 4 do DCLK[c] = CLK[c] - lastCLK[c] end

		-- a full snapshot every FULL_SECS of TAS time (and at most every FULL_EVERY frames: playback
		-- looks 3000 frames back for one when it seeks)
		local full = forceFull or frameNo - lastFullF >= FULL_EVERY or tNow - lastFullT >= FULL_SECS or tNow < lastFullT
		forceFull = false
		if full then
			chainNo = chainNo + 1
			lastFullF, lastFullT = frameNo, tNow
			if frame and data and data[#data] == frame then
				local log = starts.log
				if log[1] and log[1].data ~= data then log = {}; starts.log = log end
				log[#log + 1] = { fr = frame, i = #data, n = frameNo, data = data }
			end
		end

		updateVisibility(playerPos, false)

		local body = {}
		for id in pairs(dropQ) do
			putVar(body, id)
			putVar(body, K_DROP)
		end
		dropQ = {}

		local anyDyn = false
		local usedNow = { false, false, false }
		for i = 1, #actArr do
			local id = actArr[i]
			local part, s = parts[id], S[id]
			-- (removed parts are unregistered by DescendantRemoving; the visibility pass checks Parent too)
			if part and s then
				recordObject(body, id, part, s)
				if s.dyn and s.moved then
					anyDyn = true
					if s.clk > 1 then usedNow[s.clk - 1] = true end
				end
			end
		end

		lastCLK[1], lastCLK[2], lastCLK[3], lastCLK[4] = CLK[1], CLK[2], CLK[3], CLK[4]
		haveD = true
		base.rawS = simNow
		lastRec, lastRecVer = frame, CO.dataVersion
		-- a frame with only its header (the clocks) keeps frames alive while something moves by velocity
		-- (Optimize TAS keeps them, playback needs their clocks)
		if #body == 0 and not full and not anyDyn then
			usedPrev = usedNow
			return nil
		end
		-- the clocks moving parts use now or used in the frame before (playback blends from that frame)
		local b = full and 5 or 4
		if full then
			run[1], run[2], run[3] = 0, 0, 0
			if newChain then b = b + 64 end
			newChain = false
		end
		local carry = {}
		for i = 1, 3 do
			carry[i] = usedNow[i] or usedPrev[i]
			if carry[i] then b = b + CARRY_BIT[i] end
		end
		local out = { b }
		for i = 1, 3 do
			if carry[i] then
				local pred = 0
				if i == 2 and not full then pred = floor(((frame and frame.FrameTime) or 0) * WALL_HZ + 0.5) end
				putZig(out, val[i] - run[i] - pred)
				run[i] = val[i]
			end
		end
		table.move(body, 1, #body, #out + 1, out)
		usedPrev = usedNow
		return bufToString(out)
	end

	-- --------------------------------------------------------------------------------------------- decoder
	local function rv(str, p)
		local result, mul = 0, 1
		while true do
			local b = byte(str, p)
			if not b then error("client object record is cut off", 0) end
			p = p + 1
			if b < 128 then return result + b * mul, p end
			result = result + (b - 128) * mul
			mul = mul * 128
			if mul > 2 ^ 49 then error("bad client object number", 0) end
		end
	end
	local function rz(str, p)
		local z
		z, p = rv(str, p)
		if z % 2 == 0 then return floor(z / 2), p end
		return -floor((z + 1) / 2), p
	end
	local function skipVars(str, p, count)
		for _ = 1, count do
			local b = byte(str, p)
			while b and b >= 128 do p = p + 1; b = byte(str, p) end
			if not b then error("client object record is cut off", 0) end
			p = p + 1
		end
		return p
	end
	-- the clocks a v3 frame carries, onto rn (the running values, updated in place); ft = the frame's FrameTime.
	-- Returns where the records start
	local function readClocks(str, rn, ft)
		local b = byte(str, 1)
		local full = b % 8 == 5
		if full then rn[1], rn[2], rn[3] = 0, 0, 0 end
		local fl, p = floor(b / 8), 2
		for i = 1, 3 do
			if fl % 2 == 1 then
				local d
				d, p = rz(str, p)
				if i == 2 and not full then d = d + floor((ft or 0) * WALL_HZ + 0.5) end
				rn[i] = rn[i] + d
			end
			fl = floor(fl / 2)
		end
		return p
	end
	local function bodyStart(str)
		if byte(str, 1) >= 4 then return readClocks(str, { 0, 0, 0 }, 0) end
		return 2
	end
	local function clockValues(rn, out)
		out[1], out[2], out[3] = rn[1] / SIM_HZ, rn[2] / WALL_HZ, rn[3] / SIM_HZ
		return out
	end

	local verN = 0
	local function newState() return table.create(50, 0) end
	local function copyState(s) return table.clone(s) end

	local function skipPayload(isV2, flags, str, p)
		if isV2 then
			if hasMask(flags, K_DROP) then return p end
			if hasMask(flags, K_KEY) then
				p = skipVars(str, p, 3)
				if hasMask(flags, K_ROT) then p = skipVars(str, p, 9) end
				if hasMask(flags, K_LV) then p = skipVars(str, p, 3) end
				if hasMask(flags, K_AV) then p = skipVars(str, p, 3) end
			end
			if hasMask(flags, K_TR) then p = skipVars(str, p, 1) end
			if hasMask(flags, K_COL) then p = p + 3 end
			if hasMask(flags, K_SZ) then p = skipVars(str, p, 3) end
			if hasMask(flags, K_MAT) then p = skipVars(str, p, 1) end
		else
			if hasMask(flags, F_CF) then p = skipVars(str, p, 3) end
			if hasMask(flags, F_ROT) then p = skipVars(str, p, 9) end
			if hasMask(flags, F_TR) then p = skipVars(str, p, 1) end
			if hasMask(flags, F_COL) then p = p + 3 end
			if hasMask(flags, F_SZ) then p = skipVars(str, p, 3) end
			if hasMask(flags, F_MAT) then p = skipVars(str, p, 1) end
			if hasMask(flags, F_VEL) then p = skipVars(str, p, 6) end
			if hasMask(flags, F_SPIN) then p = skipVars(str, p, 3) end
		end
		return p
	end

	-- old format (v1)
	local function applyV1(str, cur, touched)
		local p, n = 2, #str
		while p <= n do
			local id, flags
			id, p = rv(str, p)
			flags, p = rv(str, p)
			local s = cur[id]
			if not s then s = newState(); cur[id] = s end
			verN = verN + 1
			s[I_VER] = verN
			s[48] = 0
			if hasMask(flags, F_SKIP) then
				if s[46] == 1 then
					local sx, sy, sz = s[42] / 60000, s[43] / 60000, s[44] / 60000
					local cf = CF(s[1] / 1000, s[2] / 1000, s[3] / 1000, s[4] / 1000, s[5] / 1000, s[6] / 1000, s[7] / 1000, s[8] / 1000, s[9] / 1000, s[10] / 1000, s[11] / 1000, s[12] / 1000)
					cf = cf * CFrame.fromEulerAnglesYXZ(sx, sy, sz)
					local x, y, z, r1, r2, r3, r4, r5, r6, r7, r8, r9 = cf:GetComponents()
					s[1], s[2], s[3] = floor(x * 1000 + 0.5), floor(y * 1000 + 0.5), floor(z * 1000 + 0.5)
					s[4], s[5], s[6] = floor(r1 * 1000 + 0.5), floor(r2 * 1000 + 0.5), floor(r3 * 1000 + 0.5)
					s[7], s[8], s[9] = floor(r4 * 1000 + 0.5), floor(r5 * 1000 + 0.5), floor(r6 * 1000 + 0.5)
					s[10], s[11], s[12] = floor(r7 * 1000 + 0.5), floor(r8 * 1000 + 0.5), floor(r9 * 1000 + 0.5)
				end
				touched[id] = true
			else
				local mask = s[I_MASK]
				if hasMask(flags, F_CF) then
					for i = 1, 3 do local d; d, p = rz(str, p); s[i] = s[i] + d end
					mask = addMask(mask, F_CF)
				end
				if hasMask(flags, F_ROT) then
					for i = 4, 12 do local d; d, p = rz(str, p); s[i] = s[i] + d end
					mask = addMask(mask, F_ROT)
				end
				if hasMask(flags, F_TR) then
					local d; d, p = rz(str, p); s[I_TR] = s[I_TR] + d
					mask = addMask(mask, F_TR)
				end
				if hasMask(flags, F_CC) then
					s[I_CC] = hasMask(flags, F_CCV) and 1 or 0
					mask = addMask(mask, F_CC)
				end
				if hasMask(flags, F_COL) then
					local b1, b2, b3 = byte(str, p, p + 2)
					if not b3 then error("client object record is cut off", 0) end
					s[I_COL], s[I_COL + 1], s[I_COL + 2] = b1, b2, b3
					p = p + 3
					mask = addMask(mask, F_COL)
				end
				if hasMask(flags, F_SZ) then
					for i = 0, 2 do local d; d, p = rz(str, p); s[I_SZ + i] = s[I_SZ + i] + d end
					mask = addMask(mask, F_SZ)
				end
				if hasMask(flags, F_MAT) then
					s[I_MAT], p = rv(str, p)
					mask = addMask(mask, F_MAT)
				end
				if hasMask(flags, F_VEL) then
					for i = 36, 41 do local d; d, p = rz(str, p); s[i] = (s[i] or 0) + d end
				end
				if hasMask(flags, F_SPIN) then
					s[42], p = rz(str, p)
					s[43], p = rz(str, p)
					s[44], p = rz(str, p)
					s[46] = 1
				end
				s[I_MASK] = mask
				touched[id] = true
			end
		end
	end

	-- one v2 / v3 record payload onto a state table (cvs = the frame's clocks in seconds, v3 only)
	local function applyPayloadV2(str, p, s, flags, tNow, cvs)
		verN = verN + 1
		s[I_VER] = verN
		local mask = s[I_MASK]
		if hasMask(flags, K_KEY) then
			for i = 1, 3 do local d; d, p = rz(str, p); s[i] = s[i] + d end
			mask = addMask(mask, F_CF)
			if hasMask(flags, K_ROT) then
				for i = 4, 12 do local d; d, p = rz(str, p); s[i] = s[i] + d end
				mask = addMask(mask, F_ROT)
			end
			local moving = false
			if hasMask(flags, K_LV) then
				for i = 36, 38 do s[i], p = rz(str, p) end
				moving = true
			else
				s[36], s[37], s[38] = 0, 0, 0
			end
			if hasMask(flags, K_AV) then
				for i = 39, 41 do s[i], p = rz(str, p) end
				moving = true
			else
				s[39], s[40], s[41] = 0, 0, 0
			end
			if cvs then
				local c = (hasMask(flags, K_CK1) and 1 or 0) + (hasMask(flags, K_CK2) and 2 or 0)
				s[47], s[49] = c, 3
				s[45] = (c == 0) and tNow or cvs[c]
			else
				s[47], s[49] = 0, 0
				s[45] = tNow
			end
			s[48] = moving and 1 or 0
		end
		if hasMask(flags, K_TR) then
			local d; d, p = rz(str, p); s[I_TR] = s[I_TR] + d
			mask = addMask(mask, F_TR)
		end
		if hasMask(flags, K_CC) then
			s[I_CC] = hasMask(flags, K_CCV) and 1 or 0
			mask = addMask(mask, F_CC)
		end
		if hasMask(flags, K_COL) then
			local b1, b2, b3 = byte(str, p, p + 2)
			if not b3 then error("client object record is cut off", 0) end
			s[I_COL], s[I_COL + 1], s[I_COL + 2] = b1, b2, b3
			p = p + 3
			mask = addMask(mask, F_COL)
		end
		if hasMask(flags, K_SZ) then
			for i = 0, 2 do local d; d, p = rz(str, p); s[I_SZ + i] = s[I_SZ + i] + d end
			mask = addMask(mask, F_SZ)
		end
		if hasMask(flags, K_MAT) then
			s[I_MAT], p = rv(str, p)
			mask = addMask(mask, F_MAT)
		end
		s[I_MASK] = mask
		return p
	end

	local cvScratch = { 0, 0, 0 }
	local function applyV2(str, cur, touched, tNow, ft)
		local p, n = 2, #str
		local cvs = nil
		if byte(str, 1) >= 4 then
			p = readClocks(str, play.run, ft)
			cvs = clockValues(play.run, cvScratch)
		end
		while p <= n do
			local id, flags
			id, p = rv(str, p)
			flags, p = rv(str, p)
			if hasMask(flags, K_DROP) then
				cur[id] = nil
				touched[id] = nil
				play.dropped[id] = true
			else
				local s = cur[id]
				if not s then s = newState(); cur[id] = s end
				p = applyPayloadV2(str, p, s, flags, tNow, cvs)
				touched[id] = true
			end
		end
	end

	local function isFull(str)
		local b = byte(str, 1)
		return b == 1 or b == 3 or (b >= 4 and b % 8 == 5)
	end

	local function applyString(str, cur, touched, tNow, ft)
		if isFull(str) then
			for id in pairs(cur) do
				play.dropped[id] = true
				cur[id] = nil
			end
		end
		if byte(str, 1) >= 2 then
			applyV2(str, cur, touched, tNow or 0, ft)
		else
			applyV1(str, cur, touched)
		end
	end

	-- --------------------------------------------------------------------------------------------- player
	-- true when the part was just anchored (it was free until now, so its pose must be written)
	local function ensureAnchored(part, s)
		if orig[part] == nil and not s.an then
			orig[part] = false
			-- (the CFrame it had when HappaTAS took it: where it is held while no recorded pose moves it)
			origVel[part] = { part.AssemblyLinearVelocity, part.AssemblyAngularVelocity, part.CFrame }
			part.Anchored = true
			return true
		end
		return false
	end

	local function writeProps(part, s, sh)
		local mask = s[I_MASK]
		if hasMask(mask, F_TR) and sh[I_TR] ~= s[I_TR] then
			part.Transparency = s[I_TR] / 1000
			sh[I_TR] = s[I_TR]
		end
		if hasMask(mask, F_CC) and sh[I_CC] ~= s[I_CC] then
			part.CanCollide = s[I_CC] == 1
			sh[I_CC] = s[I_CC]
		end
		if hasMask(mask, F_COL) and (sh[I_COL] ~= s[I_COL] or sh[I_COL + 1] ~= s[I_COL + 1] or sh[I_COL + 2] ~= s[I_COL + 2]) then
			part.Color = Color3.fromRGB(s[I_COL], s[I_COL + 1], s[I_COL + 2])
			sh[I_COL], sh[I_COL + 1], sh[I_COL + 2] = s[I_COL], s[I_COL + 1], s[I_COL + 2]
		end
		if hasMask(mask, F_SZ) and (sh[I_SZ] ~= s[I_SZ] or sh[I_SZ + 1] ~= s[I_SZ + 1] or sh[I_SZ + 2] ~= s[I_SZ + 2]) then
			part.Size = V3(s[I_SZ] / 1000, s[I_SZ + 1] / 1000, s[I_SZ + 2] / 1000)
			sh[I_SZ], sh[I_SZ + 1], sh[I_SZ + 2] = s[I_SZ], s[I_SZ + 1], s[I_SZ + 2]
		end
		if hasMask(mask, F_MAT) and sh[I_MAT] ~= s[I_MAT] then
			local okM, mat = pcall(function() return Enum.Material:FromValue(s[I_MAT]) end)
			if okM and mat then part.Material = mat end
			sh[I_MAT] = s[I_MAT]
		end
	end

	local function hasPose(s)
		local mask = s[I_MASK]
		return hasMask(mask, F_CF) and hasMask(mask, F_ROT)
	end

	-- pose at playback time t. With a keyframe coming in the next frame, the small correction
	-- towards it is spread over this frame (the motion itself keeps its speed)
	local IDENT = CFrame.new()
	-- returns the pose and whether it was blended with the next keyframe
	local function targetPose(id, s, t)
		local cf = poseAt(s, t)
		local nx = play.next[id]
		if nx then
			local span = play.nextT - play.curT
			if span > 1e-6 then
				local alpha = (t - play.curT) / span
				if alpha > 1 then alpha = 1 end
				if alpha > 0 then
					local rot = cf.Rotation
					if nx[2] then rot = IDENT:Lerp(nx[2], alpha) * rot end
					return rot + (cf.Position + nx[1] * alpha), true
				end
			end
		end
		return cf, false
	end

	local function writePart(id, s, t, renderPass)
		local part = parts[id]
		if not part then return end -- (removed parts are unregistered)
		local sh = CO.shown[id]
		if not sh then sh = {}; CO.shown[id] = sh end
		local rs = S[id]
		if rs.lost then
			rs.lost = false
			play.lost[part] = nil
			if orig[part] ~= nil then part.Anchored = true end
			sh.cf = nil
		end
		local v = s[I_VER]
		if hasPose(s) then
			local cf = sh.cf
			if renderPass and sh.t == t and cf then
				-- the render pass shows the pose Heartbeat computed for the same time
			elseif not (cf and sh.v == v and not sh.b and (sh.t == t or s[48] ~= 1) and not play.next[id]) then
				-- (the same state, not moving, not blended = the same pose as last time)
				cf, sh.b = targetPose(id, s, t)
			end
			local fresh = ensureAnchored(part, rs)
			-- parts HappaTAS anchored itself only need a write when the pose changed (or when they were
			-- free until now); parts anchored by the game (scripted movers) are written every time so
			-- scripts can't win
			if fresh or orig[part] == nil or sh.cf ~= cf then
				part.CFrame = cf
			end
			sh.cf, sh.t, sh.v = cf, t, v
		end
		if (not renderPass and sh.pv ~= v) or rs.pd then
			if rs.pd then
				sh[I_TR], sh[I_CC], sh[I_COL], sh[I_SZ], sh[I_MAT] = nil, nil, nil, nil, nil
			end
			writeProps(part, s, sh)
			rs.pd = false
			sh.pv = v
		end
	end

	local function writeAll(t, renderPass)
		for id, s in pairs(play.cur) do writePart(id, s, t, renderPass) end
	end

	local function cloneCur(cur)
		local c = {}
		for id, s in pairs(cur) do c[id] = copyState(s) end
		return c
	end

	local function ckPut(i)
		if play.ck[i] then return end
		if play.ckN >= MAX_CK then
			local far, farD = nil, -1
			for k in pairs(play.ck) do
				local d = abs(k - i)
				if d > farD then far, farD = k, d end
			end
			if far then play.ck[far], play.ckRun[far] = nil, nil; play.ckN = play.ckN - 1 end
		end
		play.ck[i] = cloneCur(play.cur)
		play.ckRun[i] = { play.run[1], play.run[2], play.run[3] }
		play.ckN = play.ckN + 1
	end

	local function finalize(touched)
		for id in pairs(touched) do
			local s = play.cur[id]
			if s and s[48] == 1 then play.dyn[id] = true else play.dyn[id] = nil end
		end
		for id in pairs(play.dyn) do
			if not play.cur[id] then play.dyn[id] = nil end
		end
		for id in pairs(play.dropped) do
			if not play.cur[id] then releasePart(id) end
			play.dropped[id] = nil
		end
	end

	local function applyRange(data, from, to, touched, makeCk)
		for i = from, to do
			local fr = data[i]
			local str = fr and fr.CO
			if str then
				applyString(str, play.cur, touched, fr.TotalTime or 0, fr.FrameTime)
				if makeCk and (i % CK == 0 or isFull(str)) then ckPut(i) end
			end
		end
	end

	-- look one frame ahead: pose of every object that gets a new keyframe in frame f + 1
	local nextScratch = {}
	local function computeNext(data, f)
		play.next = {}
		play.nextFor = f
		local fr, nf = data[f], data[f + 1]
		play.curT = fr and fr.TotalTime or 0
		play.nextT = nf and nf.TotalTime or play.curT
		-- the next frame's clocks (from this frame's running values)
		local nr = { play.run[1], play.run[2], play.run[3] }
		local nstr = nf and nf.CO
		local np = 2
		if nstr and byte(nstr, 1) >= 4 then np = readClocks(nstr, nr, nf.FrameTime) end
		clockValues(nr, play.nv)
		local nvReal = { play.nv[1], play.nv[2], play.nv[3] }
		if nstr and byte(nstr, 1) >= 64 then
			-- the next frame starts a new recording with new clocks: up to it, the clocks of this one go on
			-- (at the TAS clock's rate) instead of being blended into the new numbers
			local span = play.nextT - play.curT
			for c = 1, 3 do play.nv[c] = play.cv[c] + span end
		end
		if not nstr or not Settings.On("Smooth Client Objects") then return end
		local str = nstr
		if byte(str, 1) < 2 then return end
		local p, n = np, #str
		local cvs = nil
		if byte(str, 1) >= 4 then cvs = nvReal end
		local cur = play.cur
		local s = nextScratch -- (reused for every record: only dp / dr are kept)
		-- a full snapshot's records are whole values, not changes: they start from nothing (applied to the
		-- current state they made the "next keyframe" the sum of both, and a part near the origin jumped for
		-- a frame at every full snapshot)
		local nextFull = isFull(str)
		local ok = pcall(function()
			while p <= n do
				local id, flags
				id, p = rv(str, p)
				flags, p = rv(str, p)
				if not hasMask(flags, K_DROP) then
					local base = cur[id]
					local from = (not nextFull) and base or nil
					for i = 1, 50 do s[i] = from and from[i] or 0 end
					p = applyPayloadV2(str, p, s, flags, play.nextT, cvs)
					if base and hasPose(base) and hasPose(s) and hasMask(flags, K_KEY) then
						-- where the current model would be vs. the next keyframe (the keyframe's own pose: it is
						-- the pose at the next frame)
						local want = poseAt(s, nil)
						local have = poseAt(base, play.nextT)
						local dp = want.Position - have.Position
						if dp.Magnitude < 25 then
							local dr = want.Rotation * have.Rotation:Inverse()
							local _, ang = dr:ToAxisAngle()
							play.next[id] = { dp, (ang == ang and ang > 1e-5) and dr or nil }
						end
					end
				end
			end
		end)
		if not ok then play.next = {} end
	end

	local function advanceTo(data, f, touched)
		if play.ckData ~= data or play.ckVer ~= CO.dataVersion then
			play.ck, play.ckN, play.ckRun = {}, 0, {}
			play.ckData, play.ckVer = data, CO.dataVersion
		end
		local makeCk = play.kind == "show"

		if play.data == data and play.version == CO.dataVersion and play.frame and f >= play.frame and f - play.frame <= 600 then
			if f > play.frame then applyRange(data, play.frame + 1, f, touched, makeCk) end
			play.frame = f
			finalize(touched)
		else
			-- seek: nearest checkpoint, otherwise the last full snapshot
			for id in pairs(play.cur) do play.dropped[id] = true end
			local bestF
			for cfm in pairs(play.ck) do
				if cfm <= f and f - cfm <= 3000 and (not bestF or cfm > bestF) then bestF = cfm end
			end
			local start
			if bestF then
				play.cur = cloneCur(play.ck[bestF])
				local cr = play.ckRun[bestF]
				play.run[1], play.run[2], play.run[3] = cr[1], cr[2], cr[3]
				start = bestF + 1
			else
				play.run[1], play.run[2], play.run[3] = 0, 0, 0
				local base = f
				local limit = math.max(1, f - 3000)
				while base >= limit do
					local str = data[base] and data[base].CO
					if str and isFull(str) then break end
					base = base - 1
				end
				play.cur = {}
				start = (base >= limit) and base or (f + 1)
			end
			applyRange(data, start, f, touched, makeCk)
			play.data, play.version, play.frame = data, CO.dataVersion, f
			for id in pairs(play.cur) do touched[id] = true end
			finalize(touched)
		end
		clockValues(play.run, play.cv)
		if play.nextFor ~= f then computeNext(data, f) end
	end

	-- a held part goes back on the pose HappaTAS last gave it, or the one it had when HappaTAS took it
	local function restoreHeld(part)
		part.Anchored = true
		local sh = CO.shown[ids[part]]
		local ov = origVel[part]
		local cf = (sh and sh.cf) or (ov and ov[3])
		if cf then part.CFrame = cf end
	end
	-- held parts a game script let go since the last pass (found in the live client: the EToH kit's
	-- DistanceCulling sets Anchored every 0.2 s, physics moved the parts in between). Parts with a
	-- recorded pose were already put back by writePart, this handles the rest (frozen while paused,
	-- or never recorded because they did not move)
	local function fixLost()
		for part in pairs(play.lost) do
			play.lost[part] = nil
			if orig[part] ~= nil and part.Parent then
				restoreHeld(part)
				local rs = S[ids[part]]
				if rs then rs.lost = false end
			end
		end
	end
	local function sweepAnchors()
		if next(play.lost) then fixLost() end
		play.sweep = play.sweep + 1
		if play.sweep % 5 ~= 0 then return end
		for part in pairs(orig) do
			if part.Parent and not part.Anchored then restoreHeld(part) end
		end
	end

	local function freeze()
		for id, part in pairs(parts) do
			if part.Parent then ensureAnchored(part, S[id]) end
		end
		frozen = true
	end

	local function hasCOData(data)
		if play.hasData ~= data or play.hasVer ~= CO.dataVersion or (not play.has and play.hasLen ~= #data) then
			local any = false
			for i = 1, #data do
				if data[i].CO then any = true break end
			end
			play.hasData, play.hasVer, play.has, play.hasLen = data, CO.dataVersion, any, #data
		end
		return play.has
	end
	CO.HasData = hasCOData

	function CO.IsPlaying() return play.active end
	function CO.IsTesting() return play.active and play.kind == "test" end
	function CO.IsHolding() return frozen or play.active or next(orig) ~= nil end
	function CO.Invalidate()
		CO.dataVersion = CO.dataVersion + 1
		play.nextFor = nil
	end

	local function frameTime(data, frame)
		local fr = data[frame]
		return fr and fr.TotalTime or 0
	end
	local touchedScratch = {}
	local function cleanTouched() table.clear(touchedScratch); return touchedScratch end

	function CO.PlaybackBegin(data, startFrame)
		if not (enabled and scanDone) then return false end
		play.active = false
		if not hasCOData(data) then return false end
		play.kind = "test"
		play.active = true
		play.sweep = 0
		play.data = nil
		play.nextFor = nil
		play.t = frameTime(data, startFrame)
		advanceTo(data, startFrame, cleanTouched())
		writeAll(play.t, false)
		return true
	end

	-- t = playback time in seconds (the same TestingTimer the character uses)
	function CO.PlaybackTo(data, frame, t)
		if not play.active then return end
		play.t = t or frameTime(data, frame)
		advanceTo(data, frame, cleanTouched())
		writeAll(play.t, false)
		sweepAnchors()
	end

	-- every Heartbeat while paused in Create mode
	function CO.Tick()
		if not (play.active and play.kind == "show") then return end
		sweepAnchors()
	end

	-- last thing in the render step: same time as the character, re-asserted after game scripts
	function CO.RenderStep()
		if not play.active then return end
		writeAll(play.t, true)
		if next(play.lost) then fixLost() end
	end

	function CO.EndPlayback()
		play.active = false
		CO.Release()
	end

	function CO.ShowFrame(data, frame)
		if not (enabled and scanDone) then return end
		if not frozen then freeze() end
		if not hasCOData(data) then return end
		play.kind = "show"
		play.active = true
		play.t = frameTime(data, frame)
		advanceTo(data, frame, cleanTouched())
		play.next, play.nextFor = {}, nil -- no blending while paused: show exactly the frame
		writeAll(play.t, false)
		sweepAnchors()
	end

	-- unpausing at another time: put every recorded part back WITH its recorded velocity
	function CO.RestoreUnpause(data, frame)
		if not (enabled and scanDone) then return end
		if hasCOData(data) and frame and data[frame] then
			play.kind = "show"
			advanceTo(data, frame, cleanTouched())
			local t = frameTime(data, frame)
			-- a frame recorded in slow motion (speed hack, SK = its factor) has slowed velocities: they go back
			-- in normal units, the speed hack slows the world again when the slow motion goes on
			local sk = tonumber(data[frame].SK) or 1
			if sk <= 0 then sk = 1 end
			for id, s in pairs(play.cur) do
				local part = parts[id]
				if part and part.Parent and hasPose(s) then
					part.CFrame = poseAt(s, t)
					local sh = CO.shown[id]
					if not sh then sh = {}; CO.shown[id] = sh end
					writeProps(part, s, sh)
					if orig[part] ~= nil then
						part.Anchored = orig[part]
						orig[part], origVel[part] = nil, nil
					end
					if not part.Anchored then
						local L = V3(s[36] / 1000, s[37] / 1000, s[38] / 1000)
						local W = V3(s[39] / 1000, s[40] / 1000, s[41] / 1000)
						local w2 = W:Dot(W)
						if s[49] == 3 and w2 > 1e-10 then
							-- v3 keeps the velocity at the part's position; the assembly's is the one at its centre
							-- of mass: the part's motion along the screw axis + w x (centre of mass - axis point)
							local okC, com = pcall(function() return part.AssemblyCenterOfMass end)
							if okC and typeof(com) == "Vector3" then
								local ctr = V3(s[1] / 1000, s[2] / 1000, s[3] / 1000) - L:Cross(W) / w2
								L = W * (L:Dot(W) / w2) + W:Cross(com - ctr)
							end
						end
						part.AssemblyLinearVelocity = L / sk
						part.AssemblyAngularVelocity = W / sk
					end
				end
			end
		end
		CO.Release()
	end

	-- --------------------------------------------------------------------------------------------- save / load
	function CO.IdsOf(str, set)
		set = set or {}
		local isV2 = byte(str, 1) >= 2
		local p, n = bodyStart(str), #str
		while p <= n do
			local id, flags
			id, p = rv(str, p)
			set[id] = true
			flags, p = rv(str, p)
			p = skipPayload(isV2, flags, str, p)
		end
		return set
	end

	local function remapString(str, map)
		local isV2 = byte(str, 1) >= 2
		local p, n = bodyStart(str), #str
		local out = { sub(str, 1, p - 1) }
		while p <= n do
			local id
			id, p = rv(str, p)
			local after = p
			local flags
			flags, p = rv(str, p)
			p = skipPayload(isV2, flags, str, p)
			local h = {}
			putVar(h, map[id] or id)
			out[#out + 1] = bufToString(h)
			out[#out + 1] = sub(str, after, p - 1)
		end
		return table.concat(out)
	end

	function CO.ExportObjects(frames)
		local set = {}
		for _, f in ipairs(frames) do
			if f.CO then CO.IdsOf(f.CO, set) end
		end
		local list = {}
		for id in pairs(set) do
			local key = Reg.idToKey[id]
			if key then list[#list + 1] = { id = id, key = key } end
		end
		table.sort(list, function(a, b) return a.id < b.id end)
		return list
	end

	-- ids inside a file belong to the session that saved it: translate them to this session
	function CO.ImportObjects(frames, objects)
		local map, changed = {}, false
		for _, o in ipairs(objects) do
			local sid = idForKey(o.key)
			map[o.id] = sid
			Reg.used[sid] = true
			if sid ~= o.id then changed = true end
		end
		if changed then
			for i, f in ipairs(frames) do
				if f.CO then f.CO = remapString(f.CO, map) end
				if i % 1500 == 0 then task.wait() end
			end
		end
		CO.Invalidate()
	end

	function CO.Start()
		if Settings.On("Sync Client Objects") then CO.Enable() end
		Settings.Changed("Sync Client Objects", function(v)
			if v ~= 0 then CO.Enable() else CO.Disable() end
		end)
		Janitor.add(function() CO.Disable() end)
	end
end

