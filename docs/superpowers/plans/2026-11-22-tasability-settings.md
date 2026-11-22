# Tasability Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the third interface to Tasability and give it its own Tasability-style SETTINGS page, KEYS list and
CONTROLS controls, built from the settings schema and `engine/controls`.

**Architecture:** A part kit (`ui/compact/parts.lua`: checkbox, value box, dropdown, colour box, button, key box,
slider) in the theme's compact shades; a SETTINGS page (`ui/compact/settings.lua`) and a KEYS list
(`ui/compact/keys.lua`) that replace the hosted New Settings / Controls windows; helpers shared with the New windows are
exported from `ui/win/settings.lua` and a new `ui/rebind.lua` (the Controls window's key-wait logic, used by both).

**Tech Stack:** Luau (conservative syntax), the headless mock in `tests/mock`, `luau` CLI, bash tools.

**Spec:** `docs/superpowers/specs/2026-11-22-tasability-settings-design.md`

## Global Constraints

- Conservative Luau: no `+=`, `//`, backtick strings, `continue`, if-expressions; 200 locals per function.
- Shown name and stored value: **Tasability**; options `{ "New", "Classic", "Tasability" }`; a stored `"Compact"` loads as
  `"Tasability"`. Internal names stay `compact` (`ui/compact/*`, `ui.compact`, `UI:isCompact`, `theme.compact`).
- No code, text, icons or images from `tasabilitythis.lua`; glyphs only ASCII and × ▼ ← … • (the tick is a drawn square).
- Parts: square, compact shades, accent = `accentColor`, dim labels = `secondaryTextColor`, Gotham, 1 px black text
  outline; hover = `hover` shade + accent text. Sizes: checkbox row 18 (box 12, tick 6); value box / dropdown / key box /
  button 22; label 40 % / box 60 % (key box: inset 42 %); dropdown items 20; slider track 6, knob 10; swatch 14 x 12;
  waiting text "..." in #DCC83C.
- SETTINGS shows what the New window shows minus `newOnly`, `hidden`, `classicOnly`, follower rows; `interface` is a
  dropdown; `speedHackModes` is a checkbox per option labelled "<name>: <option>"; numbers are value boxes.
- Every task: `bash tools/test_all3.sh` stays ALL PASSED by the last task (traces SAME, bench OK); never commit `wow1`
  (`git restore wow1` after `bash tools/release3.sh`); every new test file ends with `finish()`.
- Commits: `git -c user.name=Claude -c user.email=noreply@anthropic.com commit`, ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; no session links, no quotes of dzr's requests.

## Review Focus

1. A value box given a bad or out-of-range value (letters, 9999 for a 0-100 setting) shows the stored value again /
   the clamped one, never a value the setting doesn't hold. (Task 2 and Task 4 tests.)
2. A setting changed elsewhere (a key toggle, Classic, the settings file) while the page exists: its row follows at
   once; a value box that has focus keeps the player's typed text until it commits. (Task 4 test.)
3. Waiting for a key, then switching interface or unloading: the wait ends and no key is bound; Backspace and Delete
   can be bound. (Task 5 test.)
4. A search matching nothing: both columns empty, no error; clearing the search brings every section back in the
   same order. (Task 4 test.)
5. A dropdown list open when the window folds or the interface switches: the list closes. (Task 2 test.)

---

### Task 1: Compact becomes Tasability

**Files:**
- Modify: `src2/engine/settings.lua` (`interface` options / desc), `src2/persist/settingsfile.lua` (`loadSettings`:
  `interface == "Compact"` -> `"Tasability"`), `src2/ui/app.lua` (`setInterface` / `isCompact` read `"Tasability"`),
  `src2/ui/win/helptext.lua` (topic id `compact` keeps its id, title "Tasability interface", text says Tasability; other
  lines naming Compact), `src2/ui/updatelog.lua` (the V3.1 line "Compact: a third interface, inspired by Tasability"
  -> "Tasability: a third interface in Tasability's style"), `README.md`
- Test: `tests3/test_tasabilityname.lua`; update every suite that sets `"Compact"` (sed `"Compact"` -> `"Tasability"`
  in tests3/test_compact*.lua, test_classicrows.lua, test_classicmenu.lua, test_updatelog.lua, test_compactreview.lua)

**Interfaces:**
- Produces: `interface` value `"Tasability"`; `UI:isCompact()` true when live == `"Tasability"`.

- [ ] **Step 1: Write the failing test**: options equal `New,Classic,Tasability`; a settings file with
  `interface = "Compact"` loads `"Tasability"` and the live interface is the third one (`ui:isCompact()`); no Help topic
  title or body contains "Compact"; the README contains "Tasability" in the Interface table row
  (`Interface (New / Classic / Tasability)`); the update log's V3.1 entry has no "Compact".
- [ ] **Step 2: Run** `bash <scratchpad>/suites.sh tasabilityname`. Expected: FAIL (option "Compact").
- [ ] **Step 3: Implement** the rename and the load mapping; update the tests that use "Compact".
- [ ] **Step 4: Run** `tasabilityname compactswitch compactshell compacthost compactcontrols compactmisc compactunload
  compactreview classicrows classicmenu updatelog settingsfile help`. Expected: all pass.
- [ ] **Step 5: Commit** "HappaTAS 3: the third interface is called Tasability".

### Task 2: The part kit

**Files:**
- Create: `src2/ui/compact/parts.lua` (modules.txt after `ui/compact/kit`)
- Test: `tests3/test_tparts.lua`

**Interfaces:**
- Consumes: `CK.border`, `CK.paintBorder` (ui/compact/kit), `theme.shades`, `ui/kit/popover`, `ui/kit/colorpicker`.
- Produces (each returns a table with `gui`, `set(v)`, `destroy()`; `opts.onChange(v)` when the player changes it;
  `onHover(on)` optional callback for the page's hover strip):
  - `P.checkbox(ctx, parent, label, opts) -> { gui, box, tick, label, value: boolean, set(on) }`
  - `P.valueBox(ctx, parent, label, opts) -> { gui, label, box (TextBox), set(text) }`; `opts.commit(text) -> ok` (false
    puts `opts.current()` back)
  - `P.dropdown(ctx, parent, label, options, opts) -> { gui, button, list (nil when closed), value, set(v), close() }`
  - `P.colorBox(ctx, parent, label, opts) -> { gui, box, swatch, set(hex) }`; swatch click opens `ColorPicker.open`
    with `opts.value()`, `opts.default`, `onPreview`, `onApply`
  - `P.button(ctx, parent, text, opts) -> { gui, label, onClick }`
  - `P.keyBox(ctx, parent, label, opts) -> { gui, key (TextLabel), clear (× chip), set(keyName), setWaiting(on),
    setConflict(on) }`; `opts.onClick()`, `opts.onClear()`
  - `P.slider(ctx, parent, opts) -> { gui, track, fill, knob, valueLabel, value, set(v) }` (`opts.min`, `max`, `fmt`)

- [ ] **Step 1: Write the failing test** (theme in compact mode, parts in a test frame in the root layer):
  checkbox: box 12 x 12, click toggles `value` and calls onChange, tick visible only when on, box fill = accent mixed
  toward `deep` when on; valueBox: typing "abc" with `commit` returning false shows `current()` again, a good value
  calls commit once; dropdown: click opens a list of the options (items 20 high), clicking one sets the value, calls
  onChange, closes; Esc and a press outside close it; **Review Focus 5:** `close()` after the owner folds leaves no
  `Popover` in the layer; colorBox: swatch BackgroundColor3 = the hex, swatch click opens a picker (a `Popover`
  appears), typing "10, 20, 30" commits "#0A141E"; keyBox: `setWaiting(true)` shows "..." in #DCC83C, `set("R")` shows
  R in the accent, the × chip calls onClear, `setConflict(true)` paints the inset outline `theme.c.rec`; slider: a click
  at 50 % of the track gives (min + max) / 2 (step-free), the label uses `fmt`; every part: no UICorner with a non-zero
  radius in it, label text colour follows a new `secondaryTextColor`, `destroy()` leaves no theme listener.
- [ ] **Step 2: Run** `tools/build_test3.sh tparts`. Expected: BUILD FAILED (module missing).
- [ ] **Step 3: Implement** `src2/ui/compact/parts.lua`. Text outline: a 1 px black UIStroke on the labels. Dropdown list:
  `Popover.open(ctx, button.gui, button.AbsoluteSize.X, 20 * math.min(#options, 8))`, its items as plain frames (the
  popover glass is already square in compact mode).
- [ ] **Step 4: Run** `tparts compacttheme compactkit`. Expected: PASS.
- [ ] **Step 5: Commit** "HappaTAS 3: Tasability parts".

### Task 3: Shared helpers (settings formatting, saved looks, key waiting)

**Files:**
- Modify: `src2/ui/win/settings.lua` (export `SettingsWin.num`, `SettingsWin.isDefault`, `SettingsWin.lookNames(E)`,
  `SettingsWin.saveLook(E, name) -> ok, why`; `themeControl` uses them)
- Create: `src2/ui/rebind.lua` (modules.txt before `ui/win/controls`); Modify: `src2/ui/win/controls.lua` to use it
- Test: `tests3/test_rebind.lua`; `controlswin` and `settingswin` must pass unchanged

**Interfaces:**
- Produces: `Rebind.new(E, life) -> rb` with `rb:start(controlKey, onDone(name|nil))`, `rb:stop()`,
  `rb.waiting: string|nil` (the control key waited for); Esc cancels (onDone(nil)); any key or mouse button in
  `engine/keys` binds through `E.controls:set` (Backspace and Delete included); `E.typing.rebinding` true while waiting;
  `E.typing.boundInput` set to the binding input; a mouse button binding swallows its release (the Controls window's
  `swallow`). `SettingsWin.saveLook(E, "Default")` -> false, "\"Default\" can't be overwritten: pick another name".

- [ ] **Step 1: Write the failing test**: `rb:start("back", f)` then a press of Backspace -> `E.controls:get("back") ==
  "Backspace"`, f got "Backspace", `rebinding` false; start then Escape -> unchanged, f(nil); start then `rb:stop()` ->
  no binding on the next key; a mouse button binds "Left Click"-style names via `Keys.fromKey`; `SettingsWin.num(0.5)
  == "0.5"`, `num(13) == "13"`, `lookNames(E)[1] == "Default"`, `saveLook(E, "Mine")` adds "Mine" with every Appearance
  key, `saveLook(E, "default")` refused.
- [ ] **Step 2: Run** `tools/build_test3.sh rebind`. Expected: FAIL.
- [ ] **Step 3: Implement** by moving the Controls window's InputBegan / InputEnded logic into `Rebind` (the window keeps
  its rows, conflicts and buttons) and exporting the settings helpers.
- [ ] **Step 4: Run** `rebind controlswin settingswin typing interface`. Expected: PASS.
- [ ] **Step 5: Commit** "HappaTAS 3: shared key waiting and settings helpers".

### Task 4: The SETTINGS page

**Files:**
- Create: `src2/ui/compact/settings.lua`; Modify: `src2/ui/compact/compact.lua` (the SETTINGS tab builds this page
  instead of hosting `SettingsWin`; the title-bar search calls `page:filter(text)`)
- Test: `tests3/test_tsettings.lua`; update `tests3/test_compacthost.lua` (settings no longer hosted: its hosted-Settings
  sections move here)

**Interfaces:**
- Consumes: Task 2 parts, Task 3 helpers, `CK.section`.
- Produces: `TSettings.build(cp) -> page` with `page.rows[key] = { def, part, gui, section }`,
  `page.sections[name] = { gui, rows, column }`, `page.columns = { left, right }`, `page.hover` (the strip TextLabel),
  `page:filter(text)`, `page:relayout()`; stored as `cp.settingsPage`.

- [ ] **Step 1: Write the failing test**: every shown row (the Global Constraints rule) has a part of the right kind
  (toggle -> checkbox, number -> valueBox, choice -> dropdown, color -> colorBox, `theme` -> dropdown + Save as,
  `speedHackModes` -> one checkbox per option) and no other row exists; sections in schema order, alternating into the
  shorter column (heights summed from fixed row heights); a checkbox click sets its setting; `s:set` elsewhere updates
  the part; **Review Focus 1:** typing "9999" into `statsTextSize` gives its max and the box shows it, "abc" shows the
  stored value; **Review Focus 2:** `s:set("syncClientObjects", 0)` from outside unticks its checkbox at once, and a focused
  value box keeps its typed text; the RESET chip on a section puts its rows to their defaults (Appearance: `applyLook("Default")`);
  hovering a row shows its `desc` in `page.hover`; **Review Focus 4:** `filter("zzzz")` leaves no section visible and no
  error, `filter("")` restores every section in the same order; `filter("accent")` keeps the accent row; the colour box
  opens the picker and Cancel puts the old accent back; `cp.hosted.settings == nil`.
- [ ] **Step 2: Run** `tools/build_test3.sh tsettings`. Expected: FAIL.
- [ ] **Step 3: Implement.** The page is a ScrollingFrame filling the SETTINGS tab; each section a `CK.section` with fixed
  row heights (18 checkbox, 22 others, gap 5) and a "RESET" chip (`CK.chip`, button) at the title's right end; the hover
  strip a 16-high label at the page's bottom.
- [ ] **Step 4: Run** `tsettings compacthost compactshell settingswin`. Expected: PASS.
- [ ] **Step 5: Commit** "HappaTAS 3: Tasability's own SETTINGS page".

### Task 5: KEYS

**Files:**
- Create: `src2/ui/compact/keys.lua`; Modify: `src2/ui/compact/compact.lua` (KEYS section builds this list instead of
  hosting `ControlsWin`; `Compact:endTyping` stops its Rebind), `src2/ui/compact/controls.lua` (the KEYS section height
  fits 17 rows + Reset all)
- Test: `tests3/test_tkeys.lua`; update `tests3/test_compacthost.lua` (controls no longer hosted)

**Interfaces:**
- Consumes: `P.keyBox`, `P.button`, `Rebind`.
- Produces: `TKeys.build(cp, parent) -> keys` with `keys.rows[controlKey] = keyBox`, `keys.resetAll`, `keys.rebind`.

- [ ] **Step 1: Write the failing test**: a key box per `Controls.LIST` entry in order with its bound key; a click waits
  ("..." shown), pressing G binds G; **Review Focus 3:** waiting then switching interface ends the wait (no binding on the
  next key, `rebinding` false), waiting then Unload leaves no listener; binding Backspace works; the × chip sets None;
  two controls on one key (not Pause / Unpause) both show the conflict outline and hovering one shows "Also: <other>" in
  the page's hover strip; Reset all puts every default back; `cp.hosted.controls == nil`.
- [ ] **Step 2: Run** `tools/build_test3.sh tkeys`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `tkeys compacthost compactcontrols controlswin`. Expected: PASS.
- [ ] **Step 5: Commit** "HappaTAS 3: Tasability's KEYS list".

### Task 6: CONTROLS with the parts

**Files:**
- Modify: `src2/ui/compact/controls.lua` (Speed Hack: `P.checkbox`; speed: `P.slider` min 0.1 max 1 fmt "%.2fx"; RUN and
  TOOLS buttons: `P.button`)
- Test: update `tests3/test_compactcontrols.lua`

- [ ] **Step 1: Update the test first**: `c.speedToggle` is a checkbox part (has `box` and `tick`), clicking it toggles
  `speedHack`; `c.speedSlider` is a slider part (has `track`, `knob`), a click at the track's middle gives 0.55; the
  buttons are part buttons (square: no rounded UICorner); the rest of the suite as before.
- [ ] **Step 2: Run** `compactcontrols`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `compactcontrols compactreview`. Expected: PASS.
- [ ] **Step 5: Commit** "HappaTAS 3: CONTROLS with the Tasability parts".

### Task 7: Docs, release, gate, live

**Files:** `src2/ui/win/helptext.lua` (the Tasability topic mentions checkboxes / value boxes, RESET, the hover strip,
key boxes and ×), `README.md` (the Tasability paragraph), `wow` (release)

- [ ] **Step 1:** Help and README text; `bash tools/release3.sh && git restore wow1`.
- [ ] **Step 2: Run** `timeout 590 bash tools/test_all3.sh` in the foreground. Expected: ALL PASSED, traces SAME, bench OK.
- [ ] **Step 3: Live check** (Real MCP, `game.GameId == 10769723786`, back up HappaTasPort with sha1 lists, debug build):
  switch to Tasability; screenshot SETTINGS and CONTROLS; with **real mouse clicks** (VirtualInputManager): a checkbox, a
  value box (type a value, Enter), a dropdown pick, the accent colour box (picker opens, Cancel), a section RESET, a key
  rebind and ×; search; switch interfaces; Unload; console clean. Restore the folder byte-identical, delete
  HappaTasTest, FPS cap as found.
- [ ] **Step 4: Commit** "HappaTAS 3: Tasability settings in Help and the README; wow".
