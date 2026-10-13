-- ================================================================================================
--  MICROPROFILER  (a copy of Roblox's desktop MicroProfiler: menu bar, frame graph, menus, modes)
--
--  Layout, menus and numbers follow the microprofile source that Roblox's MicroProfiler is built
--  on: github.com/zeux/microprofile (microprofile.h + microprofileui.h, which contains the commit
--  "Add changes from Roblox internal fork"). The font is Roboto Mono Bold on a 6 px character grid
--  with a 1 px black drop shadow, measured from the current Roblox client.
--
--    Time[ ]  the last frame's time
--    Avg[ ]   the average of the frames on the bar (the last 508), whatever Aggregate is set to
--    Max[ ]   the biggest frame since the profiler opened; it stays until a bigger frame comes
--    Aggregate[N]  shows N, or for Infinite the number of frames counted so far (nAggregateFlipCount,
--                  "Aggregate[%d]" in microprofileui.h). Picking Infinite restarts the count and resets
--                  Max. The Aggregate window is what the Timers table averages over, like Roblox's.
--  Every number comes from a documented Roblox API: frame time = RunService.PreRender delta,
--  GPU / render / jobs / physics = Stats.RenderGPUFrameTime / RenderCPUFrameTime / HeartbeatTime /
--  PhysicsStepTime, memory = Stats:GetTotalMemoryUsageMb(), HappaTAS's own work = os.clock around
--  every system. Everything keeps counting while the graph is hidden (Mode > Hidden).
--
--  Mouse: GuiBase2d.AbsolutePosition and InputObject.Position are measured from the bottom of the
--  Roblox top bar, UserInputService:GetMouseLocation() from the top of the screen (Roblox docs), so
--  the pointer is taken from input events, or GetMouseLocation() - GuiService:GetGuiInset(). Clicks
--  come from UserInputService like microprofile's MicroProfileMouseButton: a click is a release
--  less than 3 px from where the button went down, holding the left button keeps centring.
--  Text: TextSize is the height of a whole text line; every label is moved so the baseline lands
--  where Roblox's MicroProfiler draws it (Settings > MicroProfiler Text Offset adjusts it by hand).
-- ================================================================================================
do
	local function profilerModule()
		local P = Profiler
		local clock = os.clock
		local floor, ceil, mmax, mmin = math.floor, math.ceil, math.max, math.min
		local sfmt = string.format
		local HUGE = math.huge

		-- -------------------------------------------------------------------------------- geometry
		local TW, TH = 5, 8                 -- MICROPROFILE_TEXT_WIDTH / MICROPROFILE_TEXT_HEIGHT
		local CW, RH = TW + 1, TH + 1       -- 6 px per character, 9 px per text row
		local MENU_H = RH + 1               -- menu bar: (TEXT_HEIGHT + 1) + 1
		local HIST_H = 50                   -- MICROPROFILE_FRAME_HISTORY_HEIGHT
		local MAX_HISTORY = 512             -- MICROPROFILE_MAX_FRAME_HISTORY
		local NUM_FRAMES = 508              -- MAX_HISTORY - (MICROPROFILE_GPU_FRAME_DELAY 3 + 1)
		local CLOSE_W = 50                  -- the close box of the current Roblox client (50 x 50)
		local BAR_H = 12                    -- MICROPROFILE_DETAILED_BAR_HEIGHT
		local BAR_W = 100                   -- MICROPROFILE_BAR_WIDTH (Timers mode)
		local SCALE = 1                     -- Settings > MicroProfiler Size (1 = the same pixels as Roblox's)
		local DET_Y = MENU_H + HIST_H
		local DET_H = 2 * RH + 2 * BAR_H + 4

		-- -------------------------------------------------------------------------------- colours
		local function hex(h) return Color3.fromRGB(floor(h / 65536) % 256, floor(h / 256) % 256, h % 256) end
		local BACK = { hex(0x474747), hex(0x313131) }  -- g_nMicroProfileBackColors
		local BACK_HOVER = { hex(0x737373), hex(0x5d5d5d) } -- + 0x2c2c2c on the hovered row
		local HOVER = hex(0x888888)                     -- menu / dropdown highlight
		local SEP = hex(0x777777)                       -- BackColors[0] | BackColors[1]
		local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
		local HL, HL_T = hex(0x33bb44), 1 - 0x77 / 255  -- MICROPROFILE_FRAME_HISTORY_COLOR_HIGHTLIGHT 0x7733bb44
		local SQUARE = Color3.fromRGB(215, 40, 20)      -- the square next to "Jobs Wall Time" (screenshot)
		local RULER_TEXT = hex(0x808080)
		local FRAME_LINE = hex(0xbbbbbb)
		local seqCache = {}
		-- MicroProfileBoxTypeBar: (c + max) / 2 at the top, (c + min) / 2 at the bottom
		local function barSeq(r, g, b)
			local key = r * 65536 + g * 256 + b
			local s = seqCache[key]
			if s then return s end
			local mx, mn = mmax(r, g, b, 30), mmin(r, g, b, 180)
			s = ColorSequence.new(Color3.fromRGB(floor((r + mx) / 2), floor((g + mx) / 2), floor((b + mx) / 2)),
				Color3.fromRGB(floor((r + mn) / 2), floor((g + mn) / 2), floor((b + mn) / 2)))
			seqCache[key] = s
			return s
		end
		local SEQ_CPU = barSeq(255, 127, 39)   -- MICROPROFILE_FRAME_HISTORY_COLOR_CPU 0xffff7f27
		local SEQ_GPU = barSeq(55, 160, 238)   -- MICROPROFILE_FRAME_HISTORY_COLOR_GPU 0xff37a0ee
		local SEQ_HOVER = barSeq(255, 255, 255) -- the hovered frame is drawn white

		-- -------------------------------------------------------------------------------- font
		local FONT, TEXT_SIZE = nil, 10
		pcall(function() FONT = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal) end)
		if not FONT then pcall(function() FONT = Font.fromEnum(Enum.Font.RobotoMono) end) end
		-- dy = how far every label is moved down (auto + the Settings correction)
		local TXT = { dy = 0, auto = 0, nudge = 0, all = {} }
		do
			local function measure(s, size)
				local ok, v = pcall(function() return TextService:GetTextSize(s, size, Enum.Font.RobotoMono, Vector2.new(10000, 1000)) end)
				if ok and typeof(v) == "Vector2" then return v end
				return nil
			end
			-- keep the exact 6 px grid: Roboto Mono advances 0.6 em, so the em has to be 10 px
			local v = measure(string.rep("M", 20), 10)
			if v and v.X > 60 and v.X < 240 then TEXT_SIZE = 10 * CW / (v.X / 20) end
			-- TextLabel.TextSize is the height of one text line. When that line holds the font's whole
			-- ascender..descender (Roboto Mono: 2146 / 555 per 2048 em) the baseline is 2146 / 2048 em
			-- under its top; when the line is one em tall, the ascender..descender box is centred on it.
			-- Roblox's MicroProfiler has its baseline 7.5 px under the row top (capitals on rows 0-7).
			local em = CW / 0.6
			local line = v and measure("M", TEXT_SIZE)
			local lineH = line and line.Y or TEXT_SIZE
			local base
			if lineH > em * 1.15 then base = em * 2146 / 2048 else base = em * (2048 + 2146 - 555) / 4096 end
			TXT.auto = floor(7.5 - base + 0.5)
			TXT.dy = TXT.auto
			log(sfmt("MicroProfiler text: TextSize %.2f, line %.2f px, baseline %.2f px, moved %d px", TEXT_SIZE, lineH, base, TXT.auto))
		end
		P.FontFace, P.TextSize = FONT, TEXT_SIZE

		-- -------------------------------------------------------------------------------- timers
		-- name, group, colour, parent. "Engine" values are read from Stats once per frame.
		local TIMERS = {
			{ "Frame", "Engine", 255, 127, 39 },
			{ "Render CPU", "Engine", 55, 160, 238 },
			{ "Render GPU", "Engine", 120, 200, 250 },
			{ "Heartbeat", "Engine", 235, 205, 70 },
			{ "Physics", "Engine", 95, 205, 115 },
			{ "HappaTAS", "HappaTAS", 185, 125, 255 },
			{ "Record", "HappaTAS", 255, 95, 95, "HappaTAS" },
			{ "Playback", "HappaTAS", 90, 225, 125, "HappaTAS" },
			{ "Client Objects", "HappaTAS", 75, 210, 230, "HappaTAS" },
			{ "Buttons", "HappaTAS", 240, 220, 85, "HappaTAS" },
			{ "Cursor", "HappaTAS", 255, 145, 210, "HappaTAS" },
			{ "Stats UI", "HappaTAS", 175, 175, 175, "HappaTAS" },
			{ "Profiler", "HappaTAS", 230, 230, 230 },
		}
		local NT = #TIMERS
		local TI = {}
		for i, t in ipairs(TIMERS) do
			TI[t[1]] = i
			t.name, t.group, t.parent = t[1], t[2], t[6]
			t.color = Color3.fromRGB(t[3], t[4], t[5])
			t.seq = barSeq(t[3], t[4], t[5])
		end
		local GROUPS = { "Engine", "HappaTAS" }
		local EV = { 0, 0, 0, 0, 0 } -- engine values of the frame: frame, render cpu, render gpu, heartbeat, physics

		local statOk = {}
		if Stats then
			for _, p in ipairs({ "RenderCPUFrameTime", "RenderGPUFrameTime", "HeartbeatTime", "PhysicsStepTime",
				"DataReceiveKbps", "DataSendKbps", "PhysicsReceiveKbps", "PhysicsSendKbps", "InstanceCount", "PrimitivesCount",
				"MovingPrimitivesCount", "ContactsCount", "SceneDrawcallCount", "SceneTriangleCount", "ShadowsDrawcallCount",
				"UI2DDrawcallCount" }) do
				local ok, v = pcall(function() return Stats[p] end)
				statOk[p] = ok and type(v) == "number"
			end
		end
		local function statRaw(p)
			if not statOk[p] then return 0 end
			local v = Stats[p]
			if type(v) ~= "number" or v ~= v then return 0 end
			return v
		end
		-- the *Time properties are documented in seconds (a value above 10 would already be milliseconds)
		local function statMs(p)
			local v = statRaw(p)
			if v < 0 then return 0 end
			if v < 10 then return v * 1000 end
			return v
		end

		-- -------------------------------------------------------------------------------- config
		local MODES = { "Detailed", "Timers", "Counters", "Frame", "Hidden" }
		local AGG = { 0, 10, 20, 30, 60, 120 }                         -- g_MicroProfileAggregatePresets
		local REF = { 5, 10, 15, 20, 33.33, 66.66, 100, 250, 500, 1000 } -- g_MicroProfileReferenceTimePresets
		local OPAC = { 0x40, 0x80, 0xc0, 0xff }                        -- g_MicroProfileOpacityPresets
		local PRESET_NAMES = { "Default", "Render", "GPU", "Lighting", "AI", "Visibility", "Sound" }
		local COLS = { "Time", "Average", "Max", "Min", "Call Count", "Exclusive Timers", "Exclusive Average", "Exclusive Max" }
		local BITS = { 1, 2, 4, 8, 16, 32, 64, 128 }
		local function defaults()
			return { mode = "Frame", force = false, aggregate = 60, ref = 33.33, bg = 0x40, fg = 0xff, spikes = false,
				bars = 2 + 4 + 16, all = true, groups = { Engine = true, HappaTAS = true }, network = 1, flame = false,
				custom = false, dumpIncomplete = false, dumpLegacy = false, dumpBinary = false }
		end
		local cfg = defaults()
		local presets = {}
		local function hasBit(n, b) return floor(n / b) % 2 == 1 end
		local function bgT() return 1 - cfg.bg / 255 end
		local function fgT() return 1 - cfg.fg / 255 end

		-- -------------------------------------------------------------------------------- state
		P.active = false
		P.OnScrub = nil -- function(frame) set by the core
		P.GetTAS = nil  -- function() -> data, frame, dataVersion
		local paused = false
		local frameNo = 0          -- frames since HappaTAS started (the number shown in the tooltip)
		local K = 0                -- frames recorded by the profiler
		local lastStart = nil      -- os.clock at the start of the frame in progress
		local lastMs = 0
		local HIS = { ms = {}, gpu = {}, ren = {}, job = {}, phy = {}, hap = {}, start = {}, no = {} } -- frame history ring
		-- sum / max / count = nFlipAggregate, nFlipMax, nAggregateFlipCount
		-- dsum / dmax / dframes = nFlipAggregateDisplay, nFlipMaxDisplay, nAggregateFrames; clear = nAggregateClear
		local AG = { sum = 0, max = 0, count = 0, dsum = 0, dmax = 0, dframes = 0, clear = false }
		-- the Time / Avg / Max readout (HappaTAS rule, the same for every Aggregate setting and in Hidden):
		-- Avg = the frames on the bar (the last NUM_FRAMES), Max = the biggest frame since the profiler
		-- opened, kept until a bigger one comes (picking Infinite in the Aggregate menu resets it)
		local RO = { sum = 0, max = 0, exact = 0 }
		local tAcc, tCnt, tStart = {}, {}, {}
		-- per timer: last frame (time, calls, exclusive), accumulating window (a*), shown window (d*)
		local TV = { last = {}, lastC = {}, lastX = {}, aT = {}, aMax = {}, aMin = {}, aC = {}, aX = {}, aXMax = {},
			dT = {}, dMax = {}, dMin = {}, dC = {}, dX = {}, dXMax = {} }
		local function clearTimerAcc()
			for j = 1, NT do TV.aT[j], TV.aMax[j], TV.aMin[j], TV.aC[j], TV.aX[j], TV.aXMax[j] = 0, 0, HUGE, 0, 0, 0 end
		end
		for j = 1, NT do
			TV.last[j], TV.lastC[j], TV.lastX[j] = 0, 0, 0
			TV.dT[j], TV.dMax[j], TV.dMin[j], TV.dC[j], TV.dX[j], TV.dXMax[j] = 0, 0, 0, 0, 0, 0
		end
		clearTimerAcc()

		-- begin / end times of every HappaTAS scope (only kept in Detailed mode)
		local LOG_N = 4096
		local slog = { name = {}, t0 = {}, t1 = {}, depth = {}, pos = 0, depthNow = 0, on = false, open = {} }
		local view = { offset = 0, range = 50 } -- UI.fDetailedOffset / fDetailedRange (ms, from the newest frame's start)

		local function hi(k) return (k - 1) % MAX_HISTORY + 1 end
		local function slotOf(k) return (k - 1) % NUM_FRAMES + 1 end
		-- the detailed view is measured from nFrameCurrent, which trails the newest frame by
		-- MICROPROFILE_GPU_FRAME_DELAY (3), so a 50 ms window at offset 0 shows the latest frames
		local function baseStart() return HIS.start[hi(mmax(1, K - 3))] end

		-- -------------------------------------------------------------------------------- timer API
		function P.Begin(name)
			if not P.active then return end
			local t = clock()
			tStart[name] = t
			if slog.on then
				slog.pos = slog.pos + 1
				local i = (slog.pos - 1) % LOG_N + 1
				slog.name[i], slog.t0[i], slog.t1[i], slog.depth[i] = name, t, false, slog.depthNow
				slog.open[name] = i
				slog.depthNow = slog.depthNow + 1
			end
		end
		function P.End(name)
			local s = tStart[name]
			if not s then return end
			local t = clock()
			tStart[name] = nil
			tAcc[name] = (tAcc[name] or 0) + (t - s)
			tCnt[name] = (tCnt[name] or 0) + 1
			if slog.on then
				local i = slog.open[name]
				if i then slog.t1[i] = t; slog.open[name] = nil end
				if slog.depthNow > 0 then slog.depthNow = slog.depthNow - 1 end
			end
		end
		function P.Heartbeat() end -- frame times come from PreRender, kept for the core

		local function clearAcc()
			for k in pairs(tAcc) do tAcc[k] = nil end
			for k in pairs(tCnt) do tCnt[k] = nil end
			slog.depthNow = 0
		end

		-- -------------------------------------------------------------------------------- aggregate
		-- MicroProfileFlip: add the frame, publish when the window is full (Infinite: every frame),
		-- start over unless the window is Infinite (or Infinite was just picked: nAggregateClear).
		local function aggregate(ms)
			AG.sum = AG.sum + ms
			if ms > AG.max then AG.max = ms end
			AG.count = AG.count + 1
			for j = 1, NT do
				local v, c, x = TV.last[j], TV.lastC[j], TV.lastX[j]
				TV.aT[j], TV.aC[j], TV.aX[j] = TV.aT[j] + v, TV.aC[j] + c, TV.aX[j] + x
				if v > TV.aMax[j] then TV.aMax[j] = v end
				if x > TV.aXMax[j] then TV.aXMax[j] = x end
				if c > 0 and v < TV.aMin[j] then TV.aMin[j] = v end
			end
			if cfg.aggregate == 0 or AG.count >= cfg.aggregate then
				AG.dframes, AG.dsum, AG.dmax = AG.count, AG.sum, AG.max
				for j = 1, NT do
					TV.dT[j], TV.dMax[j], TV.dC[j], TV.dX[j], TV.dXMax[j] = TV.aT[j], TV.aMax[j], TV.aC[j], TV.aX[j], TV.aXMax[j]
					TV.dMin[j] = (TV.aMin[j] == HUGE) and 0 or TV.aMin[j]
				end
				if cfg.aggregate ~= 0 or AG.clear then
					AG.clear = false
					AG.sum, AG.max, AG.count = 0, 0, 0
					clearTimerAcc()
				end
			end
		end

		-- records the frame that just ended. Returns true when a frame was added to the history.
		local function flip(dt, now)
			local ms = (dt or 0) * 1000
			local start = lastStart or (now - (dt or 0))
			lastStart = now
			if paused and not cfg.force then return false end -- Pause stops the capture (Force Enable keeps it)
			lastMs = ms
			K = K + 1
			local i = hi(K)
			EV[1], EV[2], EV[3] = ms, statMs("RenderCPUFrameTime"), statMs("RenderGPUFrameTime")
			EV[4], EV[5] = statMs("HeartbeatTime"), statMs("PhysicsStepTime")
			HIS.ms[i], HIS.ren[i], HIS.gpu[i], HIS.job[i], HIS.phy[i] = ms, EV[2], EV[3], EV[4], EV[5]
			HIS.start[i] = start
			HIS.no[i] = frameNo - 1
			RO.sum = RO.sum + ms
			if K > NUM_FRAMES then RO.sum = RO.sum - HIS.ms[hi(K - NUM_FRAMES)] end
			if ms > RO.max then RO.max = ms end
			RO.exact = RO.exact + 1
			if RO.exact >= 4096 then -- recount now and then, so the running sum can never drift
				RO.exact = 0
				local sum = 0
				for k = mmax(1, K - NUM_FRAMES + 1), K do sum = sum + HIS.ms[hi(k)] end
				RO.sum = sum
			end
			local childSum = 0
			for j = 1, NT do
				local v, c
				if j <= 5 then
					v, c = EV[j], 1
				else
					local n = TIMERS[j].name
					v, c = (tAcc[n] or 0) * 1000, tCnt[n] or 0
				end
				TV.last[j], TV.lastC[j], TV.lastX[j] = v, c, v
				if TIMERS[j].parent then childSum = childSum + v end
			end
			local hj = TI.HappaTAS
			TV.lastX[hj] = mmax(0, TV.last[hj] - childSum)
			HIS.hap[i] = TV.last[hj] + TV.last[TI.Profiler]
			if not paused then aggregate(ms) end
			return true
		end

		-- average of the frames on the bar / biggest frame on the bar
		local function readAvg()
			local n = mmin(K, NUM_FRAMES)
			if n <= 0 then return 0 end
			return RO.sum / n
		end
		local function visibleMax()
			local m = 0
			for k = mmax(1, K - NUM_FRAMES + 1), K do
				local v = HIS.ms[hi(k)]
				if v > m then m = v end
			end
			return m
		end
		-- picking Infinite restarts the frame count and resets Max (to the biggest frame still on the bar)
		local function pickInfinite()
			AG.clear = true
			RO.max = visibleMax()
		end

		-- -------------------------------------------------------------------------------- instances
		local U = { built = false }
		local W, H = 1920, 1080   -- screen in profiler pixels
		local mx, my = -1000, -1000
		-- the mouse in microprofile's model (MicroProfileMousePosition / MicroProfileMouseButton):
		-- downL / downR = button held (UI.nMouseDownLeft / Right), pressL / pressR = went down since the
		-- last frame, clickL / clickR = let go less than 3 px from where it went down (UI.nMouseLeft /
		-- Right), wheel = notches since the last frame. gx / gy = the pointer in AbsolutePosition space.
		local MS = { gx = 0, gy = 0, ev = false, px = nil, py = nil, downL = false, downR = false, pressL = false,
			pressR = false, clickL = false, clickR = false, wheel = 0, dx = 0, dy = 0, touch = nil }

		local function guiInset()
			if not GuiService then return 0, 0 end
			local ok, v = pcall(GuiService.GetGuiInset, GuiService)
			if ok and typeof(v) == "Vector2" then return v.X, v.Y end
			return 0, 0
		end
		-- the pointer in AbsolutePosition space. Input events carry it directly (InputObject.Position uses
		-- the same space as AbsolutePosition); with no event since the last frame, a changed
		-- UIS:GetMouseLocation() (screen space, top bar included) minus GuiService:GetGuiInset() is used.
		-- Without a mouse (touch screens) GetMouseLocation is undefined, so only the touches count.
		local function pointer()
			if UIS.MouseEnabled == false then return MS.gx, MS.gy end
			local ok, m = pcall(UIS.GetMouseLocation, UIS)
			if ok and typeof(m) == "Vector2" then
				local ix, iy = guiInset()
				local px, py = m.X - ix, m.Y - iy
				if MS.ev then
					MS.ev = false
				elseif px ~= MS.px or py ~= MS.py then
					MS.gx, MS.gy = px, py
				end
				MS.px, MS.py = px, py
			end
			return MS.gx, MS.gy
		end
		-- AbsolutePosition space -> profiler pixels
		local function toLocal(gx, gy)
			local p = U.root.AbsolutePosition
			return (gx - p.X) / SCALE, (gy - p.Y) / SCALE
		end

		local function newFrame(parent, color, z, transp)
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundColor3 = color or WHITE
			f.BackgroundTransparency = transp or 0
			f.ZIndex = z or 1
			f.Size = UDim2.fromOffset(0, 0)
			f.Parent = parent
			return f
		end
		local function newButton(parent, z)
			local b = Instance.new("TextButton")
			b.AutoButtonColor = false
			b.BorderSizePixel = 0
			b.BackgroundTransparency = 1
			b.Text = ""
			b.ZIndex = z or 1
			b.Size = UDim2.fromOffset(0, 0)
			b.Parent = parent
			return b
		end
		-- every object remembers what it wrote last, so an unchanged value costs no property write
		local function box(parent, color, z, transp) return { f = newFrame(parent, color, z, transp) } end
		local function place(o, x, y, w, h)
			if o.x ~= x or o.y ~= y then o.x, o.y = x, y; o.f.Position = UDim2.fromOffset(x, y) end
			if w and (o.w ~= w or o.h ~= h) then o.w, o.h = w, h; o.f.Size = UDim2.fromOffset(w, h) end
		end
		local function show(o, v)
			if o.vis ~= v then o.vis = v; (o.f or o.sh).Visible = v end
		end
		local function paint(o, c, t)
			if o.c ~= c then o.c = c; o.f.BackgroundColor3 = c end
			if t and o.t ~= t then o.t = t; o.f.BackgroundTransparency = t end
		end
		local function gradBox(parent, z)
			local o = box(parent, WHITE, z)
			local g = Instance.new("UIGradient")
			g.Rotation = 90
			g.Parent = o.f
			o.g = g
			return o
		end
		local function grad(o, seq) if o.seq ~= seq then o.seq = seq; o.g.Color = seq end end

		-- text with the 1 px black drop shadow; the shadow is the parent, so one move moves both.
		-- plain = a single label in that colour (bar labels are black, no shadow)
		local function text(parent, z, plain)
			local sh = Instance.new("TextLabel")
			sh.BackgroundTransparency = 1
			sh.BorderSizePixel = 0
			if FONT then sh.FontFace = FONT else sh.Font = Enum.Font.Code end
			sh.TextSize = TEXT_SIZE
			sh.TextColor3 = plain or BLACK
			sh.TextXAlignment = Enum.TextXAlignment.Left
			sh.TextYAlignment = Enum.TextYAlignment.Top
			sh.TextWrapped = false
			sh.Text = ""
			sh.ZIndex = z or 1
			sh.Size = UDim2.fromOffset(0, RH + 2)
			local o = { sh = sh, s = "", plain = plain ~= nil }
			TXT.all[#TXT.all + 1] = o
			if not plain then
				local lb = sh:Clone()
				lb.TextColor3 = WHITE
				lb.Position = UDim2.fromOffset(-1, -1)
				lb.Size = UDim2.new(1, 0, 1, 0)
				lb.Parent = sh
				o.lb = lb
			end
			sh.Parent = parent
			return o
		end
		local function say(o, s, x, y)
			if o.s ~= s then
				o.s = s
				o.sh.Text = s
				if o.lb then o.lb.Text = s end
				local w = #s * CW + 2
				if o.w ~= w then o.w = w; o.sh.Size = UDim2.fromOffset(w, RH + 2) end
			end
			if x and (o.x ~= x or o.y ~= y or o.dy ~= TXT.dy) then
				o.x, o.y, o.dy = x, y, TXT.dy
				local dx = o.plain and 0 or 1
				o.sh.Position = UDim2.fromOffset(x + dx, y + dx + TXT.dy)
			end
		end
		-- Settings > MicroProfiler Text Offset: whole pixels, - moves the text up, + down
		function P.SetTextNudge(n)
			n = floor((tonumber(n) or 0) + 0.5)
			if n ~= n then n = 0 end
			n = clampn(n, -6, 6)
			TXT.nudge = n
			TXT.dy = TXT.auto + n
			for _, o in ipairs(TXT.all) do
				if o.x then say(o, o.s, o.x, o.y) end
			end
		end
		function P.TextOffset() return TXT.dy, TXT.auto, TXT.nudge end
		local function tint(o, c)
			if o.c ~= c then
				o.c = c
				if o.lb then o.lb.TextColor3 = c else o.sh.TextColor3 = c end
			end
		end

		-- MicroProfileDrawFloatWindow: border, black box, label left, value right, optional colour squares
		local function window(z)
			local w = { rows = {}, n = 0, z = z }
			w.outer = box(U.root, WHITE, z)
			w.inner = box(w.outer.f, BLACK, z)
			w.inner.f.Position = UDim2.fromOffset(1, 1)
			show(w.outer, false)
			return w
		end
		local function windowShow(w, x, y, rows, border)
			local colors, maxLen = false, 0
			for _, r in ipairs(rows) do
				if r[3] then colors = true end
				local l = #r[1] + #r[2]
				if l > maxLen then maxLen = l end
			end
			local cx = colors and CW or 0
			local ww = CW * (2 + maxLen) + 2 + cx
			local hh = RH * #rows + 2
			if x + ww > W then x = W - ww end
			if y + hh > H then y = H - hh end
			if x < 1 then x = 1 end
			if y < 1 then y = 1 end
			x, y = floor(x), floor(y)
			place(w.outer, x - 1, y - 1, ww + 2, hh + 2)
			paint(w.outer, border or WHITE)
			place(w.inner, 1, 1, ww, hh)
			for i, r in ipairs(rows) do
				local row = w.rows[i]
				if not row then
					row = { l = text(w.inner.f, w.z + 1), v = text(w.inner.f, w.z + 1), sq = box(w.inner.f, SQUARE, w.z + 1) }
					w.rows[i] = row
				end
				local ry = (i - 1) * RH
				say(row.l, r[1], cx + 1, ry + 1)
				say(row.v, r[2], ww - #r[2] * CW, ry + 1)
				show(row.l, true)
				show(row.v, true)
				if r[3] then
					place(row.sq, cx - TW, ry, TW, TW)
					paint(row.sq, r[3])
					show(row.sq, true)
				else
					show(row.sq, false)
				end
			end
			for i = #rows + 1, w.n do
				local row = w.rows[i]
				show(row.l, false)
				show(row.v, false)
				show(row.sq, false)
			end
			w.n = #rows
			w.x, w.y, w.w, w.h = x - 1, y - 1, ww + 2, hh + 2
			show(w.outer, true)
		end
		local function windowHide(w) if w then show(w.outer, false) end end

		-- -------------------------------------------------------------------------------- menus
		local menuX, activeMenu, helpOn = {}, nil, false
		local dd = { menu = nil, count = 0, width = 0, lines = {} }
		local timersDirty, countersDirty = true, true
		local actions = {} -- filled below (dump, presets, modes) once the functions exist

		local OPTIONS = { { false, 0, "Reference" } }
		for i, v in ipairs(REF) do OPTIONS[#OPTIONS + 1] = { 0, i, sfmt("  %6.2fms", v) } end
		OPTIONS[#OPTIONS + 1] = { false, 0, "BG Opacity" }
		for i = 1, 4 do OPTIONS[#OPTIONS + 1] = { 1, i, sfmt("  %7d%%", i * 25) } end
		OPTIONS[#OPTIONS + 1] = { false, 0, "FG Opacity" }
		for i = 1, 4 do OPTIONS[#OPTIONS + 1] = { 2, i, sfmt("  %7d%%", i * 25) } end
		OPTIONS[#OPTIONS + 1] = { false, 0, "Spike Display" }
		OPTIONS[#OPTIONS + 1] = { 3, 0, "  Enable" }

		local function allGroupsOn()
			for _, g in ipairs(GROUPS) do if not cfg.groups[g] then return false end end
			return true
		end
		local function tasLabelCount() return actions.tasCount and actions.tasCount() or 0 end

		local MENUS = {
			{ label = "Mode",
				item = function(i)
					if i < 5 then return MODES[i + 1], cfg.mode == MODES[i + 1] end
					if i == 5 then return "Off", false end
					if i == 6 then return "------", false end
					if i == 7 then return "Force Enable", cfg.force end
					return nil
				end,
				click = function(i)
					if i < 5 then P.SetMode(MODES[i + 1])
					elseif i == 5 then P.Close()
					elseif i == 7 then cfg.force = not cfg.force end
				end },
			{ label = "Groups",
				item = function(i)
					if i == 0 then return "[ALL]", cfg.all end
					if i == 1 then return "[default]", allGroupsOn() end
					local g = GROUPS[i - 1]
					if g then return "   " .. g, cfg.groups[g] == true end
					return nil
				end,
				click = function(i)
					if i == 0 then
						cfg.all = not cfg.all
					elseif i == 1 then
						local v = not allGroupsOn()
						for _, g in ipairs(GROUPS) do cfg.groups[g] = v end
					elseif GROUPS[i - 1] then
						cfg.groups[GROUPS[i - 1]] = not cfg.groups[GROUPS[i - 1]]
					end
					timersDirty = true
				end },
			{ label = function()
					-- "Aggregate[%d]", nAggregateFlip ? nAggregateFlip : nAggregateFlipCount
					if cfg.aggregate ~= 0 then return "Aggregate[" .. cfg.aggregate .. "]" end
					if cfg.custom then return "Aggregate[" .. tasLabelCount() .. "]" end
					return "Aggregate[" .. AG.count .. "]"
				end,
				item = function(i)
					local v = AGG[i + 1]
					if v == nil then return nil end
					return (v == 0) and "Infinite" or sfmt("%7d", v), cfg.aggregate == v
				end,
				click = function(i)
					local v = AGG[i + 1]
					if v == nil then return end
					cfg.aggregate = v
					if v == 0 then pickInfinite() end -- like MicroProfileUIClickAggregate's nAggregateClear
				end },
			{ label = "Timers",
				item = function(i)
					if i < 8 then return COLS[i + 1], hasBit(cfg.bars, BITS[i + 1]) end
					if i == 8 then return "------", false end
					return nil
				end,
				click = function(i)
					if i < 8 then
						local b = BITS[i + 1]
						cfg.bars = hasBit(cfg.bars, b) and (cfg.bars - b) or (cfg.bars + b)
						timersDirty = true
					end
				end },
			{ label = "Options",
				item = function(i)
					local o = OPTIONS[i + 1]
					if not o then return nil end
					local sel = false
					if o[1] == 0 then sel = cfg.ref == REF[o[2]]
					elseif o[1] == 1 then sel = cfg.bg == OPAC[o[2]]
					elseif o[1] == 2 then sel = cfg.fg == OPAC[o[2]]
					elseif o[1] == 3 then sel = cfg.spikes end
					return o[3], sel
				end,
				click = function(i)
					local o = OPTIONS[i + 1]
					if not o or not o[1] then return end
					if o[1] == 0 then cfg.ref = REF[o[2]]
					elseif o[1] == 1 then cfg.bg = OPAC[o[2]]
					elseif o[1] == 2 then cfg.fg = OPAC[o[2]]
					elseif o[1] == 3 then cfg.spikes = not cfg.spikes end
					U.barsDirty, timersDirty, countersDirty = true, true, true
				end },
			{ label = "Preset",
				item = function(i)
					local n = #PRESET_NAMES
					if i < n then return "Load '" .. PRESET_NAMES[i + 1] .. "'", false end
					if i == n then return "--", false end
					if i <= 2 * n then return "Save '" .. PRESET_NAMES[i - n] .. "'", false end
					return nil
				end,
				click = function(i)
					local n = #PRESET_NAMES
					if i < n then actions.loadPreset(PRESET_NAMES[i + 1])
					elseif i > n and i <= 2 * n then actions.savePreset(PRESET_NAMES[i - n]) end
				end },
			{ label = "Custom",
				item = function(i)
					if i == 0 then return "Disable", not cfg.custom end
					if i == 1 then return "--", false end
					if i == 2 then return "TAS Timeline", cfg.custom == true end
					return nil
				end,
				click = function(i)
					if i == 0 then cfg.custom = false elseif i == 2 then cfg.custom = true end
					U.barsDirty = true
					if actions.applyMode then actions.applyMode() end
				end },
			{ label = "[Dump]",
				item = function(i)
					if i < 4 then return sfmt("%d frames", 32 * BITS[i + 1]), false end
					if i == 4 then return sfmt("512 frames (%d complete)", mmin(K, MAX_HISTORY)), false end
					if i == 5 then return "Include incomplete", cfg.dumpIncomplete end
					if i == 6 then return "Legacy HTML format", cfg.dumpLegacy end
					if i == 7 then return "Dump in binary format (LibMP)", cfg.dumpBinary end
					return nil
				end,
				click = function(i)
					if i < 5 then actions.dump(32 * BITS[i + 1])
					elseif i == 5 then cfg.dumpIncomplete = not cfg.dumpIncomplete
					elseif i == 6 then cfg.dumpLegacy = not cfg.dumpLegacy
					elseif i == 7 then cfg.dumpBinary = not cfg.dumpBinary end
				end },
			{ label = "Flamegraphs",
				item = function(i)
					if i == 0 then return "Disable", not cfg.flame end
					if i == 1 then return "--", false end
					if i == 2 then return "HappaTAS", cfg.flame end
					return nil
				end,
				click = function(i)
					if i == 0 then cfg.flame = false elseif i == 2 then cfg.flame = true end
				end },
			{ label = function() return paused and "Unpause" or "Pause" end,
				press = function() P.TogglePause() end },
			{ label = "Help", help = true },
			{ label = "Network",
				item = function(i)
					if i == 0 then return "Verbosity Level", false end
					if i == 1 then return "Off", cfg.network == 0 end
					if i == 2 then return "Low", cfg.network == 1 end
					if i == 3 then return "High", cfg.network == 2 end
					return nil
				end,
				click = function(i)
					if i >= 1 and i <= 3 then cfg.network = i - 1; countersDirty = true end
				end },
		}
		P.Menus = MENUS

		local function menuLabel(def)
			if type(def.label) == "function" then return def.label() end
			return def.label
		end

		local function ddLine(n)
			local l = dd.lines[n]
			if l then return l end
			-- the button only keeps clicks away from the game; updateMenus reads the clicks
			l = { hl = box(U.dd.f, HOVER, 11), t = text(U.dd.f, 12), b = { f = newButton(U.dd.f, 13) } }
			show(l.hl, false)
			dd.lines[n] = l
			return l
		end

		-- the open menu's lines: "%c %s" with '*' on the selected entries
		function actions.ddRender(m)
			local def = MENUS[m]
			local lines, maxLen = {}, 0
			local i = 0
			while i < 200 do
				local s, sel = def.item(i)
				if s == nil then break end
				lines[#lines + 1] = { s, sel }
				if #s > maxLen then maxLen = #s end
				i = i + 1
			end
			local w = (2 + maxLen) * CW
			place(U.dd, menuX[m], RH, w, #lines * RH)
			for n, l in ipairs(lines) do
				local line = ddLine(n)
				local ly = (n - 1) * RH
				place(line.hl, 0, ly, w, RH)
				place(line.b, 0, ly, w, RH)
				say(line.t, (l[2] and "*" or " ") .. " " .. l[1], 0, ly)
				show(line.t, true)
				show(line.b, true)
			end
			for n = #lines + 1, dd.count do
				local line = dd.lines[n]
				show(line.t, false)
				show(line.b, false)
				show(line.hl, false)
			end
			dd.count, dd.menu, dd.width = #lines, m, w
			show(U.dd, true)
		end
		local function ddClose()
			if dd.menu then dd.menu = nil; show(U.dd, false) end
		end

		-- only the Aggregate[N] and Pause / Unpause labels change: a new label of the same length is just
		-- written (every frame with Aggregate Infinite), the bar is laid out again when one changes length
		local BAR = { labels = {}, built = false, dyn = {} }
		for i, def in ipairs(MENUS) do
			if type(def.label) == "function" then BAR.dyn[#BAR.dyn + 1] = i end
		end
		local function layoutMenuBar()
			if BAR.built then
				local relayout = false
				for _, i in ipairs(BAR.dyn) do
					local s = MENUS[i].label()
					local old = BAR.labels[i]
					if s ~= old then
						if #s ~= #old then relayout = true break end
						BAR.labels[i] = s
						say(U.items[i].t, s, menuX[i], 0)
					end
				end
				if not relayout then return end
			end
			BAR.built = true
			local x = (#"MicroProfiler" + 1 + 2) * CW -- (sizeof("MicroProfiler") + 2) characters
			for i, def in ipairs(MENUS) do
				local s = menuLabel(def)
				local it = U.items[i]
				BAR.labels[i] = s
				menuX[i] = x
				say(it.t, s, x, 0)
				local w = #s * CW
				place(it.hl, x - 1, 0, w + 1, MENU_H)
				place(it.b, x - 1, 0, w + 1, MENU_H)
				x = x + (#s + 1) * CW
			end
		end

		-- hover opens a menu, it stays open while the mouse is inside it, a click on a hovered line
		-- runs it (MicroProfileDrawMenu: nSelectMenu / nActiveMenu, UI.nMouseLeft || UI.nMouseRight)
		local function updateMenus()
			local click = MS.clickL or MS.clickR
			local sel = nil
			-- UI.nMouseY <= MICROPROFILE_TEXT_HEIGHT for whole pixels; "< RH" leaves no gap to the dropdown
			-- (which starts at RH) when the size setting makes the mouse position fractional
			if my >= 0 and my < RH then
				for i = 1, #MENUS do
					local len = #U.items[i].t.s
					if mx >= menuX[i] and mx <= menuX[i] + len * CW then sel = i end
				end
			end
			for i = 1, #MENUS do show(U.items[i].hl, sel == i) end
			if sel and click and MENUS[sel].press then -- Pause / Unpause (S.nToggleRunning)
				MENUS[sel].press()
				P.SaveConfig()
			end
			local m = sel or activeMenu
			activeMenu = sel
			if m and MENUS[m].item then
				if dd.menu ~= m then actions.ddRender(m) end
				local x0, y0 = menuX[m], RH
				local h = dd.count * RH
				if my <= y0 + h and my >= y0 and mx <= x0 + dd.width and mx >= x0 then activeMenu = m end
				local hov = nil
				if my >= y0 and my < y0 + h and mx >= x0 and mx <= x0 + dd.width then hov = floor((my - y0) / RH) + 1 end
				if hov and click and MENUS[m].click then
					MENUS[m].click(hov - 1)
					P.SaveConfig()
					if dd.menu and P.active then actions.ddRender(m) end
				end
				for n = 1, dd.count do show(dd.lines[n].hl, hov == n) end
			else
				ddClose()
			end
			helpOn = (m ~= nil and MENUS[m].help == true)
		end

		-- -------------------------------------------------------------------------------- frame graph
		local slotK, slotH = {}, {}
		local K0, stripX, hlKey = 0, nil, nil
		local hoverK = nil
		U.barsDirty = true

		local function graphVisible() return cfg.mode == "Frame" or cfg.mode == "Detailed" end
		local function graphW() return W - CLOSE_W end
		local function liveSeq(k)
			local i = hi(k)
			-- Roblox: orange when Jobs Wall Time > Render Wall Time, blue when render is longer
			if HIS.job[i] >= HIS.ren[i] then return SEQ_CPU end
			return SEQ_GPU
		end
		local function barH(ms)
			if not ms or ms <= 0 then return 0 end
			local f = ms / cfg.ref
			if f > 1 then f = 1 end
			return ceil(f * HIST_H - 1e-9) -- top edge = (int)(base + (1 - ms / reference) * 50)
		end
		local function drawBar(k, ms, seq)
			local s = slotOf(k)
			local b = U.bars[s]
			if slotK[s] ~= k then
				slotK[s] = k
				b.f.Position = UDim2.new((k - K0) / NUM_FRAMES, 0, 1, 0)
			end
			local h = barH(ms)
			if slotH[s] ~= h then
				slotH[s] = h
				b.f.Size = UDim2.new(1 / NUM_FRAMES, 0, 0, h)
			end
			grad(b, (k == hoverK) and SEQ_HOVER or seq)
		end
		local function clearBar(s)
			if slotH[s] ~= 0 then slotH[s] = 0; U.bars[s].f.Size = UDim2.new(1 / NUM_FRAMES, 0, 0, 0) end
			slotK[s] = nil
		end
		-- the bars live in a strip that slides one bar per frame: one bar + one strip write per frame
		local function setStrip(first)
			if first - K0 > 50000 or first < K0 then
				K0 = first
				for s = 1, NUM_FRAMES do
					local k = slotK[s]
					if k then U.bars[s].f.Position = UDim2.new((k - K0) / NUM_FRAMES, 0, 1, 0) end
				end
				hlKey = nil
			end
			local x = -(first - K0) / NUM_FRAMES
			if stripX ~= x then stripX = x; U.strip.Position = UDim2.new(x, 0, 0, 0) end
		end
		local function redrawLive()
			local first = K - NUM_FRAMES + 1
			setStrip(first)
			for k = first, K do
				if k >= 1 then
					local i = hi(k)
					drawBar(k, HIS.ms[i], liveSeq(k))
				else
					clearBar(slotOf(k))
				end
			end
		end
		local hlA, hlB = nil, nil
		local function setHL(kFirst, kLast)
			if not kFirst or not kLast or kFirst > kLast then show(U.hl, false) return end
			if hlKey ~= K0 or hlA ~= kFirst then
				U.hl.f.Position = UDim2.new((kFirst - K0) / NUM_FRAMES, 0, 0, 0)
			end
			if hlKey ~= K0 or hlB - hlA ~= kLast - kFirst then
				U.hl.f.Size = UDim2.new((kLast - kFirst + 1) / NUM_FRAMES, 0, 1, 0)
			end
			hlKey, hlA, hlB = K0, kFirst, kLast
			show(U.hl, true)
		end
		local function frameEnd(k)
			if k < K then return HIS.start[hi(k + 1)] end
			return HIS.start[hi(K)] + HIS.ms[hi(K)] / 1000
		end
		-- green overlay = the frames inside the detailed view's time window
		local function updateHighlight()
			if K < 1 then show(U.hl, false) return end
			local base = baseStart()
			local w0 = base + view.offset / 1000
			local w1 = w0 + view.range / 1000
			local first = mmax(1, K - NUM_FRAMES + 1)
			local kLast, kFirst = nil, nil
			if HIS.start[hi(first)] < w1 then
				local lo, up = first, K
				while lo < up do
					local mid = floor((lo + up + 1) / 2)
					if HIS.start[hi(mid)] < w1 then lo = mid else up = mid - 1 end
				end
				kLast = lo
			end
			if frameEnd(K) > w0 then
				local lo, up = first, K
				while lo < up do
					local mid = floor((lo + up) / 2)
					if frameEnd(mid) > w0 then up = mid else lo = mid + 1 end
				end
				kFirst = lo
			end
			setHL(kFirst, kLast)
		end

		-- frame index under the mouse (nil when not over the bars)
		local function graphIndex()
			if activeMenu ~= nil or not graphVisible() then return nil end
			local gw = graphW()
			if mx < 0 or mx >= gw or my < MENU_H or my >= MENU_H + HIST_H then return nil end
			local back = floor(NUM_FRAMES * (gw - mx) / gw)
			return back, (NUM_FRAMES * mx / gw) % 1
		end

		-- -------------------------------------------------------------------------------- TAS timeline (Custom)
		local tas = { a = nil, version = nil, len = -1, f = 1, cv = nil, cf = 0, ca = nil, sum = 0, max = 0, agg = -1 }
		local function tasData()
			if not P.GetTAS then return nil end
			return P.GetTAS()
		end
		function actions.tasCount()
			local data, f = tasData()
			if type(data) ~= "table" or #data == 0 then return 0 end
			return clampn(math.floor(tonumber(f) or 1), 1, #data)
		end
		local function tasFrameMs(fr) return (fr and fr.FrameTime or 0) * 1000 end
		local function tasStep()
			local data, f, version = tasData()
			if type(data) ~= "table" then return end
			local n = #data
			f = clampn(math.floor(tonumber(f) or 1), 1, mmax(1, n))
			tas.f = f
			local a = tas.a
			local full = U.barsDirty or version ~= tas.version or n < tas.len or a == nil
			if a == nil or f < a + floor(NUM_FRAMES * 0.15) or f > a + floor(NUM_FRAMES * 0.85) then
				a = mmax(1, f - floor(NUM_FRAMES * 0.7))
				full = true
			end
			if full then
				U.barsDirty = false
				setStrip(a)
				for k = a, a + NUM_FRAMES - 1 do
					if data[k] then drawBar(k, tasFrameMs(data[k]), SEQ_CPU) else clearBar(slotOf(k)) end
				end
			elseif n > tas.len then
				for k = mmax(a, tas.len + 1), mmin(n, a + NUM_FRAMES - 1) do drawBar(k, tasFrameMs(data[k]), SEQ_CPU) end
			end
			tas.a, tas.version, tas.len = a, version, n
			setHL(f, f)
		end
		-- TAS Timeline readout: Time = the current TAS frame, Avg = the TAS frames on the bar,
		-- Max = the biggest frame of the whole TAS
		local function tasReadout()
			local data, f, version = tasData()
			if type(data) ~= "table" or #data == 0 then return 0, 0, 0 end
			local n = #data
			f = clampn(math.floor(tonumber(f) or 1), 1, n)
			local cur = tasFrameMs(data[f])
			local a = tas.a or mmax(1, f - floor(NUM_FRAMES * 0.7))
			local b = mmin(n, a + NUM_FRAMES - 1)
			if tas.wv == version and tas.wa == a and tas.wb and b >= tas.wb then
				for k = tas.wb + 1, b do tas.wsum = tas.wsum + tasFrameMs(data[k]) end
			else
				local sum = 0
				for k = a, b do sum = sum + tasFrameMs(data[k]) end
				tas.wsum = sum
			end
			tas.wv, tas.wa, tas.wb = version, a, b
			if tas.mv == version and tas.mn and n >= tas.mn then
				local mxv = tas.mmax
				for k = tas.mn + 1, n do
					local v = tasFrameMs(data[k])
					if v > mxv then mxv = v end
				end
				tas.mmax = mxv
			else
				local mxv = 0
				for k = 1, n do
					local v = tasFrameMs(data[k])
					if v > mxv then mxv = v end
				end
				tas.mmax = mxv
			end
			tas.mv, tas.mn = version, n
			return cur, tas.wsum / mmax(1, b - a + 1), tas.mmax
		end

		-- -------------------------------------------------------------------------------- hover / tooltip
		local memMb, memAt = 0, -1000
		local function memUsed()
			if frameNo - memAt >= 30 then
				memAt = frameNo
				local ok, v = pcall(function() return Stats:GetTotalMemoryUsageMb() end)
				if ok and type(v) == "number" then memMb = v end
			end
			return memMb
		end
		local function luaHeapMb()
			local ok, v = pcall(collectgarbage, "count")
			if ok and type(v) == "number" then return v / 1024 end
			return 0
		end
		local function setHover(k)
			if hoverK == k then return end
			local old = hoverK
			hoverK = k
			if old then
				local s = slotOf(old)
				if slotK[s] == old then grad(U.bars[s], cfg.custom and SEQ_CPU or liveSeq(old)) end
			end
			if k then
				local s = slotOf(k)
				if slotK[s] == k then grad(U.bars[s], SEQ_HOVER) end
			end
		end
		local function frameTip(k)
			local i = hi(k)
			local rows = {
				{ "Frame " .. tostring(HIS.no[i]), "" },
				{ "CPU Time", sfmt("%6.2fms", HIS.ms[i]) },
				{ "GPU Time (device)", sfmt("%6.2fms", HIS.gpu[i]) },
				{ "", "" },
				{ "Render Wall Time", sfmt("%6.2fms", HIS.ren[i]) },
				{ "Jobs Wall Time", sfmt("%6.2fms", HIS.job[i]), SQUARE },
				{ "", "" },
				{ "Mem Used", sfmt("%.1fMB", memUsed()) },
				{ "HappaTAS", sfmt("%6.2fms", HIS.hap[i]) },
			}
			if cfg.network >= 2 then
				rows[#rows + 1] = { "Net Receive", sfmt("%.2fKB/s", statRaw("DataReceiveKbps")) }
				rows[#rows + 1] = { "Net Send", sfmt("%.2fKB/s", statRaw("DataSendKbps")) }
			end
			return rows
		end
		local function hoverUpdate()
			local back, frac = graphIndex()
			local k = nil
			if back then
				if cfg.custom then
					if tas.a then k = tas.a + NUM_FRAMES - 1 - back end
					local data = tasData()
					if not (type(data) == "table" and k and data[k]) then k = nil end
				else
					k = K - back
					if k < 1 then k = nil end
				end
			end
			setHover(k)
			if k then
				local rows
				if cfg.custom then
					local data = tasData()
					local fr = data[k]
					rows = { { "Frame " .. k, "" }, { "Frame Time", sfmt("%6.2fms", tasFrameMs(fr)) },
						{ "Total Time", sfmt("%.3fs", fr.TotalTime or 0) } }
				else
					rows = frameTip(k)
				end
				windowShow(U.tip, mx, my + 20, rows, WHITE)
			end
			return k, frac
		end

		-- -------------------------------------------------------------------------------- detailed view
		local det = { stripes = {}, lines = {}, bars = {}, nStripes = 0, nLines = 0, nBars = 0, hover = nil }
		local function detStripe(n)
			local s = det.stripes[n]
			if not s then
				s = { b = box(U.det.f, BACK[1], 2), t = text(U.det.f, 3) }
				tint(s.t, RULER_TEXT)
				det.stripes[n] = s
			end
			return s
		end
		local function detLine(n)
			local l = det.lines[n]
			if not l then l = box(U.det.f, FRAME_LINE, 4); det.lines[n] = l end
			return l
		end
		local function detBar(n)
			local b = det.bars[n]
			if not b then b = { b = gradBox(U.det.f, 5), t = text(U.det.f, 6, BLACK) }; det.bars[n] = b end
			return b
		end
		local function detailUpdate(hoverAllowed)
			det.hover = nil
			if K < 1 then return end
			local base = baseStart()
			local range = view.range
			local w0 = base + view.offset / 1000
			local w1 = w0 + range / 1000
			local px = W / range
			-- background stripes, one per time step, with the step written in each one
			local step = 10 ^ (floor(2 * (math.log10(range) - 1)) / 2)
			local label = ""
			if step >= 0.005 and step <= 1000 then
				label = (step >= 1) and sfmt("%.3gms", step) or sfmt("%.2fms", step)
			end
			local f = floor(view.offset / step) * step
			local colorIndex = floor(view.offset / step)
			local n = 0
			while f < view.offset + range and n < 64 do
				n = n + 1
				local s = detStripe(n)
				local x0 = floor((f - view.offset) * px)
				local x1 = floor((f + step - view.offset) * px + 1)
				place(s.b, x0, 0, x1 - x0, DET_H)
				paint(s.b, BACK[colorIndex % 2 + 1], bgT())
				show(s.b, true)
				if label ~= "" then
					say(s.t, label, x0 + floor((step * px - #label * CW) / 2), 0)
					show(s.t, true)
				else
					show(s.t, false)
				end
				colorIndex = colorIndex + 1
				f = f + step
			end
			for i = n + 1, det.nStripes do show(det.stripes[i].b, false); show(det.stripes[i].t, false) end
			det.nStripes = n
			-- light grey line at the start of every frame
			local nl = 0
			local k = K
			while k >= 1 and K - k < MAX_HISTORY and nl < 128 do
				local st = HIS.start[hi(k)]
				if st < w0 then break end
				if st <= w1 then
					nl = nl + 1
					local l = detLine(nl)
					place(l, floor((st - w0) * 1000 * px), 0, 1, DET_H)
					paint(l, FRAME_LINE, fgT())
					show(l, true)
				end
				k = k - 1
			end
			for i = nl + 1, det.nLines do show(det.lines[i], false) end
			det.nLines = nl
			say(det.thread, "HappaTAS (Lua)", 2, RH)
			-- the scopes, depth 0 (HappaTAS) above depth 1 (its systems)
			local nb, idx, count = 0, slog.pos, 0
			local now = clock()
			while count < LOG_N and idx >= 1 do
				local i = (idx - 1) % LOG_N + 1
				local t0 = slog.t0[i]
				if not t0 or t0 < w0 - 1 then break end
				local e = slog.t1[i] or now
				if e >= w0 and t0 <= w1 and nb < 240 then
					nb = nb + 1
					local b = detBar(nb)
					local x0 = floor((t0 - w0) * 1000 * px)
					local x1 = floor((e - w0) * 1000 * px)
					if x1 <= x0 then x1 = x0 + 1 end
					local y = 2 * RH + mmin(slog.depth[i], 1) * BAR_H
					place(b.b, x0, y, x1 - x0, BAR_H - 1)
					local t = TIMERS[TI[slog.name[i]] or 1]
					grad(b.b, t.seq)
					paint(b.b, WHITE, fgT())
					show(b.b, true)
					local wpx = x1 - x0
					if wpx > 3 * TW then
						local chars = floor((wpx - TW) / CW)
						say(b.t, t.name:sub(1, chars), x0 + 1, y + 1)
						show(b.t, true)
					else
						show(b.t, false)
					end
					if hoverAllowed and mx >= x0 and mx < x1 and my >= DET_Y + y and my < DET_Y + y + BAR_H then
						det.hover = { name = t.name, ms = (e - t0) * 1000, t0 = t0, t1 = e }
					end
				end
				idx = idx - 1
				count = count + 1
			end
			for i = nb + 1, det.nBars do show(det.bars[i].b, false); show(det.bars[i].t, false) end
			det.nBars = nb
		end
		local function timerTip(name, ms)
			local j = TI[name] or 1
			local fr = mmax(AG.dframes, 1)
			local calls = (TV.dC[j] > 0) and TV.dC[j] or 1
			local rows = { { "Timer:", name } }
			if ms then rows[#rows + 1] = { "Time:", sfmt("%6.3fms", ms) } end
			rows[#rows + 1] = { "", "" }
			rows[#rows + 1] = { "Frame Time:", sfmt("%6.3fms", TV.last[j]) }
			rows[#rows + 1] = { "Average:", sfmt("%6.3fms", TV.dT[j] / fr) }
			rows[#rows + 1] = { "Max:", sfmt("%6.3fms", TV.dMax[j]) }
			rows[#rows + 1] = { "Min:", sfmt("%6.3fms", TV.dMin[j]) }
			rows[#rows + 1] = { "", "" }
			rows[#rows + 1] = { "Call Average:", sfmt("%6.3fms", TV.dT[j] / calls) }
			rows[#rows + 1] = { "Call Count:", sfmt("%6.2f", TV.dC[j] / fr) }
			rows[#rows + 1] = { "Group:", TIMERS[j].group }
			return rows
		end

		-- -------------------------------------------------------------------------------- Timers mode
		local tim = { rows = {}, cells = {}, heads = {}, seps = {}, n = 0, layout = nil }
		local function timersLayout()
			local groups = {}
			local maxLen = 1
			for _, g in ipairs(GROUPS) do
				if cfg.all or cfg.groups[g] then
					local ts = {}
					for j = 1, NT do
						if TIMERS[j].group == g then
							ts[#ts + 1] = j
							if #TIMERS[j].name > maxLen then maxLen = #TIMERS[j].name end
						end
					end
					groups[#groups + 1] = { g, ts }
				end
			end
			local cols = {}
			local function add(kind, title, width) cols[#cols + 1] = { kind = kind, title = title, width = width } end
			local bw = BAR_W + 5 + 6 * CW
			if hasBit(cfg.bars, 1) then add("time", "Time", bw) end
			if hasBit(cfg.bars, 2) then add("avg", "Average", bw) end
			if hasBit(cfg.bars, 4) then add("max", cfg.spikes and "Max Time, Spike" or "Max Time", bw) end
			if hasBit(cfg.bars, 8) then add("min", cfg.spikes and "Min Time, Spike" or "Min Time", bw) end
			if hasBit(cfg.bars, 16) then add("callavg", "Call Average", bw); add("count", "Count", 5 + 6 * TW) end
			if hasBit(cfg.bars, 32) then add("xtime", "Exclusive Time", bw) end
			if hasBit(cfg.bars, 64) then add("xavg", "Exclusive Average", bw) end
			if hasBit(cfg.bars, 128) then add("xmax", cfg.spikes and "Excl Max Time, Spike" or "Exclusive Max Time", bw) end
			local width = 0
			for _, c in ipairs(cols) do
				width = width + ((c.kind == "count") and (6 + 6 * TW) or (BAR_W + 6 + 6 * CW))
			end
			width = width + (1 + maxLen) * CW
			return { groups = groups, cols = cols, nameW = 2 + (4 + maxLen) * CW, width = width }
		end
		local function timRow(n)
			local r = tim.rows[n]
			if not r then
				r = { v = box(U.tim.f, BACK[1], 1), nm = box(U.tim.f, BACK[1], 1), t = text(U.tim.f, 3) }
				tim.rows[n] = r
			end
			return r
		end
		local function timCell(r, c)
			local key = r * 64 + c
			local cell = tim.cells[key]
			if not cell then cell = { t = text(U.tim.f, 3), bar = gradBox(U.tim.f, 2) }; tim.cells[key] = cell end
			return cell
		end
		local function timHead(c)
			local h = tim.heads[c]
			if not h then h = { b = box(U.tim.f, BACK[2], 4), t = text(U.tim.f, 5) }; tim.heads[c] = h end
			return h
		end
		local function timSep(c)
			local s = tim.seps[c]
			if not s then s = box(U.tim.f, SEP, 2); tim.seps[c] = s end
			return s
		end
		local function colValue(kind, j)
			local fr = mmax(AG.dframes, 1)
			if kind == "time" then return TV.last[j]
			elseif kind == "avg" then return TV.dT[j] / fr
			elseif kind == "max" then return TV.dMax[j]
			elseif kind == "min" then return TV.dMin[j]
			elseif kind == "callavg" then return TV.dT[j] / mmax(TV.dC[j], 1)
			elseif kind == "count" then return TV.lastC[j]
			elseif kind == "xtime" then return TV.lastX[j]
			elseif kind == "xavg" then return TV.dX[j] / fr
			elseif kind == "xmax" then return TV.dXMax[j] end
			return 0
		end
		local function timersUpdate()
			if timersDirty or not tim.layout then
				timersDirty = false
				tim.layout = timersLayout()
				for _, cell in pairs(tim.cells) do show(cell.t, false); show(cell.bar, false) end
				for _, h in pairs(tim.heads) do show(h.b, false); show(h.t, false) end
				for _, s in pairs(tim.seps) do show(s, false) end
			end
			local L = tim.layout
			local nameW = L.nameW
			local rowsN = 1
			for _, g in ipairs(L.groups) do rowsN = rowsN + 1 + #g[2] end
			local y0 = TH + 3
			local hovRow = nil
			if activeMenu == nil and my >= y0 and my < y0 + rowsN * RH then hovRow = floor((my - y0) / RH) + 1 end
			-- row texts: group names on the left, timer names right-aligned in the timer's colour
			local rowText = {}
			local rowOf = {}
			local row = 1
			for _, g in ipairs(L.groups) do
				row = row + 1
				rowText[row] = { g[1], 0, WHITE }
				for _, j in ipairs(g[2]) do
					row = row + 1
					rowOf[j] = row
					rowText[row] = { TIMERS[j].name, nameW - 5 - #TIMERS[j].name * CW, TIMERS[j].color }
				end
			end
			-- row backgrounds (value area translucent, name column opaque)
			for r = 1, rowsN do
				local o = timRow(r)
				local yy = y0 + (r - 1) * RH
				local ci = (r - 1) % 2 + 1
				local ni = (rowsN + r - 1) % 2 + 1
				place(o.v, nameW, yy, L.width, RH + 1)
				paint(o.v, (hovRow == r) and BACK_HOVER[ci] or BACK[ci], bgT())
				place(o.nm, 0, yy, nameW, RH + 1)
				paint(o.nm, (hovRow == r) and BACK_HOVER[ni] or BACK[ni], 0)
				show(o.v, true)
				show(o.nm, true)
				local rt = rowText[r]
				if rt then
					say(o.t, rt[1], rt[2], yy + 1)
					tint(o.t, rt[3])
				end
				show(o.t, rt ~= nil)
			end
			for r = rowsN + 1, tim.n do
				local o = tim.rows[r]
				show(o.v, false); show(o.nm, false); show(o.t, false)
			end
			tim.n = rowsN
			-- columns
			local x = nameW + 10
			local totalH = rowsN * RH + y0
			for c, col in ipairs(L.cols) do
				local sep = timSep(c)
				place(sep, x - 5, 0, 1, totalH)
				paint(sep, SEP, bgT())
				show(sep, true)
				local head = timHead(c)
				local hw = (col.kind == "count") and (5 + 6 * TW) or (6 * CW + BAR_W)
				place(head.b, x - 8, TH + 2, hw + 13, RH)
				say(head.t, col.title, x, TH + 2)
				show(head.b, true)
				show(head.t, true)
				for _, g in ipairs(L.groups) do
					for _, j in ipairs(g[2]) do
						local r = rowOf[j]
						local cell = timCell(r, c)
						local yy = y0 + (r - 1) * RH + 1
						local v = colValue(col.kind, j)
						local s
						if col.kind == "count" then
							s = sfmt("%5d", v)
						elseif (col.kind == "max" or col.kind == "min" or col.kind == "xmax") and cfg.spikes then
							local avg = (col.kind == "xmax") and colValue("xavg", j) or colValue("avg", j)
							s = (avg > 0.1) and sfmt("%5.2f %3.1fx", v, v / avg) or sfmt("%5.2f", v)
						else
							s = sfmt("%5.2f", v)
						end
						say(cell.t, s, x, yy)
						show(cell.t, true)
						if col.kind ~= "count" and not (cfg.spikes and (col.kind == "max" or col.kind == "min" or col.kind == "xmax")) then
							local w = floor(BAR_W * mmin(v / cfg.ref, 1))
							place(cell.bar, x + 6 * CW, yy, w, TH)
							grad(cell.bar, TIMERS[j].seq)
							paint(cell.bar, WHITE, fgT())
							show(cell.bar, w > 0)
						else
							show(cell.bar, false)
						end
					end
				end
				x = x + col.width + 1
			end
			-- headers of the name column and the two separator lines
			say(tim.group, "Group", 0, TH + 2)
			say(tim.timer, "Timer", nameW - 3 - 5 * CW, TH + 2)
			place(tim.groupBox, 0, TH + 2, nameW + 5, RH)
			place(tim.vline, nameW, 0, 1, totalH)
			paint(tim.vline, SEP, bgT())
			place(tim.hline, 0, 2 * TH + 3, nameW + L.width, 1)
			paint(tim.hline, SEP, bgT())
			tim.rect = { nameW + L.width, totalH + 1 }
			tim.hover = nil
			if hovRow then
				for j, r in pairs(rowOf) do if r == hovRow then tim.hover = j end end
			end
		end

		-- -------------------------------------------------------------------------------- Counters mode
		local cnt = { rows = {}, n = 0, min = {}, max = {} }
		local function counterList()
			local avgMs = readAvg()
			local fps = (avgMs > 0) and (1000 / avgMs) or 0
			local list = {
				{ "frame", nil, 0 },
				{ "fps", fps, 1, "%.1f" },
				{ "frames", K, 1, "%d" },
				{ "memory", nil, 0 },
				{ "total (MB)", memUsed(), 1, "%.1f" },
				{ "lua heap (MB)", luaHeapMb(), 1, "%.1f" },
				{ "instances", nil, 0 },
				{ "count", statRaw("InstanceCount"), 1, "%d" },
				{ "primitives", statRaw("PrimitivesCount"), 1, "%d" },
				{ "moving", statRaw("MovingPrimitivesCount"), 1, "%d" },
				{ "contacts", statRaw("ContactsCount"), 1, "%d" },
				{ "rendering", nil, 0 },
				{ "scene draw calls", statRaw("SceneDrawcallCount"), 1, "%d" },
				{ "scene triangles", statRaw("SceneTriangleCount"), 1, "%d" },
				{ "shadow draw calls", statRaw("ShadowsDrawcallCount"), 1, "%d" },
				{ "ui draw calls", statRaw("UI2DDrawcallCount"), 1, "%d" },
			}
			if cfg.network >= 1 then
				list[#list + 1] = { "network", nil, 0 }
				list[#list + 1] = { "receive (KB/s)", statRaw("DataReceiveKbps"), 1, "%.2f" }
				list[#list + 1] = { "send (KB/s)", statRaw("DataSendKbps"), 1, "%.2f" }
				list[#list + 1] = { "physics receive (KB/s)", statRaw("PhysicsReceiveKbps"), 1, "%.2f" }
				list[#list + 1] = { "physics send (KB/s)", statRaw("PhysicsSendKbps"), 1, "%.2f" }
			end
			local data, f = tasData()
			list[#list + 1] = { "happatas", nil, 0 }
			list[#list + 1] = { "tas frames", (type(data) == "table") and #data or 0, 1, "%d" }
			list[#list + 1] = { "tas frame", tonumber(f) or 0, 1, "%d" }
			if ClientObjects.Counts then
				local okc, reg, onScreen, playing = pcall(ClientObjects.Counts)
				if okc then
					list[#list + 1] = { "client objects", tonumber(reg) or 0, 1, "%d" }
					list[#list + 1] = { "on screen", tonumber(onScreen) or 0, 1, "%d" }
					list[#list + 1] = { "playing", tonumber(playing) or 0, 1, "%d" }
				end
			end
			if Buttons.Count then
				local okb, nb = pcall(Buttons.Count)
				if okb then list[#list + 1] = { "buttons", tonumber(nb) or 0, 1, "%d" } end
			end
			return list
		end
		local function cntRow(n)
			local r = cnt.rows[n]
			if not r then
				r = { bg = box(U.cnt.f, BACK[1], 1), name = text(U.cnt.f, 3), v = text(U.cnt.f, 3), mn = text(U.cnt.f, 3), mx = text(U.cnt.f, 3) }
				cnt.rows[n] = r
			end
			return r
		end
		local function countersUpdate()
			local list = counterList()
			local nameW = 7 * CW
			for _, c in ipairs(list) do nameW = mmax(nameW, (2 + #c[1] + 4 * c[3]) * CW) end
			local valW = 14 * CW
			local y0 = 2 * TH + 3
			local total = nameW + 3 * valW
			for n, c in ipairs(list) do
				local r = cntRow(n)
				local yy = y0 + (n - 1) * RH
				place(r.bg, 0, yy, total, RH + 1)
				paint(r.bg, BACK[(n - 1) % 2 + 1], bgT())
				show(r.bg, true)
				say(r.name, string.rep(" ", 4 * c[3]) .. c[1], 0, yy + 1)
				show(r.name, true)
				if c[2] ~= nil then
					local key = c[1] .. "#" .. n
					local v = c[2]
					cnt.min[key] = mmin(cnt.min[key] or v, v)
					cnt.max[key] = mmax(cnt.max[key] or v, v)
					local function fmtv(x)
						local s = sfmt(c[4], (c[4] == "%d") and floor(x + 0.5) or x)
						return s
					end
					local sv, smn, smx = fmtv(v), fmtv(cnt.min[key]), fmtv(cnt.max[key])
					say(r.v, sv, nameW + valW - #sv * CW - CW, yy + 1)
					say(r.mn, smn, nameW + 2 * valW - #smn * CW - CW, yy + 1)
					say(r.mx, smx, nameW + 3 * valW - #smx * CW - CW, yy + 1)
					show(r.v, true); show(r.mn, true); show(r.mx, true)
				else
					show(r.v, false); show(r.mn, false); show(r.mx, false)
				end
			end
			for n = #list + 1, cnt.n do
				local r = cnt.rows[n]
				show(r.bg, false); show(r.name, false); show(r.v, false); show(r.mn, false); show(r.mx, false)
			end
			cnt.n = #list
			-- headers
			for i, h in ipairs(cnt.heads) do
				local hx = (i == 1) and 0 or (nameW + (i - 2) * valW)
				local hw = (i == 1) and nameW or valW
				place(h.b, hx, TH + 2, hw - 2, RH)
				say(h.t, h.title, hx + 2, TH + 2)
			end
			place(cnt.hline, 0, 2 * TH + 3, total, 1)
			paint(cnt.hline, SEP, bgT())
			cnt.rect = { total, y0 + #list * RH + 1 }
		end

		-- -------------------------------------------------------------------------------- Flamegraphs
		local flm = { boxes = {}, n = 0, hover = nil }
		local function flmBox(n)
			local b = flm.boxes[n]
			if not b then b = { b = gradBox(U.flm.f, 2), t = text(U.flm.f, 3, BLACK) }; flm.boxes[n] = b end
			return b
		end
		local function flameUpdate(hoverAllowed)
			local fr = mmax(AG.dframes, 1)
			local function avg(name) return TV.dT[TI[name]] / fr end
			local hap, prof = avg("HappaTAS"), avg("Profiler")
			local total = hap + prof
			local frameAvg = AG.dsum / fr
			local items = {}
			local function add(name, x0, x1, depth, ms, seq)
				items[#items + 1] = { name = name, x0 = floor(x0), x1 = floor(x1), depth = depth, ms = ms, seq = seq }
			end
			local pct = (frameAvg > 0) and (100 * total / frameAvg) or 0
			add(sfmt("All HappaTAS code %.3fms (%.2f%% of the frame)", total, pct), 0, W, 0, total, barSeq(150, 150, 150))
			if total > 0 then
				local hx = W * hap / total
				add(sfmt("HappaTAS %.3fms", hap), 0, hx, 1, hap, TIMERS[TI.HappaTAS].seq)
				add(sfmt("Profiler %.3fms", prof), hx, W, 1, prof, TIMERS[TI.Profiler].seq)
				local x = 0
				for j = 1, NT do
					local t = TIMERS[j]
					if t.parent == "HappaTAS" and hap > 0 then
						local v = TV.dT[j] / fr
						local w = hx * v / hap
						if w >= 1 then add(sfmt("%s %.3fms", t.name, v), x, x + w, 2, v, t.seq) end
						x = x + w
					end
				end
			end
			flm.hover = nil
			for n, it in ipairs(items) do
				local b = flmBox(n)
				local y = it.depth * BAR_H
				local w = mmax(1, it.x1 - it.x0)
				place(b.b, it.x0, y, w, BAR_H - 1)
				grad(b.b, it.seq)
				paint(b.b, WHITE, fgT())
				show(b.b, true)
				if w > 3 * TW then
					say(b.t, it.name:sub(1, floor((w - TW) / CW)), it.x0 + 1, y + 1)
					show(b.t, true)
				else
					show(b.t, false)
				end
				local top = U.flm.y or 0
				if hoverAllowed and mx >= it.x0 and mx < it.x0 + w and my >= top + y and my < top + y + BAR_H then flm.hover = it end
			end
			for n = #items + 1, flm.n do show(flm.boxes[n].b, false); show(flm.boxes[n].t, false) end
			flm.n = #items
		end

		-- true when the profiler pixel x, y is on a part of the profiler that takes the mouse
		local function overUI(x, y)
			if x < 0 or x >= W or y < 0 then return false end
			if y < MENU_H then return true end
			if graphVisible() and y < MENU_H + HIST_H then return true end
			if U.det.vis and y >= DET_Y and y < DET_Y + DET_H then return true end
			if U.flm.vis and U.flm.y and y >= U.flm.y and y < U.flm.y + 3 * BAR_H then return true end
			if dd.menu and x >= menuX[dd.menu] and x <= menuX[dd.menu] + dd.width and y >= RH and y <= RH + dd.count * RH then return true end
			if U.tim.vis and tim.rect and x < tim.rect[1] and y < tim.rect[2] then return true end
			if U.cnt.vis and cnt.rect and x < cnt.rect[1] and y < cnt.rect[2] then return true end
			return false
		end

		-- -------------------------------------------------------------------------------- build
		local function build()
			if U.built then return true end
			local sg = UI.Overlay("HappaProfiler", 2147482000)
			if not sg then return false end
			U.built = true
			U.sg = sg
			local root = Instance.new("Frame")
			root.Name = "MicroProfiler"
			root.BackgroundTransparency = 1
			root.BorderSizePixel = 0
			root.Size = UDim2.new(1 / SCALE, 0, 1 / SCALE, 0)
			root.Visible = false
			root.Parent = sg
			U.root = root
			U.scale = Instance.new("UIScale")
			U.scale.Scale = SCALE
			U.scale.Parent = root

			-- frame graph
			local graph = newButton(root, 1)
			graph.Name = "Graph"
			graph.BackgroundTransparency = 0
			graph.BackgroundColor3 = BACK[1]
			graph.ClipsDescendants = true
			graph.Position = UDim2.fromOffset(0, MENU_H)
			graph.Size = UDim2.new(1, -CLOSE_W, 0, HIST_H)
			U.graph = { f = graph }
			local strip = newFrame(graph, WHITE, 1, 1)
			strip.Name = "Strip"
			strip.Size = UDim2.new(1, 0, 1, 0)
			U.strip = strip
			U.bars = {}
			for s = 1, NUM_FRAMES do
				local b = gradBox(strip, 2)
				b.f.Name = "Bar"
				b.f.AnchorPoint = Vector2.new(0, 1)
				b.f.Size = UDim2.new(1 / NUM_FRAMES, 0, 0, 0)
				b.f.Position = UDim2.new(0, 0, 1, 0)
				U.bars[s] = b
			end
			U.hl = box(strip, HL, 3, HL_T)
			U.hl.f.Name = "Selection"
			show(U.hl, false)

			-- close box (the big X of the current client)
			local close = newButton(root, 1)
			close.Name = "Close"
			close.BackgroundTransparency = 0
			close.BackgroundColor3 = BACK[1]
			close.Position = UDim2.new(1, -CLOSE_W, 0, MENU_H)
			close.Size = UDim2.fromOffset(CLOSE_W, HIST_H)
			for _, rot in ipairs({ 45, -45 }) do
				local l = newFrame(close, WHITE, 2)
				l.AnchorPoint = Vector2.new(0.5, 0.5)
				l.Position = UDim2.fromOffset(26, 24)
				l.Size = UDim2.fromOffset(43, 1)
				l.Rotation = rot
			end
			U.close = { f = close }

			-- panels under the graph
			local detF = newButton(root, 2)
			detF.Name = "Detailed"
			detF.ClipsDescendants = true
			detF.Position = UDim2.fromOffset(0, DET_Y)
			detF.Size = UDim2.new(1, 0, 0, DET_H)
			U.det = { f = detF }
			det.thread = text(detF, 7)
			show(U.det, false)

			local timF = newFrame(root, WHITE, 2, 1)
			timF.Name = "Timers"
			timF.Size = UDim2.new(1, 0, 1, 0)
			U.tim = { f = timF }
			tim.group = text(timF, 5)
			tim.timer = text(timF, 5)
			tim.groupBox = box(timF, BACK[2], 4)
			tim.vline = box(timF, SEP, 2)
			tim.hline = box(timF, SEP, 2)
			show(U.tim, false)

			local cntF = newFrame(root, WHITE, 2, 1)
			cntF.Name = "Counters"
			cntF.Size = UDim2.new(1, 0, 1, 0)
			U.cnt = { f = cntF }
			cnt.heads = {}
			for _, title in ipairs({ "Name", "Value", "Min", "Max" }) do
				cnt.heads[#cnt.heads + 1] = { title = title, b = box(cntF, BACK[2], 4), t = text(cntF, 5) }
			end
			cnt.hline = box(cntF, SEP, 2)
			show(U.cnt, false)

			local flmF = newButton(root, 2)
			flmF.Name = "Flamegraph"
			flmF.ClipsDescendants = true
			flmF.Size = UDim2.new(1, 0, 0, 3 * BAR_H)
			U.flm = { f = flmF }
			show(U.flm, false)

			-- menu bar (a button, so clicks on it never reach the game)
			local menu = newButton(root, 5)
			menu.BackgroundTransparency = 0
			menu.BackgroundColor3 = BACK[2]
			menu.Name = "Menu"
			menu.Size = UDim2.new(1, 0, 0, MENU_H)
			U.menu = menu
			U.title = text(menu, 7)
			say(U.title, "MicroProfiler", 0, 0)
			U.items = {}
			for i, def in ipairs(MENUS) do
				local it = { hl = box(menu, HOVER, 6), t = text(menu, 7), b = { f = newButton(menu, 8) } }
				it.b.f.Name = "Item" .. i
				show(it.hl, false)
				U.items[i] = it
			end
			U.readout = text(menu, 7)

			-- dropdown, tooltip and help windows
			local ddF = newFrame(root, BACK[2], 10)
			ddF.Name = "Dropdown"
			U.dd = { f = ddF }
			show(U.dd, false)
			U.tip = window(12)
			U.help = { window(11), window(11), window(11) }

			-- input. Every click, drag and wheel notch comes from UserInputService, so it counts wherever
			-- Roblox delivers it (its top bar lies over this strip of the screen). The buttons above only
			-- keep clicks on the profiler away from the game; frameUI acts on MS once per frame.
			local MB1, MB2 = Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2
			local TOUCH = Enum.UserInputType.Touch
			local function live() return P.active and root.Visible end
			local function evPos(input)
				local p = input.Position
				if typeof(p) == "Vector3" then MS.gx, MS.gy, MS.ev = p.X, p.Y, true end
			end
			on(UIS.InputBegan, function(input)
				local t = input.UserInputType
				if (t ~= MB1 and t ~= MB2 and t ~= TOUCH) or not live() then return end
				if t == TOUCH and MS.touch then return end -- one finger at a time
				evPos(input)
				local x, y = toLocal(MS.gx, MS.gy)
				if not overUI(x, y) then return end   -- a click in the game, not on the profiler
				if not (MS.downL or MS.downR) then MS.dx, MS.dy = x, y end
				if t == MB2 then
					MS.downR, MS.pressR = true, true
				else
					MS.downL, MS.pressL = true, true
					if t == TOUCH then MS.touch = input end
				end
			end)
			on(UIS.InputChanged, function(input)
				if not live() then return end
				local t = input.UserInputType
				if t == Enum.UserInputType.MouseMovement or (t == TOUCH and input == MS.touch) then
					evPos(input)
				elseif t == Enum.UserInputType.MouseWheel then
					evPos(input)
					local z = input.Position.Z
					if z > 0 then MS.wheel = MS.wheel + 1 elseif z < 0 then MS.wheel = MS.wheel - 1 end
				end
			end)
			on(UIS.InputEnded, function(input)
				local t = input.UserInputType
				local right = (t == MB2)
				if right then
					if not MS.downR then return end
				elseif t == MB1 or (t == TOUCH and input == MS.touch) then
					if not MS.downL then return end
				else
					return
				end
				evPos(input)
				if right then MS.downR = false else MS.downL = false end
				if t == TOUCH then MS.touch = nil end
				local x, y = toLocal(MS.gx, MS.gy)
				if math.abs(x - MS.dx) + math.abs(y - MS.dy) < ((t == TOUCH) and 12 or 3) then
					if right then MS.clickR = true else MS.clickL = true end
				end
			end)
			local function resized()
				local s = root.AbsoluteSize
				if s.X > 0 and s.Y > 0 then
					W, H = s.X / SCALE, s.Y / SCALE
					U.barsDirty = true
				end
			end
			root:GetPropertyChangedSignal("AbsoluteSize"):Connect(resized)
			resized()
			BAR.built = false
			layoutMenuBar()
			return true
		end

		-- -------------------------------------------------------------------------------- modes
		local function flamePlace()
			if not U.built then return end
			local y = DET_Y + ((cfg.mode == "Detailed") and DET_H or 0)
			U.flm.y = y
			if U.flm.py ~= y then U.flm.py = y; U.flm.f.Position = UDim2.fromOffset(0, y) end
			show(U.flm, cfg.flame and graphVisible())
		end
		local function applyMode()
			if not U.built then return end
			local gv = graphVisible()
			show(U.graph, gv)
			show(U.close, gv)
			show(U.det, cfg.mode == "Detailed" and gv and not cfg.custom)
			show(U.tim, cfg.mode == "Timers")
			show(U.cnt, cfg.mode == "Counters")
			slog.on = (cfg.mode == "Detailed") and P.active and not cfg.custom
			U.barsDirty = true
			timersDirty = true
			hlKey = nil
			if not gv then windowHide(U.tip) end
			flamePlace()
		end
		actions.applyMode = applyMode
		function P.SetMode(m)
			for _, v in ipairs(MODES) do
				if v == m then
					cfg.mode = m
					applyMode()
					P.SaveConfig()
					return true
				end
			end
			return false
		end
		function P.Close()
			Settings.Set("Show MicroProfiler", 0)
			if P.active then P.SetVisible(false) end
		end
		function P.TogglePause()
			paused = not paused
		end
		function P.IsPaused() return paused end

		-- -------------------------------------------------------------------------------- per frame
		local tick = 0
		local function readMouse()
			mx, my = toLocal(pointer())
		end
		-- MicroProfileMoveGraph: one wheel notch zooms by 1.05 (1.40 with Shift) around the mouse
		local function zoom(dir)
			local shift = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
			local fct = shift and 1.40 or 1.05
			local old = view.range
			if dir > 0 then view.range = view.range * fct else view.range = mmax(view.range / fct, 1e-4) end
			view.range = mmin(view.range, 10000)
			view.offset = view.offset + (old - view.range) * mmax(mx / W, 0)
		end
		local function clearClicks()
			MS.pressL, MS.pressR, MS.clickL, MS.clickR, MS.wheel = false, false, false, false, 0
		end
		local function readoutUpdate()
			local t, a, m = lastMs, readAvg(), RO.max
			if cfg.custom then t, a, m = tasReadout() end
			local s = sfmt("Time[%6.2f] Avg[%6.2f] Max[%6.2f]", t, a, m)
			say(U.readout, s, floor(W - #s * CW), 0)
		end
		local function helpUpdate()
			local h = U.help
			if not helpOn then
				windowHide(h[1]); windowHide(h[2]); windowHide(h[3])
				return
			end
			if graphVisible() then
				windowShow(h[1], W, 20, { { "Left-Click", "Center View" }, { "Right-Click", "Zoom to frame" } }, SEP)
				windowShow(h[2], W, HIST_H + 20, { { "Drag", "Pan View" }, { "Mouse Wheel", "Zoom" },
					{ "F6", "Show / Hide" }, { "Ctrl+P", "Pause" } }, SEP)
			else
				windowHide(h[1])
				windowShow(h[2], W, HIST_H + 20, { { "F6", "Show / Hide" }, { "Ctrl+P", "Pause" } }, SEP)
			end
			windowShow(h[3], 0, H - 10, { { "Memory Usage", sfmt("%4.2fmb", luaHeapMb()) }, { "Frames", tostring(K) } }, SEP)
		end
		local function frameUI(recorded)
			tick = tick + 1
			readMouse()
			-- a release Roblox never delivered (the window lost focus with a button held)
			if MS.downL and not MS.touch and not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then MS.downL = false end
			if MS.downR and not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then MS.downR = false end
			layoutMenuBar()
			updateMenus()
			if not P.active then return end -- a menu line closed the profiler (Mode > Off)
			local gv = graphVisible()
			local overTip = false
			local detailed = cfg.mode == "Detailed" and gv and not cfg.custom
			local inDet = detailed and activeMenu == nil and mx >= 0 and mx < W and my >= DET_Y and my < DET_Y + DET_H
			if gv then
				if cfg.custom then
					tasStep()
				elseif U.barsDirty then
					U.barsDirty = false
					redrawLive()
				elseif recorded then
					drawBar(K, HIS.ms[hi(K)], liveSeq(K))
					setStrip(K - NUM_FRAMES + 1)
				end
				-- the view moves before the green selection is drawn (MicroProfileDraw: MoveGraph, then
				-- the clicks of DrawDetailedView, then the frame history)
				if detailed then
					-- MicroProfileMoveGraph: dragging pans, the wheel zooms around the mouse
					if inDet and MS.pressL then det.drag = mx end
					if det.drag then
						if not MS.downL then
							det.drag = nil
						else
							view.offset = view.offset - (mx - det.drag) * view.range / W
							det.drag = mx
						end
					end
					if inDet and MS.wheel ~= 0 then
						local n = MS.wheel
						for _ = 1, math.abs(n) do zoom((n > 0) and -1 or 1) end
					end
					local dh = det.hover
					if dh and inDet and MS.clickR and K >= 1 then -- a right click on a scope zooms to it
						view.offset = (dh.t0 - baseStart()) * 1000
						view.range = mmax(dh.ms, 0.01)
					end
				end
				local k = hoverUpdate()
				if k then overTip = true end
				-- MicroProfileDrawDetailedView: while the left button is held over the graph the detailed
				-- view stays centred on the frame under the mouse (UI.nMouseDownLeft), a right click zooms
				-- to that frame (UI.nMouseRight). The TAS Timeline scrubs instead (past the end of the TAS
				-- = its last frame).
				local back, frac = graphIndex()
				if back and (MS.downL or MS.pressL or MS.clickR) then
					if cfg.custom then
						local data = tasData()
						if tas.a and P.OnScrub and type(data) == "table" and #data > 0 then
							P.OnScrub(clampn(tas.a + NUM_FRAMES - 1 - back, 1, #data))
						end
					elseif k and K >= 1 then
						local st, en = HIS.start[hi(k)], frameEnd(k)
						if MS.clickR then
							view.offset = (st - baseStart()) * 1000
							view.range = mmax((en - st) * 1000, 0.01)
						else
							view.offset = (st + (en - st) * frac - baseStart()) * 1000 - 0.5 * view.range
						end
					end
				end
				-- the close box right of the graph
				if (MS.clickL or MS.clickR) and activeMenu == nil and mx >= W - CLOSE_W and mx < W and my >= MENU_H and my < MENU_H + HIST_H then
					P.Close()
					return
				end
				if not cfg.custom then updateHighlight() end
			else
				setHover(nil)
			end
			readoutUpdate()
			if detailed then
				if tick % 2 == 0 or det.drag then detailUpdate(activeMenu == nil and not overTip) end
				if det.hover and not overTip then
					windowShow(U.tip, mx, my + 20, timerTip(det.hover.name, det.hover.ms), WHITE)
					overTip = true
				end
			end
			if cfg.mode == "Timers" then
				if tick % 6 == 0 or timersDirty then timersUpdate() end
				if tim.hover and activeMenu == nil then
					windowShow(U.tip, mx, my + 20, timerTip(TIMERS[tim.hover].name), WHITE)
					overTip = true
				end
			end
			if cfg.mode == "Counters" and (tick % 15 == 0 or countersDirty) then
				countersDirty = false
				countersUpdate()
			end
			if cfg.flame and gv then
				flamePlace()
				if tick % 15 == 0 or flm.n == 0 then flameUpdate(false) end
				if activeMenu == nil and not overTip and U.flm.y and my >= U.flm.y and my < U.flm.y + 3 * BAR_H then
					flameUpdate(true)
					local h = flm.hover
					if h then
						windowShow(U.tip, mx, my + 20, { { h.name, "" }, { "Average", sfmt("%6.3fms", h.ms) } }, WHITE)
						overTip = true
					end
				end
			elseif U.flm.vis then
				show(U.flm, false)
			end
			if not overTip then windowHide(U.tip) end
			if dd.menu and tick % 15 == 0 then actions.ddRender(dd.menu) end
			helpUpdate()
		end

		-- called at the start of every frame (PreRender) with the render delta
		function P.FrameBegin(dt)
			frameNo = frameNo + 1
			if not P.active then
				clearAcc()
				return
			end
			local t0 = clock()
			local recorded = flip(dt, t0)
			if U.built and U.root.Visible then
				local ok, err = pcall(frameUI, recorded)
				if not ok then reportError("MicroProfiler", err) end
			end
			clearClicks() -- clicks last one frame (UI.nMouseLeft = UI.nMouseRight = 0 after drawing)
			clearAcc()
			tAcc.Profiler = clock() - t0
			tCnt.Profiler = 1
		end

		function P.SetVisible(v)
			v = v and true or false
			if v and not build() then return end
			P.active = v
			if U.root then U.root.Visible = v end
			lastStart = nil
			for k in pairs(tStart) do tStart[k] = nil end
			if v then
				applyMode()
			else
				slog.on = false
				activeMenu, helpOn, det.drag = nil, false, nil
				MS.downL, MS.downR, MS.touch = false, false, nil
				clearClicks()
				if U.built then
					ddClose()
					windowHide(U.tip)
					for _, w in ipairs(U.help) do windowHide(w) end
					setHover(nil)
				end
			end
		end

		-- true when the mouse is over any part of the profiler (inputs are not recorded there).
		-- m is a screen point (UIS:GetMouseLocation space); the current mouse uses the profiler's own pointer.
		function P.IsMouseOver(m)
			if not P.active or not U.built or not U.root.Visible then return false end
			local gx, gy
			local okc, cur = pcall(UIS.GetMouseLocation, UIS)
			if typeof(m) ~= "Vector2" or (okc and typeof(cur) == "Vector2" and cur.X == m.X and cur.Y == m.Y) then
				gx, gy = pointer()
			else
				local ix, iy = guiInset()
				gx, gy = m.X - ix, m.Y - iy
			end
			return overUI(toLocal(gx, gy))
		end

		-- -------------------------------------------------------------------------------- dump
		local function htmlEscape(s) return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end
		function actions.dump(n)
			local rows = {}
			local title
			if cfg.custom then
				local data, f = tasData()
				if type(data) == "table" and #data > 0 then
					f = clampn(math.floor(tonumber(f) or #data), 1, #data)
					for k = mmax(1, f - n + 1), f do
						local fr = data[k]
						rows[#rows + 1] = { k, tasFrameMs(fr), 0, 0, 0, 0, 0, fr.TotalTime or 0 }
					end
				end
				title = "TAS frame times"
			else
				for k = mmax(1, K - mmin(n, MAX_HISTORY) + 1), K do
					local i = hi(k)
					rows[#rows + 1] = { HIS.no[i], HIS.ms[i], HIS.gpu[i], HIS.ren[i], HIS.job[i], HIS.phy[i], HIS.hap[i] }
				end
				if cfg.dumpIncomplete and lastStart then
					rows[#rows + 1] = { frameNo, (clock() - lastStart) * 1000, 0, 0, 0, 0, 0, incomplete = true }
				end
				title = "MicroProfiler frames"
			end
			local avg, peak = readAvg(), RO.max
			local name = "microprofile-" .. os.date("%Y%m%d-%H%M%S")
			local textOut, ext
			if cfg.dumpBinary then
				-- LibMP is Roblox's own binary format; the closest open format is CSV
				local out = { "frame,cpu_ms,gpu_ms,render_ms,jobs_ms,physics_ms,happatas_ms" }
				for _, r in ipairs(rows) do
					out[#out + 1] = sfmt("%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f%s", r[1], r[2], r[3], r[4], r[5], r[6], r[7], r.incomplete and ",incomplete" or "")
				end
				textOut, ext = table.concat(out, "\n") .. "\n", "csv"
			elseif cfg.dumpLegacy then
				local out = { "HappaTAS " .. VERSION .. " " .. title, sfmt("frames %d  avg %.2f ms  max %.2f ms  aggregate %s",
					#rows, avg, peak, (cfg.aggregate == 0) and "infinite" or tostring(cfg.aggregate)), "",
					sfmt("%10s %9s %9s %9s %9s %9s %9s", "frame", "cpu", "gpu", "render", "jobs", "physics", "happatas") }
				for _, r in ipairs(rows) do
					out[#out + 1] = sfmt("%10d %9.3f %9.3f %9.3f %9.3f %9.3f %9.3f%s", r[1], r[2], r[3], r[4], r[5], r[6], r[7], r.incomplete and " incomplete" or "")
				end
				textOut, ext = table.concat(out, "\n") .. "\n", "txt"
			else
				local mxv = 0
				for _, r in ipairs(rows) do if r[2] > mxv then mxv = r[2] end end
				local bw = 4
				local svg = { sfmt("<svg width=\"%d\" height=\"120\" viewBox=\"0 0 %d 120\">", mmax(1, #rows * bw), mmax(1, #rows * bw)) }
				for i, r in ipairs(rows) do
					local h = (mxv > 0) and floor(r[2] / mxv * 118 + 0.5) or 0
					local col = (r[5] >= r[4]) and "#ff7f27" or "#37a0ee"
					svg[#svg + 1] = sfmt("<rect x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\" fill=\"%s\"><title>%s %.2fms</title></rect>",
						(i - 1) * bw, 120 - h, bw - 1, h, col, htmlEscape(tostring(r[1])), r[2])
				end
				svg[#svg + 1] = "</svg>"
				local tbl = { "<table><tr><th>frame</th><th>cpu ms</th><th>gpu ms</th><th>render ms</th><th>jobs ms</th><th>physics ms</th><th>HappaTAS ms</th></tr>" }
				for _, r in ipairs(rows) do
					tbl[#tbl + 1] = sfmt("<tr><td>%s</td><td>%.3f</td><td>%.3f</td><td>%.3f</td><td>%.3f</td><td>%.3f</td><td>%.3f</td></tr>",
						htmlEscape(tostring(r[1]) .. (r.incomplete and " (incomplete)" or "")), r[2], r[3], r[4], r[5], r[6], r[7])
				end
				tbl[#tbl + 1] = "</table>"
				textOut = table.concat({
					"<!doctype html><html><head><meta charset=\"utf-8\"><title>", htmlEscape(name), "</title><style>",
					"body{background:#313131;color:#fff;font:12px 'Roboto Mono',monospace;margin:16px}",
					"svg{background:#474747;display:block;margin:12px 0}table{border-collapse:collapse}",
					"th{background:#474747}td,th{padding:2px 10px;text-align:right;border-bottom:1px solid #474747}",
					"</style></head><body><h3>HappaTAS ", htmlEscape(VERSION), " - ", htmlEscape(title), "</h3>",
					sfmt("<p>%d frames, Avg %.2f ms, Max %.2f ms, Aggregate %s, Place %s</p>", #rows, avg, peak,
						(cfg.aggregate == 0) and "Infinite" or tostring(cfg.aggregate), htmlEscape(tostring(game.PlaceId))),
					table.concat(svg), table.concat(tbl), "</body></html>",
				})
				ext = "html"
			end
			local ok, res = Store.WriteText(name, textOut, ext)
			if Core.SetStatus then
				task.spawn(Core.SetStatus, ok and ("Dumped " .. #rows .. " frames to " .. name .. "." .. ext) or ("Dump failed: " .. tostring(res)))
			end
			return ok, res, ext
		end
		P.Dump = function(n) return actions.dump(tonumber(n) or 128) end

		-- -------------------------------------------------------------------------------- config + presets
		local function inList(v, list)
			for _, x in ipairs(list) do if x == v then return true end end
			return false
		end
		local function nearest(v, list)
			local best, bd = list[1], HUGE
			for _, x in ipairs(list) do
				local d = math.abs(x - v)
				if d < bd then best, bd = x, d end
			end
			return best
		end
		-- copies only valid values from t (a saved table, maybe from an older version) into c
		local function readConfig(t, c)
			if type(t) ~= "table" then return c end
			local mode = t.mode
			if mode == "Frame Graph" then mode = "Frame" end
			if mode == "TAS Timeline" then mode = "Frame"; c.custom = true end
			if inList(mode, MODES) then c.mode = mode end
			local a = tonumber(t.aggregate)
			if a then
				if a >= 1e9 then a = 0 end -- V2.35 saved Infinite as 1e9
				c.aggregate = inList(a, AGG) and a or nearest(a, AGG)
			end
			local ref = tonumber(t.ref)
			if ref and inList(ref, REF) then c.ref = ref end
			local bg, fg = tonumber(t.bg), tonumber(t.fg)
			if bg and inList(bg, OPAC) then c.bg = bg end
			if fg and inList(fg, OPAC) then c.fg = fg end
			local bars = tonumber(t.bars)
			if bars and bars >= 0 and bars <= 255 and bars % 1 == 0 then c.bars = bars end
			local net = tonumber(t.network)
			if net and (net == 0 or net == 1 or net == 2) then c.network = net end
			for _, k in ipairs({ "force", "spikes", "all", "flame", "custom", "dumpIncomplete", "dumpLegacy", "dumpBinary" }) do
				if type(t[k]) == "boolean" then c[k] = t[k] end
			end
			if type(t.groups) == "table" then
				for _, g in ipairs(GROUPS) do
					if type(t.groups[g]) == "boolean" then c.groups[g] = t.groups[g] end
				end
			end
			return c
		end
		-- what a preset stores (the dump options and the Custom view stay as they are)
		local function snapshotOf(c)
			return { mode = c.mode, aggregate = c.aggregate, ref = c.ref, bg = c.bg, fg = c.fg, spikes = c.spikes,
				bars = c.bars, all = c.all, groups = { Engine = c.groups.Engine, HappaTAS = c.groups.HappaTAS },
				network = c.network, flame = c.flame, force = c.force }
		end
		local function snapshot() return snapshotOf(cfg) end
		local function applied()
			U.barsDirty, timersDirty, countersDirty = true, true, true
			applyMode()
		end
		function actions.savePreset(name)
			if not inList(name, PRESET_NAMES) then return end
			presets[name] = snapshot()
			P.SaveConfig()
			if Core.SetStatus then task.spawn(Core.SetStatus, "MicroProfiler preset '" .. name .. "' saved") end
		end
		function actions.loadPreset(name)
			if not inList(name, PRESET_NAMES) then return end
			local p = presets[name]
			if p then
				local before = cfg.aggregate
				readConfig(p, cfg)
				if cfg.aggregate == 0 and before ~= 0 then pickInfinite() end
			elseif name == "Default" then
				local keep = { custom = cfg.custom, dumpIncomplete = cfg.dumpIncomplete, dumpLegacy = cfg.dumpLegacy, dumpBinary = cfg.dumpBinary }
				cfg = defaults()
				for k, v in pairs(keep) do cfg[k] = v end
			else
				if Core.SetStatus then task.spawn(Core.SetStatus, "MicroProfiler preset '" .. name .. "' is empty (use Save first)") end
				return
			end
			applied()
			P.SaveConfig()
		end
		P.LoadPreset, P.SavePreset = actions.loadPreset, actions.savePreset

		function P.Config() return cfg end
		function P.LoadConfig(t)
			if type(t) ~= "table" then return end
			cfg = readConfig(t, defaults())
			-- V2.35 stored the graph scale as "scale"
			if t.ref == nil and tonumber(t.scale) then
				local s = tonumber(t.scale)
				for _, v in ipairs(REF) do if math.abs(v - s) < 0.02 then cfg.ref = v end end
			end
			presets = {}
			if type(t.presets) == "table" then
				for _, n in ipairs(PRESET_NAMES) do
					if type(t.presets[n]) == "table" then presets[n] = snapshotOf(readConfig(t.presets[n], defaults())) end
				end
			end
			if U.built then applied() end
		end
		function P.SerializeConfig()
			local out = snapshot()
			out.custom = cfg.custom
			out.dumpIncomplete, out.dumpLegacy, out.dumpBinary = cfg.dumpIncomplete, cfg.dumpLegacy, cfg.dumpBinary
			local ps = {}
			local any = false
			for n, p in pairs(presets) do
				local copy = {}
				for k, v in pairs(p) do copy[k] = v end
				copy.groups = { Engine = p.groups.Engine, HappaTAS = p.groups.HappaTAS }
				ps[n] = copy
				any = true
			end
			if any then out.presets = ps end
			return out
		end
		P.SaveConfig = function() end -- replaced by the start code (saves Settings.json)

		-- read-only view of the numbers (the tests and the stats panel use it)
		function P.Snapshot()
			return { time = lastMs, avg = readAvg(), max = RO.max, onBar = mmin(K, NUM_FRAMES),
				aggAvg = (AG.dframes > 0) and (AG.dsum / AG.dframes) or 0, aggMax = AG.dmax,
				frames = AG.dframes, count = AG.count, recorded = K, frameNo = frameNo, paused = paused,
				offset = view.offset, range = view.range, hover = hoverK }
		end
		-- one timer's numbers: last frame, and the shown aggregate window (same values as Timers mode)
		function P.TimerStats(name)
			local j = TI[name]
			if not j then return nil end
			local fr = mmax(AG.dframes, 1)
			return { time = TV.last[j], calls = TV.lastC[j], exclusive = TV.lastX[j], avg = TV.dT[j] / fr,
				max = TV.dMax[j], min = TV.dMin[j], callAvg = TV.dT[j] / mmax(TV.dC[j], 1), group = TIMERS[j].group }
		end
		-- moves the detailed view (offset / range in ms from the current frame), like dragging and zooming
		function P.SetView(offset, range)
			offset, range = tonumber(offset), tonumber(range)
			if offset and offset == offset and math.abs(offset) < 1e7 then view.offset = offset end
			if range and range == range and range >= 1e-4 and range <= 10000 then view.range = range end
		end
		function P.Internals() return U, { det = det, tim = tim, cnt = cnt, flm = flm, dd = dd, tas = tas, view = view, menuX = menuX } end

		-- the whole profiler is drawn in Roblox's pixel sizes and scaled with one UIScale
		function P.SetScale(s)
			s = clampn(tonumber(s) or 1, 0.5, 4)
			if s ~= s then s = 1 end
			SCALE = s
			if U.built then
				U.scale.Scale = s
				U.root.Size = UDim2.new(1 / s, 0, 1 / s, 0)
				local a = U.root.AbsoluteSize
				if a.X > 0 and a.Y > 0 then W, H = a.X / s, a.Y / s end
				U.barsDirty, timersDirty, countersDirty = true, true, true
			end
		end

		function P.Start()
			P.SetScale(Settings.Get("MicroProfiler Scale"))
			Settings.Changed("MicroProfiler Scale", function(v) P.SetScale(v) end)
			P.SetTextNudge(Settings.Get("MicroProfiler Text Offset"))
			Settings.Changed("MicroProfiler Text Offset", function(v) P.SetTextNudge(v) end)
			P.SetVisible(Settings.On("Show MicroProfiler"))
			Settings.Changed("Show MicroProfiler", function(v) P.SetVisible(v ~= 0) end)
		end
	end
	profilerModule()
end

