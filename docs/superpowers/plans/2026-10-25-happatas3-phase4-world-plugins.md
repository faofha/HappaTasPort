# HappaTAS 3 Phase 4 (World Plugins) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** HappaTAS 3 records and plays back the world the way V2.38.17 does: client objects, timed buttons, lighting, time control (the speed hack: Smooth, Frame Step, the humanoid on the TAS clock) and the EToH kit (Kit Clock, kit objects), frame for frame the same as V2.38.17 in the headless mock, and V2 files with that data play the same.

**Architecture:** Each system becomes one or more world plugins on the phase 2 plugin contract, ported function by function from V2.38.17 and split into modules small enough for Luau's 200-locals limit. Plugins find each other through the engine table (`E.co`, `E.buttons`, `E.lighting`, `E.time`, `E.kitClock`, `E.kitObjects`), never through imports, so there are no import cycles. Where V2's core calls a system at one point with a return value (the speed hack's factor, Frame Step's step time, the kit's frame), `engine/frame.lua` calls the plugin by name through the phase 2 guard; everything else goes through the existing `on...` hooks at V2's call sites, plus four new ones. The per-frame data keeps V2's encodings (client object records, button events, kit events, speed factors) in the columns phase 3 created for them, so V2 files and phase 3's v6 files load into the plugins unchanged.

**Tech Stack:** Luau, the phase 1-3 kernel / engine / persist layers (`src2/`), the headless mock (`tests/mock/`), `luau` CLI, bash + python3 build scripts.

**Spec:** `docs/superpowers/specs/2026-10-18-happatas3-rewrite-design.md` (1 criteria 1, 2, 4, 5; 2; 4 layer 4; 5.2; 5.4; 7; 10; 11; 12 phase 4). Earlier plans: `docs/superpowers/plans/2026-10-19-happatas3-phase1-skeleton.md`, `2026-10-24-happatas3-phase2-engine-core.md`, `2026-10-25-happatas3-phase3-saves.md`.

## Global Constraints

- Everything in the phase 1-3 plans' Global Constraints still holds (Luau syntax, no network code, sUNC lookups with fallbacks, game code only through `GameCall` / `task.spawn(pcall, ...)`, Debug output only with `CONFIG.Debug`, version `"3.0.0-dev"`, never commit `CLAUDE.md` / `claude/`, commit only the files a task lists).
- **Ruling: reference V2 = V2.38.17 = `src/parts/` at commit `aaa21b6`** (PR #16, merged into `main` with phase 3). V2.38.17 is the script dzr uses now and the spec's settings list (8.4) already counts its 34 settings; its humanoid clock is part of time control. `git show aaa21b6:src/parts/p13_clientobjects.lua` etc.; never the working tree's `src/parts/`.
- Branch: `v3-rewrite`, first brought up to `origin/main` in Task 1. Do not edit `src/parts/`, `wow`, `wow1`, `tests/test_*.lua`. Additions to `tests/mock/` are allowed only when every V2 suite still passes on the reference (`REF=1 bash tools/test_all.sh`).
- Frame data keeps V2's encodings: client object records (V2's "v3" record bytes, `p13_clientobjects.lua:15-30`), button events `BT`, kit events `KE`, speed factor `SK` (`r(k, 10000)`), and V2's object / button / kit id tables. **Ruling:** the columns keep the names phase 3 gave them (`v2CO`, `v2BT`, `v2KE`, `v2SK`); a plugin registers its column under that name with the V2 key before `Run.registerCarry` runs, so phase 3's carry column is replaced and its v6 files load unchanged. Cost if wrong: a rename later needs a codec alias.
- **Ruling:** lighting snapshots (`LT`) and the coyote state (`CY`) stay in memory only, like V2 (V2 never saved them): their columns are marked `save = false` and codec v6 skips them.
- Every plugin turns itself on and off with its setting (V2's): `syncClientObjects` (default 0), `smoothClientObjects`, `frustumCullingCO`, `syncButtonTimers`, `syncLighting`, `kitScriptsOnTasClock` (default 1), `syncKitObjects` (default 1), `speedHack`, `speedHackSpeed` (0.1-4), `speedHackFrameStep`; a change takes effect at once (`E.settings:changed`, owned by the lifecycle), off = released (V2's `Disable`).
- Unload undoes everything each plugin changed (spec criterion 5): parts unanchored with their velocities, gravity / WalkSpeed / JumpPower and every scaled constraint / config value back, kit environments, tween helper and frame listeners restored, button `TimerStart` values back on `os.clock`, lighting as V2's `Disable` leaves it.
- **Ruling:** the Kit Clock needs the environment of the kit's functions. HappaTAS 3's own code never names `getfenv` / `setfenv` (they switch Luau's fast paths off for the environment of the code that uses them; `tools/test_all3.sh`'s deopt guard greps the build): `platform/env` looks the function up by a computed name (`"get" .. "fenv"`) and exposes `Env.envOf(f) -> table?`, used only on kit functions (deoptimizing a kit module's environment is what V2 does too, so its globals are read live). Cost if wrong: a slower HappaTAS 3 in games with the kit (the bench in Task 12 would show it).
- Game functions the plugins call (the kit's `CharacterManager:Damage`, `ControlModule` calls, camera module calls) run on their own thread (`task.spawn(pcall, f, ...)`), V2's rule (5.4).
- Tools on this PC: the scratchpad `bin/` with the `luau` and `python3` wrappers on PATH (`source <scratchpad>/env.sh`), bash is Git Bash. New files are LF; existing files keep their own line endings (edit them with the Edit tool or Python with `newline=''`, never `sed -i`).
- Live tests (Real MCP; dzr: "Real is always connected"): back up `HappaTasPort/Settings.json`, `Settings3.json` and the place's `.tas` files first, record `getfpscap()` and put it back, save only into `HappaTasPort/<PlaceId>/zz_happatas3_test/`, delete it and `HappaTasTest` afterwards, rejoin if the place was changed.

## Review Focus

1. **Unload in every state** (recording with client objects held and the speed hack at 0.5x Smooth; paused inside a Frame Step held step; Test with kit bullets in the air): nothing stays anchored, every scaled value is back, kit environments / tweens / listeners are restored, `TimerStart` follows `os.clock` again, no HappaTAS instance is left in the Camera. Test in Task 12.
2. **A sync setting turned off and on mid-run** (Sync Client Objects, Sync Button Timers, Sync Lighting, Kit Scripts On TAS Clock, Sync Kit Objects, Speed Hack, Frame Step) while recording, paused and in Test: released at once, the run keeps its data, turning it back on picks up from the current frame. Test in Task 12.
3. **A V2 file with client object, button and kit data** loaded, played in Test, saved as v6 and loaded again: plays like V2 plays it, and the reloaded run has byte-identical records and the same id tables. Test in Task 12 (fixtures from phase 3's `tests3/fixtures/v2/`).
4. **A game without the EToH kit, or an executor without `getconnections` / `filtergc` / `getloadedmodules` / `hookfunction`**: the kit plugins and the config scaling switch themselves off with a Debug note, client objects / buttons / lighting / time control still work, no error is printed. Test in Tasks 10 and 11.
5. **The speed hack changed mid-recording** (0.5x Smooth -> 2x -> Frame Step 0.25x -> off, and a pause during a held Frame Step step): every value back to normal at 1x, nothing left anchored, the recorded TotalTime stays continuous and equal to V2's for the same inputs. Test in Task 9.

---

## File Structure

| File | Responsibility |
|---|---|
| `src2/world/co/registry.lua` | Client objects: keys / ids (`keyOf`, `#n` siblings), candidates (kit folders, name hints, constraints), scan, watch / unwatch, property listeners, `register` / `unregister` (V2 `p13` 118-458) |
| `src2/world/co/recorder.lua` | The recorder: clocks 0-3, keyframes + screw motion, full snapshots, start states (`starts`), record bytes (V2 `p13` 512-1350) |
| `src2/world/co/player.lua` | The player: v1 / v2 / v3 record decoding, checkpoints, pose at time t, Smooth blending, holding / releasing / lost parts (V2 `p13` 1350-1800) |
| `src2/world/clientobjects.lua` | The plugin: hooks, settings, the `v2CO` column, object table import / export (V2 `p13` 1686-1874) |
| `src2/world/buttons.lua` | Timed buttons: registry, press / release events (`v2BT`), `TimerStart` on the TAS clock, key export / import (V2 `p14` 12-126, 1097-1811) |
| `src2/world/buttontimers.lua` | The kit's own timer labels and button visuals kept right while HappaTAS drives the timers (V2 `p14` 127-1096) |
| `src2/world/lighting.lua` | Lighting snapshots (`LT`, not saved), trim / pause / resume / release (V2 `p14` 1812-2052) |
| `src2/world/time/control.lua` | Time control: wanted factor, humanoid values, momentum, animations, `update` / `restore`, the plugin (V2 `p16_speedhack` 30-45, 380-420, 512-621) |
| `src2/world/time/world.lua` | The world in slow motion: constraints / body movers, conveyors, free assemblies, kit configs (V2 `p16_speedhack` 46-379) |
| `src2/world/time/framestep.lua` | Frame Step (V2 `p16_speedhack` 420-511) |
| `src2/world/time/humanoid.lua` | The humanoid on the TAS clock (V2.38.17 `p16_speedhack` 622-1028) |
| `src2/world/kit/clock.lua` | Kit Clock: environments, fake `task` / `os`, tween helper, frame listeners, mark / rewind (V2 `p16_kit` 1-540) |
| `src2/world/kit/beats.lua` | Beat blocks as a function of TAS time (V2 `p16_kit` 628-838) |
| `src2/world/kit/turrets.lua` | Turret bullets: events, copies, hits, damage (V2 `p16_kit` 839-1196) |
| `src2/world/kit/objects.lua` | Kit objects plugin: kinds table, scan, effects, pushbox spawners, character forces, events `v2KE`, kit table (V2 `p16_kit` 541-627, 1197-1530) |
| `src2/platform/env.lua` | Modify: drop `VirtualInput`; add `Env.envOf` (computed name), features `kit` = getloadedmodules + iscclosure + envOf, `connections` already there |
| `src2/platform/camerascript.lua`, `src2/world/inputs.lua`, `src2/world/animation.lua` | Modify: V2.38.17 changes (Task 1) |
| `src2/engine/frame.lua`, `src2/engine/modes.lua`, `src2/engine/plugins.lua`, `src2/engine/timeline.lua`, `src2/persist/codec6.lua`, `src2/persist/persist.lua`, `src2/main.lua`, `src2/modules.txt` | Modify: new hooks, the PostSimulation handler, `save = false` columns, wiring |
| `tools/trace3.sh`, `tools/bench3.sh`, `tools/savebench3.sh`, `tools/test_all.sh`, `tools/test_all3.sh` | Modify: reference `aaa21b6`, world trace groups, the world scenario |
| `tests3/trace/world.lua`, `tests3/trace/adapter_v2.lua`, `tests3/trace/adapter_v3.lua` | The world trace scenario and its adapter functions |
| `tests3/test_plugins.lua`, `test_coregistry.lua`, `test_corecord.lua`, `test_coplay.lua`, `test_buttons.lua`, `test_lighting.lua`, `test_timecontrol.lua`, `test_humanoidclock.lua`, `test_kitclock.lua`, `test_kitobjects.lua`, `test_world.lua` | One suite per task |

**Plugin orders** (phase 2: character 10, camera 20, inputs 30, animation 40, tools 50), chosen so `fill` runs in V2.38.17's order (`p18_core.lua:1141-1161`: pose, state, animation, client objects, tools, buttons, lighting, coyote state) and every other hook in V2's order (client objects, buttons, lighting, kit): client objects 45, buttons 55, lighting 56, time control 57, kit clock 60, kit objects 61.

**Hook map** (V2.38.17 `p18_core.lua` line -> HappaTAS 3):

| V2 | HappaTAS 3 |
|---|---|
| `Invalidate` (44-46) | `onDataChanged` |
| `ShowFrame` (354-356), `RestoreUnpause` (359) | `onShowFrame(tl, i)`, `onRestoreUnpause(tl, i)` |
| `Lighting.Trim(C.frame)` (400) | **new** `onCut(tl, n)` in `Modes:removeCutFrames` after `onDataChanged` |
| `Release` (594-596, 934-936, 975-977) | `onRelease`; `EndPlayback` -> `onEndPlayback` |
| `Pause(0)` (625-626), `Pause(t)` (732-733, 761-762) | `onPause(t)`; `KitClock.Rewind` (731, 760) -> `onRewind(tl, n)`; `CoyoteReset` (584, 722, 756) -> `onRewind` / `onEndPlayback` / `onRelease` in the time plugin at the same three sites |
| `PlaybackBegin` (660-663) | `onPlaybackBegin` (client objects, speed > 0) / `onPlaybackBeginAlways` (buttons, lighting) |
| `BeginRecording`, `Resume`, `CoyoteRestore` (671-676) | `onBeginRecording(tl, n)` |
| `KitObjects.Unpause` (681) | `onUnpause(tl, n)` |
| `Reset`, `Lighting.Clear` (789-790) | `onReset`; `LoadFromData` (908-909) -> `onLoaded(tl)` |
| `SpeedHack.FrameStart` (1049) | **new** `onFrameStart()` first thing in `engine.preRender` |
| `StepTime` (1058), `SK`, `KitClock.Mark` (1088-1090) | `E.time:stepTime()` in the recording condition and `dtN`; `begin(tl, i)` (time: `v2SK`; kit clock: mark) |
| `SpeedHack.Update`, `timeRate`, `KitObjects.Frame`, `KitClock.SetRate` (1107-1130) | at the end of `engine.preRender`: `E.recScale = E.time:update(...)`, `E.cs.timeRate = E.time.anim`, `E.kitObjects:frame(...)`, `E.kitClock:setRate(...)` (by name, guarded) |
| `fill` 1152-1159 | `fill(tl, n)` in plugin order |
| `KitObjects.Reassert` (1165) | **new** `onPreSimulation(dt)` first thing in `engine.preSimulation` |
| `StepBegin`, `Humanoid.Pre` (1179-1184) | end of `engine.preSimulation`, by name |
| `postSimulation` (1187-1191) | **new** pipeline handler `engine.postSimulation` (PostSimulation 50), by name |
| `StepEnd` (1276), CO end / release (1281-1282) | first thing in `engine.heartbeat` by name; `onHeartbeatStart(mode)` |
| `CO.Tick` (1289), `Buttons.Step` (1298, 1310), `KitObjects.AfterPhysics` (1309) | `onPausedTick`, `onStep(t)`, `onAfterPhysics(tl, n)` |
| `PlaybackTo` (1214-1219, 1251-1253) | `onPlayTo(tl, f, t)` |
| `RenderStep`, `Reassert` (1346-1349) | `lateRender()` in plugin order |
| `ExportObjects` / `ExportKeys` / `KO.Export` (codec save) | **new** `onSave(tl)` in `Persist:save` before `Run.build` (fills `tl.meta.v2objects`, `v2buttons`, `v2kit`, `kitVersion`); import from `tl.meta` in `onLoaded(tl)` |

---

### Task 1: Catch up with V2.38.17

**Files:**
- Modify: `src2/platform/env.lua`, `src2/platform/camerascript.lua`, `src2/world/inputs.lua`, `src2/world/animation.lua`, `tools/trace3.sh`, `tools/bench3.sh`, `tools/savebench3.sh`, `tools/test_all.sh` (REF build only), `tests3/test_inputs.lua`, `tests3/test_camerascript.lua`

**Interfaces:**
- Produces: `E.anim:running(speed)` (V2.38.17 `p12_anim.lua`: `self.Running(speed)` -> `onRunning(speed)`, the walk animation's speed from the humanoid clock); `Env.VirtualInput` removed; the camera script scan uses `filtergc` only (no `getgc(true)` fallback: "filtergc unavailable; camera scan skipped" as a Debug note).

- [ ] **Step 1: Bring the branch up.** `git fetch origin && git merge --ff-only origin/main` on `v3-rewrite`. The working tree's uncommitted `src/parts/`, `tests/mock/`, `tests/test_*.lua`, `tools/*`, `wow`, `wow1` edits equal `aaa21b6`'s (check: `git diff --stat aaa21b6 -- src/parts tests tools wow wow1` prints nothing). If git refuses because the untracked `tests/test_nosound.lua` would be overwritten, compare it with `git show aaa21b6:tests/test_nosound.lua`; only if identical, ask dzr before removing the untracked copy. Expected: `v3-rewrite` at `6d1ced9`, `git status` shows only untracked `backups/` and this plan. Then commit this plan alone: `HappaTAS 3: phase 4 plan (world plugins)` (it was written before the fast-forward, so it couldn't be committed earlier).
- [ ] **Step 2: Move the reference.** `REF_COMMIT=aaa21b6` in `tools/trace3.sh` (delete `tests3/trace/ref/` so it rebuilds), the same commit in `bench3.sh` / `savebench3.sh` and `test_all.sh`'s `REF=1`. Run `bash tools/trace3.sh` — Expected: `DIFFERENT` only where V2.38.17 changed what phase 2 ported (key replay through `keypress` instead of VirtualInputManager in the `W.input` group; nothing else). Write down the differing groups.
- [ ] **Step 3: Write the failing tests.** `tests3/test_inputs.lua`: `keys replay through keypress only` (with a `VirtualInputManager` in the mock, `Up` / `Home` / `RightControl` replay as `keypress` calls with V2.38.17's scan codes and no `SendKeyEvent`); `tests3/test_camerascript.lua`: `no getgc fallback` (mock without `filtergc`, `getgc` present: the scan never calls `getgc`, cameras are found through the PlayerModule only); `tests3/test_animation.lua`: `running(speed)` sets the walk track speed like V2.38.17's `onRunning`.
- [ ] **Step 4: Run** each suite — Expected: FAIL on the new checks.
- [ ] **Step 5: Port** the V2.38.17 changes: `git diff b1569bd aaa21b6 -- src/parts/p01_env.lua src/parts/p09_bridge.lua src/parts/p10_inputs.lua src/parts/p12_anim.lua` is the whole list (the `p18_core.lua` coyote / PostSimulation part belongs to Task 9; sounds were already left out in phase 3).
- [ ] **Step 6: Run** the suites, `bash tools/trace3.sh` — Expected: `SAME`. If the only differences left are `State` / `Cframe` on the frames right after an unpause in the air, that is V2.38.17's coyote timer across a pause: **Ruling (decided now):** then Task 9's `humanoid.lua` coyote half (`coyoteState`, `coyoteRestore`, `coyoteReset`, the coyote part of `pre` / `post`) moves into this task, with its tests from Task 9 Step 1 `coyote across a pause`. `bash tools/test_all3.sh` and `REF=1 bash tools/test_all.sh` — Expected: `ALL PASSED` both.
- [ ] **Step 7: Commit** `HappaTAS 3: V2.38.17 is the reference (keys through keypress, filtergc-only camera scan)`.

---

### Task 2: Plugin plumbing

**Files:**
- Modify: `src2/engine/plugins.lua` (doc list), `src2/engine/frame.lua`, `src2/engine/modes.lua`, `src2/engine/timeline.lua`, `src2/persist/codec6.lua`, `src2/persist/persist.lua`, `src2/main.lua`
- Test: `tests3/test_plugins.lua`

**Interfaces:**
- Consumes: the phase 2 plugin registry and guard, phase 3's `Run.registerCarry`, `Codec6.encode / decode`.
- Produces:
  - Hooks `onFrameStart()`, `onPreSimulation(dt)`, `onCut(tl, n)`, `onSave(tl)` (sites in the hook map).
  - `tl:addColumn(name, kind, width, v2)` accepts `v2.save == false`: `Codec6.encode` skips such columns, `decode` never creates them; `toV2` / `replaceFromV2` still convert them (traces, merge).
  - Named, guarded plugin slots on the engine that default to no-ops until their task: `E.time` (`stepTime() -> nil`, `update(...) -> 1`, `anim = 1`, `frameStart()`, `stepBegin(dt)`, `stepEnd()`, `humanoidPre(dt, hum, root, scaled)`, `humanoidPost(dt, hum, root, recording)`), `E.kitObjects` (`frame(mode, tl, f, t, rec)`), `E.kitClock` (`setRate(r)`). `main.lua` registers the phase 4 plugins before `Run.registerCarry`.
  - Pipeline handler `engine.postSimulation` (PostSimulation, order 50): `E.time:stepEnd()`; `E.time:humanoidPost(dt, hum, hrp, recording)` with V2's `recording` condition.

- [ ] **Step 1: Write the failing tests** (`tests3/test_plugins.lua`):
  - `hook order`: a probe plugin at order 45 and one at 56 log every hook; one recorded / paused / unpaused / Test / Idle cycle gives V2.38.17's sequence (the sites in the hook map, listed literally in the test), `onCut` once with the frame cut to, `onSave` once per save.
  - `transient columns`: a `u8` column with `save = false` holds values while recording; after save + load it is absent (`tl.cols.X == nil` after decode) and the file is the same bytes as without the column.
  - `a plugin column replaces the carry column`: a probe registers `v2CO` (list, `{ key = "CO" }`) before `Run.registerCarry`; no second `v2CO`; phase 3's fixture `kitspeed.tas` loads its CO data into it; a v6 file saved by phase 3 (written in the test with phase 3's carry column) loads into it too.
  - `frame calls`: with a stub `E.time` whose `stepTime()` returns 0 the recording condition makes no frame; `update` returning 0.5 sets `E.recScale` 0.5 and the next frame's FrameTime is `round(dt x 0.5, 1e6)`; `engine.postSimulation` calls `stepEnd` then `humanoidPost` once per physics step.
- [ ] **Step 2: Run** `bash tools/build_test3.sh plugins && (cd tests3 && luau run_plugins.lua)` — Expected: FAIL.
- [ ] **Step 3: Implement** the hooks at their sites, the `save = false` flag, the default slots, the PostSimulation handler and the frame calls in V2.38.17's places (`p18_core.lua:1049`, `1058-1065`, `1107-1130`, `1165`, `1179-1191`, `1276`).
- [ ] **Step 4: Run** the suite, `bash tools/test_all3.sh` — Expected: pass / `ALL PASSED` (trace `SAME`: the default slots change nothing).
- [ ] **Step 5: Commit** `HappaTAS 3: hooks, transient columns and engine slots for the world plugins`.

---

### Task 3: Client object registry

**Files:**
- Create: `src2/world/co/registry.lua`
- Modify: `src2/modules.txt`
- Test: `tests3/test_coregistry.lua`

**Interfaces:**
- Produces: `Registry.new(E) -> R` with `R:keyOf(inst) -> string?` (V2 `keyOf`, `p13` 137-154), `R:idForKey(key, preferred) -> id`, `R.parts[id]`, `R.ids[part]`, `R.S[id]` (V2's per-part record state, `newRecState` fields unchanged), `R.plist`, `R:register(part)`, `R:unregister(part)`, `R:enable()` (DescendantAdded / Removing, the scan on its own thread: 1500 / 300 items between yields), `R:disable()`, `R:isReady()`, `R:eachPart(fn)`, `R:counts()`, `R:hold(part)` / `R:releasePart(id)` / `R:restorePart(part, was)` (V2 459-501), `R.reg = { keyToId, idToKey, nextId }`. Constants from `CONFIG.ClientObjects` with V2's defaults (`Radius 300`, `AlwaysRadius 30`, `MaxRegistered 8000`, `MaxWatched 30000`, ...).
- **Ruling:** the `Anchored` listener (V2 `watchProps`, 292-307) is connected only while HappaTAS holds the part (`R:hold`) and disconnected on release, so a registered part at rest has 5 change listeners instead of V2's 6 (spec 7: "fewer change listeners per part"). The lost-part rule (a game script un-anchors a held part) only matters while held, so behaviour is the same. Cost if wrong: none for recording; a missed un-anchor would show in the coplay tests.

- [ ] **Step 1: Write the failing tests:** `keys` (`Workspace/ClientObjects/P#2` for the second sibling named P, `/` and `#` in names become `_`, nil outside workspace, stable after a sibling is added); `candidates` (V2's `isCandidate` cases: an unanchored part, a part with a Constraint / BodyMover / a constraint attachment, `Beat` / `OnTransparency` attributes, `VanisherConfiguration`, a part in each `KIT_FOLDERS` folder, a name hint, a part inside a character, `HappaTASIgnore`, Terrain); `scan` (2000 parts: done over several frames, `isReady` after, status "Client objects ready (N parts)"); `watch` (an anchored non-candidate un-anchored later is registered); `listeners` (a registered part at rest: 5 connections; while held: 6; after release: 5); `limits` (`MaxRegistered` stops registering); `unregister` on DescendantRemoving drops every table entry; `disable` disconnects everything (mock connection count back to the start).
- [ ] **Step 2: Run** — Expected: FAIL (no module).
- [ ] **Step 3: Implement** by porting V2 `p13` 118-458 and 459-525 function by function into `Registry` (same names, `self` instead of upvalues where a field is shared with the recorder / player).
- [ ] **Step 4: Run** the suite and `bash tools/test_all3.sh` — Expected: pass / `ALL PASSED`.
- [ ] **Step 5: Commit** `HappaTAS 3: client object registry`.

---

### Task 4: Client object recorder

**Files:**
- Create: `src2/world/co/recorder.lua`, `src2/world/clientobjects.lua` (the plugin: recording half)
- Modify: `src2/main.lua`, `src2/modules.txt`, `tools/trace3.sh`, `tests3/trace/adapter_v2.lua`, `tests3/trace/adapter_v3.lua`
- Create: `tests3/trace/diffco.lua`
- Test: `tests3/test_corecord.lua`

**Interfaces:**
- Consumes: `Registry`; `E.recSim`, `E.recWall` (phase 2); the `v2CO` column rule (Task 2).
- Produces: `Recorder.new(E, R) -> rec` with `rec:beginRecording(tl, n)` (V2 `CO.BeginRecording`), `rec:skipSim(dt)`, `rec:record(playerPos, tNow, simNow, wallNow, tl, n) -> string?` (V2 `CO.Record`: the frame's record bytes or nil), `rec:invalidate()`. The plugin `ClientObjects` (`name = "clientobjects"`, order 45, `E.co`) with column `v2CO` (`list`, `{ key = "CO", keep = true }`), hooks `fill`, `onBeginRecording`, `onDataChanged`, `onReset`, `onSave` (`tl.meta.v2objects = exportObjects`), `onLoaded` (import), and `E.co:keyOf`, `eachPart`, `isReady`, `skipSim`, `ids(str, set)`, `exportObjects(tl)`, `importObjects(tl, objects)`.
- Trace: group `W.co` (every registered part's CFrame, transparency, can-collide, colour, size, material once per frame, sorted by key) and field `CO` (hex) in the `F` group; `SCENARIO=diffco` = V2's `tests/test_diffco.lua` (props on odd / even frames, a falling platform, parts destroyed / added / re-parented while recording and testing, Sync Client Objects off and on) driven through the adapters.

- [ ] **Step 1: Write the failing tests** (`tests3/test_corecord.lua`), ported from V2's `tests/test_coclock.lua` and `tests/test_cobase.lua` recording sections with their fixtures and expected values: `static parts cost nothing` (no record bytes for 300 frames of 20 still parts); `a spinner records every few frames` (record count within V2's for the same spinner); `clocks` (a physics part on clock 1, a script part on clock 3, a wall-clock part on clock 2: frame bytes 4 / 5 + 8 / 16 / 32 as V2); `full snapshots` every 2400 frames or 10 s, `+ 64` on the first of a new recording after cut frames; `start states` (cobase: a part first changed at frame 200 gets its start record in every full snapshot logged after its registration, frames loaded from a file are never touched); `the first change is a delta`; `skipSim` (Frame Step's held steps: clock 1 skips).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the recorder by porting V2 `p13` 512-1350 (`starts`, `computeKey`, clock fitness, `CO.Record`, `CO.BeginRecording`, `CO.SkipSim`, the byte writer through `persist/bytes`' varint / zigzag with V2's exact layout), and the plugin's recording half.
- [ ] **Step 4: Run** the suite; `SCENARIO=diffco TGROUPS="mode F W.co" FIELDS="CO" bash tools/trace3.sh` up to the first Test (`UPTO=test`) — Expected: `SAME` (byte-identical records, the same poses); `bash tools/test_all3.sh` — Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `HappaTAS 3: client object recorder (V2's records, frame for frame)`.

---

### Task 5: Client object player

**Files:**
- Create: `src2/world/co/player.lua`
- Modify: `src2/world/clientobjects.lua` (playback half), `tools/test_all3.sh` (the diffco trace)
- Test: `tests3/test_coplay.lua`

**Interfaces:**
- Consumes: `Registry`, `Recorder` (shared record state), the `v2CO` column.
- Produces: `Player.new(E, R) -> pl` with `pl:playbackBegin(tl, f)`, `pl:playbackTo(tl, f, t?)` (t nil = frame mode), `pl:tick()`, `pl:renderStep()`, `pl:endPlayback()`, `pl:showFrame(tl, f)`, `pl:restoreUnpause(tl, f)` (positions and velocities back, velocities / the frame's `SK`), `pl:release()`, `pl:isHolding()`, `pl:isTesting()`. The plugin's hooks `onPlaybackBegin`, `onPlayTo`, `onPausedTick`, `lateRender`, `onEndPlayback`, `onShowFrame`, `onRestoreUnpause`, `onRelease`, `onHeartbeatStart(mode)` (V2 1281-1282: end playback outside Test, release in Idle), settings `syncClientObjects` / `smoothClientObjects` / `frustumCullingCO` (on-screen within 25 studs, V2's `isVisible`).

- [ ] **Step 1: Write the failing tests** (ported from `tests/test_coclock.lua` playback sections): `half way between frames` (playback at the midpoint vs the truth logged while recording: worst error 0.0007 at 1x, 0.001 at 0.5x, V2's numbers); `over a cut and full snapshots` (no 1-frame jumps); `v1 / v2 / v3 data` (records written by V2's own recorder in the mock for each version: the same poses as V2's player); `held parts a game script lets go` (`lost`: anchored again on their pose next pass); `showFrame / restoreUnpause` (parts on the recorded pose with the recorded velocity / SK); `release on Idle and on Disable` (Anchored and velocities back); `checkpoints` (seek to frame 4000 of 5000 reads at most V2's number of records); `frustum culling` (only parts within 25 studs written).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** by porting V2 `p13` 1350-1874 (decoders, `computeNext`, checkpoints `CK 120 / MAX_CK 64`, `fixLost`, `restoreHeld`, `IdsOf`, Export / Import).
- [ ] **Step 4: Run** the suite; `SCENARIO=diffco TGROUPS="mode F W.co" FIELDS="CO Cframe" bash tools/trace3.sh` (whole scenario) — Expected: `SAME`. Add that run to `test_all3.sh` (`diffco trace: SAME`). `bash tools/test_all3.sh` — Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `HappaTAS 3: client object playback`.

---

### Task 6: Timed buttons

**Files:**
- Create: `src2/world/buttons.lua`, `src2/world/buttontimers.lua`, `tests3/trace/world.lua` (first part: buttons)
- Modify: `src2/main.lua`, `src2/modules.txt`, `tests3/trace/adapter_v2.lua`, `tests3/trace/adapter_v3.lua`, `tools/trace3.sh`
- Test: `tests3/test_buttons.lua`

**Interfaces:**
- Consumes: `E.co:keyOf` (ids by workspace path, like V2's `keyOf` with `ClientObjects.KeyOf`).
- Produces: plugin `Buttons` (`name = "buttons"`, order 55, `E.buttons`), column `v2BT` (`list`, `{ key = "BT", keep = true }`), hooks `fill` (`RecordFrame(tNow, first)`), `onStep(t)`, `lateRender`, `onShowFrame`, `onUnpause` -> V2 `Resume` (from `onBeginRecording`, V2 673), `onPause(t)`, `onPlaybackBeginAlways`, `onPlayTo`, `onReset`, `onRelease`, `onDataChanged`, `onSave` (`tl.meta.v2buttons`), `onLoaded`; `E.buttons:count()`. `ButtonTimers.new(E) -> ui` with V2's label functions (`updateTimerUI(b, remaining, allowCreate)`, `hideTimerUI(b)`, `restoreButtonVisual(b, pressed)`, `clearOurLabels(b)`) — the kit's own timer labels, not HappaTAS's interface. Setting `syncButtonTimers`.
- Trace: group `W.bt` (each button's `Pressed`, `TimerStart` relative to the TAS clock, label text, once per frame); scenario `world.lua` part A: an EToH-kit button stand-in (BoolValue `Pressed`, NumberValue `TimerStart`, a `ButtonPart`, the kit's Heartbeat release loop as a `loadstring` stand-in like V2's `tests/test_kit.lua`) pressed while recording, paused 2 s, scrubbed back and forward, tested at playback speed 1 and 2.

- [ ] **Step 1: Write the failing tests:** `press recorded` (frame, elapsed time, `BT` event bytes equal V2's in the same mock run); `paused freezes the timer` (`TimerStart` moves with real time so the remaining time stays); `scrubbing` (remaining time = timer - TAS time since the press on every frame shown); `Test` (released at the TAS time it was released when recording, at speed 1 and 2); `keys export / import` (ids survive save + load); `release` (Idle: `TimerStart` back on `os.clock`, labels back to the kit's); `off mid-recording` (released, events kept).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** by porting V2 `p14` 12-1811 (buttons.lua: registry, events, seek / flush, the plugin; buttontimers.lua: 127-1096).
- [ ] **Step 4: Run** the suite; `SCENARIO=world TGROUPS="mode F W.bt" FIELDS="BT" bash tools/trace3.sh` — Expected: `SAME`. `bash tools/test_all3.sh` — Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `HappaTAS 3: timed buttons on the TAS clock`.

---

### Task 7: Lighting

**Files:**
- Create: `src2/world/lighting.lua`
- Modify: `src2/main.lua`, `src2/modules.txt`, `tests3/trace/world.lua` (part B), adapters
- Test: `tests3/test_lighting.lua`

**Interfaces:**
- Produces: plugin `Lighting` (`name = "lighting"`, order 56, `E.lighting`), column `LT` (`list`, `{ key = "LT", save = false }`), hooks `fill` (`RecordFrame(n, tNow, first)`), `onShowFrame`, `onCut` (`Trim`), `onPause`, `onBeginRecording` (`Resume`), `onPlaybackBeginAlways`, `onPlayTo`, `lateRender`, `onReset` (`Clear`), `onLoaded` (`LoadFromData`), `onRelease` (control none, lighting left as it is: V2.38.14's rule, Idle does not reset it); setting `syncLighting` (off / Unload: the lighting from before the TAS, V2's `Disable`). V2's property lists `L_NUM`, `L_COL`, `EFF_DEF` exactly.
- Trace: group `W.lt` (Lighting's numbers / colours and each effect's properties per frame); `world.lua` part B: a light changer stand-in changes `ClockTime`, `FogColor`, a `ColorCorrectionEffect` and adds a `BloomEffect` mid-recording; pause, scrub, Test, Idle.

- [ ] **Step 1: Write the failing tests:** `snapshot only on change`; `scrub and Test show the frame's lighting`; `cut frames trim the timeline`; `Idle leaves the lighting as it is`; `Sync Lighting off puts back the lighting from before the TAS`; `not saved` (a saved and reloaded run has no LT; Test after reload keeps the game's current lighting, V2's behaviour).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** by porting V2 `p14` 1812-2052.
- [ ] **Step 4: Run** the suite; `SCENARIO=world TGROUPS="mode F W.bt W.lt" FIELDS="BT" bash tools/trace3.sh` — Expected: `SAME`. `bash tools/test_all3.sh` — Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `HappaTAS 3: lighting`.

---

### Task 8: Time control: Smooth and the world

**Files:**
- Create: `src2/world/time/control.lua`, `src2/world/time/world.lua`
- Modify: `src2/main.lua`, `src2/modules.txt`, `src2/engine/modes.lua` (the `toggleSpeedHack` status line), `tests3/trace/world.lua` (part C), adapters
- Test: `tests3/test_timecontrol.lua`

**Interfaces:**
- Consumes: Task 2's `E.time` slot (this task replaces the no-op), `E.co:eachPart`, the animation plugin's speed hack fields from phase 2 (`src2/world/animation.lua`: `E.anim.rate` = V2's `SpeedHack.anim`, `E.anim.physScale` = V2's `SpeedHack.scale`, `E.anim:rescale()` when the factor changes, `E.anim:gameDt(dt)` which this task makes return `E.time:gameDt(dt)`).
- Produces: plugin `TimeControl` (`name = "time"`, order 57, `E.time`) with V2's names: `wanted() -> s` (0.1-4, `|s - 1| < 0.001` = off), `update(recording, hum, root, keepMomentum) -> recScale`, `restore(keepMomentum)`, `.scale`, `.anim`, `gameDt(dt)`, `frameStart()`, and the world `World.new(E)` (`track()`, `setFactor(f)`, `step()`, `factor()`, `count()`, `kick(dy)`: TIME_PROPS per class power 1 / 2, `e.writing` guard, game writes adopted, conveyors re-adopted every frame, free assemblies x ratio, `KIT_CONFIG = { BouncePadConfiguration = { Power = 1 }, SwingConfiguration = { Boost = 1 } }` found with `filtergc("table", { Keys = { "__instance", "__defaults" } })`); column `v2SK` (`list`, `{ key = "SK", keep = true }`) set in `begin`; status "Speed Hack 0.5x" / "Speed Hack Off" on the toggle (V2's text).
- Trace: `world.lua` part C: walk, jump and a spinner / conveyor / free box / bounce pad stand-in recorded at 0.5x and at 2x (Smooth), each tested; groups `W.char`, `W.co`, `W.time` (gravity, WalkSpeed, JumpPower, each scaled constraint value, bounce pad Power, per frame).

- [ ] **Step 1: Write the failing tests** (ported from V2's `tests/test_speedhack.lua` Smooth sections, same mock humanoid model and numbers): `a slow recording equals a normal one` (frames dt x s, exactly), `gravity x s^2, WalkSpeed / JumpPower x s, JumpHeight untouched`, `game writes adopted`, `momentum on start / change / stop`, `paused, Idle, Test, dead: normal values`, `world scaling` (hinge -0.75 at 0.5x, conveyor x s, AlignPosition Responsiveness x s, VectorForce x s^2), `bounce pad Power x s while slowed, back after`, `fast motion 2x`, `toggle key + status`, `unload restores` (momentum kept).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** by porting V2.38.17 `p16_speedhack` 30-420 and 512-621.
- [ ] **Step 4: Run** the suite; `SCENARIO=world TGROUPS="mode F W.char W.co W.time" FIELDS="FrameTime TotalTime Cframe Velocity SK CO" bash tools/trace3.sh` — Expected: `SAME`. `bash tools/test_all3.sh` — Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `HappaTAS 3: time control (Smooth) and the world in slow motion`.

---

### Task 9: Time control: Frame Step and the humanoid clock

**Files:**
- Create: `src2/world/time/framestep.lua`, `src2/world/time/humanoid.lua`
- Modify: `src2/world/time/control.lua`, `tests3/trace/world.lua` (part D), adapters
- Test: `tests3/test_humanoidclock.lua`

**Interfaces:**
- Consumes: `E.co:skipSim`, `E.kitClock:advance(d)` (a no-op until Task 10), `E.anim:running(speed)` (Task 1).
- Produces on `E.time`: `stepTime() -> number?`, `stepping() -> bool`, `stepDt()`, `stepBegin(dt)`, `stepEnd()` (V2 `FS`: acc += s, run when acc >= 1, starts at 1 - s; a held step anchors the HRP and every free world assembly root, saving velocities; rescans every 30 held steps); `humanoidPre(dt, hum, root, scaled)`, `humanoidPost(dt, hum, root, recording)`, `coyoteState() -> {off, jumped}?`, `coyoteRestore(state)`, `coyoteReset(hum)` (V2.38.17 `HC`: `STEP 1/240`, `GAIN 0.625`, walk caps, `TURN_A 0.58312`, `TURN_B 10/3`, `TURN_AIR 1`, `COYOTE 0.13`, `GRACE 0.125`, gravity clamp 1000); column `CY` (`list`, `save = false`) set in `fill`; hooks for `coyoteReset` / `coyoteRestore` at the hook map's sites.

- [ ] **Step 1: Write the failing tests** (ported from V2.38.17's `tests/test_speedhack.lua` Frame Step and humanoid sections, the mock's `robloxStep` rules): `Frame Step 0.5x / 0.25x recording = the 1x recording frame by frame`; `nothing held outside the physics step`; `kit clock advanced per step that ran`; `walking on the game clock` (stop slide 0.147 at 0.5x / 2x / 4x), `jump 7.27 studs at every speed`, `170-degree turn 0.343-0.350 s`, `coyote per Roblox's rule` (edge sweep), `coyote across a pause` (1x and 0.5x, 5 s pause), `gravity above the clamp`, `speed changed mid-recording` (Review Focus 5: 0.5 Smooth -> 2 -> Frame Step 0.25 -> off, a pause inside a held step: normal values, nothing anchored, TotalTime continuous).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** by porting V2.38.17 `p16_speedhack` 420-511 and 622-1028, and the frame calls Task 2 left as slots (Frame Step's record gating, `stepBegin` / `humanoidPre` / `stepEnd` / `humanoidPost`).
- [ ] **Step 4: Run** the suite; `SCENARIO=world TGROUPS="mode F W.char W.co W.time" FIELDS="FrameTime TotalTime Cframe Velocity State SK CO" bash tools/trace3.sh` with part D (Frame Step 0.5x / 0.25x, coyote at an edge, 2x) — Expected: `SAME`. `bash tools/test_all3.sh` — Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `HappaTAS 3: Frame Step and the humanoid on the TAS clock`.

---

### Task 10: Kit Clock

**Files:**
- Create: `src2/world/kit/clock.lua`
- Modify: `src2/platform/env.lua` (`envOf`, feature `kit`), `src2/main.lua`, `src2/modules.txt`, `tests3/trace/world.lua` (part E), adapters
- Test: `tests3/test_kitclock.lua`

**Interfaces:**
- Consumes: `E.time:stepping()`, `E.time:stepDt()`; `Env.envOf`, `Env.getloadedmodules`, `Env.iscclosure`, `Env.setreadonly`, `Env.getconnections`.
- Produces: plugin `KitClock` (`name = "kitclock"`, order 60, `E.kitClock`): `now()`, `setRate(r)`, `advance(d)`, `frameDt(dt)`, `waiting()`, `isEnabled()`, `.patched`, `.rate`; hooks `begin` (`mark(tl, i)`), `onRewind(tl, n)` (back to the last recorded frame's kit time: never forward, never more than 1 s, the same timeline only), its own Heartbeat handler (pipeline, order 40: `step` resumes waits once due and at least one frame later), the frame listeners (`runFrame("Heartbeat" / "PostSimulation")` while the rate isn't 1: kit listeners found with `getconnections` are disabled and called with `frameDt(dt)`; `SKIP_FRAME = { Morpher, DistanceCulling }`; enabled again at 1x / disable / Unload), `SKIP_CLOCK = { Button = true }`, the tween helper (`Utility.Functions.tween` -> `kitTween`), rescans 2 s doubling to 30 s. Setting `kitScriptsOnTasClock`.
- `Env.envOf(f) -> table?`: the function's environment through the computed-name lookup (Global Constraints), nil when missing or when `f` is a C closure.

- [ ] **Step 1: Write the failing tests** (ported from V2's `tests/test_kit.lua` Kit Clock sections, kit modules as `loadstring` stand-ins with their own environments, `M.modules`, `getloadedmodules`): `waits on the TAS clock` (paused: no wake; 0.5x: twice as long in real time; Test speed 2: half); `rewind on pause`; `tweens` (kit tween at 0.5x reaches the goal at twice the real time, `RepeatCount` / `Reverses` go to the original); `frame listeners` (a kit Heartbeat listener gets dt x rate, Morpher left alone, re-enabled at 1x); `unload` (environments get their own task / os back, waits finish in real time, tweens jump to the end, listeners enabled); `no executor support` (Review Focus 4: without `getconnections` / `getloadedmodules` / `envOf`: switched off, a Debug note, no error); `deopt guard` (the build has no literal `getfenv(` / `setfenv(`: `tools/test_all3.sh` still prints `deopt guard: clean`).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** by porting V2 `p16_kit` 1-540 (`envOf` through `Env.envOf`).
- [ ] **Step 4: Run** the suite; `SCENARIO=world TGROUPS="mode F W.kit" bash tools/trace3.sh` with part E (a moving platform stand-in that waits, a launcher push, paused and 0.5x) — Expected: `SAME`. `bash tools/test_all3.sh` — Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `HappaTAS 3: the EToH kit's scripts on the TAS clock`.

---

### Task 11: Kit objects

**Files:**
- Create: `src2/world/kit/beats.lua`, `src2/world/kit/turrets.lua`, `src2/world/kit/objects.lua`
- Modify: `src2/main.lua`, `src2/modules.txt`, `tests3/trace/world.lua` (part F), adapters, `tools/test_all3.sh` (the world trace)
- Test: `tests3/test_kitobjects.lua`

**Interfaces:**
- Consumes: `E.co:keyOf`, `E.kitClock:now()`, `E.time:stepping()`.
- Produces: plugin `KitObjects` (`name = "kitobjects"`, order 61, `E.kitObjects`): `frame(mode, tl, f, t, rec)` (replaces Task 2's slot), `reassert()` (hooks `onPreSimulation` and `lateRender`), `afterPhysics` (hook `onAfterPhysics`), `onUnpause`, `onRelease`, `onDataChanged`, `onSave` (`tl.meta.v2kit`, `tl.meta.kitVersion` = `KO.CURRENT` set at a run's first recorded frame), `onLoaded` (import; a file without the kit table -> version 0, kit objects off for it), `versionOf(tl)`, `counts()`; column `v2KE` (`list`, `{ key = "KE", keep = true }`); kinds table `CONFIGS` / `TAGS` (beat blocks, turrets, pushbox spawners, bounce pads, jump launchers `LauncherConfiguration`, morphers left to client objects); setting `syncKitObjects`.
- `Beats` (V2 628-838: `beatAt(g, t)`, original sizes / materials from the kit's own tables through `filtergc`, dirty groups only, the ding muted and played on HappaTAS's beat); `Turrets` (V2 839-1196: events `{1, turretId, seq, pos, rot, vel, life}` / `{2, seq, dmg}`, stripped copies under `Camera.HappaTASKit`, Blockcast + overlap, damage through `task.spawn(pcall, ...)`).

- [ ] **Step 1: Write the failing tests** (ported from V2's `tests/test_kit.lua` kit object sections): `beat blocks follow TAS time` (recording, paused, Test: the active group and indicator for every frame match `beatAt`); `turrets` (bullets recorded as events, the kit's bullet destroyed, the copy where `pos + v (t - tFire)` says, a hit deals damage once, Test replays fire sounds and damage); `pushbox spawns` (hidden before their first spawn); `effects` (event 4 on the frame a bounce pad / launcher plays, Test plays HappaTAS's copy and mutes the kit's); `character forces` (disabled in Test, destroyed when unpausing before their frame); `v5 kit data loads and plays like V2`; `no kit` (Review Focus 4: a place without kit objects: no scans after the first, nothing created).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** by porting V2 `p16_kit` 541-1530.
- [ ] **Step 4: Run** the suite; `SCENARIO=world TGROUPS="mode F W.char W.co W.bt W.lt W.time W.kit" FIELDS="FrameTime TotalTime Cframe Velocity State SK CO BT KE" bash tools/trace3.sh` (every part A-F) — Expected: `SAME`. Add it to `test_all3.sh` (`world trace: SAME`). `bash tools/test_all3.sh` — Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `HappaTAS 3: EToH kit objects (beat blocks, turrets, pushboxes, effects)`.

---

### Task 12: The world together

**Files:**
- Modify: `tests3/trace/bench.lua`, `tools/bench3.sh` (if a scenario option is needed), `tools/test_all3.sh`, `docs/superpowers/specs/2026-10-18-happatas3-rewrite-design.md` (13: notes)
- Test: `tests3/test_world.lua`

**Interfaces:**
- Consumes: every phase 4 plugin.

- [ ] **Step 1: Write the failing tests** (`tests3/test_world.lua`), Review Focus 1-3: `unload in every state` (recording with 50 client objects held and 0.5x Smooth; paused inside a held Frame Step step; Test with two bullets in the air: after Unload no part anchored by HappaTAS, each part's velocity back, gravity / WalkSpeed / JumpPower / every tracked constraint / bounce pad Power at their base values, kit environments' `task` / `os` the originals, the tween helper the original, no disabled kit listener, every button's `TimerStart` following `os.clock`, Lighting as before the TAS, `Camera.HappaTASKit` gone, the mock's connection count back to the start); `settings mid-run` (each of the ten settings off and on while recording, paused and in Test: released at once, the timeline's columns unchanged, on again picks up at the current frame); `a V2 file with everything` (phase 3's `kitspeed.tas` and `objbuttons.tas` fixtures: Test plays the same poses / button states / beats as V2 plays them in the same mock, saved as v6 and loaded again: `v2CO` / `v2BT` / `v2KE` / `v2SK` byte-identical, `tl.meta.v2objects` / `v2buttons` / `v2kit` equal).
- [ ] **Step 2: Run** — Expected: FAIL only where a plugin misses something; fix in the plugin that owns it (each fix with its own failing check first).
- [ ] **Step 3: Bench.** Extend `tests3/trace/bench.lua` with 100 client objects (Sync Client Objects on, 20 moving), a beat block group, a turret and the speed hack at 0.5x in one recording phase. Run `bash tools/bench3.sh` — Expected: `BENCH OK` (HappaTAS 3 no slower than V2.38.17 in any mode, spec criterion 4).
- [ ] **Step 4: Run** `bash tools/test_all3.sh` and `REF=1 bash tools/test_all.sh` — Expected: `ALL PASSED` both (traces: main, diffco, world `SAME`).
- [ ] **Step 5: Commit** `HappaTAS 3: world plugins together (unload, settings, V2 files, bench)`.

---

### Task 13: Live check

**Files:**
- Modify: `docs/superpowers/specs/2026-10-18-happatas3-rewrite-design.md` (13: live numbers)

- [ ] **Step 1: Prepare** (Global Constraints' live rules): back up `Settings.json`, `Settings3.json` and the place's `.tas` files, record `getfpscap()`, release build (`bash tools/build3.sh`, `wow3`) copied to `HappaTasTest/`.
- [ ] **Step 2: Check in the EToH kit test place** (place 72164126024589, driven through `E.modes` + `Humanoid:Move`, keys through `keypress`): Sync Client Objects on, record the spinning kill brick and the Pushing Platform area for 5 s, pause 3 s, Test (client object playback vs the recording: worst error under 0.002 studs); a timed button pressed, paused, tested (released at the recorded TAS time); a lighting changer (kept on Idle); beat blocks and a turret for 10 s (0 wrong frames in recording / paused / Test, a hit damages once); speed hack 0.5x Smooth and Frame Step 0.5x (jump 7.27 studs, Test real time = TAS time); save as v6, load, Test again (the same); per-frame cost per mode with the HappaTAS timer (no higher than V2.38.17's live numbers in `CLAUDE.md`); Unload (no console lines, nothing left: the kit envs restored, no anchored parts).
- [ ] **Step 3: Clean up**: test files and `HappaTasTest` deleted, `Settings.json` / place files byte-identical to the backup, `Settings3.json` as before, the fps cap put back, rejoin if anything in the place changed.
- [ ] **Step 4: Write** the numbers into spec 13 and commit `HappaTAS 3 phase 4: live check`.
