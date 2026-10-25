-- ================================================================================================
--  CO REGISTRY  (HappaTAS 3, client objects): which parts are client objects, their ids and per-part
--  record state, the change listeners, and holding / releasing parts HappaTAS anchors (V2.38.17
--  p13_clientobjects.lua 42-519, function by function).
--  A part is a candidate when it isn't anchored, belongs to a constraint / body mover, has the kit's
--  beat / vanisher markers, or sits in one of the kit's folders (or a folder whose name hints at one).
--  Anchored parts that aren't candidates are watched: un-anchored later (a falling platform), they are
--  registered then. Each registered part has 6 change listeners (Transparency, CanCollide, Color, Size,
--  Material: re-read when one changed; Anchored kept in s.an), so a part at rest costs nothing.
--  Ids come from the part's workspace path ("Folder/Part#2" for the second sibling of that name), stable
--  between sessions, so a saved run finds its parts again.
-- ================================================================================================
local CONFIG = import("config")

local Registry = {}
Registry.__index = Registry

local floor = math.floor

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

local function insideCharacter(part)
	local inst = part.Parent
	while inst and inst ~= workspace do
		if inst:IsA("Model") and inst:FindFirstChildOfClass("Humanoid") then return true end
		inst = inst.Parent
	end
	return false
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
Registry.listRemove = listRemove

local function readProps(part, t)
	t[1] = floor(part.Transparency * 1000 + 0.5)
	t[2] = part.CanCollide and 1 or 0
	local col = part.Color
	t[3], t[4], t[5] = floor(col.R * 255 + 0.5), floor(col.G * 255 + 0.5), floor(col.B * 255 + 0.5)
	local sz = part.Size
	t[6], t[7], t[8] = floor(sz.X * 1000 + 0.5), floor(sz.Y * 1000 + 0.5), floor(sz.Z * 1000 + 0.5)
	t[9] = part.Material.Value
end
Registry.readProps = readProps

local PROP_NAMES = { "Transparency", "CanCollide", "Color", "Size", "Material" }
Registry.PROP_NAMES = PROP_NAMES

function Registry.new(onStatus)
	local cfg = CONFIG.ClientObjects or {}
	local self = setmetatable({
		cfg = cfg,
		RADIUS = cfg.Radius or 300, ALWAYS = cfg.AlwaysRadius or 30,
		MAX_REG = cfg.MaxRegistered or 8000, MAX_WATCH = cfg.MaxWatched or 30000,
		WATCH_ANCHORED = cfg.WatchAnchored ~= false,
		reg = { keyToId = {}, idToKey = {}, nextId = 1, used = {} },
		onStatus = onStatus,
		sibCache = setmetatable({}, { __mode = "k" }),
		conParts = setmetatable({}, { __mode = "k" }),
		watchConns = {}, nWatched = 0, nRegistered = 0,
		enabled = false, scanDone = false, scanning = false, descConn = nil, remConn = nil,
		-- held parts: orig[part] = its Anchored before HappaTAS held it, origVel[part] = { lin, ang, cf }
		orig = {}, origVel = {}, frozen = false,
		shown = {}, -- id -> what the player last wrote (V2 CO.shown)
		lost = {},  -- held parts a game script let go since the last pass (V2 play.lost)
		playActive = false, -- (V2 play.active: a release puts parts on their registration state)
		frameNo = 0, -- frames recorded so far (the recorder keeps it; s.regN = frameNo at registration)
	}, Registry)
	self:clearTables()
	return self
end

function Registry:clearTables()
	self.parts, self.ids, self.S, self.partByKey = {}, {}, {}, {}
	self.plist, self.pidx, self.actArr, self.actPos, self.dropQ = {}, {}, {}, {}, {}
end

function Registry:status(text)
	if self.onStatus then task.spawn(self.onStatus, text) end
end

-- ------------------------------------------------------------------------------------------------ keys / ids
function Registry:siblingIndex(inst)
	local parent = inst.Parent
	local map = self.sibCache[parent]
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
	self.sibCache[parent] = map
	return map[inst] or 1
end

-- workspace path with "#n" for siblings that share a name (stable between sessions)
function Registry:keyOf(part)
	local segs, n = {}, 0
	local inst = part
	while inst and inst ~= workspace do
		if not inst.Parent then return nil end
		local name = (inst.Name:gsub("[/#]", "_"))
		local idx = self:siblingIndex(inst)
		n = n + 1
		segs[n] = idx > 1 and (name .. "#" .. idx) or name
		inst = inst.Parent
	end
	if inst ~= workspace then return nil end
	local out = {}
	for i = n, 1, -1 do out[#out + 1] = segs[i] end
	return table.concat(out, "/")
end

function Registry:idForKey(key, preferred)
	local Reg = self.reg
	local id = Reg.keyToId[key]
	if id then return id end
	id = preferred
	if not id or Reg.idToKey[id] then id = Reg.nextId end
	Reg.keyToId[key] = id
	Reg.idToKey[id] = key
	if id >= Reg.nextId then Reg.nextId = id + 1 end
	return id
end

-- ------------------------------------------------------------------------------------------------ which parts
function Registry:isCandidate(part)
	if not part or not part:IsA("BasePart") then return false end
	if part == workspace.Terrain or part:GetAttribute("HappaTASIgnore") then return false end
	if insideCharacter(part) then return false end
	if not part.Anchored then return true end
	local groups = self.cfg.Groups
	if groups and groups[part.CollisionGroup] == true then return true end
	if self.conParts[part] then return true end
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

-- anchored parts that may be unanchored later (falling platforms...)
function Registry:watch(part)
	if not self.WATCH_ANCHORED or self.watchConns[part] or self.nWatched >= self.MAX_WATCH then return end
	if not part.Anchored then return end
	local cn
	cn = part:GetPropertyChangedSignal("Anchored"):Connect(function()
		if not part.Anchored then
			if cn then cn:Disconnect() end
			if self.watchConns[part] then self.watchConns[part] = nil; self.nWatched = self.nWatched - 1 end
			if self.enabled and self.orig[part] == nil then self:register(part) end
		end
	end)
	self.watchConns[part] = cn
	self.nWatched = self.nWatched + 1
end

function Registry:unwatch(part)
	local cn = self.watchConns[part]
	if cn then
		cn:Disconnect()
		self.watchConns[part] = nil
		self.nWatched = self.nWatched - 1
	end
end

function Registry:noteConstraint(c)
	local ok, a0, a1 = pcall(function() return c.Attachment0, c.Attachment1 end)
	if not ok then return end
	for _, a in ipairs({ a0 or false, a1 or false }) do
		if a then
			local p = a.Parent
			if p and p:IsA("BasePart") then self.conParts[p] = true end
		end
	end
end

-- Change signals instead of reading every frame: the 5 recorded properties are re-read when one
-- of them changed (pd = for the recorder, vd = for the visibility test), Anchored is kept in s.an
function Registry:watchProps(part, s)
	local list = {}
	local function dirty() s.pd, s.vd = true, true end
	local function anchoredChanged()
		s.an = part.Anchored
		-- a game script let go of a part HappaTAS holds (the EToH kit's DistanceCulling sets the
		-- PrimaryPart's Anchored every 0.2 s): anchor it again and write its pose on the next pass
		if not s.an and self.orig[part] ~= nil then
			s.lost = true
			self.lost[part] = true
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

function Registry:setActive(id, active)
	local actPos = self.actPos
	local was = actPos[id] ~= nil
	if active == was then return end
	if active then
		local actArr = self.actArr
		actArr[#actArr + 1] = id
		actPos[id] = #actArr
	else
		listRemove(self.actArr, actPos, id)
		local s = self.S[id]
		if s and s.moved and not s.needBase then
			self.dropQ[id] = true
			s.needBase = true
		end
	end
end

function Registry:register(part)
	if self.ids[part] or self.nRegistered >= self.MAX_REG then return end
	if not self:isCandidate(part) then
		if part.Anchored and part ~= workspace.Terrain then self:watch(part) end
		return
	end
	local key = self:keyOf(part)
	if not key then return end
	local old = self.partByKey[key]
	if old and old ~= part and old.Parent then return end
	local id = self:idForKey(key)
	self.parts[id], self.ids[part], self.partByKey[key] = part, id, part
	local plist = self.plist
	plist[#plist + 1] = id
	self.pidx[id] = #plist
	local s = newRecState(part)
	s.regN = self.frameNo -- (frames recorded before it was registered)
	self.S[id] = s
	self:watchProps(part, s)
	self.nRegistered = self.nRegistered + 1
	self:unwatch(part)
end

function Registry:unregister(part)
	self:unwatch(part)
	local id = self.ids[part]
	if not id then return end
	listRemove(self.actArr, self.actPos, id)
	listRemove(self.plist, self.pidx, id)
	unwatchProps(self.S[id])
	self.ids[part], self.parts[id], self.S[id], self.dropQ[id] = nil, nil, nil, nil
	self.orig[part], self.origVel[part] = nil, nil
	local key = self.reg.idToKey[id]
	if key and self.partByKey[key] == part then self.partByKey[key] = nil end
	self.nRegistered = self.nRegistered - 1
end

function Registry:startScan()
	if self.scanning or self.scanDone then return end
	self.scanning = true
	task.spawn(function()
		local list = workspace:GetDescendants()
		for i = 1, #list do
			if not self.enabled then self.scanning = false return end
			local inst = list[i]
			if inst:IsA("Constraint") then self:noteConstraint(inst) end
			if i % 1500 == 0 then task.wait() end
		end
		for i = 1, #list do
			if not self.enabled then self.scanning = false return end
			local inst = list[i]
			if inst:IsA("BasePart") then self:register(inst) end
			if i % 300 == 0 then task.wait() end
		end
		self.scanning = false
		if self.enabled then
			self.scanDone = true
			self:status("Client objects ready (" .. self.nRegistered .. " parts)")
		end
	end)
end

function Registry:isReady() return self.enabled and self.scanDone end

-- every registered part that is still in the game (time control's world uses it)
function Registry:eachPart(fn)
	for _, part in pairs(self.parts) do
		if part.Parent then fn(part) end
	end
end

function Registry:enable()
	if self.enabled then return end
	self.enabled = true
	self.descConn = workspace.DescendantAdded:Connect(function(inst)
		if inst:IsA("Constraint") then
			task.defer(function()
				self:noteConstraint(inst)
				local ok, a0, a1 = pcall(function() return inst.Attachment0, inst.Attachment1 end)
				if ok then
					for _, a in ipairs({ a0 or false, a1 or false }) do
						if a and a.Parent and a.Parent:IsA("BasePart") then self:register(a.Parent) end
					end
				end
			end)
		elseif inst:IsA("BasePart") then
			self:register(inst)
		end
	end)
	self.remConn = workspace.DescendantRemoving:Connect(function(inst)
		if inst:IsA("BasePart") then self:unregister(inst) end
	end)
	self:status("Scanning client objects...")
	self:startScan()
end

-- ------------------------------------------------------------------------------------------------ holding
-- a part HappaTAS anchored goes back to how it was (Anchored + the velocity it had)
function Registry:restorePart(part, was)
	if not part.Parent then return end
	local origVel = self.origVel
	pcall(function()
		part.Anchored = was
		local ov = origVel[part]
		if ov then
			part.AssemblyLinearVelocity = ov[1]
			part.AssemblyAngularVelocity = ov[2]
		end
	end)
end

function Registry:releasePart(id)
	local part = self.parts[id]
	if part then
		local s = self.S[id]
		if s and s.rcf and s.rv and self.playActive then
			pcall(function()
				part.CFrame = s.rcf
				part.Transparency = s.rv[1] / 1000
				part.CanCollide = s.rv[2] == 1
				part.Color = Color3.fromRGB(s.rv[3], s.rv[4], s.rv[5])
				part.Size = Vector3.new(s.rv[6] / 1000, s.rv[7] / 1000, s.rv[8] / 1000)
				local okM, mat = pcall(function() return Enum.Material:FromValue(s.rv[9]) end)
				if okM and mat then part.Material = mat end
			end)
		end
		if self.orig[part] ~= nil then self:restorePart(part, self.orig[part]) end
		self.orig[part], self.origVel[part] = nil, nil
	end
	self.shown[id] = nil
end

-- every held part goes back (V2 CO.Release, the registry's half)
function Registry:releaseAll()
	self.playActive = false
	for part, was in pairs(self.orig) do self:restorePart(part, was) end
	self.orig, self.origVel = {}, {}
	self.frozen = false
	self.shown = {}
	self.lost = {}
end

-- true when the part was just anchored (it was free until now, so its pose must be written)
function Registry:ensureAnchored(part, s)
	if self.orig[part] == nil and not s.an then
		self.orig[part] = false
		-- (the CFrame it had when HappaTAS took it: where it is held while no recorded pose moves it)
		self.origVel[part] = { part.AssemblyLinearVelocity, part.AssemblyAngularVelocity, part.CFrame }
		part.Anchored = true
		return true
	end
	return false
end

-- off: every part released, every listener gone (the caller resets the recorder / player first)
function Registry:disable()
	if not self.enabled then return end
	self.enabled = false
	self:releaseAll()
	if self.descConn then self.descConn:Disconnect(); self.descConn = nil end
	if self.remConn then self.remConn:Disconnect(); self.remConn = nil end
	for _, cn in pairs(self.watchConns) do cn:Disconnect() end
	self.watchConns, self.nWatched = {}, 0
	for _, s in pairs(self.S) do unwatchProps(s) end
	self:clearTables()
	self.nRegistered = 0
	self.scanDone, self.scanning = false, false
end

function Registry:counts() return self.nRegistered, #self.actArr end

return Registry
