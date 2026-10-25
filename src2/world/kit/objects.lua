-- ================================================================================================
--  KIT OBJECTS  (HappaTAS 3 world plugin, order 61, "Sync Kit Objects"): the EToH kit's objects as functions
--  of TAS time (V2.38.17 p16_kit.lua 541-1530, function by function; the run is seen through a frames view,
--  below, so V2's code reads and writes the timeline as it read and wrote its frame tables).
--  Beat blocks: the beat comes from the TAS time (recording, paused on any frame, playback), the kit's own
--  writes are undone, the ding plays on HappaTAS's beat. Turrets: the kit's bullet is replaced by HappaTAS's,
--  saved as fire / end events (column v2KE), positioned on the TAS clock, stopped by walls and by your
--  character (the kit's damage), played back. Pushbox spawns: a box from later in the TAS is hidden on earlier
--  frames. Bounce pad / jump launcher effects saved and played again. Forces a kit script puts on the
--  character: removed after unpausing earlier, off while testing. Only for a run made with the kit rules
--  (tl.meta.kitVersion >= 1, set at its first recorded frame); ids are saved with their paths (tl.meta.v2kit).
-- ================================================================================================
local Env = import("platform/env")

local Players = Env.svc("Players")
local engine = nil -- (the engine, set by KitObjectsPlugin.new)
local KitObjects = {}

-- ------------------------------------------------------------------------------------------------ frames view
-- V2's kit code works on a frames table: #data, data[i].KE / TotalTime / FrameTime / SK, data.KitVersion. The
-- view gives it the timeline that way: one view per timeline (V2 compares the table it was given), one proxy per
-- frame index, reading the timeline when used (so cuts, loads and new frames are seen at once)
local views = setmetatable({}, { __mode = "k" })
local function frameProxy(tl, i)
	return setmetatable({}, {
		__index = function(_, k)
			if k == "KE" then return tl:getList("v2KE", i) end
			if k == "TotalTime" or k == "FrameTime" then return tl:get(k, i, 1) end
			if k == "SK" then return tl.cols.v2SK and tl:getList("v2SK", i) or nil end
			return nil
		end,
		__newindex = function(_, k, v)
			if k == "KE" then tl:setList("v2KE", i, v) end
		end,
	})
end
local function framesOf(tl)
	local v = views[tl]
	if v then return v end
	local proxies = {}
	v = setmetatable({}, {
		__len = function() return tl:count() end,
		__index = function(_, k)
			if type(k) == "number" then
				if k < 1 or k > tl:count() or k % 1 ~= 0 then return nil end
				local p = proxies[k]
				if not p then p = frameProxy(tl, k); proxies[k] = p end
				return p
			end
			if k == "KitVersion" then return tl.meta and tl.meta.kitVersion end
			return nil
		end,
		__newindex = function(_, k, val)
			if k == "KitVersion" then
				tl.meta = tl.meta or {}
				tl.meta.kitVersion = val
			end
		end,
	})
	views[tl] = v
	return v
end

do
	local KO = KitObjects
	KO.CURRENT = 1
	local CS = Env.svc("CollectionService")
	local V3, CF = Vector3.new, CFrame.new
	local floor = math.floor

	local reg = { keyToId = {}, idToKey = {}, nextId = 1 }
	local function idFor(key)
		local id = reg.keyToId[key]
		if id then return id end
		id = reg.nextId
		reg.nextId = id + 1
		reg.keyToId[key], reg.idToKey[id] = id, key
		return id
	end
	KO.Reg = reg

	-- the rules of a TAS (nil = a TAS being made now: decided by the setting when it starts recording)
	function KO.VersionOf(data)
		local v = data and data.KitVersion
		if v == nil then return engine.settings:on("syncKitObjects") and KO.CURRENT or 0 end
		return v
	end

	local cur = { mode = 1, data = nil, f = 0, t = 0, rec = false, on = false }
	KO.cur = cur

	local holder -- folder for HappaTAS's own bullets (under the camera: game scripts that look through the
	-- tower's parts never see them)
	local function getHolder()
		local cam = workspace.CurrentCamera
		if holder and holder.Parent == cam and cam then return holder end
		if holder then pcall(function() holder:Destroy() end) end
		holder = Instance.new("Folder")
		holder.Name = "HappaTASKit"
		holder.Parent = cam or workspace
		return holder
	end

	local function attr(inst, name, def)
		local v = inst and inst:GetAttribute(name)
		if v == nil then return def end
		if typeof(def) == "EnumItem" and type(v) == "string" then
			local ok, e = pcall(function() return def.EnumType[v] end)
			return (ok and e) or def
		end
		if typeof(v) ~= typeof(def) then return def end
		return v
	end

	-- sounds the kit plays itself are muted while HappaTAS plays them on its own time
	local muted = {}
	local function mute(snd)
		if not snd then return end
		local m = muted[snd]
		if m then m.n = m.n + 1 return end
		muted[snd] = { n = 1, vol = snd.Volume }
		pcall(function() snd.Volume = 0 end)
	end
	local function unmuteAll()
		for snd, m in pairs(muted) do pcall(function() snd.Volume = m.vol end) end
		muted = {}
	end
	local ownSounds = setmetatable({}, { __mode = "k" }) -- the copies HappaTAS plays itself
	local function playCopy(snd, parent)
		if not (snd and parent and parent.Parent) then return end
		local m = muted[snd]
		local vol = m and m.vol or snd.Volume
		if vol <= 0 then return end
		pcall(function()
			local c = snd:Clone()
			ownSounds[c] = true
			c.Volume = vol
			c.Parent = parent
			c:Play()
			local len = (c.TimeLength > 0 and c.TimeLength or 2) / math.max(c.PlaybackSpeed, 0.01)
			task.delay(len + 0.1, function() pcall(function() c:Destroy() end) end)
		end)
	end

	local function charRoot()
		local ch = Players.LocalPlayer.Character
		return ch, ch and ch:FindFirstChild("HumanoidRootPart")
	end

	-- --------------------------------------------------------------------------------------------- beat blocks
	local AFFECTED = { Decal = "Transparency", Texture = "Transparency", SelectionBox = "Transparency",
		SelectionSphere = "Transparency", SurfaceGui = "Enabled", BillboardGui = "Enabled", Beam = "Enabled",
		ParticleEmitter = "Enabled", Fire = "Enabled", Sparkles = "Enabled", Smoke = "Enabled", Trail = "Enabled",
		PointLight = "Enabled", SpotLight = "Enabled", SurfaceLight = "Enabled", Highlight = "Enabled" }
	local beats, beatOf = {}, {}

	local function beatConf(cfg)
		return {
			indicator = attr(cfg, "Indicator", true),
			indSize = attr(cfg, "IndicatorSize", V3(3, 3, 3)),
			indMul = attr(cfg, "IndicatorScaleMultiplier", 1),
			indMat = attr(cfg, "MaterialIndicator", Enum.Material.SmoothPlastic),
			offCC = attr(cfg, "OffCanCollide", false), offTr = attr(cfg, "OffTransparency", 0.5), offCT = attr(cfg, "OffCanTouch", false),
			onCC = attr(cfg, "OnCanCollide", true), onTr = attr(cfg, "OnTransparency", 1), onCT = attr(cfg, "OnCanTouch", true),
			interval = attr(cfg, "Interval", 1), indInterval = attr(cfg, "IndicatorInterval", 0.5),
			children = attr(cfg, "ToggleChildren", false),
		}
	end

	-- the kit's own table of the group's parts with their sizes and materials (Visual/BeatBlock: the
	-- toggleBeatBlock closure of the group's loop keeps it), so a group caught showing its indicator still
	-- gets its real size back
	local function kitBeatTables()
		local out = {}
		if not Env.filtergc then return out end
		local ok, fns = pcall(Env.filtergc, "function", { Constants = { "IndicatorInterval" } })
		if not ok or type(fns) ~= "table" then return out end
		for _, fn in ipairs(fns) do
			pcall(function()
				local cfgInst, tbl = nil, nil
				for _, up in pairs(debug.getupvalues(fn)) do
					if type(up) == "table" and typeof(rawget(up, "__instance")) == "Instance" and rawget(up, "Interval") ~= nil then
						cfgInst = rawget(up, "__instance")
					elseif type(up) == "function" then
						for _, up2 in pairs(debug.getupvalues(up)) do
							if type(up2) == "table" then
								local _, first = next(up2)
								if type(first) == "table" and type(first[1]) == "table" and typeof(first[1].part) == "Instance" then tbl = up2 end
							end
						end
					end
				end
				if cfgInst and tbl then out[cfgInst] = tbl end
			end)
		end
		return out
	end

	local function looksLikeIndicator(g, p)
		local c = g.conf
		return c.indicator and c.indMul == 1 and p.Material == c.indMat and (p.Size - c.indSize).Magnitude < 1e-3
	end

	local function addBeat(cfg, kitTables)
		if beatOf[cfg] then return end
		local folder = cfg.Parent
		if not (folder and folder:IsA("Folder")) then return end
		local ms = cfg:FindFirstChild("MusicSyncConfiguration")
		if ms and ms:GetAttribute("SyncEnabled") == true and type(ms:GetAttribute("ZoneName")) == "string" then return end
		local g = { cfg = cfg, groups = {}, parts = {}, orig = {}, kids = {}, conf = beatConf(cfg), n = 0, dirty = true, conns = {},
			last = nil }
		for _, p in ipairs(folder:GetDescendants()) do
			if p:IsA("BasePart") then
				local num = tonumber(p.Name:match("%d+"))
				if num then
					local list = g.groups[num]
					if not list then list = {}; g.groups[num] = list end
					list[#list + 1] = p
					g.parts[#g.parts + 1] = p
				end
			end
		end
		while g.groups[g.n + 1] do g.n = g.n + 1 end
		if g.n == 0 then return end
		local kitT = kitTables and kitTables[cfg]
		for _, p in ipairs(g.parts) do
			local o = nil
			if kitT then
				for _, list in pairs(kitT) do
					for _, d in ipairs(list) do
						if d.part == p and typeof(d.size) == "Vector3" then o = { size = d.size, material = d.material } end
					end
				end
			end
			if not o and not looksLikeIndicator(g, p) then o = { size = p.Size, material = p.Material } end
			g.orig[p] = o
			local kids = {}
			for _, ch in ipairs(p:GetChildren()) do
				if AFFECTED[ch.ClassName] then kids[#kids + 1] = ch end
			end
			g.kids[p] = kids
			for _, prop in ipairs({ "CanCollide", "CanTouch", "Transparency", "Size", "Material" }) do
				g.conns[#g.conns + 1] = p:GetPropertyChangedSignal(prop):Connect(function()
					g.dirty = true
					-- learned while HappaTAS doesn't drive the group: the kit gives every part its own size and
					-- material back at each beat
					if not g.driving and (prop == "Size" or prop == "Material") and not looksLikeIndicator(g, p) then
						g.orig[p] = { size = p.Size, material = p.Material }
					end
				end)
			end
		end
		g.conns[#g.conns + 1] = cfg.AttributeChanged:Connect(function() g.conf = beatConf(cfg); g.dirty = true end)
		local snd = cfg:FindFirstChild("DingSound")
		if not (snd and snd:IsA("Sound")) then
			local ok, s = pcall(function()
				return Env.svc("ReplicatedStorage").Framework.Kit.Repository.Visual.BeatBlock:FindFirstChild("DefaultDingSound")
			end)
			snd = (ok and s and s:IsA("Sound")) and s or nil
		end
		g.ding = snd
		beatOf[cfg] = g
		beats[#beats + 1] = g
	end

	local function dropBeat(g)
		for _, c in ipairs(g.conns) do c:Disconnect() end
		beatOf[g.cfg] = nil
		for i = #beats, 1, -1 do if beats[i] == g then table.remove(beats, i) end end
	end

	-- the kit's loop: toggle(k) [wait Interval - IndicatorInterval] displayNext(k + 1) [wait IndicatorInterval]
	local function beatAt(g, t)
		local c = g.conf
		local ii = c.indicator and math.max(c.indInterval, 0) or 0
		local first = math.max(c.interval - ii, 0)
		local len = first + ii
		if len <= 1e-6 then len = 1e-6 end
		local cycle = floor(t / len)
		local active = cycle % g.n + 1
		local phase = t - cycle * len
		local ind = nil
		if c.indicator and phase >= first then ind = active % g.n + 1 end
		return active, ind, cycle
	end

	local function setIf(p, prop, v)
		if p[prop] ~= v then p[prop] = v end
	end
	local function beatWrite(g, active, ind)
		local c = g.conf
		for num, list in pairs(g.groups) do
			local on = num == active
			local isInd = num == ind
			for _, p in ipairs(list) do
				local o = g.orig[p] or { size = p.Size, material = p.Material }
				g.orig[p] = o
				pcall(function()
					if isInd then
						setIf(p, "Size", (c.indMul ~= 1) and o.size * c.indMul or c.indSize)
						setIf(p, "Material", c.indMat)
						setIf(p, "CanCollide", c.offCC)
						setIf(p, "CanTouch", c.offCT)
						setIf(p, "Transparency", c.offTr)
					else
						local cc, ct, tr = c.offCC, c.offCT, c.offTr
						if on then cc, ct, tr = c.onCC, c.onCT, c.onTr end
						setIf(p, "Size", o.size)
						setIf(p, "Material", o.material)
						setIf(p, "CanCollide", cc)
						setIf(p, "CanTouch", ct)
						setIf(p, "Transparency", tr)
						if c.children then
							for _, ch in ipairs(g.kids[p]) do
								if AFFECTED[ch.ClassName] == "Transparency" then setIf(ch, "Transparency", tr)
								else setIf(ch, "Enabled", on) end
							end
						end
					end
				end)
			end
		end
	end

	-- a group is written when its beat changed or a write touched it since (dirty); beatWrite only writes the
	-- properties that differ
	local function beatStep(t, advancing)
		for _, g in ipairs(beats) do
			if not (g.cfg.Parent) then
				dropBeat(g)
			else
				local active, ind, cycle = beatAt(g, t)
				local key = active * 1000 + (ind or 0)
				if g.dirty or g.lastKey ~= key then
					if advancing and g.lastCycle ~= nil and cycle ~= g.lastCycle and g.ding then
						local _, root = charRoot()
						local best, bd = nil, math.huge
						for _, p in ipairs(g.groups[active] or {}) do
							local d = root and (p.Position - root.Position).Magnitude or 0
							if d < bd then best, bd = p, d end
						end
						playCopy(g.ding, best)
					end
					g.driving = true
					beatWrite(g, active, ind)
					g.dirty = false
					g.lastKey = key
				end
				g.lastCycle = cycle
			end
		end
	end

	-- --------------------------------------------------------------------------------------------- turrets
	local turrets, turretOf = {}, {}
	-- the bullets of the TAS in memory (fire order), built from its events; firstSpawn[spawner id] = the first
	-- frame a pushbox spawn event of that spawner is saved on
	local idx = { data = nil, list = {}, bySeq = {}, nextSeq = 1, valid = false, maxLife = 0, firstSpawn = {} }
	local shown = {}   -- bullet record -> model on screen
	local damageEvent  -- the kit's CharacterManager (for its Damage)

	local function stripBullet(m)
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("LuaSourceContainer") or d:IsA("Constraint") or d:IsA("BodyMover") or d:IsA("TouchTransmitter") then
				pcall(function() d:Destroy() end)
			elseif d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d:SetAttribute("HappaTASIgnore", true)
			end
		end
		m:SetAttribute("HappaTASBullet", true)
		return m
	end
	local function mainPartOf(m)
		return m.PrimaryPart or m:FindFirstChild("Bullet") or m:FindFirstChildWhichIsA("BasePart", true)
	end

	-- the kit's bullet templates (Interactables/Turret keeps each one in its fireBullet closure, out of the game)
	local function kitBulletTemplates()
		local out = {}
		if not Env.filtergc then return out end
		local ok, fns = pcall(Env.filtergc, "function", { Constants = { "BulletOffset" } })
		if not ok or type(fns) ~= "table" then return out end
		for _, fn in ipairs(fns) do
			pcall(function()
				local tpl, model = nil, nil
				for _, up in pairs(debug.getupvalues(fn)) do
					if typeof(up) == "Instance" then
						if up:IsA("Model") and up.Parent == nil and up:FindFirstChildWhichIsA("BasePart", true) then tpl = up
						elseif up:IsA("BasePart") and up.Name == "Turret" and up.Parent then model = up.Parent end
					end
				end
				if tpl and model then out[model] = tpl end
			end)
		end
		return out
	end

	local function fallbackBullet()
		local m = Instance.new("Model")
		m.Name = "Bullet"
		local p
		local ok, def = pcall(function()
			return Env.svc("ReplicatedStorage").Framework.Kit.Repository.Interactables.Turret:FindFirstChild("Bullet")
		end)
		if ok and def and def:IsA("BasePart") then
			p = def:Clone()
		else
			p = Instance.new("Part")
			p.Shape = Enum.PartType.Ball
			p.Size = V3(1, 1, 1)
			p.Material = Enum.Material.Neon
			p.Color = Color3.fromRGB(255, 0, 0)
		end
		p.Name = "Bullet"
		p.Parent = m
		m.PrimaryPart = p
		return m
	end

	local function turretTemplate(t)
		if t.template then return t.template end
		local kitT = kitBulletTemplates()
		local src = kitT[t.model]
		local ok, m = pcall(function() return src and src:Clone() end)
		t.template = stripBullet((ok and m) or fallbackBullet())
		return t.template
	end

	local onKitBullet -- (below)

	local function addTurret(cfg)
		local model = cfg.Parent
		if not model or turretOf[model] then return end
		local part = model:FindFirstChild("Turret")
		if not (part and part:IsA("BasePart")) then return end
		local key = engine.co:keyOf(model)
		if not key then return end
		local t = { model = model, part = part, cfg = cfg, key = key, id = idFor(key), conns = {} }
		local snd = part:FindFirstChild("Fire")
		t.fireSnd = (snd and snd:IsA("Sound")) and snd or nil
		t.conns[#t.conns + 1] = model.ChildAdded:Connect(function(child)
			if child:IsA("Model") and not child:GetAttribute("HappaTASBullet") then onKitBullet(t, child) end
		end)
		turretOf[model] = t
		turrets[#turrets + 1] = t
		idx.valid = false -- (bullets saved for this turret before it was found)
		-- (the kit loads its objects again on respawn: a turret taken out of the game is forgotten)
		t.conns[#t.conns + 1] = model.AncestryChanged:Connect(function()
			if model:IsDescendantOf(workspace) then return end
			for _, c in ipairs(t.conns) do c:Disconnect() end
			turretOf[model] = nil
			for i = #turrets, 1, -1 do if turrets[i] == t then table.remove(turrets, i) end end
			idx.valid = false
		end)
	end

	local function rotVec(cf)
		local axis, angle = cf:ToAxisAngle()
		return axis * angle
	end
	local function vecRot(x, y, z)
		local v = V3(x, y, z)
		local a = v.Magnitude
		if a < 1e-9 then return CF() end
		return CFrame.fromAxisAngle(v / a, a)
	end

	local function makeBullet(e, f, tFire)
		-- e = { 1, turretId, seq, ox, oy, oz, rx, ry, rz, vx, vy, vz, life }
		local key = reg.idToKey[e[2]]
		local tur = nil
		for _, t in ipairs(turrets) do if t.key == key then tur = t break end end
		return { seq = e[3], f = f, t = tFire, tur = tur, turId = e[2], pos = V3(e[4], e[5], e[6]), rot = vecRot(e[7], e[8], e[9]),
			v = V3(e[10], e[11], e[12]), life = e[13], endF = nil, dmg = 0 }
	end

	local function buildIndex(data)
		idx.data, idx.list, idx.bySeq, idx.nextSeq, idx.valid, idx.maxLife, idx.firstSpawn = data, {}, {}, 1, true, 0, {}
		if not data then return end
		for f = 1, #data do
			local fr = data[f]
			local ke = fr and fr.KE
			if ke then
				for _, e in ipairs(ke) do
					if e[1] == 1 then
						local b = makeBullet(e, f, fr.TotalTime or 0)
						idx.list[#idx.list + 1] = b
						idx.bySeq[b.seq] = b
						if b.seq >= idx.nextSeq then idx.nextSeq = b.seq + 1 end
						if b.life > idx.maxLife then idx.maxLife = b.life end
					elseif e[1] == 2 then
						local b = idx.bySeq[e[2]]
						if b then b.endF = f; b.dmg = e[3] or 0 end
					elseif e[1] == 3 then
						if not idx.firstSpawn[e[2]] then idx.firstSpawn[e[2]] = f end
					end
				end
			end
		end
	end
	-- the first bullet that can still be flying at TAS time t (the list is in fire order)
	local function firstFlying(I, t)
		local list = I.list
		local lo, hi, from = 1, #list, #list + 1
		local tMin = t - I.maxLife - 1e-6
		while lo <= hi do
			local mid = floor((lo + hi) / 2)
			if list[mid].t >= tMin then from = mid; hi = mid - 1 else lo = mid + 1 end
		end
		return from
	end
	local function index(data)
		if not idx.valid or idx.data ~= data then buildIndex(data) end
		return idx
	end

	local function addEvent(fr, e)
		local ke = fr.KE
		if not ke then ke = {}; fr.KE = ke end
		ke[#ke + 1] = e
	end

	local function hideBullet(b)
		local m = shown[b]
		if m then
			shown[b] = nil
			pcall(function() m:Destroy() end)
		end
	end
	local function hideAllBullets()
		for b in pairs(shown) do hideBullet(b) end
	end

	local function bulletAt(b, t)
		return b.pos + b.v * math.max(0, t - b.t)
	end

	local function showBullets(data, f, t)
		local I = index(data)
		local alive = {}
		local list = I.list
		for i = firstFlying(I, t), #list do
			local b = list[i]
			if b.f >= f then break end
			if (b.endF == nil or b.endF >= f) and (t - b.t) <= b.life + 1e-6 then
				alive[b] = true
				local m = shown[b]
				if not m then
					local tur = b.tur
					if tur then
						local ok, c = pcall(function() return turretTemplate(tur):Clone() end)
						if ok and c then
							m = c
							c.Parent = getHolder()
							shown[b] = m
						end
					end
				end
				if m then
					pcall(function() m:PivotTo(CF(bulletAt(b, t)) * b.rot) end)
				end
			end
		end
		for b in pairs(shown) do
			if not alive[b] then hideBullet(b) end
		end
	end

	-- the kit's bullet appeared (its loop fired, on the kit clock): recording -> HappaTAS's bullet takes its
	-- place in the TAS; paused / testing -> the TAS already has its bullets, the kit's is removed
	onKitBullet = function(t, child)
		if not cur.on then return end
		if cur.rec and cur.data and #cur.data > 0 then
			local data = cur.data
			local n = #data
			local fr = data[n]
			if not t.template then
				local ok, c = pcall(function() return child:Clone() end)
				if ok and c then t.template = stripBullet(c) end
			end
			local cfg = t.cfg
			local spawn = t.part.CFrame * attr(cfg, "BulletOffset", CF())
			local vel = t.part.CFrame.LookVector * attr(cfg, "Speed", 50)
			local r3 = rotVec(spawn)
			local I = index(data)
			local seq = I.nextSeq
			I.nextSeq = seq + 1
			local e = { 1, t.id, seq, spawn.X, spawn.Y, spawn.Z, r3.X, r3.Y, r3.Z, vel.X, vel.Y, vel.Z, attr(cfg, "MaxLifetime", 15) }
			addEvent(fr, e)
			local b = makeBullet(e, n, fr.TotalTime or 0)
			b.tur = t
			I.list[#I.list + 1] = b
			I.bySeq[seq] = b
			if b.life > I.maxLife then I.maxLife = b.life end
			playCopy(t.fireSnd, t.part)
		end
		pcall(function() child:Destroy() end)
	end

	local function dealDamage(amount)
		if amount <= 0 then return end
		if damageEvent == nil then
			damageEvent = false
			pcall(function()
				local cm = require(Env.svc("ReplicatedStorage").Framework.Kit.Managers.CharacterManager)
				if type(cm) == "table" and type(cm.Damage) == "function" then damageEvent = cm end
			end)
		end
		if damageEvent then
			-- (a call into the game's script runs in a thread of its own, see gameCall in the bridge)
			task.spawn(pcall, damageEvent.Damage, damageEvent, amount)
		end
	end

	-- what the kit's isValidHit would say about a part the bullet ran into
	local function verdict(b, part, ch)
		if not part:IsA("BasePart") then return nil end
		if b.tur and part == b.tur.part then return nil end
		if CS and part:HasTag("IgnoreBullets") then return nil end
		if not part.CanTouch then return nil end
		local owner = Players:GetPlayerFromCharacter(part.Parent)
		if owner then
			if owner ~= Players.LocalPlayer or part.Name == "Torso" then return nil end
			local tc = b.tur and b.tur.cfg:FindFirstChild("TouchConfiguration")
			if tc and tc:GetAttribute("player") == false then return nil end
			return "player"
		end
		if part.CanCollide then return "solid" end
		return nil
	end

	local castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Exclude
	castParams.RespectCanCollide = false
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.RespectCanCollide = false
	-- the first thing the bullet runs into from p0 to p1 ("player" / "solid"); a Blockcast doesn't see what
	-- already overlaps its start, so what overlaps the end (a limb that moved into the bullet) counts too
	local function castBullet(b, p0, p1, size, ch)
		local ex = { getHolder() }
		if b.tur then ex[#ex + 1] = b.tur.model end
		local dir = p1 - p0
		if dir.Magnitude >= 1e-5 then
			for _ = 1, 8 do
				castParams.FilterDescendantsInstances = ex
				local ok, res = pcall(workspace.Blockcast, workspace, CF(p0) * b.rot, size, dir, castParams)
				if not ok or not res then break end
				local v = verdict(b, res.Instance, ch)
				if v then return v end
				ex[#ex + 1] = res.Instance
			end
		end
		overlapParams.FilterDescendantsInstances = ex
		local ok, list = pcall(workspace.GetPartBoundsInBox, workspace, CF(p1) * b.rot, size, overlapParams)
		if ok and type(list) == "table" then
			local best = nil
			for _, part in ipairs(list) do
				local v = verdict(b, part, ch)
				if v == "player" then return v end
				best = best or v
			end
			return best
		end
		return nil
	end

	local function turretHits(data, n)
		local I = index(data)
		local fr, prev = data[n], data[n - 1]
		if not fr then return end
		local t1 = fr.TotalTime or 0
		local t0 = prev and prev.TotalTime or t1
		local ch = Players.LocalPlayer.Character
		local list = I.list
		for i = firstFlying(I, t0), #list do
			local b = list[i]
			if b.f < n and b.endF == nil then
				local dmg = nil
				if t1 - b.t >= b.life - 1e-6 then
					dmg = 0
				else
					local size = V3(1, 1, 1)
					local m = shown[b] or (b.tur and turretTemplate(b.tur))
					local mp = m and mainPartOf(m)
					if mp then size = mp.Size end
					local hit = castBullet(b, bulletAt(b, math.max(t0, b.t)), bulletAt(b, t1), size, ch)
					if hit == "player" then
						dmg = (mp == nil or mp.Name == "Bullet") and attr(b.tur and b.tur.cfg, "Damage", 5) or 0
					elseif hit == "solid" then
						dmg = 0
					end
					if hit and b.tur and not attr(b.tur.cfg, "DestroyOnTouch", true) then
						-- (the kit leaves such a bullet flying; only the damage happens)
						if dmg > 0 then dealDamage(dmg) end
						dmg = nil
					end
				end
				if dmg then
					addEvent(fr, { 2, b.seq, dmg })
					b.endF, b.dmg = n, dmg
					if dmg > 0 then dealDamage(dmg) end
				end
			end
		end
	end

	-- --------------------------------------------------------------------------------------------- effects
	-- Bounce pads (Interactables/BouncePad) and jump launchers (Interactables/JumpLauncher) play their effect from
	-- their Touched handler: a sound (the kit's playSoundFromInstance puts a copy of it into the part), a particle
	-- burst and a flash the kit tweens back. Playback moves the character itself, so the kit never sees a touch
	-- and nothing showed: the effect is saved as an event when the kit's sound copy appears while recording
	-- (event 4: the object, which sound) and Test plays it again (the sound, the BounceParticle burst; the flash
	-- comes back with Sync Client Objects, which records the part's colour / transparency / size). A sound the
	-- kit plays itself while testing is muted (the TAS has its own).
	local FX_SOUNDS = { "BounceSound", "Tick", "Bounce" } -- event code = index
	local FX_CODE = { BounceSound = 1, Tick = 2, Bounce = 3 }
	local FX_PARTICLE = { BounceSound = true, Bounce = true } -- (the launcher's Tick is only a sound)
	local fxObjects, fxOf = {}, {}
	local function addFx(cfg)
		local part = cfg.Parent
		if not (part and part:IsA("BasePart")) or fxOf[part] then return end
		local key = engine.co:keyOf(part)
		if not key then return end
		local o = { part = part, cfg = cfg, key = key, id = idFor(key), conns = {} }
		o.conns[1] = part.ChildAdded:Connect(function(child)
			if not (FX_CODE[child.Name] and child:IsA("Sound")) or ownSounds[child] or not cur.on then return end
			if cur.mode == 3 then
				pcall(function() child.Volume = 0 end)
			elseif cur.rec and cur.data and #cur.data > 0 then
				addEvent(cur.data[#cur.data], { 4, o.id, FX_CODE[child.Name] })
			end
		end)
		o.conns[2] = part.AncestryChanged:Connect(function()
			if part:IsDescendantOf(workspace) then return end
			for _, c in ipairs(o.conns) do c:Disconnect() end
			fxOf[part] = nil
			for i = #fxObjects, 1, -1 do if fxObjects[i] == o then table.remove(fxObjects, i) end end
		end)
		fxOf[part] = o
		fxObjects[#fxObjects + 1] = o
	end
	local function playFx(id, code)
		local key, name = reg.idToKey[id], FX_SOUNDS[code]
		if not (key and name) then return end
		for _, o in ipairs(fxObjects) do
			if o.key == key and o.part.Parent then
				local snd, burst = nil, nil
				for _, d in ipairs(o.part:GetDescendants()) do
					-- (the kit's sound: in the pad's configuration / the launcher's Sounds folder, not a copy)
					if not snd and d.Name == name and d:IsA("Sound") and d.Parent ~= o.part then snd = d end
					if not burst and d.Name == "BounceParticle" and d:IsA("ParticleEmitter") then burst = d end
				end
				if snd then playCopy(snd, o.part) end
				if burst and FX_PARTICLE[name] then pcall(function() burst:Emit(1) end) end
			end
		end
	end

	-- testing: the frames playback went through since last time (fire sounds and the damage of the TAS)
	local replayedTo = nil
	local function replayEvents(data, f)
		if replayedTo == nil or f < replayedTo then replayedTo = f - 1 end
		if f - replayedTo > 600 then replayedTo = f - 1 end
		for i = replayedTo + 1, f do
			local fr = data[i]
			if fr and fr.KE then
				for _, e in ipairs(fr.KE) do
					if e[1] == 1 then
						local key = reg.idToKey[e[2]]
						for _, t in ipairs(turrets) do if t.key == key then playCopy(t.fireSnd, t.part) end end
					elseif e[1] == 2 and (e[3] or 0) > 0 then
						dealDamage(e[3])
					elseif e[1] == 4 then
						playFx(e[2], e[3])
					end
				end
			end
		end
		replayedTo = f
	end

	-- --------------------------------------------------------------------------------------------- pushboxes
	local spawners, spawnerOf = {}, {}
	local function boxParts(box)
		local list = {}
		if box:IsA("BasePart") then list[1] = box end
		for _, d in ipairs(box:GetDescendants()) do if d:IsA("BasePart") then list[#list + 1] = d end end
		return list
	end
	local function hideBox(s)
		if s.hidden or not (s.box and s.box.Parent) then return end
		s.hidden = {}
		for _, p in ipairs(boxParts(s.box)) do
			s.hidden[p] = { p.Transparency, p.CanCollide, p.CanTouch, p.CanQuery }
			pcall(function() p.Transparency = 1; p.CanCollide = false; p.CanTouch = false; p.CanQuery = false end)
		end
	end
	local function unhideBox(s)
		if not s.hidden then return end
		for p, v in pairs(s.hidden) do
			if p.Parent then pcall(function() p.Transparency = v[1]; p.CanCollide = v[2]; p.CanTouch = v[3]; p.CanQuery = v[4] end) end
		end
		s.hidden = nil
	end
	local function addSpawner(cfg)
		local model = cfg.Parent
		if not (model and model:IsA("Model")) or spawnerOf[model] then return end
		local key = engine.co:keyOf(model)
		if not key then return end
		local s = { model = model, cfg = cfg, key = key, id = idFor(key), conns = {}, box = nil, boxF = nil }
		s.box = model:FindFirstChild("Pushbox")
		s.conns[#s.conns + 1] = model.ChildAdded:Connect(function(child)
			if child.Name ~= "Pushbox" then return end
			unhideBox(s)
			s.box = child
			s.boxF = nil
			if cur.on and cur.data then
				if cur.rec and #cur.data > 0 then
					s.boxF = #cur.data
					addEvent(cur.data[#cur.data], { 3, s.id, 1 })
					local I = index(cur.data)
					if not I.firstSpawn[s.id] or I.firstSpawn[s.id] > s.boxF then I.firstSpawn[s.id] = s.boxF end
				elseif cur.mode == 3 then
					s.boxF = cur.f
				end
			end
		end)
		spawnerOf[model] = s
		spawners[#spawners + 1] = s
		s.conns[#s.conns + 1] = model.AncestryChanged:Connect(function()
			if model:IsDescendantOf(workspace) then return end
			for _, c in ipairs(s.conns) do c:Disconnect() end
			spawnerOf[model] = nil
			for i = #spawners, 1, -1 do if spawners[i] == s then table.remove(spawners, i) end end
		end)
	end
	-- a spawn (or "there at the start") of this spawner is saved on frame f or before
	local function spawnedBy(data, s, f)
		local first = index(data).firstSpawn[s.id]
		return first ~= nil and first <= f
	end
	local function boxesAt(data, f)
		for _, s in ipairs(spawners) do
			if s.box and not s.box.Parent then s.box, s.boxF = nil, nil end
			if s.box and s.boxF and s.boxF > f and not spawnedBy(data, s, f) then hideBox(s) else unhideBox(s) end
		end
	end

	-- --------------------------------------------------------------------------------------------- character forces
	local FORCE = { LinearVelocity = true, VectorForce = true, AngularVelocity = true, AlignPosition = true,
		AlignOrientation = true, LineForce = true, Torque = true, BodyVelocity = true, BodyForce = true, BodyThrust = true,
		BodyPosition = true, BodyGyro = true, BodyAngularVelocity = true }
	local forces = setmetatable({}, { __mode = "k" }) -- force -> frame it was added on (recording) or false
	local charConn
	local function watchCharacter(ch)
		if charConn then charConn:Disconnect(); charConn = nil end
		if not ch then return end
		charConn = ch.DescendantAdded:Connect(function(d)
			if not FORCE[d.ClassName] then return end
			if cur.on and cur.rec and cur.data then forces[d] = #cur.data else forces[d] = false end
			if cur.on and cur.mode == 3 then pcall(function() d.Enabled = false end) end
		end)
	end

	-- --------------------------------------------------------------------------------------------- finding objects
	local CONFIGS = { BeatBlockConfiguration = addBeat, TurretConfiguration = addTurret, PushboxSpawnConfiguration = addSpawner,
		BouncePadConfiguration = addFx, LauncherConfiguration = addFx }
	local TAGS = { ["CO_Visual/BeatBlock"] = addBeat, ["CO_Interactables/Turret"] = addTurret,
		["CO_Interactables/PushboxSpawn"] = addSpawner, ["CO_Interactables/BouncePad"] = addFx,
		["CO_Interactables/JumpLauncher"] = addFx }

	local function consider(inst, kitTables)
		local add = CONFIGS[inst.Name]
		if not add and CS then
			for tag, f in pairs(TAGS) do
				if inst:HasTag(tag) then add = f break end
			end
		end
		if add then
			if add == addBeat then add(inst, kitTables) else add(inst) end
		end
	end

	local function scanAll()
		local kitTables = kitBeatTables()
		local seen = {}
		if CS then
			for tag in pairs(TAGS) do
				local ok, list = pcall(CS.GetTagged, CS, tag)
				if ok then
					for _, inst in ipairs(list) do
						if inst:IsDescendantOf(workspace) and not seen[inst] then seen[inst] = true; consider(inst, kitTables) end
					end
				end
			end
		end
		local cp = workspace:FindFirstChild("ClientParts")
		for _, d in ipairs((cp or workspace):GetDescendants()) do
			if CONFIGS[d.Name] and not seen[d] then seen[d] = true; consider(d, kitTables) end
		end
	end

	-- --------------------------------------------------------------------------------------------- the frame
	local enabled = false

	local function release()
		if cur.on then
			cur.on = false
			for _, g in ipairs(beats) do g.driving = false; g.lastKey = nil; g.lastCycle = nil end
			hideAllBullets()
			for _, s in ipairs(spawners) do unhideBox(s) end
			unmuteAll()
		end
		replayedTo = nil
	end
	KO.Release = release

	function KO.Invalidate()
		idx.valid = false
	end

	-- every PreRender after the frame was recorded. mode: 1 Idle, 2 Create, 3 Test; f / t: the frame shown and
	-- its TAS time (testing: the playback time); rec: frame f is being recorded now
	function KO.Frame(mode, data, f, t, rec)
		cur.mode, cur.data, cur.f, cur.t, cur.rec = mode, data, f, t, rec
		if not enabled or (mode ~= 2 and mode ~= 3) or not data then release() return end
		if rec and data.KitVersion == nil then data.KitVersion = KO.VersionOf(data) end
		if KO.VersionOf(data) < 1 or not engine.settings:on("syncKitObjects") then release() return end
		if not cur.on then
			cur.on = true
			for _, g in ipairs(beats) do mute(g.ding); g.dirty = true end
			for _, tt in ipairs(turrets) do mute(tt.fireSnd) end
			replayedTo = nil
		end
		local advancing = rec or (mode == 3)
		if rec and #data == 1 then
			-- a box that is already there when the TAS starts (so it isn't hidden before a later spawn)
			for _, s in ipairs(spawners) do
				if s.box and s.box.Parent and not spawnedBy(data, s, 1) then
					addEvent(data[1], { 3, s.id, 0 })
					index(data).firstSpawn[s.id] = 1
				end
			end
		end
		beatStep(t, advancing)
		showBullets(data, f, t)
		boxesAt(data, f)
		if mode == 3 then replayEvents(data, f) end
	end

	-- every Heartbeat while recording, after the frame got its character state: the bullets' hits
	function KO.AfterPhysics(data, n)
		if not (enabled and cur.on and cur.rec and data and data[n]) then return end
		turretHits(data, n)
	end

	-- before the physics step and at the end of the render step: what the kit (or anything else) wrote since
	-- is undone. Only groups a write touched since are looked at (their change signals mark them dirty; Roblox
	-- fires those signals a little later, still before the next render step / physics step)
	function KO.Reassert()
		if not (enabled and cur.on) or #beats == 0 then return end
		beatStep(cur.t, false)
	end

	-- unpausing at frame f: forces a kit script put on the character after f belong to the cut frames
	function KO.Unpause(data, f)
		for d, fr in pairs(forces) do
			if fr and fr > f then
				forces[d] = nil
				pcall(function() d:Destroy() end)
			end
		end
		idx.valid = false
	end

	-- ------------------------------------------------------------------------------------- save / load
	function KO.Export(frames)
		local used = {}
		for fi = 1, #frames do
			local fr = frames[fi]
			if fr.KE then
				for _, e in ipairs(fr.KE) do
					if e[1] == 1 or e[1] == 3 or e[1] == 4 then used[e[2]] = true end
				end
			end
		end
		local keys = {}
		for id in pairs(used) do keys[#keys + 1] = { id = id, key = reg.idToKey[id] or "" } end
		table.sort(keys, function(a, b) return a.id < b.id end)
		return { version = KO.VersionOf(frames), keys = keys }
	end
	-- ids inside a file belong to the session that saved it: translate them to this session's
	function KO.Import(frames, kit)
		if not kit then frames.KitVersion = 0 return end
		frames.KitVersion = kit.version or 0
		local map = {}
		for _, k in ipairs(kit.keys or {}) do map[k.id] = idFor(k.key) end
		for fi = 1, #frames do
			local fr = frames[fi]
			if fr.KE then
				for _, e in ipairs(fr.KE) do
					if (e[1] == 1 or e[1] == 3 or e[1] == 4) and map[e[2]] then e[2] = map[e[2]] end
				end
			end
		end
		idx.valid = false
	end

	function KO.Counts()
		local live = 0
		for _ in pairs(shown) do live = live + 1 end
		return #beats, #turrets, #spawners, live
	end

	function KO.Enable()
		if enabled then return end
		enabled = true
		pcall(scanAll)
	end
	function KO.Disable()
		if not enabled then return end
		release()
		enabled = false
	end

	function KO.StartHooks()
		engine.life:connect(workspace.DescendantAdded, function(d)
			if CONFIGS[d.Name] then
				task.defer(function()
					if d.Parent then pcall(consider, d, (d.Name == "BeatBlockConfiguration") and kitBeatTables() or nil) end
				end)
			end
		end)
		local lp = Players.LocalPlayer
		if lp and lp.Character then watchCharacter(lp.Character) end
		if lp then engine.life:connect(lp.CharacterAdded, watchCharacter) end
		engine.life:own(function()
			KO.Disable()
			if charConn then charConn:Disconnect() end
			for _, g in ipairs(beats) do for _, c in ipairs(g.conns) do c:Disconnect() end end
			for _, t in ipairs(turrets) do for _, c in ipairs(t.conns) do c:Disconnect() end end
			for _, s in ipairs(spawners) do for _, c in ipairs(s.conns) do c:Disconnect() end end
			for _, o in ipairs(fxObjects) do for _, c in ipairs(o.conns) do c:Disconnect() end end
			if holder then pcall(function() holder:Destroy() end) end
		end)
	end
end

-- ------------------------------------------------------------------------------------------------ the plugin
local KO = KitObjects
local KitObjectsPlugin = { name = "kitobjects", order = 61 }
KitObjectsPlugin.__index = KitObjectsPlugin

function KitObjectsPlugin.new(E)
	engine = E
	local self = setmetatable({ E = E, KO = KO, framesOf = framesOf }, KitObjectsPlugin)
	E.tl:addColumn("v2KE", "list", 1, { key = "KE", keep = true })
	KO.StartHooks()
	E.life:own(E.settings:changed("syncKitObjects", function(v)
		if v ~= 0 then KO.Enable() else KO.Disable() end
	end))
	if E.settings:on("syncKitObjects") then KO.Enable() end
	return self
end

-- every PreRender (the engine calls it by name): mode 1 Idle, 2 Create, 3 Test; f / t the frame shown and its TAS
-- time (Test: the playback time); rec: frame f is being recorded
function KitObjectsPlugin:frame(mode, tl, f, t, rec) KO.Frame(mode, framesOf(tl), f, t, rec) end
function KitObjectsPlugin:onPreSimulation() KO.Reassert() end
function KitObjectsPlugin:lateRender() KO.Reassert() end
function KitObjectsPlugin:onAfterPhysics(tl, n) KO.AfterPhysics(framesOf(tl), n) end
function KitObjectsPlugin:onUnpause(tl, n) KO.Unpause(framesOf(tl), n) end
function KitObjectsPlugin:onDataChanged() KO.Invalidate() end
-- (Idle, the end of a Test, a new run: the kit gets its objects and sounds back, V2 KitObjects.Release)
function KitObjectsPlugin:onRelease() KO.Release() end
function KitObjectsPlugin:onSave(tl)
	tl.meta = tl.meta or {}
	tl.meta.v2kit = KO.Export(framesOf(tl))
	tl.meta.kitVersion = KO.VersionOf(framesOf(tl))
end
-- a run loaded from a file: its kit table translated to this session's ids (a V2 file without one, older than
-- V2.38.14, comes with kitVersion 0 from the reader: the kit's own behaviour)
function KitObjectsPlugin:onLoaded(tl)
	local meta = tl.meta or {}
	if type(meta.v2kit) == "table" then KO.Import(framesOf(tl), meta.v2kit) end
	KO.Invalidate()
end
function KitObjectsPlugin:versionOf(tl) return KO.VersionOf(framesOf(tl)) end
function KitObjectsPlugin:counts() return KO.Counts() end

return KitObjectsPlugin
