# HappaTAS V3.1: the third interface (Tasability-inspired)

Date: 2026-11-22. Item 12 of the V3.1 list (branch feature/third-ui). Research notes: the V3.1 Part 1 research,
sections 13 (inventory) and 14 (third interface): `docs/superpowers/specs/2026-11-21-v3-1-part1-research.md` on
branch `v3-credits-key-ui` (commit 355559e; not on this branch). Style reference: dzr's Tasability script, kept
outside the repo at `C:/Users/User/Downloads/tasabilitythis.lua` (never committed).

## Why

dzr likes how Tasability's interface looks ("It looks nice") and wants HappaTAS to offer that look, with its
layout, as a third choice next to New and Classic. Success: a player picks it in Settings > Interface and gets a
HappaTAS that looks and is laid out like Tasability, with every HappaTAS feature reachable, and nothing else in
HappaTAS changes.

## Goals

- A third value of the `interface` setting. The selector shows three options in the New window, in Classic and
  in the new interface.
- Tasability's look: one main window, square corners, layered dark borders, a thin accent border and a 2 px
  accent line on top, small capital titles, Gotham text with a black text outline.
- Tasability's layout: a title bar, capital tabs, sectioned pages (two columns on the Controls page), side
  panels docked to the main window's edges.
- Every HappaTAS feature the New interface offers is reachable here (spec 8 of the rewrite design; the V3.1
  research section 13 inventory is the checklist).

## Non-goals

- No Tasability features HappaTAS doesn't have: physics editor, player viewer, console, teleport / rejoin,
  trajectory tracer, keyboard overlay, FPS box. Each would be its own request.
- No change to the New or Classic interfaces, the engine, the file formats or the settings file format.
- No phone support: a touch screen without a keyboard stays Classic-only (app.lua `classicOnly`).

## Anti-goals (a failure even if it works)

- Copying Tasability: no code, text, icons, images or names taken from `tasabilitythis.lua`. It is a style
  reference only. The PR lists everything taken as inspiration (layout ideas, the layered-border style, the
  section look).
- A second copy of anything that already has one source: settings rows come from the settings schema, keys from
  `engine/controls`, Help from `ui/win/helptext`, credits and the update log from the same lists the About window
  uses, colours from the shared Appearance settings. Adding a setting must never need an edit here.
- Per-frame cost while it is hidden (only one interface is live, like Classic today).
- Making the New interface slower (bench gate, traces SAME).

## Constraints

- Conservative Luau (no `+=`, `//`, backtick strings, `continue`, if-expressions); 200 locals per function.
- Everything parented under gethui / CoreGui like the other interfaces; AutoLocalize off; owned by the
  interface's lifecycle scope (Unload leaves nothing).
- Clicks on it are never a Pause / Unpause; keys don't fire while typing in its boxes (`E.typing:watch`).
- Fonts: only Roblox fonts (Gotham via `Font.fromEnum`); glyphs limited to ASCII and × ▼ ← … • (Help text rule).
- Old settings files load; `interface` values other than the three fall back to New (today: anything not
  "Classic" is New).

## Approaches (dzr picked B)

- A. The look only: the New interface's Dock and windows redrawn in Tasability's style. Small, but close to a
  colour theme.
- **B. The look and the layout (picked):** a real third interface, like Classic is, built from the shared lists.
  The most work; the only one that looks like Tasability.

Colours (dzr picked A): the interface shares the New interface's Appearance colours. `accentColor` (default green
#3FB950 since V3.1) is the accent; the background shades are fixed dark greys tinted faintly toward the accent's
hue (like Tasability's presets, whose blacks lean to their accent). Changing the accent in either interface
changes both. No preset list of its own.

## What dzr decided

- Approach B, colours A (above).
- The mockup shown in the conversation (no objections raised):

```
 ┌ LIBRARY ──┐ ┌ HAPPATAS [V3.1] [LIBRARY][INSPECTOR]  ● Create · paused  – ┐ ┌ INSPECTOR ┐
 │ search... │ │ CONTROLS  SETTINGS  HELP  ABOUT                            │ │ FRAME     │
 │ Slot 1    │ │ ┌▔RUN▔▔▔▔▔▔▔▔▔▔▔▔▔┐  ┌▔KEYS▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔┐                 │ │ CHARACTER │
 │ 123       │ │ │ mode frame time │  │ Pause  [Left Click] │                 │ │ CAMERA    │
 │ [Save]... │ │ │ [Idle][Create].. │  │ ...                 │                 │ │           │
 └───────────┘ │ ┌▔SPEED HACK▔▔▔▔▔┐  ┌▔TOOLS▔▔▔▔▔▔▔▔▔▔▔▔▔▔┐                 │ └───────────┘
               └──────────────────────────────────────────────────────────────┘
 [CREATE 0.5x  |◀ ◀| ● |▶ ▶ ◆  ━━━━━━━━━━━━━━━━━━━━━━━━  1,204 · 20.07 s]   (timeline bar, same style)
```

  - Title bar: "HAPPATAS", a version chip, LIBRARY and INSPECTOR toggles (open / close the side panels), a search
    box (searches settings and jumps to the Settings tab), a status pill (mode, and paused / recording), a
    minimise button. Drag the title bar to move the window.
  - Tabs: CONTROLS, SETTINGS, HELP, ABOUT.
  - CONTROLS (two columns): RUN (mode, frame / total, time, file; Idle / Create / Test buttons), SPEED HACK (the
    on switch and the speed), KEYS (every control from `engine/controls`, click to rebind like the Controls
    window), TOOLS (MicroProfiler, Unload HappaTAS).
  - SETTINGS: every setting the New window shows, one section per schema section, in the schema's order; the
    same controls (switch, slider, choice, colour swatch opening the V3.1 picker, keys); the reset arrow; locked
    / hidden rows as in the New window.
  - HELP: the Help topics (list + text, the same search) from `ui/win/helptext`.
  - ABOUT: version, credits and the update log from the same lists as the About window.
  - Library panel docked left (search, the run list with attempts and folders, Save / Load / Merge / Delete,
    Rename / Move to); Inspector panel docked right (the Inspector's sections and rows).
  - The timeline bar at the bottom in Create and Test, in this interface's style.

## Calls made here (dzr can overrule)

- **Name in the Interface selector: "Compact".** Not "Tasability" (it is not Tasability, and HappaTAS shouldn't
  carry another script's name). Stored value "Compact".
- Window: 700 x 500 by default, minimum 560 x 400, drag by the title bar, resize from the bottom-right corner,
  position / size / open tab / open panels saved in the settings file's `ui` table (like the New windows).
  Side panels are fixed widths (about 180 px Library, 200 px Inspector) and follow the window.
- Minimise hides the main window and its panels; the Menu key does the same as in the other interfaces (hide /
  show everything). The timeline bar stays while hidden only if the New interface's bar does today.
- Fonts are fixed: GothamMedium for text, GothamBold for titles (Tasability's look); the shared `textSize`
  setting scales them.
- Appearance rows in Compact (a schema flag in the spirit of `classicOnly`, e.g. `newOnly`, marks the rest):
  - **Shown and used:** `theme` (saved looks still store every Appearance key; loading one in Compact applies
    the keys Compact uses), `accentColor`, `textColor`, `secondaryTextColor`, `recordingColor`, `textSize`,
    `interfaceScale`, `uiSounds`, `uiSoundVolume` (Compact plays the same interface sounds as New: `Sounds:play`
    learns the third value).
  - **Hidden here (New only):** `glass`, `glassColor`, `glassTransparency`, `blurStrength`, `edgeLight`, `font`,
    `numberFont`, `windowCorners`, `buttonShape`, `shadows`, `animations`, `animationLength`, `easing`,
    `easingDirection` and the custom curve. Compact's panels are solid (no glass, no blur), square, without
    shadows; hover changes are instant or a fixed short fade.
  - Classic Look rows stay Classic-only.
- Minimise folds the main window to its title bar (the side panels close with it; the title bar stays draggable
  and clickable, and its minimise button unfolds it). The fold is saved in the `ui` table. The Menu key still
  hides / shows everything (today's `shown` flag); folded is not hidden, so the title bar counts for
  `pointerOver`, and the timeline bar and toasts stay as they are.
- Inspector panel: the Show Stats rows (`showStatsIdle` / `Create` / `Test`) decide per mode, as in the New
  interface; the INSPECTOR toggle opens / closes it until the next mode change, which applies Show Stats again.
  The Library panel's open state is saved in the `ui` table.
- Help: the shared topics stay; `ui/win/helptext` gets a "Compact interface" topic (title bar, tabs, panels,
  minimise) next to "Classic interface", and the New-only lines ("The Dock at the top opens the windows",
  "Settings and Controls are their own windows", "The Merge window") are reworded so they read right in every
  interface, or name the interface they describe. The What's new / update log lists aren't touched here (PR 13
  owns them).
- Merge: the merge flow opens as a small window in this style (same states as the New Merge window). Toasts
  use this style too.
- Inspector panel: the same values and update rules as the New Inspector (every frame while open, slow rows 5
  times a second); pin / hide / fold may be left out if it costs a lot - the values matter, the extras don't.
- Interface switch: switching to or from Compact keeps the run, the settings and the engine state; only the
  interface changes (as New <-> Classic today).

## What's left to the builder

- How to share code with the New interface: reuse the New interface's pointer, theme, popover, colour picker,
  bar model, Inspector values and Library logic where they don't assume the New look; write new drawing code
  (a small kit: section, tab, chip, button, switch, slider, keybind box, text box) for the look. Wherever a New
  window's builder can draw into a given frame, prefer driving it with this style over copying it.
- The exact background shades (dark greys with a faint accent tint, readable text on all of them) and how the
  tint is derived.
- Module layout (suggested: `src2/ui/compact/*`), how `UI:setInterface` / `newActive` / `liveShown` /
  `pointerOver` / `updateModal` learn the third value.
- Tests: a suite per piece, the existing interface suites (interface, classicmenu, settingswin...) still pass,
  traces SAME, bench OK; a live check in the EToH kit test place.
- The PR description lists what was taken from Tasability as inspiration.
