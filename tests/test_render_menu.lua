SCENE = "menu"
-- ================================================================================================
-- Dumps the MicroProfiler GUI (absolute boxes, gradients, texts) so tools/render_dump.py can draw it
-- ================================================================================================
local SCENE = SCENE or "bar"
-- Roblox's text engine: a TextSize-tall line holds the whole ascender..descender (see test_textline)
M.textLineModel = true
M.realPrint("TEXTMODEL line")
check(boot(5), "boots")
local P, S = __T.Profiler, __T.Settings
M.mouse = Vector2.new(960, 900)
S.Set("Show MicroProfiler", 1)
M.step(1 / 60)
local U, I = P.Internals()

-- frames like the screenshot: fast frames first (blue / orange mix), then ~34 ms frames
local seed = 7
local function rnd()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
for i = 1, 380 do
	local ms = 4 + rnd() * 3 + ((rnd() < 0.05) and 3 or 0)
	if rnd() < 0.5 then M.stats.HeartbeatTime, M.stats.RenderCPUFrameTime = 0.003, 0.001
	else M.stats.HeartbeatTime, M.stats.RenderCPUFrameTime = 0.001, 0.003 end
	M.step(ms / 1000)
end
-- 58 x 33.32, one 34.94 spike, last frame 34.10 -> Time[ 34.10] Avg[ 33.36] Max[ 34.94]
for i = 1, 200 do
	local ms = 33.32 + rnd() * 0.04
	M.stats.HeartbeatTime, M.stats.RenderCPUFrameTime = 0.003, 0.001
	if i % 23 == 0 then M.stats.HeartbeatTime, M.stats.RenderCPUFrameTime = 0.001, 0.003 end
	M.step(ms / 1000)
end
-- line the readout up with a window boundary
local guard = 0
while P.Snapshot().count ~= 0 and guard < 100 do M.step(33.32 / 1000); guard = guard + 1 end
for i = 1, 57 do M.step(33.32 / 1000) end
M.step(34.94 / 1000)
M.stats.HeartbeatTime, M.stats.RenderCPUFrameTime = 0.001, 0.003
M.step(33.37 / 1000)
M.stats.HeartbeatTime, M.stats.RenderCPUFrameTime = 0.003, 0.001
M.step(34.10 / 1000)
M.realPrint("READOUT " .. U.readout.s)

if SCENE == "tooltip" then
	M.mouse = Vector2.new(1500, 40)
	M.step(34.1 / 1000)
elseif SCENE == "menu" then
	M.mouse = Vector2.new(I.menuX[5] + 10, 4)
	M.step(34.1 / 1000)
elseif SCENE == "detailed" then
	M.clockStep = 4e-5
	P.SetMode("Detailed")
	P.SetView(-60, 80)
	for i = 1, 8 do M.step(16.6 / 1000) end
elseif SCENE == "timers" then
	P.SetMode("Timers")
	for i = 1, 12 do M.step(16.6 / 1000) end
	M.mouse = Vector2.new(400, 40)
	M.step(16.6 / 1000)
end

-- dump in drawing order (ZIndexBehavior.Sibling: children above their parent, siblings by ZIndex)
local function esc(s) return (tostring(s):gsub("\\", "\\\\"):gsub("\"", "\\\"")) end
local function c3(c) local r, g, b = M.rgb255(c); return string.format("[%d,%d,%d]", r, g, b) end
-- AbsolutePosition is measured from the bottom of the top bar; the profiler's ScreenGui ignores the
-- inset, so screen y = AbsolutePosition.Y + inset
local OFF = Vector2.new(0, M.inset)
local function visit(inst, clip)
	if not inst:IsA("GuiObject") then return end
	if inst.Visible == false then return end
	local p, s = inst.AbsolutePosition + OFF, inst.AbsoluteSize
	local parts = { string.format("\"x\":%.3f,\"y\":%.3f,\"w\":%.3f,\"h\":%.3f", p.X, p.Y, s.X, s.Y) }
	parts[#parts + 1] = "\"bg\":" .. c3(inst.BackgroundColor3)
	parts[#parts + 1] = string.format("\"bt\":%.4f", inst.BackgroundTransparency)
	parts[#parts + 1] = string.format("\"rot\":%.2f", inst.Rotation)
	if clip then parts[#parts + 1] = string.format("\"clip\":[%.3f,%.3f,%.3f,%.3f]", clip[1], clip[2], clip[3], clip[4]) end
	local g = inst:FindFirstChildOfClass("UIGradient")
	if g then
		local k = g.Color.Keypoints
		parts[#parts + 1] = "\"grad\":[" .. c3(k[1].Value) .. "," .. c3(k[#k].Value) .. "]"
	end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") then
		if inst.Text ~= "" then
			parts[#parts + 1] = "\"text\":\"" .. esc(inst.Text) .. "\""
			parts[#parts + 1] = "\"tc\":" .. c3(inst.TextColor3)
			parts[#parts + 1] = string.format("\"ts\":%.3f", inst.TextSize)
			local ff = inst.FontFace
			parts[#parts + 1] = "\"fw\":" .. (ff and ff.Weight.Value or 400)
		end
	end
	M.realPrint("EL {" .. table.concat(parts, ",") .. "}")
	local newClip = clip
	if inst.ClipsDescendants then
		local c = { p.X, p.Y, p.X + s.X, p.Y + s.Y }
		if clip then c = { math.max(c[1], clip[1]), math.max(c[2], clip[2]), math.min(c[3], clip[3]), math.min(c[4], clip[4]) } end
		newClip = c
	end
	local kids = {}
	for i, ch in ipairs(inst:GetChildren()) do kids[#kids + 1] = { ch, i } end
	table.sort(kids, function(a, b)
		local za = a[1]:IsA("GuiObject") and a[1].ZIndex or 0
		local zb = b[1]:IsA("GuiObject") and b[1].ZIndex or 0
		if za ~= zb then return za < zb end
		return a[2] < b[2]
	end)
	for _, k in ipairs(kids) do visit(k[1], newClip) end
end
visit(U.root, nil)
finish()
