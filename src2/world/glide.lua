-- ================================================================================================
--  GLIDE  (HappaTAS 3 world plugin, order 58, "Glide Manipulation" / "Glide Chance (%)"): decides whether a
--  side-edge glide happens.
--  What a glide is (measured live 2026-11-13, R6, at a 16-stud cylinder, from a recorded run: built-in shift lock,
--  W held, A / D switched, falling 120 - 190 stud/s along the part): the torso box is the character's colliding
--  box (2 x 2 x 1). With shift lock Roblox turns the humanoid toward the camera through physics
--  (UserGameSettings.RotationType = CameraRelative), and turning while pressed against a part swings the torso's
--  vertical corner into it. A physics step that STARTS with the torso 0.10 - 0.22 studs inside the part glides
--  now and then (14 of 78 steps, random from step to step); one that starts 0.06 - 0.09 deep never did (0 of 24;
--  0 of 352 below 0.10 in other runs). A glide stops the fall or slows it (-125 -> +10 down to -125 -> -112),
--  throws the character outward (1 - 36 stud/s) and tilts it (3 - 60 degrees). Which steps start that deep
--  depends on the frame rate and on the parts' exact positions: the "luck".
--  So, on a frame whose physics runs, in Idle or while recording, falling in Freefall, R6: the depth of the
--  torso box in the parts it overlaps is measured (exact shapes, GetPartsInPart, along the part's outward
--  horizontal normal), the chance is rolled once per part the character hugs, and:
--    * no glide wanted: a torso deeper than SAFE_ABOVE is moved out to SAFE; a glide Roblox makes anyway (live it
--      also came from outside the band) is undone after the step: the fall goes on, the tilt and spin are taken back
--    * a glide wanted: the torso is put TARGET deep; if the step doesn't glide, HappaTAS makes the glide: the fall
--      cut to FILL_KEEP of itself, thrown outward at FILL_OUT of the fall speed, tilted outward
--  The run records what happened, so Test plays it back like any other frame.
--  R6 only. The root part's box is the torso's (R6: the same box, RootJoint at no offset).
-- ================================================================================================
local Glide = { name = "glide", order = 58 }
Glide.__index = Glide

local H = 1 / 240
Glide.SAFE = 0.05 -- (studs: no glide wanted, the torso is at most this deep)
Glide.TARGET = 0.15 -- (studs: a glide wanted, the torso is put this deep: the middle of the band that glided)
local SAFE_ABOVE = 0.08 -- (deeper than this is moved out: 0.06 - 0.09 never glided live)
local MIN_FALL = 20 -- (stud/s: slower falls are left alone)
local SAME_HUG = 0.4 -- (s: the same part touched again within this is the same hug, one roll)
local REACH = 0.6 -- (studs: the deepest depth measured)
local FILL_KEEP = 0.09 -- (a made glide keeps this much of the fall: live -132 -> -13, -186 -> -14)
local FILL_OUT = 0.17 -- (... and throws outward at this much of it: live 22 of 132, 31 of 186)
local FILL_SPIN = 12 -- (rad/s: the tilt outward, live peaks 33 - 59 degrees within a few frames)

function Glide.new(E)
	local self = setmetatable({ E = E, rng = Random.new(), last = nil, pend = nil, hug = nil }, Glide)
	local find = OverlapParams.new()
	find.FilterType = Enum.RaycastFilterType.Exclude
	find.RespectCanCollide = true
	self.find = find
	local only = OverlapParams.new()
	only.FilterType = Enum.RaycastFilterType.Include
	self.only = only
	if E.pipe then
		E.life:own(E.pipe:add("PostSimulation", 60, "glide.check", function(dt) self:check(dt) end, "glide"))
	end
	-- (a changed setting is a new roll)
	E.life:own(E.settings:changed("glideChance", function() self.hug = nil end))
	E.life:own(E.settings:changed("glideManipulation", function() self.hug = nil end))
	E.life:own(function()
		if self.probe then pcall(function() self.probe:Destroy() end) end
	end)
	return self
end

-- Idle, or Create while recording (the physics runs there); never in Test
function Glide:active()
	local E = self.E
	if not E.settings:on("glideManipulation") then return false end
	if E.mode == 1 then return true end
	return E.mode == 2 and not E.paused
end

-- false on a Frame Step step that is held (no physics this frame)
function Glide:stepRuns()
	local t = self.E.time
	local fs = t and t.SH and t.SH.FS
	return not (fs and fs.on and fs.plan == false)
end

-- a box like the torso, for the overlap checks (never collides, never touched, not seen by other queries)
function Glide:box(size)
	local p = self.probe
	if not (p and p.Parent) then
		p = Instance.new("Part")
		p.Name = "HappaTASGlideProbe"
		p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
		p.Transparency = 1
		p.Parent = workspace.CurrentCamera or workspace
		self.probe = p
	end
	if p.Size ~= size then p.Size = size end
	return p
end

-- the way out of a part, flat: from a round part's axis, else from the nearest point of its box (a box the torso's
-- middle is inside: its nearest side face)
local function outward(part, at)
	local pc = part.CFrame
	local isRound = part:IsA("Part") and (part.Shape == Enum.PartType.Cylinder or part.Shape == Enum.PartType.Ball)
	local axis = pc.RightVector
	if isRound and (part.Shape == Enum.PartType.Ball or math.abs(axis.Y) > 0.9) then
		local d = Vector3.new(at.X - pc.X, 0, at.Z - pc.Z)
		return d.Magnitude > 1e-4 and d.Unit or nil, true
	end
	local lp = pc:PointToObjectSpace(at)
	local hs = part.Size / 2
	local near = Vector3.new(math.clamp(lp.X, -hs.X, hs.X), math.clamp(lp.Y, -hs.Y, hs.Y), math.clamp(lp.Z, -hs.Z, hs.Z))
	local d = at - pc:PointToWorldSpace(near)
	d = Vector3.new(d.X, 0, d.Z)
	if d.Magnitude > 1e-4 then return d.Unit, isRound end
	-- (inside: the side face closest to the middle)
	local best, bestGap = nil, math.huge
	for _, f in ipairs({ { pc.RightVector, hs.X, lp.X }, { pc.LookVector, hs.Z, -lp.Z }, { pc.UpVector, hs.Y, lp.Y } }) do
		local flat = Vector3.new(f[1].X, 0, f[1].Z)
		if flat.Magnitude > 0.7 then
			local gap = f[2] - math.abs(f[3])
			if gap < bestGap then
				bestGap = gap
				best = flat.Unit * ((f[3] >= 0) and 1 or -1)
			end
		end
	end
	return best, isRound
end

-- how deep the box (at cf) is in `part` along `n`: the least move out along n that clears it (0 = touching or clear)
function Glide:depth(part, cf, size, n)
	local probe = self:box(size)
	self.only.FilterDescendantsInstances = { part }
	local function hits(s)
		probe.CFrame = cf + n * s
		return #workspace:GetPartsInPart(probe, self.only) > 0
	end
	if not hits(0) then return 0 end
	if hits(REACH) then return REACH end
	local lo, hi = 0, REACH
	for _ = 1, 12 do
		local mid = (lo + hi) / 2
		if hits(mid) then lo = mid else hi = mid end
	end
	return hi
end

-- the roll for a part, kept for the whole hug
function Glide:decide(part)
	local now = os.clock()
	local hug = self.hug
	if hug and hug.part == part and now - hug.t < SAME_HUG then
		hug.t = now
		return hug.want
	end
	local chance = math.clamp(tonumber(self.E.settings:get("glideChance")) or 50, 0, 100)
	local want = chance >= 100 or (chance > 0 and self.rng:NextNumber(0, 100) < chance)
	self.hug = { part = part, t = now, want = want, done = false }
	return want
end

-- PreSimulation (before the frame is filled): the torso's depth where the roll wants it
function Glide:onPreSimulation()
	self.pend = nil
	if not self:active() or not self:stepRuns() then return end
	local ch = self.E.char
	local hum, root, model = ch.hum, ch.hrp, ch.model
	if not (hum and root and model and root.Parent) or root.Anchored then return end
	if hum.RigType ~= Enum.HumanoidRigType.R6 or hum:GetState() ~= Enum.HumanoidStateType.Freefall then return end
	local v = root.AssemblyLinearVelocity
	if v.Y > -MIN_FALL then return end
	local size = (ch.torso and ch.torso.Size) or root.Size
	local cf = root.CFrame
	-- the parts the torso touches (a hair wider: touching counts)
	local probe = self:box(size + Vector3.new(0.02, 0, 0.02))
	probe.CFrame = cf
	self.find.FilterDescendantsInstances = { model, probe }
	local parts = workspace:GetPartsInPart(probe, self.find)
	if #parts == 0 then return end
	-- the part it is deepest in
	local best
	for _, part in ipairs(parts) do
		if part.CanCollide then
			local n, round = outward(part, cf.Position)
			if n then
				local d = self:depth(part, cf, size, n)
				if not best or d > best.d then best = { part = part, n = n, d = d, round = round } end
			end
		end
	end
	if not best then return end
	local want = self:decide(best.part)
	local hug = self.hug
	if hug.done then return end
	local shift = 0
	if want then
		shift = best.d - Glide.TARGET
	elseif best.d > SAFE_ABOVE then
		shift = best.d - Glide.SAFE
	end
	if math.abs(shift) > 1e-6 then root.CFrame = cf + best.n * shift end
	self.last = { part = best.part, want = want, depth = best.d, shift = shift, filled = false, undone = false, glided = nil }
	self.pend = { want = want, n = best.n, v = v, w = root.AssemblyAngularVelocity, g = workspace.Gravity,
		last = self.last, hug = hug }
end

-- PostSimulation: did Roblox glide? A wanted one it didn't make is made; an unwanted one is undone
function Glide:check(dt)
	local p = self.pend
	self.pend = nil
	if not p then return end
	local root = self.E.char.hrp
	if not (root and root.Parent) then return end
	dt = tonumber(dt) or H
	local v = root.AssemblyLinearVelocity
	local freeVy = p.v.Y - p.g * dt
	local fall = -freeVy
	local glided = v.Y > freeVy + 12 and v.Y > freeVy + 0.1 * fall
	p.last.glided = glided
	if glided == p.want then
		if glided then p.hug.done = true end
		return
	end
	local cf = root.CFrame
	local flatLook = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if not p.want then
		-- (undone: the fall goes on as if the step hadn't glided, upright, the spin from before)
		root.AssemblyLinearVelocity = Vector3.new(p.v.X, freeVy, p.v.Z)
		root.AssemblyAngularVelocity = p.w
		if flatLook.Magnitude > 1e-4 then root.CFrame = CFrame.lookAt(cf.Position, cf.Position + flatLook) end
		p.last.undone = true
		p.last.glided = false
		return
	end
	-- (made: the fall cut, thrown outward, tilted outward)
	local into = Vector3.new(v.X, 0, v.Z):Dot(p.n)
	local horiz = Vector3.new(v.X, 0, v.Z) - p.n * math.min(0, into)
	root.AssemblyLinearVelocity = horiz + p.n * (FILL_OUT * fall) + Vector3.new(0, freeVy * FILL_KEEP, 0)
	root.AssemblyAngularVelocity = Vector3.yAxis:Cross(p.n) * FILL_SPIN
	p.last.filled = true
	p.last.glided = true
	p.hug.done = true
end

return Glide
