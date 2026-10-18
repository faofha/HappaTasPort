# HappaTasPort

HappaTAS as **one client-side Luau script** for Roblox executors. It records and replays TAS
(tool-assisted speedrun) runs frame by frame and saves them as compact `.tas` files in
`<executor workspace>/HappaTasPort/<PlaceId>/`.

It started as the HappaTAS model pair (an initializer that `require()`s a MainModule); everything,
including the old server scripts, now runs in one local script. No network code.

**Latest version: V2.38.15.** Run `wow` (or `wow1`, the same file) in your executor.

## Quick start

1. Run the contents of `wow` in your executor while you are in the game.
2. Press `2` (Create). Left click unpauses and pauses: you record while it is unpaused.
3. While paused, `F` / `G` step one frame back / forward, `R` / `T` hold back / forward. Unpausing on an
   earlier frame cuts the frames after it.
4. Press `3` (Test) to play the TAS back, `1` (Idle) to stop.
5. `M` opens the menu: controls, settings, saves (slots), help and the update log.

## Default controls (all can be changed in the menu)

| Action | Key | Action | Key |
| --- | --- | --- | --- |
| Idle | 1 | Forward 1 Frame | G |
| Create | 2 | Back 1 Frame | F |
| Test | 3 | Unpause 1 Frame | V |
| Pause / Unpause | Left Click | Return | E |
| Forward (hold) | T | Look Around | L |
| Back (hold) | R | Optimize TAS | Q |
| Menu | M | Delete TAS | Backspace |
| MicroProfiler | F6 (Ctrl+P pauses it) | Toggle Speed Hack | none (pick one) |

No HappaTAS key does anything while you type in chat or a text box.

## What it does

- **Recording and playback**: per frame the character state, camera and zoom, keyboard, mouse buttons,
  wheel and position, animations, tools, death and respawn. Test replays them (keys and mouse too, if
  you want), at any playback speed.
- **Client objects** (Settings > World Sync > Sync Client Objects, off by default): parts only your
  client shows (spinners, moving / falling / swinging platforms, pushboxes, vanishers...) are saved with
  the TAS and put back while testing and scrubbing. Only the ones on screen are saved. A part that
  changes for the first time while recording (a morph, a vanisher) also gets the state it had before.
- **EToH kit** (Eternal Towers of Hell kit v6.1.3): timed buttons and their timers, lighting changers,
  beat blocks, turrets, pushboxes, morphs.
  - *Kit Scripts On TAS Clock*: the kit's own scripts wait, delay and tween on the TAS clock, so they
    stop while you are paused and slow down with the speed hack (a jump launcher's push, moving
    platforms, vanishers, cooldowns...).
  - *Sync Kit Objects*: beat blocks follow the TAS time, turret bullets are saved in the TAS (with
    their hits and damage), pushboxes are hidden on frames before they were spawned.
- **Speed Hack** (Settings > Speed Hack): slow motion while recording, like a video played slower. The
  character, gravity, animations and the world (constraints, conveyors, bounce pads, kit timers) slow
  down; the TAS is still saved in normal time, so Test plays it at normal speed. Not slowed: a platform
  you push yourself (the kit's Pushing Platform), because Roblox's walking force can't be slowed by a
  script.
- **MicroProfiler** (F6): a copy of Roblox's MicroProfiler (modes, timers, counters, dumps), plus a TAS
  timeline (Custom > TAS Timeline).
- **Inputs**: mouse positions replay on any screen size, a fake cursor for NohBoard while the camera is
  locked, mobile thumbstick replay, keyboard / click sounds.
- **Saving**: binary `.tas` files ("HTAS" header, LZ4 compressed), settings in
  `HappaTasPort/Settings.json`. The interface lives under `gethui()` (or CoreGui).

## Settings (menu > Settings)

| Section | Settings |
| --- | --- |
| Playback | Lock Camera (Test), Interpolate Playback, Playback Speed, Restart When Testing, Show Completion Message |
| Create | Lock Camera (Paused), Record Death & Respawn, Record Tool Actions, Ignore Game Processed |
| Speed Hack | Speed Hack, Speed (0.1 - 1, 0.5 = half) |
| Inputs | Replay Keyboard, Replay Mouse Clicks, Replay Mouse Movement, Normalize Mouse UV, NohBoard Cursor, Invisible Mouse Speed, Window Guarding |
| World Sync | Sync Client Objects, Smooth Client Objects, Frustum Culling CO, Sync Button Timers, Sync Lighting, Kit Scripts On TAS Clock, Sync Kit Objects |
| Interface | Show Stats (Idle / Create / Test), Stats Text Size, Show MicroProfiler, MicroProfiler Size, MicroProfiler Text Offset, Allow Visible Interface (PlayerGui) |
| Sounds | Keyboard Sounds, Mouse Click Sounds, Sound Mode, Sound Volume, Dynamic Pitch Variation |

## Files in this repository

- `wow`, `wow1`: the latest script (release build: the source without comments and blank lines).
- `src/parts/`: the commented source, one module per file, joined in this order (`tools/order.txt`):

  | Part | What it is |
  | --- | --- |
  | `p00_header` | version, changelog, config |
  | `p01_env` | executor functions, services, shared helpers |
  | `p02_settings` | controls and settings tables |
  | `p03_keys` | key names |
  | `p04_ui` | the interface, built from compact data (help page, update log) |
  | `p07_codec` | the `.tas` file format (columns, LZ4) |
  | `p08_store` | slots and settings files |
  | `p09_bridge` | the game's camera / control scripts (zoom, shift lock, first person) |
  | `p10_inputs` | keyboard and mouse recording and replay |
  | `p11_cursor` | the NohBoard cursor |
  | `p12_anim` | animations |
  | `p13_clientobjects` | client objects |
  | `p14_buttons` | EToH timed buttons, lighting changers, vanishers, morphs |
  | `p15_tools` | tool actions |
  | `p16_sounds` | keyboard / click sounds |
  | `p16_speedhack` | the speed hack (character and world) |
  | `p16_kit` | the Kit Clock and kit objects (beat blocks, turrets, pushboxes) |
  | `p17_profiler` | the MicroProfiler |
  | `p18_core` | modes, recording, playback, the frame loop |
  | `p19_menu` | the menu |
  | `p20_start` | start-up and unload |

- `tests/`: headless tests with a mock of the Roblox API (`tests/mock/`), run with the Luau CLI.
- `tools/`: build and test scripts.
- Older versions: `true`, `true real`, `nohboard` (V2.33), `HappaTAS_Executor-2.lua` (V2.32). Every
  version is also in the git history.

## Building and testing

You need bash, Python 3 and the [Luau CLI](https://github.com/luau-lang/luau/releases) (on Windows: Git
Bash or WSL; put `luau` on your PATH, or set `LUAU=path/to/luau` for `test_all.sh` / `diff_builds.sh`).

```
bash tools/assemble.sh                 # joins src/parts/ into src/HappaTAS_Executor.lua (with comments)
bash tools/release.sh                  # writes wow (the release build); then copy wow to wow1
bash tools/test_all.sh                 # every test suite (headless mock, not a real game)
bash tools/test_all.sh old.lua         # ... plus frame-by-frame traces compared with an older build
bash tools/build_test.sh kit && cd tests && luau run_kit.lua      # one suite
bash tools/build_test.sh kit wow && cd tests && luau run_kit.lua  # one suite on the release build
bash tools/diff_builds.sh old.lua      # same behaviour as an older build? (IGNORE='regex' skips lines)
bash tools/build_test.sh bench && cd tests && luau run_bench.lua   # cost per frame in every mode
```

Suites: smoke, profiler, graphimg, core, scale, perf, textline, typing, live, realinput, security,
coclock, speedhack, kit, cobase. Passing tests do not prove it works in a real game: the mock is not Roblox.

Testing in a real Roblox client (development only, never released):

```
bash tools/live_build.sh               # build/HappaTAS_live.lua: debug log on, modules exported as
                                       # getgenv().__HappaTAS_T for test scripts
python3 tools/prof_patch.py build/HappaTAS_live.lua build/HappaTAS_prof.lua
                                       # + os.clock timers per section, totals in getgenv().__HPROF
```

`tools/live/harness.lua` (key taps, real mouse clicks on GUI objects, console capture) and
`tools/live/perf_scenario.lua` (cost per frame in every mode) run inside the client; see their headers.

## Making changes

- Edit `src/parts/`, never `wow` by hand. Then `bash tools/release.sh`, copy `wow` to `wow1`, and run
  `bash tools/test_all.sh`.
- A release build someone edited by hand can be ported back into the parts with
  `python3 tools/port_release.py OLD_RELEASE NEW_RELEASE --apply`.
- Luau allows 200 locals per function: the main chunk is at that limit, so new helpers go inside `do`
  blocks or module tables.
- Conservative Luau syntax (no `+=`, `//`, backtick strings, `continue`, if-expressions), no network
  code (no HttpGet / request / loadstring).

## Working on it with Claude Code

Open this folder in Claude Code. If there is a `CLAUDE.md` in the folder, Claude Code reads it
automatically. `CLAUDE.md` and the `claude/` folder are listed in `.gitignore`: personal notes kept
there stay on your own computer and are never pushed to GitHub.

## File format

`.tas` files start with `HTAS` and a version byte; the frames are stored column by column and LZ4
compressed. v5 (V2.38.14) adds the kit events (turret bullets, pushbox spawns), the speed hack factor
and the kit objects' ids; v4 (V2.38.13) the client object clocks. Older files (v1 - v4, and the old JSON
slots) still load.

## Version history (short)

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

Credits: Happy_Liam/happa (HappaTAS), plusgiant5 (Tasability), TestMicrowaveDinner.
