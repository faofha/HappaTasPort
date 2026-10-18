--[[
	HappaTAS - Executor Port (single file, client side only)
	Version: V2.38.16

	What this file is:
		One LocalScript-style file for executors. It records and replays TAS runs on the client and
		saves them as compact .tas files in   <executor workspace>/HappaTasPort/<PlaceId>/

	V2.38.16 changes (short): fast motion, Frame Step slow motion, zoom, bounce pad / launcher effects
		- Speed hack: speeds above 1 (up to 4x: fast motion while recording, saved and tested at normal speed
		  like slow motion). Settings > Speed Hack > Speed 0.1 - 4.
		- Speed hack Frame Step (Settings > Speed Hack, below 1x): nothing is scaled. Roblox runs its normal
		  physics on some frames only (one in two at 0.5x) and everything that moves is held still for the
		  physics step of the others; only the frames whose step ran are recorded, with that step's time.
		  Walking, jumping and falling are exactly like normal speed, and a platform you push yourself (the
		  kit's Pushing Platform) speeds up like at normal speed instead of far too fast; the moment you bump
		  into it can still play out differently. Smooth (the scaled slow motion) stays the default.
		- The camera's zoom spring runs on the TAS clock: a zoom recorded in slow / fast motion plays back at
		  its normal speed (before: 2x too fast at 0.5x, too slow at 2x).
		- Bounce pads and jump launchers: their effect (sound, particle burst) is saved when the kit plays it
		  and played again while testing (the kit only plays it on a real touch). File event 4.
		- Kit scripts that move things by RunService's frame time (the Zipline ride, the Sequencer) follow the
		  TAS clock too (paused, slow / fast motion, Frame Step), through getconnections.
		- Swings: their Boost is slowed with the world, like a bounce pad's Power.
		- The game's camera script is patched again (zoom spring, mouse behaviour, camera freeze while paused):
		  since V2.38.2 the garbage collector scan found the cameras before the bridge looked for the
		  PlayerModule, and the patches were never made (found in the client).
		- Checked in the Roblox client (EToH kit test place): Frame Step walks and jumps exactly like 1x (same
		  height, states and times); the Pushing Platform accelerates the same once pushed, but the moment the
		  character hits it plays out differently (it lands on the slower of 1x's outcomes, and a push can stall);
		  the zoom spring runs at the speed hack's rate; bounce pad effects saved and played in Test. Holding
		  the world costs about 0.5 ms per held frame (16 parts in the test place).

	V2.38.15 changes (short): bounce pads in slow motion, client objects saved from their start
		- Speed hack: a bounce pad (EToH kit) sets your velocity to its Power itself, so with the slowed
		  gravity a slowed bounce went 1 / speed^2 as high (4x at 0.5x). Its Power is slowed with the world now
		  (x speed while recording, put back after): the same bounce height and timing at any speed (checked in
		  the client: 30.1 studs at 1x, 30.4 at 0.5x, 30.5 at 0.25x).
		- Client objects: a part that changes for the first time while recording (a morph growing when its
		  button is pressed, a vanisher, a platform that starts to fall) gets the state it had before into the
		  TAS. Before, a TAS had nothing for it until it changed, so playback left it as it was then: after
		  running the script again or loading the TAS later the morph showed pressed from the first frame.
		- Not slowed: a pushing platform you push yourself (the kit's Pushing Platform, the X pushers). The
		  push comes from Roblox's own walking force inside the Humanoid, which no script can slow down, so
		  the platform still moves too fast in slow motion. Record those parts at normal speed.

	V2.38.14 changes (short): the EToH kit's objects on the TAS clock, the speed hack slows the world too
		- Kit Clock (Settings > World Sync > Kit Scripts On TAS Clock, on): the kit's own scripts wait, delay,
		  time and tween on the TAS clock: stopped while paused in Create mode, slowed by the speed hack, at the
		  playback speed in Test. A jump launcher's push lasts its 0.125 s of TAS time even when you pause in
		  the middle of it (before: a pause cut the jump to about half its height); moving platforms,
		  vanishers, falling platforms and spawner cooldowns wait for the TAS too. (Eternal Obbying's TAS
		  works this way: its whole game runs on one clock that its TAS speed slows down.) A pause also puts
		  the kit's clock back on the last recorded frame, so pausing never gives the kit an extra frame.
		- Sync Kit Objects (on): beat blocks follow the TAS time with the kit's own rules (the group that is
		  on, the indicator, the ding), so a recording and its test always have the same beat and a paused
		  TAS stops beating. Turret bullets are saved in the TAS (where and when each one was fired, its
		  speed and lifetime): they fly the same way while recording, paused (frozen, also on any frame you
		  go back to) and testing, stop at walls and hit your character with the kit's damage. A pushbox a
		  spawner makes is hidden on the frames before it was spawned.
		- The speed hack slows the world too: every constraint and body mover (spinners, moving platforms,
		  swings, pushers, the jump launcher's push), conveyors and the motion of free parts.
		- Idle (key 1) leaves the lighting as it is (before: it went back to the lighting at the TAS's start).
		- File format v5 (bullets, spawns, the speed hack factor): older versions refuse it, v1 - v4 files load
		  as before, and TAS files from before V2.38.14 keep the kit's own behaviour.
		- Checked in the Roblox client (EToH kit test place): beat blocks right on every recorded, paused and
		  tested frame, bullets where the saved events put them, the launcher's push 0.125 s of TAS time with
		  or without a pause, spinners / conveyor / platform at half speed in 0.5x slow motion.

	V2.38.13 changes (short): speed hack (slow motion while recording)
		- Settings > Speed Hack slows the game down while you record in Create mode, like a video played
		  slower (Speed 0.1 - 1, 0.5 = half speed; a key for Toggle Speed Hack can be picked in Controls).
		  Gravity x speed^2, WalkSpeed and JumpPower x speed, the character's motion and HappaTAS's
		  animations x speed (JumpHeight jumps stay as high). The frames are saved in normal time (their time
		  x speed, the velocity / speed), so Test plays the TAS at normal speed and a slow recording is the
		  same TAS a normal one makes (tested frame by frame). Paused, Idle, Test and while dead everything
		  runs at normal speed. Moving parts and other players keep their speed (like Tasability's speed
		  hack); timed buttons follow the TAS clock, so they slow down too.
		- Client objects move on their own clocks (physics parts on the simulation clock, scripted parts on
		  the wall clock) and a part that turns while it moves is one screw motion: a spinner needs a key
		  about every 2 s instead of every frame (a test TAS: 17.8 KB -> 4.0 KB). File format v4 (older
		  versions refuse it instead of playing its client objects wrong; v1 - v3 files load as before).
		- Frames without a physics step (above 60 FPS Roblox steps physics at 240 Hz, so some frames have
		  none) are recorded in Heartbeat instead of being dropped: a TAS recorded at 240 FPS lost about
		  12 % of its frames and time and replayed too fast.
		- Camera calls (zoom, first person, shift lock, the zoom spring, the mouse lock offset) run in a
		  thread of their own again: called directly they took the frame's access to the interface away
		  ("lacking capability Plugin" while paused in Create mode, checked in the client).

	V2.38.5 - V2.38.12 (made in the release build, now in src/parts too): timed buttons and their timer UI,
	Lighting Changers, vanishers, beat blocks, morphs, camera freeze while paused, first person / shift lock
	fixes, see the update log.

	V2.38.4 changes (short): the MicroProfiler's Avg counts every frame
		- Avg in the Time / Avg / Max readout is the average of every frame since the count started, also the
		  frames that already left the graph (before: only the 508 frames on the graph). Max is the biggest
		  frame since then, as before. This is what Roblox's own profiler shows with Aggregate Infinite.
		- Picking Aggregate Infinite starts the count again: Aggregate[1], Avg and Max (before, Max went back
		  to the biggest frame still on the graph).
		- Custom > TAS Timeline works the same way with the TAS: Avg and Max cover the TAS's frames from the
		  first one to the current one (the number Aggregate[N] shows there). A [Dump] writes the same Avg /
		  Max as the readout.

	V2.38.3 changes (short): harder for game scripts to notice
		- The game's camera script is changed with the executor's hookfunction when it has one: its functions
		  stay the same function values (before, they were swapped for HappaTAS's own in the script's tables,
		  which a game script could notice). Unload undoes it with restorefunction.
		- The interface only goes to PlayerGui, where game scripts can see it, when "Allow Visible Interface
		  (PlayerGui)" is on (off by default). It is only needed on an executor without gethui() or CoreGui.

	V2.38.2 changes (short): every function in Real's documentation checked against HappaTAS, the ones
	that help are used now (measured in the Roblox client)
		- Keys: Real's keypress sends a key's scancode without the "extended key" flag, so Up arrived as
		  Keypad 8, Left as Keypad 4, Home as Keypad 7, Right Ctrl as Left Ctrl and so on. These keys are
		  replayed through Roblox's VirtualInputManager, which gives Roblox the exact key.
		- Mouse: Roblox showed an injected move only when the next mouse event came (every move one move
		  late, the last one never). Each move is followed by a 1 pixel step right and back.
		- Mouse: Real's mousemoveabs scales with whole-number maths, so the cursor landed up to 0.4 % (x) /
		  1.2 % (y) short, 8 / 11 px at the edges of a 1920x1080 screen. HappaTAS measures where its moves
		  land and aims through that: within 1 px.
		- Keys the TAS holds while the Roblox window isn't focused (Real sends no input then) are pressed
		  as soon as it is focused again.
		- The game's camera scripts are found with filtergc instead of getgc(true), which put every object
		  of the game's memory in one table (Real's own tools refuse to run it: it can freeze the client).
		- Help: the cloneref sentence was wrong (cloneref only makes a second reference).

	V2.38.1 changes (short): the MicroProfiler's numbers checked against Roblox's own, frame by frame
		- Roblox's MicroProfiler dumps (read with Roblox's open-source LibMP) show how it colours a bar:
		  Jobs Wall Time = from the frame's start to the end of its PreRender step, Render Wall Time = its
		  Prepare + Perform steps (Roblox's dump viewer does exactly this, and so did every bar of the
		  client's own graph).
		- Stats.RenderCPUFrameTime is exactly that Render Wall Time three frames later, and
		  Stats.RenderGPUFrameTime exactly the GPU device time one frame later. They are now paired with
		  the right frame (before, with the wrong one), so a frame joins the graph three frames after it
		  ran, like in Roblox's profiler.
		- CPU Time (the bar's height) = PreAnimation to the next PreAnimation, within 0.1 ms of Roblox's.
		- Jobs Wall Time = PreAnimation to the end of HappaTAS's PreRender work + 0.37 ms: the two pieces
		  no script can time, measured in Roblox's dumps with HappaTAS running.
		- In the real client, both profilers paused on the same frame: the same 503 frames, every bar the
		  same height, 501 of them the same colour.
		- The frame tooltip has Roblox's rows: CPU Time, GPU Time, GPU Time (device), Render / Jobs Wall
		  Time and Mem Used (the same value as Roblox's). GPU Wait Time, CPU Freq and Mem Free have no API.
		- Detailed: the Engine lane draws each frame like Roblox's (the jobs from the frame's start, then
		  the render).

	V2.38 changes (short): the MicroProfiler compared side by side with Roblox's own, in the real client
		- The close box (X) turns grey under the mouse, with Roblox's hint box ("Press F6 to close",
		  "Hold Ctrl (or Cmd) to click through"). Holding Ctrl lets clicks go through to the game.
		- [Dump] always sits on its lighter box. The graph starts under the menu bar like Roblox's, the
		  green selection and the tooltip's red square match too.
		- Frame bar colours work like Roblox's (Roblox docs): orange = the frame's jobs (animations,
		  physics, scripts) took longer than its render, blue = the render took longer. Jobs are timed
		  from RunService.PreAnimation to the next frame, plus 0.3 ms for the engine work before
		  PreAnimation that no script can time (measured against Roblox's own profiler). Red bars need
		  the GPU wait time, which no API gives.
		- The frame graph is one EditableImage instead of 508 frames: the profiler costs about 0.1 ms of
		  render time instead of 0.4-0.6 ms (measured), so it no longer pushes the bars towards blue.
		  Clients without EditableImage get the frames.
		- Detailed: lanes like Roblox's ("0000:  Engine" = each frame's render, jobs, animations,
		  simulation and heartbeat; "0001:  HappaTAS" = its own work), time ruler and frame lines.
		- Timers: Roblox's timer tooltip (frame time, average, max, min, calls, exclusive times, group)
		  with a border in the timer's colour.
		- Counters: Roblox's layout (Name, Value, Limit, Graph, Min, Max; groups collapse; a click shows
		  a counter's graph). Roblox's own counters can't be read by scripts, so the values come from
		  Stats, collectgarbage and HappaTAS, and the red line at the top says so.
		- The profiler is drawn above Roblox's top bar, like Roblox's.

	V2.37.2 changes (short): tested in the real Roblox client (EToH kit), the bugs found there fixed
		- The interface always loads: re-running the script could leave the new copy without access to
		  gethui() / CoreGui (the old copy's unload took it away), and calls into the game's camera module
		  (zoom, shift lock, mouse lock) did the same for the rest of the frame. Those calls run in a thread
		  of their own now, leftover interfaces are removed and attaching retries one frame later.
		- Client objects HappaTAS holds stay where they belong when a game script un-anchors them (the
		  EToH kit's DistanceCulling does it every 0.2 s): anchored again and put back on their pose.
		- Rebinding a control: the key press that gave it the new key no longer runs its old action.
		- Replay Keyboard: replayed keys came back as live input (sound played twice in Sound Mode 2).
		- The click sound plays: its asset id was a Roblox Place, not a sound (Roblox printed six "Failed to
		  load sound" errors on every start). It is now a sound file that comes with the Roblox client.
		- Errors in the frame handlers are printed to the console once each (before: only with Debug on).
		- 2-5x less CPU per frame (measured in game): Roblox's automatic translation (AutoLocalize) checked
		  every text HappaTAS wrote and is now off for HappaTAS's own interfaces, client objects at rest
		  skip the velocity work, the MicroProfiler menu bar is only laid out again when a label changes.
		- The same TAS files and behaviour as V2.37.1 (checked frame by frame, headless).

	V2.37.1 changes (short):
		- The Menu key works even when the game processed the key press (Ignore Game Processed off).
		- No HappaTAS key does anything while you type: chat (the new TextChatService chat too), any text
		  box (HappaTAS's slot names and settings too) or the Roblox menu, whatever Ignore Game Processed
		  says. Keys typed there are not recorded into the TAS either.
		- A click on a HappaTAS window (menu, merge dialog, MicroProfiler) never pauses / unpauses.

	V2.37 changes (short):
		- Faster: client objects notice property / Anchored changes through change signals instead of
		  reading every part every frame, unchanged parts skip the maths, poses and property writes are
		  reused while a part's state is the same (60-80% fewer engine calls with Sync Client Objects).
		  The stats panel remembers what it wrote, no closures or extra tables per frame.
		- Smaller: the interface is built from compact data, repeated code is shared, and the release
		  file has no comments or blank lines (the commented source is src/parts/ in the repository).
		- The same TAS files and the same behaviour as V2.36 (checked frame by frame, headless).

	V2.36: MicroProfiler like the current Roblox client (font, menus, tooltip, Time / Avg / Max,
	       Aggregate[N], Detailed / Timers / Counters modes, flame graph, clicks in the real client).
	V2.35: rebuilt into modules with one job each, settings in a plain table, timed buttons saved, first
	       person and fake cursor fixes, smooth client objects, file format v3, new MicroProfiler,
	       no network code, interface under gethui() / CoreGui, only an Unload handle in getgenv.
]]

local VERSION = "V2.38.16"

-- ------------------------------------------------------------------------------------------------ config
local CONFIG = {
	RootFolder      = "HappaTasPort",
	TakeOverAnimate = true,
	DisableAutoJump = true,
	Debug           = false,
	MaxFileBytes    = 512 * 1024 * 1024, -- refuse to decode anything bigger (corrupt / hostile files)
	ClientObjects = {
		Radius        = 450,
		AlwaysRadius  = 35,
		FullEvery     = 2400, -- a full snapshot at least every 2400 recorded frames...
		FullSeconds   = 10,   -- ...and every 10 s of TAS time
		VisEvery      = 6,
		PosTolerance  = 0.015,
		RotTolerance  = 0.0015,
		MaxModelAge   = 2.0,
		MaxRegistered = 8000,
		MaxWatched    = 30000,
		WatchAnchored = true,
		Groups        = { ClientObjects = true },
	},
}

