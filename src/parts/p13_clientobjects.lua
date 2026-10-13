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
--
--  record layout (v2):  frame byte 2 = delta, 3 = full snapshot, then records:
--      varint id, varint flags, payload
--  flags: 1 key (pos), 2 rotation, 4 linear velocity, 8 angular velocity, 16 transparency,
--         32 can-collide (64 = its value), 128 colour, 256 size, 512 material, 1024 dropped
--  v1 data (frame byte 0 / 1) still plays.
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
	local FULL_EVERY     = CFG.FullEvery or 600
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
	--   42-44 v1 spin  45 keyframe time  46 v1 spin flag  48 "moves by velocity"  50 version (new number on
	--   every change, so a pose / property write can be skipped while the state is the same)
	local I_TR, I_CC, I_COL, I_SZ, I_MAT, I_MASK, I_VER = 13, 14, 15, 18, 21, 23, 50
	local F_CF, F_TR, F_CC, F_CCV, F_COL, F_SZ, F_MAT, F_ROT = 1, 2, 4, 8, 16, 32, 64, 128
	local F_VEL, F_SPIN, F_SKIP = 256, 512, 1024
	local K_KEY, K_ROT, K_LV, K_AV = 1, 2, 4, 8
	local K_TR, K_CC, K_CCV, K_COL, K_SZ, K_MAT, K_DROP = 16, 32, 64, 128, 256, 512, 1024

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
	local recGen, lastT, visCursor = 0, nil, 1

	local play = {
		cur = {}, dyn = {}, dropped = {}, active = false, kind = "test",
		data = nil, version = -1, frame = nil, sweep = 0,
		ck = {}, ckN = 0, ckData = nil, ckVer = -1,
		t = 0, curT = 0, nextT = 0, next = {}, nextFor = nil,
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
		BeatBlock = true, ["Beat Block"] = true, Buttons = true, ButtonPlatforms = true,
		ButtonDeactivator = true, Morpher = true, Client = true,
	}

	local function nameHint(n)
		return n:find("[Pp]usher") or n:find("[Ss]pinner") or n:find("[Cc]onveyor")
			or n:find("[Mm]oving") or n:find("[Bb]eat[Bb]lock")
	end

	local function isCandidate(part)
		if not part or not part:IsA("BasePart") then return false end
		if part == workspace.Terrain or part:GetAttribute("HappaTASIgnore") then return false end
		if insideCharacter(part) then return false end
		if not part.Anchored then return true end
		if CFG.Groups and CFG.Groups[part.CollisionGroup] == true then return true end
		if conParts[part] then return true end
		if part:FindFirstChildWhichIsA("Constraint") or part:FindFirstChildWhichIsA("BodyMover") then return true end
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
		local function anchoredChanged() s.an = part.Anchored end
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
			rv = rv, cp = cp,
			kp = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
			lq = { 0, 0, 0 }, aq = { 0, 0, 0 },
			pv = { 0, 0, 0, 0, 0, 0, 0, 0, 0 },
			dyn = false, kT = 0, moved = false, needBase = true, chain = -1, gen = 0,
			prevCF = nil, prevFrame = -10, emaL = nil, emaA = nil,
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
	end

	-- --------------------------------------------------------------------------------------------- visibility
	local function isVisible(part, s, ppos, cam, camPos, vpX, vpY, tanHalf, strict)
		if s.vd then -- size / transparency changed (or never read)
			s.vd = false
			s.rad = part.Size.Magnitude * 0.5
			s.tr = part.Transparency
		end
		local pos = part.Position
		local d = (pos - ppos).Magnitude
		local rad = s.rad
		if d - rad > RADIUS then return false end
		if strict then
			-- Frustum Culling CO: close parts always, otherwise only visible parts on screen
			if d <= 25 then return true end
			if s.tr >= 1 and part.LocalTransparencyModifier >= 1 then return false end
			if not cam then return true end
			local sp, onScreen = cam:WorldToViewportPoint(pos)
			return onScreen and sp.Z > 0
		end
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
	local function buildPose(x, y, z, r1, r2, r3, r4, r5, r6, r7, r8, r9, lx, ly, lz, wx, wy, wz, dt)
		local cf = CF(x, y, z, r1, r2, r3, r4, r5, r6, r7, r8, r9)
		if dt and dt > 0 then
			if dt > MAX_EXTRAP then dt = MAX_EXTRAP end
			local pos = V3(x + lx * dt, y + ly * dt, z + lz * dt)
			local mag = sqrt(wx * wx + wy * wy + wz * wz)
			local rot = cf.Rotation
			if mag > 1e-5 then
				rot = CFrame.fromAxisAngle(V3(wx / mag, wy / mag, wz / mag), mag * dt) * rot
			end
			return rot + pos
		end
		return cf
	end

	local function poseAt(s, t)
		local dt = nil
		if t and s[48] == 1 then dt = t - s[45] end
		return buildPose(
			s[1] / 1000, s[2] / 1000, s[3] / 1000,
			s[4] / 1000, s[5] / 1000, s[6] / 1000, s[7] / 1000, s[8] / 1000, s[9] / 1000, s[10] / 1000, s[11] / 1000, s[12] / 1000,
			s[36] / 1000, s[37] / 1000, s[38] / 1000, s[39] / 1000, s[40] / 1000, s[41] / 1000, dt)
	end

	-- --------------------------------------------------------------------------------------------- recorder
	local A, P, K = {}, {}, {}

	local function recordObject(out, id, part, s, now, dtT)
		if s.gen ~= recGen then
			s.gen = recGen
			s.prevCF, s.emaL, s.emaA = nil, nil, nil
		end

		local cf = part.CFrame
		local cp = s.cp
		-- the properties are read on the same frames as always (every 2nd), but only when one of them
		-- changed since the last read (or every 16th frame, in case a change was not reported)
		if (frameNo + id) % 2 == 0 and (s.pd or (frameNo + id) % 16 == 0) then
			s.pd = false
			readProps(part, cp)
		end

		-- velocity: physics parts report it, scripted (anchored) parts are measured frame to frame
		local anchored = s.an
		local instL, instA = ZV, ZV
		if anchored then
			local prev = s.prevCF
			if prev and dtT and s.prevFrame == frameNo - 1 and cf ~= prev then -- an unchanged CFrame = no velocity
				instL = (cf.Position - prev.Position) / dtT
				local axis, ang = (cf.Rotation * prev.Rotation:Inverse()):ToAxisAngle()
				if ang == ang and ang > 1e-6 and axis.X == axis.X then instA = axis * (ang / dtT) end
				if instL.X ~= instL.X then instL = ZV end
			end
			local eL, eA = s.emaL, s.emaA
			if instL == ZV and (eL == nil or eL == ZV) then s.emaL = ZV else s.emaL = eL and eL:Lerp(instL, 0.5) or instL end
			if instA == ZV and (eA == nil or eA == ZV) then s.emaA = ZV else s.emaA = eA and eA:Lerp(instA, 0.5) or instA end
		else
			instL, instA = part.AssemblyLinearVelocity, part.AssemblyAngularVelocity
		end
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
			if not dev then return end
			s.moved = true
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

		-- does the model still explain the part? (same maths as playback, same clock)
		local needKey = first
		if not first then
			local age = now - s.kT
			if s.dyn then
				if age > MAX_AGE then
					needKey = true
				else
					local pc = buildPose(
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
		if needKey then
			for i = 1, 12 do K[i] = floor(A[i] * 1000 + 0.5) end
			rotChanged = first
			if not first then
				for i = 4, 12 do
					if K[i] ~= kp[i] then rotChanged = true break end
				end
			end
			local L, W = instL, instA
			if anchored and s.dyn then L, W = s.emaL or instL, s.emaA or instA end
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
			s.kT = now
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

	function CO.BeginRecording()
		forceFull = true
		recGen = recGen + 1
		lastT = nil
		dropQ = {}
		if enabled and scanDone then updateVisibility(playerPosNow(), true) end
	end

	-- tNow = TotalTime of the frame being recorded (TAS clock)
	function CO.Record(playerPos, tNow)
		if not (enabled and scanDone) then return nil end
		frameNo = frameNo + 1
		local now = tNow or 0
		local dtT = lastT and (now - lastT) or nil
		lastT = now
		if dtT and (dtT > 0.25 or dtT <= 0) then dtT = nil end

		local full = forceFull or frameNo % FULL_EVERY == 0
		forceFull = false
		if full then chainNo = chainNo + 1 end

		updateVisibility(playerPos, false)

		local out = { full and 3 or 2 }
		for id in pairs(dropQ) do
			putVar(out, id)
			putVar(out, K_DROP)
		end
		dropQ = {}

		local anyDyn = false
		for i = 1, #actArr do
			local id = actArr[i]
			local part, s = parts[id], S[id]
			-- (removed parts are unregistered by DescendantRemoving; the visibility pass checks Parent too)
			if part and s then
				recordObject(out, id, part, s, now, dtT)
				if s.dyn and s.moved then anyDyn = true end
			end
		end

		-- a 1 byte marker keeps frames alive while something moves by velocity (Optimize TAS keeps them)
		if #out == 1 and not full and not anyDyn then return nil end
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
	local verN = 0
	local function newState()
		local t = {}
		for i = 1, 50 do t[i] = 0 end
		return t
	end
	local function copyState(s)
		local t = {}
		for i = 1, 50 do t[i] = s[i] end
		return t
	end

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

	-- one v2 record payload onto a state table
	local function applyPayloadV2(str, p, s, flags, tNow)
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
			s[45] = tNow
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

	local function applyV2(str, cur, touched, tNow)
		local p, n = 2, #str
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
				p = applyPayloadV2(str, p, s, flags, tNow)
				touched[id] = true
			end
		end
	end

	local function isFull(str)
		local b = byte(str, 1)
		return b == 1 or b == 3
	end

	local function applyString(str, cur, touched, tNow)
		if isFull(str) then
			for id in pairs(cur) do
				play.dropped[id] = true
				cur[id] = nil
			end
		end
		if byte(str, 1) >= 2 then
			applyV2(str, cur, touched, tNow or 0)
		else
			applyV1(str, cur, touched)
		end
	end

	-- --------------------------------------------------------------------------------------------- player
	local function ensureAnchored(part, s)
		if orig[part] == nil and not s.an then
			orig[part] = false
			origVel[part] = { part.AssemblyLinearVelocity, part.AssemblyAngularVelocity }
			part.Anchored = true
		end
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
		local v = s[I_VER]
		if hasPose(s) then
			local cf = sh.cf
			if renderPass and sh.t == t and cf then
				-- the render pass shows the pose Heartbeat computed for the same time
			elseif not (cf and sh.v == v and not sh.b and (sh.t == t or s[48] ~= 1) and not play.next[id]) then
				-- (the same state, not moving, not blended = the same pose as last time)
				cf, sh.b = targetPose(id, s, t)
			end
			ensureAnchored(part, S[id])
			-- parts HappaTAS anchored itself only need a write when the pose changed; parts that were
			-- anchored by the game (scripted movers) are written every time so scripts can't win
			if orig[part] == nil or sh.cf ~= cf then
				part.CFrame = cf
			end
			sh.cf, sh.t, sh.v = cf, t, v
		end
		if not renderPass and sh.pv ~= v then
			writeProps(part, s, sh)
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
			if far then play.ck[far] = nil; play.ckN = play.ckN - 1 end
		end
		play.ck[i] = cloneCur(play.cur)
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
				applyString(str, play.cur, touched, fr.TotalTime or 0)
				if makeCk and (i % CK == 0 or isFull(str)) then ckPut(i) end
			end
		end
	end

	-- look one frame ahead: pose of every object that gets a new keyframe in frame f + 1
	local function computeNext(data, f)
		play.next = {}
		play.nextFor = f
		local fr, nf = data[f], data[f + 1]
		play.curT = fr and fr.TotalTime or 0
		play.nextT = nf and nf.TotalTime or play.curT
		if not (nf and nf.CO) or not Settings.On("Smooth Client Objects") then return end
		local str = nf.CO
		if byte(str, 1) < 2 then return end
		local p, n = 2, #str
		local cur = play.cur
		local ok = pcall(function()
			while p <= n do
				local id, flags
				id, p = rv(str, p)
				flags, p = rv(str, p)
				if not hasMask(flags, K_DROP) then
					local base = cur[id]
					local s = base and copyState(base) or newState()
					p = applyPayloadV2(str, p, s, flags, play.nextT)
					if base and hasPose(base) and hasPose(s) and hasMask(flags, K_KEY) then
						-- where the current model would be vs. the next keyframe
						local want = poseAt(s, play.nextT)
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
			play.ck, play.ckN = {}, 0
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
				start = bestF + 1
			else
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
		if play.nextFor ~= f then computeNext(data, f) end
	end

	local function sweepAnchors()
		play.sweep = play.sweep + 1
		if play.sweep % 5 ~= 0 then return end
		for part in pairs(orig) do
			if part.Parent and not part.Anchored then part.Anchored = true end
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
		advanceTo(data, startFrame, {})
		writeAll(play.t, false)
		return true
	end

	-- t = playback time in seconds (the same TestingTimer the character uses)
	function CO.PlaybackTo(data, frame, t)
		if not play.active then return end
		play.t = t or frameTime(data, frame)
		advanceTo(data, frame, {})
		writeAll(play.t, false)
		sweepAnchors()
	end

	-- every Heartbeat while paused in Create mode
	function CO.Tick()
		if not (play.active and play.kind == "show") then return end
		writeAll(play.t, false)
		sweepAnchors()
	end

	-- last thing in the render step: same time as the character, re-asserted after game scripts
	function CO.RenderStep()
		if not play.active then return end
		writeAll(play.t, true)
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
		advanceTo(data, frame, {})
		play.next, play.nextFor = {}, nil -- no blending while paused: show exactly the frame
		writeAll(play.t, false)
		sweepAnchors()
	end

	-- unpausing at another time: put every recorded part back WITH its recorded velocity
	function CO.RestoreUnpause(data, frame)
		if not (enabled and scanDone) then return end
		if hasCOData(data) and frame and data[frame] then
			play.kind = "show"
			advanceTo(data, frame, {})
			local t = frameTime(data, frame)
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
						part.AssemblyLinearVelocity = V3(s[36] / 1000, s[37] / 1000, s[38] / 1000)
						part.AssemblyAngularVelocity = V3(s[39] / 1000, s[40] / 1000, s[41] / 1000)
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
		local p, n = 2, #str
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
		local out = { sub(str, 1, 1) }
		local p, n = 2, #str
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

