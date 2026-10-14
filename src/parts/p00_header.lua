--[[
	HappaTAS - Executor Port (single file, client side only)
	Version: V2.38

	What this file is:
		One LocalScript-style file for executors. It records and replays TAS runs on the client and
		saves them as compact .tas files in   <executor workspace>/HappaTasPort/<PlaceId>/

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

local VERSION = "V2.38"

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
		FullEvery     = 600,
		VisEvery      = 6,
		PosTolerance  = 0.015,
		RotTolerance  = 0.0015,
		MaxModelAge   = 1.0,
		MaxRegistered = 8000,
		MaxWatched    = 30000,
		WatchAnchored = true,
		Groups        = { ClientObjects = true },
	},
}

