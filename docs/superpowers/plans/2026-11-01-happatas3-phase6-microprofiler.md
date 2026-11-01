# HappaTAS 3 Phase 6: MicroProfiler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** HappaTAS 3 gets V2.38.17's MicroProfiler with the same look and the same numbers, fed by HappaTAS 3's kernel.

**Architecture:** A function-by-function port of V2.38.17's `p17_profiler.lua` (reference `git show aaa21b6:src/parts/p17_profiler.lua`, never the working tree). It is split along V2's own sections into four modules that share one state table.
- The profiler keeps V2's `P` API names (Begin, End, FrameBegin, FrameEnd, SetMode, Snapshot, TimerStats, ...). That lets V2's test suites (tests/test_profiler.lua, 34 sections / 431 checks; tests/test_graphimg.lua, 58) port section by section with V2's expected values unchanged.
- The kernel feeds it: the pipeline reports each stage's start and end, and the plugin registry reports each plugin hook's time. Both cost one nil check when the profiler is off.

**Tech Stack:** Luau (src2/, tools/build3.sh), the headless mock (tests/mock, its EditableImage and Stats), tests3/.

**Spec:** docs/superpowers/specs/2026-10-18-happatas3-rewrite-design.md — section 9 ("same look and numbers as V2.38.16": V2.38.17 is the reference since phase 4), 10, 11, 12 (phase 6).

## Global Constraints

- Conservative Luau only: no `+=`, `//`, backtick strings, `continue`, if-expressions; never name getfenv / setfenv; 200 locals per function (V2 needed `profilerModule()` and state tables for this: keep each new module under it).
- No network code. Executor functions only from docs.projectreal.gg, docs.potassium.pro, sunc.su.
- dzr's MicroProfiler rules, unchanged:
  - Time = the current frame's time.
  - Avg = the average of every frame since the count started (off the bar too).
  - Max = the biggest frame since the count started.
  - These don't depend on the Aggregate setting and work the same in Hidden mode.
  - Aggregate Infinite shows Aggregate[N] and picking it restarts the count, Avg and Max.
  - Every number comes from a documented source (Roblox Stats / RunService docs, github.com/zeux/microprofile).
- The look: Roboto Mono Bold with a 1 px black shadow, title "MicroProfiler", menus Mode / Groups / Aggregate / Timers / Options / Preset / Custom / [Dump] / Flamegraphs / Pause / Help / Network. Plus the X close box with Roblox's hint, the EditableImage graph (frames as a fallback), and the ScreenGui straight in CoreGui at DisplayOrder 2147482000 (gethui otherwise).
- Keys: the `microProfiler` control (F6) shows / hides it. Ctrl+P pauses it. Holding Ctrl lets clicks through. A click on the profiler never counts as Pause / Unpause.
- Settings: `showMicroProfiler`, `microProfilerScale`, `microProfilerTextOffset` (they exist). The profiler's own config and presets live in the settings file's `profiler` table (`SettingsFile:setProfiler`, already carried from V2's Settings.json).
- Behaviour unchanged elsewhere: the three traces in `tools/test_all3.sh` stay SAME. Bench reads / writes are never above V2's in a gated mode. `test_all3.sh` passes (run it with `timeout 3600`, in a temporary worktree of the commit).
- Live checks follow spec 11, plus the session rules: backups first, put the files back byte for byte, fps cap / quality as recorded, HappaTasTest deleted, never Tower Creator.

## Review Focus

1. The profiler opened, closed and reopened mid-recording, and while paused: its count / Avg / Max carry on as V2's do, and recording isn't paused by any click on it (Task 6 test).
2. A run cut, loaded or merged while the TAS Timeline is shown: the timeline reads the run as it is now and a click seeks inside it (Task 5 test).
3. Unload with the profiler open in each mode: no ScreenGui, EditableImage, connection or kernel hook left (Task 8 test).
4. A settings file without a `profiler` table, with V2.35's old layout, or with damaged values: the profiler opens with defaults, never an error (Task 7 test).
5. The profiler shown in Classic and in New, and switching while it's open: it stays as it is, above both (Task 8 test).

---

## File Structure

| File | Responsibility (V2 p17 sections it ports) |
|---|---|
| `src2/profiler/stats.lua` (new) | timers and groups, Stats reads, the engine values of a frame, raw frames finished 3 frames later, aggregate (AG) and readout (RO), Snapshot / TimerStats, config defaults (p17 "timers", "config", "state", "timer API", "aggregate", FrameEnd). |
| `src2/profiler/graph.lua` (new) | the frame graph: EditableImage (GI) with the frames fallback, bar colours (Jobs vs Render), selection (p17 "frame graph", GI). |
| `src2/profiler/view.lua` (new) | geometry, colours, font / text offset, instances, menus, hover tooltip, Detailed, Timers, Counters, Flamegraphs, TAS timeline, build, modes, per-frame drawing, visibility, scale (p17 "geometry" .. "per frame"). |
| `src2/profiler/dump.lua` (new) | dumps (html / txt / csv) and presets (p17 "dump", "config + presets"). |
| `src2/profiler/app.lua` (new) | wires it to HappaTAS 3: kernel feed, keys, mouse / click-through, the recorder's mouse-over test, settings, settings file, Unload. |
| `src2/kernel/pipeline.lua` | `pipe.profiler` hook: `stageBegin(stage)` / `stageEnd(stage, module times)` when set. |
| `src2/engine/plugins.lua` | `plugins.timer` hook: a plugin hook's time by plugin name when set. |
| `src2/modules.txt`, `src2/main.lua` | the new modules and `E.profiler`. |
| `tests3/test_profiler.lua`, `tests3/test_graphimg.lua` (new) | V2's suites ported, section by section, in the task that owns the code. |

The four modules share one state table `S`, made by stats.lua and passed to the others, the way V2's sections share the `profilerModule()` locals.

### Task 1: The kernel feed and the profiler's numbers

**Files:** Create `src2/profiler/stats.lua`, `src2/profiler/app.lua` (the feed part). Modify `src2/kernel/pipeline.lua`, `src2/engine/plugins.lua`, `src2/modules.txt`, `src2/main.lua`. Test `tests3/test_profiler.lua`, `tests3/test_pipeline.lua`, `tests3/test_plugins.lua`.

**Interfaces:**
- Produces: `E.profiler` with V2's API: `Begin(name)`, `End(name)`, `FrameBegin(dt)`, `FrameEnd()`, `Snapshot() -> { time, avg, max, averaged, onBar, aggAvg, aggMax, frames, count, recorded, frameNo, paused, offset, range, hover }`, `TimerStats(name) -> { time, calls, exclusive, avg, max, min, callAvg, group }`, `TogglePause()`, `IsPaused()`, `active`.
- `pipe.profiler = { stageBegin = f(stage), stageEnd = f(stage), entry = f(module, seconds) }`, called only when set.
- `plugins.timer = f(pluginName, seconds)`, called only when set.
- Timer mapping, V2's names and colours:
  - HappaTAS = every pipeline stage.
  - Record = module "engine" entries in Create while recording; Playback = the same in Test.
  - Client Objects = plugin "clientobjects"; Buttons = plugin "buttons"; Cursor = plugin "cursor" (their hooks and entries).
  - Stats UI = module "ui" entries.
  - Profiler = its own work.
- The Engine timers come from the profiler's own RunService listeners (PreAnimation, PreSimulation, PostSimulation, Heartbeat), connected only while it's active, as V2's flip does.

- [ ] **Step 1: Write the failing tests:**
  - Port V2's sections "boot", "timers fed by the core", "readout format", "Avg = every frame since the count started (off the bar too), Max = the biggest frame (any Aggregate)", "Avg over a long session ...", "Infinite: the label counts every frame ...", "the Aggregate setting does not change how Time / Avg / Max work", "Pause / Unpause / Force Enable" and "Options: reference time" into tests3/test_profiler.lua. Adapter: V2's `__T.Profiler` → `E.profiler`; V2's core sections → `E.modes` requests. Keep V2's expected values.
  - In test_pipeline: "a profiler hook sees every stage once and costs nothing when unset".
  - In test_plugins: "plugins.timer gets each hook's time by plugin name".
- [ ] **Step 2: Run** `bash tools/build_test3.sh profiler && (cd tests3 && luau run_profiler.lua)`. Expected: FAIL (no `E.profiler`).
- [ ] **Step 3: Implement** by porting p17's sections listed in the File Structure. The 3-frame finish (RAW, 8 slots) and the FRAME_LEAD 0.22 / PRERENDER_TAIL 0.15 constants stay; FrameEnd marks the end of HappaTAS's PreRender work, i.e. the last PreRender entry.
- [ ] **Step 4: Run** the suites, then `bash tools/test_all3.sh`. Expected: PASS, traces SAME, BENCH OK (the hooks unset).
- [ ] **Step 5: Commit** `HappaTAS 3: MicroProfiler numbers fed by the kernel`.

### Task 2: The frame graph

**Files:** Create `src2/profiler/graph.lua`. Test `tests3/test_graphimg.lua`, `tests3/test_profiler.lua`.

**Interfaces:** `Graph.new(S, parent) -> graph` with `graph:push(frame)`, `graph:redraw()`, `graph:destroy()`. EditableImage 1016 x 50 (2 x 508 columns), one column written twice per frame, `ImageRectOffset`, whole redraw on a change of view. Frames when creating the image or a write fails (`M.eiFail` in the mock).

- [ ] **Step 1:** Port tests/test_graphimg.lua (58 checks) and V2's sections "frame bars: height, colour (Jobs vs Render), strip position" and "green selection = detailed view window". Expected values unchanged.
- [ ] **Step 2: Run** `bash tools/build_test3.sh graphimg && (cd tests3 && luau run_graphimg.lua)`. Expected: FAIL.
- [ ] **Step 3: Implement** (p17 "frame graph" + GI).
- [ ] **Step 4: Run** both suites. Expected: PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: MicroProfiler frame graph`.

### Task 3: The window, menus and text

**Files:** Create `src2/profiler/view.lua` (shell: geometry, colours, font, instances, menu bar, menus, close box, hint, build, modes Frame / Hidden, scale, visibility). Test `tests3/test_profiler.lua`.

**Interfaces:** `View.new(S, E) -> view` with `view:build()`, `view:setMode(m)`, `view:setVisible(v)`, `view:setScale(s)`, `view:setTextNudge(n)`, `view:frame()` (the per-frame draw), `view:destroy()`. The ScreenGui is "HappaProfiler" (buttons.lua already skips that name).

- [ ] **Step 1:** Port V2's sections "font: Roboto Mono Bold, 6 px grid, 1 px black drop shadow", "menu bar layout (MicroProfileDrawMenu)", "menus open on hover, stay open inside, close outside", "clicking a dropdown line", "close box", "text offset setting" and "Hidden mode works the same, the bar is just invisible".
- [ ] **Step 2: Run** the profiler suite. Expected: FAIL on those sections.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: MicroProfiler window and menus`.

### Task 4: Detailed, Timers, Counters, Flamegraphs and the tooltip

**Files:** Modify `src2/profiler/view.lua`. Test `tests3/test_profiler.lua`.

- [ ] **Step 1:** Port V2's sections "hover tooltip on a frame", "Detailed mode: engine phases and HappaTAS scopes on a timeline", "Timers mode (MicroProfileDrawBarView)", "Counters mode (MicroProfileDrawCounterView)" and "Flamegraphs".
- [ ] **Step 2: Run.** Expected: FAIL on those sections.
- [ ] **Step 3: Implement** (p17 "hover / tooltip" .. "Flamegraphs"). The Detailed lanes are "0000:  Engine" and "0001:  HappaTAS" with Task 1's timers.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: MicroProfiler modes`.

### Task 5: Custom > TAS Timeline

**Files:** Modify `src2/profiler/view.lua`, `src2/engine/modes.lua` (the scrub notice where the comment "V2 Profiler.OnScrub" already sits: `E.profiler:OnScrub(f)` when set). Test `tests3/test_profiler.lua`.

**Interfaces:** The TAS timeline reads `E.tl` (FrameTime / TotalTime). The readout shows frame f's Time and the Avg / Max of frames 1 .. f, from prefix sums reset on `onDataChanged` / `onLoaded`. A click seeks with `E.modes:request("seek", { frame = f })`.

- [ ] **Step 1:** Port V2's section "Custom > TAS Timeline", and add "a cut / load / merge while shown: the timeline and readout follow the run as it is now; a click seeks inside it" (Review Focus 2).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** (p17 "TAS timeline (Custom)").
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: MicroProfiler TAS timeline`.

### Task 6: Mouse, keys and the recorder

**Files:** Modify `src2/profiler/app.lua`, `src2/ui/app.lua` (`E.inputs.mouseOverOwn` also asks the profiler). Test `tests3/test_profiler.lua`.

**Interfaces:**
- `E.profiler:IsMouseOver(m) -> bool`. Pointer positions come from input events, or `GetMouseLocation() - GetGuiInset()` (V2's fix).
- A click is a release within 3 px of the press. Ctrl held lets clicks through.
- The `microProfiler` control toggles `showMicroProfiler`. Ctrl+P runs `TogglePause`. Both respect `E.typing`.

- [ ] **Step 1:** Port V2's sections "mouse: Roblox's coordinate spaces", "mouse: clicks (microprofile's MicroProfileMouseButton)", "mouse: the new 58 px top bar and touch" and "mouse-over test for the recorder". Add "opened, closed and reopened mid-recording: the count / Avg / Max carry on, no click on it pauses recording" (Review Focus 1).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite and test_interface / test_ui. Expected: PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: MicroProfiler mouse and keys`.

### Task 7: Dumps, config and presets

**Files:** Create `src2/profiler/dump.lua`. Modify `src2/profiler/app.lua`. Test `tests3/test_profiler.lua`.

**Interfaces:**
- Dumps are written to the place folder through `E.files` as `microprofile-<date>-<time>.html` (`.txt` legacy, `.csv` binary), as V2 names them. The Library lists runs only, so dumps never show up there (test_library checks a dump.html isn't listed).
- Config / presets: a new `SettingsFile:getProfiler() -> table?` (the `profiler` field as loaded) and the existing `setProfiler(t)`, with V2's `SerializeConfig` / `LoadConfig` shapes.

- [ ] **Step 1:** Port V2's sections "Dump", "Presets", "config: save / load / old V2.35 settings" and "settings file". Add "no profiler table / V2.35 layout / damaged values: defaults, no error" (Review Focus 4).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** (p17 "dump", "config + presets").
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: MicroProfiler dumps and presets`.

### Task 8: Together

**Files:** Modify `tests3/test_ui.lua`, `tests3/trace/bench.lua`, `tests3/trace/adapter_v3.lua`, `tests3/trace/adapter_v2.lua`, `src2/ui/win/helptext.lua` (the MicroProfiler topic, V2's text). Test `tests3/test_profiler.lua` ("unload", "cost per frame").

**Interfaces:**
- Bench modes "idle, profiler" and "recording, profiler": the profiler shown in Frame mode on both sides, gated like the other modes. `A.showProfiler(on)` in both adapters.

- [ ] **Step 1:**
  - Port V2's sections "unload" and "cost per frame".
  - In test_ui: the profiler open in Classic and in New, a switch while it's open, then Unload. No HappaProfiler ScreenGui, EditableImage, connection, `pipe.profiler` or `plugins.timer` left (Review Focus 3 and 5).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** what the tests need, plus the bench modes and the Help topic.
- [ ] **Step 4: Run** `bash tools/test_all3.sh`. Expected: ALL PASSED, BENCH OK.
- [ ] **Step 5: Commit** `HappaTAS 3: phase 6 together`.

### Task 9: Live check

**Files:** Modify the spec (13: the phase 6 entry). Fixes found live go in their own files, each with a test that fails first.

- [ ] **Step 1:** Backups (Global Constraints); the release and a debug copy in HappaTasTest/.
- [ ] **Step 2:** In the EToH kit test place:
  - HappaTAS 3's profiler beside V2.38.17's on the same scene: the readout, frame colours and heights over the same seconds, every menu with real clicks, every mode, the TAS timeline seek, a dump written and opened, Ctrl click-through, F6 and Ctrl+P.
  - The frame colour rule against Roblox's own profiler, as V2.38.1 did. Use Ctrl+F6 for Roblox's profiler, with HappaTAS's F6 handled as the notes say.
  - The cost with the profiler open, with `tools/live/meter3.lua`, against V2 with its profiler open.
  - The release silent, Unload clean.
- [ ] **Step 3:** Clean up.
- [ ] **Step 4:** Write spec 13's phase 6 entry and commit `HappaTAS 3 phase 6: live check`.
