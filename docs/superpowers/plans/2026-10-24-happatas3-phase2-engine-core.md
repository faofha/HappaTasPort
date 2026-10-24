# HappaTAS 3 Phase 2 (Engine Core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** HappaTAS 3 records and replays a run (character, camera, inputs, animations, tools, death) with Idle / Create / Test and every key control, frame for frame the same as V2.38.16 in the headless mock.

**Architecture:** A column timeline (Luau `buffer`s for numbers, sparse lists for rare data) holds the frames. A mode machine owns every transition; a frame module registers the engine's handlers in the kernel pipeline and calls the world plugins (character, camera, inputs, animation, tools) through one contract, in V2's order. A trace harness runs one scripted session on V2.38.16 and on HappaTAS 3 and diffs the results; each plugin task turns on its own fields and groups in that diff.

**Tech Stack:** Luau, bash + python3 build scripts, the headless mock (`tests/mock/`), `luau` CLI, the phase 1 kernel (`src2/kernel/*`, `src2/platform/*`).

**Spec:** `docs/superpowers/specs/2026-10-18-happatas3-rewrite-design.md` (sections 1 criteria 1, 4, 5; 4; 5; 7 (shared interface); 10; 11; 12 phase 2). Phase 1 plan: `docs/superpowers/plans/2026-10-19-happatas3-phase1-skeleton.md`.

## Global Constraints

- Everything in the phase 1 plan's Global Constraints still holds (Luau syntax, no network code, sUNC lookups with fallbacks, game code only through `GameCall`, Debug output only with `CONFIG.Debug`, version `"3.0.0-dev"`, commit rules, never commit `CLAUDE.md` / `claude/`).
- **Reference build = V2.38.16 = `src/parts/` at commit `b1569bd`** (merge of PR #13). Never use the working tree's `src/parts/`, `wow` or `wow1`: other sessions and dzr edit them. Changes dzr made after `b1569bd` are handled in Task 12, not before.
- Do not edit `src/parts/`, `wow`, `wow1`, `tests/test_*.lua`. Additions to `tests/mock/` are allowed (shared with V2): every V2 suite must still pass on the reference build afterwards (`REF=1 bash tools/test_all.sh` from Task 3).
- Frame values are rounded exactly like V2: `round(n, 1000)` for positions, rotations, velocities, zoom; `round(n, 1000000)` for FrameTime / TotalTime; `-0` becomes `0` (V2 `r()`, `p01_env.lua:201`).
- Frame handlers never yield. V2's waiting transitions (`noJumpOneFrame`, `Unpause1F`'s RenderStepped waits, the status-text fades) become frame countdowns run at the start of PreRender (order 0), which is where V2's waiting threads resumed relative to HappaTAS's own handlers.
- Default settings and keys are V2.38.16's (`p02_settings.lua`), with V2 names kept in the schema for phase 3's conversion.
- Tools on this PC: put a Claude scratchpad `bin/` with the `luau` and `python3` wrappers on PATH (copies exist in earlier session scratchpads, `.../scratchpad/tools/{luau,python}`); bash is Git Bash.

## Review Focus

1. The character dies mid-recording and respawns (Record Death & Respawn on: the timeline continues on the new character; off: the last frame is dropped and HappaTAS goes Idle). Test in Task 4.
2. A transition key pressed twice within V2's 3-frame debounce (`DoubleInput`), or Pause and Unpause on the same Left Click: exactly one transition runs. Test in Task 4.
3. Test on a 2-frame TAS, Test with `Restart When Testing` off from the middle, and Playback Speed below 0 (V2 starts from the end and runs backwards). Test in Task 4 (trace scenario covers speed 2 and -1).
4. Unload in each mode (recording, paused, Test): the root unanchored, AutoRotate and Jumping back on, camera type Custom, mouse behaviour and the camera script's functions restored, no held input left down. Test in Task 11.
5. Replay with the Roblox window not focused, and an executor without `keypress` / VirtualInputManager / `mousemoveabs`: keys are pressed once the window is active again, a missing function turns that replay off without errors. Test in Task 7.

---

## File Structure

| File | Responsibility |
|---|---|
| `src2/engine/util.lua` | `round(n, d)`, `clamp(v, lo, hi)`, `toTime(t)` (V2 `C.ToTime`), `ZERO3` |
| `src2/engine/keys.lua` | Key names ↔ Roblox enums (V2 `p03_keys.lua`) |
| `src2/engine/settings.lua` | Settings schema (39 rows) + in-memory store with change listeners |
| `src2/engine/controls.lua` | The 17 controls, default keys, `matches(input, control)` |
| `src2/platform/typing.lua` | `Typing.active(input)` (V2 `p01_env.lua:167-200`) |
| `src2/engine/timeline.lua` | Column timeline, V2 frame conversion, optimize |
| `src2/engine/plugins.lua` | Plugin registry and ordered calls |
| `src2/engine/modes.lua` | Mode machine: every transition, debounce, deferred steps, status messages |
| `src2/engine/frame.lua` | Pipeline handlers: what records / plays in each stage (V2 `p18_core.lua:1043-1339`) |
| `src2/engine/merge.lua` | Merge two runs (V2 `p18_core.lua:846-913, 1487-1514`) |
| `src2/world/character.lua` | Root pose, velocities, state, anchoring, death, respawn, coyote / ladder rules |
| `src2/platform/camerascript.lua` | The game's camera module: find, patch, zoom, shift lock, mouse behaviour, ghost (V2 `p09_bridge.lua`) |
| `src2/world/camera.lua` | Camera columns, posing the camera, paused / Test mouse rules |
| `src2/world/inputs.lua` | Keyboard / mouse recording and replay (V2 `p10_inputs.lua`) |
| `src2/world/animation.lua` | The R6 Animate engine, recorded per frame (V2 `p12_anim.lua`) |
| `src2/world/tools.lua` | Tool events and state replay (V2 `p15_tools.lua`) |
| `src2/kernel/pipeline.lua` | Modify: add the `Heartbeat` stage |
| `src2/main.lua`, `src2/modules.txt` | Modify: build and start the engine |
| `tools/trace3.sh`, `tests3/trace/scenario.lua`, `tests3/trace/adapter_v2.lua`, `tests3/trace/adapter_v3.lua` | Trace parity against V2.38.16 |
| `tests3/test_settings.lua`, `test_timeline.lua`, `test_modes.lua`, `test_character.lua`, `test_camerascript.lua`, `test_camera.lua`, `test_inputs.lua`, `test_animation.lua`, `test_tools.lua`, `test_merge.lua`, `test_engine.lua` | One suite per task |

Build outputs to add to `.gitignore`: `tests3/trace/ref/`, `tests3/trace/out_*.txt`, `tests3/trace/run_*.lua`.

**Plugin contract** (spec section 7, split where V2 records in two stages; every field optional):

```lua
-- plugin = { name = "camera", order = 20, columns = { {name, kind, width, v2key}, ... },
--   enter(mode, ctx), leave(mode, ctx),          -- mode: "Idle" | "Paused" | "Recording" | "Testing"
--   begin(tl, i),                                -- PreRender: frame i was just appended
--   fill(tl, i),                                 -- PreSimulation (or Heartbeat without a physics step)
--   show(tl, i, how),                            -- world on frame i while paused; how = { unpausing, backtrack }
--   playTo(tl, i, t, ctx),                       -- Test: frame i, playback time t
--   afterPhysics(tl, i), lateRender(ctx), unload() }
```

Orders: character 10, camera 20, inputs 30, animation 40, tools 50 (phase 4 plugins slot in between, V2 order: client objects, buttons, lighting after camera). Ruling recorded in the plan: `record(frame)` from the spec is `begin` + `fill`, because V2 takes camera / inputs / time in PreRender and the character's pose in PreSimulation.

---

### Task 1: Util, keys, settings, controls, typing

**Files:**
- Create: `src2/engine/util.lua`, `src2/engine/keys.lua`, `src2/engine/settings.lua`, `src2/engine/controls.lua`, `src2/platform/typing.lua`
- Modify: `src2/modules.txt`
- Test: `tests3/test_settings.lua`

**Interfaces:**
- Produces: `Util.round(n, d) -> number`, `Util.clamp`, `Util.toTime(t) -> "m:ss.sss"`; `Keys.toKey[name] -> EnumItem`, `Keys.fromKey[item] -> name`; `Settings.new(errs) -> s` with `s:get(key)`, `s:on(key) -> bool`, `s:set(key, v) -> bool` (sanitised, listeners only on change), `s:changed(key, fn) -> off`, `Settings.SCHEMA` (rows `{ key, v2, section, kind, default, min, max, integer, nonzero }`), `Settings.byV2[v2name] -> row`; `Controls.new(settings) -> c` with `c:get(control) -> keyName`, `c:set(control, keyName)`, `c:matches(input, control) -> bool`, `Controls.LIST` (17 rows `{ key, v2, default }`); `Typing.new(life) -> t` with `t:active(input) -> bool`, `t:watch(textBox)`, `t.rebinding`, `t.boundInput`.

- [ ] **Step 1: Write the failing tests** (`tests3/test_settings.lua`):
  - `every V2 setting is in the schema`: 39 rows; the multiset of `v2` names equals V2's `SettingsTable` names (listed literally in the test); every `key` unique; `byV2["Lock Camera (Test)"].key == "lockCameraTest"`.
  - `defaults are V2's`: e.g. `playbackSpeed 1`, `ignoreGameProcessed 0`, `speedHackSpeed 0.5`, `statsTextSize 11`, `soundVolume 50`, `syncClientObjects 0`.
  - `sanitise`: toggle 5 → 1; `speedHackSpeed` 9 → 4, 0.01 → 0.1; `statsTextSize` 11.6 → 12; `playbackSpeed` 0 refused (`set` returns false, value unchanged); NaN / inf refused.
  - `listeners`: called once per change, not on an equal value; a listener that errors is reported once, others still run.
  - `controls`: 17 rows, defaults `idle "1"`, `create "2"`, `test "3"`, `pause / unpause "Left Click"`, `forward "T"`, `back "R"`, `forward1 "G"`, `back1 "F"`, `unpause1 "V"`, `return "E"`, `lookAround "L"`, `optimize "Q"`, `deleteTas "Backspace"`, `menu "M"`, `microProfiler "F6"`, `toggleSpeedHack "None"`; `matches` for a key, Left Click, and `"None"` (never matches).
  - `typing` (ported from `tests/test_typing.lua` sections 2-5): own box focused, a game TextBox focused, chat bar focused, Roblox menu open → `active` true; `rebinding` and `boundInput` → true; otherwise false.
- [ ] **Step 2: Run** `bash tools/build_test3.sh settings && (cd tests3 && luau run_settings.lua)` — Expected: FAIL (`HappaTAS3: no module engine/settings`).
- [ ] **Step 3: Implement** the five modules. Key names: the 39 setting keys are the camelCase of the V2 names (`lockCameraTest`, `interpolatePlayback`, `playbackSpeed`, `restartWhenTesting`, `showCompletionMessage`, `lockCameraPaused`, `recordDeath`, `recordTools`, `ignoreGameProcessed`, `speedHack`, `speedHackSpeed`, `speedHackFrameStep`, `replayKeyboard`, `replayMouseClicks`, `replayMouseMovement`, `normalizeMouseUV`, `nohboardCursor`, `invisibleMouseSpeed`, `windowGuarding`, `syncClientObjects`, `smoothClientObjects`, `frustumCullingCO`, `syncButtonTimers`, `syncLighting`, `kitScriptsOnTasClock`, `syncKitObjects`, `showStatsIdle`, `showStatsCreate`, `showStatsTest`, `statsTextSize`, `showMicroProfiler`, `microProfilerScale`, `microProfilerTextOffset`, `allowPlayerGuiInterface`, `keyboardSounds`, `clickSounds`, `soundTriggerMode`, `soundVolume`, `dynamicPitch`); control keys as in Step 1. Sanitise = V2 `Settings.Sanitize`. Typing watches TextChatService / GuiService through `Env.svc`, connections owned by the given lifecycle.
- [ ] **Step 4: Run** the suite — Expected: `RESULT N passed, 0 failed`; `bash tools/test_all3.sh` — Expected: `ALL PASSED`.
- [ ] **Step 5: Commit** `HappaTAS 3: settings schema, controls, key names, typing check`.

---

### Task 2: Timeline

**Files:**
- Create: `src2/engine/timeline.lua`
- Test: `tests3/test_timeline.lua`

**Interfaces:**
- Consumes: `Util.round`.
- Produces: `Timeline.new() -> tl`; `tl:addColumn(name, kind, width, v2)` with kind `"f64"` (dense, `width` numbers a frame), `"u8"` (dense, width 1), `"list"` (sparse: any Lua value or nil a frame); `v2 = { key = "Cframe" } | { key = "Velocity", sub = "Linear" } | { toV2 = fn(tl, i, frame), fromV2 = fn(tl, i, frame) }`; `tl:count()`; `tl:append() -> i` (dense values 0, lists nil, not filled); `tl:isFilled(i)`, `tl:setFilled(i)`; `tl:set(name, i, k, v)`, `tl:get(name, i, k)`; `tl:setN(name, i, ...)`, `tl:getN(name, i) -> ...` (all `width` values); `tl:setList(name, i, v)`, `tl:getList(name, i)`; `tl:cut(n)` (keep 1..n); `tl:removeLast()`; `tl.version` (bumped by `cut`, `removeLast`, `replace`, `optimize`, not by `append` / `set`); `tl:toV2(i) -> table` (only registered columns); `tl:toV2All() -> { frames }`; `tl:replaceFromV2(frames)`; `tl:optimize() -> newCount`.

- [ ] **Step 1: Write the failing tests:**
  - `append / get / set` on all three kinds; values read back are the exact numbers written (`0.1 + 0.2`, `-123456.789`, `1e-6`).
  - `growth`: 10,000 appends; frames 1, 5000, 10000 hold their own values; capacity doubling never loses data.
  - `memory`: `collectgarbage("collect")`, 8192 frames with the phase 2 columns registered by a helper (TotalTime / FrameTime f64 x2, Cframe 12, Lin 3, Ang 3, CamCframe 12, Zoom 1, mouse 4, State / ShiftLock / Pose u8, JumpTime / Speed f64 x2) grow `collectgarbage("count")` by less than 400 bytes a frame (a V2 table frame of the same fields is over 1,500, measured in the same test and printed).
  - `cut`: `cut(3)` on 5 frames → count 3, list entries of frames 4-5 gone, `version` +1; `append` after a cut gives clean frames (no old values).
  - `V2 round trip`: 5 hand-written V2 frames (fields `FrameTime, TotalTime, Cframe, Velocity{Linear,Angular}, CamCframe, ShiftLock, Zoom, State, Anim{Pose,JumpTime,Speed,Anims}, Input, MX, MY, UVX, UVY, VX, VY, Tools, Died`; VX / VY only on frame 1) → `replaceFromV2` → `toV2(i)` serialises identically (sorted-key serialiser from `tests/test_diff.lua`), fields absent in the source stay absent.
  - `optimize`: the V2 rule (`p18_core.lua:797-838`): frame 1 kept; a frame is kept when fewer than 12 of its 12 camera components equal the previous frame's, or it has anims, inputs, a mouse move, CO / BT / Tools / Died; TotalTime re-summed from FrameTime; a 6-frame fixture gives the same frames and times as V2's function run on the same fixture (V2's loop copied into the test as the oracle).
- [ ] **Step 2: Run** `bash tools/build_test3.sh timeline && (cd tests3 && luau run_timeline.lua)` — Expected: FAIL (no module).
- [ ] **Step 3: Implement** `src2/engine/timeline.lua`: one `buffer` per dense column (`f64`: 8 bytes x width, `u8`: 1 byte), start capacity 1024 frames, doubled with `buffer.copy`; lists are Lua tables keyed by frame; a u8 `filled` column built in. `optimize` reads `CO`, `BT` and other unknown V2 fields through registered columns only (phase 4 columns join the rule through a per-column `keepFrame(tl, i)` flag in `addColumn`'s `v2` table).
- [ ] **Step 4: Run** the suite and `bash tools/test_all3.sh` — Expected: pass / `ALL PASSED`.
- [ ] **Step 5: Commit** `HappaTAS 3: column timeline with V2 frame conversion and optimize`.

---

### Task 3: Trace harness against V2.38.16

**Files:**
- Create: `tools/trace3.sh`, `tests3/trace/scenario.lua`, `tests3/trace/adapter_v2.lua`, `tests3/trace/adapter_v3.lua` (stub until Task 4)
- Modify: `tools/test_all.sh` (a `REF=1` switch: run V2's suites on the reference build), `.gitignore`

**Interfaces:**
- Produces: `bash tools/trace3.sh` with env `FIELDS` (V2 frame fields compared, space-separated), `GROUPS` (trace groups compared), `SIDES` (`v2 v2` or `v2 v3`, default `v2 v3`); prints `SAME (N lines)` or `DIFFERENT:` + the first 40 diff lines, exit 2; full traces `tests3/trace/out_a.txt`, `out_b.txt`.
- Adapter contract (global `A`, both sides): `A.boot() -> bool`, `A.mode() -> 1|2|3`, `A.frame()`, `A.paused()`, `A.count()`, `A.frameV2(i) -> table`, `A.setSetting(v2name, v)`, `A.char() -> hrp, humanoid`, `A.merge(frames, where)`, `A.mergeFinish(complete)`, `A.optimizeTwice()`.
- Trace lines: `T|mode|tag|mode|frame|paused|count`; `T|F|tag|i|<frame serialised with FIELDS only>`; `T|W.char|tag|hrpCF|lin|ang|state|anchored|autoRotate|jumpEnabled`; `T|W.cam|tag|camCF|cameraType|mouseBehavior`; `T|W.input|tag|<new M.inputLog entries>`; `T|W.anim|tag|<playing tracks: id, speed x1000, time x1000>`; `T|W.tool|tag|<equipped tool name or ->`.

- [ ] **Step 1: Write the scenario** (`tests3/trace/scenario.lua`; the session of `tests/test_diff.lua` without client objects, buttons, GUI, saving): a Tool `Sword` in the Backpack; record 200 frames with W / A / Space, right mouse down / up, wheel +1 / -1, a camera yaw per frame, mouse moves, equip the tool (key `One` is Idle: equip through `Humanoid:EquipTool` at frame 40, activate at 45, unequip at 90), a ladder (`ChangeState(Climbing)` frames 120-130 then a Space jump), velocities set per frame; pause; R held 20 frames; G, F, F; T held 5 frames; V; E; cut and record 60 more frames; death (`Health = 0`) with Record Death & Respawn on, respawn, 30 frames; pause; print every frame (`F`); Test (Interpolate on) to the end; Idle; optimize (`A.optimizeTwice`); Test at Playback Speed 2 without interpolation; Test at Playback Speed -1; merge: record a second 40-frame run, `A.merge(firstRunFrames, "after")`, move the root to the start pose, `A.mergeFinish(true)`, print every frame. `W.*` lines after every step and every frame of each Test.
- [ ] **Step 2: Write `adapter_v2.lua`** over V2's `__T` (`Core.State`, `Core.GetTAS`, `Core.SetTAS`, `Settings.Set`, `C.inputs.Optimize` in two coroutines as `test_diff.lua` does, `C.MergeStats.MouseButton1Click` for `mergeFinish`).
- [ ] **Step 3: Write `tools/trace3.sh`**: `git archive b1569bd src/parts tools/assemble.sh tools/order.txt | tar -x -C tests3/trace/ref` once, then `tools/assemble.sh` run inside it → `tests3/trace/ref/src/HappaTAS_Executor.lua`; side `v2` = mock + that build wrapped like `tools/build_test.sh` + `test_util` + `adapter_v2` + `scenario`; side `v3` = like `tools/build_test3.sh` with `adapter_v3`; `M.clockStep = 0`; keep `T|` lines of `GROUPS`, cut `F` lines down to `FIELDS`; diff.
- [ ] **Step 4: Run** `SIDES="v2 v2" GROUPS="mode F W.char W.cam W.input W.anim W.tool" FIELDS=all bash tools/trace3.sh` — Expected: `SAME` (the scenario is deterministic on V2), and `grep -c "^T|F|" tests3/trace/out_a.txt` is over 300. Also `REF=1 bash tools/test_all.sh` — Expected: V2's suites pass on the reference build.
- [ ] **Step 5: Commit** `HappaTAS 3: trace harness against V2.38.16`.

---

### Task 4: Engine core: Heartbeat stage, plugins, modes, frame loop, character

**Files:**
- Create: `src2/engine/plugins.lua`, `src2/engine/modes.lua`, `src2/engine/frame.lua`, `src2/world/character.lua`
- Modify: `src2/kernel/pipeline.lua` (stage `Heartbeat` = `RunService.Heartbeat`, after PostSimulation; runs every frame), `src2/main.lua`, `src2/modules.txt`, `tests3/trace/adapter_v3.lua`, `tests3/test_pipeline.lua` (the new stage)
- Test: `tests3/test_modes.lua`, `tests3/test_character.lua`

**Interfaces:**
- Consumes: Tasks 1-3; kernel `State`, `Bus`, `Pipeline:add`, `Lifecycle:scope`, `GameCall`.
- Produces:
  - `Plugins.new(errs) -> reg`; `reg:add(plugin)`; `reg:call(hook, ...)` (by `order`, each protected, an erroring plugin reported once).
  - `Modes.new(kernel, tl, reg, settings, controls) -> m`; state keys `mode` (`"Idle" | "Paused" | "Recording" | "Testing"`), `frame`, `merging`; `m:request(action, opts) -> bool` with actions `idle, create, test, pause, unpause, unpause1, back, forward, back1, forward1, return, seek (opts.frame: V2 `Profiler.OnScrub`, `p18_core.lua:1378-1390`, paused or Test), lookAround, deleteTas, optimize, toggleSpeedHack`; the 3-frame debounce of V2 `DoubleInput` (`create` with `opts.force` skips it); `m.firstFrame`, `m.lastPause`, `m.backHeld`, `m.forwardHeld`, `m.lookAround`, `m.testTime`; bus event `status` `(text, inverse)` for V2's status messages (Delete / Optimize confirm within 1.05 s, "There is not enough TAS data to test.", "TAS Completed [Time: m:ss.sss]" when `showCompletionMessage` is on).
  - `Frame.start(kernel, m)`: pipeline handlers, engine order 0-99: PreRender 0 (deferred steps), 50 (recording `begin`, Test pose); PreSimulation 50 (`fill`, Test pose for physics); Heartbeat 50 (paused stepping, first-frame times, fill without a physics step, Test `playTo`, finish Test); LateRender 50 (paused camera hold, plugins' `lateRender`). Input dispatch (InputBegan / InputEnded / JumpRequest) owned by the engine scope.
  - `Character` plugin (order 10): columns `FrameTime`, `TotalTime` (f64), `Cframe` 12, `Lin` 3, `Ang` 3, `State` u8, `Died` list; `character.sync(cf, lin, ang)` (V2 `SyncCharacter`, torso through the root joint), `character.anchor(on)`, `character.loaded() -> bool`.
- Behaviour to port, function for function, from the reference `p18_core.lua`: `LoadFrame` (339-393), `RemoveCutFrames`, `AveragedFrame` / `PlaybackPose` (405-446), `CanCoyoteJump`, `JumpedOffLader`, the mode functions (583-843), `preRender` (1043-1129, without the speed hack / kit / profiler calls: phase 4 / 6), `fillFrame` + `preSimulation` (1136-1175), `playbackStep` + `heartbeat` (1184-1312), `finishTest` (961-993), `lateRender` (1315-1339), the InputBegan dispatch (1398-1433), `CharLoad` / Died (937-952). Deferred steps: `noJumpOneFrame` = Jumping disabled until PreRender order 0 of the second frame after the unpause, `firstFrame` cleared there; `Unpause1F` = record `FrameCount` frames (1, or 2 after a ladder jump or a Landed frame), pause at PreRender order 0 of the frame after.

- [ ] **Step 1: Write the failing tests:**
  - `test_pipeline`: `Heartbeat stage runs every frame, also without a physics step` (`M.simDt` returning 0), after PostSimulation.
  - `test_modes`: Create on an empty TAS → `Paused`, frame 0, root anchored, AutoRotate off; Left Click → `Recording`, first frame recorded only on the second frame after the click, Jumping disabled until then; Left Click → `Paused` on the last frame, frames after it cut on the next unpause; `back` / `forward` held step one frame per Heartbeat; `back1` / `forward1`; `seek` to frame 5 while paused shows frame 5, in Test restarts the playback clock at frame 5's TotalTime; `return` goes to `lastPause` and cuts; `unpause1` records exactly 1 frame (2 after a Landed frame); Test with fewer than 2 frames → status "There is not enough TAS data to test." and stays; debounce: two `create` requests in one frame run once; `deleteTas` needs a second press within 1.05 s; `optimize` refused outside Idle with "Switch to idle to optimize TAS"; Review Focus 2 and 3 cases.
  - `test_character`: frame values rounded (`Cframe` components at 1/1000, `-0` → `0`); a frame without a physics step is filled in Heartbeat (240 FPS: `M.simDt` 0 every 5th frame → no frame lost, times add up); death with `recordDeath` on → `Died` on the frame, recording goes on after the respawn on the new root; off → last frame dropped, mode `Idle`; coyote jump allowed only after two Running frames; jump off a ladder steps back one frame on unpause.
- [ ] **Step 2: Run** both suites — Expected: FAIL (no module `engine/modes`).
- [ ] **Step 3: Implement** the four modules and the pipeline stage; `main.lua` builds settings, controls, typing, timeline, plugins, modes, frame inside `kernel.life:scope("engine")`; Debug shares `T.engine = { tl, modes, settings, controls, plugins }`. Fill `adapter_v3.lua` (mode numbers: Idle 1, Paused / Recording 2, Testing 3; `paused` = mode is Paused or `firstFrame`).
- [ ] **Step 4: Run** the suites, `bash tools/test_all3.sh`, then `GROUPS="mode F W.char" FIELDS="FrameTime TotalTime Cframe Velocity State Died" bash tools/trace3.sh` — Expected: `ALL PASSED`; `SAME`.
- [ ] **Step 5: Commit** `HappaTAS 3: mode machine, frame loop and character plugin (trace = V2.38.16)`.

---

### Task 5: Camera script bridge

**Files:**
- Create: `src2/platform/camerascript.lua`
- Test: `tests3/test_camerascript.lua`

**Interfaces:**
- Consumes: `Env` (`filtergc`, `getgc`, `hookfunction`, `restorefunction`), `GameCall`, a `Lifecycle` scope.
- Produces (V2 `Bridge` names, same behaviour, `p09_bridge.lua`): `CameraScript.new(life, errs) -> cs` with `cs:getZoom()`, `cs:setZoom(z, static)`, `cs:removeZoomSpring()`, `cs:updateGhost(zoom, dt, snap)`, `cs:resetGhost(keepCurrent)`, `cs:isShiftlocked()`, `cs:shiftlockSwitch()`, `cs:lockShiftlock(lock)`, `cs:shiftlockRotation(on)`, `cs:isFirstPerson()`, `cs:setCameraFreeze(freeze, forceLock, freezeZoom)`, `cs:setFreeMouse(free)`, `cs:guardMouse(modal, forceLocked)`, `cs:refreshMouse(modal)`, `cs:restoreAfterTest(zoom, shift)`, `cs.timeRate` (1 in phase 2), `cs:restore()`.

- [ ] **Step 1: Write the failing tests** (fixtures from `tests/test_realinput.lua` sections 1 and 8, `tests/test_live.lua` "the camera module runs in a thread of its own", `tests/test_security.lua`'s hook sections):
  - controllers found through `filtergc` (0 `getgc(true)` calls when `filtergc` exists); `getgc(true)` only without it.
  - the patches apply when the GC scan found the cameras before the PlayerModule resolved (V2.38.16 rule, spec 5.4), and never again after `restore()` (a `RefreshMouse` after restore re-hooks nothing).
  - with `hookfunction`: the module's functions keep their identity (`rawequal` before / after), `isfunctionhooked` true while loaded, false after `restore()`; a failing hook falls back to the table swap.
  - zoom / mouse lock calls run on another thread than the caller (the caller keeps CoreGui access).
  - ghost: `updateGhost(1, dt, false)` limits the change to `2.8 * dt` per call, `resetGhost(false)` puts `LocalTransparencyModifier` back to 0.
- [ ] **Step 2: Run** — Expected: FAIL (no module).
- [ ] **Step 3: Implement** by porting `p09_bridge.lua` (less `GetAnimation` / `SetAnimation` / `LockAnimations`, which move to Task 8), every connection and hook owned by `life`.
- [ ] **Step 4: Run** the suite and `bash tools/test_all3.sh` — Expected: pass.
- [ ] **Step 5: Commit** `HappaTAS 3: camera script bridge (zoom, shift lock, mouse lock, ghost, patches)`.

---

### Task 6: Camera plugin

**Files:**
- Create: `src2/world/camera.lua`
- Modify: `src2/main.lua`, `src2/modules.txt`, `src2/engine/frame.lua` (mouse rules call the camera plugin)
- Test: `tests3/test_camera.lua`

**Interfaces:**
- Consumes: `CameraScript` (Task 5), plugin contract, `Modes` state.
- Produces: plugin `camera` (order 20): columns `CamCframe` 12 (f64), `Zoom` 1 (f64), `ShiftLock` u8; `camera.update(frameOrPose, unlockShift)` (V2 `C.UpdateCamera`), `camera.holdPaused()`, `camera.updateMouseMode()` (V2 `updateMouseMode`, `isMode2MouseLocked`, `FIRST_PERSON 0.55`), camera type rules (Scriptable in Test when `lockCameraTest`).

- [ ] **Step 1: Write the failing tests:** recorded `Zoom` = `round(getZoom, 1000)`; `ShiftLock` 0 / 1; paused with `lockCameraPaused` holds the camera on the frame (a game write is undone the same frame in LateRender); `lookAround` frees it; Test with `lockCameraTest` → CameraType Scriptable, back to Custom at the end with the last frame's zoom; mouse free while paused unless the frame is shift-locked or zoom ≤ 0.55.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the plugin; the camera parts of `LoadFrame`, `preRender`, `lateRender`, `finishTest` move behind it.
- [ ] **Step 4: Run** the suite, `bash tools/test_all3.sh`, and `GROUPS="mode F W.char W.cam" FIELDS="FrameTime TotalTime Cframe Velocity State Died CamCframe Zoom ShiftLock" bash tools/trace3.sh` — Expected: pass, `SAME`.
- [ ] **Step 5: Commit** `HappaTAS 3: camera plugin (trace = V2.38.16)`.

---

### Task 7: Inputs plugin

**Files:**
- Create: `src2/world/inputs.lua`
- Test: `tests3/test_inputs.lua`

**Interfaces:**
- Consumes: `Env` (`keypress`, `keyrelease`, `mouse1press` ..., `mousemoveabs`, `mousemoverel`, `mousescroll`, `VirtualInput`, `WindowActive`), `Keys`, `Typing`, `Settings`.
- Produces: plugin `inputs` (order 30): columns `Input` list, `Mouse` f64 x4 (`MX, MY, UVX, UVY`), `Viewport` list (`{VX, VY}` only when changed); `inputs.take()`, `inputs.clear()`, `inputs.mouse() -> mx, my, uvx, uvy, vx, vy`, `inputs.heldAt(tl, upTo, base) -> set`, `inputs.beginRecording(tl, base)`, `inputs.replayBegin / replayTo / replayMouse / replayEnd`, `inputs.describe(set) -> text`, `inputs.isOverOwnUI` (hook, returns false until phase 5), `inputs.calibration()`.
- Behaviour: V2 `p10_inputs.lua` as of `b1569bd`: key ids are file format (A-Z 1-26 ... LMB 96, RMB 97, wheel `10000 + n`), never reordered; the extended-key set goes through VirtualInputManager with `keypress` as fallback; keys pressed while the window isn't active are pressed when it is; the real-mouse fit (least squares per axis, `n >= 6`, spread ≥ 150 px, `a` in 0.9..1.1, `|b| <= 64`, halved at 240) and the `mousemoverel(1,0) / (-1,0)` flush; replayed presses ignored by live recording for 0.5 s.

- [ ] **Step 1: Write the failing tests** (port `tests/test_realinput.lua` sections 2-7 and `tests/test_typing.lua` section 7): every V2 key id unchanged (table of 10 sample ids written literally); wheel notches; held set at a frame; `beginRecording` emits the releases / presses between the live keys and the frame resumed from; keys typed in chat not recorded; Review Focus 5 (window inactive, missing functions).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the plugin; the engine's input dispatch asks `inputs.isOverOwnUI` before Pause / Unpause.
- [ ] **Step 4: Run** the suite, `bash tools/test_all3.sh`, and the trace with `GROUPS` + `W.input`, `FIELDS` + `Input MX MY UVX UVY VX VY` — Expected: pass, `SAME`.
- [ ] **Step 5: Commit** `HappaTAS 3: inputs plugin (trace = V2.38.16)`.

---

### Task 8: Animation plugin

**Files:**
- Create: `src2/world/animation.lua`
- Test: `tests3/test_animation.lua`

**Interfaces:**
- Produces: plugin `animation` (order 40): columns `AnimPose` u8, `AnimJump` f64, `AnimSpeed` f64, `AnimList` list (V2 `Anim = { Pose, JumpTime, Speed, Anims }`; a frame with no engine converts to V2's `EMPTY_ANIM` `{ Pose = 0, JumpTime = 0, Speed = 1, Anims = {} }`); `animation.get(startOfTAS)`, `animation.set(data, anims, speed, timeDiff)`, `animation.lock(mode)` (`true`, `false`, `"ReplayAnimationsOnly"`), `animation.attach(char)`, `animation.detach()`.
- Behaviour: V2 `p12_anim.lua` at `b1569bd` with the speed hack factors fixed at 1 (`hack()`, `SpeedHack.scale`, `SpeedHack.GameDt(dt) = dt`) behind a `timeRate` hook phase 4 sets; the game's Animate script disabled while attached and restored on detach / Unload; frame 2 records `{ {current, 0} }` as V2 does.

- [ ] **Step 1: Write the failing tests:** the 13 animation numbers and pose numbers are V2's (literal tables); walking at speed 16 plays `walk` at speed `16 / 16` scaled like V2 `onRunning`; paused → `lock(true)` holds the track at speed 0; backtrack sets `TimePosition` to the summed time; detach restores the game's Animate.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the plugin.
- [ ] **Step 4: Run** the suite, `bash tools/test_all3.sh`, and the trace with `W.anim` and `Anim` added — Expected: pass, `SAME`.
- [ ] **Step 5: Commit** `HappaTAS 3: animation plugin (trace = V2.38.16)`.

---

### Task 9: Tools plugin

**Files:**
- Create: `src2/world/tools.lua`
- Test: `tests3/test_tools.lua`

**Interfaces:**
- Produces: plugin `tools` (order 50): column `Tools` list (`{ {Action, Name}, ... }`); `tools.take()`, `tools.clear()`, `tools.replayBegin(tl, i, char)`, `tools.replayFrame(events, char)`, `tools.step(char, hum)`, `tools.replayEnd()`, `tools.attach(char)`.
- Behaviour: V2 `p15_tools.lua` (`FIX_AFTER = 4` frames of mismatch before HappaTAS equips itself; clicks a tool only when mouse click replay is off; at most 64 pending events; nothing recorded with `recordTools` off).

- [ ] **Step 1: Write the failing tests:** equip / activate / deactivate / unequip recorded on their frames; replay corrects a wrong tool after 4 frames, not before; no double toggle when the key replay already equipped it.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the plugin.
- [ ] **Step 4: Run** the suite, `bash tools/test_all3.sh`, and the trace with `W.tool` and `Tools` added — Expected: pass, `SAME`.
- [ ] **Step 5: Commit** `HappaTAS 3: tools plugin (trace = V2.38.16)`.

---

### Task 10: Merge, optimize and delete in the engine

**Files:**
- Create: `src2/engine/merge.lua`
- Modify: `src2/engine/modes.lua` (action `merge`), `tests3/trace/adapter_v3.lua`
- Test: `tests3/test_merge.lua`

**Interfaces:**
- Produces: `Merge.begin(m, otherTl, where) -> bool` (`where` = `"after"` | `"before"`; refuses an empty run or one without a pose with V2's status texts), `Merge.finish(m, complete)`; state `merging`, `mergeCanComplete` (distance to the other run's start < `16 * (t1 + t2) / 2`); two hitbox parts (`startHitbox` red `205,10,0`, `endHitbox` green `0,185,8`, 2.1 x 2.1 x 1.1, transparency 0.5, no collide / query / touch) under the camera, owned by the engine scope; the merged run re-times TotalTime from `max(2, #before)`.

- [ ] **Step 1: Write the failing tests:** merge "after" and "before" give V2's frame order and times (V2's click handler copied as the oracle); cancel restores the old run; hitboxes created and destroyed; the held keys of the run merged onto are the recording's base.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement**.
- [ ] **Step 4: Run** the suite, `bash tools/test_all3.sh`, and the full trace: `GROUPS="mode F W.char W.cam W.input W.anim W.tool" FIELDS="FrameTime TotalTime Cframe Velocity State Died CamCframe Zoom ShiftLock Input MX MY UVX UVY VX VY Anim Tools" bash tools/trace3.sh` — Expected: pass, `SAME` (the scenario's optimize and merge sections included).
- [ ] **Step 5: Commit** `HappaTAS 3: merge, optimize and delete (full trace = V2.38.16)`.

---

### Task 11: Unload, bench, release

**Files:**
- Create: `tests3/test_engine.lua`, `tests3/test_bench3.lua`
- Modify: `tools/test_all3.sh` (runs the full trace; fails on `DIFFERENT`), `README.md` only if it already mentions HappaTAS 3 (otherwise untouched until phase 7)

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Write the failing tests:**
  - `test_engine`: Review Focus 4: Unload while recording, paused, testing → root unanchored, AutoRotate and Jumping on, CameraType Custom, `MouseBehavior` as before load, camera functions not hooked, no key left down by the replay, no handler or connection left (counts as `test_main`), `LocalTransparencyModifier` 0; a second copy started while the first is recording takes over cleanly.
  - `test_bench3`: microseconds and engine reads / writes per frame in Idle, Create paused, recording and Test over 600 frames each (method of `tests/test_bench.lua`); the same session on the reference V2 build with Sync Client Objects, stats panels and the MicroProfiler off; HappaTAS 3 must be ≤ V2 in every mode (prints both).
- [ ] **Step 2: Run** — Expected: FAIL on whatever Unload misses (fix in Step 3; if nothing fails, record that as a finding in the ledger).
- [ ] **Step 3: Fix** what the tests found; `tools/test_all3.sh` gains the full trace and the bench.
- [ ] **Step 4: Run** `bash tools/test_all3.sh` — Expected: `ALL PASSED` including `trace: SAME` and the release `wow3` through `main` and `engine`.
- [ ] **Step 5: Commit** `HappaTAS 3: clean unload of the engine, bench against V2.38.16`.

---

### Task 12: V2 changes after the reference, live check

**Files:** the ledger only, unless a port is needed.

- [ ] **Step 1:** List the V2 changes on `main` after `b1569bd` (`git log b1569bd..origin/main`, the `wow` diff) and any later committed `src/parts` changes; for each, decide: port now (engine-core behaviour), later phase, or not (with the reason). Port the engine-core ones with a test each.
- [ ] **Step 2: Live check** (only after dzr says directly that the Real MCP is connected; otherwise write "not tested live" in the ledger and the PR): back up `HappaTasPort/Settings.json` and the place's `.tas` files, note `getfpscap()`; in the EToH kit test place load the release `wow3` from `HappaTasTest/`; check that Heartbeat runs every frame at 240 FPS; record ~5 s with walking, a jump, the camera turned, a tool equipped; pause, scrub, unpause 1 frame, return; Test; compare the played root path with the recorded one (max error printed); Unload → nothing left (connections, camera hooks, anchoring). Restore everything, delete `HappaTasTest`.
- [ ] **Step 3: Commit** any ports; open the phase 2 PR (`v3-rewrite` → `main`) only when dzr asks.
