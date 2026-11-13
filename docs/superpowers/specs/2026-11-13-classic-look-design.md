# Classic interface: colours and a background (design)

Date: 2026-11-13. Status: waiting for dzr's approval.

## Intent

The New interface has an Appearance section (glass, accent, text colours, fonts...). The Classic interface has none:
it always draws V2.38.17's fixed blue palette. dzr wants Classic customisable too: every colour it draws, plus a
picture or video as its background, set by pasting a link. These settings exist only for Classic, so only Classic's
Settings tab shows them; the New interface's Settings window never lists them.

## Goals

- One setting per colour Classic draws (dzr picked "every colour" over a 4-colour summary).
- A background: a link to a picture (downloaded once, then loaded with `getcustomasset`), or a Roblox image / video
  asset id.
- Changes show at once, also on rows made later (saves list, settings rows).
- Saved in the one settings store (`Settings3.json`) like every other setting.

## Non-goals

- GIFs (dzr: "maybe not GIFs").
- Video files from links: measured live 2026-11-13, a `VideoFrame` never loaded an MP4, a VP8 WebM or a VP9 WebM
  loaded through `getcustomasset` (20 s each, no resolution / length, time still), while a Roblox-hosted video
  (`rbxassetid://5608337069`) loaded at once (1280x720). Videos therefore work only as Roblox video asset ids.
- Changing the New interface, fonts or layout of Classic.

## Constraints

- Network: HappaTAS has had no network code. This adds exactly one call, `game:HttpGet(link)`, only for a link dzr
  pastes into the Classic Background setting, only when that file isn't saved yet (as dzr's EvadeClone script does).
  Nothing else touches the network. The project conventions note changes to say so.
- Executor functions from Real's docs only: `getcustomasset(path)` takes a workspace file path, not a URL, and
  returns `rbxasset://...` (docs.projectreal.gg filesystem/getcustomasset). Without `getcustomasset`, `writefile`
  or `HttpGet`, link backgrounds are off with a status message; asset ids still work.
- Bench gate: no new per-frame engine reads; colours are written only when a setting changes or a part is built.
- Conservative Luau; files keep their line endings.

## Approaches considered

1. **Every colour (picked).** A setting per distinct colour in V2's Classic palette, named by where it shows.
2. Four role colours (window, buttons, outlines, text) with the rest derived. Fewer settings, less control:
   dzr chose 1.

Main colour (dzr asked for one colour that the others follow, darker parts staying darker):

1. **Auto colours (picked).** Every colour setting is "Auto" until typed; Auto follows the Main Colour. Clearing a
   box puts it back on Auto.
2. Picking a Main Colour overwrites every colour once (hand-set colours lost on the next pick): not picked.

Picker (dzr: "make it choose any color"):

1. **A Classic-styled picker (picked)**: saturation / value square, hue bar, HEX / RGB box, old / new preview,
   Apply / Cancel, drawn in Classic's look with plain button events; the colour maths shared with the New
   interface's `ui/kit/colorpicker.lua`.
2. The New interface's picker opened inside Classic: its glass look would stand out and New's pointer layer would
   have to run under Classic: not picked.

## Design

### Main Colour and Auto

- **Main Colour** (default `#003481` = V2's Button colour 0, 52, 129, so every Auto colour starts exactly on V2's).
- Every colour below stores either "Auto" (the default) or a colour. Auto = derived from the Main Colour; a typed or
  picked colour is fixed; an empty box = Auto again.
- Derivation, for the tinted colours (V2's blues: Window, Panel, Button, Outline, Field outline, Divider, Line,
  Section title): in HSV, hue = the Main Colour's; saturation = main S x (default S / base S); value = main V x
  (default V / base V), base = 0, 52, 129. A value above 1 is capped at 1 and the excess lowers the saturation
  instead (a brighter part turns paler, not clipped). With the default Main Colour each result rounds back to V2's
  colour exactly (tested).
- Neutral colours (Shade, Scroll bar, Text, Dark text, Placeholder text, Light outline, Cancel, Warning, Icon button,
  Switch on / off) have Auto = their V2 colour; they change only when set by hand.

### Settings (section "Classic Look", `classicOnly = true`, Appearance-like `color` kind, defaults = Auto)

| Setting | V2 colour (Auto at the default Main Colour) | Where it shows |
|---|---|---|
| Window | 0, 35, 73 | Main menu, stats panels, merge dialog, join message |
| Panel | 0, 41, 91 | Lists, slot list, slot expansion, menu Close button |
| Button | 0, 52, 129 | Buttons, key buttons, text boxes, button bars |
| Shade | 0, 0, 0 | Tab buttons, list rows, credits / update log backs |
| Scroll bar | 0, 0, 0 | Scroll bars |
| Text | 255, 255, 255 | Text |
| Dark text | 27, 42, 53 | Merge stats text, dark labels |
| Placeholder text | 178, 178, 178 | Empty text boxes |
| Outline | 0, 141, 237 | Window outlines |
| Field outline | 0, 169, 244 | Text box and list outlines |
| Divider | 0, 196, 248 | Row dividers, highlight outlines |
| Line | 0, 77, 205 | Title line, default outlines |
| Light outline | 255, 255, 255 | White outlines and borders |
| Cancel | 142, 11, 0 | Cancel button |
| Warning | 100, 0, 0 | Merge stats warning |
| Icon button | 163, 162, 165 | Close / expand icon buttons |
| Section title | 140, 205, 255 | Settings section titles |
| Switch on | 75, 75, 75 | A switch's knob when on |
| Switch off | 255, 255, 255 | A switch's knob when off |

Found while planning (2026-11-13), also "every colour": Light Fill (255, 255, 255 backgrounds: switch tracks,
light fills), Label Text (0, 0, 0 text: expand arrows), Merge OK (0, 80, 0) and Toggle Off (50, 50, 50), the last
two painted by the Saves tab while running. That makes 23 colours; the plan's Task 2 has the final list and keys.

The "Where it shows" names are checked against the built tree while building (same colour value -> same setting);
`Shade` and `Scroll bar` share V2's black but are separate settings because they are different parts.

Plus:

- **Background** (text): empty = none. A link (`http://` / `https://`) to a picture, a Roblox image id
  (`rbxassetid://123` or a plain number), or a Roblox video id written `video:123` / `rbxassetid://` with
  Background Is Video on. (Builder's call: the exact video marker; it must be one field dzr can paste into.)
- **Background Transparency** (0 - 100, default 40): how much the window colour shows over the picture.
- **Background Fit**: Crop / Fit / Stretch (default Crop).

Hex (`#00234A`) and `r, g, b` are both accepted in Classic's input boxes; a value the store refuses shows the old one.

### Where it lives

- `src2/engine/settings.lua`: the rows, `classicOnly` flag.
- `src2/ui/win/settings.lua`: skips `classicOnly` rows. `src2/ui/classic/settingsrows.lua`: shows them (colour rows
  as input boxes with a small colour swatch; the box shows "Auto" or the hex; clicking the swatch opens the picker).
- `src2/ui/classic/colorpicker.lua` (new): the Classic-styled picker, one at a time, inside Classic's ScreenGui;
  Apply writes the setting, Cancel / Esc / clicking outside closes it unchanged.
- The HSV / hex helpers move from `ui/kit/colorpicker.lua` into a small shared module both pickers import.
- `src2/ui/classic/look.lua` (new): the palette remap. While Classic builds (and whenever `ClassicBuild.node` builds
  a later row), every colour property whose value is a palette colour is registered as (instance, property, key);
  a settings change rewrites only that key's entries. Dead instances drop out.
- `src2/ui/classic/background.lua` (new): an `ImageLabel` / `VideoFrame` behind the main menu's content, clipped to
  it. A link is saved as `HappaTasPort/Backgrounds/<hash of the link>.<ext from the link or the file's magic bytes>`;
  an existing file is reused (no download). Videos loop, muted. A failed download or load leaves the plain window
  colour and puts the reason on Classic's status line.

## Tests (headless)

- New suite: the default Main Colour gives V2's colours exactly; a red / grey / white Main Colour keeps each
  part's darker / lighter order; Auto vs typed vs cleared; the picker (square, hue, HEX / RGB, Apply / Cancel);
  every palette colour maps to its setting; changing a setting repaints built parts and rows built
  later; New's Settings window lists none of them, Classic's lists all; hex / rgb input; background link downloads
  once (mock `HttpGet`, `writefile`, `getcustomasset`), reused next time, failure messages; asset id / video id;
  transparency and fit; Unload leaves nothing.
- Gate: `bash tools/test_all3.sh` (traces SAME except the settings rows, bench OK).

## Live check

Classic with a few colours changed, a picture link (downloaded once, reused after a reload), a Roblox image id, a
Roblox video id; New interface's Settings window unchanged. Test files deleted afterwards.

## Left to the builder

The video marker in the Background field, the swatch look, the exact part names in "Where it shows".
