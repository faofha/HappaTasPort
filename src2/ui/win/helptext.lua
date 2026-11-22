-- ================================================================================================
--  HELP TEXT  (HappaTAS 3 ui): the Help topics, in V2.38.17's friendly style, a control at a time (every V2.38.17 help
--  topic has a home here: its title, or named in a body). topics(E) -> { { id, title, body } }; a body's
--  {key:<control>} becomes the control's key as bound now, in brackets. "missing" lists Env.notes. Text uses
--  only characters every listed font has (ASCII and × ▼ ← … •). The credits and what's new aren't Help
--  topics: the About window and Classic's More page show them (the credits here, the log in ui/updatelog).
-- ================================================================================================
local Env = import("platform/env")

local HelpText = {}

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
		"The controls in this tool let you create a TAS and replay it in game. Start at the top of the topics and "
		.. "work your way down to see how it works. If you don't like the preset keys, you can change them in "
		.. "Controls.\n\n"
		.. "1. Press {key:create} for Create. You start paused, so nothing is recorded yet.\n"
		.. "2. Press {key:unpause} to start recording, and {key:pause} to pause again.\n"
		.. "3. Messed up a jump? Go back to before it, then unpause and record over it.\n"
		.. "4. Press {key:test} to watch your TAS play.\n"
		.. "5. Save it in the Library so you can load it later.\n\n"
		.. "{key:menu} hides or shows the interface. In the New interface the Dock at the top opens the windows; "
		.. "Tasability has one window with tabs.\n\n"
		.. "If you used V2, its settings and keys were brought over on the first start. Want to bring them over "
		.. "again? You need to unload HappaTAS first (Unload HappaTAS below the topics, or rejoin), then delete "
		.. "HappaTasPort/Settings3.json, then run the script. That also resets the look, the windows and which "
		.. "interface you use." },
	{ "modes", "Idle, Create and Test",
		"Idle {key:idle}: the default mode. Switching to Idle leaves everything TAS related, so you can play the "
		.. "obby like normal. Your TAS stays, so you can still save it, test it or go back to Create.\n\n"
		.. "Create {key:create}: switches you to create mode and pauses you, so you can start recording your TAS. "
		.. "You start on its last frame, or at the start if it's a new TAS. While you are paused nothing moves: your "
		.. "character, the camera, client objects and the kit's timers all wait for you.\n\n"
		.. "Test {key:test}: plays the TAS you created. Just sit back, relax, and feel free to flex on your friends as "
		.. "you watch your character go." },
	{ "pause", "Pause and Unpause",
		"Unpause {key:unpause}: can be pressed while you are paused in create mode. Once you unpause, the TAS starts "
		.. "recording from the frame you are on. Anything you do shows up in your TAS, and everything after that "
		.. "frame is recorded over.\n\n"
		.. "Pause {key:pause}: can be pressed while recording. Once you pause, the TAS stops recording. While paused, "
		.. "you can use the other controls to remove the parts of the TAS you don't want.\n\n"
		.. "Good to know: a coyote jump you had before pausing is kept. If you unpause on the frame you jump off a "
		.. "ladder, you are unpaused a frame earlier." },
	{ "time", "Moving through your TAS",
		"Back/Forward ({key:back} / {key:forward}): hold them to move back and forward in time. Use them to go back if "
		.. "you mess up a jump or want to be faster. They pause you if you are recording, and when you unpause you "
		.. "carry on from where you moved to.\n\n"
		.. "Back/Forward 1 Frame ({key:back1} / {key:forward1}): the same, but one frame per press. Holding them does "
		.. "nothing extra.\n\n"
		.. "Return {key:return}: brings you back to the last frame you unpaused at. Pressing it while recording pauses "
		.. "you first.\n\n"
		.. "Unpause 1 Frame {key:unpause1}: records exactly one frame and pauses again. Right after a landing or a "
		.. "ladder jump it records two.\n\n"
		.. "You can also drag the playhead on the timeline bar while paused.\n\n"
		.. "Optimize TAS {key:optimize}: want your TAS to be quicker? Use it in Idle and the still frames are "
		.. "removed (frames where nothing moved, the camera stayed put and no new animation started).\n\n"
		.. "Delete TAS {key:deleteTas}: RIP all your hard work :( Save it first if you want to keep it." },
	{ "test", "Watching your TAS (Test)",
		"These settings change how Test plays your TAS back.\n\n"
		.. "Playback Speed: how fast your TAS plays in Test. At any speed other than 1 the Inspector always shows its "
		.. "Frame section.\n\n"
		.. "Restart When Testing: on, Test always starts from frame 1. Turn it off to start from the frame you are "
		.. "on, handy when you only want to watch the end.\n\n"
		.. "Interpolate Playback (on by default): your character is placed between two recorded frames, so playback "
		.. "looks smooth at any frame rate. Off, it plays one recorded frame at a time.\n\n"
		.. "Show Completion Message: tells you when your TAS has finished playing." },
	{ "camera", "The camera",
		"Lock Camera (Mode): whether you can move the camera in that mode. Lock Camera (Paused) keeps the camera on "
		.. "the recorded frame while you are paused, and Lock Camera (Test) follows the recorded camera while "
		.. "testing.\n\n"
		.. "Look Around {key:lookAround}: while paused with the camera locked, this unlocks it so you can look around. "
		.. "Press it again to lock it. If you unpause while looking around, the camera goes back to where it should "
		.. "be by itself.\n\n"
		.. "Want to turn the camera between frames? Turn Lock Camera (Paused) off.\n\n"
		.. "In shift lock or first person the mouse stays locked, even with a window open. Hold Ctrl to use the "
		.. "windows.\n\n"
		.. "Your zoom and shift lock are saved with every frame." },
	{ "bar", "Timeline bar",
		"The bar at the bottom shows your TAS while you are in Create and Test.\n\n"
		.. "On the left you see the mode and the speed. In the middle are buttons for: go to the start, back one "
		.. "frame, record / pause, forward one frame, Test and marker. On the right, a dot shows your TAS has unsaved "
		.. "changes, then the frame and the time.\n\n"
		.. "Drag on the bar while paused to jump to a frame, or while testing to scrub through. The mouse wheel "
		.. "zooms in and out. The marker button marks the frame you are on (it's saved with your TAS). ▼ opens the "
		.. "lanes: deaths, states and tools, inputs, the kit's events and buttons." },
	{ "inspector", "Inspector",
		"The Inspector shows the numbers of the frame you are on, split into sections: Frame, Character, Camera & "
		.. "input, World and Performance.\n\n"
		.. "While paused it shows the recorded frame, while recording the newest one, in Test the playback and in "
		.. "Idle your character right now.\n\n"
		.. "Pin a row (•) to keep it at the top, hide one (×), or fold a section you don't need.\n\n"
		.. "Show Stats (Mode) (Idle / Create / Test): whether it shows values in that mode. Stats Text Size sets "
		.. "how big they are.\n\n"
		.. "It never takes the mouse away from the game." },
	{ "library", "Library: Saving and Loading",
		"Saving and Loading happen in the Library.\n\n"
		.. "Each TAS is a .tas file in HappaTasPort/<PlaceId>/ in your executor's workspace, and you only see the "
		.. "ones for the place you are in. There is no size or count limit.\n\n"
		.. "To save, type a name and press Save. If that name is taken, it asks before saving over it. New attempt "
		.. "saves \"Name (2)\", \"Name (3)\" and so on, folded under the first one in the list.\n\n"
		.. "You can make folders (three levels deep), search, sort, Rename, Move to and Delete (it asks twice, just "
		.. "in case).\n\n"
		.. "You can't save while recording, or load while testing. Old .tas files still load." },
	{ "merge", "Merging a TAS",
		"Merging joins your TAS to one you saved before.\n\n"
		.. "1. Pick a saved TAS in the Library and press Merge.\n"
		.. "2. Choose Before or After. Before only works if its last frame is on the ground (Running); After only if "
		.. "its first frame is.\n"
		.. "3. Record the part in between: from the red box (where the TAS before ends) to the green box (where the "
		.. "TAS after starts).\n"
		.. "4. The Merge window shows how far away you are and how close you need to be. Press Complete merge once "
		.. "you are close enough, or Cancel merge.\n\n"
		.. "Closing the window cancels the merge too." },
	{ "inputs", "Keyboard and Mouse Inputs",
		"Your keys, mouse buttons, mouse wheel and mouse position are saved with every frame, and Test presses them "
		.. "again through the executor (keypress, mouse1press, mouse2press, mousemoveabs, mousescroll).\n\n"
		.. "Keep the Roblox window focused while it plays, and keep your hands off. Window Guarding stops the replayed "
		.. "input while the window isn't focused.\n\n"
		.. "HappaTAS's own keys are never recorded, and nothing happens while you type in chat or a text box.\n\n"
		.. "Replay Keyboard, Replay Mouse Clicks and Replay Mouse Movement turn each part off if you don't want it.\n\n"
		.. "The cursor is saved as a fraction of the screen, so your TAS aims the same at another window size.\n\n"
		.. "NohBoard Cursor draws a still cursor while the camera is locked (right click, shift lock, first person). "
		.. "NohBoard Mouse Speed (at most 1) sets how fast the hidden cursor moves.\n\n"
		.. "Keep Mouse Position (Paused) shows a see-through cursor where the mouse was on the frame you are on, and "
		.. "puts the mouse back there when you unpause.\n\n"
		.. "Holding right click while paused keeps the cursor locked like in the game, so unpausing with it held "
		.. "doesn't turn the camera.\n\n"
		.. "Chat: what you type in the chat bar while recording is saved with your TAS, letter by letter. Test "
		.. "types it into the chat bar again on the same frames and sends it, so a command like /e dance2 makes you "
		.. "dance again.\n\nA normal message is really sent again every time, so other players see it. Replay Chat "
		.. "turns it off. It works with Roblox's current chat only." },
	{ "world", "Client Objects and the world",
		"Sync Client Objects (on by default) is one switch for everything besides your character that follows your "
		.. "TAS.\n\n"
		.. "Client Objects: parts only your game moves, like moving, falling and swinging platforms, pushboxes, "
		.. "vanishers and morphs. They are saved with your TAS, put back while testing and scrubbing, and smooth at "
		.. "any frame rate. Only the ones on screen or within 25 studs are kept, so files stay small.\n\n"
		.. "Button & Obby Mechanism Sync: the EToH kit's buttons and timers (timed switches, pressure plates, "
		.. "countdown doors, disappearing parts) are saved with every press. While paused, the timers wait.\n\n"
		.. "EToH Kit Objects: the kit's own timers follow your TAS's clock. Beat blocks follow its time, turret "
		.. "bullets are saved with their hits, pushboxes stay hidden until they spawn, and bounce pad and launcher "
		.. "effects play again in Test.\n\n"
		.. "Lighting changes are kept with your TAS too.\n\n"
		.. "Death & Respawn Recording (Record Death & Respawn): your TAS can go through deaths, and playback carries "
		.. "on with the new character.\n\n"
		.. "Tool Actions Support (Record Tool Actions): equipping, unequipping and using tools. If a tool isn't there "
		.. "during playback, it's skipped." },
	{ "speed", "Speed Hack (Slow Motion)",
		"The speed hack slows the game down while you record, like playing a video slower. Test still plays your "
		.. "TAS at normal speed.\n\n"
		.. "Speed Hack turns it on, and Speed Hack Speed sets how slow (0.1 to 1).\n\n"
		.. "Toggle Speed Hack {key:toggleSpeedHack} switches it on and off while recording (bind it in Controls first).\n\n"
		.. "Speed Hack In: where it works, Create (recording, the default) and / or Idle (nothing is saved there).\n\n"
		.. "Gravity, walking, jumping, animations, the zoom and the world (spinners, platforms, swings, conveyors, "
		.. "bounce pads, ziplines, the kit's timers) all slow down with it.\n\n"
		.. "Roblox's physics only runs on some frames and everything waits in between (Frame Step), so walking, "
		.. "jumping, landing and coyote time feel exactly like normal speed. The frames in between are drawn "
		.. "smoothly, but things the kit's scripts move still move in steps." },
	{ "glide", "Glide Manipulation",
		"A glide happens when you fall fast along a part in shift lock, strafing with A / D, with your torso's "
		.. "corner turned into the part's side. If the torso starts a physics step 0.1 - 0.2 studs inside the part, "
		.. "Roblox may push it out hard: your fall stops or slows and you get thrown outward, tilted.\n\n"
		.. "Normally that's down to luck. With Glide Manipulation on, Glide Chance decides it for each part you hug: "
		.. "0 % never glides, 100 % always glides, and anything in between rolls once per part.\n\n"
		.. "Sinking into the wall again (falling fast again, or leaving the wall and coming back) can glide again.\n\n"
		.. "HappaTAS only moves you by a few tenths of a stud at most. It works in Idle and while recording, with R6 "
		.. "characters." },
	{ "classiclook", "Classic interface",
		"Settings > Interface switches between the New, the Classic and the Tasability interface.\n\n"
		.. "Classic Look (in Classic's Settings tab) sets Classic's colours and background.\n\n"
		.. "Main Colour: every colour set to Auto follows it.\n\n"
		.. "Each of the 23 colours has its own row: type #RRGGBB or r, g, b, clear the box for Auto, or click the "
		.. "swatch to open the picker.\n\n"
		.. "Background: a picture link (downloaded once into HappaTasPort/Backgrounds, the only time HappaTAS uses "
		.. "the internet), a Roblox image id, or video: and a Roblox video id. Roblox can't play video files from "
		.. "links.\n\n"
		.. "Background Transparency and Background Fit (Crop, Fit, Stretch) set how it looks." },
	{ "compact", "Tasability interface",
		"Everything in one window. Pick it in Settings > Interface (not on phones).\n\n"
		.. "Drag the title bar to move the window, and the corner grip to resize it. The title bar shows the "
		.. "version, the mode (and whether you are paused or recording), a search box that finds settings, and "
		.. "minimise (_), which folds the window down to its title bar.\n\n"
		.. "The tabs: CONTROLS (your TAS, the speed hack, your keys, the MicroProfiler and Unload), SETTINGS, HELP "
		.. "and ABOUT. LIBRARY opens your saved TAS files on the left, INSPECTOR the frame's numbers on the right.\n\n"
		.. "In SETTINGS, tick a box to turn a setting on, type a number and press Enter, pick from a list (▼), or "
		.. "click a colour's swatch for the picker. RESET puts a section back to its defaults. Hover a row to read "
		.. "what it does.\n\n"
		.. "In KEYS (on CONTROLS), click a key box and press the new key (Esc cancels), × clears it, and Reset all "
		.. "puts every key back. Two actions on one key are marked; hover one to see the other.\n\n"
		.. "It uses your accent colour, text colours and text size. The New interface's glass, fonts, corners and "
		.. "animations don't apply here. The timeline bar, messages and the Merge window are the same as in New." },
	{ "settings", "Executor Port Settings",
		"Ignore Game Processed: HappaTAS's keys work even when Roblox says the game already used the key. The Menu "
		.. "key always works.\n\n"
		.. "No HappaTAS key does anything while you are typing.\n\n"
		.. "In the New interface, Settings and Controls are their own windows; Tasability has them as tabs. A "
		.. "setting that isn't at its default has a reset arrow (←).\n\n"
		.. "A colour swatch opens the colour picker: drag the square and the hue bar, type #RRGGBB or r, g, b, or "
		.. "pick a quick or recent colour. You see the colour while you pick. Cancel puts the old one back, and "
		.. "Reset to default sets the default." },
	{ "profiler", "MicroProfiler",
		"A copy of Roblox's MicroProfiler ({key:microProfiler}).\n\n"
		.. "Time is the last frame, Avg the average of every frame since the count started, and Max the biggest "
		.. "frame so far.\n\n"
		.. "Aggregate Infinite counts the frames, and picking it starts Avg and Max again.\n\n"
		.. "Mode: Detailed, Timers, Counters, Frame or Hidden.\n\n"
		.. "Custom > TAS Timeline shows your TAS on the bar (green is the frame you are on, click to jump there).\n\n"
		.. "[Dump] saves the frames into the place's folder.\n\n"
		.. "Pause or Ctrl+P freezes it, and holding Ctrl lets you click through it. Hover a menu to open it and click "
		.. "a line to pick it." },
	{ "problems", "Common problems",
		"Keys do nothing? You are probably typing in chat or a text box, or the Roblox menu is open.\n\n"
		.. "The mouse is stuck in the middle? The camera is locked while you are paused. Hold Ctrl, or press Look "
		.. "Around {key:lookAround}.\n\n"
		.. "Test doesn't press keys? Keep the Roblox window focused.\n\n"
		.. "The cursor moves too fast in NohBoard? Lower NohBoard Mouse Speed.\n\n"
		.. "Known limits:\n"
		.. "• Other players don't follow your TAS.\n"
		.. "• In slow motion, a push against a loose platform can start a little later (up to about 0.2 s of game "
		.. "time).\n"
		.. "• Kit listeners the executor can't see keep real time.\n"
		.. "• Keep Sync Client Objects on for platforms you need to be exact.\n\n"
		.. "Have fun :)" },
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
