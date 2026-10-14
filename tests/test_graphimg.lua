-- ================================================================================================
-- MicroProfiler frame graph drawn into one EditableImage (V2.38). The other suites run without
-- EditableImage, so they test the 508-frame fallback; this one turns the mock's EditableImage on.
-- ================================================================================================
local function stepMs(ms, n) for _ = 1, (n or 1) do M.step(ms / 1000) end end
local function away() M.moveMouse(960, 700) end
M.editableImages = true

section("boot")
check(boot(5), "script boots")
local P, S = __T.Profiler, __T.Settings
away()
S.Set("Show MicroProfiler", 1)
M.step(1 / 60)
check(P.active == true, "profiler open")
local U, I = P.Internals()

section("one image instead of 508 frames")
check(U.bars == nil and U.strip == nil, "no bar frames when EditableImage works")
local lab = U.graph.f:FindFirstChild("Bars")
check(lab ~= nil and lab.ClassName == "ImageLabel", "the bars are one ImageLabel")
local img = lab and lab.ImageContent and lab.ImageContent.Object
check(img ~= nil, "it shows an EditableImage (ImageContent = Content.fromObject(image))")
eq(img.Size, Vector2.new(1016, 50), "the image is 2 x 508 columns, 50 rows")
eq(lab.ImageRectSize, Vector2.new(508, 50), "the label shows 508 columns of it")
check(lab.ResampleMode == Enum.ResamplerMode.Pixelated, "pixelated: no blur between the columns")
check(lab.Size == UDim2.new(1, 0, 1, 0), "it fills the graph")
local x = U.close.f:FindFirstChild("X")
check(x ~= nil and x.ClassName == "ImageLabel", "the close box's X is an image too")
check(x.Position == UDim2.fromOffset(10, 10) and x.Size == UDim2.fromOffset(30, 30), "X from (10, 10) to (39, 39)")
local xi = x.ImageContent.Object
local function px(im, a, b) local r, g, bl, al = im:Pixel(a, b); return r .. "," .. g .. "," .. bl .. "," .. al end
eq(px(xi, 0, 0), "255,255,255,255", "X: top-left corner white")
eq(px(xi, 29, 0), "255,255,255,255", "X: top-right corner white")
eq(px(xi, 15, 15), "255,255,255,255", "X: crossing white")
eq(px(xi, 5, 0), "0,0,0,0", "X: off the diagonals transparent")
local nGui = 0
for _, d in ipairs(U.sg:GetDescendants()) do if d:IsA("GuiObject") then nGui = nGui + 1 end end
check(nGui < 400, "far fewer GUI objects than with 508 bars + 60 pixels (" .. nGui .. ")")

-- slot s of frame k; both copies of a column must match
local function column(k)
	local s = (k - 1) % 508
	local h = 0
	for y = 0, 49 do
		if px(img, s, y) ~= px(img, s + 508, y) then return -1 end
		local _, _, _, a = img:Pixel(s, y)
		if a > 0 then h = h + 1 end
	end
	local function rgb(y) local r, g, b = img:Pixel(s, y); return r .. "," .. g .. "," .. b end
	return h, h > 0 and rgb(50 - h) or nil, h > 0 and rgb(49) or nil, s
end

section("bars: height, colour, scrolling")
M.jobMs, M.stats.RenderCPUFrameTime = 4, 0.001
stepMs(33.33 / 2, 3)
local K = P.Snapshot().recorded
local h, top, bottom = column(K)
eq(h, 25, "half the reference = 25 px")
-- the gradient (255,191,147) -> (147,83,39) sampled at pixel centres: f = 0.5 / 25 and 24.5 / 25
eq(top, "253,189,145", "orange gradient, top pixel")
eq(bottom, "149,85,41", "orange gradient, bottom pixel")
local x0 = (K - 1) % 508
local r, g, b, a = img:Pixel(x0, 50 - h - 1)
eq(a, 0, "transparent above the bar (the graph's 0x474747 shows through)")
eq(lab.ImageRectOffset, Vector2.new(K % 508, 0), "the label starts at the first frame's slot (K - 507)")
M.jobMs, M.stats.RenderCPUFrameTime = 1, 0.0039
stepMs(100, 3)
K = P.Snapshot().recorded
h, top, bottom = column(K)
eq(h, 50, "longer than the reference = full height")
eq(top, "145,198,237", "blue gradient, top pixel ((146,199,238) -> (55,107,146), f = 0.01)")
eq(bottom, "56,108,147", "blue gradient, bottom pixel")
eq(lab.ImageRectOffset, Vector2.new(K % 508, 0), "scrolled with the new frame")
-- one new frame = one column, written twice (both halves), and one ImageRectOffset write
M.stats.RenderCPUFrameTime = 0.0039
local w0 = M.eiWrites
stepMs(100)
eq(M.eiWrites - w0, 2, "a new frame writes one column twice")
M.writeLog = {}
stepMs(100)
local offsetWrites = 0
for _, e in ipairs(M.writeLog) do if e[1] == lab then offsetWrites = offsetWrites + 1 end end
M.writeLog = nil
eq(offsetWrites, 1, "and the label gets one property write (ImageRectOffset)")
M.jobMs, M.stats.RenderCPUFrameTime = nil, 0.0021
-- many frames: every column still matches its frame
stepMs(5, 600)
K = P.Snapshot().recorded
local bad = 0
for k = K - 507, K do if column(k) ~= 8 then bad = bad + 1 end end
eq(bad, 0, "after 600 more frames every column holds its frame (5 ms = 8 px)")
eq(lab.ImageRectOffset, Vector2.new(K % 508, 0), "offset follows the newest frame")

section("a redraw writes the whole image once")
w0 = M.eiWrites
-- Options > Reference 66.66 makes every bar half as tall
local MENUS = P.Menus
MENUS[5].click(6)
M.step(5 / 1000)
eq(P.Config().ref, 66.66, "reference 66.66 ms")
check(M.eiWrites - w0 <= 4, "redraw = one write of the whole image (+ the new frame) (" .. (M.eiWrites - w0) .. ")")
K = P.Snapshot().recorded
eq(column(K - 100), 4, "an old 5 ms frame is now ceil(5/66.66*50) = 4 px")
MENUS[5].click(5)
M.step(5 / 1000)
eq(column(K - 100), 8, "back to 8 px at 33.33 ms")

section("hover: the frame under the mouse is drawn white")
local gw = 1870
local function barX(back) return gw - (back + 0.5) * gw / 508 end
M.moveMouse(barX(10), 40)
M.step(5 / 1000)
local hov = P.Snapshot().hover
check(hov ~= nil, "a frame is hovered")
h, top, bottom = column(hov)
eq(h, 8, "hovered bar keeps its height")
eq(top, "253,253,253", "white gradient, top pixel ((255,255,255) -> (217,217,217), f = 0.5 / 8)")
eq(bottom, "219,219,219", "white gradient bottom ((255,255,255) -> (217,217,217), f = 7.5 / 8)")
away()
M.step(5 / 1000)
h, top = column(hov)
check(top ~= "253,253,253", "colour back when the mouse leaves")

section("green selection sits on the graph")
local hl = U.hl.f
check(hl.Parent == U.graph.f, "selection is a child of the graph (the image does not move)")
check(hl.Visible, "selection visible")
near(hl.Position.X.Scale, 504 / 508, 1e-6, "default window starts 3 frames behind the newest")
local hlWrites = 0
M.writeLog = {}
stepMs(5, 3)
for _, e in ipairs(M.writeLog) do if e[1] == hl then hlWrites = hlWrites + 1 end end
M.writeLog = nil
eq(hlWrites, 0, "a window that follows the newest frame costs no selection writes")

section("TAS Timeline draws into the image too")
local data = {}
for i = 1, 700 do data[i] = { FrameTime = (i == 575) and 0.05 or 0.016, TotalTime = i * 0.016 } end
local curF = 600
P.GetTAS = function() return data, curF, 1 end
P.OnScrub = function() end
MENUS[7].click(2)
M.step(16 / 1000)
check(P.Config().custom == true, "TAS Timeline on")
eq(column(curF), 25, "TAS bar from FrameTime (16 ms = 25 px)")
eq(column(575), 50, "TAS spike frame full height")
local tas = I.tas
eq(lab.ImageRectOffset, Vector2.new((tas.a - 1) % 508, 0), "the label starts at the window's first TAS frame")
near(hl.Position.X.Scale, (curF - tas.a) / 508, 1e-9, "selection on the current TAS frame")
MENUS[7].click(0)
M.step(16 / 1000)
check(P.Config().custom == false, "back to the live graph")
K = P.Snapshot().recorded
eq(column(K), 25, "live bars drawn again (16 ms)")

section("an image that stops working: back to frames")
M.eiFail = true
stepMs(16, 2)
M.eiFail = false
stepMs(16, 2)
check(U.bars ~= nil and #U.bars == 508, "508 bar frames built after a failed image write")
check(U.graph.f:FindFirstChild("Bars") == nil and U.close.f:FindFirstChild("X") == nil, "the image labels are gone")
local live0 = 0
for _ in pairs(M.eiImages) do live0 = live0 + 1 end
eq(live0, 0, "both images destroyed")
K = P.Snapshot().recorded
local nb = U.bars[(K - 1) % 508 + 1]
eq(nb.f.Size.Y.Offset, 25, "the newest frame is drawn as a frame bar (16 ms = 25 px)")
near(nb.f.Position.X.Scale + 1 / 508 + U.strip.Position.X.Scale, 1, 1e-6, "and ends at the right edge")
local xPixels = 0
for _, c in ipairs(U.close.f:GetChildren()) do if c:IsA("Frame") and c.Size == UDim2.fromOffset(1, 1) then xPixels = xPixels + 1 end end
eq(xPixels, 60, "the X is 60 pixel frames again")

section("closing and unloading")
S.Set("Show MicroProfiler", 0)
M.step(1 / 60)
check(P.active == false, "closed")
local h0 = M.genv.__HappaTAS
if h0 and h0.Unload then h0.Unload() end
M.steps(3)
local live = 0
for _ in pairs(M.eiImages) do live = live + 1 end
eq(live, 0, "Unload destroys both EditableImages")
finish()
