-- ================================================================================================
--  HELP TEXT  (HappaTAS 3 ui): the Help window's topics, rewritten for HappaTAS 3 from V2.38.17's help (every
--  V2 topic has a home here: its title, or named in a body). topics(E) -> { { id, title, body } }; a body's
--  {key:<control>} becomes the control's key as bound now, in brackets. "missing" lists Env.notes. Text uses
--  only characters every listed font has (ASCII and × ▼ ← … •).
-- ================================================================================================
local Env = import("platform/env")

local HelpText = {}

local CREDITS = table.concat({
	"Happy_Liam/happa - Main Scripter/UI Design",
	"plusgiant5 - Tasability creator",
	"TestMicrowaveDinner - Scripting Help",
	"Skittlesuna - Playtester",
	"Executor port - client side script",
}, "\n")

local TOPICS = {
	{ "start", "Getting started",
		"HappaTAS records what you do frame by frame and plays it back. There are three modes: Idle {key:idle}, "
		.. "Create {key:create} and Test {key:test}.\n\nIn Create you record, pause, go back and record over your "
		.. "mistakes. Test plays the run. The Dock at the top opens the windows; {key:menu} hides or shows the whole "
		.. "interface." },
	{ "idle", "Idle",
		"Idle {key:idle} is the default mode: everything TAS related stops and you play the game like normal. The "
		.. "run you made stays, so you can save it, test it or go back to Create." },
	{ "create", "Create",
		"Create {key:create} switches you to Create mode and pauses you at the last frame of the run (or at the "
		.. "start of a new one). While paused nothing moves: the character, the camera, client objects and the kit's "
		.. "timers all wait for you." },
	{ "pause", "Pause and Unpause",
		"Unpause {key:unpause} starts recording from the frame you are on; anything after it is recorded over. Pause "
		.. "{key:pause} stops recording.\n\nIf you unpause on the frame you jump off a ladder, you are unpaused a frame "
		.. "earlier. A coyote jump you had before pausing is kept." },
	{ "time", "Moving through the run",
		"Back/Forward ({key:back} / {key:forward}): hold to move back and forward through the run; they pause you if "
		.. "you are recording.\n\nBack/Forward 1 Frame ({key:back1} / {key:forward1}): one frame each press.\n\n"
		.. "Return {key:return}: back to the frame you last unpaused at.\n\nUnpause 1 Frame {key:unpause1}: records "
		.. "exactly one frame (two after a landing or a ladder jump). Turn Lock Camera (Paused) off if you want to "
		.. "turn the camera between frames.\n\nThe timeline bar does the same with the mouse: drag the playhead while "
		.. "paused." },
	{ "test", "Test",
		"Test {key:test} plays the run. Playback Speed sets how fast (Test at another speed always shows the "
		.. "Inspector's Frame section). Restart When Testing starts from frame 1, or from the frame you are on when "
		.. "it is off.\n\nInterpolate Playback (on by default) places the character between the two recorded frames "
		.. "for the time that has passed, which stays smooth at any frame rate. Off, the run is played one frame at a "
		.. "time.\n\nShow Completion Message says when the run has finished." },
	{ "camera", "The camera",
		"Lock Camera (Mode): Lock Camera (Paused) holds the camera on the recorded frame while you are paused; with Lock "
		.. "Camera (Test) it follows the recorded camera while testing.\n\nLook Around {key:lookAround}: while paused with the "
		.. "camera locked, look around freely; press it again (or unpause) and the camera goes back to the frame. "
		.. "Zoom and shift lock are recorded with every frame." },
	{ "edit", "Optimize TAS and Delete TAS",
		"Optimize TAS {key:optimize} (in Idle) removes still frames: frames where nothing moved, the camera stayed "
		.. "and no new animation started.\n\nDelete TAS {key:deleteTas} throws the run away. Save it first if you "
		.. "want to keep it." },
	{ "bar", "Timeline bar",
		"The bar at the bottom shows the run while you are in Create or Test. On the left: the mode and the speed; "
		.. "then the buttons: start, back one frame, record / pause, forward one frame, Test and marker. On the right: "
		.. "a dot when the run has changes that aren't saved, and the frame and time.\n\nDrag on it while paused to "
		.. "jump to a frame, scrub it while testing, and zoom with the mouse wheel. The marker button puts a marker on "
		.. "the frame (saved with the run). ▼ opens the lanes: deaths, states and tools, inputs, the kit's events and "
		.. "buttons." },
	{ "inspector", "Inspector",
		"The Inspector shows the numbers of the frame you are on: Frame, Character, Camera & input, World and "
		.. "Performance. Paused, it shows the recorded frame; recording, the newest one; in Test, the playback; in "
		.. "Idle, the character as it is.\n\nPin a row (•) to keep it at the top, hide it (×), and fold sections. "
		.. "Show Stats (Mode) (Idle / Create / Test) chooses whether it shows values in that mode, and Stats Text Size "
		.. "sizes them. It doesn't take the mouse from the game." },
	{ "library", "Library and attempts",
		"Saving and Loading happen in the Library. Every run is a compact .tas file in HappaTasPort/<PlaceId>/ in "
		.. "your executor's workspace, so you only see the runs of the place you are in. There is no size or count "
		.. "limit.\n\nType a name and press Save; saving over a name that exists asks again. New attempt saves "
		.. "\"Name (2)\", \"Name (3)\"… next to the run; they fold under it in the list. Folders go three levels "
		.. "deep. Search, sort, Rename, Move to and Delete (it asks twice) are there too. You can't save while "
		.. "recording, or load while testing." },
	{ "merge", "Merging a TAS",
		"Pick a saved run in the Library and press Merge. It goes before or after the run you have: before only if "
		.. "its last frame is on the ground (Running), after only if its first frame is.\n\nYou then record the piece "
		.. "between them, from the red box (where the run before ends) to the green box (where the run after starts). "
		.. "The Merge window shows how far you are and how close you must be: Complete merge when close enough, "
		.. "Cancel merge otherwise. Closing the window cancels the merge." },
	{ "inputs", "Keyboard and Mouse Inputs",
		"Your keys, mouse buttons, wheel and mouse position are recorded with every frame and replayed while "
		.. "testing through the executor's input functions (keypress, mouse1press, mouse2press, mousemoveabs, "
		.. "mousescroll). HappaTAS's own keys are never recorded, and nothing reacts while you type in chat or a text "
		.. "box. Keep the Roblox window focused during playback (Window Guarding stops replayed input while it isn't) and keep "
		.. "your hands off the keyboard and mouse.\n\nReplay Keyboard, Replay Mouse Clicks and Replay Mouse Movement "
		.. "turn each part off. Normalize Mouse UV (Mouse UV Normalization) stores the cursor as a fraction of the "
		.. "screen, so a run aims the same at another window size. NohBoard Cursor draws a still cursor while the "
		.. "camera is locked (right click, shift lock, first person); Invisible Mouse Speed Multiplier scales how the "
		.. "hidden cursor moves." },
	{ "death", "Death & Respawn Recording",
		"With Record Death & Respawn on, a run can go through deaths (kill bricks, resets, respawn shortcuts): the "
		.. "death frame is kept and playback carries on with the new character." },
	{ "tools", "Tool Actions Support",
		"Record Tool Actions records equipping, unequipping and using tools. During playback a tool that isn't there "
		.. "is skipped with a short notice." },
	{ "buttons", "Button & Obby Mechanism Sync",
		"Sync Button Timers: the EToH kit's buttons and timers (timed switches, pressure plates, countdown doors, "
		.. "disappearing parts) are saved with every press. While paused the timers wait; going back puts the buttons "
		.. "back exactly; testing runs them on the run's clock. Sync Lighting keeps lighting changes with the run." },
	{ "co", "Client Objects",
		"Sync Client Objects records the parts only your game client moves: moving, falling and swinging "
		.. "platforms, pushboxes, vanishers, morphs and the like. They are saved with the run and put back while "
		.. "testing and scrubbing. Smooth Client Objects blends between the saved positions so they move smoothly at "
		.. "any frame rate.\n\nFrustum Culling CO (V2's Frustum Culling & Sandboxing) only keeps objects that are on "
		.. "screen or within 25 studs, which keeps files small." },
	{ "kit", "EToH Kit Objects",
		"Kit Scripts On TAS Clock: the EToH kit's own timers (waits, delays, tweens) follow the run's clock, so they "
		.. "stop while paused and slow down with the speed hack. A jump launcher's push, moving platforms and spawner "
		.. "cooldowns keep the same timing whether you pause or not.\n\nSync Kit Objects: beat blocks follow the run's "
		.. "time, turret bullets are saved with their hits and damage, pushboxes are hidden before they were spawned, "
		.. "and bounce pad and launcher effects play again in Test." },
	{ "speed", "Speed Hack (Slow / Fast Motion)",
		"Turn on Speed Hack to record in slow or fast motion, like a video played slower or faster. Speed Hack Speed "
		.. "goes from 0.1 to 4. Bind Toggle Speed Hack {key:toggleSpeedHack} in Controls to switch it while "
		.. "recording.\n\nThe run is saved in normal time, so Test plays it at normal speed. Gravity, walking, "
		.. "jumping, animations, the zoom and the world (spinners, platforms, swings, conveyors, bounce pads, "
		.. "ziplines, the kit's timers) all change speed.\n\nSpeed Hack Frame Step (below 1x): Roblox's normal "
		.. "physics runs on some frames only and everything is held in between, so walking, jumping and pushing are "
		.. "exactly like normal speed." },
	{ "settings", "Executor Port Settings",
		"Ignore Game Processed lets HappaTAS's keys work when Roblox marks a key as used by the game (the Menu key "
		.. "always works). No HappaTAS key does anything while you type. Allow PlayerGui Interface puts the "
		.. "interface in PlayerGui on an executor that has neither gethui nor CoreGui access (off by default).\n\n"
		.. "Settings and Controls are their own windows; every setting has a reset arrow (←) when it isn't at its "
		.. "default." },
	{ "profiler", "MicroProfiler",
		"V2's copy of Roblox's MicroProfiler ({key:microProfiler}) comes back in a later part of HappaTAS 3. Its "
		.. "settings (Show MicroProfiler, MicroProfiler Scale, MicroProfiler Text Offset) are kept until then." },
	{ "limits", "Known limits",
		"Some things can't follow the run: other players; Roblox's own timers inside the humanoid; the moment the "
		.. "character bumps into a platform it pushes in Frame Step (the push can start a little later, or stall); "
		.. "kit listeners whose function the executor can't see. Turn on Sync Client Objects for platforms you need "
		.. "exactly." },
	{ "missing", "Missing executor functions", "" },
	{ "credits", "Credits", CREDITS },
}

-- the topics with keys filled in (the controls as bound now) and the missing functions listed
function HelpText.topics(E)
	local out = {}
	for _, t in ipairs(TOPICS) do
		local body = t[3]
		if t[1] == "missing" then
			body = (#Env.notes > 0) and table.concat(Env.notes, "\n") or "None: every feature is available"
		end
		body = body:gsub("{key:([%w]+)}", function(key)
			local k = E and E.controls and E.controls:get(key)
			return "[" .. tostring(k or "?") .. "]"
		end)
		out[#out + 1] = { id = t[1], title = t[2], body = body }
	end
	return out
end

return HelpText
