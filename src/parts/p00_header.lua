--[[
	HappaTAS - Executor Port (single file, client side only)
	Version: V2.36 (Rebuild Edition)

	What this file is:
		One LocalScript-style file for executors. It records and replays TAS runs on the client and
		saves them as compact .tas files in   <executor workspace>/HappaTasPort/<PlaceId>/

	V2.36 changes (short):
		- MicroProfiler matches the current Roblox client: Roboto Mono Bold font with the 1 px shadow,
		  the "MicroProfiler" title, the real menus (Mode, Groups, Aggregate, Timers, Options, Preset,
		  Custom, [Dump], Flamegraphs, Pause, Help, Network), the frame tooltip and the close box.
		- Time = the last frame, Avg = the average of the frames on the bar, Max = the biggest frame,
		  kept until a bigger one (the same for every Aggregate setting, and in Hidden mode).
		  Aggregate Infinite counts the frames as Aggregate[1], [2], [3]...; picking it resets Max.
		- New modes: Detailed (HappaTAS work on a timeline), Timers, Counters, plus a flame graph.
		- Clicks work in the real client: the mouse is read in Roblox's GUI coordinates (the top bar
		  inset taken into account) and every click goes through UserInputService. The text sits at
		  the height of Roblox's, and Settings > MicroProfiler Text Offset can move it by whole pixels.

	V2.35 changes (short):
		- Rebuilt structure: every system is its own module with one clear job, settings live in a
		  plain Lua table (no more Value instances), and every feature reads them the same way.
		- Fixed a set of nil globals that silently disabled Window Guarding, the menu check of the mouse
		  lock, keyboard/click sounds and parts of Unload.
		- Timed buttons (EToH kit v6.1.3) are now saved and restored: press state + elapsed timer per frame,
		  the kit's own timer is frozen while paused and follows the TAS clock while testing.
		- First person recording: the camera no longer needs a right click after unpausing.
		- Fake cursor: no more one-frame gap on right click (the fake cursor is shown first, the real
		  cursor is hidden two frames later, both sit on the same pixel).
		- Smooth client objects: playback blends towards the next recorded keyframe (Tasability style
		  render segments) on the same clock as the character, so platforms and the player stay in sync.
		- File format v3: mouse viewport, tools, deaths and button events are saved (v1/v2 still load).
		- New MicroProfiler: looks like Roblox's (menu bar + frame bar graph + green frame cursor),
		  shows real measurements only, costs O(1) per frame.
		- Security: no network code, services via cloneref, interface under gethui()/CoreGui, only an
		  Unload handle is shared in getgenv, loaded files are size/format checked.
]]

local VERSION = "V2.36"

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

