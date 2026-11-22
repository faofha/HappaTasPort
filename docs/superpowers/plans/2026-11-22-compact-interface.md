# Compact Interface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A third interface, "Compact" (Tasability-inspired): one main window with a title bar, capital tabs and
sectioned pages, the Library and Inspector as docked side panels, every HappaTAS feature reachable.

**Architecture:** Compact is the New interface's machinery in a different shell. The theme gets a compact mode
(Gotham fonts, square corners, solid accent-tinted dark shades, no shadows), so every existing kit control,
popover, toast, the timeline bar, the colour picker and the Merge window take the look for free. A new shell
(`src2/ui/compact/*`) draws the main window, title bar, tabs, sections and side panels, and *hosts* the existing
window builders (Settings, Controls, Help, About, Library, Inspector) inside its pages and panels through a
small fake-window object, so no page is written twice.

**Tech Stack:** Luau (conservative syntax), the headless Roblox mock in `tests/mock`, `luau` CLI, bash tools.

**Spec:** `docs/superpowers/specs/2026-11-22-third-interface-design.md`

## Global Constraints

- Conservative Luau: no `+=`, `//`, backtick strings, `continue`, if-expressions; 200 locals per function.
- Stored `interface` values: `"New"`, `"Classic"`, `"Compact"`; anything else loads as New. Phones stay
  Classic-only (`ui.classicOnly`).
- Name shown in the selector: **Compact**. Never "Tasability" anywhere in the product.
- No code, text, icons, images or names from `C:/Users/User/Downloads/tasabilitythis.lua` (style reference only,
  never committed). The PR lists what was taken as inspiration.
- Fonts: `Font.fromEnum(Enum.Font.GothamMedium)` text, `Font.fromEnum(Enum.Font.GothamBold)` titles; scaled by
  `textSize`. Glyphs: ASCII and × ▼ ← … • only.
- Colours: accent = `accentColor`; text = `textColor` / `secondaryTextColor`; recording = `recordingColor`.
  Backgrounds: fixed dark shades tinted toward the accent's hue. Square corners, no shadows, no glass, no blur.
- Appearance rows hidden in Compact (`newOnly = true` in the schema): `glass`, `glassColor`, `glassTransparency`,
  `blurStrength`, `edgeLight`, `font`, `numberFont`, `windowCorners`, `buttonShape`, `shadows`, `animations`,
  `animationLength`, `easing`, `easingDirection`, `bezierX1`, `bezierY1`, `bezierX2`, `bezierY2`.
  Shown and used: `theme`, `accentColor`, `textColor`, `secondaryTextColor`, `recordingColor`, `textSize`,
  `interfaceScale`, `uiSounds`, `uiSoundVolume`.
- Main window: default 700 x 500, minimum 560 x 400, drag by the title bar, resize from the bottom-right corner;
  rect, open tab, Library panel open, folded saved in the settings file's `ui.compact` table. Library panel
  ~180 px, Inspector panel ~200 px, docked left / right, following the window.
- Inspector panel follows `showStatsIdle` / `showStatsCreate` / `showStatsTest` per mode; the INSPECTOR toggle
  overrides it until the next mode change.
- Minimise folds to the title bar (panels close with it); Menu key hides / shows everything; folded is not hidden.
- Only one interface is live; Compact hidden = no per-frame work. Unload leaves nothing. Every new test file ends
  with `finish()`. `bash tools/test_all3.sh`: ALL PASSED, traces SAME, bench OK. Never commit `wow1`
  (`git restore wow1` after `bash tools/release3.sh`).
- Commits: `git -c user.name=Claude -c user.email=noreply@anthropic.com commit`, ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; no session links, no quotes of dzr's requests.

## Review Focus

1. A merge running while the interface switches to / from Compact: the Merge window must still show (it is the
   one wm window Compact keeps) and finishing / cancelling it must work. (Task 7 test.)
2. Typing in the title-bar search or a hosted text box must never fire HappaTAS keys; rebinding a key in KEYS
   then switching interface must end the wait. (Task 5 test.)
3. A saved Compact rect that is off screen (smaller window, other monitor) must come back on screen at load and
   on a screen change. (Task 4 test.)
4. Switching New -> Compact -> Classic -> Compact must leave one live copy of each hosted page (no duplicated
   rows, no stale `ui.settingsWin` pointing at a hosted copy) and no extra pipeline handlers. (Task 5 test.)
5. Unload while Compact is live, folded, with a picker / dropdown popover open: nothing left in gethui / CoreGui.
   (Task 8 test.)

---

### Task 1: The third interface value and the `newOnly` rows

**Files:**
- Modify: `src2/engine/settings.lua` (`interface` options; `newOnly` on the rows in Global Constraints)
- Modify: `src2/ui/app.lua` (`setInterface`, `newActive`, `liveShown`, `pointerOver`, `updateModal`, Menu key)
- Modify: `src2/ui/sounds.lua:92` (play while New or Compact is live)
- Modify: `src2/ui/win/settings.lua` (skip `def.newOnly` rows when the window is hosted by Compact: `win.compact`)
- Test: `tests3/test_compactswitch.lua`

**Interfaces:**
- Produces: `UI:isCompact() -> boolean` (live == "Compact"); `UI:newActive()` now true when New **or** Compact is
  live and shown (it gates the bar, Inspector and pointer work both share); `UI:setInterface("Compact")`
  creates `ui.compact` lazily via `Compact.new(ui)` (Task 4) and calls `ui.compact:setLive(true/false)`;
  schema flag `def.newOnly`.

- [ ] **Step 1: Write the failing test** `tests3/test_compactswitch.lua` (`-- needs: ui`): boot; assert
  `Settings.byKey.interface.options` equals `{ "New", "Classic", "Compact" }`; every key in the hidden list has
  `newOnly == true` and none of the shown list does; `E.settings:set("interface", "Compact")` then
  `ui:isCompact() == true`, `ui:newActive() == true`, the Dock's gui is not visible, `ui.compact ~= nil`;
  `set("interface", "Bogus")` -> live is "New"; with `ui.classicOnly = true` a set to "Compact" gives "Classic";
  `ui.sounds:play(...)` logs a sound while Compact is live (use the existing uisounds test's way of observing).
  Until Task 4 exists, stub nothing: the test is expected to fail on `ui.compact`.
- [ ] **Step 2: Run** `bash tools/build_test3.sh compactswitch && cd tests3 && luau run_compactswitch.lua`.
  Expected: FAIL (options have 2 entries).
- [ ] **Step 3: Implement** the schema change and the app.lua changes. In Compact, `applyShown` keeps
  `root.layer` visible (the bar, toasts and the Merge window live there) but hides the Dock and every wm window
  except `merge` (a wm flag `wm.hiddenAll = true` read in `Windows:apply`, or `Visible` on each holder: builder's
  choice). `updateModal` in Compact: `self.compact:modal()`. Menu key in Compact: `self:toggle()` (shows / hides
  root, which holds the compact shell too).
- [ ] **Step 4: Run** the suite again. Expected: PASS for everything except the parts needing Task 4's
  `Compact.new` (leave a minimal `Compact.new` returning `{ setLive = function() end, modal = function() return
  false end, destroy = function() end }` in `src2/ui/compact/compact.lua` and add it to `src2/modules.txt` after
  `ui/classic/*`; Task 4 replaces it). Then run `interface settings settingswin classicrows uisounds` with
  `bash <scratchpad>/suites.sh` (or `tools/build_test3.sh` per suite). Expected: all pass.
- [ ] **Step 5: Commit** "HappaTAS 3: a third interface value, Compact (switch and newOnly rows)".

### Task 2: The theme's compact mode

**Files:**
- Modify: `src2/ui/theme.lua` (`Theme:setCompact(on)`, `theme.compact`, `Theme.compactShades(accent)`)
- Modify: `src2/ui/kit/glass.lua` (`restyle`: in compact mode square, solid, outline rim, no shadow)
- Modify: `src2/ui/app.lua` (`setInterface` calls `self.theme:setCompact(name == "Compact")`)
- Test: `tests3/test_compacttheme.lua`

**Interfaces:**
- Produces: `theme.compact: boolean`; `Theme:setCompact(on: boolean)` (fires `changed` once when it flips);
  `Theme.compactShades(accent: Color3) -> { deep, window, inline, panel, element, hover, border, outline: Color3 }`;
  in compact mode `theme.font("text") = GothamMedium`, `theme.font("bold") = GothamBold`, `theme.font("number")
  = GothamMedium`, `theme.corner(any) = 0`, `theme.c.glass = shades.window`, `theme.t.glass = 0`,
  `theme.t.rim = 0`, `theme.c.rim = shades.outline` (new field, `Color3.new(1,1,1)` outside compact mode);
  `theme.shades` = the current table (nil outside compact mode).

- [ ] **Step 1: Write the failing test**: shades for accent #3FB950 — each shade's luminance in this order
  deep < window < inline < panel < element < hover, all below 0.2; each shade's hue within 30 degrees of the
  accent's hue and saturation > 0 (tinted), yet `textColor` #FFFFFF on `panel` has contrast ratio >= 7; shades
  for #F85149 are tinted red (hue within 30 degrees of red). After `theme:setCompact(true)`: `theme.corner("window")
  == 0`, `theme.font("text").Family` is GothamMedium's family string, a Glass panel's `CornerRadius` is 0, its
  shadow is not visible, its `BackgroundTransparency` is 0, its rim colour is `shades.outline`; changing
  `accentColor` re-derives the shades; `setCompact(false)` restores the New look exactly (corner = windowCorners,
  previous font, previous transparency). A `changed` listener fires once per flip, not on a no-op call.
- [ ] **Step 2: Run** `tools/build_test3.sh compacttheme`. Expected: FAIL (`setCompact` is nil).
- [ ] **Step 3: Implement.** Shades: start from Tasability-like neutral greys
  (deep 10, window 15, inline 21, panel 28, element 35, hover 44, border 8, outline 30 — grey levels out of 255)
  and mix each 8 % toward the accent (`base:Lerp(accent, 0.08)`); the builder may tune the mix if the contrast
  test needs it. Glass in compact mode: `BackgroundColor3 = th.c.glass`, transparency 0 (cover or not), rim
  `Color = th.c.rim`, `Transparency = 0`, shadow hidden.
- [ ] **Step 4: Run** `compacttheme theme windows ui picker` suites. Expected: PASS (New look unchanged).
- [ ] **Step 5: Commit** "HappaTAS 3: the theme's compact mode".

### Task 3: The compact kit (sections, tabs, chips, borders)

**Files:**
- Create: `src2/ui/compact/kit.lua`
- Modify: `src2/modules.txt` (before `ui/compact/compact`)
- Test: `tests3/test_compactkit.lua`

**Interfaces:**
- Consumes: `theme.shades`, `theme.font`, `theme.size`, `theme.c.accent` (Task 2).
- Produces (all draw with `W.set`, repaint on `theme:changed`, return tables with `gui` and `destroy()`):
  - `CK.border(gui)` — a 2 px `border` shade frame edge plus a 1 px `outline` UIStroke (the layered border).
  - `CK.accentLine(parent)` — a 2 px accent frame across the top, with a white-to-grey vertical UIGradient.
  - `CK.section(ctx, parent, title: string) -> { gui, body, title }` — `inline` fill, layered border, accent line,
    capital title (`string.upper`) in the accent at size 10.5 bold, `body` a frame with a vertical UIListLayout
    (padding 5) and AutomaticSize Y.
  - `CK.chip(ctx, parent, text, opts) -> { gui, label, set(text) }` — `element` fill, layered border, size 9.5 text;
    `opts.button` makes it a pointer rect with `onClick`.
  - `CK.tab(ctx, parent, text, onClick) -> { gui, setActive(on) }` — 90 x 22, capital text; active: accent text, a
    2 px accent underline, `inline` fill; inactive: text at transparency 0.48, `panel` fill; hover: `hover` fill.

- [ ] **Step 1: Write the failing test**: with the theme in compact mode, `CK.section(ctx, frame, "run")` has a
  title label reading "RUN" coloured `theme.c.accent`, a child named `AccentLine` 2 px tall, a UIStroke coloured
  `shades.outline`, and `body` with a UIListLayout; `CK.tab` toggled active shows its underline and accent text,
  inactive hides it; a tab click (UIH.click) calls `onClick` once; changing `accentColor` repaints the section
  title and the tab underline; `destroy()` removes the instances and the theme listener (listener count back).
- [ ] **Step 2: Run** `tools/build_test3.sh compactkit`. Expected: FAIL (module missing).
- [ ] **Step 3: Implement** `src2/ui/compact/kit.lua` with the signatures above (pointer rects through
  `ctx.pointer.add` like `ui/kit/base`).
- [ ] **Step 4: Run** `compactkit`. Expected: PASS.
- [ ] **Step 5: Commit** "HappaTAS 3: the compact kit".

### Task 4: The main window (title bar, tabs, fold, drag, resize, saving)

**Files:**
- Modify: `src2/ui/compact/compact.lua` (replace Task 1's stub)
- Test: `tests3/test_compactshell.lua`

**Interfaces:**
- Consumes: Tasks 1-3; `ui.pointer`, `ui.root.layer`, `ui.wm:screen()`, `ui.wm:screenChanged(f)`,
  `E.settingsFile:getUi()` / `setUi()`.
- Produces: `Compact.new(ui) -> compact` with fields `gui` (the main window holder in `ui.root.layer`),
  `titleBar`, `pages: { controls, settings, help, about: Frame }`, `tab: string`, `folded: boolean`,
  `panels: { library, inspector: { gui, body, open: boolean } }`, `search` (a `ui/kit/field` Field), `status`
  (a chip); methods `setLive(on)`, `modal() -> boolean` (live and shown and not folded), `showTab(name)`,
  `setFolded(on)`, `setPanel(name, on)`, `place(x, y, w, h)`, `save()`, `pointerOver() -> boolean`,
  `destroy()`. Saved shape: `ui.compact = { x, y, w, h, tab, library = bool, folded = bool }`.

- [ ] **Step 1: Write the failing test**: switch to Compact; the window is 700 x 500 at the screen centre; the
  title bar holds "HAPPATAS", a version chip reading "V" .. `CONFIG.VERSION`, LIBRARY and INSPECTOR chips, the
  search field, the status chip and a minimise chip; four tabs CONTROLS SETTINGS HELP ABOUT, CONTROLS active;
  clicking SETTINGS shows `pages.settings` only; a drag on the title bar by (40, 30) moves the window by that much;
  a drag on the bottom-right grip to below the minimum gives 560 x 400; the minimise chip folds the window to the
  title bar height (pages hidden, panels closed, `compact:modal() == false`) and a second click unfolds it;
  `save()` writes `ui.compact` and a fresh boot with that settings file restores rect, tab and folded;
  **Review Focus 3:** a saved rect at x = 5000 comes back fully on screen at boot, and again after the viewport
  shrinks (fire the camera's ViewportSize change); while live and shown the main window makes `E.modal` true;
  hidden (Menu key) makes it false and the window invisible.
- [ ] **Step 2: Run** `tools/build_test3.sh compactshell`. Expected: FAIL.
- [ ] **Step 3: Implement** the shell: holder frame with `window` shade fill, accent UIStroke, `CK.accentLine`,
  a 28-high title bar in `deep`; pages are ScrollingFrames (`AutomaticCanvasSize` Y, scroll bar 2 px accent) in
  a content frame (`deep`, layered border) inside an `inline` frame; panel frames docked at x = -panelW - 8 and
  x = w + 8, same height as the window. Save on drag / resize end, tab change, fold, panel toggle (not per move).
- [ ] **Step 4: Run** `compactshell compactswitch interface windows`. Expected: PASS.
- [ ] **Step 5: Commit** "HappaTAS 3: the Compact main window".

### Task 5: Hosting the pages (Settings, Help, About, Library, Inspector, KEYS)

**Files:**
- Create: `src2/ui/compact/host.lua`
- Modify: `src2/ui/compact/compact.lua` (host the pages and panels; title-bar search drives the Settings search)
- Modify: `src2/ui/win/settings.lua`, `help.lua`, `about.lua`, `library.lua`, `inspector.lua`, `controls.lua` only
  where a builder assumes it lives in a wm window (each change is guarded by `win.hosted`)
- Test: `tests3/test_compacthost.lua`

**Interfaces:**
- Consumes: each window module's `XWin.build(ui, body, win)` (not `define`: hosting never writes `ui.xWin`).
- Produces: `Host.new(compact, id: string, build: function, frame: Frame, opts) -> host` with `host.win =
  { ctx, body = frame, open = false, min = false, hosted = true, compact = true }`, `host.obj` (what `build`
  returned), `host:setOpen(on)` (sets `win.open`, then `ui.wm:fire(id, on)` so builders that refresh on open do),
  `host:destroy()`. `win.ctx` is a pointer context whose rects are clipped to `frame` and grouped under the
  compact window (same shape as `ui/kit/window`'s ctx). Compact keeps `compact.hosted[id]`.

- [ ] **Step 1: Write the failing test**: switch to Compact; `compact.hosted.settings`, `.help`, `.about`,
  `.library`, `.inspector`, `.controls` exist; `ui.settingsWin` is nil (or the wm copy) — never the hosted copy;
  the hosted Settings shows a row for `accentColor` and none for any `newOnly` key; typing "accent" in the
  title-bar search shows the SETTINGS tab and the hosted settings list filtered to rows matching "accent";
  **Review Focus 2:** while the title-bar search has focus, pressing the Create key (2) leaves the mode Idle; clicking
  a key in the hosted Controls list, then switching to New, ends the wait (`E.typing.rebinding == false`);
  the HELP tab lists the Help topics; the ABOUT tab shows the credits text; LIBRARY toggles the left panel and the
  hosted Library lists the place's runs; **Review Focus 4:** New -> Compact -> Classic -> Compact leaves one
  hosted settings list (row count unchanged) and the pipeline handler count equals the first Compact count.
- [ ] **Step 2: Run** `tools/build_test3.sh compacthost`. Expected: FAIL.
- [ ] **Step 3: Implement** `host.lua`; host the pages: SETTINGS <- `SettingsWin.build`, HELP <- `HelpWin.build`,
  ABOUT <- `AboutWin.build`, Library panel <- `LibraryWin.build`, Inspector panel <- `InspectorWin.build`, KEYS
  section (Task 6) <- `ControlsWin.build`. Build each lazily the first time its page / panel opens. When a
  builder closes its own window through `ui.wm:close(id)` (e.g. Merge closes the Library), Compact listens to
  `ui.wm:changed` and closes the matching panel.
- [ ] **Step 4: Run** `compacthost settingswin help librarywin inspector controlswin about pages`. Expected: PASS.
- [ ] **Step 5: Commit** "HappaTAS 3: Compact hosts the pages".

### Task 6: The CONTROLS page, status chip and Inspector rule

**Files:**
- Modify: `src2/ui/compact/compact.lua` (or `src2/ui/compact/controls.lua` if compact.lua passes ~300 lines)
- Test: `tests3/test_compactcontrols.lua`

**Interfaces:**
- Consumes: `CK.section`, `ui/kit/button`, `ui/kit/toggle`, `ui/kit/slider`; `E.modes:request(mode)`,
  `E.state` / `E.bus` for mode, frame, paused / recording; `E.settings` (`speedHack`, `speedHackSpeed`,
  `showStats*`); `E.profiler` toggle as the Help / Classic MicroProfiler button does; `Env.genv.__HappaTAS3.Unload`.
- Produces: `compact.controls = { run, speed, keys, tools }` sections; `compact.status:set(text)` driven at most
  10 times a second and only when the text changes.

- [ ] **Step 1: Write the failing test**: the CONTROLS page has sections titled RUN, SPEED HACK, KEYS, TOOLS in two
  columns (RUN, SPEED HACK left; KEYS, TOOLS right); RUN shows mode, frame / total, time and the loaded file and
  updates while recording; its Create button requests Create (mode becomes Create); the SPEED HACK switch flips
  `speedHack` and the slider sets `speedHackSpeed` (0.1 - 1); TOOLS has "MicroProfiler" (toggles it) and
  "Unload HappaTAS" (unloads); the status chip reads "Idle", then "Create · paused" after entering Create, then
  "Create · recording" while recording, "Test" while testing, coloured `recordingColor` while recording;
  Inspector panel: with `showStatsCreate = 1` it opens on entering Create and with `showStatsIdle = 0` closes on
  Idle; the INSPECTOR chip opens it in Idle and the next mode change applies Show Stats again.
- [ ] **Step 2: Run** `tools/build_test3.sh compactcontrols`. Expected: FAIL.
- [ ] **Step 3: Implement.** Status and RUN rows update from a 10-per-second throttle in the same place the Inspector
  reads its slow rows (no new per-frame handler while Compact is hidden).
- [ ] **Step 4: Run** `compactcontrols compactshell bench`. Expected: PASS, bench OK.
- [ ] **Step 5: Commit** "HappaTAS 3: Compact's controls page".

### Task 7: Bar, toasts, Merge and popovers in Compact

**Files:**
- Modify: `src2/ui/bar/bar.lua`, `src2/ui/toast.lua`, `src2/ui/kit/popover.lua` only if the theme's compact mode
  doesn't already give them the look (most should need nothing)
- Test: `tests3/test_compactmisc.lua`

- [ ] **Step 1: Write the failing test**: in Compact, in Create, the timeline bar is shown, its glass panel has
  corner 0 and transparency 0; a status toast appears with corner 0; the colour picker opened from the hosted
  Settings' accent row has corner 0; **Review Focus 1:** start a merge from the hosted Library (pick a saved run,
  Merge, Before), switch to New and back to Compact: the Merge window is visible each time and "Cancel merge"
  ends the merge (`E.merge == nil`).
- [ ] **Step 2: Run** `tools/build_test3.sh compactmisc`. Expected: FAIL on whatever doesn't follow yet.
- [ ] **Step 3: Implement** the smallest changes that make it pass.
- [ ] **Step 4: Run** `compactmisc bar mergewin dock`. Expected: PASS.
- [ ] **Step 5: Commit** "HappaTAS 3: bar, toasts, Merge and pickers in Compact".

### Task 8: Help, README, unload, release, live check

**Files:**
- Modify: `src2/ui/win/helptext.lua` (a "compact" topic "Compact interface" after "classiclook"; reword the New-only
  lines: "The Dock at the top opens the windows" -> name the New interface; "Settings and Controls are their own
  windows" -> "In the New interface, Settings and Controls are their own windows; Compact has them as tabs";
  the Merging topic's "The Merge window" stays, it exists in both)
- Modify: `README.md` (Interface row: New / Classic / Compact; a short Compact paragraph next to Classic's)
- Test: `tests3/test_compactunload.lua`; update `tests3/test_help.lua` only if a count it checks changed

- [ ] **Step 1: Write the failing test**: the Help topics include id "compact" titled "Compact interface" whose body
  names the title bar, the tabs, the LIBRARY and INSPECTOR panels and minimise; no topic body contains "Dock" without
  "New interface" in the same line; **Review Focus 5:** Compact live, folded, with the accent picker open and a
  dropdown open: Unload leaves no descendant named like the compact window, `Popover` or `PopoverCatcher` under the
  root / gethui, `getgenv().__HappaTAS3 == nil`.
- [ ] **Step 2: Run** `tools/build_test3.sh compactunload`. Expected: FAIL.
- [ ] **Step 3: Implement** the Help and README text and any unload gap the test finds.
- [ ] **Step 4: Run** `bash tools/release3.sh && git restore wow1`, then
  `timeout 590 bash tools/test_all3.sh > <scratchpad>/gate_compact.txt` in the foreground. Expected: ALL PASSED,
  traces SAME, bench OK.
- [ ] **Step 5: Live check** (Real MCP, after `game.GameId == 10769723786`; back up `HappaTasPort/` with sha1 lists,
  debug build with `Debug = true` in `HappaTasTest/`): switch to Compact; screenshot; every tab; drag / resize /
  fold; Library panel save + load of a scratch run (`zz_compact.tas`, deleted after); Inspector panel in Create;
  speed hack switch; a merge started and cancelled; switch to New and Classic and back; Unload. Restore the folder
  byte-identical, delete `HappaTasTest`, leave the FPS cap as found.
- [ ] **Step 6: Commit** "HappaTAS 3: Compact in Help and the README; wow".
