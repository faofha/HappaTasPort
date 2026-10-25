-- ================================================================================================
-- HappaTAS 3, phase 2: the column timeline (buffers for numbers, sparse lists), V2 frame conversion,
-- optimize
-- ================================================================================================
check(boot(3), "boots")
local Timeline = __T3("engine/timeline")

-- (sorted-key serialiser of tests/test_diff.lua: two frames print the same only when every value is equal)
local function ser(v, out)
	if type(v) == "table" then
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b)
			local ta, tb = type(a), type(b)
			if ta ~= tb then return ta < tb end
			return a < b
		end)
		out[#out + 1] = "{"
		for _, k in ipairs(keys) do
			out[#out + 1] = tostring(k) .. "="
			ser(v[k], out)
			out[#out + 1] = ","
		end
		out[#out + 1] = "}"
	elseif type(v) == "number" then
		out[#out + 1] = string.format("%.17g", v)
	else
		out[#out + 1] = tostring(v)
	end
	return out
end
local function S(v) return table.concat(ser(v, {})) end

-- the phase 2 columns with their V2 fields (what the plugins register)
local function phase2(tl)
	tl:addColumn("FrameTime", "f64", 1, { key = "FrameTime" })
	tl:addColumn("TotalTime", "f64", 1, { key = "TotalTime" })
	tl:addColumn("Cframe", "f64", 12, { key = "Cframe" })
	tl:addColumn("Lin", "f64", 3, { key = "Velocity", sub = "Linear" })
	tl:addColumn("Ang", "f64", 3, { key = "Velocity", sub = "Angular" })
	tl:addColumn("State", "u8", 1, { key = "State" })
	tl:addColumn("Died", "list", 1, { key = "Died", keep = true })
	tl:addColumn("CamCframe", "f64", 12, { key = "CamCframe", keepOnChange = true })
	tl:addColumn("Zoom", "f64", 1, { key = "Zoom" })
	tl:addColumn("ShiftLock", "u8", 1, { key = "ShiftLock" })
	tl:addColumn("Input", "list", 1, { key = "Input", keep = function(v) return #v > 0 end })
	tl:addColumn("Mouse", "f64", 4, { keys = { "MX", "MY", "UVX", "UVY" }, keepOnChange = { 1, 2 } })
	tl:addColumn("Viewport", "list", 1, { keys = { "VX", "VY" } })
	tl:addColumn("AnimPose", "u8", 1, { key = "Anim", field = "Pose" })
	tl:addColumn("AnimJump", "f64", 1, { key = "Anim", field = "JumpTime" })
	tl:addColumn("AnimSpeed", "f64", 1, { key = "Anim", field = "Speed" })
	tl:addColumn("AnimList", "list", 1, { key = "Anim", field = "Anims", default = {}, keep = function(v) return #v > 0 end })
	tl:addColumn("Tools", "list", 1, { key = "Tools", keep = true })
	return tl
end

section("append / get / set")
do
	local tl = Timeline.new()
	tl:addColumn("A", "f64", 1, { key = "A" })
	tl:addColumn("V", "f64", 3, { key = "V" })
	tl:addColumn("B", "u8", 1, { key = "B" })
	tl:addColumn("L", "list", 1, { key = "L" })
	eq(tl:count(), 0, "empty")
	eq(tl:append(), 1, "first frame is 1")
	tl:set("A", 1, 1, 0.1 + 0.2)
	tl:setN("V", 1, -123456.789, 1e-6, 7)
	tl:set("B", 1, 1, 15)
	tl:setList("L", 1, { 5, -5 })
	eq(tl:get("A", 1, 1), 0.1 + 0.2, "f64 exact")
	local x, y, z = tl:getN("V", 1)
	check(x == -123456.789 and y == 1e-6 and z == 7, "f64 x3 exact")
	eq(tl:get("V", 1, 2), 1e-6, "one component")
	eq(tl:get("B", 1, 1), 15, "u8")
	eq(tl:getList("L", 1)[2], -5, "list")
	tl:append()
	eq(tl:get("A", 2, 1), 0, "a new frame starts at 0")
	eq(tl:getList("L", 2), nil, "a new frame's list value is nil")
	eq(tl:isFilled(2), false, "not filled")
	tl:setFilled(2)
	eq(tl:isFilled(2), true, "filled")
end

section("growth")
do
	local tl = Timeline.new()
	tl:addColumn("A", "f64", 2, { key = "A" })
	for i = 1, 10000 do
		tl:append()
		tl:setN("A", i, i, -i)
	end
	eq(tl:count(), 10000, "10000 frames")
	local ok = true
	for _, i in ipairs({ 1, 1024, 1025, 5000, 10000 }) do
		local a, b = tl:getN("A", i)
		if a ~= i or b ~= -i then ok = false end
	end
	check(ok, "frames keep their values across every growth")
end

section("memory")
do
	collectgarbage("collect")
	local before = collectgarbage("count")
	local tl = phase2(Timeline.new())
	for i = 1, 8192 do
		tl:append()
		tl:set("TotalTime", i, 1, i / 60)
		tl:setN("Cframe", i, i, 2, 3, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	collectgarbage("collect")
	local perFrame = (collectgarbage("count") - before) * 1024 / 8192
	-- the same fields as V2 table frames
	collectgarbage("collect")
	local b2 = collectgarbage("count")
	local frames = {}
	for i = 1, 2048 do
		frames[i] = { FrameTime = 1 / 60, TotalTime = i / 60, Cframe = { i, 2, 3, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
			Velocity = { Linear = { 1, 2, 3 }, Angular = { 0, 0, 0 } }, State = 8, CamCframe = { i, 2, 3, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
			Zoom = 12.5, ShiftLock = 0, MX = 1, MY = 2, UVX = 0.5, UVY = 0.5, Anim = { Pose = 1, JumpTime = 0, Speed = 1, Anims = {} } }
	end
	collectgarbage("collect")
	local v2PerFrame = (collectgarbage("count") - b2) * 1024 / 2048
	M.realPrint(string.format("  timeline %.0f bytes a frame, V2 tables %.0f", perFrame, v2PerFrame))
	check(perFrame < 400, "less than 400 bytes a frame (" .. math.floor(perFrame) .. ")")
	check(v2PerFrame > perFrame * 3, "V2 tables take over 3x more")
	tl = nil; frames = nil
end

section("cut")
do
	local tl = Timeline.new()
	tl:addColumn("A", "f64", 1, { key = "A" })
	tl:addColumn("L", "list", 1, { key = "L" })
	for i = 1, 5 do tl:append(); tl:set("A", i, 1, i); tl:setList("L", i, i) end
	local v0 = tl.version
	tl:cut(3)
	eq(tl:count(), 3, "3 frames left")
	eq(tl.version, v0 + 1, "version bumped")
	eq(tl:getList("L", 4), nil, "list entry of frame 4 gone")
	eq(tl:append(), 4, "next frame is 4")
	eq(tl:get("A", 4, 1), 0, "clean values after a cut")
	eq(tl:getList("L", 4), nil, "clean list after a cut")
	local v1 = tl.version
	tl:set("A", 4, 1, 9)
	tl:append()
	eq(tl.version, v1, "append / set don't bump the version")
	tl:removeLast()
	eq(tl:count(), 4, "removeLast")
	eq(tl.version, v1 + 1, "removeLast bumps the version")
end

section("V2 round trip")
local function v2frames()
	local out = {}
	for i = 1, 5 do
		local f = {
			FrameTime = 0.016667, TotalTime = math.round(i * 0.016667 * 1e6) / 1e6,
			Cframe = { i, 3.5, -2.125, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
			Velocity = { Linear = { 16, -0.5, 0 }, Angular = { 0, 0.25, 0 } },
			CamCframe = { i, 8, 12, 1, 0, 0, 0, 0.966, 0.259, 0, -0.259, 0.966 },
			ShiftLock = (i == 3) and 1 or 0, Zoom = 12.5, State = (i == 4) and 3 or 8,
			Anim = { Pose = 1, JumpTime = (i == 4) and 0.3 or 0, Speed = 1.068, Anims = (i == 2) and { { 2, 0 } } or {} },
			MX = 800 + i, MY = 400, UVX = 0.417, UVY = 0.37,
		}
		if i == 1 then f.VX, f.VY = 1920, 1080 end
		if i == 2 then f.Input = { 23, 96 } end
		if i == 3 then f.Input = { -23 }; f.Tools = { { Action = "Equip", Name = "Sword" } } end
		if i == 5 then f.Died = true end
		out[i] = f
	end
	return out
end
do
	local src = v2frames()
	local tl = phase2(Timeline.new())
	tl:replaceFromV2(src)
	eq(tl:count(), 5, "5 frames loaded")
	for i = 1, 5 do eq(S(tl:toV2(i)), S(src[i]), "frame " .. i .. " converts back identically") end
	eq(tl:toV2(2).VX, nil, "VX only where the source had it")
	eq(tl:toV2(1).Died, nil, "Died absent where absent")
	eq(#tl:toV2All(), 5, "toV2All")
	check(tl:isFilled(3), "loaded frames are filled")
end

section("optimize")
-- V2.38.16's Optimize loop (p18_core.lua 808-829), the oracle
local function v2optimize(data)
	local function r(n, d) local v = math.round(n * d) / d; if v == 0 then v = 0 end; return v end
	local NewData = {}
	local prev, prevMX, prevMY
	for i = 1, #data do
		local v = data[i]
		local values = v.CamCframe
		local SameCount = 0
		local mouseMoved = v.MX ~= nil and (v.MX ~= prevMX or v.MY ~= prevMY)
		prevMX, prevMY = v.MX, v.MY
		if prev then
			for y, z in pairs(values) do
				if prev[y] == z then SameCount = SameCount + 1 end
			end
		end
		prev = values
		if i == 1 or SameCount < 12 or (v.Anim and v.Anim.Anims and #v.Anim.Anims > 0) or (v.Input and #v.Input > 0) or mouseMoved
			or v.CO ~= nil or v.BT ~= nil or v.Tools ~= nil or v.Died then
			NewData[#NewData + 1] = v
			if #NewData > 1 then
				v.TotalTime = r(NewData[#NewData - 1].TotalTime + v.FrameTime, 1000000)
			else
				v.TotalTime = r(v.FrameTime, 1000000)
			end
		end
	end
	return NewData
end
do
	local function fixture()
		local out = {}
		for i = 1, 9 do
			out[i] = {
				FrameTime = 0.01 * i, TotalTime = 0, Cframe = { i, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
				Velocity = { Linear = { 0, 0, 0 }, Angular = { 0, 0, 0 } }, State = 8,
				CamCframe = { 0, 5, 10, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, ShiftLock = 0, Zoom = 12.5,
				Anim = { Pose = 1, JumpTime = 0, Speed = 1, Anims = {} }, MX = 10, MY = 10, UVX = 0, UVY = 0,
			}
		end
		out[3].CamCframe = { 0, 5, 10.5, 1, 0, 0, 0, 1, 0, 0, 0, 1 } -- camera moved: 3 and 4 differ from their previous
		out[5].Input = { 23 }
		out[6].MX = 11                -- mouse moved
		out[7].Anim.Anims = { { 3, 0.1 } }
		out[8].Tools = { { Action = "Activate", Name = "Sword" } }
		out[9].Died = true
		out[2].Input = {}             -- (an empty list keeps nothing)
		local t = 0
		for i = 1, 9 do t = t + out[i].FrameTime; out[i].TotalTime = math.round(t * 1e6) / 1e6 end
		return out
	end
	local oracle = v2optimize(fixture())
	local tl = phase2(Timeline.new())
	tl:replaceFromV2(fixture())
	local v0 = tl.version
	eq(tl:optimize(), #oracle, "same number of frames kept as V2 (" .. #oracle .. ")")
	eq(tl.version, v0 + 1, "optimize bumps the version")
	for i = 1, #oracle do
		local want = oracle[i]
		if want.Input and #want.Input == 0 then want.Input = nil end
		eq(S(tl:toV2(i)), S(want), "kept frame " .. i .. " equals V2's")
	end
end
section("phase 3: meta, newLike, adopt, resize")
do
	local a = Timeline.new()
	check(type(a.meta) == "table" and next(a.meta) == nil, "a new timeline has an empty meta")
	a:addColumn("P", "f64", 3, { key = "P" })
	a:addColumn("S", "u8", 1, { key = "S" })
	a:addColumn("L", "list", 1, { key = "L" })
	for i = 1, 3 do
		a:append()
		a:setN("P", i, i, i * 2, i * 3)
		a:set("S", i, 1, i)
		a:setList("L", i, { i })
	end
	a.meta.x = 1
	local b = Timeline.newLike(a)
	eq(b:count(), 0, "newLike: no frames")
	check(b.cols.P and b.cols.P.width == 3 and b.cols.P.v2.key == "P", "newLike: same columns")
	check(b.cols.L and b.cols.L.kind == "list", "newLike: list column")
	check(next(b.meta) == nil, "newLike: empty meta")
	b:resize(2000)
	eq(b:count(), 2000, "resize: count")
	check(b:isFilled(2000), "resize: frames filled")
	eq(b:get("P", 2000, 3), 0, "resize: numbers zero")
	eq(b:getList("L", 1), nil, "resize: lists empty")
	b:setN("P", 2000, 7, 8, 9)
	b:addColumn("Extra", "f64", 1, nil)
	b:set("Extra", 5, 1, 42)
	b.meta.y = 2
	local v0 = a.version
	a:adopt(b)
	eq(a:count(), 2000, "adopt: count")
	eq(a:get("P", 2000, 2), 8, "adopt: the other's numbers")
	eq(a:get("Extra", 5, 1), 42, "adopt: a column only the other had")
	eq(a.meta.y, 2, "adopt: meta")
	check(a.version > v0, "adopt: version changed")
	a:append()
	eq(a:count(), 2001, "append after adopt grows fine")
end
finish()
