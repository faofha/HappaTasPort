# HappaTAS 3 Live Frame Cost Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** HappaTAS 3's per-frame cost in the live client at or below V2.38.17's in recording, paused and Test, with the same behaviour.

**Architecture:** Measure first, with tools kept in the repo: an outside meter that times both scripts' frame handlers the same way, and a section profiler that times named pieces in both. Then fix the measured pieces one at a time. Each fix keeps the headless traces line-for-line SAME and is checked live, before and after, with the meter. The headless bench can't be the gate for time here: the mock's own Instance reads and Lua datatypes dominate its frame, so it shows HappaTAS 3 within V2 while the client doesn't. Subtracting a measured per-read cost was tried on 2026-11-01 and gave negative times. The bench stays the gate for reads / writes; the live meter is the gate for time.

**Tech Stack:** Luau (src2/, bundled by tools/build3.sh), the headless mock (tests/mock, tests3/), Real executor in the live client (Real MCP).

**Spec:** docs/superpowers/specs/2026-10-18-happatas3-rewrite-design.md — section 13, the phase 5c live entry (commit e5406c5) has the measurements this plan starts from.

## Global Constraints

- Conservative Luau only: no `+=`, `//`, backtick strings, `continue`, if-expressions; never name getfenv / setfenv; 200 locals per function.
- No network code (HttpGet / request / loadstring) in src2/.
- Behaviour unchanged: `bash tools/trace3.sh` stays SAME for the main, diffco and world traces, and `bash tools/test_all3.sh` passes (run it with `timeout 3600`, in a temporary worktree of the commit: it globs every tests3/test_*.lua).
- Bench reads / writes never above V2's in any gated mode (tools/bench3.sh).
- Live tests: the EToH kit test place 72164126024589 only, never Tower Creator.
  - Before: back up HappaTasPort/Settings.json, Settings3.json and the place folder; record getfpscap() and the graphics quality.
  - After: put all of them back byte for byte / as recorded, delete HappaTasTest/, leave nothing loaded.
- The live acceptance numbers come from the same meter run on both scripts, never from two different methods.
- Commits: `git -c user.name="Claude" -c user.email="noreply@anthropic.com"`, ending "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>". No push without asking dzr.

## Review Focus

1. A run cut back (Back / Return, Delete TAS, a merge) and then recorded again: the new frames start from zeros and empty lists, never values left over from the cut frames (Task 2 test).
2. A plugin that errors in a hook: reported once as "name.hook", the other plugins' hooks still run in order, and a plugin added or removed later is seen on the next call (Task 3 test).
3. The kit objects reading a run that was cut, loaded or merged: the frame views read the run as it is now, never a stale row (Task 4 test).
4. 240 FPS frames without a physics step and Frame Step / speed hack paths: covered by the world trace staying SAME (every task's gate).
5. Unload after any of these changes leaves nothing behind (test_ui's Unload section, every gate).

---

## File Structure

| File | Responsibility |
|---|---|
| `tools/live/meter3.lua` (new) | Live harness, loaded through Real: `Meter.compare(opts)` runs V2 and HappaTAS 3 in alternating rounds and times each script's frame handlers from outside; `Meter.sections(file, labels)` times named functions (exclusive time) inside one script. |
| `tools/live/v2expose.sh` (new) | Writes a copy of V2.38.17 that also sets `genv.__V2T` (its module tables) for the section profiler. |
| `src2/engine/timeline.lua` | `append` clears only rows used before; `setN` / `getN` without `select` loops. |
| `src2/engine/plugins.lua` | Hook dispatch from prebuilt function lists. |
| `src2/world/kit/objects.lua` | Frame views cached per index. |
| Pieces found by Task 1's table | Changed in Task 5, each in its own file. |

### Task 1: Live meter and section profiler

**Files:** Create `tools/live/meter3.lua`, `tools/live/v2expose.sh`. Modify `docs/superpowers/specs/2026-10-18-happatas3-rewrite-design.md` (13: the baseline table).

**Interfaces:**
- Produces: `Meter.compare({ v2 = path, h3 = path, rounds = 3, modes = { "rec", "paused", "test" } }) -> { [script] = { [mode] = { total = us, stages = { PreRender = us, ... } } } }` (medians over rounds).
  - It matches V2's Settings.json to Settings3.json for the run (Sync Client Objects, Record Tool Actions, Show Stats (Idle / Create / Test), Show MicroProfiler 0; Settings3 interface "Classic") and restores both files at the end, also on error.
  - It puts the character back on the start spot before each run and walks the same direction.
  - Hooks: the RunService signals' `__index` (Connect / Once wrap the handler) and `game`'s `__namecall` (BindToRenderStep). Both are removed at the end.
- Produces: `Meter.sections(path, specs, mode, seconds) -> { [label] = us }`: exclusive time per wrapped function (a wrapper subtracts its children). `specs` is a list of `{ table, key, label }`; HappaTAS 3 tables come from the debug build's `__HappaTAS3_T.engine`, V2's from `__V2T`.
- `tools/live/v2expose.sh IN OUT`: sed of `genv["__HappaTAS"] = handle` that also sets `genv.__V2T = { C, Bridge, InputSys, Cursor, AnimEngine, ClientObjects, Buttons, Lighting, ToolSync, SpeedHack, KitClock, KitObjects }`.

- [ ] **Step 1:** Write both files from the jobs used on 2026-11-01 (spec 13 describes them). Keys go through VirtualInputManager with dzr's controls from Settings3.json: create, pause / unpause, test, idle.
- [ ] **Step 2:** Run `Meter.compare` live (3 rounds). Expected: HappaTAS 3 above V2 as in spec 13 (recording ~+25-30 %). Write the per-stage medians into spec 13 as the baseline.
- [ ] **Step 3:** Run `Meter.sections` on both scripts in recording, paused and Test. HappaTAS 3: every engine handler, every plugin hook, and the methods of `tl`, `kitObjects`, `cam`, `char`, `inputs`, `anim`, `cursor`. V2: every function in the exposed tables plus its core handlers. Write a table into the ledger: each HappaTAS 3 piece next to its V2 counterpart (the port's header names it), with the difference in us.
- [ ] **Step 4:** Commit `HappaTAS 3: live meter and section profiler`.

### Task 2: Timeline append and multi-value columns

**Files:** Modify `src2/engine/timeline.lua`. Test `tests3/test_timeline.lua`.

**Interfaces:**
- Produces: `Timeline.used` (the highest row ever appended, kept over `cut` / `removeLast` / `adopt`). `append` fills a row only when `i <= used`; lists are cleared the same way.
- `setN(name, i, ...)` / `getN(name, i)`: no `select` loop. Widths 1, 3 and 12 (the columns that exist: CamCframe 12, Cframe / velocities 3) are written and read directly; other widths keep a loop over a packed table.

- [ ] **Step 1: Write the failing tests** in test_timeline:
  - "a cut run records from zeros": append 5 rows, set every column, cut to 2, append 3. Rows 3-5 read 0 in every numeric column and nil in every list.
  - "setN / getN round trip at widths 1, 3, 12": values 1..12 written and read back exactly.
  - "append doesn't clear rows never used": with the bench's column set, a counter on `buffer.fill` calls (a test-only wrapper, set through a `Timeline._fill` field the module uses instead of `buffer.fill` directly) reads 0 for 100 appends into a fresh timeline and the full column count after a cut.
- [ ] **Step 2: Run** `bash tools/build_test3.sh timeline && (cd tests3 && luau run_timeline.lua)`. Expected: FAIL on the fill counter.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite, then `bash tools/trace3.sh`. Expected: PASS, traces SAME. Live: `Meter.sections` on `tl:append`, `tl:setN` drops (record the before / after in the ledger).
- [ ] **Step 5: Commit** `HappaTAS 3: timeline append and setN without per-frame waste`.

### Task 3: Plugin hook dispatch

**Files:** Modify `src2/engine/plugins.lua`. Test `tests3/test_plugins.lua`.

**Interfaces:**
- `Plugins:call(hook, ...)` unchanged for callers. `byHook[hook]` becomes `{ fns = { f1, ... }, ps = { p1, ... }, names = { "p1.hook", ... } }`, built on the first call after an add / remove. The loop is `pcall(fns[i], ps[i], ...)`; an error reports `names[i]` (no string concatenation per call).

- [ ] **Step 1: Write the failing tests** in test_plugins:
  - "a hook resolved once": a plugin whose hook is replaced on the instance after the first call keeps the resolved one until an add / remove. This pins the cache, and the lookup it saves.
  - "an erroring hook": reported once as "name.hook", the next plugin still runs, in order.
  - "add / remove": seen on the next call.
- [ ] **Step 2: Run** `bash tools/build_test3.sh plugins && (cd tests3 && luau run_plugins.lua)`. Expected: FAIL on "resolved once".
- [ ] **Step 3: Implement.** Check that the live profiler's hook swap (it resets `byHook`) still works.
- [ ] **Step 4: Run** the suite, the traces and the live section numbers for `plugins:call`. Expected: PASS, SAME, lower.
- [ ] **Step 5: Commit** `HappaTAS 3: plugin hooks dispatched from prebuilt lists`.

### Task 4: Kit objects' frame views

**Files:** Modify `src2/world/kit/objects.lua` (`framesOf`). Test `tests3/test_kit.lua`.

**Interfaces:**
- `framesOf(tl)[i]` returns the same proxy table for the same index (a per-view cache keyed by index). The proxy still reads through `tl` on every field access, so a cut / load / merge never leaves a stale value.

- [ ] **Step 1: Write the failing tests** in test_kit:
  - "the same proxy for an index": `framesOf(tl)[3] == framesOf(tl)[3]`.
  - "a cut and re-recorded run reads its new values": TotalTime of frame 3 after cut + append + set equals the new value.
  - "out of range": index 0 and count + 1 return nil.
- [ ] **Step 2: Run** `bash tools/build_test3.sh kit && (cd tests3 && luau run_kit.lua)`. Expected: FAIL on "the same proxy".
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite, the traces and the live section numbers for the four kit hooks. Expected: PASS, SAME, lower.
- [ ] **Step 5: Commit** `HappaTAS 3: kit objects' frame views cached`.

### Task 5: The remaining pieces from Task 1's table

**Files:** The ones each piece lives in, plus that module's test file.

**Interfaces:** Each change keeps its function's signature. The rule:
- Take the pieces in Task 1's table where HappaTAS 3 is at least 5 us a frame above its V2 counterpart, largest first.
- Find the cause in the piece's own code: work V2 doesn't do, or does less often.
- Change it to V2's way, or cheaper with the same result.
- Stop when `Meter.compare` shows HappaTAS 3 at or below V2 in all three modes, or the table has no piece left at 5 us or more.

- [ ] **Step 1:** For each piece, write a test in its module's suite that fails first. It pins what makes the piece cheaper (a call that no longer happens, a value cached, a cadence), with the behaviour assertions unchanged.
- [ ] **Step 2:** Run it. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the suite and the traces (SAME), and record the piece's live before / after in the ledger.
- [ ] **Step 5:** Commit `HappaTAS 3: <piece> cheaper per frame`, one commit per piece.

### Task 6: Live acceptance

**Files:** Modify `docs/superpowers/specs/2026-10-18-happatas3-rewrite-design.md` (13).

- [ ] **Step 1:** Build the release and the debug copy into HappaTasTest/ (backups first: Global Constraints).
- [ ] **Step 2:** Run `Meter.compare` (3 rounds). Expected: HappaTAS 3 median ≤ V2 median in recording, paused and Test, and every stage within 5 us of V2 or below. If not, back to Task 5 with the new table.
- [ ] **Step 3:** Check the release loads with no console line and unloads clean. Clean up: files byte-identical, fps cap / quality as recorded, HappaTasTest deleted.
- [ ] **Step 4:** Run `bash tools/test_all3.sh` in a worktree. Expected: ALL PASSED, BENCH OK.
- [ ] **Step 5:** Write the before / after table into spec 13 and commit `HappaTAS 3: live frame cost at V2's`.
