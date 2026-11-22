-- ================================================================================================
--  HELP TEXT  (HappaTAS 3 ui): the Help topics, short sections in short sentences (every V2.38.17 help
--  topic has a home here: its title, or named in a body). topics(E) -> { { id, title, body } }; a body's
--  {key:<control>} becomes the control's key as bound now, in brackets. "missing" lists Env.notes. Text uses
--  only characters every listed font has (ASCII and × ▼ ← … •). The credits and what's new aren't Help
--  topics: the About window and Classic's More page show them (one list each, here).
-- ================================================================================================
local CONFIG = import("config")
local Env = import("platform/env")

local HelpText = {}

-- what this version brings: the About window's update log and Classic's (More tab); one line an item, at
-- most 60 characters (a classic update log row is 360 px of 12 px text)
HelpText.WHATS_NEW = {
	version = CONFIG.VERSION,
	items = {
		"A new interface: Dock, windows, timeline bar, Inspector",
		"Classic interface: Settings > Interface",
		"Library: folders, search, sort, numbered attempts",
		"File format v6: smaller files, safe saving",
		"Old .tas files (v1-v5) and Settings.json carry over",
		"Smaller files and faster saving, a clean Unload",
		"Touch buttons and thumbstick replay on phones",
		"The MicroProfiler on the new engine",
	},
}

-- the credits, in order (the About window and Classic's More page)
HelpText.CREDITS = {
	"Happy_Liam/happa - UI design",
	"plusgiant5 - Tasability creator",
	"9kwr - Tasability UI design",
	"TestMicrowaveDinner - Scripting Help",
	"Skittlesuna - Playtester",
}
HelpText.PORT = "Executor port - client side script"

local TOPICS = {
	{ "start", "Getting started",
		"HappaTAS records what you do, frame by frame, and plays it back.\n\n"
		.. "1. Press {key:create} for Create. You start paused.\n"
		.. "2. Press {key:unpause} to record. Press {key:pause} to pause.\n"
		.. "3. Made a mistake? Go back, then unpause to record over it.\n"
		.. "4. Press {key:test} to play the run.\n"
		.. "5. Save it in the Library.\n\n"
		.. "The Dock at the top opens the windows. {key:menu} hides or shows the interface.\n\n"
		.. "If you used V2, its settings and keys were converted on the first start (HappaTasPort/Settings3.json). "
		.. "To convert them again: unload HappaTAS first (Unload HappaTAS below the topics, or rejoin), then delete "
		.. "HappaTasPort/Settings3.json, then run the script. That also resets the look, the windows and the "
		.. "interface choice." },
	{ "modes", "Modes",
		"• Idle {key:idle}: play the game normally. Your run stays, so you can save it, test it or go back to "
		.. "Create.\n"
		.. "• Create {key:create}: record. You start paused on the run's last frame (or at the start of a new run). "
		.. "While paused nothing moves: the character, the camera, client objects and the kit's timers wait.\n"
		.. "• Test {key:test}: play the run." },
	{ "pause", "Pause and Unpause",
		"• Unpause {key:unpause} records from the frame you are on. Everything after it is recorded over.\n"
		.. "• Pause {key:pause} stops recording.\n\n"
		.. "A coyote jump you had before pausing is kept. Unpausing on the frame you jump off a ladder unpauses you "
		.. "a frame earlier." },
	{ "time", "Moving through the run",
		"• Back/Forward ({key:back} / {key:forward}): hold to move through the run. They pause you if you are "
		.. "recording.\n"
		.. "• Back/Forward 1 Frame ({key:back1} / {key:forward1}): one frame each press.\n"
		.. "• Return {key:return}: back to the frame you last unpaused at.\n"
		.. "• Unpause 1 Frame {key:unpause1}: records exactly one frame (two after a landing or a ladder jump).\n"
		.. "• The timeline bar: drag the playhead while paused.\n\n"
		.. "• Optimize TAS {key:optimize} (in Idle): removes still frames, where nothing moved, the camera stayed and "
		.. "no new animation started.\n"
		.. "• Delete TAS {key:deleteTas}: throws the run away. Save it first if you want to keep it." },
	{ "test", "Test",
		"• Playback Speed: how fast Test plays. At another speed the Inspector always shows its Frame section.\n"
		.. "• Restart When Testing: on, Test starts from frame 1. Off, from the frame you are on.\n"
		.. "• Interpolate Playback (on by default): the character is placed between the two recorded frames, so "
		.. "playback is smooth at any frame rate. Off, the run plays one frame at a time.\n"
		.. "• Show Completion Message: says when the run has finished." },
	{ "camera", "The camera",
		"• Lock Camera (Mode): Lock Camera (Paused) holds the camera on the recorded frame while you are paused. "
		.. "Lock Camera (Test) follows the recorded camera while testing.\n"
		.. "• Look Around {key:lookAround}: while paused with the camera locked, look around freely. Press it again "
		.. "(or unpause) and the camera goes back to the frame.\n"
		.. "• Turn Lock Camera (Paused) off to turn the camera between frames.\n\n"
		.. "Zoom and shift lock are recorded with every frame." },
	{ "bar", "Timeline bar",
		"The bar at the bottom shows the run in Create and Test.\n\n"
		.. "• Left: the mode and the speed.\n"
		.. "• Buttons: start, back one frame, record / pause, forward one frame, Test, marker.\n"
		.. "• Right: a dot when the run has unsaved changes, then the frame and the time.\n\n"
		.. "Drag on it while paused to jump to a frame, or while testing to scrub. The mouse wheel zooms. The marker "
		.. "button marks the frame (saved with the run). ▼ opens the lanes: deaths, states and tools, inputs, the "
		.. "kit's events and buttons." },
	{ "inspector", "Inspector",
		"The numbers of the frame you are on, in sections: Frame, Character, Camera & input, World, Performance.\n\n"
		.. "• Paused: the recorded frame. Recording: the newest one. Test: the playback. Idle: the character now.\n"
		.. "• Pin a row (•) to keep it at the top, hide it (×), fold a section.\n"
		.. "• Show Stats (Mode) (Idle / Create / Test): whether it shows values in that mode. Stats Text Size "
		.. "sizes them.\n\n"
		.. "It doesn't take the mouse from the game." },
	{ "library", "Library: Saving and Loading",
		"Saving and Loading happen in the Library.\n\n"
		.. "• Each run is a .tas file in HappaTasPort/<PlaceId>/ in your executor's workspace. You only see the runs "
		.. "of the place you are in. No size or count limit.\n"
		.. "• Type a name and press Save. Saving over a name that exists asks again.\n"
		.. "• New attempt saves \"Name (2)\", \"Name (3)\"… They fold under the run in the list.\n"
		.. "• Folders (three levels), search, sort, Rename, Move to and Delete (it asks twice).\n"
		.. "• You can't save while recording, or load while testing.\n"
		.. "• Old .tas files load." },
	{ "merge", "Merging a TAS",
		"1. Pick a saved run in the Library and press Merge.\n"
		.. "2. Choose Before or After. Before works only if its last frame is on the ground (Running); after, only if "
		.. "its first frame is.\n"
		.. "3. Record the piece between them: from the red box (where the run before ends) to the green box (where "
		.. "the run after starts).\n"
		.. "4. The Merge window shows how far you are and how close you must be. Press Complete merge when close "
		.. "enough, or Cancel merge.\n\n"
		.. "Closing the window cancels the merge." },
	{ "inputs", "Keyboard and Mouse Inputs",
		"Your keys, mouse buttons, wheel and mouse position are recorded with every frame. Test replays them "
		.. "through the executor (keypress, mouse1press, mouse2press, mousemoveabs, mousescroll).\n\n"
		.. "• Keep the Roblox window focused during playback, and your hands off. Window Guarding stops replayed input "
		.. "while it isn't focused.\n"
		.. "• HappaTAS's own keys are never recorded. Nothing reacts while you type in chat or a text box.\n"
		.. "• Replay Keyboard, Replay Mouse Clicks and Replay Mouse Movement turn each part off.\n"
		.. "• The cursor is stored as a fraction of the screen, so a run aims the same at another window size.\n"
		.. "• NohBoard Cursor draws a still cursor while the camera is locked (right click, shift lock, first "
		.. "person). NohBoard Mouse Speed (at most 1) scales how the hidden cursor moves.\n"
		.. "• Keep Mouse Position (Paused) shows a see-through cursor where the mouse was on the frame shown, and "
		.. "puts the mouse back there when you unpause.\n"
		.. "• Hold right click while paused and the cursor stays locked, as in the game, so unpausing with it held "
		.. "doesn't turn the camera." },
	{ "world", "Client Objects and the world",
		"Sync Client Objects (on by default) is one switch for everything that follows the run besides your "
		.. "character.\n\n"
		.. "• Client Objects: parts only your game client moves (moving, falling and swinging platforms, pushboxes, "
		.. "vanishers, morphs). Saved with the run, put back while testing and scrubbing, smooth at any frame rate. "
		.. "Only objects on screen or within 25 studs are kept, which keeps files small.\n"
		.. "• Button & Obby Mechanism Sync: the EToH kit's buttons and timers (timed switches, pressure plates, "
		.. "countdown doors, disappearing parts) are saved with every press. Paused, the timers wait.\n"
		.. "• EToH Kit Objects: the kit's own timers follow the run's clock. Beat blocks follow the run's time, turret "
		.. "bullets are saved with their hits, pushboxes are hidden before they spawn, bounce pad and launcher "
		.. "effects play again in Test.\n"
		.. "• Lighting changes are kept with the run.\n\n"
		.. "Death & Respawn Recording (Record Death & Respawn): a run can go through deaths; playback carries on with "
		.. "the new character.\n"
		.. "Tool Actions Support (Record Tool Actions): equipping, unequipping and using tools. A tool that isn't "
		.. "there in playback is skipped." },
	{ "speed", "Speed Hack (Slow Motion)",
		"Records in slow motion, like a video played slower. Test plays the run at normal speed.\n\n"
		.. "• Speed Hack turns it on. Speed Hack Speed goes from 0.1 to 1.\n"
		.. "• Toggle Speed Hack {key:toggleSpeedHack} (bind it in Controls) switches it while recording.\n"
		.. "• Speed Hack In: Create (recording, the default) and / or Idle (nothing is saved there).\n\n"
		.. "Gravity, walking, jumping, animations, the zoom and the world (spinners, platforms, swings, conveyors, "
		.. "bounce pads, ziplines, the kit's timers) all slow down.\n\n"
		.. "Roblox's physics runs on some frames only and everything waits in between (Frame Step), so walking, "
		.. "jumping, landing and coyote time are exactly like normal speed. The frames in between are drawn smoothly; things the kit's scripts move still move in "
		.. "steps." },
	{ "glide", "Glide Manipulation",
		"A glide: falling fast along a part with shift lock, strafing with A / D, your torso's vertical corner "
		.. "turned into the part's side. If the torso starts a physics step 0.1 - 0.2 studs inside the part, Roblox "
		.. "may push it out hard: your fall stops or slows and you are thrown outward, tilted.\n\n"
		.. "• Normally that is luck. With Glide Manipulation on, Glide Chance decides each part you hug.\n"
		.. "• 0 %: never glides. 100 %: always glides. In between: one roll per part.\n"
		.. "• Sinking into the wall again (falling fast again, or off the wall and back) glides again.\n"
		.. "• HappaTAS moves you by at most a few tenths of a stud.\n"
		.. "• Idle and recording, R6 characters." },
	{ "classiclook", "Classic interface",
		"Settings > Interface switches between the New and the Classic interface.\n\n"
		.. "Classic Look (Classic's Settings tab) sets Classic's colours and background:\n"
		.. "• Main Colour: every colour set to Auto follows it.\n"
		.. "• Each of the 23 colours has a row: type #RRGGBB or r, g, b, clear the box for Auto, or click the "
		.. "swatch for the picker.\n"
		.. "• Background: a picture link (downloaded once into HappaTasPort/Backgrounds: the only time HappaTAS "
		.. "uses the internet), a Roblox image id, or video: and a Roblox video id. Roblox can't play video files "
		.. "from links.\n"
		.. "• Background Transparency and Background Fit (Crop, Fit, Stretch)." },
	{ "settings", "Executor Port Settings",
		"• Ignore Game Processed: HappaTAS's keys work even when Roblox says the game used the key. The Menu key "
		.. "always works.\n"
		.. "• No HappaTAS key does anything while you type.\n"
		.. "• Settings and Controls are their own windows. A setting that isn't at its default has a reset arrow (←)." },
	{ "profiler", "MicroProfiler",
		"A copy of Roblox's MicroProfiler ({key:microProfiler}).\n\n"
		.. "• Time: the last frame. Avg: the average of every frame since the count started. Max: the biggest frame "
		.. "so far.\n"
		.. "• Aggregate Infinite counts the frames; picking it starts Avg and Max again.\n"
		.. "• Mode: Detailed, Timers, Counters, Frame, Hidden.\n"
		.. "• Custom > TAS Timeline shows your run (green = the current frame, click to jump there).\n"
		.. "• [Dump] saves the frames to the place's folder.\n"
		.. "• Pause or Ctrl+P freezes it. Hold Ctrl to click through it.\n"
		.. "• Hover a menu to open it, click a line to pick it." },
	{ "problems", "Common problems",
		"• Keys do nothing: you are typing in chat or a text box, or the Roblox menu is open.\n"
		.. "• The mouse is stuck in the middle: the camera is locked while paused. Hold Ctrl, or press Look Around "
		.. "{key:lookAround}.\n"
		.. "• Test doesn't press keys: keep the Roblox window focused.\n"
		.. "• The cursor moves too fast in NohBoard: lower NohBoard Mouse Speed.\n\n"
		.. "Known limits:\n"
		.. "• Other players don't follow the run.\n"
		.. "• In slow motion a push against a loose platform can start later (up to about 0.2 s of game time).\n"
		.. "• Kit listeners whose function the executor can't see keep real time.\n"
		.. "• Keep Sync Client Objects on for platforms you need exactly." },
	{ "missing", "Missing executor functions", "" },
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
