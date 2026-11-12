# HappaTasPort

HappaTAS as **one client-side Luau script** for Roblox executors. It records and replays TAS
(tool-assisted speedrun) runs frame by frame and saves them as compact `.tas` files in
`<executor workspace>/HappaTasPort/<PlaceId>/`.

**Latest version: HappaTAS 3.0.0**, a rewrite from scratch of HappaTAS V2.38.17 with a new interface, a
library for your runs and smaller files that save faster. Every V2 feature stays, and your old runs and settings
carry over.
No network code.

Run `wow` (or `wow1`, the same file) in your executor.

## Quick start

1. Run the contents of `wow` in your executor while you are in the game. Real is the executor it is made
   for; other executors with the sUNC functions mostly work (Help > Missing executor functions lists what yours lacks).
2. Press `2` (Create). Left click unpauses and pauses: you record while it is unpaused.
3. While paused, `F` / `G` step one frame back / forward, `R` / `T` hold back / forward. Unpausing on an
   earlier frame cuts the frames after it.
4. Press `3` (Test) to play the run back, `1` (Idle) to stop.
5. The Dock at the top opens the windows (Inspector, Library, Settings, Controls, Help); `M` hides or shows
   the whole interface.

## Default controls (all can be changed in the Controls window)

| Action | Key |
| --- | --- |
| Idle | 1 |
| Create | 2 |
| Test | 3 |
| Pause | Left Click |
| Unpause | Left Click |
| Forward | T |
| Back | R |
| Forward 1 Frame | G |
| Back 1 Frame | F |
| Unpause 1 Frame | V |
| Return | E |
| Look Around | L |
| Optimize TAS | Q |
| Delete TAS | Backspace |
| Menu | M |
| MicroProfiler | F6 |
| Toggle Speed Hack | none |

Forward / Back are held; Ctrl+P pauses the MicroProfiler. No HappaTAS key does anything while you type in
chat or a text box.

## Two interfaces

- **New** (the default): the Dock, windows you can move, resize and minimise, a timeline bar at the
  bottom with markers, and the Inspector with the live numbers of the character, camera and frame. The look
  can be changed far more than V2's: theme, glass (Frost blurs the game behind a window at high graphics
  quality), colours, fonts, text size, scale, corners, shadows and animations (Settings > Appearance).
- **Classic**: V2.38.17's interface, the menu on `M` with Controls, Settings, Saves, Help and More. Pick it in
  Settings > Interface > Classic interface (a switch). It looks and works like V2.38.17: its settings, fonts
  and colours; the New interface's Appearance settings aren't shown there and keep their values. Both
  interfaces read one settings store: a setting changed in one shows in the other at once. Phones get touch
  buttons in either.

## What it does

- **Recording and playback**: per frame the character state, camera and zoom, keyboard, mouse buttons,
  wheel and position, animations, tools, death and respawn. Test replays them (keys and mouse too, if
  you want), at any playback speed.
- **Library** (New) / **Saves** (Classic): every run shows its length, frames, saved date, size, script
  version and whether it used the kit or the speed hack. Folders, search as you type, sort by name / date /
  length, rename, move, delete (with a confirm). New attempt keeps numbered attempts
  (`Name (2)`, `Name (3)`...) grouped under the run.
- **Merging**: join a run before or after the one loaded, standing where they meet.
- **Client objects** (Settings > World sync > Sync Client Objects, off by default): parts only your client
  shows (spinners, moving / falling / swinging platforms, pushboxes, vanishers...) are saved with the run and
  put back while testing and scrubbing. Only the ones on screen are saved. A part that changes for the first
  time while recording (a morph, a vanisher) also gets the state it had before.
- **EToH kit** (Eternal Towers of Hell kit v6.1.3): timed buttons and their timers, lighting changers, beat
  blocks, turrets, pushboxes, morphs.
  - *Kit Scripts On TAS Clock*: the kit's own scripts wait, delay and tween on the TAS clock, so they stop
    while you are paused and slow down with the speed hack. Kit scripts that move things every frame (the
    Zipline ride, the Sequencer) get the TAS clock's frame time too.
  - *Sync Kit Objects*: beat blocks follow the TAS time, turret bullets are saved in the run (with their hits
    and damage), pushboxes are hidden on frames before they were spawned, and the effects of bounce pads and
    jump launchers are saved and shown again when testing.
- **Speed hack** (Settings > Speed hack): slow or fast motion while recording (0.1x - 4x), like a video played
  slower or faster. The character (walking, turning, jumps, coyote time), gravity, animations, the camera's
  zoom and the world (constraints, conveyors, bounce pads, swings, kit timers) change speed; the run is saved
  in normal time, so Test plays it at normal speed. Fast motion (above 1x) is close, not exact: one real
  physics step covers several steps of game time. Use it to get through waits.
  - *Frame Step* (below 1x): nothing is scaled. Roblox's normal physics runs on some frames only (one in two
    at 0.5x) and everything that moves is held still for the others, the humanoid itself too (its state
    machine and timers stand still, so a landing, a jump's push and coyote time take the same game time as at
    normal speed and nothing plays at full speed); only the frames whose physics ran are recorded, each made
    right before its step as at 1x, so walking, jumping, falling and landing come out like normal speed. A
    loose platform you push or stand on is held with you, so slow motion stays slow there too.
- **MicroProfiler** (F6): a copy of Roblox's MicroProfiler (modes, timers, counters, dumps), plus a TAS
  timeline (Custom > TAS Timeline: click a frame to go there).
- **Inputs**: mouse positions replay on any screen size, a fake cursor for NohBoard while the camera is
  locked, mobile thumbstick replay. Paused in Create, a see-through cursor shows where the mouse was on the
  frame shown (it follows Back / Forward) and unpausing puts the real mouse back there, so the recorded mouse
  doesn't jump (Keep Mouse Position (Paused)).
- **Unload** (Help > Unload HappaTAS, below the topics; Classic: More > Unload HappaTAS) undoes everything: no
  interface, connection, hook or changed property is left. Running the script again unloads the copy already
  running, V2 too, and running V2 (from the history) unloads HappaTAS 3.

## Settings and files

| Section | Settings |
| --- | --- |
| Playback | Lock Camera (Test), Interpolate Playback, Playback Speed, Restart When Testing, Show Completion Message |
| Create | Lock Camera (Paused), Record Death & Respawn, Record Tool Actions, Ignore Game Processed |
| Speed hack | Speed Hack, Speed Hack Speed (0.1 - 4), Speed Hack Frame Step |
| Inputs | Replay Keyboard, Replay Mouse Clicks, Replay Mouse Movement, Normalize Mouse UV, NohBoard Cursor, Keep Mouse Position (Paused), Invisible Mouse Speed Multiplier, Window Guarding |
| World sync | Sync Client Objects, Smooth Client Objects, Frustum Culling CO, Sync Button Timers, Sync Lighting, Kit Scripts On TAS Clock, Sync Kit Objects |
| Interface | Classic interface, Show Stats (Idle / Create / Test), Stats Text Size, Show MicroProfiler, MicroProfiler Scale, MicroProfiler Text Offset, Allow PlayerGui Interface |
| Appearance | Theme, Glass, colours, fonts, text size, interface scale, corners, button shape, shadows, animations |

Files, in `<executor workspace>/HappaTasPort/`:

- `Settings3.json`: HappaTAS 3's settings, keys and windows. The first start converts V2's `Settings.json`
  (every setting and key binding; V2's old sound settings are dropped). `Settings.json` itself is never
  written, so V2 keeps its own settings. To convert V2's settings again (say you kept using V2 after trying a
  HappaTAS 3 test build), unload HappaTAS first (Help > Unload HappaTAS, or rejoin; while it runs it writes
  `Settings3.json` again within a moment), then delete `Settings3.json`, then run the script. That also resets
  what only HappaTAS 3 has: the look, the windows and the interface choice.
- `<PlaceId>/`: the runs of that game (`.tas`), folders as real subfolders, and `library.cache` (the runs'
  details, rebuilt when it's missing or out of date).
- Every `.tas` file V2 saved (file versions 1 - 5, and V2's old `.json` slots) opens and plays. A run is saved
  as version 6 only when you save it again; saving writes a temporary file first and checks it, so a failed
  save never touches the old file.
- V2 can't open version 6 files: it says "unsupported file version 6" and leaves the file alone. Keep a copy
  saved by V2 if you want to go back to V2 with a run.

## Files in this repository

- `wow`, `wow1`: the latest script, HappaTAS 3 (release build: `src2/` without comments and blank lines).
- `src2/`: HappaTAS 3's commented source, one module per file, built in the order of `src2/modules.txt`:
  `platform/` (executor functions), `kernel/` (lifecycle, pipeline, state, events), `engine/` (modes,
  timeline, settings, controls, plugins, merge), `world/` (character, camera, inputs, animations, tools,
  client objects, buttons, lighting, the EToH kit, time control), `persist/` (file format v6, the v1 - v5
  readers, library, settings file), `ui/` (both interfaces), `profiler/` (the MicroProfiler).
- `tests3/`: HappaTAS 3's test suites (headless), `tests3/trace/` the frame-by-frame comparisons with V2.
- `tools/`: build and test scripts.
- `src/parts/` and `tests/`: V2.38.17's source and tests, kept as the reference the traces compare against
  (commit aaa21b6) and for the mock of the Roblox API (`tests/mock/`) both test sets use.
- `docs/superpowers/`: HappaTAS 3's design (spec) and the plan of each phase.
- Older scripts: `works` (a V2.38.16 copy), `true`, `true real`, `nohboard` (V2.33),
  `HappaTAS_Executor-2.lua` (V2.32). Every version is also in the git history.

## Building and testing

You need bash, Python 3 and the [Luau CLI](https://github.com/luau-lang/luau/releases) (on Windows: Git
Bash or WSL; put `luau` on your PATH, or set `LUAU=path/to/luau`).

```
bash tools/release3.sh                 # writes wow and wow1 from src2/
bash tools/check_release3.sh           # wow / wow1 are the release build of src2/?
bash tools/build3.sh --check           # builds src2/HappaTAS3.lua (with comments) and loads it in the mock
timeout 3600 bash tools/test_all3.sh   # every suite, the traces against V2, the bench (headless mock)
BENCH=1 bash tools/test_all3.sh        # ... plus the 10-minute save / load bench against V2
bash tools/build_test3.sh kit && (cd tests3 && luau run_kit.lua)       # one suite
bash tools/build_test3.sh main wow && (cd tests3 && luau run_main.lua) # one suite on the release build
bash tools/trace3.sh                   # one scripted session on V2.38.17 and HappaTAS 3, compared line by line
bash tools/bench3.sh                   # cost per frame in every mode against V2
bash tools/savebench3.sh               # save / load time and size of a 10-minute run against V2
python3 tools/check_readme3.py         # this README matches the code (commands, controls)
```

Passing tests do not prove it works in a real game: the mock is not Roblox. Each phase was also checked in a
real Roblox client (spec section 13 has the numbers). `tools/live/meter3.lua` times V2 and HappaTAS 3 in a real
client (development only, never released).

## Making changes

- Edit `src2/`, never `wow` by hand. Then `bash tools/release3.sh` and `timeout 3600 bash tools/test_all3.sh`
  (it warns when `wow` is out of date).
- Luau allows 200 locals per function: big modules keep their state in tables and helpers in `do` blocks.
- Conservative Luau syntax (no `+=`, `//`, backtick strings, `continue`, if-expressions), no network code
  (no HttpGet / request / loadstring).
- V2: `bash tools/release.sh` still builds V2.38.17 from `src/parts/`, into `build/wow_v2` (never `wow`).

## Working on it with Claude Code

Open this folder in Claude Code. If there is a `CLAUDE.md` in the folder, Claude Code reads it
automatically. `CLAUDE.md` and the `claude/` folder are listed in `.gitignore`: personal notes kept
there stay on your own computer and are never pushed to GitHub.

## File format

`.tas` files start with `HTAS` and a version byte. Version 6 (HappaTAS 3) has a small uncompressed header
(frame count, length, created / saved time, script version, PlaceId, kit and speed hack use) so the library
never unpacks a whole file, then the frames column by column, LZ4 compressed: numbers are stored as changes of
their 1/1000 value (times 1/1000000), an unchanged value in one byte. A 10-minute run at 240 FPS is about 80 %
of V2's size. Versions 1 - 5 are V2's (v5: kit events and the speed hack factor, v4: client object clocks).

## Version history (short)

- **HappaTAS 3.0.0**: rewritten from scratch. A new interface (Dock, windows, timeline bar, Inspector) and
  the classic one; a library with folders, search, sort and numbered attempts; file format v6 (smaller,
  safe saving); old runs and settings carry over; smaller files that save faster and a clean Unload; touch
  buttons and thumbstick replay on phones; the MicroProfiler on the new engine.
- **V2.38.17**: no sounds, keys replayed with keypress only, the speed hack's walking, turning, jumps,
  gravity and coyote time on the TAS clock, coyote time kept across a pause.
- **V2.38.16**: speed hack up to 4x (fast motion), Frame Step slow motion (normal physics: pushed
  platforms speed up normally), the zoom plays back at normal speed after slow / fast motion, bounce pad and jump
  launcher effects shown when testing, the Zipline ride and Sequencer on the TAS clock.
- **V2.38.15**: bounce pads bounce as high in slow motion, client objects saved from their start state
  (morphs show up before their button is pressed when testing).
- **V2.38.14**: the EToH kit's scripts on the TAS clock (a pause no longer cuts a jump launcher's
  push), beat blocks / turret bullets / pushboxes from the TAS, the speed hack slows the world too,
  Idle leaves the lighting as it is, file format v5.
- **V2.38.13**: speed hack (slow motion while recording), client objects on their own clocks (smaller
  files), 240 FPS frames no longer dropped.
- **V2.38.5 - V2.38.12**: timed buttons and their timer UI, lighting changers, vanishers, beat blocks,
  morphs, camera freeze while paused, first person / shift lock fixes.
- **V2.38.4**: the MicroProfiler's Avg counts every frame.
- **V2.38.3**: the camera script is hooked in place; no visible PlayerGui interface by default.
- **V2.38.2**: every Real executor function checked (keys, mouse replay within 1 px, filtergc).
- **V2.38 / V2.38.1**: the MicroProfiler compared with Roblox's own, frame by frame.
- **V2.37 - V2.37.2**: faster and smaller, no keys while typing, bugs found in a real client fixed.
- **V2.36**: MicroProfiler like Roblox's. **V2.35**: rebuilt into modules.

Credits: Happy_Liam/happa (HappaTAS), plusgiant5 (Tasability), TestMicrowaveDinner, Skittlesuna.
