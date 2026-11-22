-- ================================================================================================
--  UPDATE LOG  (HappaTAS 3 ui, V3.1): every version, newest first, as { heading, bullets } (V2's update log
--  form: " date - version", "   -   line"). V3.1 and V3.0 on top; below them V2.38.17's log word for word,
--  generated from src/parts/p04_ui.lua on branch v2.38.17-humanoid-clock (its 3UpdateLog rows in name order:
--  39 versions, 167 lines; never edited by hand). The About window, Classic's More page and Compact's ABOUT
--  tab all show this list.
-- ================================================================================================
local UpdateLog = {}

UpdateLog.ENTRIES = {
	{ heading = " 11/22/26 - V3.1", bullets = {
		"   -   Compact: a third interface, inspired by Tasability",
		"   -   About window: version, credits and the update log",
		"   -   Help rewritten in short sections; credits out of Help",
		"   -   A new colour picker: one box, quick and recent colours",
		"   -   Green default colours for the New interface",
		"   -   One Sync Client Objects switch; fewer settings",
		"   -   NohBoard Mouse Speed (was Invisible Mouse Speed)",
		"   -   Face fades with the character when zoomed all the way in",
		"   -   Zooming keeps its smooth move through a pause",
		"   -   Dragging the timeline never locks the mouse",
		"   -   Speed slider: one message, knob inside the track",
		"   -   Long text on Classic's More page wraps, never cut off",
		"   -   Speed hack: exact slow motion, no lag after jumps",
		"   -   Smooth Slow Motion: the frames between physics steps",
		"   -   Speed Hack In: pick Idle and / or Create",
		"   -   Speed hack capped at 1x, fast motion removed",
		"   -   Shift lock works in slow motion",
		"   -   Glide Manipulation: decide side-edge glides",
		"   -   Right click held while paused keeps the camera",
		"   -   Classic Look: colours, picker and background",
		"   -   Glide settings and choice boxes in Classic",
		"   -   Smaller TAS files; Classic on phones",
		"   -   The Inspector updates every frame",
		"   -   Keep Mouse Position (Paused); interface sounds",
		"   -   The full update log, back to 2.01",
	} },
	{ heading = " 11/02/26 - V3.0", bullets = {
		"   -   A new interface: Dock, windows, timeline bar, Inspector",
		"   -   Classic interface: Settings > Interface",
		"   -   Library: folders, search, sort, numbered attempts",
		"   -   File format v6: smaller files, safe saving",
		"   -   Old .tas files (v1-v5) and Settings.json carry over",
		"   -   Smaller files and faster saving, a clean Unload",
		"   -   Touch buttons and thumbstick replay on phones",
		"   -   The MicroProfiler on the new engine",
	} },
	{ heading = " 10/25/26 - 2.38.17", bullets = {
		"   -   Sounds removed (keyboard / click sounds)",
		"   -   Keys replayed with keypress / keyrelease only",
		"   -   Speed Hack: walking, turning, jumps and gravity on the TAS clock",
		"   -   Speed Hack: coyote time as at normal speed",
		"   -   Coyote time kept across a pause",
	} },
	{ heading = " 10/18/26 - 2.38.16", bullets = {
		"   -   Speed Hack: speeds above 1 (fast motion, up to 4x)",
		"   -   Speed Hack Frame Step: normal physics in slow motion",
		"   -   Zoom plays back at normal speed after slow / fast motion",
		"   -   Bounce pad / jump launcher effects shown when testing",
		"   -   Zipline and Sequencer follow the TAS clock",
		"   -   Camera script patches work again (zoom, mouse)",
	} },
	{ heading = " 10/18/26 - 2.38.15", bullets = {
		"   -   Speed Hack: bounce pads bounce as high as at normal speed",
		"   -   Client objects saved from their start: morphs show up",
		"   -   before their button is pressed when testing",
	} },
	{ heading = " 10/18/26 - 2.38.14", bullets = {
		"   -   Kit scripts on the TAS clock: pause / slow motion stop them",
		"   -   Jump launcher push no longer cut short by a pause",
		"   -   Beat blocks follow the TAS time (same beat in playback)",
		"   -   Turret bullets saved in the TAS, hits and damage replayed",
		"   -   Pushboxes hidden on frames before they were spawned",
		"   -   Speed Hack slows spinners, platforms, conveyors too",
		"   -   Idle (1) leaves the lighting as it is",
	} },
	{ heading = " 10/17/26 - 2.38.13", bullets = {
		"   -   Speed Hack: slow motion while recording (Settings)",
		"   -   Slow recordings are saved and tested at normal speed",
		"   -   Client objects on their own clocks: smaller files",
		"   -   240 FPS: frames without physics are no longer dropped",
		"   -   Camera calls no longer break the interface when paused",
	} },
	{ heading = " 10/17/26 - 2.38.12", bullets = {
		"   -   Synced exact button timer decimal places (e.g. 0.90) from live game UI & configs",
	} },
	{ heading = " 10/17/26 - 2.38.11", bullets = {
		"   -   Eliminated lag with many buttons (event-indexed seek & cached scans)",
		"   -   Fixed shiftlock cursor & mouse lock state after Test replay ends",
		"   -   Fixed first-person zoom resetting to Frame 1 zoom after Test ends",
		"   -   Synced part timer SurfaceGui/BillboardGui with top screen timer UI",
	} },
	{ heading = " 10/16/26 - 2.38.10", bullets = {
		"   -   Create mode rewind fix: buttons un-glow & reset before press",
		"   -   Locked mouse cursor in FP & shiftlock while paused/rewinding",
		"   -   Cloned EToH v6.1.3 timer UI with UIStroke & zero duplicates",
		"   -   Paused/unpaused button lock: no timer restart when near end",
		"   -   Fixed first-person character body visibility (Test -> Create)",
		"   -   FPS boost: event-driven lighting & CO props, cached CFrames",
		"   -   Smaller files & lower RAM: compact v2/v3 encoding & table reuse",
	} },
	{ heading = " 10/16/26 - 2.38.9", bullets = {
		"   -   3-digit number and Digits/NeedDigits part property support",
		"   -   Duplicate timer prevention: re-touching after rewind starts 1 clean timer",
		"   -   Matched timer sizing: restored timers dynamically match other timers' size",
	} },
	{ heading = " 10/16/26 - 2.38.8", bullets = {
		"   -   Top screen timer UI direct sync & restoration across all ScreenGuis",
		"   -   Screen countdown freezes strictly on pause without advancing",
		"   -   Scrubbing backwards accurately restores and reverses top timer UI",
		"   -   ModuleScript & Attribute config support for EToH kits",
	} },
	{ heading = " 10/16/26 - 2.38.7", bullets = {
		"   -   Timed buttons: PlayerGui EffectGui.TimerList synchronized",
		"   -   Screen timer freezes while paused and follows TAS frame scrubbing",
		"   -   Fixed stale index cache preventing newly recorded button presses",
		"   -   ModuleScript & Attribute config support for EToH kits",
		"   -   Infinite restart loop suppressed via pause debounce",
	} },
	{ heading = " 10/16/26 - 2.38.6", bullets = {
		"   -   EToH kit v6 Lighting Changers: all properties and effects synced",
		"   -   Lighting timeline trimming fixes corrupted scrub/rewind searches",
		"   -   Timed buttons: stopped infinite restart loop when paused",
		"   -   Button timer UI locked at RenderPriority.Last to prevent overrides",
		"   -   Vanishers (fading platforms): tracked, paused, and restored",
	} },
	{ heading = " 10/16/26 - 2.38.5", bullets = {
		"   -   Timed buttons fixed: timer freezes while paused, reverses cleanly",
		"   -   EToH Kit v6.1.3 button detection for Configurations & models",
		"   -   Beat Blocks synced and frozen while paused without script overrides",
		"   -   Morph buttons and morphing part (Base) shape/size tracked",
		"   -   Lighting Changers: game.Lighting properties & effects synced",
	} },
	{ heading = " 10/14/26 - 2.38.4", bullets = {
		"   -   MicroProfiler Avg = every frame since the count started",
		"   -   Picking Aggregate Infinite starts Avg and Max again",
		"   -   TAS Timeline: Avg / Max from the TAS's first frame",
	} },
	{ heading = " 10/14/26 - 2.38.3", bullets = {
		"   -   Camera script hooked in place (hookfunction)",
		"   -   No visible PlayerGui interface unless you allow it",
	} },
	{ heading = " 10/14/26 - 2.38.2", bullets = {
		"   -   Every Real executor function checked for HappaTAS",
		"   -   Arrow keys, Home, End, PgUp/PgDn, right Ctrl/Alt fixed",
		"   -   Mouse replay within 1 px (Real's moves were up to 11 off)",
		"   -   Mouse moves no longer arrive one move late",
		"   -   Held keys pressed again when Roblox gets focus back",
		"   -   Camera scripts found with filtergc, no full memory scan",
	} },
	{ heading = " 10/14/26 - 2.38.1", bullets = {
		"   -   Frame colours checked against Roblox's own profiler",
		"   -   Render time taken from the right frame (exact)",
		"   -   Same bars as Roblox's: 501 of 503 the same colour",
		"   -   Frame tooltip rows like Roblox's (GPU Time added)",
	} },
	{ heading = " 10/14/26 - 2.38", bullets = {
		"   -   MicroProfiler compared side by side with Roblox's",
		"   -   Close box turns grey under the mouse, hint box",
		"   -   Hold Ctrl to click through; [Dump] box like Roblox's",
		"   -   Orange = jobs longer, blue = render longer",
		"   -   Frame graph is one image: far less render time",
		"   -   Detailed lanes, Timers tooltip, Counters layout",
		"   -   Drawn above Roblox's top bar",
	} },
	{ heading = " 10/13/26 - 2.37.2", bullets = {
		"   -   Tested in the real Roblox client, the bugs found fixed",
		"   -   Interface always loads, also when re-running the script",
		"   -   Client objects stay put when the game un-anchors them",
		"   -   Rebinding a key doesn't also run the old control",
		"   -   Replayed keys play their sound once, errors print once",
		"   -   2-5x less CPU per frame (auto-translate off, less work)",
		"   -   Click sound plays (its old sound id was not a sound)",
	} },
	{ heading = " 10/13/26 - 2.37.1", bullets = {
		"   -   Menu key works even when the game used the key",
		"   -   Keys do nothing while typing in chat or a text box",
		"   -   Clicks on the HappaTAS menu never pause / unpause",
	} },
	{ heading = " 10/13/26 - 2.37", bullets = {
		"   -   Client objects: change signals, far fewer engine calls",
		"   -   Stats panel and playback do less work every frame",
		"   -   Smaller script: compact interface data, shared code",
		"   -   Same TAS files and behaviour as 2.36",
	} },
	{ heading = " 10/12/26 - 2.36", bullets = {
		"   -   MicroProfiler font, menus and tooltip match Roblox",
		"   -   Avg = frames on the bar, Max keeps the biggest spike",
		"   -   Detailed, Timers, Counters modes and a flame graph",
		"   -   MicroProfiler Size setting, dumps as HTML/text/CSV",
		"   -   MicroProfiler clicks fixed, text sits like Roblox's",
	} },
	{ heading = " 10/12/26 - 2.35 (Rebuild)", bullets = {
		"   -   Timed buttons saved, timer frozen while paused",
		"   -   First person camera works right after unpausing",
		"   -   Fake cursor shows up on the same frame (no gap)",
		"   -   Smooth client objects, in sync with the character",
		"   -   New MicroProfiler (Roblox look, real timings, F6)",
		"   -   File v3: saves viewport, tools, deaths, buttons",
		"   -   Settings grouped by topic, faster settings reads",
		"   -   Fixes: sounds, window guarding, unload, zoom",
		"   -   Lower CPU cost per frame while recording and testing",
	} },
	{ heading = " 10/12/26 - 2.34 (Master Engine Update)", bullets = {
		"   -   Official Roblox MicroProfiler replica (Ctrl+F6) with live TAS sync, Aggregate modes & scrubbing",
		"   -   Custom mechanical keyboard & click sound engine with dynamic pitch modulation",
		"   -   Client Object sync overhaul with EToH Kit v6.1.3 & 25-stud frustum culling",
		"   -   Button Timer & Obby Mechanism Sync (countdown doors & pressure plates)",
		"   -   Humanoid Death & Respawn recording across character respawns",
		"   -   Tool equip, unequip, activate, and deactivate recording & playback",
		"   -   Modern executor sandboxing (cloneref, gethui, syn.protect_gui, native LZ4)",
		"   -   Settings UI alignment fix and Help page documentation overhaul",
	} },
	{ heading = " 10/10/26 - 2.33.1", bullets = {
		"   -   Mobile DynamicThumbstick middle tracking position & size",
		"   -   Fixed first-person camera lock during pause and unpause",
		"   -   Sub-pixel cursor UV normalization for cross-resolution aiming",
	} },
	{ heading = " 07/03/26 - 2.33", bullets = {
		"   -   Fixed camera zoom, NohBoard mouse, and client objects",
	} },
	{ heading = " 10/11/25 - 2.31", bullets = {
		"   -   Emotes 😛",
		"   -   Animation fixes (PLEASE dont be bad)",
		"   -   Fixed coyote frame abuse",
	} },
	{ heading = " 9/19/25 - 2.3", bullets = {
		"   -   GUI Redesign/recolor",
		"   -   Public Save Slots",
		"   -   Merge TAS (refer to help)",
		"   -   Interpolate Playback Setting (refer to help)",
		"   -   Fixed save slot order/IDs (new slots only)",
		"   -   Update to character animations",
		"   -   Renamed \"Spectate\" mode to \"Idle\"",
		"   -   Fixed TAS not loading in studio (must update HappaTAS loader)",
	} },
	{ heading = " 9/16/25 - 2.23.1", bullets = {
		"   -   Fixed saving and loading crashing (i think)",
	} },
	{ heading = " 1/11/23 - 2.23", bullets = {
		"   -   Patched boosted bounce (lied last time)",
		"   -   Fixed repeating slot IDs",
		"   -   Small adjustments/fixes for quality of life",
	} },
	{ heading = " 1/2/23 - 2.22", bullets = {
		"   -   Patched physics bugs and cheats",
		"   -   Fixed animations (not fake at all)",
	} },
	{ heading = " 12/14/22 - 2.21", bullets = {
		"   -   Data limit removed  : }",
		"   -   Better animations (real)",
		"   -   Fixed a couple TAS breaking bugs",
	} },
	{ heading = " 11/5/22 - 2.2", bullets = {
		"  -  Mobile support",
		"  -  Playback speed controller",
		"  -  Replay matches the timer of recording (no FPS/lag abuse)",
		"  -  Fixes to animations, camera, and player transparency",
		"  -  Patched physics bug \"super bounce\"",
		"  -  Discord Server (link in description of main game)",
	} },
	{ heading = " 7/25/22 - 2.1", bullets = {
		"  -  Added Help menu",
		"  -  A couple minor bug fixes",
	} },
	{ heading = " 7/25/22 - 2.05", bullets = {
		"  -  Save/Load is a lot faster now",
		"  -  Fixed getting kicked by saving large files",
		"  -  Max slots increased",
		"  -  Unpause 1 works on any humanoid state except \"Landed\"",
		"  -  New setting 'Stats Text Size'",
	} },
	{ heading = " 7/24/22 - 2.04", bullets = {
		"  -  New Setting 'Restart When Testing'",
		"  -  New Control 'Look Around' while paused with camera lock ",
		"  -  Fixed animations",
		"  -  Fixed transparency when testing",
	} },
	{ heading = " 7/21/22 - 2.03", bullets = {
		"  -  Timers now show in minutes and seconds",
		"  -  Message on the bottom when the TAS playback is complete",
		"  -  You can see others move while they are testing",
		"  -  Removed manually toggling shiftlock while in test",
	} },
	{ heading = " 7/16/22 - 2.02", bullets = {
		"  -  Fixed issue with the shiftlock cursor",
		"  -  Fixed issue with the \"Delete\" keybind",
		"  -  Fixed timer skipping forward after TAS is optimized",
	} },
	{ heading = " 7/14/22 - 2.01", bullets = {
		"  -  Script still usable in studio when API services are turned off",
	} },
}

-- the whole log as text: each heading, then its lines
function UpdateLog.text()
	local out = {}
	for _, e in ipairs(UpdateLog.ENTRIES) do
		out[#out + 1] = e.heading
		for _, b in ipairs(e.bullets) do out[#out + 1] = b end
	end
	return table.concat(out, "\n")
end

return UpdateLog
