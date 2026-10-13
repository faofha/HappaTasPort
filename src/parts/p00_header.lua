--[[
	HappaTAS - Executor Port (single file, client side only)
	Version: V2.37.1

	What this file is:
		One LocalScript-style file for executors. It records and replays TAS runs on the client and
		saves them as compact .tas files in   <executor workspace>/HappaTasPort/<PlaceId>/

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

local VERSION = "V2.37.1"

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

