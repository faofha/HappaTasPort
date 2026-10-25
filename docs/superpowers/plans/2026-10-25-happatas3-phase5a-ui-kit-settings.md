# HappaTAS 3 Phase 5a: UI kit, windows, appearance, Settings and Controls — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** HappaTAS 3 gets its own interface for the first time: a glass component kit, floating windows, every Appearance setting, and the Settings and Controls windows (spec 8.1-8.4), with the Frost glass tried in the real client.

**Architecture:** A new `src2/ui/` layer started by `main.lua` after the engine (`E.ui`). It owns one ScreenGui (`TASUserInterface`, V2's attach rules), does its own layout and its own pointer hit-testing (no UIListLayout, no GuiButton events: V2.36's inset lesson), and does no per-frame work unless something animates or is being dragged. Every value it shows comes from the one settings store (`E.settings`, spec 6.3) and updates on its change events.

**Tech Stack:** Luau (conservative syntax), Roblox GUI instances (Frame, TextLabel, TextBox, ScrollingFrame, ImageLabel, UICorner, UIStroke, UIGradient, UIScale), TweenService:GetValue for Roblox easing, the headless mock (`tests/mock/`) and `luau`.

**Spec:** `docs/superpowers/specs/2026-10-18-happatas3-rewrite-design.md` (sections 6.3, 8.1-8.4, 10, 11, 12) and the mockup `docs/superpowers/specs/2026-10-18-happatas3-ui-mockup.html` (exact look: colours, sizes, radii).

## Global Constraints

- Everything in the phase 1-4 plans' Global Constraints still holds: conservative Luau (no `+=`, `//`, backtick strings, `continue`, if-expressions), no network code, sUNC lookups with fallbacks through `platform/env`, game code only through `GameCall` / `task.spawn(pcall, ...)`, Debug output only with `CONFIG.Debug` (`Env.debugNote`), version `"3.0.0-dev"`, never commit `CLAUDE.md` / `claude/`, commit only the files a task lists, never name `getfenv` / `setfenv` (deopt guard).
- Branch `v3-rewrite` (PR #18 open). Do not edit `src/parts/`, `wow`, `wow1`, `tests/test_*.lua`. Additions to `tests/mock/` only when every V2 suite still passes on the reference (`REF=1 bash tools/test_all.sh`).
- **Ruling (dzr, 2026-10-25): no UI sounds.** The "UI sounds" section and settings (spec 8.3 / 8.4) are dropped; Task 1 edits the spec.
- **Ruling (dzr, 2026-10-25): phase 5 is three plans.** 5a (this plan): kit, windows, appearance, Settings, Controls, Frost trial. 5b: timeline bar, Inspector, Library, Merge, Help. 5c: classic interface (8.5), mobile touch buttons.
- Look (from the mockup, the defaults): window fill `#242A38` at transparency 0.54, rim 1 px white at transparency 0.84, corners 16 px, title bar 13.5 px bold with 11 px dots (close `#FF6A6A`), rows ≥ 32 px with 18 px side padding, section headers 10.5 px uppercase; accent `#3F7CF0`; reset button 24 px amber gradient `#FFC86E` → `#F0A032`; toggle 44x26 with a 22 px white glass knob; slider 112x4 with a 22 px knob; segmented pill with a glass bubble on the selected segment; fields 24 px high on black at transparency 0.75; search box 32 px with 13.5 px text, vertically centred, magnifier on the right.
- **Ruling: own layout.** The kit places every child itself (`ui/layout.lua` stacks); no UIListLayout / AutomaticSize. Positions are then exact in the mock and Roblox runs no layout pass.
- **Ruling: own pointer.** Pointer position = `UserInputService:GetMouseLocation() - GuiService:GetGuiInset()` (or the input object's Position); press / move / release / wheel / touch come from UserInputService; a click is a release within 3 px of its press (V2.36); the hit test walks HappaTAS's own rect list front to back. GuiButton events are not used.
- **Ruling: windows open from a Dock.** The spec names no launcher: a small glass pill at the top centre ("HappaTAS" + a button per window: Settings and Controls now, 5b adds its windows). The Menu key (default `M`, works even with Ignore Game Processed off and is ignored while typing) shows / hides the whole interface; the interface starts with only the Dock shown.
- Performance: no GUI property is written unless its value changes (`ui/write.lua`); every ScreenGui has `AutoLocalize = false`; with no tween or drag running the UI's pipeline handler returns at once (bench: Idle per-frame cost within V2's 10 % line with the interface shown).
- Unload removes every HappaTAS GUI, Frost part / effect and connection; a click on a HappaTAS window never reaches the engine's keys (`E.inputs.mouseOverOwn`).
- Live tests (Real MCP, dzr: "Real is always connected"): back up `HappaTasPort/Settings.json` and the place's `.tas` files, delete `Settings3.json` / `library.cache` afterwards when they weren't there before, record `getfpscap()` and put it back, use `HappaTasTest/` and delete it, rejoin if the place changed; never run HappaTAS in Tower Creator.

## Review Focus

1. **Typing in any HappaTAS box** (search, a slider's number, HEX / RGB / HSV, a theme name): no HappaTAS control fires and the box keeps the keys. Test in Task 2 (`Typing.watch` on the root) and Task 8 (typing "2" in the search box doesn't Create).
2. **A press on a window that is released outside it** (dragging a slider off the window, a window drag that ends over the game): never Pauses / Unpauses and never clicks what is under the release point. Test in Task 2.
3. **The screen size changes while windows are open** (window resized, rotated phone): every window stays fully on screen, and each screen size keeps its own layout. Test in Task 4.
4. **A setting changed outside the window** (the Toggle Speed Hack key, the settings file loading, another window): the open control shows the new value in the same frame without being rebuilt. Test in Task 8.
5. **Bad typed values** (letters, empty, `nan`, out of range, `#12` in HEX): refused or clamped by the schema; the control shows the stored value again. Test in Tasks 5 and 6.

---

## File Structure

| File | Responsibility |
|---|---|
| `src2/engine/settings.lua` (modify) | value kinds `choice` / `color` / `text`, `desc` on every row, Appearance rows |
| `src2/persist/settingsfile.lua` (modify) | the `ui` table in Settings3.json: themes, layout per screen size, recent colours |
| `src2/ui/write.lua` | `W.set(inst, prop, value)`: writes only changed values |
| `src2/ui/root.lua` | the ScreenGui (attach rules, stale removal, UIScale), visibility, Unload |
| `src2/ui/pointer.lua` | pointer position, hit test over registered rects, hover / press / click / drag / wheel |
| `src2/ui/theme.lua` | palette from the Appearance settings, fonts list, font preview, change events |
| `src2/ui/tween.lua` | the UI's own tweens: Roblox easing via GetValue, cubic bezier, presets |
| `src2/ui/layout.lua` | vertical / horizontal stacks, text measuring |
| `src2/ui/kit/*.lua` | `glass`, `window`, `button`, `toggle`, `slider`, `segmented`, `field`, `dropdown`, `colorpicker`, `bezier`, `row` |
| `src2/ui/windows.lua` | window manager: open / close / focus / z-order, drag, resize, minimise, layout memory, Reset layout, sheets on touch-only devices |
| `src2/ui/dock.lua`, `src2/ui/toast.lua` | the Dock and status toasts (bus `status`) |
| `src2/ui/frost.lua` | Frost glass: Glass-material parts in front of the camera + DepthOfField, fallback to Tint |
| `src2/ui/win/settings.lua`, `src2/ui/win/controls.lua` | the Settings and Controls windows |
| `src2/ui/app.lua` | `UI.start(E)`: wires everything, `E.ui`, the Menu key, `E.modalOpen` |
| `tests3/ui_helpers.lua` | pointer / keyboard helpers for UI suites (`-- needs: ui`) |

`src2/modules.txt`: the ui modules after `engine/frame`, `ui/app` last before `main`.

---

### Task 1: Settings kinds, Appearance rows, the `ui` file table

**Files:** Modify `src2/engine/settings.lua`, `src2/persist/settingsfile.lua`, `docs/superpowers/specs/2026-10-18-happatas3-rewrite-design.md` (8.3 / 8.4 / 13: no UI sounds; 12: phase 5 in three parts). Test: `tests3/test_settings.lua`, `tests3/test_settingsfile.lua`.

**Interfaces:**
- Produces: row kinds `"choice"` (`options = { ... }`, value = one of them), `"color"` (value `"#RRGGBB"`, upper case), `"text"` (string ≤ 40 chars); `Settings.sanitize(def, v)` handles them (choice: case-insensitive match → canonical, else nil; color: `#RGB` / `RRGGBB` / `#RRGGBB` → `#RRGGBB`, else nil); `Settings:get(key)` returns strings for those kinds; every row has `desc` (one short sentence, shown under the name).
- Produces: section `"Appearance"` rows (key, default, range): `theme` text "Default"; `glass` choice Clear/Tint/Frost "Tint"; `glassColor` "#242A38"; `glassTransparency` 0-100 int 54; `blurStrength` 0-100 int 70; `edgeLight` 0-100 int 16; `accentColor` "#3F7CF0"; `textColor` "#FFFFFF"; `secondaryTextColor` "#B4BBC8"; `recordingColor` "#FF5A5A"; `font` choice (`Settings.FONTS`) "BuilderSans"; `numberFont` choice (`Settings.FONTS`) "RobotoMono"; `textSize` 8-24 int 13; `interfaceScale` 50-200 int 100; `windowCorners` 0-24 int 16; `buttonShape` Pill/Rounded/Square "Pill"; `shadows` toggle 1; `animations` Off/Smooth/Snappy/Bouncy "Smooth"; `animationLength` 0.05-1 0.2; `easing` choice Preset/Linear/Sine/Quad/Cubic/Quart/Quint/Exponential/Circular/Back/Elastic/Bounce/Custom "Preset"; `easingDirection` In/Out/InOut "Out"; `bezierX1` 0-1 0.25, `bezierY1` -1-2 0.1, `bezierX2` 0-1 0.25, `bezierY2` -1-2 1.
- Produces: `Settings.FONTS = { "BuilderSans", "GothamSSm", "SourceSansPro", "Roboto", "Montserrat", "Nunito", "Ubuntu", "FredokaOne", "Oswald", "Merriweather", "RobotoMono", "Inconsolata" }` (font family names; the schema needs them, so they live here, not in `ui/`). **Ruling:** the spec's "which fonts" question is answered with this list; Task 12 drops any that doesn't load in the client.
- Produces: `SettingsFile:getUi() -> { themes = { [name] = { [key] = value } }, layout = { ["WxH"] = { [windowId] = { x, y, w, h, min } } }, recentColors = { "#RRGGBB", ... } }` (never nil; ≤ 8 recent colours) and `SettingsFile:setUi(t)` (queued save like settings). Settings3.json gets `ui = ...`; a file without it loads with an empty table.

- [ ] **Step 1: Write the failing tests:** `choice / color / text kinds sanitise` (`"tint"` → `"Tint"`, `"Glassy"` → refused, `"3f7cf0"` → `"#3F7CF0"`, `"#3F7"` → `"#33FF77"`, `"#12"` refused, a 41-char text refused), `appearance defaults` (every key above with its default and section "Appearance"), `every row has a desc`, `ui table round trip` (themes, a layout for "1920x1080", 9 recent colours kept as the newest 8), `old Settings3.json without ui loads`, and in `test_settingsfile` `a V2 Settings.json converts with the Appearance defaults`.
- [ ] **Step 2: Run** `bash tools/build_test3.sh settings && (cd tests3 && luau run_settings.lua)` and the same for `settingsfile` — Expected: FAIL.
- [ ] **Step 3: Implement** the kinds, rows and `getUi` / `setUi`; edit the spec (no UI sounds; phase 5 = 5a / 5b / 5c).
- [ ] **Step 4: Run** both suites, then `bash tools/test_all3.sh` — Expected: PASS, `ALL PASSED` (the traces don't read the new rows).
- [ ] **Step 5: Commit** `HappaTAS 3: appearance settings and the interface's saved data`.

### Task 2: Root, writes, pointer, the Menu key

**Files:** Create `src2/ui/write.lua`, `src2/ui/root.lua`, `src2/ui/pointer.lua`, `src2/ui/app.lua`, `tests3/ui_helpers.lua`; modify `src2/main.lua`, `src2/modules.txt`, `tools/build_test3.sh` (`-- needs: ui` appends `tests3/ui_helpers.lua` after `tests/test_util.lua`). Test: `tests3/test_uiroot.lua`.

**Interfaces:**
- Produces: `W.set(inst, prop, value) -> boolean` (true when written); `Root.new(E) -> root` with `root.gui` (ScreenGui "TASUserInterface", ResetOnSpawn false, IgnoreGuiInset true, AutoLocalize false, ZIndexBehavior Sibling, DisplayOrder 10), `root.layer` (Frame under a UIScale = interfaceScale / 100), `root:setShown(bool)`, `root.parentName` ("gethui" / "CoreGui" / "PlayerGui"), `root.refused`; stale `TASUserInterface` guis removed first; parented like V2's `UI.Attach` (gethui → CoreGui → PlayerGui only with `allowPlayerGuiInterface`, GUID name there).
- Produces: `Pointer.new(E, root) -> pointer` with `pointer:add(rect)` / `pointer:remove(rect)`, where `rect = { gui = GuiObject, z = number, onHover = f(bool), onPress = f(pos), onRelease = f(pos, clicked), onDrag = f(pos, delta), onWheel = f(dz), cursor = nil }`; `pointer:over(pos) -> rect?`; `pointer.pos` (Vector2, screen space minus inset). Press captures: move / release go to the pressed rect wherever the pointer is.
- Produces: `UI.start(E) -> ui` sets `E.ui = ui`, `E.inputs.mouseOverOwn = function() return ui:pointerOver() end`, `E.modalOpen = function() return ui:anyWindowOpen() end`, calls `E.typing:watch(root.gui)`; `ui:toggle()`; the Menu key (`E.controls:matches(inp, "menu")`, its own InputBegan connection; ignores `gameProcessed`, ignored while `E.typing:active(inp)`).
- `tests3/ui_helpers.lua` gives `UIH.move(pos)`, `UIH.press(pos)`, `UIH.release(pos)`, `UIH.click(guiOrPos)`, `UIH.drag(from, to, steps)`, `UIH.center(gui) -> Vector2`, `UIH.typeInto(textBox, text, enter)`, `UIH.key(KeyCode)`.

- [ ] **Step 1: Write the failing tests:** `the root attaches` (gethui; without gethui CoreGui; with both refused and the setting off: `refused`, no gui anywhere; with it on: PlayerGui with a 12-char name), `a stale TASUserInterface is removed`, `W.set writes only changes` (a counter on the mock's property writes), `click = release within 3 px` (4 px → no click), `press capture` (press on rect A, release over the game: A gets the release, no InputBegan reaches the engine's keys, `E.mode` unchanged — Review Focus 2), `a click over a window doesn't Pause` (recording, click on a rect: still recording), `Menu key toggles` (with Ignore Game Processed off and `gameProcessed` true it still toggles; while a TextBox under the root is focused it doesn't — Review Focus 1), `UIScale follows interfaceScale`, `Unload leaves nothing` (no ScreenGui named TASUserInterface anywhere, no pointer connections).
- [ ] **Step 2: Run** `bash tools/build_test3.sh uiroot && (cd tests3 && luau run_uiroot.lua)` — Expected: FAIL.
- [ ] **Step 3: Implement** the four modules and the wiring.
- [ ] **Step 4: Run** the suite and `bash tools/test_all3.sh` — Expected: PASS, `ALL PASSED`, `BENCH OK` (the root has no per-frame handler yet).
- [ ] **Step 5: Commit** `HappaTAS 3: the interface's root and pointer`.

### Task 3: Theme, fonts, tweens

**Files:** Create `src2/ui/theme.lua`, `src2/ui/tween.lua`. Test: `tests3/test_theme.lua`.

**Interfaces:**
- Produces: `Theme.new(E) -> theme` with `theme.c` (Color3s: glass, accent, text, text2, rec, reset1 `#FFC86E`, reset2 `#F0A032`, close `#FF6A6A`), `theme.t` (transparencies 0-1: glass, rim = 1 - edgeLight / 100), `theme.font(kind) -> Font` (`kind` "text" / "bold" / "number"), `theme.size(n) -> number` (n x textSize / 13), `theme.corner(kind)` (window = windowCorners; control: Pill 999 / Rounded 8 / Square 2), `theme:changed(f) -> remover` (fires once per settings change that affects the look), `theme:preview(fontName | nil)` (a font shown everywhere until `nil`, the stored value untouched).
- Fonts: `theme.font` builds `Font.new("rbxasset://fonts/families/<name>.json", weight)` from `Settings.FONTS` names (Task 1).
- Produces: `Tween.new(E) -> tw`, `tw:play(inst, props, opts?) -> handle` (`opts.length`, `opts.easing` override), `tw:cancel(handle)`, `tw:finishAll()`; one pipeline handler (PreRender, order 200, module "ui") that runs only while a tween is active; `Tween.curve(settings) -> f(alpha) -> number`: `animations` Off → length 0 (props set at once); Preset easing = Smooth: Quad Out, Snappy: Quint Out at 0.6 x length, Bouncy: Back Out; an explicit `easing` uses `TweenService:GetValue(alpha, style, direction)`; Custom = cubic bezier (x1, y1, x2, y2) solved for x by Newton steps with bisection fallback (|error| < 1e-4).

- [ ] **Step 1: Write the failing tests:** `palette from the defaults` (each Color3 / transparency above), `a settings change fires changed once`, `text size scales`, `button shape corners`, `font preview and revert` (preview "Oswald" → every `theme.font` returns Oswald, the stored `font` stays "BuilderSans"; `preview(nil)` → back), `bezier` (0.25, 0.1, 0.25, 1 at x 0.5 ≈ 0.8024 ± 1e-3; 0, 0, 1, 1 is linear; y outside 0..1 allowed), `Off is instant`, `a tween ends exactly on its goal and its handler stops` (pipeline handler count back to its idle cost: the handler returns before touching anything once no tween is active).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite and `bash tools/test_all3.sh` — Expected: PASS, `ALL PASSED`, `BENCH OK`.
- [ ] **Step 5: Commit** `HappaTAS 3: theme, fonts and the interface's tweens`.

### Task 4: Glass windows and the window manager

**Files:** Create `src2/ui/layout.lua`, `src2/ui/kit/glass.lua`, `src2/ui/kit/window.lua`, `src2/ui/windows.lua`. Test: `tests3/test_windows.lua`.

**Interfaces:**
- Produces: `Layout.vstack(parent, items, opts) -> height` (`opts.pad`, `opts.gap`, `opts.x`; each item `{ gui, h }` placed top to bottom, Visible false items skipped), `Layout.hstack(...)`, `Layout.textWidth(text, font, size) -> number` (TextService:GetTextSize, cached).
- Produces: `Glass.panel(theme, parent, opts) -> frame` (fill, rim UIStroke, UICorner, shadow = 3 stacked frames 4 / 8 / 14 px larger at transparency 0.86 / 0.92 / 0.96 when `shadows` is on — **Ruling:** no image assets); it re-styles on `theme:changed`.
- Produces: `Windows.new(E, root, pointer, theme, tween) -> wm`: `wm:define(id, { title, minW, minH, w, h, build = f(body, win) })`, `wm:open(id)`, `wm:close(id)`, `wm:toggle(id)`, `wm:isOpen(id)`, `wm:anyOpen()`, `wm:focus(id)` (front: highest ZIndex group), `wm:resetLayout()`; title bar drag, resize from any edge (6 px band) or the corner grip, minimise (title bar only), close; positions / sizes saved through `SettingsFile:setUi` under the screen size key `"<W>x<H>"` (`workspace.CurrentCamera.ViewportSize`, rounded); on a ViewportSize change each window is clamped fully on screen (Review Focus 3) and the new size's own layout used when it has one; on a touch-only device (TouchEnabled and not KeyboardEnabled) a window opens as a full-width sheet at the bottom, 60 % of the screen high, not draggable.

- [ ] **Step 1: Write the failing tests:** `open / close / toggle / focus order`, `drag by the title moves; a drag past the screen edge stops at it`, `resize from the left edge and the grip; min size kept`, `minimise keeps only the title bar`, `layout remembered per screen size` (move at 1920x1080, switch to 1280x720: default position; move there; back to 1920x1080: the first position; restart (settings file reloaded): both kept), `a smaller screen clamps open windows on screen` (Review Focus 3), `Reset layout`, `sheet on a touch-only device`, `restyle on theme change` (glass colour → every open panel's BackgroundColor3 in the same frame), `no per-frame work while nothing moves` (no GUI writes over 60 idle frames).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite and `bash tools/test_all3.sh` — Expected: PASS, `ALL PASSED`.
- [ ] **Step 5: Commit** `HappaTAS 3: glass windows`.

### Task 5: Controls: button, toggle, slider, segmented, field, row

**Files:** Create `src2/ui/kit/button.lua`, `toggle.lua`, `slider.lua`, `segmented.lua`, `field.lua`, `row.lua`. Test: `tests3/test_kit.lua`.

**Interfaces:**
- Each control: `X.new(ctx, parent, opts) -> ctl` with `ctl.gui`, `ctl:set(value)` (shows a value, no event), `ctl.onChange` (set by the owner, called with the user's new value), `ctl:destroy()`; `ctx = { theme, tween, pointer, typing }`.
- `Button.new(ctx, parent, { text, kind = "primary" | "plain" | "reset" })` (`reset` = the 24 px amber ↺); `Toggle` 44x26; `Slider { min, max, step, fmt = f(v) -> string, w = 112 }` with the value label beside it: clicking the label turns it into a Field, Enter or focus lost applies (through the schema's sanitise: letters / empty / nan refused, out of range clamped — Review Focus 5), Esc restores; drag and click on the track; `Segmented { options }`; `Field { placeholder, w, onCommit = f(text) -> accepted }` (the search box variant: 32 px, magnifier right, text vertically centred); `Row.new(ctx, parent, { name, desc, control, resetVisible })` (name + desc left, control flush right, reset just left of the control).

- [ ] **Step 1: Write the failing tests:** `toggle click flips and reports`, `slider drag / track click / step rounding`, `slider value typed` ("abc" → refused, label shows the old value; "250" for 0-200 → 200; "" → old; Esc → old), `segmented picks a segment, selected bubble moves`, `field commit on Enter and on focus lost`, `row layout` (control's right edge = row width - 18; reset button's right edge = control's left - 7), `set() doesn't fire onChange`, `destroy removes the rects from the pointer`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite and `bash tools/test_all3.sh` — Expected: PASS, `ALL PASSED`.
- [ ] **Step 5: Commit** `HappaTAS 3: interface controls`.

### Task 6: Dropdown (with font preview), the colour picker, the easing curve

**Files:** Create `src2/ui/kit/dropdown.lua`, `src2/ui/kit/colorpicker.lua`, `src2/ui/kit/bezier.lua`. Test: `tests3/test_picker.lua`.

**Interfaces:**
- `Dropdown.new(ctx, parent, { options, fontPreview = bool })`: a pill showing the value + ▾; opens a plain list popover above every window (closes on a pick, Esc or a press outside); with `fontPreview` each option is drawn in its own font and hovering one calls `theme:preview(name)`, moving away or closing calls `theme:preview(nil)`, a click keeps it (`onChange`).
- `ColorPicker.open(ctx, anchorGui, { value = "#RRGGBB", onApply = f(hex) })`: saturation / value square, hue bar, transparency bar (when `opts.alpha`), old / new halves, HEX / RGB / HSV tabs with labelled boxes (typing: HEX through the schema, RGB 0-255 each, HSV 0-360 / 0-100 / 0-100; bad input refused — Review Focus 5), recent colours row from `SettingsFile:getUi().recentColors` (Apply adds the colour first), Cancel / Apply.
- `Bezier.new(ctx, parent)` (spec 8.4's Custom easing): a 120x120 curve box drawing the curve (24 small dots along it), two draggable handles that write `bezierX1` / `bezierY1` and `bezierX2` / `bezierY2` (x clamped 0..1, y -1..2), the four values as small Fields under it (x1 y1 x2 y2), presets Ease (0.25, 0.1, 0.25, 1), Ease in (0.42, 0, 1, 1), Ease out (0, 0, 0.58, 1), Overshoot (0.34, 1.56, 0.64, 1), and a Preview button that runs a dot along a track with the current curve and `animationLength` (Task 3's `Tween.curve`). Shown in the Settings window's Easing row when `easing` is "Custom".

- [ ] **Step 1: Write the failing tests:** `bezier handles write the four settings, clamped`, `a preset sets all four`, `Preview moves the dot with the curve` (at half the length the dot is at `Tween.curve(...)(0.5)` of the track ± 1 px), `dropdown opens, picks, closes on outside press`, `font preview on hover and revert` (hover "Oswald": a TextLabel elsewhere in the root shows Oswald; move off: back), `picker HEX → RGB → HSV round trip` ("#6A5CFF" = 106 92 255; HSV 245 64 100), `square / hue drags change the new half only`, `bad HEX "#12" refused`, `Apply stores the colour and puts it first in recent (≤ 8)`, `Cancel changes nothing`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite and `bash tools/test_all3.sh` — Expected: PASS, `ALL PASSED`.
- [ ] **Step 5: Commit** `HappaTAS 3: dropdowns and the colour picker`.

### Task 7: The Dock and status toasts

**Files:** Create `src2/ui/dock.lua`, `src2/ui/toast.lua`; modify `src2/ui/app.lua`. Test: `tests3/test_dock.lua`.

**Interfaces:**
- `Dock.new(ui)`: top-centre glass pill (y 8 px below the top bar), "HappaTAS" in bold + one button per defined window (`wm:define` order), the open ones highlighted; `ui:addDockButton(id)` for 5b's windows.
- `Toast.new(ui)`: listens to `E.bus` `"status"` (`text`, `isError`) and `"moduleDisabled"` (module, err → "<module> was switched off after errors"); bottom centre 96 px above the bottom, at most 3 stacked, each 3 s (errors 6 s), fade with the theme's tween.

- [ ] **Step 1: Write the failing tests:** `only the Dock shows at start`, `dock buttons open / close their window and show which are open`, `Menu key hides the Dock and the windows, shows them again`, `a status message toasts and goes after 3 s`, `four messages: three shown, the oldest goes first`, `a disabled module toasts`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite and `bash tools/test_all3.sh` — Expected: PASS, `ALL PASSED`.
- [ ] **Step 5: Commit** `HappaTAS 3: dock and toasts`.

### Task 8: The Settings window

**Files:** Create `src2/ui/win/settings.lua`; modify `src2/ui/app.lua`. Test: `tests3/test_settingswin.lua`.

**Interfaces:**
- Window id `"settings"`, 420x640 default, min 340x320. Search box on top, then section chips (Appearance, Playback, Create, Speed hack, Inputs, World sync, Interface; a click scrolls to the section), then a ScrollingFrame with each section's header ("RESET SECTION" on the right when any row in it isn't default) and a Row per schema row in schema order.
- Control by kind: toggle → Toggle; number with min and max → Slider (integer rows step 1; `glassTransparency` / `blurStrength` / `edgeLight` / `interfaceScale` shown as `%`, `windowCorners` as `px`, `animationLength` as `s`); number without a range → Field; choice with ≤ 4 options → Segmented, more → Dropdown (`font` / `numberFont` with `fontPreview`); color → swatch (20 px circle) opening the colour picker; `theme` → Dropdown of the saved looks + a "Save as…" button (a name field; "Default" can't be overwritten; picking a look sets its Appearance values).
- Reset ↺ shown exactly when the value isn't the default; Reset section resets that section's rows. Search filters rows by name or desc as you type (case-insensitive); empty sections hidden. Every control listens to `E.settings:changed(key)` and calls `ctl:set` (Review Focus 4).

- [ ] **Step 1: Write the failing tests:** `every schema row has a control of its kind` (count = #SCHEMA), `toggle row writes the setting`, `a change made elsewhere shows at once` (`E.settings:set("speedHack", 1)` → the toggle on the same frame, no rebuild: same Instance — Review Focus 4), `reset button visible only when not default; click resets`, `Reset section`, `search "frame step" shows one row; typing "2" in the search box doesn't Create` (Review Focus 1), `chip scrolls to its section`, `Save as… a look, change accent, pick the look: accent back`, `"Default" can't be overwritten`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite and `bash tools/test_all3.sh` — Expected: PASS, `ALL PASSED`.
- [ ] **Step 5: Commit** `HappaTAS 3: the Settings window`.

### Task 9: The Controls window

**Files:** Create `src2/ui/win/controls.lua`; modify `src2/ui/app.lua`. Test: `tests3/test_controlswin.lua`.

**Interfaces:**
- Window id `"controls"`, 380x560. A Row per `Controls.LIST` entry (its V2 name), the key as a pill; clicking it shows "Press a key…" and sets `E.typing.rebinding = true`; the next InputBegan (keyboard key or mouse button, `Keys` names) binds it and sets `E.typing.boundInput` to that input (the press never runs the old control: V2.37.2's rule); Esc cancels; a small ✕ sets "None"; per-row reset ↺ and "Reset all".
- Conflicts: two controls on the same key are marked with the amber colour and a short note, except the pair `pause` / `unpause` (one of them is allowed at a time, V2's defaults share Left Click).

- [ ] **Step 1: Write the failing tests:** `rebind with a key`, `the binding press doesn't run the control it had` (bind `create` to `One` while `idle` is on `One`: the press doesn't go Idle), `Esc cancels`, `✕ sets None`, `conflict marked, pause / unpause not`, `a key changed in the settings file reload shows`, `Reset all`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite and `bash tools/test_all3.sh` — Expected: PASS, `ALL PASSED`.
- [ ] **Step 5: Commit** `HappaTAS 3: the Controls window`.

### Task 10: Frost glass

**Files:** Create `src2/ui/frost.lua`; modify `src2/ui/kit/glass.lua`, `src2/ui/app.lua`; mock: `DepthOfFieldEffect` class in `tests/mock/svc.lua` if missing (then `REF=1 bash tools/test_all.sh`). Test: `tests3/test_frost.lua`.

**Interfaces:**
- `Frost.new(ui)`: when `glass` is "Frost" and the graphics quality allows it (`UserSettings().GameSettings.SavedQualityLevel` ≥ 8, or Automatic with `settings().Rendering.QualityLevel` ≥ 8 — read with pcall), each open window gets a Glass-material part (Transparency from `blurStrength`, CanCollide / CanTouch / CanQuery false, `HappaTASIgnore` attribute) placed in front of the camera every frame a window is open (pipeline PreRender order 210, "ui"), plus one `DepthOfFieldEffect` in Lighting (FarIntensity from `blurStrength`, FocusDistance 0, InFocusRadius 0); otherwise the panels use Tint and the Settings row shows "needs high graphics" in its desc.
- The parts live in a Camera child folder "HappaTASFrost"; everything is removed when Frost is switched off, when no window is open and on Unload.

- [ ] **Step 1: Write the failing tests:** `Frost with high quality makes one part per open window and a DepthOfField`, `the part follows the window's screen rect` (its CFrame projects onto the window's centre, its size covers the window at its distance), `low quality falls back to Tint`, `closing the last window removes the parts and the effect`, `Unload removes everything`, `no per-frame work with Frost off`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite and `bash tools/test_all3.sh` (and `REF=1 bash tools/test_all.sh` if the mock changed) — Expected: PASS, `ALL PASSED`.
- [ ] **Step 5: Commit** `HappaTAS 3: Frost glass (trial)`.

### Task 11: The interface's cost, all together

**Files:** Modify `tests3/trace/bench.lua` (modes with the interface shown: Dock only, Settings open, Settings open while recording), `tools/bench3.sh` if needed; `tests3/test_ui.lua` (new: everything together). Test: `tests3/test_ui.lua`, `bash tools/bench3.sh`.

- [ ] **Step 1: Write the failing tests:** `test_ui`: start → only the Dock; open Settings and Controls; record 2 s with both open (no click reaches the engine, frames recorded); change the accent in Settings (every open window and the Dock restyle in one frame); pause, Test, Idle; Unload (no GUI, no Frost, no pointer / Menu connections, `E.inputs.mouseOverOwn` and `E.modalOpen` cleared). Bench: the Idle / recording / paused / Test modes with the Dock shown and with Settings open stay within V2's 10 % line and write no GUI property per frame while nothing animates.
- [ ] **Step 2: Run** — Expected: FAIL (the suite) or over the line (the bench) until the gaps are fixed.
- [ ] **Step 3: Fix** what they show (no new features).
- [ ] **Step 4: Run** `bash tools/test_all3.sh` — Expected: `ALL PASSED`, `BENCH OK`; the traces SAME (the interface records nothing).
- [ ] **Step 5: Commit** `HappaTAS 3: the interface together (unload, bench)`.

### Task 12: Live check

**Files:** Modify `docs/superpowers/specs/2026-10-18-happatas3-rewrite-design.md` (13: Frost answer, fonts answer, live numbers); `src2/engine/settings.lua` (fonts that don't load removed from `Settings.FONTS`, if any).

- [ ] **Step 1: Prepare** (Global Constraints' live rules), release build `bash tools/build3.sh --release wow3` to `HappaTasTest/`.
- [ ] **Step 2: Check in the EToH kit test place:** the Dock and windows appear under gethui with nothing in PlayerGui; open / drag / resize / minimise / close with the real mouse (`mousemoveabs` + `mouse1press` / `mouse1release` while `isrbxactive()`, else through `ui_helpers`-style UIS events); a click on a window while recording neither pauses nor clicks the game; typing in the search box doesn't trigger keys; every font in `Settings.FONTS` loads (`TextBounds` non-zero and the FontFace kept; drop the ones that don't); a colour change restyles every window; layout kept after re-running the script; Frost at the current graphics quality and at quality 10 (look, frame cost with 1 and 2 windows open; decide: ships, or Frost stays a trial and the option says so); per-frame cost with the Dock shown and Settings open in each mode (the zz_stage method from phase 4: every RunService connection timed, interleaved with Settings closed); Unload (no console line, nothing left).
- [ ] **Step 3: Clean up** (test files, `HappaTasTest`, Settings.json / place files byte-identical, Settings3.json / library.cache as before, the fps cap and graphics quality put back, rejoin if anything changed).
- [ ] **Step 4: Write** the answers and numbers into spec 13 and commit `HappaTAS 3 phase 5a: live check`.
