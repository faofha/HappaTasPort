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
--  Every number comes from a documented Roblox API: frame time = RunService.PreRender delta, render /
--  GPU / physics = Stats.RenderCPUFrameTime / RenderGPUFrameTime / PhysicsStepTime, memory =
--  Stats:GetTotalMemoryUsageMb() / GetMemoryUsageMbForTag(), HappaTAS's own work = os.clock around
--  every system. Everything keeps counting while the graph is hidden (Mode > Hidden).
--  Frame bar colours (Roblox docs, MicroProfiler): orange = "Jobs Wall Time exceeds the Render Wall
--  Time", blue = "Render Wall Time exceeds the Jobs Wall Time". Render = Stats.RenderCPUFrameTime; jobs =
--  os.clock from RunService.PreAnimation to the next PreRender (the docs' frame order: PreRender ->
--  render -> PreAnimation -> animations -> PreSimulation -> physics -> PostSimulation -> Heartbeat ->
--  replication). Roblox's own rule (its LibMP dump viewer, checked against the client's graph bar by
--  bar): Jobs Wall Time = frame start .. end of the PreRender step, Render Wall Time = Prepare +
--  Perform. Measured against its dumps: Stats.RenderCPUFrameTime is exactly that Render Wall Time three
--  frames later and Stats.RenderGPUFrameTime the GPU device time one frame later, so every frame joins
--  the graph three frames after it ran (like Roblox's). Jobs = PreAnimation .. the end of HappaTAS's
--  PreRender work + FRAME_LEAD + PRERENDER_TAIL. Red bars need "GPU Wait Time", which no API gives, so
--  there are none. The bars are one EditableImage (508 frames when the client has no EditableImage).
--  Detailed lanes: "Engine" = those RunService phases + the render time, "HappaTAS" = its own scopes.
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
		-- the graph starts at nBaseY = TEXT_HEIGHT + 1 (9), its top row under the menu bar; the detailed
		-- view starts under it at 9 + 50 = 59 (measured in the Roblox client: bars end on row 58)
		local GRAPH_Y = TH + 1
		local DET_Y = GRAPH_Y + HIST_H

		-- -------------------------------------------------------------------------------- colours
		local function hex(h) return Color3.fromRGB(floor(h / 65536) % 256, floor(h / 256) % 256, h % 256) end
		local BACK = { hex(0x474747), hex(0x313131) }  -- g_nMicroProfileBackColors
		local BACK_HOVER = { hex(0x737373), hex(0x5d5d5d) } -- + 0x2c2c2c on the hovered row
		local HOVER = hex(0x888888)                     -- menu / dropdown highlight
		local SEP = hex(0x777777)                       -- BackColors[0] | BackColors[1]
		local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
		-- green selection over the graph: (39, 144, 53) at 60 %, measured over two backgrounds in the client
		local HL, HL_T = Color3.fromRGB(39, 144, 53), 0.4
		local SQUARE = Color3.fromRGB(255, 0, 0)        -- the square next to the longer of render / jobs
		-- Roblox's frame colours (its dump viewer, Roblox LibMP tools.js calculateStatistics, checked bar by
		-- bar against the client's own graph): Jobs Wall Time = frame start .. end of the "PreRender" step,
		-- Render Wall Time = the "Prepare" + "Perform" render steps; blue when render is longer. Two parts
		-- of the jobs can't be timed by a script; their medians, measured in Roblox's dumps with HappaTAS
		-- running (ms). With them 97 % of the bars had Roblox's colour (all of them had its render time).
		local FRAME_LEAD = 0.22      -- frame start .. RunService.PreAnimation handlers
		local PRERENDER_TAIL = 0.15  -- end of HappaTAS's PreRender work .. end of the PreRender step
		local RULER_TEXT = hex(0x808080)
		local FRAME_LINE = hex(0x757575)                -- frame start lines, opaque (measured)
		-- colours measured in the Roblox client (native window captures), transparency = 1 - alpha
		local COL = {
			dump = hex(0x5a5a5a),                       -- the box always behind "[Dump"
			band = Color3.fromRGB(24, 75, 60), bandT = 0.56,      -- row under a thread name in Detailed
			lane = hex(0x606060), laneT = 0.375,                  -- box behind "0000:  Engine"
			red = hex(0xcc3333),                        -- Counters: the note row
			cline = Color3.fromRGB(69, 69, 69), clineT = 0.59,    -- Counters: separator lines
			graph = hex(0x0088ff),                      -- Counters: detailed graph (0xff0088ff, fill 0x33)
			range = hex(0x009900),                      -- MICROPROFILE_FRAME_COLOR_HIGHTLIGHT 0x20009900
		}
		-- SEQ_RGB[sequence] = { top r, g, b, bottom r, g, b } (the frame graph image draws from these)
		local seqCache, SEQ_RGB = {}, {}
		-- MicroProfileBoxTypeBar: (c + max) / 2 at the top, (c + min) / 2 at the bottom
		local function barSeq(r, g, b)
			local key = r * 65536 + g * 256 + b
			local s = seqCache[key]
			if s then return s end
			local mx, mn = mmax(r, g, b, 30), mmin(r, g, b, 180)
			local t = { floor((r + mx) / 2), floor((g + mx) / 2), floor((b + mx) / 2), floor((r + mn) / 2), floor((g + mn) / 2), floor((b + mn) / 2) }
			s = ColorSequence.new(Color3.fromRGB(t[1], t[2], t[3]), Color3.fromRGB(t[4], t[5], t[6]))
			seqCache[key] = s
			SEQ_RGB[s] = t
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
		-- name, group, colour, parent. The first NE ("Engine") are measured once per frame in flip:
		-- Frame = PreRender to PreRender, Render CPU / GPU / Physics = Stats, Jobs = PreAnimation to
		-- PreRender, Animations = PreAnimation to PreSimulation, Simulation = PreSimulation to
		-- PostSimulation, Heartbeat = Heartbeat to PreRender (RunService docs: "when most scripts run",
		-- followed by replication)
		local TIMERS = {
			{ "Frame", "Engine", 255, 127, 39 },
			{ "Render CPU", "Engine", 55, 160, 238 },
			{ "Render GPU", "Engine", 120, 200, 250 },
			{ "Jobs", "Engine", 255, 175, 95 },
			{ "Animations", "Engine", 225, 120, 210, "Jobs" },
			{ "Simulation", "Engine", 70, 195, 170, "Jobs" },
			{ "Heartbeat", "Engine", 235, 205, 70, "Jobs" },
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
		for _, t in ipairs(TIMERS) do t.pj = t.parent and TI[t.parent] end
		local GROUPS = { "Engine", "HappaTAS" }
		-- a group's frame time (the "Group:" rows of a timer tooltip): the frame for Engine (its timers
		-- overlap), HappaTAS + the profiler for HappaTAS
		local GROUP_OF = { Engine = { TI.Frame }, HappaTAS = { TI.HappaTAS, TI.Profiler } }
		local NE = TI.Physics
		local EV = {} -- engine values of the frame (TIMERS 1 .. NE)
		for j = 1, NE do EV[j] = 0 end

		local statOk = {}
		if Stats then
			for _, p in ipairs({ "RenderCPUFrameTime", "RenderGPUFrameTime", "FrameTime", "HeartbeatTime", "PhysicsStepTime",
				"DataReceiveKbps", "DataSendKbps", "PhysicsReceiveKbps", "PhysicsSendKbps", "InstanceCount", "PrimitivesCount",
				"MovingPrimitivesCount", "ContactsCount", "SceneDrawcallCount", "SceneTriangleCount", "ShadowsDrawcallCount",
				"ShadowsTriangleCount", "UI2DDrawcallCount", "UI2DTriangleCount", "UI3DDrawcallCount", "UI3DTriangleCount" }) do
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
		-- frame history ring (finished frames, see RAW): ms = CPU Time, gft = GPU Time, gpu = GPU Time (device),
		-- ren / job = Render / Jobs Wall Time; pa / ps / po / hb / pr = os.clock of PreAnimation /
		-- PreSimulation / PostSimulation / Heartbeat / PreRender inside the frame (false when missing)
		local HIS = { ms = {}, gft = {}, gpu = {}, ren = {}, job = {}, phy = {}, hap = {}, start = {}, no = {}, pa = {}, ps = {},
			po = {}, hb = {}, pr = {} }
		-- RunService events of the frame in progress (connected only while the profiler is open)
		local EVQ = { pa = false, ps = false, po = false, hb = false, conns = nil }
		-- Frames in progress (a ring of RAW_N). Measured against Roblox's own MicroProfiler (its dumps, read
		-- with Roblox's LibMP): a frame starts shortly before PreAnimation and its jobs run until the end of
		-- the PreRender step; Stats.RenderCPUFrameTime gives that frame's Render Wall Time three frames
		-- later, Stats.RenderGPUFrameTime its GPU device time one frame later, and the time from its
		-- PreAnimation to the next one is its length. So a frame joins the history (and the graph) three
		-- frames after it ran, like in Roblox's profiler (MICROPROFILE_GPU_FRAME_DELAY 3).
		local RAW_N = 8
		local RAW = { n = 0, pa = {}, ps = {}, po = {}, hb = {}, pr = {}, prEnd = {}, dt = {}, len = {}, gpu = {}, hap = {}, phy = {}, no = {} }
		function EVQ.connect()
			if EVQ.conns then return end
			EVQ.conns = {}
			for _, e in ipairs({ { "PreAnimation", "pa" }, { "PreSimulation", "ps" }, { "PostSimulation", "po" }, { "Heartbeat", "hb" } }) do
				local key = e[2]
				local ok, c = pcall(function()
					return RunService[e[1]]:Connect(function() if not EVQ[key] then EVQ[key] = clock() end end)
				end)
				if ok and c then EVQ.conns[#EVQ.conns + 1] = c end
			end
		end
		function EVQ.disconnect()
			if not EVQ.conns then return end
			for _, c in ipairs(EVQ.conns) do pcall(function() c:Disconnect() end) end
			EVQ.conns = nil
			EVQ.pa, EVQ.ps, EVQ.po, EVQ.hb = false, false, false, false
			RAW.n = 0
		end
		Janitor.add(EVQ.disconnect)
		-- sum / max / count = nFlipAggregate, nFlipMax, nAggregateFlipCount
		-- dsum / dmax / dframes = nFlipAggregateDisplay, nFlipMaxDisplay, nAggregateFrames; clear = nAggregateClear
		local AG = { sum = 0, max = 0, count = 0, dsum = 0, dmax = 0, dframes = 0, clear = false }
		-- the Time / Avg / Max readout (HappaTAS rule, the same for every Aggregate setting and in Hidden):
		-- Avg = the frames on the bar (the last NUM_FRAMES), Max = the biggest frame since the profiler
		-- opened, kept until a bigger one comes (picking Infinite in the Aggregate menu resets it)
		local RO = { sum = 0, max = 0, exact = 0 }
		local tAcc, tCnt, tStart = {}, {}, {}
		-- per timer: last frame (time, calls, exclusive), accumulating window (a*), shown window (d*)
		-- g* = per group: frame time, accumulating sum / max, shown sum / max (AggregateGroup / Max)
		local TV = { last = {}, lastC = {}, lastX = {}, aT = {}, aMax = {}, aMin = {}, aC = {}, aX = {}, aXMax = {},
			dT = {}, dMax = {}, dMin = {}, dC = {}, dX = {}, dXMax = {}, child = {},
			gLast = {}, gA = {}, gAMax = {}, gD = {}, gDMax = {} }
		local function clearTimerAcc()
			for j = 1, NT do TV.aT[j], TV.aMax[j], TV.aMin[j], TV.aC[j], TV.aX[j], TV.aXMax[j] = 0, 0, HUGE, 0, 0, 0 end
			for _, g in ipairs(GROUPS) do TV.gA[g], TV.gAMax[g] = 0, 0 end
		end
		for j = 1, NT do
			TV.last[j], TV.lastC[j], TV.lastX[j] = 0, 0, 0
			TV.dT[j], TV.dMax[j], TV.dMin[j], TV.dC[j], TV.dX[j], TV.dXMax[j] = 0, 0, 0, 0, 0, 0
		end
		for _, g in ipairs(GROUPS) do TV.gLast[g], TV.gD[g], TV.gDMax[g] = 0, 0, 0 end
		clearTimerAcc()

		-- begin / end times of every HappaTAS scope (only kept in Detailed mode)
		local LOG_N = 4096
		local slog = { name = {}, t0 = {}, t1 = {}, depth = {}, pos = 0, depthNow = 0, on = false, open = {} }
		function slog.push(name, t0, t1, depth) -- a scope measured elsewhere (the profiler's own frame work)
			slog.pos = slog.pos + 1
			local i = (slog.pos - 1) % LOG_N + 1
			slog.name[i], slog.t0[i], slog.t1[i], slog.depth[i] = name, t0, t1, depth
		end
		local view = { offset = 0, range = 50 } -- UI.fDetailedOffset / fDetailedRange (ms, from the newest frame's start)

		local function hi(k) return (k - 1) % MAX_HISTORY + 1 end
		local function slotOf(k) return (k - 1) % NUM_FRAMES + 1 end
		-- the detailed view is measured from nFrameCurrent: the newest frame in the history, which trails
		-- the frame in progress by MICROPROFILE_GPU_FRAME_DELAY (3) frames
		local function baseStart() return HIS.start[hi(mmax(1, K))] end

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
			for _, g in ipairs(GROUPS) do
				local v = TV.gLast[g]
				TV.gA[g] = TV.gA[g] + v
				if v > TV.gAMax[g] then TV.gAMax[g] = v end
			end
			if cfg.aggregate == 0 or AG.count >= cfg.aggregate then
				AG.dframes, AG.dsum, AG.dmax = AG.count, AG.sum, AG.max
				for j = 1, NT do
					TV.dT[j], TV.dMax[j], TV.dC[j], TV.dX[j], TV.dXMax[j] = TV.aT[j], TV.aMax[j], TV.aC[j], TV.aX[j], TV.aXMax[j]
					TV.dMin[j] = (TV.aMin[j] == HUGE) and 0 or TV.aMin[j]
				end
				for _, g in ipairs(GROUPS) do TV.gD[g], TV.gDMax[g] = TV.gA[g], TV.gAMax[g] end
				if cfg.aggregate ~= 0 or AG.clear then
					AG.clear = false
					AG.sum, AG.max, AG.count = 0, 0, 0
					clearTimerAcc()
				end
			end
		end

		-- Jobs Wall Time of a raw frame: frame start .. end of the PreRender step, i.e. FRAME_LEAD + our
		-- PreAnimation .. the end of HappaTAS's PreRender work + PRERENDER_TAIL (0 when unknown)
		local function rawJob(j)
			local pa, e = RAW.pa[j], RAW.prEnd[j]
			if pa and e and e > pa then return FRAME_LEAD + (e - pa) * 1000 + PRERENDER_TAIL end
			return 0
		end
		-- a raw frame whose Render Wall Time just arrived joins the history as frame K
		local function finish(j, ren, gft)
			K = K + 1
			local i = hi(K)
			local ms = RAW.len[j] or RAW.dt[j]
			HIS.ms[i], HIS.gft[i], HIS.gpu[i], HIS.ren[i], HIS.job[i] = ms, gft, RAW.gpu[j] or 0, ren, rawJob(j)
			HIS.phy[i], HIS.hap[i], HIS.no[i] = RAW.phy[j], RAW.hap[j] or 0, RAW.no[j]
			local pa = RAW.pa[j]
			HIS.pa[i], HIS.ps[i], HIS.po[i], HIS.hb[i], HIS.pr[i] = pa, RAW.ps[j], RAW.po[j], RAW.hb[j], RAW.pr[j]
			-- the frame starts FRAME_LEAD before PreAnimation (or, without one, where the last frame ended)
			if pa then
				HIS.start[i] = pa - FRAME_LEAD / 1000
			elseif K > 1 then
				HIS.start[i] = HIS.start[hi(K - 1)] + HIS.ms[hi(K - 1)] / 1000
			else
				HIS.start[i] = RAW.pr[j] - 0.001
			end
			lastMs = ms
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
		end

		-- called at PreRender, at the start of HappaTAS's PreRender work. Returns true when a frame joined
		-- the history (the frame three frames back).
		local function flip(dt, now)
			local ms = (dt or 0) * 1000
			local start = lastStart or (now - (dt or 0))
			lastStart = now
			-- the RunService events seen since the last PreRender (they belong to this frame)
			local pa, ps, po, hb = EVQ.pa, EVQ.ps, EVQ.po, EVQ.hb
			EVQ.pa, EVQ.ps, EVQ.po, EVQ.hb = false, false, false, false
			if pa and pa < start then pa = false end
			if paused and not cfg.force then RAW.n = 0 return false end -- Pause stops the capture (Force Enable keeps it)
			local r = RAW.n + 1
			RAW.n = r
			local i = (r - 1) % RAW_N + 1
			RAW.pa[i], RAW.ps[i], RAW.po[i], RAW.hb[i], RAW.pr[i] = pa, ps or false, po or false, hb or false, now
			RAW.prEnd[i], RAW.dt[i], RAW.len[i], RAW.gpu[i], RAW.no[i] = false, ms, false, false, frameNo
			RAW.phy[i] = statMs("PhysicsStepTime")
			local ren, gpu = statMs("RenderCPUFrameTime"), statMs("RenderGPUFrameTime")
			local jobPrev = 0
			if r >= 2 then -- the last frame: its length (PreAnimation to PreAnimation) and GPU device time
				local j = (r - 2) % RAW_N + 1
				local pj = RAW.pa[j]
				RAW.len[j] = (pa and pj and pa > pj) and (pa - pj) * 1000 or ms
				RAW.gpu[j] = gpu
				jobPrev = rawJob(j)
			end
			local done = false
			if r >= 4 then -- three frames back: its Render Wall Time arrived
				finish((r - 4) % RAW_N + 1, ren, statMs("FrameTime"))
				done = true
			end
			EV[1], EV[2], EV[3], EV[4] = ms, ren, gpu, jobPrev
			EV[5] = (pa and ps and ps >= pa) and (ps - pa) * 1000 or 0
			EV[6] = (ps and po and po >= ps) and (po - ps) * 1000 or 0
			EV[7] = (hb and hb >= start) and (now - hb) * 1000 or 0
			EV[8] = RAW.phy[i]
			local child = TV.child
			for j = 1, NT do child[j] = 0 end
			for j = 1, NT do
				local v, c
				if j <= NE then
					v, c = EV[j], 1
				else
					local n = TIMERS[j].name
					v, c = (tAcc[n] or 0) * 1000, tCnt[n] or 0
				end
				TV.last[j], TV.lastC[j], TV.lastX[j] = v, c, v
				local p = TIMERS[j].pj
				if p then child[p] = child[p] + v end
			end
			-- exclusive time = the timer minus its children
			for j = 1, NT do
				if child[j] > 0 then TV.lastX[j] = mmax(0, TV.last[j] - child[j]) end
			end
			for g, list in pairs(GROUP_OF) do
				local s = 0
				for _, j in ipairs(list) do s = s + TV.last[j] end
				TV.gLast[g] = s
			end
			-- HappaTAS's work since its last PreRender: mostly the last frame's
			if r >= 2 then RAW.hap[(r - 2) % RAW_N + 1] = TV.gLast.HappaTAS end
			if not paused then aggregate(ms) end
			return done
		end
		-- called at the end of HappaTAS's PreRender work: the end of this frame's jobs as far as a script can see
		function P.FrameEnd()
			if not P.active or RAW.n < 1 then return end
			local i = (RAW.n - 1) % RAW_N + 1
			if not RAW.prEnd[i] then RAW.prEnd[i] = clock() end
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
			{ label = "[Dump]", dump = true,
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
			l = { hl = box(U.dd.f, HOVER, 11), t = text(U.dd.f, 12) }
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
			place(U.cDd, menuX[m], RH, w, #lines * RH) -- keeps the clicks on the dropdown away from the game
			for n, l in ipairs(lines) do
				local line = ddLine(n)
				local ly = (n - 1) * RH
				place(line.hl, 0, ly, w, RH)
				say(line.t, (l[2] and "*" or " ") .. " " .. l[1], 0, ly)
				show(line.t, true)
			end
			for n = #lines + 1, dd.count do
				local line = dd.lines[n]
				show(line.t, false)
				show(line.hl, false)
			end
			dd.count, dd.menu, dd.width = #lines, m, w
			show(U.dd, true)
			show(U.cDd, true)
		end
		local function ddClose()
			if dd.menu then dd.menu = nil; show(U.dd, false); show(U.cDd, false) end
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
				if def.dump then
					-- Roblox's client: "[Dump]" always sits on a 0x5a5a5a box (x - 1 .. under the "]"), and its
					-- hover box is one pixel wider than the others' (measured)
					place(U.dumpBox, x - 1, 0, w - CW + 2, MENU_H)
					place(it.hl, x - 1, 0, w + 2, MENU_H)
				else
					place(it.hl, x - 1, 0, w + 1, MENU_H)
				end
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
		-- slot s holds frame k when slotOf(k) == s: slotH = its bar height (px), slotC = its colours
		local slotK, slotH, slotC = {}, {}, {}
		local K0, stripX, shownFirst = 0, nil, 1
		local hoverK = nil
		U.barsDirty = true

		-- The bars are drawn into one EditableImage when the client allows it (Roblox docs, EditableImage:
		-- RGBA bytes from the top-left corner, at most 1024 x 1024, shown by an ImageLabel whose
		-- ImageContent is Content.fromObject(image)). The image is twice NUM_FRAMES wide: slot s is
		-- written to columns s - 1 and s - 1 + NUM_FRAMES, and the label shows the NUM_FRAMES columns
		-- that start at the first frame's slot (ImageRectOffset), so the graph scrolls with one property
		-- write per frame. Roblox redoes a ScreenGui when anything in it changes, so 508 gradient frames
		-- cost about 0.2 ms of render time every frame (measured in the client; the image about 0.05 ms),
		-- which also made Render Wall Time look longer. Without EditableImage the frames are used.
		local GI = { ok = false, cols = {}, batch = false }
		function GI.drop()
			GI.ok = false
			for _, o in ipairs({ GI.label, GI.img, GI.xLabel, GI.xImg }) do pcall(function() o:Destroy() end) end
			GI.label, GI.img, GI.xLabel, GI.xImg = nil, nil, nil, nil
		end
		Janitor.add(GI.drop)
		local function imageLabel(parent, img, z)
			local lab = Instance.new("ImageLabel")
			lab.BackgroundTransparency = 1
			lab.BorderSizePixel = 0
			lab.ZIndex = z
			lab.ResampleMode = Enum.ResamplerMode.Pixelated
			lab.ImageContent = Content.fromObject(img)
			lab.Parent = parent
			return lab
		end
		function GI.make(graph, close)
			local ok = pcall(function()
				local AssetService = svc("AssetService")
				GI.img = AssetService:CreateEditableImage({ Size = Vector2.new(2 * NUM_FRAMES, HIST_H) })
				local lab = imageLabel(graph, GI.img, 2)
				lab.Name = "Bars"
				lab.ImageRectSize = Vector2.new(NUM_FRAMES, HIST_H)
				lab.Size = UDim2.new(1, 0, 1, 0)
				GI.label = lab
				GI.blank = buffer.create(HIST_H * 4)
				GI.size = Vector2.new(1, HIST_H)
				-- the close box's X: white pixels from (10, 10) to (39, 39) and back (measured), one image
				GI.xImg = AssetService:CreateEditableImage({ Size = Vector2.new(30, 30) })
				local px = buffer.create(30 * 30 * 4)
				for i = 0, 29 do
					buffer.writeu32(px, (i * 30 + i) * 4, 4294967295)
					buffer.writeu32(px, (i * 30 + 29 - i) * 4, 4294967295)
				end
				GI.xImg:WritePixelsBuffer(Vector2.new(0, 0), Vector2.new(30, 30), px)
				GI.xLabel = imageLabel(close, GI.xImg, 3)
				GI.xLabel.Name = "X"
				GI.xLabel.Position = UDim2.fromOffset(10, 10)
				GI.xLabel.Size = UDim2.fromOffset(30, 30)
			end)
			if not ok then GI.drop() return false end
			GI.ok = true
			return true
		end
		-- a column h px high in the colours of seq (the gradient sampled at pixel centres, like a quad
		-- with a top and a bottom colour), cached per colour and height
		function GI.colbuf(h, seq)
			if h <= 0 or not seq then return GI.blank end
			local per = GI.cols[seq]
			if not per then per = {}; GI.cols[seq] = per end
			local b = per[h]
			if b then return b end
			b = buffer.create(HIST_H * 4)
			local c = SEQ_RGB[seq]
			for r = 0, h - 1 do
				local f = (r + 0.5) / h
				local R = floor(c[1] + (c[4] - c[1]) * f + 0.5)
				local G = floor(c[2] + (c[5] - c[2]) * f + 0.5)
				local B = floor(c[3] + (c[6] - c[3]) * f + 0.5)
				buffer.writeu32(b, (HIST_H - h + r) * 4, R + G * 256 + B * 65536 + 4278190080)
			end
			per[h] = b
			return b
		end
		-- the 508 gradient frames and the 60 pixel frames of the X (no EditableImage, or it stopped working)
		function GI.frames()
			local graph, close = U.graph.f, U.close.f
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
			for i = 0, 29 do
				for _, x in ipairs({ 10 + i, 39 - i }) do
					local px = newFrame(close, WHITE, 3)
					px.Position = UDim2.fromOffset(x, 10 + i)
					px.Size = UDim2.fromOffset(1, 1)
				end
			end
			K0, stripX = 0, nil
			for s = 1, NUM_FRAMES do slotK[s], slotH[s], slotC[s] = nil, nil, nil end
			U.barsDirty = true
		end
		-- an image write failed: frames from now on
		function GI.fail()
			GI.drop()
			GI.frames()
		end
		function GI.write(x, w, buf)
			local img = GI.img
			if not pcall(img.WritePixelsBuffer, img, Vector2.new(x, 0), Vector2.new(w, HIST_H), buf) then GI.fail() end
		end
		function GI.column(s)
			if GI.batch then return end
			local b = GI.colbuf(slotH[s] or 0, slotC[s])
			GI.write(s - 1, 1, b)
			if GI.ok then GI.write(s - 1 + NUM_FRAMES, 1, b) end
		end
		-- every column at once (after a batch of drawBar / clearBar calls): one write of the whole image
		function GI.flush()
			GI.batch = false
			local w2 = 2 * NUM_FRAMES
			local full = GI.full
			if not full then full = buffer.create(w2 * HIST_H * 4); GI.full = full end
			buffer.fill(full, 0, 0)
			for s = 1, NUM_FRAMES do
				local h = slotH[s] or 0
				if h > 0 then
					local b = GI.colbuf(h, slotC[s])
					for r = HIST_H - h, HIST_H - 1 do
						local v = buffer.readu32(b, r * 4)
						local o = (r * w2 + s - 1) * 4
						buffer.writeu32(full, o, v)
						buffer.writeu32(full, o + NUM_FRAMES * 4, v)
					end
				end
			end
			GI.write(0, w2, full)
		end

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
		-- slot s gets frame k, h px high, in the colours of seq (only what changed is written)
		local function drawBar(k, ms, seq)
			local s = slotOf(k)
			local h = barH(ms)
			local c = (k == hoverK) and SEQ_HOVER or seq
			if GI.ok then
				if slotK[s] ~= k or slotH[s] ~= h or slotC[s] ~= c then
					slotK[s], slotH[s], slotC[s] = k, h, c
					GI.column(s)
				end
				return
			end
			local b = U.bars[s]
			if slotK[s] ~= k then
				slotK[s] = k
				b.f.Position = UDim2.new((k - K0) / NUM_FRAMES, 0, 1, 0)
			end
			if slotH[s] ~= h then
				slotH[s] = h
				b.f.Size = UDim2.new(1 / NUM_FRAMES, 0, 0, h)
			end
			slotC[s] = c
			grad(b, c)
		end
		local function clearBar(s)
			if slotH[s] ~= 0 then
				slotH[s] = 0
				if GI.ok then GI.column(s) else U.bars[s].f.Size = UDim2.new(1 / NUM_FRAMES, 0, 0, 0) end
			end
			slotK[s] = nil
		end
		local function recolor(s, c)
			slotC[s] = c
			if GI.ok then GI.column(s) else grad(U.bars[s], c) end
		end
		-- the graph shows frames first .. first + NUM_FRAMES - 1. Image: the label's ImageRectOffset moves
		-- to the first frame's slot. Frames: the bars live in a strip that slides one bar per frame.
		local function setStrip(first)
			shownFirst = first
			if GI.ok then
				local c = (first - 1) % NUM_FRAMES
				if stripX ~= c then stripX = c; GI.label.ImageRectOffset = Vector2.new(c, 0) end
				return
			end
			if first - K0 > 50000 or first < K0 then
				K0 = first
				for s = 1, NUM_FRAMES do
					local k = slotK[s]
					if k then U.bars[s].f.Position = UDim2.new((k - K0) / NUM_FRAMES, 0, 1, 0) end
				end
			end
			local x = -(first - K0) / NUM_FRAMES
			if stripX ~= x then stripX = x; U.strip.Position = UDim2.new(x, 0, 0, 0) end
		end
		local function redrawLive()
			local first = K - NUM_FRAMES + 1
			GI.batch = GI.ok
			setStrip(first)
			for k = first, K do
				if k >= 1 then
					local i = hi(k)
					drawBar(k, HIS.ms[i], liveSeq(k))
				else
					clearBar(slotOf(k))
				end
			end
			if GI.ok then GI.flush() end
		end
		-- the green selection over frames kFirst .. kLast (it sits on the graph, not in the strip)
		local hlA, hlN = nil, nil
		local function setHL(kFirst, kLast)
			if not kFirst or not kLast or kFirst > kLast then show(U.hl, false) return end
			local a, n = kFirst - shownFirst, kLast - kFirst + 1
			if hlA ~= a then hlA = a; U.hl.f.Position = UDim2.new(a / NUM_FRAMES, 0, 0, 0) end
			if hlN ~= n then hlN = n; U.hl.f.Size = UDim2.new(n / NUM_FRAMES, 0, 1, 0) end
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
				GI.batch = GI.ok
				setStrip(a)
				for k = a, a + NUM_FRAMES - 1 do
					if data[k] then drawBar(k, tasFrameMs(data[k]), SEQ_CPU) else clearBar(slotOf(k)) end
				end
				if GI.ok then GI.flush() end
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
				if slotK[s] == old then recolor(s, cfg.custom and SEQ_CPU or liveSeq(old)) end
			end
			if k then
				local s = slotOf(k)
				if slotK[s] == k then recolor(s, SEQ_HOVER) end
			end
		end
		local function frameTip(k)
			local i = hi(k)
			local ren, job = HIS.ren[i], HIS.job[i]
			-- the red square marks the longer of the two (the one that gives the bar its colour)
			-- Roblox's rows (GPU Wait Time, CPU Freq and Mem Free have no script API, so they are left out):
			-- CPU Time = the frame's length, GPU Time = Stats.FrameTime three frames later (Roblox's GPU frame
			-- time within ~0.1 ms), GPU Time (device) = Stats.RenderGPUFrameTime one frame later (exact)
			local rows = {
				{ "Frame " .. tostring(HIS.no[i]), "" },
				{ "CPU Time", sfmt("%6.2fms", HIS.ms[i]) },
				{ "GPU Time", sfmt("%6.2fms", HIS.gft[i] or 0) },
				{ "GPU Time (device)", sfmt("%6.2fms", HIS.gpu[i]) },
				{ "", "" },
				{ "Render Wall Time", sfmt("%6.2fms", ren), (ren > job) and SQUARE or nil },
				{ "Jobs Wall Time", sfmt("%6.2fms", job), (ren <= job) and SQUARE or nil },
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
		-- MicroProfileDrawDetailedBars, with the Roblox client's look (measured): frame start lines, the
		-- time ruler (one column per step, the step written in each), then one lane per "thread": its
		-- name at x 10 on a box, a band under it, the scopes stacked 12 px per level with their names in
		-- white. Lanes: Engine (every frame's RunService phases and render time, see flip) and HappaTAS
		-- (its own scopes and the profiler's frame work). The panel covers the screen under the graph.
		local det = { stripes = {}, lines = {}, bars = {}, heads = {}, nStripes = 0, nLines = 0, nBars = 0,
			hover = nil, hoverPrev = nil, pulse = 155, pulseD = 10, rng = nil,
			LANES = { "0000:  Engine", "0001:  HappaTAS" } }
		do
			local D = { w0 = 0, w1 = 0, px = 1, y = 0, nb = 0, depth = 0, hoverOK = false, myd = 0, lastLine = {} }
			local function stripe(n)
				local s = det.stripes[n]
				if not s then
					s = { b = box(U.det.f, BACK[1], 2), t = text(U.det.f, 3) }
					tint(s.t, RULER_TEXT)
					det.stripes[n] = s
				end
				return s
			end
			local function frameLine(n)
				local l = det.lines[n]
				if not l then l = box(U.det.f, FRAME_LINE, 4); det.lines[n] = l end
				return l
			end
			local function bar(n)
				local b = det.bars[n]
				if not b then b = { b = gradBox(U.det.f, 7), t = text(U.det.f, 8) }; det.bars[n] = b end
				return b
			end
			-- the hovered scope pulses grey, the other scopes of its timer are dark grey (UI.nHoverColor,
			-- UI.nHoverColorShared: the counter steps by 10 between 100 and 245, shared = counter / 4)
			local function barColor(j, key)
				local hv = det.hoverPrev
				if hv and hv.j == j then
					local c = (hv.key == key) and det.pulse or floor(det.pulse / 4)
					return barSeq(c, c, c)
				end
				return TIMERS[j].seq
			end
			-- one scope: timer j from t0 to t1 (os.clock seconds) at stack level depth (1 = outermost)
			local function entry(j, t0, t1, depth, key)
				if t1 < D.w0 or t0 > D.w1 then return end
				local xs, xe = (t0 - D.w0) * 1000 * D.px, (t1 - D.w0) * 1000 * D.px
				local ys = D.y + (depth - 1) * BAR_H
				if depth > D.depth then D.depth = depth end
				-- MICROPROFILE_HOVER_DIST 0.5
				if D.hoverOK and mmax(xs - mx, mx - xe) < 0.5 and ys <= D.myd and D.myd <= ys + BAR_H and D.myd > 0 then
					det.hover = { j = j, ms = (t1 - t0) * 1000, t0 = t0, t1 = t1, key = key }
				end
				local iw = floor(xe - xs)
				local x0, wpx
				if iw >= 1 then
					x0 = floor(xs)
					wpx = floor(xe) - x0
				else
					-- narrower than a pixel: a 1 px line, once per pixel column and level
					x0 = floor((xs + xe) / 2 + 0.5)
					if D.lastLine[depth] == x0 then return end
					D.lastLine[depth] = x0
					wpx = 1
				end
				if D.nb >= 400 then return end
				D.nb = D.nb + 1
				local b = bar(D.nb)
				place(b.b, x0, ys, wpx, BAR_H)
				grad(b.b, barColor(j, key))
				paint(b.b, WHITE, fgT())
				show(b.b, true)
				if iw > 3 * TW then
					local xst = mmax(xs, 0)
					local nch = floor((floor(xe - xst) - TW) / CW)
					if nch > 0 then
						say(b.t, TIMERS[j].name:sub(1, nch), floor(xst + 1), ys + 1)
						show(b.t, true)
						return
					end
				end
				show(b.t, false)
			end
			-- lane header: nY += 3, "%04x: %s" on its box at x 10, nY += 3 + TEXT_HEIGHT + 1, the band
			local function lane(n)
				D.y = D.y + 3
				local h = det.heads[n]
				if not h then
					h = { band = box(U.det.f, COL.band, 5, COL.bandT), b = box(U.det.f, COL.lane, 5, COL.laneT), t = text(U.det.f, 6) }
					det.heads[n] = h
				end
				local s = det.LANES[n]
				place(h.b, 10, D.y, #s * CW + 2, RH)
				say(h.t, s, 10, D.y)
				D.y = D.y + 3 + RH
				place(h.band, 0, D.y, W, BAR_H)
				show(h.b, true); show(h.t, true); show(h.band, true)
				D.depth = 0
			end
			-- nY += nMaxStackDepth * 12 + 12 + 1 (the Roblox client draws level 1 on the band)
			local function laneEnd() D.y = D.y + D.depth * BAR_H + BAR_H + 1 end
			local function engineLane()
				local k, nf = K, 0
				local rj, jj, aj, sj, hj = TI["Render CPU"], TI.Jobs, TI.Animations, TI.Simulation, TI.Heartbeat
				while k >= 1 and K - k < MAX_HISTORY - 1 and nf < 64 do
					local i = hi(k)
					local st, en = HIS.start[i], frameEnd(k)
					if en < D.w0 then break end
					if st <= D.w1 then
						nf = nf + 1
						-- Roblox's frame: the jobs from its start to the end of PreRender, then the render
						local je = st + HIS.job[i] / 1000
						if je > st then entry(jj, st, je, 1, st) end
						entry(rj, je, je + HIS.ren[i] / 1000, 1, je)
						local pa, ps, po, hb, pr = HIS.pa[i], HIS.ps[i], HIS.po[i], HIS.hb[i], HIS.pr[i]
						if pa and ps and ps >= pa then entry(aj, pa, ps, 2, pa) end
						if ps and po and po >= ps then entry(sj, ps, po, 2, ps) end
						if hb and pr and pr >= hb then entry(hj, hb, pr, 2, hb) end
					end
					k = k - 1
				end
			end
			local function happaLane()
				local idx, count = slog.pos, 0
				local now = clock()
				while count < LOG_N and idx >= 1 do
					local i = (idx - 1) % LOG_N + 1
					local t0 = slog.t0[i]
					if not t0 or t0 < D.w0 - 1 then break end
					local j = TI[slog.name[i]]
					if j then entry(j, t0, slog.t1[i] or now, slog.depth[i] + 1, t0) end
					idx = idx - 1
					count = count + 1
				end
			end
			-- while paused: the time range of the frame under the mouse in the graph, or of the hovered
			-- scope, over the whole view with its start / end times (UI.nRangeBegin / nRangeEnd)
			local function rangeShow(hgt)
				local a, b
				if paused then
					if hoverK and not cfg.custom then
						a, b = HIS.start[hi(hoverK)], frameEnd(hoverK)
					elseif det.hover then
						a, b = det.hover.t0, det.hover.t1
					end
				end
				local r = det.rng
				if not a then
					if r then for _, o in pairs(r) do show(o, false) end end
					return
				end
				if not r then
					r = { box = box(U.det.f, COL.range, 9, 1 - 0x20 / 255), l0 = box(U.det.f, COL.range, 9, 1 - 0x44 / 255),
						l1 = box(U.det.f, COL.range, 9, 1 - 0x44 / 255), b0 = box(U.det.f, BLACK, 10, 1 - 0x33 / 255),
						b1 = box(U.det.f, BLACK, 10, 1 - 0x33 / 255), t0 = text(U.det.f, 11), t1 = text(U.det.f, 11) }
					det.rng = r
				end
				local xs, xe = (a - D.w0) * 1000 * D.px, (b - D.w0) * 1000 * D.px
				place(r.box, floor(xs), 0, mmax(floor(xe) - floor(xs), 0), hgt)
				place(r.l0, floor(xs), 0, 1, hgt)
				place(r.l1, floor(xe), 0, 1, hgt)
				local base = baseStart()
				local s0, s1 = sfmt("%.2fms", (a - base) * 1000), sfmt("%.2fms", (b - base) * 1000)
				local x0 = floor(xs - #s0 * CW - 2)
				place(r.b0, x0, 0, #s0 * CW + 2, TH + 2)
				say(r.t0, s0, x0 + 1, 0)
				local x1 = floor(xe + 1)
				place(r.b1, x1, 0, #s1 * CW + 3, TH + 2)
				say(r.t1, s1, floor(xe + 2), 1)
				for _, o in pairs(r) do show(o, true) end
			end
			function det.update(hoverAllowed)
				det.hoverPrev = det.hover
				det.hover = nil
				if K < 1 then return end
				det.pulse = det.pulse + det.pulseD
				if det.pulse >= 245 then det.pulseD = -10 elseif det.pulse < 100 then det.pulseD = 10 end
				local range = view.range
				D.w0 = baseStart() + view.offset / 1000
				D.w1 = D.w0 + range / 1000
				D.px = W / range
				D.hoverOK = hoverAllowed
				D.myd = my - DET_Y
				local hgt = mmax(0, H - DET_Y)
				-- light grey line at the start of every frame
				local nl, k = 0, K
				while k >= 1 and K - k < MAX_HISTORY and nl < 128 do
					local st = HIS.start[hi(k)]
					if st < D.w0 then break end
					if st <= D.w1 then
						nl = nl + 1
						local l = frameLine(nl)
						place(l, floor((st - D.w0) * 1000 * D.px), 0, 1, hgt)
						paint(l, FRAME_LINE, fgT())
						show(l, true)
					end
					k = k - 1
				end
				for i = nl + 1, det.nLines do show(det.lines[i], false) end
				det.nLines = nl
				-- the ruler: 10^(floor(2 * (log10(range) - 1)) / 2) ms per column
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
					local s = stripe(n)
					local x0 = floor((f - view.offset) * D.px)
					local x1 = floor((f + step - view.offset) * D.px + 1)
					place(s.b, x0, 0, x1 - x0, hgt)
					paint(s.b, BACK[colorIndex % 2 + 1], bgT())
					show(s.b, true)
					if label ~= "" then
						say(s.t, label, x0 + floor((step * D.px - #label * CW) / 2), 0)
						show(s.t, true)
					else
						show(s.t, false)
					end
					colorIndex = colorIndex + 1
					f = f + step
				end
				for i = n + 1, det.nStripes do show(det.stripes[i].b, false); show(det.stripes[i].t, false) end
				det.nStripes = n
				-- the lanes, starting one text row under the ruler labels
				D.y, D.nb = RH, 0
				for key in pairs(D.lastLine) do D.lastLine[key] = nil end
				lane(1); engineLane(); laneEnd()
				lane(2); happaLane(); laneEnd()
				for i = D.nb + 1, det.nBars do show(det.bars[i].b, false); show(det.bars[i].t, false) end
				det.nBars = D.nb
				rangeShow(hgt)
			end
			-- MicroProfileDrawFloatTooltip: timer j (ms = the hovered scope's time, nil in the Timers table)
			function det.tip(j, ms)
				local fr = mmax(AG.dframes, 1)
				local calls = (TV.dC[j] > 0) and TV.dC[j] or 1
				local g = TIMERS[j].group
				local rows = { { "Timer:", TIMERS[j].name } }
				local function add(a, b) rows[#rows + 1] = { a, b } end
				if ms then
					add("Time:", sfmt("%6.3fms", ms))
					add("", "")
				end
				add("Frame Time:", sfmt("%6.3fms", TV.last[j]))
				add("Average:", sfmt("%6.3fms", TV.dT[j] / fr))
				add("Max:", sfmt("%6.3fms", TV.dMax[j]))
				add("Min:", sfmt("%6.3fms", TV.dMin[j]))
				add("", "")
				add("Call Average:", sfmt("%6.3fms", TV.dT[j] / calls))
				add("Call Count:", sfmt("%6.2f", calls / fr))
				add("", "")
				add("Exclusive Frame Time:", sfmt("%6.3fms", TV.lastX[j]))
				add("Exclusive Average:", sfmt("%6.3fms", TV.dX[j] / fr))
				add("Exclusive Max:", sfmt("%6.3fms", TV.dXMax[j]))
				add("", "")
				add("Group:", g)
				add("Frame Time:", sfmt("%6.3f", TV.gLast[g] or 0))
				add("Frame Average:", sfmt("%6.3f", (TV.gD[g] or 0) / fr))
				add("Frame Max:", sfmt("%6.3f", TV.gDMax[g] or 0))
				return rows
			end
		end

		-- -------------------------------------------------------------------------------- Timers mode
		local tim = { rows = {}, cells = {}, heads = {}, seps = {}, n = 0, layout = nil }
		do
			local function layout()
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
			local function row(n)
				local r = tim.rows[n]
				if not r then
					r = { v = box(U.tim.f, BACK[1], 1), nm = box(U.tim.f, BACK[1], 1), t = text(U.tim.f, 3) }
					tim.rows[n] = r
				end
				return r
			end
			local function cell(r, c)
				local key = r * 64 + c
				local ce = tim.cells[key]
				if not ce then ce = { t = text(U.tim.f, 3), bar = gradBox(U.tim.f, 2) }; tim.cells[key] = ce end
				return ce
			end
			local function head(c)
				local h = tim.heads[c]
				if not h then h = { b = box(U.tim.f, BACK[2], 4), t = text(U.tim.f, 5) }; tim.heads[c] = h end
				return h
			end
			local function sep(c)
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
			function tim.update()
				if timersDirty or not tim.layout then
					timersDirty = false
					tim.layout = layout()
					for _, ce in pairs(tim.cells) do show(ce.t, false); show(ce.bar, false) end
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
				local rr = 1
				for _, g in ipairs(L.groups) do
					rr = rr + 1
					rowText[rr] = { g[1], 0, WHITE }
					for _, j in ipairs(g[2]) do
						rr = rr + 1
						rowOf[j] = rr
						rowText[rr] = { TIMERS[j].name, nameW - 5 - #TIMERS[j].name * CW, TIMERS[j].color }
					end
				end
				-- row backgrounds (value area translucent, name column opaque)
				for r = 1, rowsN do
					local o = row(r)
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
					local s = sep(c)
					place(s, x - 5, 0, 1, totalH)
					paint(s, SEP, bgT())
					show(s, true)
					local h = head(c)
					local hw = (col.kind == "count") and (5 + 6 * TW) or (6 * CW + BAR_W)
					place(h.b, x - 8, TH + 2, hw + 13, RH)
					say(h.t, col.title, x, TH + 2)
					show(h.b, true)
					show(h.t, true)
					for _, g in ipairs(L.groups) do
						for _, j in ipairs(g[2]) do
							local r = rowOf[j]
							local ce = cell(r, c)
							local yy = y0 + (r - 1) * RH + 1
							local v = colValue(col.kind, j)
							local str
							if col.kind == "count" then
								str = sfmt("%5d", v)
							elseif (col.kind == "max" or col.kind == "min" or col.kind == "xmax") and cfg.spikes then
								local avg = (col.kind == "xmax") and colValue("xavg", j) or colValue("avg", j)
								str = (avg > 0.1) and sfmt("%5.2f %3.1fx", v, v / avg) or sfmt("%5.2f", v)
							else
								str = sfmt("%5.2f", v)
							end
							say(ce.t, str, x, yy)
							show(ce.t, true)
							if col.kind ~= "count" and not (cfg.spikes and (col.kind == "max" or col.kind == "min" or col.kind == "xmax")) then
								local w = floor(BAR_W * mmin(v / cfg.ref, 1))
								place(ce.bar, x + 6 * CW, yy, w, TH)
								grad(ce.bar, TIMERS[j].seq)
								paint(ce.bar, WHITE, fgT())
								show(ce.bar, w > 0)
							else
								show(ce.bar, false)
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
				place(U.cTim, 0, 0, tim.rect[1], tim.rect[2])
				tim.hover = nil
				if hovRow then
					for j, r in pairs(rowOf) do if r == hovRow then tim.hover = j end end
				end
			end
		end

		-- -------------------------------------------------------------------------------- Counters mode
		-- MicroProfileDrawCounterView with the Roblox client's layout (measured): a note row at y 10, the
		-- Name / Value / Limit / Graph / Min / Max headers under it, then one 9 px row per counter, nested 4
		-- characters per level. A left click on a counter's name opens / closes its children; a click right
		-- of the Limit column shows its graph and min / max (again: a 5 rows tall graph), a right click there
		-- hides them. Every value comes from a documented API (Stats, collectgarbage) or from HappaTAS.
		local cnt = { rows = {}, n = 0, min = {}, max = {}, hist = {}, histPos = 0, closed = {}, detail = {}, big = {},
			counterW = 8 * CW, list = nil, rowOf = {} }
		do
			local HISTORY = 128 -- MICROPROFILE_GRAPH_HISTORY
			local NOTE = "Roblox's own counters can't be read by scripts. These come from Stats, collectgarbage and HappaTAS."
			local EXT = { "b", "kb", "mb", "gb", "tb", "pb", "eb", "zb", "yb" }
			-- MicroProfileFormatCounter: groups of three digits split by spaces, or bytes as "%3.2f" + unit
			local function fmt(v, bytes)
				v = floor(v + 0.5)
				if v == 0 then return "0" end
				if bytes then
					local div, shift = 1, 0
					local s = floor(math.abs(v) / 1024)
					while s >= 1 and shift < #EXT - 1 do div = div * 1024; s = floor(s / 1024); shift = shift + 1 end
					if shift > 0 then return sfmt("%3.2f%s", v / div, EXT[shift + 1]) end
					return sfmt("%d%s", v, EXT[1])
				end
				local neg = v < 0
				local digits = sfmt("%d", neg and -v or v)
				local out = {}
				local first = #digits % 3
				if first > 0 then out[1] = digits:sub(1, first) end
				for p = first + 1, #digits, 3 do out[#out + 1] = digits:sub(p, p + 2) end
				return (neg and "-" or "") .. table.concat(out, " ")
			end
			cnt.fmt = fmt
			local function us(p) return statMs(p) * 1000 end
			local TAGS = {}
			pcall(function()
				for _, item in ipairs(Enum.DeveloperMemoryTag:GetEnumItems()) do
					-- LuaHeap -> lua_heap, GraphicsSolidModels -> graphics_solid_models
					local snake = item.Name:gsub("(%l)(%u)", "%1_%2"):gsub("(%u)(%u%l)", "%1_%2"):lower()
					TAGS[#TAGS + 1] = { snake, item }
				end
			end)
			local function memTag(item)
				local ok, v = pcall(function() return Stats:GetMemoryUsageMbForTag(item) end)
				return (ok and type(v) == "number") and v * 1048576 or 0
			end
			-- the counter tree: { name, level, value or nil (a group), bytes }
			local function build()
				local data, f = tasData()
				local L = {}
				local function add(name, level, value, bytes) L[#L + 1] = { name, level, value, bytes } end
				add("frame_stats", 0)
				add("basic", 1)
				add("cpu_frame_time_microsec", 2, lastMs * 1000)
				add("render_cpu_time_microsec", 2, us("RenderCPUFrameTime"))
				add("gpu_device_time_microsec", 2, us("RenderGPUFrameTime"))
				add("jobs_time_microsec", 2, TV.last[TI.Jobs] * 1000)
				add("physics_step_time_microsec", 2, us("PhysicsStepTime"))
				add("heartbeat_time_microsec", 2, us("HeartbeatTime"))
				add("frame_count", 2, K)
				add("instance_count", 0)
				add("instance", 1, statRaw("InstanceCount"))
				add("primitives", 1, statRaw("PrimitivesCount"))
				add("moving_primitives", 1, statRaw("MovingPrimitivesCount"))
				add("contacts", 1, statRaw("ContactsCount"))
				add("render", 0)
				add("scene_drawcalls", 1, statRaw("SceneDrawcallCount"))
				add("scene_triangles", 1, statRaw("SceneTriangleCount"))
				add("shadows_drawcalls", 1, statRaw("ShadowsDrawcallCount"))
				add("shadows_triangles", 1, statRaw("ShadowsTriangleCount"))
				add("ui2d_drawcalls", 1, statRaw("UI2DDrawcallCount"))
				add("ui2d_triangles", 1, statRaw("UI2DTriangleCount"))
				add("ui3d_drawcalls", 1, statRaw("UI3DDrawcallCount"))
				add("ui3d_triangles", 1, statRaw("UI3DTriangleCount"))
				add("memory", 0)
				add("total", 1, memUsed() * 1048576, true)
				for _, t in ipairs(TAGS) do add(t[1], 1, memTag(t[2]), true) end
				add("luau", 0)
				add("heap", 1, luaHeapMb() * 1048576, true)
				if cfg.network >= 1 then
					-- Stats: "kilobytes of data ... per second"
					add("network", 0)
					add("data_receive_per_sec", 1, statRaw("DataReceiveKbps") * 1024, true)
					add("data_send_per_sec", 1, statRaw("DataSendKbps") * 1024, true)
					add("physics_receive_per_sec", 1, statRaw("PhysicsReceiveKbps") * 1024, true)
					add("physics_send_per_sec", 1, statRaw("PhysicsSendKbps") * 1024, true)
				end
				add("happatas", 0)
				add("tas_frames", 1, (type(data) == "table") and #data or 0)
				add("tas_frame", 1, tonumber(f) or 0)
				if ClientObjects.Counts then
					local okc, reg, onScreen, playing = pcall(ClientObjects.Counts)
					if okc then
						add("client_objects", 1, tonumber(reg) or 0)
						add("client_objects_on_screen", 1, tonumber(onScreen) or 0)
						add("client_objects_playing", 1, tonumber(playing) or 0)
					end
				end
				if Buttons.Count then
					local okb, nb = pcall(Buttons.Count)
					if okb then add("buttons", 1, tonumber(nb) or 0) end
				end
				-- leaf = no deeper row follows; a group's key is its path
				local path = {}
				for i, c in ipairs(L) do
					path[c[2] + 1] = c[1]
					for p = c[2] + 2, #path do path[p] = nil end
					c.key = table.concat(path, ".")
					local nxt = L[i + 1]
					c.parent = (nxt ~= nil and nxt[2] > c[2])
				end
				return L
			end
			local function rowObj(n)
				local r = cnt.rows[n]
				if not r then
					r = { bg = box(U.cnt.f, BACK[1], 1), star = text(U.cnt.f, 3), name = text(U.cnt.f, 3), v = text(U.cnt.f, 3),
						mn = text(U.cnt.f, 3), mx = text(U.cnt.f, 3), cols = nil, fills = nil }
					cnt.rows[n] = r
				end
				return r
			end
			-- the 128-sample graph: a filled area (0x330088ff) under a line (0xff0088ff)
			local function graph(r, key, x, y0, rows)
				if not r.cols then
					r.cols, r.fills = {}, {}
					for i = 1, HISTORY do
						r.fills[i] = box(U.cnt.f, COL.graph, 2, 1 - 0x33 / 255)
						r.cols[i] = box(U.cnt.f, COL.graph, 2)
					end
				end
				local h = cnt.hist[key]
				local mnv, mxv = cnt.min[key] or 0, cnt.max[key] or 0
				local base, off = mxv, 0
				if mnv < 0 then base = mxv - mnv; off = -mnv end
				local gh = rows * TH
				local yo = y0 + ((rows > 1) and 3 or 1)
				local prevY = nil
				for i = 1, HISTORY do
					local v = h and h[(cnt.histPos + i - 1) % HISTORY + 1] or 0
					v = clampn(v, mnv, mxv)
					local py = (base > 0) and floor(yo + gh - (v + off) * gh / base + 0.5) or (yo + gh)
					place(r.fills[i], x + i - 1, py, 1, mmax(0, yo + gh - py))
					local a = prevY and mmin(prevY, py) or py
					local b = prevY and mmax(prevY, py) or py
					place(r.cols[i], x + i - 1, a, 1, b - a + 1)
					show(r.fills[i], true)
					show(r.cols[i], true)
					prevY = py
				end
			end
			local function hideGraph(r)
				if not r.cols then return end
				for i = 1, HISTORY do show(r.cols[i], false); show(r.fills[i], false) end
			end
			-- every counter's value goes into its history ring (the graphs) and its min / max
			local function sample(L)
				cnt.histPos = cnt.histPos % HISTORY + 1
				for _, c in ipairs(L) do
					if c[3] ~= nil then
						local key, v = c.key, c[3]
						cnt.min[key] = mmin(cnt.min[key] or v, v)
						cnt.max[key] = mmax(cnt.max[key] or v, v)
						local h = cnt.hist[key]
						if not h then h = {}; cnt.hist[key] = h end
						h[cnt.histPos] = v
					end
				end
			end
			function cnt.update()
				local L = build()
				sample(L)
				cnt.list = L
				-- column widths (nTimerWidth, UI.nCounterWidth from the longest value, UI.nLimitWidth)
				local nameW = 7 * CW
				for _, c in ipairs(L) do nameW = mmax(nameW, (2 + #c[1] + 4 * c[2]) * CW) end
				local counterW, limitW = cnt.counterW, 8 * CW
				local maxLen = 7
				local y0 = 27       -- the first row (Roblox: one row lower than microprofile's 2 * 8 + 3)
				local rowW = nameW + counterW * 3 + 100 + limitW + 4 * CW + 4 + HISTORY
				local graphX = nameW + counterW + 3 * CW + limitW + 100 + 5
				local n, skipBelow = 0, nil
				for _, c in ipairs(L) do
					if skipBelow and c[2] > skipBelow then
						-- inside a closed group
					else
						skipBelow = nil
						n = n + 1
						local r = rowObj(n)
						local rows = (cnt.detail[c.key] and cnt.big[c.key]) and 5 or 1
						local yy = y0 + (n - 1) * RH
						place(r.bg, 0, yy, rowW, RH * rows + 1)
						paint(r.bg, BACK[(n - 1) % 2 + 1], 0)
						show(r.bg, true)
						local indent = 4 * c[2] * CW
						local closed = c.parent and cnt.closed[c.key]
						if closed then say(r.star, "*", indent, yy); show(r.star, true) else show(r.star, false) end
						say(r.name, c[1], indent + CW, yy)
						show(r.name, true)
						if c[3] ~= nil then
							local s = fmt(c[3], c[4])
							if #s > maxLen then maxLen = #s end
							say(r.v, s, nameW + counterW - #s * CW, yy)
							show(r.v, true)
						else
							show(r.v, false)
						end
						if c[3] ~= nil and cnt.detail[c.key] then
							graph(r, c.key, graphX, yy, rows)
							local smn, smx = fmt(cnt.min[c.key] or 0, c[4]), fmt(cnt.max[c.key] or 0, c[4])
							say(r.mn, smn, graphX + HISTORY + 5, yy)
							say(r.mx, smx, graphX + HISTORY + 5 + counterW, yy)
							show(r.mn, true); show(r.mx, true)
						else
							hideGraph(r)
							show(r.mn, false); show(r.mx, false)
						end
						r.key, r.parent, r.y, r.rows, r.val = c.key, c.parent, yy, rows, c[3] ~= nil
						if closed then skipBelow = c[2] end
						y0 = y0 + RH * (rows - 1)
					end
				end
				for i = n + 1, cnt.n do
					local r = cnt.rows[i]
					show(r.bg, false); show(r.star, false); show(r.name, false); show(r.v, false); show(r.mn, false); show(r.mx, false)
					hideGraph(r)
					r.key = nil
				end
				cnt.n = n
				cnt.counterW = (1 + maxLen) * CW
				cnt.hov = nil
				cnt.hoverPaint()
				-- the note row and the headers (MicroProfileDrawHeader: the box from x - 8 to x + width + 5)
				local bottom = 27 + n * RH + (y0 - 27)
				place(cnt.note, 0, MENU_H, rowW, RH)
				say(cnt.noteT, NOTE, 0, MENU_H)
				local hx = { 0, nameW, nameW + counterW + 3 * TW, nameW + counterW + 3 * TW + limitW + 100 + 4 }
				hx[5] = hx[4] + HISTORY + 4
				hx[6] = hx[5] + counterW
				local hw = { nameW, counterW + 3 * TW, limitW + 100, HISTORY, counterW, counterW }
				for i, h in ipairs(cnt.heads) do
					place(h.b, hx[i] - 8, 18, hw[i] + 13, RH)
					say(h.t, h.title, hx[i], 18)
				end
				local headW = hx[6] + counterW
				place(cnt.vline, nameW - 2, MENU_H, 1, bottom - MENU_H)
				place(cnt.hline, 0, 2 * TH + 3, headW, 1)
				cnt.rect = { mmax(rowW, headW), bottom + 1 }
				cnt.limitEnd = nameW + counterW + 3 * CW + limitW + 100 + 5
				place(U.cCnt, 0, 0, cnt.rect[1], cnt.rect[2])
			end
			-- the row under the mouse (bInside: only the height counts), lit + 0x2c2c2c
			local function rowAt()
				if activeMenu ~= nil then return nil end
				for i = 1, cnt.n do
					local r = cnt.rows[i]
					if my >= r.y and my < r.y + RH * r.rows then return i end
				end
				return nil
			end
			function cnt.hoverPaint()
				local h = rowAt()
				if h == cnt.hov then return end
				for _, i in ipairs({ cnt.hov or 0, h or 0 }) do
					local r = cnt.rows[i]
					if r and i <= cnt.n then paint(r.bg, ((i == h) and BACK_HOVER or BACK)[(i - 1) % 2 + 1], 0) end
				end
				cnt.hov = h
			end
			-- MicroProfileDrawCounterRecursive's clicks
			function cnt.click(left, right)
				local i = rowAt()
				local r = i and cnt.rows[i]
				if not r then return false end
				if mx > (cnt.limitEnd or 0) and r.val then
					if right then
						cnt.detail[r.key], cnt.big[r.key] = nil, nil
					elseif cnt.detail[r.key] then
						cnt.big[r.key] = not cnt.big[r.key] or nil
					else
						cnt.detail[r.key] = true
					end
					return true
				elseif left and r.parent then
					cnt.closed[r.key] = not cnt.closed[r.key] or nil
					return true
				end
				return false
			end
		end

		-- -------------------------------------------------------------------------------- Flamegraphs
		local flm = { boxes = {}, n = 0, hover = nil }
		do
			local function boxN(n)
				local b = flm.boxes[n]
				if not b then b = { b = gradBox(U.flm.f, 2), t = text(U.flm.f, 3) }; flm.boxes[n] = b end
				return b
			end
			function flm.update(hoverAllowed)
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
					local b = boxN(n)
					local y = it.depth * BAR_H
					local w = mmax(1, it.x1 - it.x0)
					place(b.b, it.x0, y, w, BAR_H)
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
		end

		-- the Ctrl (or Cmd) key: held, clicks go through the profiler to the game ("Hold Ctrl (or Cmd) to
		-- click through", the Roblox client's hint)
		MS.ctrlKeys = {}
		for _, n in ipairs({ "LeftControl", "RightControl", "LeftSuper", "RightSuper", "LeftMeta", "RightMeta" }) do
			local ok, k = pcall(function() return Enum.KeyCode[n] end)
			if ok and k then MS.ctrlKeys[#MS.ctrlKeys + 1] = k end
		end
		function MS.ctrlHeld()
			for _, k in ipairs(MS.ctrlKeys) do
				local ok, down = pcall(UIS.IsKeyDown, UIS, k)
				if ok and down then return true end
			end
			return false
		end

		-- true when the profiler pixel x, y is on a part of the profiler that takes the mouse
		local function overUI(x, y)
			if x < 0 or x >= W or y < 0 then return false end
			if y < MENU_H then return true end
			if graphVisible() and y < MENU_H + HIST_H then return true end
			if U.det.vis and y >= DET_Y then return true end
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

			-- frame graph (its top row is under the menu bar, like Roblox's)
			local graph = newFrame(root, BACK[1], 1)
			graph.Name = "Graph"
			graph.ClipsDescendants = true
			graph.Position = UDim2.fromOffset(0, GRAPH_Y)
			graph.Size = UDim2.new(1, -CLOSE_W, 0, HIST_H)
			U.graph = { f = graph }

			-- close box: a pixel X from (10, 10) to (39, 39), a 46 x 46 0x888888 box under the mouse (measured)
			local close = newFrame(root, BACK[1], 1)
			close.Name = "Close"
			close.Position = UDim2.new(1, -CLOSE_W, 0, GRAPH_Y)
			close.Size = UDim2.fromOffset(CLOSE_W, HIST_H)
			U.close = { f = close }
			U.closeHover = box(close, HOVER, 2)
			place(U.closeHover, 2, 2, CLOSE_W - 4, CLOSE_W - 4)
			show(U.closeHover, false)

			-- the bars and the X: two EditableImages, or 508 gradient frames and 60 pixel frames
			if not GI.make(graph, close) then GI.frames() end
			U.hl = box(graph, HL, 3, HL_T)
			U.hl.f.Name = "Selection"
			show(U.hl, false)

			-- panels under the graph
			local detF = newFrame(root, WHITE, 2, 1)
			detF.Name = "Detailed"
			detF.ClipsDescendants = true
			detF.Position = UDim2.fromOffset(0, DET_Y)
			detF.Size = UDim2.new(1, 0, 1, -DET_Y)
			U.det = { f = detF }
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
			for _, title in ipairs({ "Name", "Value", "Limit", "Graph", "Min", "Max" }) do
				cnt.heads[#cnt.heads + 1] = { title = title, b = box(cntF, BACK[2], 4), t = text(cntF, 5) }
			end
			cnt.note = box(cntF, COL.red, 6)      -- over the headers' top row, like the client's
			cnt.noteT = text(cntF, 7)
			cnt.vline = box(cntF, COL.cline, 4, COL.clineT)
			cnt.hline = box(cntF, COL.cline, 4, COL.clineT)
			show(U.cnt, false)

			local flmF = newFrame(root, WHITE, 2, 1)
			flmF.Name = "Flamegraph"
			flmF.ClipsDescendants = true
			flmF.Size = UDim2.new(1, 0, 0, 3 * BAR_H)
			U.flm = { f = flmF }
			show(U.flm, false)

			-- menu bar
			local menu = newFrame(root, BACK[2], 5)
			menu.Name = "Menu"
			menu.Size = UDim2.new(1, 0, 0, MENU_H)
			U.menu = menu
			U.title = text(menu, 8)
			say(U.title, "MicroProfiler", 0, 0)
			U.dumpBox = box(menu, COL.dump, 6)
			U.items = {}
			for i in ipairs(MENUS) do
				local it = { hl = box(menu, HOVER, 7), t = text(menu, 8) }
				show(it.hl, false)
				U.items[i] = it
			end
			U.readout = text(menu, 8)

			-- the hint under the graph while the mouse is on it (240 x 68 at 20, 69, lines 15 px apart)
			U.hint = box(root, BACK[2], 9)
			place(U.hint, 20, DET_Y + 10, 240, 68)
			U.hintT = { text(U.hint.f, 10), text(U.hint.f, 10), text(U.hint.f, 10) }
			say(U.hintT[1], "This is the MicroProfiler", 16, 15)
			say(U.hintT[3], "Hold Ctrl (or Cmd) to click through", 16, 45)
			show(U.hint, false)

			-- dropdown, tooltip and help windows
			local ddF = newFrame(root, BACK[2], 10)
			ddF.Name = "Dropdown"
			U.dd = { f = ddF }
			show(U.dd, false)
			U.tip = window(12)
			U.help = { window(11), window(11), window(11) }

			-- invisible buttons over every part that takes the mouse, so those clicks never reach the game;
			-- all of them go away while Ctrl is held (click through)
			local catch = newFrame(root, WHITE, 20, 1)
			catch.Name = "Input"
			catch.Size = UDim2.new(1, 0, 1, 0)
			U.catch = { f = catch }
			local function catcher(name)
				local b = newButton(catch, 20)
				b.Name = name
				return { f = b }
			end
			U.cMenu, U.cGraph, U.cDet = catcher("Menu"), catcher("Graph"), catcher("Detailed")
			U.cDd, U.cFlm, U.cTim, U.cCnt = catcher("Dropdown"), catcher("Flamegraph"), catcher("Timers"), catcher("Counters")
			U.cMenu.f.Size = UDim2.new(1, 0, 0, MENU_H)
			U.cGraph.f.Position = UDim2.fromOffset(0, MENU_H)
			U.cGraph.f.Size = UDim2.new(1, 0, 0, HIST_H)
			U.cDet.f.Position = UDim2.fromOffset(0, DET_Y)
			U.cDet.f.Size = UDim2.new(1, 0, 1, -DET_Y)
			U.cFlm.f.Size = UDim2.new(1, 0, 0, 3 * BAR_H)
			for _, c in ipairs({ U.cDet, U.cDd, U.cFlm, U.cTim, U.cCnt }) do show(c, false) end

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
				if t ~= TOUCH and MS.ctrlHeld() then return end -- Ctrl: the click goes through to the game
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
		-- the flame strip: under the graph, or at the bottom of the screen in Detailed (whose view
		-- fills the screen)
		local function flamePlace()
			if not U.built then return end
			local y = (cfg.mode == "Detailed" and not cfg.custom) and floor(H - 3 * BAR_H) or DET_Y
			U.flm.y = y
			if U.flm.py ~= y then
				U.flm.py = y
				U.flm.f.Position = UDim2.fromOffset(0, y)
				U.cFlm.f.Position = UDim2.fromOffset(0, y)
			end
			local on2 = cfg.flame and graphVisible()
			show(U.flm, on2)
			show(U.cFlm, on2)
		end
		local function applyMode()
			if not U.built then return end
			local gv = graphVisible()
			local dv = cfg.mode == "Detailed" and gv and not cfg.custom
			show(U.graph, gv)
			show(U.close, gv)
			show(U.cGraph, gv)
			show(U.det, dv)
			show(U.cDet, dv)
			show(U.tim, cfg.mode == "Timers")
			show(U.cTim, cfg.mode == "Timers")
			show(U.cnt, cfg.mode == "Counters")
			show(U.cCnt, cfg.mode == "Counters")
			slog.on = dv and P.active
			U.barsDirty = true
			timersDirty = true
			countersDirty = true
			hlA, hlN = nil, nil
			if not gv then
				windowHide(U.tip)
				show(U.hint, false)
				show(U.closeHover, false)
			end
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
		-- the key bound to Show / Hide (Controls > MicroProfiler)
		local function closeKey()
			local ok, k = pcall(function() return Controls.Get("MicroProfiler") end)
			return (ok and type(k) == "string" and k ~= "") and k or "F6"
		end
		local function helpUpdate()
			local h = U.help
			if not helpOn then
				windowHide(h[1]); windowHide(h[2]); windowHide(h[3])
				return
			end
			local key = closeKey()
			if graphVisible() then
				windowShow(h[1], W, 20, { { "Left-Click", "Center View" }, { "Right-Click", "Zoom to frame" } }, SEP)
				windowShow(h[2], W, HIST_H + 20, { { "Drag", "Pan View" }, { "Mouse Wheel", "Zoom" },
					{ key, "Show / Hide" }, { "Ctrl+P", "Pause" } }, SEP)
			else
				windowHide(h[1])
				windowShow(h[2], W, HIST_H + 20, { { key, "Show / Hide" }, { "Ctrl+P", "Pause" } }, SEP)
			end
			windowShow(h[3], 0, H - 10, { { "Memory Usage", sfmt("%4.2fmb", luaHeapMb()) }, { "Frames", tostring(K) } }, SEP)
		end
		local function frameUI(recorded)
			tick = tick + 1
			readMouse()
			-- a release Roblox never delivered (the window lost focus with a button held)
			if MS.downL and not MS.touch and not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then MS.downL = false end
			if MS.downR and not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then MS.downR = false end
			-- Ctrl held: the invisible buttons go away, so clicks reach the game
			MS.ctrl = MS.ctrlHeld()
			show(U.catch, not MS.ctrl)
			layoutMenuBar()
			updateMenus()
			if not P.active then return end -- a menu line closed the profiler (Mode > Off)
			local gv = graphVisible()
			local overTip = false
			local detailed = cfg.mode == "Detailed" and gv and not cfg.custom
			local inDet = detailed and activeMenu == nil and mx >= 0 and mx < W and my >= DET_Y and my < H
			-- the graph strip and the close box under the mouse (no menu open)
			local overGraph = gv and activeMenu == nil and mx >= 0 and mx < W and my >= MENU_H and my < MENU_H + HIST_H
			local overClose = overGraph and mx >= W - CLOSE_W
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
				-- the close box right of the graph: grey under the mouse, a click closes the profiler
				show(U.closeHover, overClose)
				if (MS.clickL or MS.clickR) and overClose then
					P.Close()
					return
				end
				if not cfg.custom then updateHighlight() end
			else
				setHover(nil)
			end
			-- the hint box while the mouse is on the graph strip or the close box
			if overGraph then
				say(U.hintT[2], "Press " .. closeKey() .. " to close", 16, 30)
			end
			show(U.hint, overGraph)
			readoutUpdate()
			if detailed then
				if tick % 2 == 0 or det.drag or inDet then det.update(activeMenu == nil and not overTip) end
				local dh = det.hover
				if dh and inDet and not overTip then
					windowShow(U.tip, mx, my + 20, det.tip(dh.j, dh.ms), TIMERS[dh.j].color)
					overTip = true
				end
			end
			if cfg.mode == "Timers" then
				if tick % 6 == 0 or timersDirty then tim.update() end
				if tim.hover and activeMenu == nil then
					windowShow(U.tip, mx, my + 20, det.tip(tim.hover), TIMERS[tim.hover].color)
					overTip = true
				end
			end
			if cfg.mode == "Counters" then
				if (MS.clickL or MS.clickR) and activeMenu == nil and cnt.click(MS.clickL, MS.clickR) then countersDirty = true end
				if tick % 15 == 0 or countersDirty then
					countersDirty = false
					cnt.update()
				else
					cnt.hoverPaint()
				end
			end
			if cfg.flame and gv then
				flamePlace()
				if tick % 15 == 0 or flm.n == 0 then flm.update(false) end
				if activeMenu == nil and not overTip and U.flm.y and my >= U.flm.y and my < U.flm.y + 3 * BAR_H then
					flm.update(true)
					local h = flm.hover
					if h then
						windowShow(U.tip, mx, my + 20, { { h.name, "" }, { "Average", sfmt("%6.3fms", h.ms) } }, WHITE)
						overTip = true
					end
				end
			elseif U.flm.vis then
				show(U.flm, false)
				show(U.cFlm, false)
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
			local t1 = clock()
			tAcc.Profiler = t1 - t0
			tCnt.Profiler = 1
			if slog.on then slog.push("Profiler", t0, t1, 0) end
		end

		function P.SetVisible(v)
			v = v and true or false
			if v and not build() then return end
			P.active = v
			if U.root then U.root.Visible = v end
			lastStart = nil
			for k in pairs(tStart) do tStart[k] = nil end
			if v then
				EVQ.connect()
				applyMode()
			else
				EVQ.disconnect()
				slog.on = false
				activeMenu, helpOn, det.drag = nil, false, nil
				MS.downL, MS.downR, MS.touch = false, false, nil
				clearClicks()
				if U.built then
					ddClose()
					windowHide(U.tip)
					for _, w in ipairs(U.help) do windowHide(w) end
					setHover(nil)
					show(U.hint, false)
					show(U.closeHover, false)
				end
			end
		end

		-- true when the mouse is over any part of the profiler (inputs are not recorded there; with Ctrl
		-- held the clicks go through to the game, so they are). m is a screen point (UIS:GetMouseLocation
		-- space); the current mouse uses the profiler's own pointer.
		function P.IsMouseOver(m)
			if not P.active or not U.built or not U.root.Visible then return false end
			if MS.ctrlHeld() then return false end
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
		do
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
		end

		-- -------------------------------------------------------------------------------- config + presets
		do
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
		end

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
		function P.Internals() return U, { det = det, tim = tim, cnt = cnt, flm = flm, dd = dd, tas = tas, view = view, menuX = menuX, his = HIS, evq = EVQ, ms = MS } end

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

