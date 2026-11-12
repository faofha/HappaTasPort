-- ================================================================================================
--  DIAGNOSTICS  (HappaTAS 3): a read-only text report to share when the physics acts differently on
--  another PC (Settings > Copy diagnostics, or getgenv().__HappaTAS3.Diagnostics()): the version, the
--  executor and which of its functions exist, the last ~10 s of frame times and physics steps (Roblox
--  steps physics in whole 1/240 s steps), every setting, the speed hack / coyote state right now, a census
--  of the world (the parts and constraints a recording here can't follow exactly) and the last errors. It only
--  reads: nothing here writes to the character or the world.
-- ================================================================================================
local CONFIG = import("config")
local Env = import("platform/env")

local Diag = {}
local N = 4096 -- (samples kept per ring: ~17 s at 240 FPS)
local WINDOW = 10
local STEP = 1 / 240
local FUNCS = { "writefile", "readfile", "isfile", "isfolder", "makefolder", "listfiles", "delfile", "appendfile",
	"delfolder", "gethui", "cloneref", "getgc", "filtergc", "getconnections", "hookfunction", "restorefunction",
	"iscclosure", "getloadedmodules", "setreadonly", "isreadonly", "isactive", "keypress", "keyrelease",
	"mousemoveabs", "mousemoverel", "mousescroll", "getcustomasset", "identifyexecutor", "envOf", "setclipboard" }

-- the world, counted once for the report: every part, the ones that collide, the loose ones among those (held
-- with the character in slow motion; in fast motion they run on real time), the constraints and movers by class,
-- and the meshes and unions that collide (the speed hack doesn't need their shape; nothing a script could read)
function Diag.census()
	local c = { parts = 0, collide = 0, loose = 0, meshes = 0, constraints = {} }
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") then
			c.parts = c.parts + 1
			if d.CanCollide then
				c.collide = c.collide + 1
				if not d.Anchored then c.loose = c.loose + 1 end
				if d:IsA("MeshPart") or d:IsA("UnionOperation") then c.meshes = c.meshes + 1 end
			end
		elseif d:IsA("Constraint") or d:IsA("BodyMover") then
			c.constraints[d.ClassName] = (c.constraints[d.ClassName] or 0) + 1
		end
	end
	return c
end

local function ring() return { t = table.create(N, 0), v = table.create(N, 0), i = 0, n = 0 } end
local function push(r, t, v)
	local i = r.i % N + 1
	r.t[i], r.v[i], r.i = t, v, i
	if r.n < N then r.n = r.n + 1 end
end
-- the samples of the last WINDOW seconds, oldest first
local function recent(r, now)
	local out = {}
	for k = r.n - 1, 0, -1 do
		local i = (r.i - k - 1) % N + 1
		if now - r.t[i] <= WINDOW then out[#out + 1] = r.v[i] end
	end
	return out
end

function Diag.start(E)
	local d = { frames = ring(), steps = ring() }
	E.diag = d
	E.pipe:add("Heartbeat", 95, "diagnostics.frame", function(dt) push(d.frames, os.clock(), dt) end, "diagnostics")
	E.pipe:add("PostSimulation", 95, "diagnostics.step", function(dt) push(d.steps, os.clock(), dt) end, "diagnostics")
end

local function fmt(v)
	if type(v) == "number" then return string.format("%.6g", v) end
	return tostring(v)
end

function Diag.report(E)
	local d = E.diag
	local now = os.clock()
	local L = {}
	local function add(s) L[#L + 1] = s end
	add("HappaTAS diagnostics")
	add("Version: " .. CONFIG.VERSION .. "   Executor: " .. tostring(Env.executor) .. "   Date: " .. os.date("%Y-%m-%d %H:%M:%S"))
	add("Interface: " .. tostring(E.settings:get("interface")) .. "   Touch: "
		.. tostring(game:GetService("UserInputService").TouchEnabled) .. "   Place: " .. tostring(game.PlaceId))
	local have, miss = {}, {}
	for _, name in ipairs(FUNCS) do
		if Env[name] then have[#have + 1] = name else miss[#miss + 1] = name end
	end
	add("Executor functions present: " .. table.concat(have, ", "))
	add("Executor functions missing: " .. (#miss > 0 and table.concat(miss, ", ") or "none"))
	for _, n in ipairs(Env.notes) do add("  note: " .. n) end
	-- frame times
	local ft = d and recent(d.frames, now) or {}
	local sum, worst = 0, 0
	for _, v in ipairs(ft) do
		sum = sum + v
		if v > worst then worst = v end
	end
	if #ft > 0 then
		add(string.format("Frames (last %d s): %d, FPS %.1f, average %.2f ms, worst %.2f ms", WINDOW, #ft, #ft / math.max(sum, 1e-6),
			1000 * sum / #ft, 1000 * worst))
	else
		add("Frames: no samples")
	end
	if Env.getfpscap then
		local ok, v = pcall(Env.getfpscap)
		if ok then add("FPS cap: " .. fmt(v)) end
	end
	-- physics steps per PostSimulation
	local st = d and recent(d.steps, now) or {}
	local hist, whole, offMax, steps = {}, 0, 0, 0
	for _, v in ipairs(st) do
		local n = v / STEP
		local r = math.floor(n + 0.5)
		local off = math.abs(n - r)
		if off < 1e-3 then whole = whole + 1 end
		if off > offMax then offMax = off end
		steps = steps + n
		local key = off < 1e-3 and tostring(r) or string.format("%.2f", n)
		hist[key] = (hist[key] or 0) + 1
	end
	if #st > 0 then
		local h = {}
		for k, c in pairs(hist) do h[#h + 1] = k .. " step(s) x" .. c end
		table.sort(h)
		add(string.format("Physics (last %d s): %d PostSimulation events, %.3f steps each on average, %.1f %% whole 1/240 s steps (largest off: %.4f of a step)",
			WINDOW, #st, steps / #st, 100 * whole / #st, offMax))
		add("  " .. table.concat(h, ", "))
	else
		add("Physics: no samples")
	end
	-- the engine right now
	local mode = ({ "Idle", "Create", "Test" })[E.mode or 1] or tostring(E.mode)
	add("Mode: " .. mode .. "   paused: " .. tostring(E.paused) .. "   frames: " .. tostring(E.tl:count()))
	local SH = E.time and E.time.SH
	if SH then
		local FS = SH.FS or {}
		add("Speed hack now: wanted " .. fmt(SH.Wanted()) .. ", physics scale " .. fmt(SH.scale) .. ", animation rate " .. fmt(SH.anim)
			.. ", Frame Step " .. (FS.on and ("on (" .. fmt(FS.s) .. ")") or "off"))
		local cy = SH.Humanoid and SH.Humanoid.coyote
		if cy then
			add("Coyote now: enforcing " .. tostring(cy.enforce == true) .. ", restored " .. tostring(cy.restored)
				.. ", off floor " .. fmt(cy.off) .. " s, jumped " .. tostring(cy.jumped) .. ", Jumping disabled by it "
				.. tostring(cy.disabled) .. ", Freefall disabled by it " .. tostring(cy.noFall))
		end
	end
	local hum = E.char and E.char.hum
	if hum then
		local ok, s = pcall(function()
			return string.format("Humanoid: state %s, WalkSpeed %s, JumpPower %s, Jumping enabled %s, Freefall enabled %s, Gravity %s",
				hum:GetState().Name, fmt(hum.WalkSpeed), fmt(hum.JumpPower), tostring(hum:GetStateEnabled(Enum.HumanoidStateType.Jumping)),
				tostring(hum:GetStateEnabled(Enum.HumanoidStateType.Freefall)), fmt(workspace.Gravity))
		end)
		if ok then add(s) end
	end
	-- the world
	local okC, c = pcall(Diag.census)
	if okC then
		add("World: " .. c.parts .. " parts, " .. c.collide .. " collide, " .. c.loose .. " of them loose (held with the character in slow motion)")
		local list = {}
		for class, n in pairs(c.constraints) do list[#list + 1] = class .. " x" .. n end
		table.sort(list)
		add("  Constraints and movers: " .. (#list > 0 and table.concat(list, ", ") or "none"))
		add("  Meshes and unions that collide: " .. c.meshes)
	end
	-- settings
	add("Settings:")
	local keys = {}
	for k in pairs(E.settings.values) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do add("  " .. k .. " = " .. fmt(E.settings.values[k])) end
	-- errors
	local errs = E.errs
	local counts = {}
	for src, c in pairs(errs.counts) do counts[#counts + 1] = src .. " x" .. c end
	table.sort(counts)
	add("Errors per source: " .. (#counts > 0 and table.concat(counts, ", ") or "none"))
	for _, m in ipairs(errs.last) do add("  " .. m) end
	return table.concat(L, "\n")
end

-- copies the report (or saves it in the place folder when there is no clipboard); returns the status text
function Diag.share(E)
	local text = Diag.report(E)
	if Env.setclipboard and pcall(Env.setclipboard, text) then return "Diagnostics copied to the clipboard" end
	local path = "HappaTasPort/diagnostics-" .. os.date("%Y%m%d-%H%M%S") .. ".txt"
	E.files:makeFolder("HappaTasPort")
	if E.files:write(path, text) then return "Diagnostics saved to " .. path end
	return "Diagnostics: no clipboard and no file functions"
end

return Diag
