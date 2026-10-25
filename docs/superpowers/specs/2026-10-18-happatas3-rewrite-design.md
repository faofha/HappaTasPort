# HappaTAS 3: full rewrite, design

Date: 2026-10-18. Status: draft for review.
Visual reference: `2026-10-18-happatas3-ui-mockup.html` (the Settings window, final mockup).

## 1. Goal

Rewrite HappaTAS from scratch, engine included, as HappaTAS 3. It must be:

- **easier to use**, above all saving and loading: every run shows its details, runs can be organised in
  folders, searched, sorted and kept as numbered attempts;
- **faster**: less work per frame, less memory and garbage-collection lag, smaller files, faster saving;
- **more reliable**: one place that decides what runs when, explicit modes instead of flags that must
  agree, everything undone on Unload;
- **new to look at**: a "Studio" layout in a soft liquid-glass style, with far more ways to customise it.

Every feature of V2.38.16 stays. Old `.tas` files and `Settings.json` keep working.

### Success criteria

1. Recording a run with the same inputs gives the same frames as V2.38.16 (frame-by-frame trace
   comparison in the mock, plus spot checks in the real client), for the character, camera, inputs,
   animations, client objects, buttons, lighting, the EToH kit and the speed hack (Smooth and Frame Step).
2. Every `.tas` file V2.38.16 can open, HappaTAS 3 opens and plays the same way.
3. `Settings.json` from V2.38.16 is converted: every setting and key binding carries over.
4. Per-frame cost in each mode (Idle, Create paused, recording, Test) is no higher than V2.38.16's, measured
   with the bench in the mock and the HappaTAS timer in the real client; saving a 10-minute TAS takes less
   time than in V2.38.16.
5. Unload leaves nothing behind: no GUI, no connections, no hooks, no changed properties.

## 2. Scope

**Kept:** recording / playback (keyboard, mouse buttons, wheel, mouse position, camera, zoom, animations,
tools, death and respawn), Create / Test / Idle modes with every key control, TAS merge, client objects
(Sync / Smooth / Frustum culling), timed buttons, lighting, the EToH kit (Kit Clock, frame listeners, beat
blocks, turrets, pushboxes, bounce pad / launcher effects, morphers), the speed hack (0.1x to 4x, Smooth and
Frame Step), the MicroProfiler copy, mobile support (touch buttons, thumbstick replay), the NohBoard cursor,
keyboard / click sounds, real-mouse replay, the Real-specific input fixes (VirtualInputManager keys, mouse
calibration).

**Not included:** autosave, cloud sync, tags on runs, anything for games other than the ones HappaTAS
already supports. Working around a game's anti-cheat is out of scope.

**Executors:** Real first. Only functions in the sUNC standard where possible, each looked up with
fallbacks (as V2.38.16 does), so Potassium and other sUNC executors mostly work. Executor function docs:
docs.projectreal.gg, docs.potassium.pro, sunc.su only.

## 3. Approach

A new source folder `src2/`, built into one file like now. V2.38.16 stays the script in use until
HappaTAS 3 catches up. Systems are rebuilt one by one on the new skeleton, each checked against V2.38.16 with
the existing trace tools and then in the real client.

## 4. Architecture

Six layers; each uses only the ones above it.

1. **Platform**: executor feature detection by sUNC name with fallbacks; services through `cloneref`;
   file access; one safe way to call game code (`gameCall`: on its own thread, so the game's camera module
   can't take HappaTAS's CoreGui access away).
2. **Kernel**:
   - **Pipeline**: the single place that says what runs in each Roblox event and in what order. Every
     module registers its handlers with an explicit order number. Events, in the order measured in the
     client: input, PreRender (+ RenderStepped), PreSimulation, physics, PostSimulation / Heartbeat,
     end of render step (BindToRenderStep Last + 1).
   - **State store**: mode, frame, paused, speed, selection, etc., with change events. The UI only listens.
   - **Event bus**: module-to-module notifications.
   - **Lifecycle**: every connection, hook, created instance and changed property is owned by a module and
     undone on Unload, in reverse order.
3. **Engine**: timeline, recorder, player, mode machine.
4. **World plugins**: character, camera, inputs, animations, client objects, buttons, lighting, EToH kit,
   time control (speed hack).
5. **Persistence**: codec v6 plus readers for v1-v5, the library, settings.
6. **UI**: component kit, windows, timeline bar, MicroProfiler.

**Build:** each `src2/` module is its own function in the built file, so no function comes near Luau's
200-locals limit. `tools/build3.sh` writes `src2/HappaTAS3.lua` (with comments, used by the tests) and the
release (`wow3`, then `wow` / `wow1` at switch-over) without comments and blank lines.

## 5. Engine core

### 5.1 Mode machine

States: **Idle**, **Paused** (on frame n), **Recording**, **Testing**. Transitions: Create, Unpause, Pause,
Step one frame, Seek (back / forward / to a frame), Return, Test, Idle, Merge. Each transition is one function
that checks it is allowed, then calls every plugin's leave / enter in a fixed order. Keys, buttons and the
timeline all request transitions; nothing sets mode flags directly.

### 5.2 One frame

| Event | Recording | Testing |
|---|---|---|
| PreRender | start frame n: camera, inputs, mouse, time | pose the character for the screen |
| PreSimulation | fill frame n: character, humanoid state, animation, every plugin's record; Frame Step decides run or hold | pose for physics |
| PostSimulation | release a held step; fill the frame if there was no physics step (240 FPS) | advance the playback clock |
| End of render | - | re-apply poses the game moved; cursor |

### 5.3 Timeline

Frames are stored as columns. Numbers live in Luau `buffer`s: TotalTime, FrameTime, root CFrame
(position + rotation), linear / angular velocity, camera CFrame, zoom, humanoid state, mouse. Rare data
(inputs, tool events, kit events, deaths, speed factor) is kept in sparse lists keyed by frame. Plugins
register their own columns. Growth doubles the buffers; cutting frames truncates.

### 5.4 Rules carried over from V2.38.x live testing (each one becomes a test)

- A frame's time is the simulated step time; frames without a physics step at 240 FPS are kept.
- Pausing throws away the step after the last frame; the kit clock goes back with it.
- Unpausing puts velocities back and client objects on their recorded pose with their velocities.
- No jump on the first recorded frame; coyote jump and ladder rules as in V2.38.16.
- Game code (camera module, kit functions) is only ever called on its own thread.
- The camera script is patched (hookfunction / restorefunction) once the PlayerModule is found, even when
  the garbage-collector scan found the cameras first; never re-patched after Unload.

## 6. Persistence

### 6.1 File format v6

`HTAS`, version byte 6, then a small uncompressed header (frame count, TAS length, created / saved time,
script version, PlaceId, kit rules version, speed hack use) so the library never has to unpack a whole file,
then the LZ4-compressed column blocks (buffers written directly). v1-v5 files load through readers ported from
V2.38.16's codec and are converted in memory; a file is only rewritten as v6 when it is saved again.

### 6.2 Library

- Files stay in `HappaTasPort/<PlaceId>/`; folders are real subfolders.
- `library.cache` per place caches every file's header info; rebuilt from the headers when missing or stale (not `.json`: V2 lists every `.json` in the place folder as a legacy slot).
- Each run shows name, length, frames, saved date, size, script version, kit / speed hack use.
- **Attempts:** "Save as new attempt" saves `Name (2)`, `(3)`...; attempts are grouped under the run, newest
  first.
- Sort by name / date / length; search filters as you type; rename, move to folder, delete (with confirm).
- **Safe saving:** write `name.tas.tmp`, read it back and check its size, then write the real file and delete
  the temporary one. A failed save never touches the old file.

### 6.3 Settings

One schema (name, type, default, range, section, description). `Settings.json` from V2.38.16 is converted
on first load: every old name maps to a new key (table in the code, tested); the old file is kept as
`Settings.v2.json`. "Show Stats (Idle / Create / Test)" and "Stats Text Size" become Inspector settings.
The sound settings that V2.38.16 had (removed in V2.38.17) are dropped by the conversion without an error.

There is one settings store for the whole script. Every interface (the new one and the classic one, 8.5)
reads its values from that store and listens to its change events; no interface keeps a copy of its own.
A change saved from one interface shows in the other at once, also when the other one isn't open yet (it
reads the store when it opens).

## 7. World plugins

Shared interface: `enter(mode)`, `leave(mode)`, `record(frame)`, `show(frame)` (paused), `playTo(frame, t)`
(Test), `afterPhysics(frame)`, `save(columns)`, `load(columns)`.

- **Time control** (the speed hack): the single source of "TAS time per real second" (0.1x to 4x).
  Smooth mode scales gravity (x s^2), WalkSpeed / JumpPower (x s), momentum, the world's constraints and
  body movers, conveyors, free assemblies and kit config velocities (bounce pad Power, swing Boost).
  Frame Step (below 1x) runs normal physics on some steps and holds everything for the others (anchored from
  PreSimulation to PostSimulation, velocities put back). It feeds the rate to the kit clock, animations, the
  zoom spring and the kit frame listeners.
- **Client objects:** same recording model as V2.38.16 (keyframes + screw motion on per-part clocks,
  start states, on-screen only within a 25-stud radius), rewritten around one registry with fewer
  change listeners per part; parts at rest cost nothing.
- **EToH kit:** Kit Clock (module environments, tween helper, RunService frame listeners through
  getconnections, Morpher / DistanceCulling left alone); kit objects as a table of kinds, each with how to find
  it (configuration name or tag), what it records and how it plays back: beat blocks, turrets, pushbox spawners,
  bounce pads, jump launchers (`LauncherConfiguration`), morphers.
- **Buttons, lighting, tools, death:** same behaviour as V2.38.16, as plugins.

**Known limits (documented, not promised):** other players; Roblox's own humanoid timers; the moment the
character bumps into a platform it pushes in Frame Step (the push can start later or stall); kit listeners whose
function the executor can't see.

## 8. UI

### 8.1 Look

- **Windows:** soft frosted glass ("W2"): translucent fill, thin subtle rim, soft shadow, 16 px corners
  (adjustable). No sheen band.
- **Glass setting:** Clear / Tint (default) / Frost. Frost blurs the game behind the windows with Glass-material
  parts in front of the camera plus a DepthOfField effect; it needs high graphics quality and falls back to Tint.
  It must be proven in the real client in phase 5 before it ships.
- **Controls:** pills. Solid accent fills; switch and slider knobs are clear, bright glass (white with a
  crisp rim); the selected segment is a gentle glass bubble; buttons calm.
- **Colours:** blue accent by default (changeable), red only for recording, amber for reset buttons.
- **Fonts:** Builder Sans for text, Roboto Mono for numbers (both changeable).

### 8.2 Layout

Floating windows: drag by the title, resize from any edge or the corner grip, minimise, close, click to bring
to front. Positions and sizes are remembered per screen size; a "Reset layout" puts them back. On mobile,
windows open as full-width sheets.

**Timeline bar** (bottom centre): a thin bar with a time ruler, ticks, markers, events and the playhead
(drag to jump while paused, scrub in Test, wheel to zoom); ▾ opens lanes (Character, Inputs, Kit & objects,
Buttons). Its left end shows the mode (● Recording / ❚❚ Paused / ▶ Test / Idle) and the speed; then the
transport buttons (start, step back, record / pause, step forward, Test, marker); on the right the unsaved dot
and the frame / time readout. Collapses to a slim strip in Idle.

### 8.3 Windows

- **Inspector:** collapsible sections: Frame (frame, frame time, total time, speed), Character (rig type,
  state, position, rotation, velocity, angular velocity, move direction, walk / jump, health, floor),
  Camera & input (camera rotation, zoom, keys, mouse), World (client objects, kit, buttons), Performance
  (FPS, HappaTAS ms). Every row can be pinned or hidden. Every value from V2.38.16's stats panels is here.
- **Library:** folder sidebar, search, list (name, length, frames, saved, attempts nested), info line, buttons
  Load / Save / New attempt / Merge / Rename / Delete.
- **Settings:**
  - Search box (text vertically centred, magnifier icon on the right) and section chips.
  - Each row: name (and a short explanation) on the left; the control flush right; when the value isn't the
    default, an amber ↺ reset button right next to the control (just left of it). "Reset section" per section.
  - Slider values are typeable (click the number). Colour swatches open a colour picker (colour square, hue,
    transparency, old / new halves, HEX / RGB / HSV boxes with labels, recent colours). Dropdowns open a plain
    list; for fonts each name is drawn in its font and hovering previews it live on the whole interface (click
    keeps it, moving away reverts).
  - Sections: Appearance, Playback, Create, Speed hack, Inputs, World sync, Interface, UI sounds.
- **Controls:** every action with its key, click to rebind, conflicts flagged. Default keys as V2.38.16.
- **Help**, **Merge**. The **MicroProfiler** stays its own Roblox-style overlay.

### 8.4 Settings list

All 34 settings of V2.38.17 (Playback 5, Create 4, Speed hack 3, Inputs 7, World sync 7, Interface 8;
V2.38.16's 5 sound settings were removed in V2.38.17), plus:

- **Appearance:** Theme (saved looks, Save as…), Glass (Clear / Tint / Frost), Glass colour, Glass
  transparency, Blur strength, Edge light, Accent colour, Text colour, Secondary text colour, Recording
  colour, Font, Number font, Text size, Interface scale, Window corners, Button shape (Pill / Rounded /
  Square), Shadows, Animations (Off / Smooth / Snappy / Bouncy), Animation length, Easing (Roblox easing
  style + direction, or Custom cubic-bezier with a draggable curve, x1 y1 x2 y2, presets and Preview).
- **UI sounds:** Interface sounds on / off, Click sound, Hover sound, Open / close sound, Volume.

Custom bezier easing runs in HappaTAS's own tween code (TweenService has no bezier).

### 8.5 Classic interface

A setting **Interface: New / Classic** (in Interface; default New). Classic is V2.38.17's interface (main
menu, stats panels, settings list, controls, help, merge) drawn by HappaTAS 3, for people who prefer it.

- Switching takes effect at once, without running the script again; each interface keeps its own window
  positions.
- Both interfaces use the one settings store (6.3). A setting changed in one shows in the other right away:
  the classic interface listens to the same change events, so nothing waits for a switch back.
- Appearance settings apply to the classic interface wherever it has the same thing: accent colour, text
  colour, secondary text colour, recording colour, font, number font, text size and interface scale. The
  rest (glass, blur, edge light, corners, button shape, shadows, animations, easing) are kept untouched in
  the store and shown only in the new interface; the classic one never resets or overwrites them.
- The classic interface's settings list shows every setting, the new Appearance ones too (so they can be
  changed there), in V2.38.17's row style.
- Tests (mock): with both interfaces built, change each setting in one and check the other's control and its
  look in the same frame; change the accent colour in the new interface, switch to classic: the classic one
  uses it at once; change it in classic, switch back: the new one shows it; restart: both load it.

## 9. MicroProfiler

Rebuilt on the kernel with the same look and numbers as V2.38.16 (modes, groups, aggregate, timers, counters,
dumps, TAS timeline, EditableImage graph).

## 10. Error handling

- The pipeline calls every handler protected; each distinct error is reported once; a plugin that keeps
  failing is switched off with a toast and the frame goes on.
- Saving never destroys the old file; the settings conversion keeps the old file.
- Missing executor functions switch the matching feature off with a note in Help, never an error.

## 11. Testing

- The headless mock (`tests/mock/`) with a suite per module.
- Trace comparison against V2.38.16 for the engine, client objects, kit and time control.
- Mutation checks for each rule in 5.4 and each fix.
- Bench of per-frame cost per mode against V2.38.16.
- A live check in the EToH kit test place at the end of each phase, only when dzr says the Real MCP is
  connected; Settings.json and the place's `.tas` files backed up and restored, the FPS cap recorded and put back.

## 12. Phases

Each phase has its own implementation plan, tests and PR.

1. **Skeleton:** build tool, platform, pipeline, state, events, lifecycle, mock harness.
2. **Engine core:** timeline, mode machine, recorder / player (character, camera, inputs, animations, tools,
   death); trace parity with V2.38.16.
3. **Saves:** codec v6, v1-v5 readers, library, settings conversion. First phase you can record and save with.
4. **World plugins:** client objects, buttons, lighting, EToH kit, time control.
5. **UI:** component kit, windows, timeline bar, Settings, Inspector, Library, Controls, Help, Merge, mobile;
   the classic interface (8.5); Frost blur trial in the client.
6. **MicroProfiler.**
7. **Switch-over:** HappaTAS 3 becomes `wow` / `wow1`; README; V2.38.16 stays in history.

## 13. Open questions (answered during the phases)

- Does the Frost blur work well enough in Roblox (graphics levels, performance, look)? Phase 5.
- V2.38.17 removed every sound: should the new UI sounds (8.4) stay, or go too? Ask before phase 5.
- Which Roblox fonts to list (Builder Sans, Gotham, Source Sans Pro, Roboto, Fredoka One, Oswald,
  Merriweather, Roboto Mono and others available as Font families). Phase 5.
- ~~Exact v6 column encodings and how much smaller files get. Phase 3.~~ Answered in phase 3: numbers are
  stored losslessly as changes of their 1/1000 (times: 1/1000000) value, an unchanged value in one byte,
  anything else as its 8 bytes; LZ4 over the body. A synthetic 10-minute run (144,000 frames at 240 FPS,
  `tools/savebench3.sh`, headless mock): 81,778 bytes against V2.38.16's 101,880 (80 %), saved in 470 ms
  against 523 ms; loaded in 672 ms against 532 ms (the mock's LZ4 is Lua on both sides). Live (EToH kit test
  place, 2026-10-25): a 5-second run (301 frames) saved in 37 ms (3,268 bytes) and loaded in 28 ms; dzr's V2
  files (v1, v2, v3, up to 3,141 frames) loaded in 17-71 ms and played.
- Phase 4 (world plugins, headless mock against V2.38.17): every system is a port of V2.38.17's code (client
  objects, buttons, lighting, time control with the humanoid clock, the Kit Clock, kit objects); the traces
  (main, V2's client object trace, a world trace with buttons, lighting, Smooth / fast / Frame Step motion, coyote
  time, the Kit Clock and kit objects) are the same line for line. One V2 flaw was fixed on the way: V2's Kit
  Clock asked for the environment of every Heartbeat / PostSimulation listener's function, HappaTAS's own
  included, which switches Luau's fast paths off for that environment (frames about 2.5x slower after the first
  pause); HappaTAS 3 only looks at listeners whose source is a kit module on the clock. Bench (us per frame, mock):
  Idle 17.3 vs V2's 17.4, recording 84 vs 90, paused 88 vs 113, Test 107 vs 125, a world with 100 client objects,
  beat blocks, a turret and the speed hack at 0.5x 3,402 vs 3,414. The client object listeners stay at 6 per part
  (V2's): the recorder needs Anchored for every registered part (spec 7's "fewer listeners" is still open).
  Live (EToH kit test place, 2026-10-25, ~230 FPS, window not focused, driven through E.modes and
  Humanoid:Move; samples read as the last PreRender handler, i.e. what is drawn): client objects played back
  against the recording, by TAS time: spinning kill brick worst 0.0007 studs (one frame 0.0066 where the part
  jumped two physics steps after a frame with none), the Pushing Platform worst 0.014 (V2's Smooth design: a
  position every 2nd frame plus velocity, the error is about a dt^2 / 2 at ~150 stud/s^2; the same in V2's code,
  diffco trace SAME), held still while paused 3 s. A timed button (Timer 3) pressed at TAS 0.472, released at
  3.479 with a 3 s pause in between (its TimerStart moved 2.997 s while paused), Test released it at 3.474.
  Lighting: the changer's 1 s tween recorded per frame, played back frame by frame (721 frames, worst 0.0005,
  the write tolerance), the run's start lighting shown before the touch, kept as it is on Idle and after Test.
  Beat blocks 10 s with a 3 s pause: switches at whole TAS seconds, recording 2,400 / paused 800 seeked / Test
  2,402 frames 0 wrong against the kit's beat formula at the time shown. Turret 10 s with a pause: one 5 damage
  hit per bullet at the same TAS times in recording and Test (1.025 / 1.029 ...), bullets still and no damage
  while paused, 481 seeked frames the same, Test bullets within 0.009 studs by time (bullets the kit fired in Idle
  before a Test can still hit, as in V2). Speed hack: jump 7.269 studs at 1x, 0.5x Smooth and 0.5x Frame Step
  (apex TAS 0.572 / 0.576 / 0.572), the 0.5x recordings took 2.6 s real for 1.3 s TAS, every Test 1.307 s for
  1.301; walking 13.4-13.8 studs by TAS 0.95 in all of them. Save / load v6 (live1 21,220 bytes, 1,439 frames with
  client objects, speed factors, 5 kit events; long1 2,394 frames loaded in 31 ms while paused in Create): every
  saved column the same after the load (only CY and LT, never saved, differ), the Test after it the same.
  Unload while recording at 0.5x: 94 kit environments back, gravity / WalkSpeed / JumpPower back, no part's
  Anchored changed, nothing left in the Camera / CoreGui / gethui; the release loads and unloads with no console
  line. Per-frame cost, both builds timed the same way (every RunService connection of the build and its render
  bind), interleaved, fresh loads (us, V2.38.17 vs HappaTAS 3 after the review fixes): Idle 79 / 91 vs 78 / 79,
  recording 389 / 439 vs 364 / 442, paused 389 / 358 vs 604 / 504, Test 557 / 444 vs 651 / 541, turret recording
  445 / 361 vs 474 / 429, turret paused 382 / 326 vs 417 / 370, turret Test 496 / 461 vs 492 / 436. So live
  HappaTAS 3 is level in Idle and recording but costs more while paused and in Test (the plugins' own methods cost
  about the same as V2's modules; the Kit Clock's frame listener check while paused is ~70 us a frame) - not
  the headless bench's result; open for a later phase.
