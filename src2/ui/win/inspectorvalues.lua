-- ================================================================================================
--  INSPECTOR VALUES  (HappaTAS 3 ui): the Inspector's rows (LIST) and their values as text (values), no GUI.
--  Every value V2.38.16's stats panels showed is here, from the same sources (p18_core SS.Idle / SS.Create
--  / SS.Test): paused in Create, the frame shown (its columns; the keys held there); recording, the newest
--  recorded frame with the live keys and mouse; Test, the playback time and speed, the replayed keys; Idle
--  (or no frame), the live character. Numbers as V2 wrote them: 3 decimals, rotations in degrees (YXZ).
--  values(E, perf, want) works out only the rows in want (all when nil): a collapsed section or a hidden row
--  reads nothing. Rows marked slow change rarely; the Inspector asks for them less often. memo (optional)
--  keeps each live row's last raw value and text: a value that didn't change isn't formatted again.
-- ================================================================================================
local Util = import("engine/util")

local IV = {}

IV.SECTIONS = { "Frame", "Character", "Camera & input", "World", "Performance" }
IV.LIST = {
	{ section = "Frame", key = "frame", label = "Frame" },
	{ section = "Frame", key = "frameTime", label = "Frame time" },
	{ section = "Frame", key = "totalTime", label = "Total time" },
	{ section = "Frame", key = "speed", label = "Speed", slow = true },
	{ section = "Character", key = "rig", label = "Rig type", slow = true },
	{ section = "Character", key = "state", label = "State" },
	{ section = "Character", key = "position", label = "Position" },
	{ section = "Character", key = "rotation", label = "Rotation" },
	{ section = "Character", key = "velocity", label = "Velocity" },
	{ section = "Character", key = "angular", label = "Angular velocity" },
	{ section = "Character", key = "moveDirection", label = "Move direction" },
	{ section = "Character", key = "walkJump", label = "Walk / jump", slow = true },
	{ section = "Character", key = "health", label = "Health", slow = true },
	{ section = "Character", key = "floor", label = "Floor", slow = true },
	{ section = "Camera & input", key = "cameraRotation", label = "Camera rotation" },
	{ section = "Camera & input", key = "zoom", label = "Zoom", slow = true },
	{ section = "Camera & input", key = "keys", label = "Keys" },
	{ section = "Camera & input", key = "mouse", label = "Mouse" },
	{ section = "World", key = "clientObjects", label = "Client objects", slow = true },
	{ section = "World", key = "kit", label = "Kit clock", slow = true },
	{ section = "World", key = "buttons", label = "Button timers", slow = true },
	{ section = "Performance", key = "fps", label = "FPS" },
	{ section = "Performance", key = "happaMs", label = "HappaTAS ms" },
}

local function r3(v) return tostring(Util.round(v or 0, 1000)) end
local function v3(x, y, z) return r3(x) .. ", " .. r3(y) .. ", " .. r3(z) end
local function vec(v) return v3(v.X, v.Y, v.Z) end
local function deg(cf)
	local x, y, z = cf:ToEulerAnglesYXZ()
	return v3(math.deg(x), math.deg(y), math.deg(z))
end
local function cframe(t) return CFrame.new(table.unpack(t, 1, 12)) end
local function mouseText(v) return math.floor(v.X + 0.5) .. ", " .. math.floor(v.Y + 0.5) end
local function fpsText(v) return string.format("%.0f", v) end
local function msText(v) return string.format("%.3f", v) end
local function dtText(v) return tostring(Util.round(v, 1000000)) end

-- make(raw), or the text memo kept for key when raw is the same value as last time
local function same(memo, key, raw, make)
	if not memo then return make(raw) end
	local m = memo[key]
	if m and m.raw == raw then return m.text end
	local text = make(raw)
	if m then
		m.raw, m.text = raw, text
	else
		memo[key] = { raw = raw, text = text }
	end
	return text
end

local stateNames = nil
local function stateName(n)
	if not stateNames then
		stateNames = {}
		pcall(function()
			for _, it in ipairs(Enum.HumanoidStateType:GetEnumItems()) do stateNames[it.Value] = it.Name end
		end)
	end
	return stateNames[n] or "None"
end

local function on(E, key) return E.settings:on(key) end

-- want is nil (every row) or has one of the keys
local function need(want, a, b, c, d, e)
	if not want then return true end
	return want[a] or (b and want[b]) or (c and want[c]) or (d and want[d]) or (e and want[e]) or false
end

-- { [key] = text } for the rows of LIST in want (a set of keys; nil = every row); perf = { dt, fps, ms } (the
-- Inspector's own measurements); out: the table to fill (a new one when nil; rows not wanted keep old text)
function IV.values(E, perf, want, memo, out)
	perf = perf or {}
	out = out or {}
	local tl = E.tl
	local n = tl:count()
	local char = E.char
	local hrp, hum = char and char.hrp, char and char.hum
	local inputs = E.inputs
	-- which frame's data: paused or recording in Create (V2 SS.Create's FrameData)
	local f = nil
	if E.mode == 2 and n > 0 then
		f = E.paused and math.clamp(E.frame, 1, n) or n
		if not tl:isFilled(f) then f = nil end
	end
	local playFrame = (E.mode == 3 and n > 0) and math.clamp(E.frame, 1, n) or nil
	-- Frame
	local shown = f or playFrame
	out.frame = shown and (shown .. " / " .. n) or (n > 0 and ("- / " .. n) or "-")
	if f then
		out.frameTime = tostring(tl:get("FrameTime", f, 1))
		out.totalTime = Util.toTime(tl:get("TotalTime", f, 1))
	elseif E.mode == 3 then
		out.frameTime = playFrame and tostring(tl:get("FrameTime", playFrame, 1)) or "-"
		out.totalTime = Util.toTime(E.testTime or 0)
	else
		out.frameTime = same(memo, "frameTime", perf.dt or 0, dtText)
		out.totalTime = "-"
	end
	if E.mode == 3 then
		out.speed = tostring(E.settings:get("playbackSpeed"))
	elseif on(E, "speedHack") then
		out.speed = tostring(E.settings:get("speedHackSpeed"))
	else
		out.speed = "1"
	end
	-- Character
	local okHum = hum ~= nil and char:loaded()
	if need(want, "rig") then out.rig = okHum and hum.RigType.Name or "-" end
	if not need(want, "state", "position", "rotation", "velocity", "angular") then
		-- (none of them wanted)
	elseif f then
		local cf = { tl:getN("Cframe", f) }
		out.state = stateName(tl:get("State", f, 1))
		out.position = v3(cf[1], cf[2], cf[3])
		out.rotation = deg(cframe(cf))
		out.velocity = v3(tl:getN("Lin", f))
		out.angular = v3(tl:getN("Ang", f))
	elseif okHum then
		if need(want, "state") then out.state = hum:GetState().Name end
		if need(want, "position") then out.position = same(memo, "position", hrp.Position, vec) end
		if need(want, "rotation") then out.rotation = same(memo, "rotation", hrp.Orientation, vec) end
		if need(want, "velocity") then out.velocity = same(memo, "velocity", hrp.AssemblyLinearVelocity, vec) end
		if need(want, "angular") then out.angular = same(memo, "angular", hrp.AssemblyAngularVelocity, vec) end
	else
		out.state, out.position, out.rotation, out.velocity, out.angular = "None", "-", "-", "-", "-"
	end
	if okHum then
		if need(want, "moveDirection") then out.moveDirection = same(memo, "moveDirection", hum.MoveDirection, vec) end
		if need(want, "walkJump") then
			out.walkJump = r3(hum.WalkSpeed) .. " / " .. r3(hum.UseJumpPower and hum.JumpPower or hum.JumpHeight)
		end
		if need(want, "health") then out.health = r3(hum.Health) .. " / " .. r3(hum.MaxHealth) end
		if need(want, "floor") then out.floor = hum.FloorMaterial.Name end
	else
		out.moveDirection, out.walkJump, out.health, out.floor = "-", "-", "-", "-"
	end
	-- Camera & input
	if f then
		out.cameraRotation = deg(cframe({ tl:getN("CamCframe", f) }))
		out.zoom = r3(tl:get("Zoom", f, 1))
		out.mouse = tl:get("Mouse", f, 1) .. ", " .. tl:get("Mouse", f, 2)
	else
		if need(want, "cameraRotation") then
			local cam = workspace.CurrentCamera
			out.cameraRotation = cam and same(memo, "cameraRotation", cam.CFrame, deg) or "-"
		end
		if need(want, "zoom") then
			local z = E.cs and E.cs:getZoom()
			out.zoom = r3(z or 12.5)
		end
		if not need(want, "mouse") then
			-- (not wanted)
		elseif playFrame then
			out.mouse = tl:get("Mouse", playFrame, 1) .. ", " .. tl:get("Mouse", playFrame, 2)
		else
			-- (the position alone: one read, not inputs:mouse()'s viewport too)
			out.mouse = same(memo, "mouse", inputs.uis:GetMouseLocation(), mouseText)
		end
	end
	if not need(want, "keys") then
		-- (not wanted)
	elseif E.mode == 3 then
		out.keys = inputs:describe(inputs.replay.state)
	elseif f and E.paused then
		out.keys = inputs:describe(inputs:heldAt(tl, f))
	else
		out.keys = inputs:describe(inputs.held)
	end
	-- World
	if need(want, "clientObjects") then
		if on(E, "syncClientObjects") and E.co and E.co.reg then
			out.clientObjects = #E.co.reg.parts .. " parts"
		else
			out.clientObjects = "off"
		end
	end
	if need(want, "kit") then
		local kc = E.kitClock
		if on(E, "kitScriptsOnTasClock") and kc and kc:isEnabled() then
			out.kit = "on, " .. r3(kc.rate or 1) .. "x"
		else
			out.kit = "off"
		end
	end
	if need(want, "buttons") then out.buttons = on(E, "syncButtonTimers") and "on" or "off" end
	-- Performance
	if need(want, "fps") then out.fps = same(memo, "fps", perf.fps or 0, fpsText) end
	if need(want, "happaMs") then out.happaMs = same(memo, "happaMs", perf.ms or 0, msText) end
	return out
end

return IV
