# HappaTAS 3 Phase 5c: the classic interface and touch buttons — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A setting that switches between HappaTAS 3's interface and V2.38.17's classic one at once (spec 8.5), both on the one settings store (6.3), plus touch buttons and thumbstick replay on phones and tablets (spec 2, 8.2), and six of the seven minors phase 5b deferred (no work while the interface is hidden in Task 1, the other five in Task 10; the bar index rebuild after a cut stays as it is: measured at 1.6 ms for 100,000 frames).

**Architecture:** The classic interface is V2.38.17's interface rebuilt inside HappaTAS 3: V2's style and tree data (`src/parts/p04_ui.lua` at `aaa21b6`) ported as data into `src2/ui/classic/tree.lua`, built by a small builder, and wired by new code that talks only to the engine (`E.modes:request`, `E.settings`, `E.controls`, `E.persist`, `E.library`, `E.mergeRun`). `src2/ui/app.lua` owns both interfaces and a switch: only one is live at a time, the other is hidden and does no per-frame work. Touch buttons are a small piece of each interface: the new one draws its own pad from the kit's icons, the classic one wires V2's `Mobile` folder.

**Tech Stack:** Luau (conservative syntax), Roblox GUI instances, phase 5a's kit for the new interface's touch pad, the headless mock (`tests/mock/`) and `luau`.

**Spec:** `docs/superpowers/specs/2026-10-18-happatas3-rewrite-design.md`: 2 (mobile support kept), 6.3 (one settings store), 8.2 (windows as sheets on mobile), 8.5 (classic interface, its tests), 11, 12, 13. Reference look and behaviour: V2.38.17 (`git show aaa21b6:src/parts/p04_ui.lua`, `p19_menu.lua`, `p18_core.lua` stats panels and mobile buttons).

## Global Constraints

- Everything in the phase 1-5b plans' Global Constraints still holds:
  - conservative Luau (no `+=`, `//`, backtick strings, `continue`, if-expressions);
  - no network code; executor lookups with fallbacks through `platform/env`;
  - game code only through `GameCall` / `task.spawn(pcall, ...)`;
  - Debug output only with `CONFIG.Debug`; version `"3.0.0-dev"`;
  - never commit `CLAUDE.md` / `claude/`; commit only the files a task lists;
  - never name `getfenv` / `setfenv` (deopt guard);
  - no GUI property written unless it changes (`W.set` / `W.paint` in the new interface; the classic one compares before writing); `AutoLocalize = false` on every ScreenGui;
  - no per-frame work while nothing changes; Unload leaves nothing (`test_ui` counts UserInputService connections).
- Branch `v3-rewrite` (PR #20 open with phase 5b, Auto-fix on: commits pushed there join PR #20 until it is merged; after that, a new PR). Do not edit `src/parts/`, `wow`, `wow1`, `tests/test_*.lua`.
- **Text in the new interface: only ASCII and `× ▼ ← … •`** (phase 5a, measured live). The classic interface keeps V2.38.17's text and images (rbxassetid icons) as V2 drew them.
- **Ruling: the setting.** `interface`, choice `{ "New", "Classic" }`, section Interface, default `"New"`, desc "New is HappaTAS 3's interface, Classic is V2's". V2 had no such setting (no `v2` name).
- **Ruling: only one interface is live.** The other is hidden (`ScreenGui.Enabled = false`) and has no pipeline handler and no `UserInputService` reaction. The engine's hooks (`E.inputs.mouseOverOwn`, `E.modalOpen` / `E.modal`) answer for the live one. The Menu key shows / hides the live one.
- **Ruling: classic Help shows HappaTAS 3's topics** (`ui/win/helptext`) in V2's expandable rows, not V2's old texts (they describe V2). No update log until phase 7.
- **Ruling: classic Saves lists the runs at the top of the place folder** (V2 had no folders); runs in folders show only in the new interface's Library. Saving, loading and merging follow the same rules as the Library (`Persist` messages, `Files.cleanName`, a second click before overwriting, never an empty run).
- **Ruling: touch buttons show when `UserInputService.TouchEnabled` and not `KeyboardEnabled`** (the same test as phase 5a's sheets), for either interface.
- **Ruling: holding Back / Forward on a touch button** uses a new `Modes:release(which)` (`which` = `"back"` / `"forward"`), which clears `E.back` / `E.forw` the way the key's release does (`engine/frame.lua:302-303`).
- Live tests (Real MCP; dzr: "Real is always connected"): back up `HappaTasPort/Settings.json`, `Settings3.json` and the place's files and restore them byte-identical; record `getfpscap()` and the graphics quality and put them back; use `HappaTasTest/` and delete it; never run HappaTAS in Tower Creator; mouse through `VirtualInputManager`; wrap every eval in `pcall`.

## Review Focus

1. **Switching interfaces at an awkward moment** (while recording, during a merge, with a text box focused, while a key is being rebound, with a window or the classic menu open): recording goes on, the merge goes on, typing and rebinding end cleanly, the mouse is freed or locked as the live interface says. Test in Task 1.
2. **A setting changed while the other interface is hidden or not built yet**: it shows the new value the moment it appears, and the classic one never writes an Appearance value it doesn't draw (glass, blur, edge light, corners, button shape, shadows, animations, easing). Test in Tasks 3 and 7.
3. **Names typed in classic Saves** (empty, `/`, the same name in another case, an existing name, 200 characters) and an empty run: the same answers as the Library. Test in Task 5.
4. **A laptop with a touch screen** (TouchEnabled and KeyboardEnabled): no touch buttons; a phone: touch buttons, and a single tap during Test never quits it (two taps do). Test in Task 8.
5. **Unload and a re-run with Classic chosen**: nothing left of either interface, no connection left, the re-run opens Classic. Test in Task 11.

---

## File Structure

| File | Responsibility |
|---|---|
| `src2/ui/app.lua` (modify) | both interfaces, the switch, the engine hooks for the live one |
| `src2/ui/classic/tree.lua` | V2.38.17's styles and tree as data (ported from p04), changes listed in Task 2 |
| `src2/ui/classic/build.lua` | builds a tree into instances (styles, children, names), returns them by path |
| `src2/ui/classic/classic.lua` | the classic interface: ScreenGui, show / hide, Menu, tabs, More, Help, status line |
| `src2/ui/classic/settingsrows.lua` | the settings list bound to the store (every schema row) |
| `src2/ui/classic/controlsrows.lua` | the controls list and rebinding |
| `src2/ui/classic/saves.lua` | the Saves tab and the merge dialog / Merge Stats |
| `src2/ui/classic/stats.lua` | V2's Idle / Create / Test stats panels |
| `src2/ui/classic/look.lua` | the Appearance values the classic interface draws |
| `src2/ui/classic/mobile.lua` | V2's Mobile folder wired to the engine |
| `src2/ui/touch.lua` | the new interface's touch pad |
| `src2/world/thumbstick.lua` | recording and replaying the touch thumbstick (V2's ReadMobile / ReplayMobile) |
| `src2/engine/settings.lua`, `src2/engine/modes.lua` (modify) | the `interface` setting, `Modes:release` |
| `src2/ui/windows.lua`, `src2/ui/bar/*.lua`, `src2/ui/win/inspector.lua`, `src2/persist/persist.lua` (modify) | the 5b follow-ups (Task 9) |

`src2/modules.txt`: `ui/classic/tree`, `ui/classic/build`, `ui/classic/look`, `ui/classic/settingsrows`, `ui/classic/controlsrows`, `ui/classic/saves`, `ui/classic/stats`, `ui/classic/mobile`, `ui/classic/classic`, `ui/touch` after `ui/win/help`; `ui/app` stays last before `main`.

---

### Task 1: The switch

**Files:** Modify `src2/engine/settings.lua`, `src2/ui/app.lua`, `src2/ui/root.lua` (if hiding needs it), `src2/ui/bar/bar.lua`, `src2/ui/win/inspector.lua`; create `src2/ui/classic/classic.lua` (a stub: a ScreenGui named `HappaTASClassic` with an empty `MainMenu` frame, `show(on)`, `pointerOver()`, `modal()`, `destroy()`). Test: `tests3/test_interface.lua` (`-- needs: ui`).

**Interfaces:**
- Produces: setting `interface` (Global Constraints).
- Produces: `UI:setInterface(name: "New" | "Classic")`, called on start with the stored value and on every change of the setting. `UI.live` = `"New"` or `"Classic"`; `UI.classic` = the classic interface once built (built the first time it is chosen).
- Produces: `UI:liveShown() -> boolean` (the live interface is shown: Menu key state); `E.inputs.mouseOverOwn` and `E.modalOpen` ask the live interface.
- Produces: the new interface hidden (Menu key or the switch) means no pipeline handler of the bar, the Inspector, Library or Merge runs (the 5b deferred minor #12).

- [ ] **Step 1: Write the failing tests:**
  - `default New`: `UI.live == "New"`, no `HappaTASClassic` ScreenGui.
  - `switch at once`: `settings:set("interface", "Classic")` → the new root's ScreenGui `Enabled == false`, `HappaTASClassic` exists and is enabled, all in the same frame; back to New → the reverse; the classic one is not built again (same instance).
  - `hidden does nothing`: with Classic live (and with New hidden by the Menu key), count `T.pipe` handlers whose module is `"ui"` and whose name starts `ui.bar` / `ui.inspector`: none; Instance writes under the new root over 60 frames of recording: 0.
  - `awkward moments` (Review Focus 1): recording → switch → still recording, frames keep coming; a merge running → switch → `E.merge` still true; the Settings search box focused → switch → `E.typing:active(nil) == false`; rebinding in Controls → switch → `E.typing.rebinding == false`; Settings open (mouse free) → switch to Classic with its menu closed → `E.modal == false`.
  - `the Menu key` toggles the live interface only.
- [ ] **Step 2: Run** `bash tools/build_test3.sh interface && (cd tests3 && luau run_interface.lua)` — Expected: FAIL (no setting).
- [ ] **Step 3: Implement** the setting, `setInterface`, the stub and the hidden-means-idle rule (the bar and the Inspector `follow()` also check `ui:liveShown()` and `ui.live == "New"`).
- [ ] **Step 4: Run** the suite, `ui`, `bar`, `inspector`, then `bash tools/test_all3.sh` — Expected: PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: the interface switch`.

### Task 2: The classic tree

**Files:** Create `src2/ui/classic/tree.lua`, `src2/ui/classic/build.lua`; modify `src2/ui/classic/classic.lua`. Test: `tests3/test_classictree.lua` (`-- needs: ui`).

**Interfaces:**
- Produces: `ClassicTree.STYLES`, `ClassicTree.TREE`: V2.38.17's `UI_STYLES` and tree from `p04_ui.lua` (`git show aaa21b6:src/parts/p04_ui.lua`), as data, with these changes only: the title and version text read `HappaTAS 3.0.0-dev` (`CONFIG.VERSION`); the Help list and the update log are left empty (Task 3 fills Help; no update log); nothing that refers to sounds.
- Produces: `ClassicBuild.build(tree, styles, parent) -> root, byPath` (`byPath["MainMenu.SettingsFrame.List"]` = the instance), every ScreenGui with `AutoLocalize = false`, `ResetOnSpawn = false`.
- Produces: `classic.gui` holds V2's top-level children: `MainMenu` (with `ControlsFrame`, `SettingsFrame`, `SavesFrame`, `HelpFrame`, `MoreFrame` and their `…Toggle` buttons), `IdleStats`, `CreateStats`, `TestStats`, `Merge`, `MergeStats`, `Mobile` (`MobileCreate`, `MobileModes`, `MobileOptions`, `MenuOpener`, `More`), `JoinMessage`.

- [ ] **Step 1: Write the failing tests:**
  - `every V2 frame`: each path above exists, with V2's class (`git show aaa21b6` names copied into the test as a table).
  - `V2's look`: `MainMenu` size, position and background as V2's tree says (three values copied into the test); the Settings list has no rows yet (Task 3 makes them from the schema).
  - `localization off`: every ScreenGui has `AutoLocalize == false`.
  - `nothing per frame`: building adds no pipeline handler.
- [ ] **Step 2: Run** `bash tools/build_test3.sh classictree && (cd tests3 && luau run_classictree.lua)` — Expected: FAIL.
- [ ] **Step 3: Implement** the port (data first, then the builder; keep V2's helper style `X` / `CR` / row makers inside a `do` block if the chunk nears Luau's 200 register limit, as V2 did).
- [ ] **Step 4: Run** the suite and `bash tools/test_all3.sh` — Expected: PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: the classic interface's tree`.

### Task 3: The classic menu and its settings list

**Files:** Create `src2/ui/classic/settingsrows.lua`; modify `src2/ui/classic/classic.lua`. Test: `tests3/test_classicmenu.lua` (`-- needs: ui`).

**Interfaces:**
- Consumes: `Settings.SCHEMA` (every row, Appearance ones too), `E.settings:get / set / changed`, `HelpText.topics(E)`.
- Produces: the menu's tabs (Controls, Settings, Saves, Help, More) as V2's `tab()` (`p19_menu.lua:392`); More: Unload (`getgenv().__HappaTAS3.Unload`), MicroProfiler (toggles `showMicroProfiler`); Help: one expandable row per topic in V2's style; a status line (`E.bus` `"status"`) in V2's `JoinMessage` way.
- Produces: the classic menu can be dragged by its top bar, and its place is kept per screen size in the settings file's interface data under `classic.menu = { x, y }` (`settingsfile.lua`'s `cleanUi` keeps it), apart from the new interface's window layout (spec 8.5: "each interface keeps its own window positions").
- Produces: `SettingsRows.build(classic)`: one V2-style row per schema row, sections as headers; toggles as V2's switch, every other kind as V2's input box (choices typed, matched without case by the store; colours as `#RRGGBB`). A row shows `E.settings:get` when built and follows `changed` events; a typed value the store refuses shows the old one again.

- [ ] **Step 1: Write the failing tests** (spec 8.5's test):
  - `both built`: build Classic once, switch back to New, then for every schema row: set a new valid value through the new interface's Settings window control (or `E.settings:set` where the window has no direct control) → the classic row shows it in the same frame; then through the classic row (switch click / input box `FocusLost`) → the new window's control shows it in the same frame.
  - `refused input`: typing `abc` in a number row → the row shows the old value, the store unchanged.
  - `never written`: switching to Classic and back, opening every tab, changes none of glass, blurStrength, edgeLight, windowCorners, buttonShape, shadows, animations, easing (Review Focus 2).
  - `tabs, More, Help`: each tab shows its frame; Help has one row per topic, expanding one closes the other; MicroProfiler flips `showMicroProfiler`.
  - `own place`: drag the classic menu by 100, 40 → switch to New and back, and `boot` again → the menu is where it was dragged; the new interface's Settings window place is unchanged.
- [ ] **Step 2: Run** `bash tools/build_test3.sh classicmenu && (cd tests3 && luau run_classicmenu.lua)` — Expected: FAIL.
- [ ] **Step 3: Implement** the menu and `SettingsRows`.
- [ ] **Step 4: Run** the suite and `bash tools/test_all3.sh` — Expected: PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: the classic menu and settings`.

### Task 4: Classic controls

**Files:** Create `src2/ui/classic/controlsrows.lua`; modify `src2/ui/classic/classic.lua`. Test: `tests3/test_classiccontrols.lua` (`-- needs: ui`).

**Interfaces:**
- Consumes: `Controls.LIST`, `E.controls:get / set / changed`, `E.typing.rebinding`, `E.typing.boundInput`, `Keys.fromKey`.
- Produces: one V2-style row per control; a click waits for the next key or mouse button (the engine's keys off meanwhile, the binding press never runs a control: phase 5a's rule), Esc cancels.

- [ ] **Step 1: Write the failing tests:** rebinding Pause to P in classic → `E.controls:get("pause") == "P"` and the new Controls window shows P; the P press didn't pause; Esc while waiting cancels; a key bound in the new window shows in the classic row at once; touch screens hide the Controls tab (V2's rule, `p19_menu.lua:288`).
- [ ] **Step 2: Run** `bash tools/build_test3.sh classiccontrols && (cd tests3 && luau run_classiccontrols.lua)` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite and `bash tools/test_all3.sh` — Expected: PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: classic controls`.

### Task 5: Classic saves and merging

**Files:** Create `src2/ui/classic/saves.lua`; modify `src2/ui/classic/classic.lua`. Test: `tests3/test_classicsaves.lua` (`-- needs: ui`).

**Interfaces:**
- Consumes: `E.library:list()` (entries with `folder == ""`), `E.persist:save / load / readFrames`, `Persist.canMerge`, `Persist.NOT_NOW_MERGE`, `E.mergeRun:startMerge / finishMerge`, `E.mergeDistance`, `E.mergeRun.reqDist`, `E.mergeCanComplete`, bus `persist`.
- Produces: V2's slot rows (name box, Save, Load, Merge, Delete, size text, `updateSlotCount`), "Add slot"; V2's Merge dialog (Before / After by the Running rule of phase 5b) and V2's `MergeStats` panel (Current Distance, Distance Required, "Click here to complete merge" green / "Click here to cancel merge" red).

- [ ] **Step 1: Write the failing tests** (Review Focus 3):
  - save, load, merge after (completed) and merge (cancelled) through the classic buttons, the same frame counts as `test_mergewin`;
  - names: empty → "Invalid name"; `a/b` → `ab`; 200 characters → 60; renaming to a name another slot has in another case → refused with the Library's message; Save on a slot that exists asks a second click within 3 s;
  - an empty run: Save dimmed, `Persist:save` refuses ("There is nothing to save");
  - merge from Test or while recording → "Go Idle or pause before merging";
  - a run saved in a folder through the new Library is not listed in classic Saves.
- [ ] **Step 2: Run** `bash tools/build_test3.sh classicsaves && (cd tests3 && luau run_classicsaves.lua)` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite, `librarywin`, `mergewin` and `bash tools/test_all3.sh` — Expected: PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: classic saves and merging`.

### Task 6: Classic stats panels

**Files:** Create `src2/ui/classic/stats.lua`; modify `src2/ui/classic/classic.lua`. Test: `tests3/test_classicstats.lua` (`-- needs: ui`).

**Interfaces:**
- Consumes: `IV.values(E, perf, want, memo, out)` (phase 5b), the settings `showStatsIdle / Create / Test`, `statsTextSize`, `playbackSpeed`.
- Produces: V2's `SS.Idle / SS.Create / SS.Test` (`p18_core.lua:184-262`): the same labels and line texts (" Root Position: x, y, z" …), one panel visible by mode, Create's background darker while paused (0.1 / 0.2), Test showing Frame-only rows at another playback speed (V2's rule). Updated as the Inspector is (5 a second while the character moves, on a change while paused, skipped when nothing moved), only while Classic is live.

- [ ] **Step 1: Write the failing tests:** each panel's numbers equal the Inspector's values for the same frame (paused, recording, Test, Idle); Show Stats off hides the panel; Stats Text Size sizes it; no Instance write over 30 paused frames with nothing changing; none while New is live.
- [ ] **Step 2: Run** `bash tools/build_test3.sh classicstats && (cd tests3 && luau run_classicstats.lua)` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite and `bash tools/test_all3.sh` — Expected: PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: classic stats panels`.

### Task 7: Appearance in the classic interface

**Files:** Create `src2/ui/classic/look.lua`; modify `src2/ui/classic/classic.lua`. Test: `tests3/test_classiclook.lua` (`-- needs: ui`).

**Interfaces:**
- Consumes: `accentColor`, `textColor`, `secondaryTextColor`, `recordingColor`, `font`, `numberFont`, `textSize`, `interfaceScale` (spec 8.5's list, nothing else).
- Produces: `ClassicLook.apply(classic, E)`, run on build and on each of those settings' `changed`: accent → V2's blue elements (tab selected, switch on, primary strokes: the tree's `c(0,141,237)` / `c(0,77,205)` family); text / secondary → white / grey labels; recording → the Create stats panel while recording; font → every Gotham face (bold weights kept), number font → stats values; text size → each label's size × textSize / 13; interface scale → a `UIScale` on the classic ScreenGui (percent / 100).

- [ ] **Step 1: Write the failing tests** (spec 8.5): accent changed in the new interface → switch to Classic → its selected tab and an on switch use it at once; changed in Classic → switch back → the new Dock's lit button uses it; restart (`boot` again) → both load it; the eight values apply, nothing else changes (Review Focus 2); a font change reaches a label, a number font change a stats value.
- [ ] **Step 2: Run** `bash tools/build_test3.sh classiclook && (cd tests3 && luau run_classiclook.lua)` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite and `bash tools/test_all3.sh` — Expected: PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: appearance in the classic interface`.

### Task 8: Touch buttons

**Files:** Create `src2/ui/touch.lua`, `src2/ui/classic/mobile.lua`; modify `src2/engine/modes.lua`, `src2/ui/app.lua`, `src2/ui/classic/classic.lua`; mock: `tests/mock/svc.lua` only if `TouchEnabled` / `KeyboardEnabled` / `TouchTap` are missing (keep `REF=1 bash tools/test_all.sh` passing). Test: `tests3/test_touch.lua` (`-- needs: ui`).

**Interfaces:**
- Produces: `Modes:release(which: "back" | "forward")` (Global Constraints).
- Produces: the new interface's pad (`src2/ui/touch.lua`): mode buttons Idle / Create / Test; in Create: pause / unpause (icon follows `E.paused`), back and forward (held: `request` on press, `release` on release), back 1 / forward 1 frame, unpause 1 frame, return, look around; options: delete TAS and optimize (with `{ mobile = true }`, as V2's mobile buttons); a "HappaTAS" button that shows / hides the interface (the Menu key's job). Drawn with the kit's icons, only the allowed characters, a bottom-left column above Roblox's thumbstick area, buttons enabled by `E.modes:allowed`.
- Produces: in Test, V2's quit: the first tap says "Tap again to quit Test" (status), a second tap within 1 s ends playback; a single tap never quits (Review Focus 4).
- Produces: `ClassicMobile.wire(classic)`: V2's `Mobile` folder (`p18_core.lua:1451-1499`) through `E.modes:request` / `release`, shown under the same rule.

- [ ] **Step 1: Write the failing tests:** TouchEnabled + not KeyboardEnabled → the pad shows, Create / unpause / pause / back held 30 frames then released (`E.back` false, frame moved) / Test / double-tap quit work; TouchEnabled + KeyboardEnabled → no pad (Review Focus 4); the same with Classic live through V2's buttons; windows open as sheets (5a) with the pad.
- [ ] **Step 2: Run** `bash tools/build_test3.sh touch && (cd tests3 && luau run_touch.lua)` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite, `modes`, and `bash tools/test_all3.sh` — Expected: PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: touch buttons`.

### Task 9: Thumbstick recording and replay

**Files:** Create `src2/world/thumbstick.lua`; modify `src2/main.lua` (register the plugin), `src2/modules.txt`. Test: `tests3/test_thumbstick.lua`.

**Interfaces:**
- Produces: a world plugin `thumbstick` (spec 2 keeps "thumbstick replay"; HappaTAS 3 only carried V2's `Mobile` field so far) that registers a list column with `v2 = { key = "Mobile" }`, so `Run.registerCarry` no longer makes `v2Mobile` and files keep the data either way.
- Recording (only when `UserInputService.TouchEnabled`): V2's `C.ReadMobile()` (`git show aaa21b6:src/parts/p18_core.lua`, lines 479-516): `PlayerGui.TouchGui.TouchControlFrame` → the static `ThumbstickFrame.StickImage` offset and the `DynamicThumbstickFrame` images (`ThumbstickStart`, `ThumbstickEnd`, up to 15 visible `ThumbstickMiddle`: position, transparency, size), `Jumping`; the same table shape V2 saved (`{ Jumping, JoystickX, JoystickY, Dynamic = { Start, End, Middles } }`).
- Playback (Test, touch devices only): V2's `C.ReplayMobile(mob)` (lines 517-…) on the frame shown.

- [ ] **Step 1: Write the failing tests:** with a mock `TouchGui` (frames named as V2 expects) and TouchEnabled, a recording stores each frame's stick and the dynamic images; save / load v6 keeps them; Test puts the images where they were; without TouchEnabled nothing is read; a V2 file with `Mobile` loads into the new column and plays (the phase 3 v2reader fixture with Mobile, or one made in the test); the trace scenario still SAME.
- [ ] **Step 2: Run** `bash tools/build_test3.sh thumbstick && (cd tests3 && luau run_thumbstick.lua)` — Expected: FAIL.
- [ ] **Step 3: Implement** (a port of V2's two functions, as the other world plugins are).
- [ ] **Step 4: Run** the suite, `persist`, `v2reader` and `bash tools/test_all3.sh` — Expected: PASS, traces SAME.
- [ ] **Step 5: Commit** `HappaTAS 3: thumbstick recording and replay`.

### Task 10: Phase 5b's follow-ups

**Files:** Modify `src2/ui/windows.lua`, `src2/ui/win/merge.lua`, `src2/ui/bar/bar.lua`, `src2/ui/bar/lanes.lua`, `src2/persist/persist.lua`. Tests: `tests3/test_mergewin.lua`, `tests3/test_bar.lua`.

**Interfaces:**
- `def.remember = false` (the Merge window): `rememberOpen` / `restoreOpen` skip it, so a re-run never opens an empty Merge window (5b minor #6).
- The marker button is refused while `E.busy` (5b minor #7).
- `Persist` emits bus `"persist"` `{ op = "started", what = "save" | "load" | "frames" }` when a save, load or read begins; the bar refreshes on it, so its buttons dim in Idle during a save (5b minor #9).
- The lanes panel hides while the bar is a strip (5b minor #10).
- While recording, the ruler and marks redraw once a second of real time (`os.clock`), not every 120th frame (5b minor #11).

- [ ] **Step 1: Write the failing tests:** a re-run with the Merge window open → it stays closed; marker refused while busy (no `tl.edits` change); in Idle a save start dims the bar's Test button until the save ends; lanes open + strip → hidden, reopening the run → shown; recording at 60 FPS for 1.5 s → the ruler redrew at least once (labels moved).
- [ ] **Step 2: Run** `bash tools/build_test3.sh mergewin && (cd tests3 && luau run_mergewin.lua)` and the same for `bar` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** both suites and `bash tools/test_all3.sh` — Expected: PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: phase 5b follow-ups`.

### Task 11: Together

**Files:** Modify `tests3/test_ui.lua`, `tests3/trace/bench.lua`, `tests3/trace/adapter_v3.lua`, `tests3/trace/adapter_v2.lua`, `tools/bench3.sh` (if needed). Test: `tests3/test_ui.lua`, `bash tools/bench3.sh`.

**Interfaces:**
- Bench modes "idle, classic", "recording, classic" and "Test, classic": HappaTAS 3 with Classic live against V2 (both draw V2's interface: gated like the other modes); `A.setInterface(name)` in both adapters (a no-op on V2).

- [ ] **Step 1: Write the failing tests** in `test_ui`: record, save, load and Test with Classic live and its menu open (no click on the menu pauses, frames recorded); the font check over the new interface still passes with Classic built; Unload with Classic live leaves no ScreenGui of either, no UserInputService connection, `pipe.timing` off; a re-run opens Classic (Review Focus 5).
- [ ] **Step 2: Run** `bash tools/build_test3.sh ui && (cd tests3 && luau run_ui.lua)` — Expected: FAIL (the classic checks).
- [ ] **Step 3: Implement** what the tests need and the bench modes.
- [ ] **Step 4: Run** `bash tools/test_all3.sh` — Expected: PASS, `BENCH OK`.
- [ ] **Step 5: Commit** `HappaTAS 3: phase 5c together`.

### Task 12: Live check

**Files:** Modify `docs/superpowers/specs/2026-10-18-happatas3-rewrite-design.md` (13: phase 5c live numbers). Fixes found live: in their own files, each with a test that failed first.

- [ ] **Step 1: Prepare** the backups (Global Constraints) and the builds (`bash tools/build3.sh --release wow3` and a `Debug = true` copy) in `HappaTasTest/`.
- [ ] **Step 2: Check in the EToH kit test place:** switch to Classic and back while recording (screenshots of both); V2.38.17 loaded alone beside a screenshot of HappaTAS 3's Classic for the look; every tab; a setting changed in each interface shows in the other; saves, load, a merge; the stats panels against the Inspector on the same frame; per-frame cost with Classic live (pipeline timing) against V2.38.17's; the release silent, Unload clean. Touch: not available on the PC client; note it as checked headless only.
- [ ] **Step 3: Clean up:** files byte-identical, `HappaTasTest` deleted, fps cap and graphics quality as before, unloaded.
- [ ] **Step 4: Write** spec 13's phase 5c entry; commit `HappaTAS 3 phase 5c: live check`.
