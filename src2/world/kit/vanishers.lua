-- ================================================================================================
--  VANISHERS  (HappaTAS 3, part of Kit Objects, "Sync Kit Objects"): the EToH kit's vanishers (fading parts,
--  Interactables/Vanisher.lua) as functions of TAS time. The kit keeps its own state (the running tween, the
--  vanish / respawn timer, an "active" flag); HappaTAS put back only Transparency and CanCollide, so after going
--  back the fade never went on and in Test the kit's leftover timer jumped the part to vanished (measured live).
--  While recording, HappaTAS sees your character touch a vanisher (the kit's own rule: a box 0.1 bigger than
--  the part) and saves it as a kit event { 5, id, kind } on that frame (kind 1 = touched: Fade / Blink;
--  2 / 3 = contact on / off: Constant). Each frame (recording, paused on any frame, Test) the vanisher's
--  Transparency, CanCollide, CanTouch and outline come from those events and its configuration, and are
--  written over the kit's own writes. Modes Fade, Blink and Constant; Shrink and button-activated vanishers
--  are left to the kit. Only for runs with the kit rules version 2 (older runs keep the kit's behaviour).
-- ================================================================================================
local Env = import("platform/env")

local TweenService = Env.svc("TweenService")
local Players = Env.svc("Players")

local Vanishers = {}
local groups, groupOf = {}, {}
local MODES = { Fade = true, Blink = true, Constant = true }
local params = OverlapParams.new()

local function attr(inst, name, def)
	if not inst then return def end
	local v = inst:GetAttribute(name)
	if v == nil then return def end
	return v
end

-- the kit's own normal / touched values per part (each vanisher part's { part, selection, defaults } table):
-- a part found mid-fade or vanished has its normal values there, not on the part (live: a vanisher found
-- vanished kept Transparency 1 as its normal value)
local kitDefaults = nil
function Vanishers.findKitDefaults()
	kitDefaults = {}
	if not Env.filtergc then return end
	local ok, list = pcall(Env.filtergc, "table", { Keys = { "part", "defaults" } })
	if not ok or type(list) ~= "table" then return end
	for _, t in ipairs(list) do
		local p, d = rawget(t, "part"), rawget(t, "defaults")
		if typeof(p) == "Instance" and type(d) == "table" and rawget(d, "DefaultTransparency") ~= nil then kitDefaults[p] = d end
	end
end

-- a vanisher's configuration and its parts' normal / touched values, like the kit works them out
function Vanishers.add(cfg, key, id)
	local obj = cfg.Parent
	if not obj or groupOf[cfg] then return nil end
	local mode = attr(cfg, "VanishMode", "Fade")
	if not MODES[mode] then return nil end
	local tween = cfg:FindFirstChild("TweenConfiguration")
	local invert = attr(cfg, "Invert", false) == true
	local g = { cfg = cfg, key = key, id = id, mode = mode, parts = {},
		time = math.max(1e-3, tonumber(attr(tween, "Time", 1)) or 1),
		style = attr(tween, "Style", Enum.EasingStyle.Quad), dir = attr(tween, "Direction", Enum.EasingDirection.Out),
		respawn = tonumber(attr(cfg, "RespawnTime", 2)) or 2, respawnFade = attr(cfg, "RespawnFade", false) == true,
		blinks = tonumber(attr(cfg, "BlinkCount", 3)) or 3, noRecovery = attr(cfg, "ConstantNoRecovery", false) == true,
		outline = attr(cfg, "OutlineColor", Color3.fromRGB(255, 0, 0)), events = nil, last = nil }
	local list = obj:IsA("BasePart") and { obj } or obj:GetChildren()
	for _, p in ipairs(list) do
		if p:IsA("BasePart") then
			if p:HasTag("ButtonActivated") then return nil end -- (button activated: the kit's. An Activated attribute
			-- alone is normal: live, the test place's Fade vanisher has Activated = false)
			local invisible, ignoreT, ignoreC = p:HasTag("Invisible"), p:HasTag("IgnoreTransparency"), p:HasTag("IgnoreCanCollide")
			local defC, touchC, defT, touchT
			if invisible then defC = false elseif ignoreC then defC = p.CanCollide else defC = not invert end
			if invisible then touchC = false elseif ignoreC then touchC = p.CanCollide else touchC = not defC end
			if invisible then defT = 1 elseif ignoreT then defT = p.Transparency elseif invert then defT = 1 else defT = p.Transparency end
			if ignoreT then touchT = p.Transparency elseif invert then touchT = 0 else touchT = 1 end
			local kd = kitDefaults and kitDefaults[p]
			if kd then
				defT, defC = rawget(kd, "DefaultTransparency"), rawget(kd, "DefaultCanCollide")
				touchT, touchC = rawget(kd, "TouchedTransparency"), rawget(kd, "TouchedCanCollide")
			elseif not p.CanTouch and not invisible and not ignoreT and not invert then
				-- (no kit table and caught vanished: the usual normal values)
				defT, defC, touchC = 0, true, false
			end
			local sel = p:FindFirstChild("VanisherSelectionBox")
			if sel and not sel:IsA("SelectionBox") then sel = nil end
			g.parts[#g.parts + 1] = { part = p, defT = defT, defC = defC, touchT = touchT, touchC = touchC, sel = sel,
				selColor = sel and sel.Color3, selThick = sel and sel.LineThickness or 0.1 }
		end
	end
	if #g.parts == 0 then return nil end
	groupOf[cfg] = g
	groups[#groups + 1] = g
	return g
end

function Vanishers.count() return #groups end
function Vanishers.invalidate() for _, g in ipairs(groups) do g.events = nil end end

local function ease(g, a)
	a = math.clamp(a, 0, 1)
	local ok, v = pcall(TweenService.GetValue, TweenService, a, g.style, g.dir)
	return ok and v or a
end

-- the group's events in TAS time (from the run's kit events), built when the run changed
local function eventsOf(g, data)
	if g.events and g.eventsData == data then return g.events end
	local ev = {}
	for i = 1, #data do
		local fr = data[i]
		local ke = fr.KE
		if ke then
			for _, e in ipairs(ke) do
				if e[1] == 5 and e[2] == g.id then ev[#ev + 1] = { fr.TotalTime, e[3] } end
			end
		end
	end
	g.events, g.eventsData = ev, data
	return ev
end

-- the state at TAS time t: phase "idle", "fade" (a = 0..1 of the way), "gone", "back" (respawn fade, a)
-- and, for Blink, the time into the blinks
local function stateAt(g, data, t)
	local ev = eventsOf(g, data)
	if g.mode == "Constant" then
		-- the touch time goes up while touched, down (Time / RespawnTime per second) while not, the part goes at
		-- Time, comes back RespawnTime later with the touch time 0 (the kit's handleConstantMode)
		local tt, lastT, on, goneAt = 0, 0, false, nil
		local function advance(to)
			if goneAt then
				-- (back with the touch time 0; still touched, it fills again: the recorder saves a contact change
				-- on the first frame after it came back)
				if to >= goneAt + g.respawn then tt, lastT, goneAt = 0, goneAt + g.respawn, nil else return end
			end
			local d = to - lastT
			if d <= 0 then return end
			if on then
				if tt + d >= g.time then goneAt = lastT + (g.time - tt); tt = g.time; lastT = goneAt; return advance(to) end
				tt = tt + d
			elseif not g.noRecovery then
				tt = math.max(0, tt - d * g.time / g.respawn)
			end
			lastT = to
		end
		for _, e in ipairs(ev) do
			if e[1] > t then break end
			advance(e[1])
			if not goneAt then on = e[2] == 2 end
		end
		advance(t)
		if goneAt then return "gone", 0, goneAt end
		return (tt > 0) and "fade" or "idle", tt / g.time
	end
	local s = nil
	for _, e in ipairs(ev) do
		if e[1] > t then break end
		if e[2] == 1 then s = e[1] end
	end
	if not s then return "idle", 0 end
	local d = t - s
	local fadeLen = (g.mode == "Blink") and (g.blinks * g.time) or g.time
	if d < fadeLen then return "fade", d / fadeLen, d end
	d = d - fadeLen
	if d < g.respawn then return "gone", 0 end
	d = d - g.respawn
	if g.respawnFade and d < g.time then return "back", d / g.time end
	return "idle", 0
end
Vanishers.stateAt = stateAt

local function setIf(inst, prop, v)
	if inst[prop] ~= v then inst[prop] = v end
end

local function write(g, phase, a, blinkT)
	for _, vp in ipairs(g.parts) do
		local p = vp.part
		if p.Parent then
			local T, C, CT, color, thick = vp.defT, vp.defC, true, vp.selColor, vp.selThick
			if phase == "fade" then
				if g.mode == "Constant" then
					T = vp.defT + (vp.touchT - vp.defT) * a
				elseif g.mode == "Fade" then
					T = vp.defT + (vp.touchT - vp.defT) * ease(g, a)
				elseif vp.sel then
					-- (Blink with an outline: each blink the outline goes from 3x its thickness back to normal)
					local k = (blinkT or 0) % g.time
					thick = vp.selThick * 3 + (vp.selThick - vp.selThick * 3) * ease(g, k / g.time)
				else
					-- (Blink without one: half way to vanished over the first blink, then stays)
					local mid = (vp.defT + vp.touchT) / 2
					T = vp.defT + (mid - vp.defT) * ease(g, (blinkT or 0) / g.time)
				end
			elseif phase == "gone" then
				T, C, CT, color = vp.touchT, vp.touchC, false, g.outline
			elseif phase == "back" then
				T = vp.touchT + (vp.defT - vp.touchT) * ease(g, a)
			end
			pcall(setIf, p, "Transparency", T)
			pcall(setIf, p, "CanCollide", C)
			pcall(setIf, p, "CanTouch", CT)
			if vp.sel then
				if color then pcall(setIf, vp.sel, "Color3", color) end
				pcall(setIf, vp.sel, "LineThickness", thick)
			end
		end
	end
	g.last = { phase, a, blinkT }
end

-- your character touches the group (the kit: a box 0.1 bigger than each part)
local function touching(g, ch)
	if not ch then return false end
	for _, vp in ipairs(g.parts) do
		local p = vp.part
		if p.Parent then
			local ok, hits = pcall(workspace.GetPartBoundsInBox, workspace, p.CFrame, p.Size + Vector3.one * 0.1, params)
			if ok then
				for _, h in ipairs(hits) do if h:IsDescendantOf(ch) then return true end end
			end
		end
	end
	return false
end

-- every PreRender while Sync Kit Objects drives the run (mode 2 / 3; rec: frame f is being recorded now)
function Vanishers.frame(data, f, t, rec, addEvent)
	local ch = Players.LocalPlayer and Players.LocalPlayer.Character
	if rec and ch then params.FilterType = Enum.RaycastFilterType.Include; params.FilterDescendantsInstances = { ch } end
	for i = #groups, 1, -1 do
		local g = groups[i]
		if not g.cfg:IsDescendantOf(workspace) then
			groupOf[g.cfg] = nil
			table.remove(groups, i)
		else
			if rec and #data > 0 then
				local phase = stateAt(g, data, t)
				local hit = touching(g, ch)
				if g.mode == "Constant" then
					local ev = eventsOf(g, data)
					local lastOn = false
					for _, e in ipairs(ev) do if e[1] <= t then lastOn = e[2] == 2 end end
					if phase ~= "gone" and hit ~= lastOn then
						addEvent(data[#data], { 5, g.id, hit and 2 or 3 })
						g.events = nil
					end
				elseif hit and phase == "idle" then
					addEvent(data[#data], { 5, g.id, 1 })
					g.events = nil
				end
			end
			local phase, a, extra = stateAt(g, data, t)
			write(g, phase, a, extra)
		end
	end
end

-- before the physics step / at the end of the render step: the values of the frame again (the kit's tween
-- and timers write in between)
function Vanishers.reassert()
	for _, g in ipairs(groups) do
		if g.last then write(g, g.last[1], g.last[2], g.last[3]) end
	end
end

-- Idle / Sync Kit Objects off: the kit's again (left as last shown)
function Vanishers.release()
	for _, g in ipairs(groups) do g.last = nil end
end

return Vanishers
