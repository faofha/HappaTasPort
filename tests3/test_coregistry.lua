-- ================================================================================================
-- HappaTAS 3, phase 4: the client object registry (keys, candidates, the scan, watched parts, change
-- listeners, holding and releasing; V2.38.17 p13_clientobjects.lua 42-519)
-- ================================================================================================
check(boot(3), "boots")
local Registry = __T3("world/co/registry")

local statuses = {}
local function newReg() return Registry.new(function(t) statuses[#statuses + 1] = t end) end
local function part(name, parent, anchored)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = anchored ~= false
	p.Parent = parent
	return p
end
local function folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent or workspace
	return f
end
local PROPS = { "Transparency", "CanCollide", "Color", "Size", "Material", "Anchored" }
local function listeners(p)
	local n = 0
	for _, k in ipairs(PROPS) do n = n + #p:GetPropertyChangedSignal(k)._conns end
	return n
end
local function waitReady(R)
	local g = 0
	while not R:isReady() and g < 600 do M.step(1 / 60); g = g + 1 end
	return R:isReady()
end

section("keys")
do
	local R = newReg()
	local f = folder("Keys")
	local a = part("P", f)
	local b = part("P", f)
	local odd = part("a/b#c", f)
	eq(R:keyOf(a), "Keys/P", "the first sibling keeps its name")
	eq(R:keyOf(b), "Keys/P#2", "the second sibling of that name gets #2")
	eq(R:keyOf(odd), "Keys/a_b_c", "/ and # become _")
	local loose = Instance.new("Part")
	eq(R:keyOf(loose), nil, "nil outside workspace")
	part("Q", f)
	eq(R:keyOf(b), "Keys/P#2", "stable after another sibling is added")
	eq(R:idForKey("Keys/P"), 1, "first id 1")
	eq(R:idForKey("Keys/P#2", 7), 7, "a preferred id is taken when free")
	eq(R:idForKey("Keys/Q", 7), 8, "a taken preferred id gives the next one")
	eq(R:idForKey("Keys/P"), 1, "the same key, the same id")
	f:Destroy()
end

section("candidates")
do
	local R = newReg()
	local plain = folder("Plain")
	eq(R:isCandidate(part("Floor", plain)), false, "an anchored part in a plain folder is not")
	check(R:isCandidate(part("Box", plain, false)), "an unanchored part is")
	local withC = part("Hinge", plain)
	Instance.new("HingeConstraint").Parent = withC
	check(R:isCandidate(withC), "a part with a Constraint")
	local attr = part("B", plain)
	attr:SetAttribute("Beat", 1)
	check(R:isCandidate(attr), "a part with the kit's Beat attribute")
	local vf = part("V", plain)
	Instance.new("Configuration").Name = "x"
	local cfg = Instance.new("Configuration"); cfg.Name = "VanisherConfiguration"; cfg.Parent = vf
	check(R:isCandidate(vf), "a part with a VanisherConfiguration")
	for _, name in ipairs({ "ClientObjects", "Spinners", "Beat Blocks", "Morphers", "Light Changers", "Fading Platforms" }) do
		check(R:isCandidate(part("X", folder(name, plain))), "a part in a " .. name .. " folder")
	end
	check(R:isCandidate(part("MovingPlatform", plain)), "a name hint (Moving)")
	check(R:isCandidate(part("X", folder("Obstacle 3", plain))), "a folder named like an obstacle")
	local char = Instance.new("Model"); char.Name = "Someone"; char.Parent = plain
	Instance.new("Humanoid").Parent = char
	eq(R:isCandidate(part("Arm", char, false)), false, "a part inside a character is not")
	local ign = part("Ign", plain, false)
	ign:SetAttribute("HappaTASIgnore", true)
	eq(R:isCandidate(ign), false, "HappaTASIgnore")
	eq(R:isCandidate(workspace.Terrain), false, "Terrain")
	plain:Destroy()
end

section("the scan")
do
	local f = folder("ClientObjects")
	for i = 1, 2000 do part("P" .. i, f) end
	local R = newReg()
	statuses = {}
	R:enable()
	eq(R:isReady(), false, "not ready at once")
	check(waitReady(R), "ready after some frames")
	eq(R.nRegistered, 2000, "every part registered")
	eq(statuses[#statuses], "Client objects ready (2000 parts)", "status")
	check(statuses[1] == "Scanning client objects...", "scanning status first")
	R:disable()
	f:Destroy()
end

section("watched anchored parts, change listeners, removal, limits")
do
	local plain = folder("Plain2")
	local floorP = part("Floor", plain)
	local cof = folder("ClientObjects")
	local a = part("A", cof)
	local R = newReg()
	R:enable()
	check(waitReady(R), "ready")
	eq(R.ids[floorP], nil, "an anchored plain part isn't registered")
	check(R.watchConns[floorP] ~= nil, "but it is watched")
	floorP.Anchored = false
	check(R.ids[floorP] ~= nil, "un-anchored: registered")
	eq(R.watchConns[floorP], nil, "and no longer watched")
	eq(listeners(a), 6, "a registered part has 6 change listeners")
	local s = R.S[R.ids[a]]
	s.pd = false
	a.Transparency = 0.5
	eq(s.pd, true, "a property change marks the part")
	a.Anchored = false
	eq(s.an, false, "Anchored is kept in s.an")
	local id = R.ids[a]
	a.Parent = nil
	eq(R.ids[a], nil, "removed: unregistered")
	eq(R.parts[id], nil, "its part")
	eq(R.S[id], nil, "and its state")
	local b = part("B", cof)
	check(R.ids[b] ~= nil, "a part added later is registered")
	R.MAX_REG = R.nRegistered
	local c = part("C", cof)
	eq(R.ids[c], nil, "no more than MaxRegistered")
	R:disable()
	eq(listeners(b), 0, "disable removes every listener")
	eq(#workspace.DescendantAdded._conns, 0, "and the workspace connections")
	eq(R.nWatched, 0, "and the watches")
	plain:Destroy()
	cof:Destroy()
end

section("holding and releasing")
do
	local cof = folder("ClientObjects")
	local p = part("Mover", cof, false)
	p.AssemblyLinearVelocity = Vector3.new(3, 0, 0)
	local R = newReg()
	R:enable()
	check(waitReady(R), "ready")
	local id = R.ids[p]
	check(R:ensureAnchored(p, R.S[id]), "anchored by HappaTAS")
	eq(p.Anchored, true, "held")
	eq(R:ensureAnchored(p, R.S[id]), false, "only once")
	R:releasePart(id)
	eq(p.Anchored, false, "released: as it was")
	eq(p.AssemblyLinearVelocity, Vector3.new(3, 0, 0), "with its velocity")
	R:ensureAnchored(p, R.S[id])
	R:releaseAll()
	eq(p.Anchored, false, "releaseAll lets every part go")
	eq(next(R.orig), nil, "nothing held")
	R:disable()
	cof:Destroy()
end
finish()
