# HappaTAS V3.1: the Tasability interface's own settings (and the Compact -> Tasability rename)

Date: 2026-11-22. Follows `2026-11-22-third-interface-design.md` (the third interface, merged as PR #46 under the name
"Compact"). Style reference: dzr's Tasability script, outside the repo at `C:/Users/User/Downloads/tasabilitythis.lua`
(its `addCheckbox`, `addTextbox`, `addCombo`, `addKeybind`, `addButton`, `addSection` element builders; never
committed, nothing copied).

## Why

dzr: the third interface "doesn't feel like the Tasability one". Its SETTINGS tab and KEYS list are the New
interface's windows hosted inside it (rounded pills, sliders, one column, descriptions under every row). Like New and
Classic, it should have settings of its own, designed so it looks and feels like Tasability's. dzr approved the mockup
shown in the conversation and picked approach A. dzr also renamed the interface: **Tasability**.

## Goals

- The interface is called **Tasability** everywhere a player sees it (the Interface choice, Help, README, the PR text).
- Its SETTINGS tab is its own page, drawn with Tasability-style parts, two columns of sections, built from the same
  settings schema as New and Classic.
- The KEYS list on CONTROLS and the CONTROLS page's own controls (Speed Hack switch and speed, the Idle / Create / Test
  and tool buttons) use the same parts.

## Non-goals

- The Library and Inspector side panels, HELP and ABOUT stay hosted New windows in this round (a follow-up once dzr
  has seen this).
- No change to New, Classic, the engine, file formats or the settings file format.
- No Tasability features HappaTAS doesn't have.

## Anti-goals

- Copying Tasability's code, text, icons, images. The look is matched by our own code; the tick and the dropdown arrow
  are drawn or use glyphs every font has (ASCII and × ▼ ← … •) - Tasability's "✓" and "▾" are not used.
- A setting that needs an edit here to appear: every row comes from `Settings.SCHEMA` (shown rules below).
- Per-frame work for the page: rows repaint on setting / theme changes only.

## Approaches (dzr picked A)

- **A. Its own settings page (picked):** a small Tasability-style part kit and a SETTINGS page generated from the
  schema; KEYS uses the same key box; the hosted New Settings and Controls windows leave this interface.
- B. Keep the hosted New Settings window and swap its controls: less code, but New's single-column layout, row
  descriptions, search box and section chips stay - still feels like New.

## The rename (dzr's decision)

- `interface` option "Compact" becomes **"Tasability"** (options: New, Classic, Tasability). Description: "Tasability:
  one window with tabs, in Tasability's style".
- A settings file holding "Compact" (PR #46 shipped that value) loads as "Tasability" (the settings loader maps it, like
  the old default colours).
- Help's "Compact interface" topic becomes "Tasability interface"; the Interface lines in Help and the README say
  Tasability; README credits already name Tasability's creator.
- Internal names stay (`src2/ui/compact/*`, `ui.compact`, `UI:isCompact`, `theme.compact`, the `ui.compact` table in the
  settings file): players never see them; renaming them would touch every file of PR #46 for nothing. (Call: the
  builder may add `UI:isTasability` as an alias only if it reads clearer at a call site.)

## The parts (look, from the approved mockup)

All square, in the theme's compact shades (`Theme.compactShades`), the accent from `accentColor`, Gotham text (text
10.5-11, labels dim = `secondaryTextColor`), a 1 px black text outline like the section titles. Hover: background to
the `hover` shade and the text to the accent (instant). Each part: `gui`, `set(value)`, `destroy()`, repaints on a
theme change, pointer rects through the Compact ctx (rects grouped with the window or panel they are in).

- **Checkbox** (toggle rows): a 12 x 12 box (`deep` fill, layered border) and the label to its right (11, normal
  text). On: the box fills with a dim accent (accent mixed ~70 % toward `deep`) and an inner 6 x 6 accent square (the
  tick, drawn). The whole row is the click target. 18 high.
- **Value box** (number and text rows): the label on the left 40 % (10.5, dim), a box on the right 60 % (`element`
  fill, layered border, text left-aligned 11). Focus: the outline turns accent, the text accent. Enter or focus lost
  commits through `Settings:set` (the schema's sanitize / clamp); a refused value puts the stored one back. Numbers
  show like the New window's (integers plain, others trimmed, e.g. 0.5). 22 high.
- **Dropdown** (choice rows): the value-box row with the current choice and a ▼ at the right; a click opens a flat list
  under it (`deep` fill, layered border, 20-high items, hover accent text), in a popover above everything (the existing
  `ui/kit/popover` catcher closes it on a press outside / Esc). Font rows aren't shown here (newOnly).
- **Multi choice** (`speedHackModes`): a checkbox per option, labelled "<setting name>: <option>" (Classic does the
  same with switches).
- **Colour box** (color rows): the value box with the hex text and a 14 x 12 swatch at its right end; typing a hex /
  r, g, b commits; a click on the swatch opens the V3.1 colour picker (live preview, Cancel puts it back).
- **Theme row** (`theme`, saved looks): a dropdown of the saved looks plus a "Save as" button row (a value box for
  the name and a button), same behaviour as the New window's Theme control.
- **Key box** (controls): a 22-high button: the control's name on the left (10.5, dim), an inset box on the right 42 %
  (`deep` fill, accent-dim outline) with the key in the accent. A click waits for a key ("..." in the warning yellow
  #DCC83C); the next key / mouse button binds it through `E.controls` like the Controls window (same allowed keys,
  Backspace and Delete included, same conflict rules, Esc cancels, `Typing.rebinding` while waiting, ended by
  `UI:endTyping`). A small "×" chip at the key box's right end clears it to None (the Controls window's ×). No per-key
  reset (the "Reset all" button stays). A conflict paints the key box's outline in the recording colour and the hover
  strip says which other control shares the key (the Controls window's "Also: ..."). (Call, from the builder check.)
- **Button**: full width (or a given width) 22 high, `element` fill with a soft top-to-bottom shine, layered border,
  text centred 11.
- **Slider** (CONTROLS' Speed Hack speed only): a thin 6-high track (`deep`, layered border) with the accent fill and
  a 10 x 10 square knob, the value at the right ("0.50x"); drag or click to set, a click on the value edits it in a
  value box.

## The SETTINGS page

- Two columns. Sections in the schema's section order, placed one by one into the shorter column (balanced), each a
  `CK.section` (accent line, capital title) with its rows stacked (fixed row heights, like the CONTROLS page: the mock
  has no list layout).
- Shown rows: every schema row that the New window shows, minus `newOnly`, `hidden`, `classicOnly` and the follower rows
  (the same rules the hosted page used) - and minus `interface`'s own segmented look (it is a dropdown here).
- Each section title bar has a small "RESET" chip at its right end: puts that section's rows to their defaults (the
  New window's "Reset section"). No per-row reset arrows (Tasability has none). (Call.)
- Descriptions: hovering a row shows its `desc` in a one-line strip at the bottom of the SETTINGS page (dim text).
  (Call: Tasability shows none; this keeps the help without a line under every row.)
- The title-bar search filters this page: rows whose name or description matches stay, sections with none hide, the
  columns re-balance. An empty search shows everything.
- Live: every row follows its setting (a change from anywhere shows at once), and its parts repaint on a theme change.

## KEYS and CONTROLS

- KEYS (right column of CONTROLS): a key box per control in `engine/controls` order, plus a "Reset all" button at the
  bottom (the Controls window's). The hosted Controls window leaves this interface.
- CONTROLS' SPEED HACK: the Speed Hack checkbox and the slider above. RUN's Idle / Create / Test and TOOLS' buttons:
  the button part.

## Calls made here (dzr can overrule)

- Internal names stay `compact`.
- RESET chip per section, no per-row reset; descriptions in a hover strip.
- Numbers are value boxes (Tasability's physics numbers are text boxes); only the Speed Hack speed on CONTROLS is a
  slider (Tasability's speed hack has one).
- Library / Inspector / HELP / ABOUT unchanged this round.

## What's left to the builder

- File layout (suggested: `src2/ui/compact/parts.lua` for the parts, `src2/ui/compact/settings.lua` for the page,
  `src2/ui/compact/keys.lua` for KEYS), how the column balancing measures heights (fixed row heights make it a sum).
- Reusing the New window's helpers (number formatting, the theme / saved-looks logic, the controls' binding rules)
  by moving them where both can import them, or calling them where they already are.
- Tests: a suite per piece (parts, page, keys, rename / migration), the existing suites still pass, traces SAME, bench
  OK; a live check in the EToH kit test place with real mouse clicks.
