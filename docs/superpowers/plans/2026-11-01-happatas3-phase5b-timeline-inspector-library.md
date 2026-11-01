# HappaTAS 3 Phase 5b: timeline bar, Inspector, Library, Merge and Help — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Everything you need to make and keep a run without V2's menu: the timeline bar (spec 8.2), and the Inspector, Library, Merge and Help windows (spec 8.3), built on phase 5a's kit.

**Architecture:** One new non-window piece, the timeline bar (`src2/ui/bar/`), fed by a timeline model that indexes the run's events once and then only the frames that were added; four new windows in `src2/ui/win/`, opened from the Dock. Every transition goes through `E.modes:request`; saving, loading and merging go through `E.persist` (one thread, `E.busy`, bus `persist`). Small engine additions where a window needs them: a `Marker` column, `Persist:readFrames`, a saved / unsaved mark, `Library:folders`, `Env.notes`, and timing of the pipeline on demand.

**Tech Stack:** Luau (conservative syntax), Roblox GUI instances through phase 5a's kit (`ui/kit/*`, `W.set`, own pointer, own layout), the headless mock (`tests/mock/`) and `luau`.

**Spec:** `docs/superpowers/specs/2026-10-18-happatas3-rewrite-design.md`: 5.1 (transitions), 6.2 (Library), 6.3 (the stats settings become Inspector settings), 7 (known limits, for Help), 8.1-8.3, 10 (missing executor functions noted in Help), 11, 12, 13. Look: phase 5a's (no new mockup).

## Global Constraints

- Everything in the phase 1-5a plans' Global Constraints still holds:
  - conservative Luau (no `+=`, `//`, backtick strings, `continue`, if-expressions);
  - no network code; sUNC lookups with fallbacks through `platform/env`;
  - game code only through `GameCall` / `task.spawn(pcall, ...)`;
  - Debug output only with `CONFIG.Debug`; version `"3.0.0-dev"`;
  - never commit `CLAUDE.md` / `claude/`; commit only the files a task lists;
  - never name `getfenv` / `setfenv` (deopt guard);
  - no GUI property written unless it changes (`W.set`); `AutoLocalize = false`;
  - no per-frame work while nothing changes; Unload leaves nothing (the 5a test counts UserInputService connections: keep it passing).
- Branch `v3-rewrite` (PR #19 open with phase 5a). Do not edit `src/parts/`, `wow`, `wow1`, `tests/test_*.lua`. Mock additions only when `REF=1 bash tools/test_all.sh` still passes.
- **Text: only characters every listed font has.** Measured live in phase 5a: `× ▼ ← … •` plus ASCII. Every other icon is drawn from frames, or is `▼` rotated (TextLabel `Rotation`: -90 = ▶, 90 = ◀). Phase 5a's `test_ui` check walks every text under the root, so it covers the new windows.
- **Ruling: the Inspector and the timeline bar don't free the mouse.**
  - 5a frees the mouse whenever a window is open (`E.modal`). Windows get `def.modal` (default true); the Inspector has `modal = false`. The bar is not a window.
  - With only non-modal things open, the camera and shift lock behave as with nothing open.
- **Ruling: the Inspector replaces V2's stats panels.**
  - It opens on first start (V2's panels were on by default). Its open state is remembered in the `ui` table (`open = { [id] = true }`).
  - `showStatsIdle` / `showStatsCreate` / `showStatsTest` decide whether it shows values in that mode; when off, one line says so. Test at a playback speed other than 1 still shows the Frame section (V2's rule).
  - `statsTextSize` is its values' text size.
  - The four settings stay in Settings > Interface (spec 8.4 counts them) and are also in the Inspector's options popover (the same store, spec 6.3).
- **Ruling: markers.** A marker is a frame bookmark with an optional label, kept in a new list column `Marker` (`v2 = { key = "Marker", keep = true }`, saved in v6 files; V2 files have none). The bar's marker button adds or removes one at the shown frame.
- **Ruling: the timeline bar's place.**
  - Bottom centre, 76 layer units above the bottom edge, so it clears Roblox's hotbar.
  - Width `min(900, 70 % of the screen)`, height 40; lanes open above it (4 × 16).
  - Pointer z 40,000,000, draw ZIndex 450,000: above windows, below the Dock and popovers.
  - It is hidden with the interface (Menu key) and collapses to a 10-high strip in Idle with no run.
- **Ruling: Help is rewritten for HappaTAS 3, not V2's text copied.**
  - Topics come from V2.38.17's help entries (`git show aaa21b6:src/parts/p04_ui.lua`, the `H("..")` entries), updated to what HappaTAS 3 does.
  - Add: the timeline bar, Library and attempts, Inspector, known limits (spec 7), "Missing executor functions" (live from `Env.notes`), and Credits, copied exactly from V2.38.17:
    - "Happy_Liam/happa - Main Scripter/UI Design"
    - "plusgiant5 - Tasability creator"
    - "TestMicrowaveDinner - Scripting Help"
    - "Skittlesuna - Playtester"
    - "Executor port - client side script"
  - No update log until phase 7.
- **Ruling: Merge follows V2's flow.**
  - Pick a run in the Library, then Merge.
  - The run is read, then **Before** and **After** are offered: Before only if its last frame's `State` is `Enum.HumanoidStateType.Running.Value`, After only if its first frame's is.
  - Then the Merge window shows the current distance against the distance required, with one button that completes when close enough and cancels otherwise (`E.mergeRun:finishMerge()`).
  - "You must have a TAS to merge" when the run is empty.
- Live tests (Real MCP; dzr: "Real is always connected"):
  - back up `HappaTasPort/Settings.json`, `Settings3.json` and the place's files, and restore them byte-identical;
  - record `getfpscap()` and the graphics quality, and put them back;
  - use `HappaTasTest/` and delete it; rejoin if the place changed;
  - never run HappaTAS in Tower Creator.
  - Mouse input through `VirtualInputManager` (works without window focus, screen coordinates; phase 5a). Wrap every eval in `pcall` (an erroring eval never returns).

## Review Focus

1. **A long run** (144,000 frames, 10 minutes at 240 FPS): opening the bar, zooming and dragging stays cheap. The model is built once, then grows by the frames added. The bar never has more GUI objects than its pools. Test in Tasks 1 and 2.
2. **The run changes under an open window** (a load, a merge, Delete TAS, going back and recording over frames): the bar, lanes and Inspector show the new run on the next frame, with no stale index past `tl:count()`. Test in Tasks 1, 2 and 4.
3. **Save / load / merge at the wrong moment** (while recording, while `E.busy`, from Test, an empty run): the button refuses with the persist or merge message and nothing half-happens. Test in Tasks 5 and 6.
4. **Names and folders users type** (empty, `/` or `\` inside, 200 characters, the same name in another case, a name that already exists): refused, cleaned by `Files.cleanName`, or a second click is asked for before overwriting. Test in Task 5.
5. **Seeking at the edges** (dragging past either end, a run of 0 or 1 frame, scrubbing in Test to the last frame, the wheel zoomed in to fewer frames than pixels): the frame is clamped to `1..count`, and no seek is requested when `E.modes:allowed("seek")` is false. Test in Task 2.

---

## File Structure

| File | Responsibility |
|---|---|
| `src2/ui/bar/model.lua` | the run's events by kind (sorted frame lists), markers, incremental growth, rebuild on change |
| `src2/ui/bar/bar.lua` | the timeline bar: mode / speed, transport, ruler and track with playhead, readout, unsaved dot, zoom, collapse |
| `src2/ui/bar/lanes.lua` | the lanes under ▾: Character, Inputs, Kit & objects, Buttons (bucketed marks from the model) |
| `src2/ui/kit/icon.lua` | icons drawn from frames or a rotated ▼ (play, step, record, pause, start, marker, chevron) |
| `src2/ui/win/inspector.lua` | the Inspector window (sections, rows, pin / hide, options popover) |
| `src2/ui/win/inspectorvalues.lua` | the Inspector's values from the frame shown or the live character (pure functions, no GUI) |
| `src2/ui/win/library.lua` | the Library window |
| `src2/ui/win/merge.lua` | the Merge window |
| `src2/ui/win/help.lua`, `src2/ui/win/helptext.lua` | the Help window and its topics (data) |
| `src2/ui/windows.lua`, `src2/ui/app.lua`, `src2/ui/dock.lua` (modify) | `def.modal`, remembered open state, the new Dock buttons, the bar |
| `src2/world/inputs.lua` or `src2/main.lua` (modify) | the `Marker` column (registered with the other core columns in `main.lua`) |
| `src2/persist/persist.lua`, `src2/persist/library.lua` (modify) | `Persist:readFrames`, `Persist:dirty()`, `Library:folders()` |
| `src2/platform/env.lua`, `src2/kernel/pipeline.lua` (modify) | `Env.notes`, pipeline timing on demand |

`src2/modules.txt`: `ui/kit/icon` after `ui/kit/bezier`; `ui/bar/model`, `ui/bar/lanes`, `ui/bar/bar` after `ui/frost`; the windows after `ui/win/controls`; `ui/app` last before `main`.

---

### Task 1: The timeline model and markers

**Files:** Create `src2/ui/bar/model.lua`; modify `src2/main.lua` (the `Marker` column), `src2/modules.txt`. Test: `tests3/test_barmodel.lua`.

**Interfaces:**
- Produces: column `Marker` (list; `v2 = { key = "Marker", keep = true }`), registered in `main.lua` next to `FrameTime` / `TotalTime`.
- Produces: `BarModel.new(E) -> model`. `model:sync()` is cheap when nothing changed. It rebuilds when the timeline object, `tl.version` or a lower `tl:count()` is seen, and indexes only frames `old count + 1 .. count` when the count grew.
- Produces: `model:events(kind) -> { frame, ... }` (ascending). Kinds:
  - `"state"`: frames whose `State` differs from the frame before;
  - `"death"`: `Died`; `"tool"`: `Tools`; `"input"`: a non-empty `Input`;
  - `"kit"`: `v2KE`; `"button"`: `v2BT`; `"marker"`: `Marker`.
  - A kind whose column isn't registered gives `{}`.
- Produces: `model:range(kind, f0, f1) -> i0, i1` (binary search into `events(kind)`; `i0 > i1` when none); `model.version` (bumps on every change the bar must redraw for).
- Produces: `model:toggleMarker(f, label?) -> boolean` (true = added). It writes `tl:setList("Marker", f, label or true)` / `nil`, updates `"marker"` and bumps `model.version`; `model:markerAt(f)`.

- [ ] **Step 1: Write the failing tests:**
  - `events by kind`: a 10-frame run with State 8,8,3,3,8; Died on 4; Input on 2 and 7; Tools on 5 → `state` {3, 5}, `death` {4}, `input` {2, 7}, `tool` {5}.
  - `grows by the added frames`: append 5 frames with one Input; a spy on `tl:getList` shows only frames 11-15 were read.
  - `rebuilds on change`: `tl:cut(6)` → no event past 6; `tl:adopt(other)` → the other run's events.
  - `markers round trip`: toggle on 3 → `events("marker")` {3}; save with `Run.build` and load into a fresh timeline → the marker on 3; toggle on 3 again → none.
  - `long run` (Review Focus 1): 144,000 frames with an Input every 100th → the first `sync` reads each frame once and takes under 2 s in the mock; a second `sync` reads none.
  - `range`: `range("input", 150, 450)` covers exactly the inputs on 200, 300, 400.
- [ ] **Step 2: Run** `bash tools/build_test3.sh barmodel && (cd tests3 && luau run_barmodel.lua)` — Expected: FAIL (module missing).
- [ ] **Step 3: Implement** the model and the column.
- [ ] **Step 4: Run** the suite, then `bash tools/test_all3.sh` — Expected: PASS; traces SAME (the `Marker` column is empty in the trace scenario and V2 files have none).
- [ ] **Step 5: Commit** `HappaTAS 3: the timeline model and markers`.

### Task 2: The timeline bar

**Files:** Create `src2/ui/kit/icon.lua`, `src2/ui/bar/bar.lua`; modify `src2/ui/app.lua`, `src2/persist/persist.lua` (the saved mark), `src2/modules.txt`. Test: `tests3/test_bar.lua` (`-- needs: ui`).

**Interfaces:**
- Consumes: `BarModel` (Task 1); `E.modes:request` / `allowed`; `E.state` (`mode`, `frame`); `E.settings` (`speedHack`, `speedHackSpeed`, `playbackSpeed`).
- Produces: `Icon.new(ctx, parent, kind, size) -> icon` with kinds `"play"`, `"back1"`, `"forward1"`, `"start"`, `"record"`, `"pause"`, `"marker"`, `"chevron"`; `icon:setKind(kind)`; colour follows the theme (`record` uses the recording colour).
- Produces: `E.persist:dirty() -> boolean`:
  - true when the run has frames and its count or `tl.version` differs from the mark;
  - the mark is set on a successful save or load (bus `persist`, `ok`), and to the empty run on Delete TAS and Idle with no frames.
- Produces: `Bar.new(ui) -> bar`, `ui.bar`:
  - fields: `bar.gui` (holder), `bar.track`, `bar.playhead`, `bar.readout`, `bar.modeLabel`, `bar.unsaved`;
  - `bar.buttons = { start, back1, rec, forward1, test, marker, lanes }`;
  - `bar.view = { first, last }`; `bar:frameAt(x) -> frame` (clamped to `1..max(1, count)`); `bar:xOf(frame) -> x`.
- Transport buttons:
  - `start` = seek 1;
  - `back1` / `forward1` = those requests;
  - `rec`: Idle → `create`, paused → `unpause`, recording → `pause`;
  - `test`: Create → `test`, Test → `create`;
  - `marker` = `model:toggleMarker(E.frame)`.
  - A button whose request isn't allowed is dimmed (transparency 0.6) and does nothing.
- Track:
  - press or drag = seek to `frameAt(x)`, while `E.modes:allowed("seek")`;
  - wheel = zoom ×0.8 / ×1.25 around the pointer's frame, never fewer than 10 frames in view;
  - in Create / Test the view follows the end while it shows the whole run.
- Mode label: `● Recording` uses the dot as text `•` in the recording colour plus the word. `Paused`, `Test` and `Idle` are drawn with icons `pause` / `play`. Speed shows `0.5x` when the speed hack is on, or the playback speed in Test.
- Readout: `frame / count` in the number font, then `Util.toTime(total)`.
- Pools: at most 41 ticks with 11 labels, and 1 playhead. Readout and playhead are written every frame only when they change. The ruler and the marker marks are redrawn when `model.version`, the view or the width changes, at most every 6th frame while recording.

- [ ] **Step 1: Write the failing tests:**
  - `shown in Create and Test, a strip in Idle`: no run → 10 high; Create → 40.
  - `transport`: Idle → `rec` → mode 2 recording; `rec` → paused; `back1` → frame − 1; `start` → frame 1; `test` → mode 3; `test` → mode 2.
  - `seek by dragging` (Review Focus 5): drag past both ends → frames 1 and count; a 1-frame run → 1; no seek requested while recording (`E.frame` unchanged, still recording); scrub in Test to the last frame → `E.frame == count - 1` (Modes:seek's rule).
  - `wheel zoom`: in to 10 frames minimum, out to the whole run; the frame under the pointer stays under it within 1 px.
  - `readout and mode`: `frame / count`, the time, `Paused` / `Recording`; speed hack 0.5 → `0.5x`.
  - `marker button`: a mark appears at the frame's x; a second click removes it.
  - `unsaved dot`: hidden after a load; shown after recording a frame; hidden after a save.
  - `the run changes` (Review Focus 2): a load of a shorter run → the playhead and readout match on the next frame.
  - `long run` (Review Focus 1): 144,000 frames → the number of GUI objects under the bar equals the pools' sizes.
  - `no per-frame writes when nothing changes`: paused, 30 frames → 0 property writes.
  - `clicks never reach the engine`: recording, click on the track → still recording, no Pause.
- [ ] **Step 2: Run** `bash tools/build_test3.sh bar && (cd tests3 && luau run_bar.lua)` — Expected: FAIL.
- [ ] **Step 3: Implement** `icon`, `bar`, `Persist:dirty`, and the bar's start in `UI.start`.
- [ ] **Step 4: Run** the suite, then `bash tools/test_all3.sh` — Expected: PASS, `BENCH OK` (the bar shows in the bench's Create / Test modes; V2 shows its stats panels there).
- [ ] **Step 5: Commit** `HappaTAS 3: the timeline bar`.

### Task 3: The lanes

**Files:** Create `src2/ui/bar/lanes.lua`; modify `src2/ui/bar/bar.lua`. Test: `tests3/test_bar.lua` (new sections).

**Interfaces:**
- Consumes: `model:events` / `range` (Task 1), `bar.view` / `bar:xOf` (Task 2).
- Produces: `Lanes.new(bar) -> lanes`, `bar.lanes`. Lanes, top to bottom:
  - "Character": `state`, `death` in the recording colour, `tool`;
  - "Inputs": `input`;
  - "Kit & objects": `kit`;
  - "Buttons": `button`.
  - Each mark is a 2 × 10 frame. Events in the same 2-pixel column share one mark, at most 300 marks per lane.
- `bar.buttons.lanes` (a `chevron` icon) opens and closes them (remembered in the `ui` table: `bar = { lanes = bool }`). Closed lanes cost nothing per frame.

- [ ] **Step 1: Write the failing tests:**
  - `lanes show the events`: the Task 1 run → a Character mark at frame 3's x, a recording-coloured one at 4, Inputs at 2 and 7.
  - `bucketed`: 10,000 inputs on a 600-px track → ≤ 300 marks.
  - `follow zoom`: zoom into frames 1-50 → only marks for events in 1-50.
  - `closed = no objects updated`: with the lanes closed, recording 60 frames writes nothing under the lanes.
  - `remembered`: open, re-run (`boot` again) → open.
- [ ] **Step 2: Run** the bar suite — Expected: FAIL.
- [ ] **Step 3: Implement** the lanes.
- [ ] **Step 4: Run** the suite and `bash tools/test_all3.sh` — Expected: PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: timeline lanes`.

### Task 4: The Inspector

**Files:** Create `src2/ui/win/inspectorvalues.lua`, `src2/ui/win/inspector.lua`; modify `src2/ui/windows.lua` (`def.modal`, remembered open state), `src2/ui/app.lua`, `src2/kernel/pipeline.lua` (timing), `src2/modules.txt`, `tests3/test_ui.lua` (its start section: a window is open now, the Inspector, and the mouse still isn't freed). Test: `tests3/test_inspector.lua` (`-- needs: ui`).

**Interfaces:**
- Produces: `Windows:define(id, def)` takes `def.modal` (default true); `E.modal` / `E.modalOpen()` count only modal windows. Open windows are remembered in `ui.open[id]`, and reopened on start (`def.openByDefault` when there is no saved state).
- Produces: `pipe.timing = true` makes `Pipeline:run` add its `os.clock` time to `pipe.timeSum` / `pipe.frames` (PreRender counts frames). Off by default: no extra calls.
- Produces: `InspectorValues.rows(E) -> { { section, key, label, value } ... }`, values as display strings:
  - **Frame:** frame, frame time, total time, speed.
  - **Character:** rig type, state, position, rotation, velocity, angular velocity, move direction, walk / jump, health, floor.
  - **Camera & input:** camera rotation, zoom, keys, mouse.
  - **World:** client objects, kit, buttons.
  - **Performance:** FPS, HappaTAS ms.
  - Sources follow V2's `SS.Idle` / `SS.Create` / `SS.Test` (p18_core.lua 177-260 at b1569bd):
    - paused in Create: the frame's columns (keys = `E.inputs:describe(E.inputs:heldAt(tl, f))`);
    - recording / Idle: the live character;
    - Test: the playback time, the playback speed, the replayed keys and mouse.
  - Number formats are V2's: 3 decimals, rotations in degrees YXZ, times by `Util.toTime`.
- Produces: the Inspector window (`id = "inspector"`, `modal = false`, `openByDefault = true`):
  - collapsible sections; every row has pin and hide (an options popover lists hidden rows to bring back); pinned rows also show in a "Pinned" section at the top. Kept in the `ui` table as `inspector = { pinned = {}, hidden = {}, collapsed = {} }`.
  - The options popover has the four stats settings.
  - Updates every 2nd frame while recording or testing, on frame change while paused, and never while closed or minimised. Performance turns `pipe.timing` on only while its section shows.

- [ ] **Step 1: Write the failing tests:**
  - `every V2 stats value` (values module, no GUI): paused on frame f → position = the frame's Cframe to 3 decimals, state name, zoom, keys = V2's `Describe` text for the held set, mouse = `MX, MY`; Idle → the live root; Test → time and speed.
  - `non-modal`: Inspector open, Settings closed → `E.modal == false`; Settings open → true.
  - `opens by default, remembered`: first start → open; close, re-run → closed.
  - `pin / hide`: pin "Zoom" → it shows in Pinned; hide "Health" → gone, back from the options popover; both kept after a re-run.
  - `stats settings` (spec 6.3): `showStatsCreate = 0` → one line "Hidden in Create"; Test at speed 0.5 → the Frame section still shows; `statsTextSize = 20` → value labels at size 20.
  - `the run changes` (Review Focus 2): paused on frame 900, load a 100-frame run → rows for frame 100.
  - `update rate`: recording 60 frames → rows written on ≤ 30 frames; paused 30 frames → none.
  - `Performance timing only when shown`: section collapsed → `pipe.timing == false`.
- [ ] **Step 2: Run** `bash tools/build_test3.sh inspector && (cd tests3 && luau run_inspector.lua)` — Expected: FAIL.
- [ ] **Step 3: Implement** the windows change, the timing, the values module and the window.
- [ ] **Step 4: Run** the suite, `windows`, `ui`, then `bash tools/test_all3.sh` — Expected: PASS, `BENCH OK` (the Inspector now opens by default in every bench mode, next to V2's stats panels).
- [ ] **Step 5: Commit** `HappaTAS 3: the Inspector`.

### Task 5: The Library

**Files:** Create `src2/ui/win/library.lua`; modify `src2/persist/library.lua` (`folders`), `src2/ui/app.lua`, `src2/modules.txt`. Test: `tests3/test_librarywin.lua` (`-- needs: ui`), `tests3/test_library.lua` (folders).

**Interfaces:**
- Consumes: `E.library` (`list`, `sorted`, `search`, `groups`, `rename`, `move`, `delete`, `createFolder`, `deleteFolder`, `nextAttemptName`); `E.persist:save(name, folder, asAttempt)` / `load(path)`; bus `persist`; `Files.cleanName`.
- Produces: `Library:folders() -> { "", "A", "A/B", ... }`: every folder, empty ones too, to the 3-level limit, sorted by name.
- Produces: the Library window (`id = "library"`, modal):
  - a folder sidebar with "All runs", the folders, and New folder / Delete folder (empty folders only);
  - a search field and a sort dropdown: Name / Date / Length × ascending / descending;
  - the list: name, `Util.toTime(length)`, frames, saved (`os.date("%Y-%m-%d %H:%M")`); attempts nested under their run (`groups`), opened with a `chevron`;
  - an info line for the selection: size, version, script, kit / speed hack use, created;
  - a name field and buttons Load / Save / New attempt / Merge / Rename / Move / Delete.
- Button rules:
  - Save writes the name field into the shown folder. A name that exists asks for a second click within 3 s ("Overwrite?").
  - New attempt = `save(name, folder, true)`.
  - Rename takes the name field; Move takes a folder from a dropdown.
  - Delete asks for a second click ("Delete?" for 3 s).
  - While `E.busy`, Load / Save / New attempt / Merge are dimmed.
  - Results show through the existing `status` toast.
  - The list refreshes on open and on every `persist` event.

- [ ] **Step 1: Write the failing tests:**
  - `folders`: `A`, `A/B` and an empty `C` → `{ "", "A", "A/B", "C" }`.
  - `list, sort, search`: three runs → by name, by date descending, by length; search "tow" → the matching ones; attempts "Run (2)", "Run (3)" nested under "Run", newest first.
  - `save and load through the window`: Save "My run" → the file exists, the unsaved dot hides; Load it → `tl:count()` as saved.
  - `refusals` (Review Focus 3): Save while recording → the toast "Pause before saving", no file; Load from Test → "Go Idle or pause before loading"; any button while `E.busy` → dimmed, nothing called.
  - `names` (Review Focus 4): empty → refused; `a/b` → cleaned or refused as `Files.cleanName` says; 200 characters → as `cleanName` says; "my run" when "My run" exists → the overwrite question; second click → saved over.
  - `delete asks twice`: one click → still there; second click within 3 s → gone; after 3 s the first click is forgotten.
  - `rename and move`: rename to "B" → listed as B; move to folder A → under A.
  - `typing in the fields never runs a control` (`2` in the name field: still Idle).
- [ ] **Step 2: Run** `bash tools/build_test3.sh librarywin && (cd tests3 && luau run_librarywin.lua)` and `library` — Expected: FAIL.
- [ ] **Step 3: Implement** `Library:folders` and the window.
- [ ] **Step 4: Run** both suites and `bash tools/test_all3.sh` — Expected: PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: the Library window`.

### Task 6: Merge

**Files:** Create `src2/ui/win/merge.lua`; modify `src2/persist/persist.lua` (`readFrames`), `src2/ui/win/library.lua` (the Merge button), `src2/ui/app.lua`, `src2/modules.txt`. Test: `tests3/test_mergewin.lua` (`-- needs: ui`).

**Interfaces:**
- Produces: `Persist:readFrames(path) -> true, "started" | false, why` (same busy / availability rules as `load`).
  - On its thread it reads the file into `Timeline.newLike(E.tl)`, calls the plugins' `onLoading` on it, then emits `persist` with `{ op = "frames", ok, frames = fresh:toV2All(), message, path }`.
  - The run in use is untouched.
- Produces: the Merge window (`id = "merge"`, modal), opened by the Library's Merge with the selected path.
  - "You must have a TAS to merge" when `E.tl:count() == 0`.
  - Reading → Before / After buttons (enabled per the Running rule) and Cancel.
  - After a choice: `E.mergeRun:startMerge(frames, "before" | "after")`. The window then shows "Current distance" (`E.mergeDistance`, 3 decimals) and "Distance required" (`E.mergeRun.reqDist`), and one button: "Complete merge" (green, `E.mergeCanComplete`) or "Cancel merge" (red) → `E.mergeRun:finishMerge()`.
  - Closing the window during a merge cancels it.

- [ ] **Step 1: Write the failing tests:**
  - `readFrames`: a saved 50-frame run → the event with 50 frames; the run in use unchanged.
  - `Running rule`: a run whose last frame is Running and first isn't → Before enabled, After dimmed.
  - `merge after, completed`: start → `E.merge`; move the character within the required distance of the goal (set the root's CFrame), record 3 frames → the button reads "Complete merge" → click → `E.merge == false`; `tl:count()` = before + recorded + after − 1; "Merge Complete" toast.
  - `cancelled`: far away → "Cancel merge" → click → the old run back frame for frame.
  - `refusals` (Review Focus 3): an empty run → the message, no read; while `E.busy` → dimmed.
  - `closing cancels`: close the window mid-merge → the old run back.
- [ ] **Step 2: Run** `bash tools/build_test3.sh mergewin && (cd tests3 && luau run_mergewin.lua)` — Expected: FAIL.
- [ ] **Step 3: Implement** `readFrames`, the window and the Library button.
- [ ] **Step 4: Run** the suite, `librarywin`, and `bash tools/test_all3.sh` — Expected: PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: the Merge window`.

### Task 7: Help

**Files:** Create `src2/ui/win/helptext.lua`, `src2/ui/win/help.lua`; modify `src2/platform/env.lua` (`Env.notes`), `src2/ui/app.lua`, `src2/modules.txt`. Test: `tests3/test_help.lua` (`-- needs: ui`).

**Interfaces:**
- Produces: `Env.notes`, a list of the texts `Env.debugNote` was given, each once, kept whatever `CONFIG.Debug` is (printing still only with Debug).
- Produces: `HelpText.topics -> { { id, title, body } ... }`. A body may hold `{key:<control>}`, replaced by the control's current key name (`E.controls:get`).
- Produces: the Help window (`id = "help"`, modal): a topic list, a search field (title and body, as you type), and the text.
  - The topic "Missing executor functions" lists `Env.notes`, or "None: every feature is available".
  - The "Credits" topic is the exact five lines of the Global Constraints.

- [ ] **Step 1: Write the failing tests:**
  - `every V2 help topic has a home`: each of V2.38.17's help titles (listed in the test as a table, from `git show aaa21b6:src/parts/p04_ui.lua`, minus "Keyboard & Click Sounds") is a topic title or named in a topic's body.
  - `keys are live`: rebind Pause to `P` → the Pause topic says `P`.
  - `search`: "merge" → only topics mentioning it.
  - `missing functions`: with `getconnections` removed in the mock (`M.noGetConnections`) → the topic lists the Kit Clock note; with everything → "None: …".
  - `credits exact`: the five lines.
  - `text the fonts have`: covered by `test_ui`'s check (run it).
- [ ] **Step 2: Run** `bash tools/build_test3.sh help && (cd tests3 && luau run_help.lua)` — Expected: FAIL.
- [ ] **Step 3: Implement** `Env.notes`, the topics and the window.
- [ ] **Step 4: Run** the suite, `ui`, then `bash tools/test_all3.sh` — Expected: PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: the Help window`.

### Task 8: Together: Dock, test_ui, bench

**Files:** Modify `src2/ui/app.lua`, `src2/ui/dock.lua`, `tests3/test_ui.lua`, `tests3/trace/bench.lua`, `tools/bench3.sh` (if needed). Test: `tests3/test_ui.lua`, `bash tools/bench3.sh`.

**Interfaces:**
- The Dock lists Inspector, Library, Settings, Controls, Help (Merge opens from the Library).
- Bench modes add "recording, Inspector open" and "Test, lanes open". Measured with the mouse moving and still: it records the phase 5a follow-up ("recording, menu open" with the mouse moving), as information.

- [ ] **Step 1: Write the failing tests** in `test_ui`:
  - `start`: the Dock has its 5 buttons; the bar is a strip; the Inspector is open and non-modal.
  - `record, save, load, merge, Test, Idle with every window open`: no click pauses; the frames are recorded.
  - `Unload`: no GUI, no UserInputService connection, `pipe.timing` off, no marker hitboxes or merge parts.
  - `text the fonts have` over every window.
- [ ] **Step 2: Run** `bash tools/build_test3.sh ui && (cd tests3 && luau run_ui.lua)` — Expected: FAIL (the Dock has 2 buttons).
- [ ] **Step 3: Implement** the Dock order and the bench modes.
- [ ] **Step 4: Run** `bash tools/test_all3.sh` — Expected: PASS, `BENCH OK`. Every gated mode stays within V2's 10 %; the new modes are printed.
- [ ] **Step 5: Commit** `HappaTAS 3: phase 5b together`.

### Task 9: Live check

**Files:** Modify `docs/superpowers/specs/2026-10-18-happatas3-rewrite-design.md` (13: phase 5b live numbers). Fixes found live: in their own files, each with a test that failed first.

- [ ] **Step 1: Prepare** the backups (Global Constraints) and the release build `bash tools/build3.sh --release wow3` into `HappaTasTest/`, plus a debug copy (`Debug = true`).
- [ ] **Step 2: Check in the EToH kit test place:**
  - the bar's icons look right (screenshot);
  - record, pause, drag the playhead, scrub in Test, zoom, and open the lanes, all with VIM mouse events;
  - markers saved and loaded;
  - Inspector values against V2.38.16's panels on the same frame (V2 loaded alone, the same frame);
  - Library: save, attempt, folder, rename, move, delete, load, all on files under a `zz5b` folder, deleted afterwards;
  - a merge completed and one cancelled;
  - Help topics and the missing-functions list;
  - per-frame cost (the pipeline wrapper) with the bar, with the Inspector open, and with the mouse moving with a window open (the 5a follow-up);
  - Unload leaves nothing; the release is silent.
- [ ] **Step 3: Clean up:** files byte-identical, `HappaTasTest` and `zz5b` deleted, fps cap and graphics quality as before, unloaded.
- [ ] **Step 4: Write** spec 13's phase 5b entry; commit `HappaTAS 3 phase 5b: live check`.
