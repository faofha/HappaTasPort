# Memory for Claude (dzr)


- I go by **dzr**.
- I write Roblox scripts in Lua/Luau, mostly client-side scripts that run through a script executor
  (a TAS tool, an obby checkpoint tool). I'm into Roblox scripting, executor tooling, Lua and modding.
- I'm new to C# and .NET.
- Other interest: economics (in a Thai-language academic context).
- My setup: Windows x64, VS Code, PowerShell.
- I test Roblox on my Windows PC (Voidstrap launcher) and sometimes control it from my phone through a
  remote-desktop app (that's what my screenshots look like).

# How to work with me

- Explain things step by step, in a beginner-friendly way.
- Never say something was tested in a live Roblox game unless I have said directly that the Real MCP
  (the live game connection) is connected. Until then, test offline/headless and tell me that's what
  you did.
- For executor functions, use ONLY these sites:
  - https://docs.projectreal.gg
  - https://docs.potassium.pro/api-reference/introduction
  - https://sunc.su/

# My projects

- **HappaTAS executor port**: this repository (notes below).
- **Lua TAS script** and **obby checkpoint executor script**: see the end of this file.

---

# HappaTAS executor port

One client-side Luau script that records and replays TAS (tool-assisted speedrun) runs in Roblox.
It started as the HappaTAS .rbxm pair (an initializer that `require()`s an asset id + the MainModule
it loads). Everything, including the old server scripts, was moved into ONE local script that runs
through an executor.

- Latest script in this repo: **`wow`** = HappaTAS V2.36 (about 10,000 lines), built from `src/parts/`.
  Older files: `true`, `true real`, `nohboard` (V2.33, dzr's own versions), `HappaTAS_Executor-2.lua` (V2.32).
- Test game: **EToH Kit V6.1.3** (Eternal's Towers of Hell kit). Every "Continue" may be a new join.

## Rules from dzr (always follow)

1. Explain step by step, beginner-friendly.
2. Assume the **Real MCP is NOT connected** until dzr says directly that it is. Test offline/headless
   and say so; never claim in-game testing.
3. Executor function docs: ONLY https://docs.projectreal.gg ,
   https://docs.potassium.pro/api-reference/introduction and https://sunc.su/
4. Client objects (parts only the client sees, e.g. spinners) come ONLY from dzr's Tasability fork
   (tasability.lua) and must cover every client object in the EToH kit
   (docs https://etohgame.github.io/kit/, kit file UPDATE-KIT-v6_1_3.rbxm), optimized, opt-in setting.
5. No data limit (unlike the old DataStore version).

## Saving

- Root folder `HappaTasPort` in the executor workspace, one subfolder per PlaceId
  (`HappaTasPort/<PlaceId>/`). The UI lists only the current place's files.
- TAS files: compact binary `.tas` ("HTAS" header, LZ4 compressed, file format v3; v1/v2 still load).
- Settings: `HappaTasPort/Settings.json` (controls, settings and the MicroProfiler config + presets).
- MicroProfiler dumps: `microprofile-<date>-<time>.html` (or `.txt` legacy, `.csv` "binary") in the
  place folder.

## Default controls

Idle 1 · Create 2 · Test 3 · Pause/Unpause Left Click · Forward T · Back R · Forward 1 Frame G ·
Back 1 Frame F · Unpause 1 Frame V · Return E · Look Around L · Optimize TAS Q · Delete TAS Backspace ·
Menu M · MicroProfiler F6 (Ctrl+P pauses the profiler).

## What the script does (feature list)

- Records per frame: character state, camera, keyboard, mouse buttons, mouse wheel and mouse position
  (dzr's Tasability script tas-3.lua was the base for keyboard recording); replays them while testing.
- Client objects: only on-screen ones are saved ("Frustum Culling CO" setting); position, velocity and
  spin are stored so playback fills the gaps smoothly (Tasability-style "Smooth Client Objects"); their
  state is restored when pausing/unpausing at another time.
- Timed buttons (EToH kit v6.1.3): press state + timer saved per frame, timer frozen while paused.
- Camera zoom is saved per frame and restored; first-person recording works without an extra right
  click.
- NohBoard fix: in right click / shiftlock / first person a fake cursor image stays where the mouse was
  (Tasability's ArrowFarCursor 64x64 offset 4,4 and MouseLockedCursor 32x32 offset -16,-16) while the real
  hidden cursor moves with the camera; "Invisible Mouse Speed Multiplier" setting; no one-frame gap.
- Mobile: the DynamicThumbstick images (ThumbstickStart, ThumbstickEnd, 7x ThumbstickMiddle in
  PlayerGui.TouchGui.TouchControlFrame.DynamicThumbstickFrame) follow the TAS (position + transparency).
- Settings include: Ignore Game Processed, Show Completion Message (hide "TAS complete"), Sync / Smooth
  Client Objects, Replay Keyboard / Mouse, MicroProfiler Size, MicroProfiler Text Offset, sounds.
- Keyboard/click sounds, tool actions, death & respawn recording.

## MicroProfiler (V2.36): dzr's spec

A copy of Roblox's current desktop MicroProfiler, matched to dzr's screenshots.

- Look: Roboto Mono Bold with a 1 px black shadow, title "MicroProfiler", menus Mode, Groups,
  Aggregate, Timers, Options, Preset, Custom, [Dump], Flamegraphs, Pause, Help, Network, the frame
  tooltip and the X close box. Menus open on hover; a click on a line picks it.
- Readout `Time[ ] Avg[ ] Max[ ]`:
  - Time = the current frame's time.
  - Avg = the average of the frames visible on the bar (the last 508). The same whatever Aggregate is
    set to, and the same in Hidden mode.
  - Max = the biggest frame time; it stays until an even bigger frame comes (Aggregate doesn't matter).
- Aggregate set to Infinite shows the frame count: Aggregate[1], Aggregate[2], ... (picking Infinite
  restarts the count and resets Max).
- Mode Hidden works the same, just with the bar invisible.
- Every number must come from a documented source (dzr provides screenshots, Claude finds the data
  sources). Sources used: Roblox creator docs (Stats, RunService, TextLabel, UserInputService,
  GuiBase2d) and the microprofile source Roblox's profiler is built on (github.com/zeux/microprofile).
- Custom > TAS Timeline shows the TAS on the bar (green = current frame, click to jump there).

### Latest fixes (2026-10-13, still named V2.36)

- dzr reported: "The UI isn't clickable and the text is down by a little."
- Cause: Roblox measures GUI AbsolutePosition and InputObject.Position from the bottom of the top bar,
  but UserInputService:GetMouseLocation() from the top of the screen. The profiler mixed them, so the
  mouse looked about one top-bar height (~58 px) lower than it was.
- Fix: the pointer comes from input events (or GetMouseLocation() - GuiService:GetGuiInset()); all
  clicks, drags and wheel go through UserInputService. Click = release less than 3 px from the press
  (microprofile's rule); holding left on the graph keeps centring; right-click zooms to a frame.
- Text: moved up automatically from Roblox's measured font metrics (1 px or 3 px) + new setting
  **MicroProfiler Text Offset** (-6..6, minus = up).
- **Open:** waiting for dzr to check clicks and the text height in the real game (tested headless only).

## Code layout

The single file is assembled from parts, in this order:
p00_header, p01_env, p02_settings, p03_keys, p04_ui, p07_codec, p08_store, p09_bridge, p10_inputs,
p11_cursor, p12_anim, p13_clientobjects, p14_buttons, p15_tools, p16_sounds, p17_profiler, p18_core,
p19_menu, p20_start.

Conventions:
- No network code anywhere (no HttpGet / request / loadstring); Tasability's telemetry and
  remote-loading code are never copied.
- Every system is its own module with one job; settings live in one plain Lua table (SettingsTable).
- Conservative Luau syntax (no `+=`, `//`, backtick strings, `continue`, if-expressions).
- Luau allows 200 locals per function: the profiler is wrapped in `local function profilerModule()` and
  groups state into tables to stay under it.
- Debug logging only when `CONFIG.Debug = true`.

## Build and test (this repo)
- Edit the parts in `src/parts/`, never the built file by hand. Build: `bash tools/assemble.sh`
  (writes `src/HappaTAS_Executor.lua`; copy it out as the new release).
- Tests use a headless mock of the Roblox API (`tests/mock/`) and the `luau` CLI
  (https://github.com/luau-lang/luau/releases). Run one suite:
  `bash tools/build_test.sh profiler && cd tests && luau run_profiler.lua`
  Suites: smoke, profiler, core, scale, perf, textline. All passed for V2.36.
- The mock is not real Roblox: passing tests does not mean it works in game.

## Reference files from dzr

HappaTAS__READ_ME_.rbxm, MainModule.rbxm (original HappaTAS), UPDATE-KIT-v6_1_3.rbxm (EToH kit),
tas-3.lua and tasability.lua (dzr's Tasability scripts), true.txt (dzr's own later version of the
script, made with another AI plus dzr's edits, used as a base in an earlier round), and MicroProfiler
screenshots (21726.png, 21727-21740.jpg) plus IMG_20261012_165642.png (looks like the V2.35 profiler in game).

## History of requests (what dzr asked for, oldest first)

1. Turn the HappaTAS rbxm pair into one client-side executor script, saving to HappaTasPort/<PlaceId>/.
2. Add keyboard recording plus mouse (right click, mouse position); improve the steps; make TAS files
   more compact.
3. Setting to hide the "TAS completed" message; client objects from the Tasability fork (opt-in).
4. Fix camera zoom; fix buggy client objects (Pushing Platform, Rope Swing Platform) by saving their
   state every frame; NohBoard fake cursor; mobile thumbstick replay; Ignore GameProcessedEvent setting.
5. Save only on-screen client objects; character limbs lagging behind the root part during playback.
6. Spinning client objects: store position every few frames + spin speed, fill the gaps on playback.
7. "Invisible mouse speed multiplier" setting.
8. Work from dzr's own version (true.txt); merge Tasability smooth client objects with
   ClientObjects_v2.lua; fix timed buttons not saving, first-person recording needing a right click,
   and the fake cursor appearing one frame late.
9. Optimize and redesign V2.34 (became the V2.35 rebuild); add a MicroProfiler like Roblox's.
10. Earlier messages, word for word:
    - "Use only these websites to search for executor functions. https://docs.projectreal.gg
      https://docs.potassium.pro/api-reference/introduction https://sunc.su/."
    - "Add this to checklist, always assume you are not connected to the Real MCP until I say it
      directly."
11. V2.36 messages, word for word:
    - "This is very close to the original but right now Roblox uses another font and is very different
      from this. The aggregate when set to infinite doesn't go like Aggregate[Inf] it goes Aggregate[1]
      -> Aggregate[2] it just adds up every frame. I hope you know what I'm trying to say. And the right
      side when the time is the current frame time and avg is the average frame time that is currently
      in the bar thing (still the same if chose hidden) and max is the highest frame time (like lag spike
      that will stay there forever until there's an even bigger frame time) I will provide images of the
      recent microprofiler. Make sure to get sources of how to get those data and I will just provide
      images."
    - "What I mean is every aggregate in the frame time is the same if u choose infinite or not. If the
      frame thing is at the end of the frame show bar and it disappears it will only average the only
      frames that are on the bar and the biggest frame time stays there indefinitely if aggregate
      infinite or not. Average is the average of the frames that are visible on the bar. If chose mode
      hidden it will work like I said but with the bar invisible"
    - "The UI isn't clickable and the text is down by a little."

---

# Other projects

## Lua TAS script (Roblox, executor)

- A Lua TAS (tool-assisted speedrun) script for Roblox that records and plays back inputs, animations
  and game state, running in an executor.
- Requested: emote animation time-position tracking, with a new codec flag and delta-state recording.
- Requested: remove the AHKConnection system and use native `mousescroll()` calls instead.

## Obby checkpoint executor script (Roblox)

- An executor script for a specific obby game: checkpoint save/load, character freeze, teleport, and a
  settings menu with remappable keybinds.
- Goal: exactly the same as the original "Advanced Checkpoint System" .rbxm (GUI and scripts, with the
  server scripts ported to run client-side). dzr made it because nobody had an executor version.
- Past work on it: lots of debugging of scoping issues and missing functions, and rebuilding the UI from
  a G2L export.
- Open bug in optimized_script-5.lua: place a checkpoint in midair, stand on the ground, teleport to it,
  and you can still jump during coyote time.

## Other past work

- Deobfuscated a Lua script that used XOR-with-key decoding (understood the obfuscation pattern).
- Looked at a Roblox Studio boss-fight project with a custom A* pathfinder; the silent failure came from a
  missing `Grid` folder in workspace that the pathfinder needed.
