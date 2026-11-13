# Classic Look Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Classic gets a "Classic Look" settings section: a Main Colour that every colour follows on Auto, one setting per colour Classic draws, a Classic-styled colour picker, and a background picture (link or Roblox image id) or Roblox video id behind the main menu.

**Architecture:** Settings rows live in the one store (`engine/settings.lua`, section "Classic look", `classicOnly`). `ui/classic/palette.lua` knows every V2 colour, which setting owns it and how Auto derives it from the Main Colour; `ui/classic/look.lua` registers every Classic instance property that holds a palette colour (at build and on `DescendantAdded`) and repaints only what a settings change touches. `ui/classic/colorpicker.lua` is the picker; `ui/classic/background.lua` loads and shows the background.

**Tech Stack:** Luau (conservative syntax), headless mock `tests/mock/*`, `luau` CLI, `bash tools/build_test3.sh NAME`.

**Spec:** `docs/superpowers/specs/2026-11-13-classic-look-design.md`

## Global Constraints

- The only network call in HappaTAS: `game:HttpGet(link)` for a link typed into Classic's Background setting, only when its file isn't saved yet. Nothing else touches the network.
- `getcustomasset(path)` takes a workspace path and returns `rbxasset://...` (Real docs). Without `getcustomasset`, `writefile` or `HttpGet`, a link background is off with a status message; Roblox ids still work.
- Video files from links are refused (MP4 / VP8 WebM / VP9 WebM never loaded live); videos only as Roblox video ids.
- Defaults reproduce V2.38.17's Classic exactly (Main Colour `#003481`, every colour Auto).
- No new per-frame engine reads (bench gate); colours are written only on build or a settings change.
- Conservative Luau (no `+=`, `//`, backtick strings, `continue`, if-expressions); keep each file's line endings (src2 mixes CRLF / LF).
- The New interface's Settings window lists none of these rows; Classic's Settings tab lists all of them.

## Review Focus

- A later-built row (a new save slot after Rename / Delete, a rebuilt settings row) must come up in the current colours, not V2's.
- A colour the code writes while running (save slot on / off, merge OK / warning, switch knobs, section titles) must follow its setting and must not be repainted with a wrong key on the next change.
- A Main Colour of pure white, pure black or grey (saturation 0) must not produce NaN or garbage hues.
- A bad link (404 page, HTML, a video file, a 0-byte body) leaves the plain window and says why; it never leaves a half-written file that is then reused.
- Switching to the New interface and back, or Unload, leaves no picker, background or listener behind.

Each line has its test in the task that owns the code (marked "Review Focus").

---

### Task 1: Settings rows, kinds and where they show

**Files:**
- Modify: `src2/engine/settings.lua` (rows, NAMES, `sanitize`)
- Modify: `src2/ui/classic/settingsrows.lua` (`shownHere`, `SECTIONS`)
- Modify: `tests3/test_classiclook.lua` (the shown count)
- Create: `tests3/test_classiccolors.lua` (first sections; later tasks add theirs)

**Interfaces:**
- Produces: setting keys (all `classicOnly = true`, section `"Classic look"`):
  `classicMainColor` (kind `color`, default `"#003481"`);
  23 colour keys of kind `autocolor` (value `"Auto"` or `"#RRGGBB"`, default `"Auto"`), in this order:
  `classicWindow, classicPanel, classicButton, classicShade, classicScrollBar, classicLight, classicText, classicDarkText, classicLabelText, classicPlaceholder, classicSectionTitle, classicOutline, classicFieldOutline, classicDivider, classicLine, classicLightOutline, classicCancel, classicWarning, classicMergeOk, classicToggleOff, classicIconButton, classicSwitchOn, classicSwitchOff`;
  `classicBackground` (kind `text`, `maxLength = 500`, default `""`), `classicBackgroundTransparency` (number 0 - 100, integer, default 40), `classicBackgroundFit` (choice `Crop / Fit / Stretch`, default `Crop`).
- Produces: `Settings.sanitize` accepts, for `color` and `autocolor`, `#RGB`, `#RRGGBB` and `"r, g, b"` (0 - 255 integers, any spaces) -> `"#RRGGBB"`; `autocolor` also maps `"auto"` (any case) and `""` to `"Auto"`. `text` rows honour `def.maxLength` (default 40).

- [ ] **Step 1: Write the failing tests** (`tests3/test_classiccolors.lua`, starts with `-- needs: ui`, ends with `finish()`)

```lua
section("the rows")
local Settings = __T3("engine/settings")
local keys = 0
for _, def in ipairs(Settings.SCHEMA) do
	if def.classicOnly then keys = keys + 1; eq(def.section, "Classic look", def.key .. " in Classic look") end
end
eq(keys, 27, "Main Colour, 23 colours, 3 background rows")
eq(Settings.sanitize(Settings.byKey.classicPanel, "auto"), "Auto", "auto")
eq(Settings.sanitize(Settings.byKey.classicPanel, ""), "Auto", "empty = Auto")
eq(Settings.sanitize(Settings.byKey.classicPanel, "0, 41, 91"), "#00295B", "r, g, b")
eq(Settings.sanitize(Settings.byKey.classicMainColor, "255,0,0"), "#FF0000", "r,g,b on a color row")
eq(Settings.sanitize(Settings.byKey.classicPanel, "256, 0, 0"), nil, "out of range refused")
eq(Settings.sanitize(Settings.byKey.classicMainColor, "Auto"), nil, "the Main Colour has no Auto")
eq(Settings.sanitize(Settings.byKey.classicBackground, string.rep("a", 500)), string.rep("a", 500), "a 500-character link")
eq(Settings.sanitize(Settings.byKey.classicBackground, string.rep("a", 501)), nil, "501 refused")
section("Classic shows them, the New Settings window doesn't")
-- Classic: E.settings:set("interface", "Classic"); every classicOnly key has ui.classic.settingsRows[key]
-- New: open the Settings window (E.ui windows API as test_settingswin.lua does); none of its rows is classicOnly
```

Also in `tests3/test_classiclook.lua`: the loop's shown rule becomes `def.v2 or def.key == "interface" or def.classicOnly`, and `eq(shown, 61, ...)` (34 + 27).

- [ ] **Step 2: Run, expect FAIL** — `bash tools/build_test3.sh classiccolors >/dev/null && (cd tests3 && timeout 300 luau run_classiccolors.lua | grep -E "FAIL|RESULT")` -> `0 classicOnly rows` failures.

- [ ] **Step 3: Implement** the rows (names: "Main Colour", "Window", "Panel", "Button", "Shade", "Scroll Bar", "Light Fill", "Text", "Dark Text", "Label Text", "Placeholder Text", "Section Title", "Outline", "Field Outline", "Divider", "Line", "Light Outline", "Cancel", "Warning", "Merge OK", "Toggle Off", "Icon Button", "Switch On", "Switch Off", "Background", "Background Transparency", "Background Fit"; each with a `desc` from the spec's "Where it shows"), the sanitize rules, `shownHere` += `def.classicOnly`, `SECTIONS["Classic look"] = "Classic Look"`. The rows go after the Interface rows (Classic's list order = schema order).

- [ ] **Step 4: Run** `classiccolors` and `classiclook` -> PASS.

- [ ] **Step 5: Commit** `HappaTAS 3: Classic Look settings (Classic only)`.

### Task 2: The palette and Auto colours

**Files:**
- Create: `src2/ui/classic/palette.lua`
- Modify: `src2/ui/kit/colorpicker.lua` (use `Palette.hex` instead of its local `hexOf`)
- Modify: `src2/modules.txt` (palette before the classic modules)
- Test: `tests3/test_classiccolors.lua`

**Interfaces:**
- Produces: `Palette.LIST` = array of `{ key = string, color = Color3 (V2's), tinted = boolean, props = { [propName] = true } }` in Task 1's key order, with these V2 colours and property families (B = BackgroundColor3, T = TextColor3, P = PlaceholderColor3, S = UIStroke Color, D = BorderColor3, I = ScrollBarImageColor3):
  window 0,35,73 B tinted · panel 0,41,91 B tinted · button 0,52,129 B tinted · shade 0,0,0 B · scrollBar 0,0,0 I · light 255,255,255 B · text 255,255,255 T · darkText 27,42,53 T · labelText 0,0,0 T · placeholder 178,178,178 P · sectionTitle 140,205,255 T tinted (runtime only) · outline 0,141,237 S tinted · fieldOutline 0,169,244 S tinted · divider 0,196,248 B,S tinted · line 0,77,205 B,S tinted · lightOutline 255,255,255 S,D · cancel 142,11,0 B · warning 100,0,0 B · mergeOk 0,80,0 B (runtime) · toggleOff 50,50,50 B (runtime) · iconButton 163,162,165 B · switchOn 75,75,75 B (runtime) · switchOff 255,255,255 B (runtime).
- Produces: `Palette.keyFor(prop: string, c: Color3) -> string?` (the owner of a built colour; runtime-only keys are never returned), `Palette.resolve(settings) -> { [key] = Color3 }`, `Palette.derive(main: Color3, v2: Color3) -> Color3`, `Palette.hex(c: Color3) -> "#RRGGBB"`, `Palette.BASE = Color3.fromRGB(0, 52, 129)`.
- `derive` (the spec's rule, written out because the tests don't fix every detail):

```lua
-- hue keeps the V2 colour's offset from the base hue; saturation and value scale by main / base;
-- a value above 1 is capped and the rest lowers the saturation (paler, not clipped). Grey mains: s = 0.
local function derive(main, v2)
	local bh, bs, bv = BASE:ToHSV()
	local mh, ms, mv = main:ToHSV()
	local h, s, v = v2:ToHSV()
	local nh = (mh + (h - bh)) % 1
	local ns = (bs > 0) and math.min(1, ms * s / bs) or 0
	local nv = (bv > 0) and (mv * v / bv) or v
	if nv > 1 then ns = ns / nv; nv = 1 end
	return Color3.fromHSV(nh, ns, nv)
end
```

- [ ] **Step 1: Write the failing tests**

```lua
section("Auto colours")
local Palette = __T3("ui/classic/palette")
local function rgb(c) return math.floor(c.R * 255 + 0.5) .. "," .. math.floor(c.G * 255 + 0.5) .. "," .. math.floor(c.B * 255 + 0.5) end
for _, p in ipairs(Palette.LIST) do
	eq(rgb(Palette.derive(Palette.BASE, p.color)), rgb(p.color), p.key .. ": the default Main Colour gives V2's colour")
end
local red = Color3.fromRGB(200, 0, 0)
local w, b, o = Palette.derive(red, Palette.LIST[1].color), Palette.derive(red, Palette.LIST[3].color), Palette.derive(red, Palette.LIST[12].color)
check(select(3, w:ToHSV()) < select(3, b:ToHSV()) and select(3, b:ToHSV()) <= select(3, o:ToHSV()), "red: window darker than buttons, outline lightest")
check(w.R > w.G and w.R > w.B, "red: the window is red")
-- Review Focus: grey / white / black mains
for _, m in ipairs({ Color3.new(1, 1, 1), Color3.new(0, 0, 0), Color3.fromRGB(128, 128, 128) }) do
	for _, p in ipairs(Palette.LIST) do
		local c = Palette.derive(m, p.color)
		check(c.R == c.R and c.G == c.G and c.B == c.B and c.R >= 0 and c.R <= 1, p.key .. ": a number for " .. rgb(m))
	end
end
local resolved = Palette.resolve(E.settings)
eq(rgb(resolved.classicWindow), "0,35,73", "resolve: Auto at the default")
E.settings:set("classicShade", "#123456")
eq(rgb(Palette.resolve(E.settings).classicShade), "18,52,86", "resolve: a typed colour wins")
E.settings:set("classicMainColor", "#C80000")
eq(rgb(Palette.resolve(E.settings).classicText), "255,255,255", "neutral Auto stays V2's")
E.settings:set("classicShade", "Auto"); E.settings:set("classicMainColor", "#003481")
eq(Palette.keyFor("ScrollBarImageColor3", Color3.new(0, 0, 0)), "classicScrollBar", "black scroll bar")
eq(Palette.keyFor("BackgroundColor3", Color3.new(0, 0, 0)), "classicShade", "black background")
eq(Palette.keyFor("BackgroundColor3", Color3.fromRGB(50, 50, 50)), nil, "runtime-only colours aren't registered")
```

- [ ] **Step 2: Run, expect FAIL** (module missing).
- [ ] **Step 3: Implement** `palette.lua` per the Interfaces block; neutral Auto = the V2 colour.
- [ ] **Step 4: Run** `classiccolors` and `settingswin` (the kit picker's hex) -> PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: Classic palette and Auto colours`.

### Task 3: Repainting Classic

**Files:**
- Create: `src2/ui/classic/look.lua`
- Modify: `src2/ui/classic/classic.lua` (create the Look right after `ClassicBuild.build`, before the rows; `self.look`)
- Modify: `src2/ui/classic/saves.lua` (ON / OFF / GREEN / RED from the Look; refresh on a change)
- Modify: `src2/ui/classic/settingsrows.lua` (knobs and section titles from the Look; re-show on a change)
- Test: `tests3/test_classiccolors.lua`

**Interfaces:**
- Consumes: `Palette.keyFor`, `Palette.resolve`.
- Produces: `Look.new(classic) -> look`; `look:color(key) -> Color3`; `look:own(inst, prop)` (the caller paints this property itself: never registered or repainted); `look:changed(f) -> off` (f() after any repaint); everything disconnected through `classic.offs`. Registration walks `classic.gui` once and on `DescendantAdded`, for the property families of Task 2 on `GuiObject`s and `UIStroke`s; an instance with attribute `HappaTASNoLook` and its descendants are skipped. Entries of destroyed instances (Parent nil) are dropped when found. A change of `classicMainColor` or any colour key re-resolves and rewrites only keys whose colour changed.

- [ ] **Step 1: Write the failing tests**

```lua
section("repainting")
E.settings:set("interface", "Classic"); M.steps(1)
local c = ui.classic
local menu = c.byPath.MainMenu
eq(rgb(menu.BackgroundColor3), "0,35,73", "V2's window colour at the default")
E.settings:set("classicMainColor", "#C80000"); M.steps(1)
check(menu.BackgroundColor3.R > menu.BackgroundColor3.B, "Main Colour red: the window turns red")
E.settings:set("classicWindow", "#00FF00"); M.steps(1)
eq(rgb(menu.BackgroundColor3), "0,255,0", "a typed Window colour wins")
E.settings:set("classicWindow", "Auto"); M.steps(1)
check(menu.BackgroundColor3.R > menu.BackgroundColor3.G, "back on Auto: red again")
-- Review Focus: a row built later comes up in the current colours
c:tab("Saves"); c.saves.refresh(); M.steps(1)
-- every BackgroundColor3 / TextColor3 under MainMenu.SavesFrame equals look:color(its key) for registered entries
-- Review Focus: runtime colours follow their setting and aren't repainted with another key
E.settings:set("classicToggleOff", "#010203"); c.saves.refresh(); M.steps(1)
-- an "off" slot button's BackgroundColor3 is 1,2,3; then E.settings:set("classicButton", "#FFFF00"): it stays 1,2,3
E.settings:set("classicSwitchOn", "#0A0B0C"); M.steps(1)
-- a switch that is on has its knob at 10,11,12; a section title follows classicSectionTitle
-- Review Focus: New and back, Unload
E.settings:set("interface", "New"); M.steps(1); E.settings:set("interface", "Classic"); M.steps(1)
eq(rgb(ui.classic.byPath.MainMenu.BackgroundColor3), rgb(ui.classic.look:color("classicWindow")), "back to Classic: still the set colours")
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** `look.lua` and the three call sites (saves: `look:own` on the slot buttons / merge stats it paints; settingsrows: `look:own` on knobs and section titles, re-show on `look:changed`).
- [ ] **Step 4: Run** `classiccolors`, `classiclook`, `classicsaves`, `classicmenu`, `classicstats` -> PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: Classic repaints in the Classic Look colours`.

### Task 4: Colour rows and the Classic picker

**Files:**
- Create: `src2/ui/classic/colorpicker.lua`
- Modify: `src2/ui/classic/settingsrows.lua` (colour rows: a swatch button left of the box; the box shows `Auto` or the hex)
- Modify: `src2/ui/classic/classic.lua` (close the picker on tab change / hide / destroy)
- Test: `tests3/test_classiccolors.lua`

**Interfaces:**
- Consumes: `Palette.hex`, `look:color`, `Settings.sanitize`.
- Produces: `ClassicPicker.open(classic, key) -> picker` (one at a time: opening another closes the first); `picker:setSV(sx, sy)` and `picker:setHue(y)` (0..1, what a drag on the square / bar calls), `picker:typed(text)` (the box), `picker:apply()`, `picker:auto()` (autocolor rows only), `picker:close()`, `picker.frame`, `picker.newColor: Color3`. Drags: InputBegan on the square / bar starts, `UserInputService.InputChanged` (mouse move / touch) follows, InputEnded stops. Esc and a click outside the picker close without applying. The picker frame is a child of `classic.gui`, ZIndex above the menu, in Classic's colours (it registers with the Look like any part).
- Row: `rows[key] = { frame, label, input, swatch }`; swatch BackgroundColor3 = `look:color(key)` (`look:own`); clicking it opens the picker.

- [ ] **Step 1: Write the failing tests**

```lua
section("colour rows and the picker")
local r = c.settingsRows.classicPanel
eq(r.input.Text, "Auto", "Auto shown")
r.input.Text = "10, 20, 30"; r.input.FocusLost:Fire(true, nil)
eq(E.settings:get("classicPanel"), "#0A141E", "typed r, g, b stored as hex"); eq(r.input.Text, "#0A141E", "shown as hex")
r.input.Text = ""; r.input.FocusLost:Fire(true, nil)
eq(E.settings:get("classicPanel"), "Auto", "an empty box = Auto")
r.swatch.MouseButton1Click:Fire()
local p = c.picker
check(p ~= nil and p.frame.Parent == c.gui, "the swatch opens the picker")
p:setHue(0); p:setSV(1, 0)
eq(Palette.hex(p.newColor), "#FF0000", "hue 0, full saturation and value = red")
p:apply()
eq(E.settings:get("classicPanel"), "#FF0000", "Apply stores it"); eq(c.picker, nil, "and closes")
c.settingsRows.classicMainColor.swatch.MouseButton1Click:Fire()
c.picker:typed("#123456"); c.picker:close()
eq(E.settings:get("classicMainColor"), "#003481", "Cancel / close changes nothing")
c.settingsRows.classicPanel.swatch.MouseButton1Click:Fire(); c.picker:auto()
eq(E.settings:get("classicPanel"), "Auto", "Auto button")
check(c.settingsRows.classicMainColor.swatch ~= nil and c.settingsRows.classicMainColor.input.Text == "#003481", "the Main Colour row has no Auto")
-- Esc closes (M.pressKey(Enum.KeyCode.Escape)); switching to the New interface closes it (no picker left in any gui)
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** the picker (square = hue colour + white-to-clear and clear-to-black UIGradients as `ui/kit/colorpicker.lua` does; hue bar = a 7-key ColorSequence; old / new preview; one box for HEX or R, G, B; Apply, Cancel, and Auto on autocolor rows) and the rows.
- [ ] **Step 4: Run** `classiccolors`, `classicmenu`, `classiclook` -> PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: Classic colour picker`.

### Task 5: The background

**Files:**
- Create: `src2/ui/classic/background.lua`
- Modify: `src2/platform/env.lua` (`Env.httpGet(url) -> (ok: boolean, body: string)`: `pcall(game.HttpGet, game, url)`; nil-safe when `game.HttpGet` is missing)
- Modify: `tests/mock/svc.lua` (`DataModel:HttpGet(url)`: `M.http[url]` = body string or `{ error = "..." }`, unknown url errors; `M.httpLog` list of urls; nothing else changes)
- Modify: `src2/ui/classic/classic.lua` (`self.background = Background.new(self)`)
- Test: `tests3/test_classicbg.lua` (`-- needs: ui`, ends with `finish()`)

**Interfaces:**
- Consumes: `Env.httpGet`, `Env.writefile`, `Env.isfile`, `Env.makefolder`, `Env.isfolder`, `Env.getcustomasset`, `look:color("classicWindow")`, `classic:status(text)`.
- Produces: `Background.new(classic)`; `bg.kind` = `nil | "image" | "video"`, `bg.view` (an `ImageLabel` named `HappaTASBackground` or a `VideoFrame` of that name) placed as a sibling right behind `MainMenu` (same Position / Size / AnchorPoint, ZIndex one lower, a UICorner like the menu's, attribute `HappaTASNoLook`), following the menu's Position / Size / Visible. While a background shows, `MainMenu.BackgroundTransparency = 1 - classicBackgroundTransparency / 100`; with none, V2's 0.2 again. Fit: Crop / Fit / Stretch = `ScaleType` Crop / Fit / Stretch (video: Fit and Crop both fill the frame; stated in the help).
- Background value rules: `""` none · `http://` or `https://` = a picture link · `rbxassetid://N` or digits only = a Roblox image · `video:N` or `video:rbxassetid://N` = a Roblox video (looped, muted). Anything else: status `Background: not a link or an id`.
- Link rules: path `HappaTasPort/Backgrounds/<8 hex digits of a djb2 hash of the link>.<png|jpg|bmp|tga>`; the extension comes from the link (query stripped) or, if none, the first bytes (`\137PNG` png, `\255\216` jpg, `BM` bmp); a link ending in `.mp4 .webm .mov .mkv .ogv .avi .m4v`, or a body starting with an MP4 `ftyp` box or the WebM magic `\26\69\223\163`, is refused with status `Roblox can't play video files from links: use a Roblox video id (video:123)`; a body under 16 bytes or starting with `<` (an HTML page) is refused `Background: the link didn't give a picture`; only a checked body is written, and an existing file is used without downloading. The download runs in `task.spawn`; a newer value cancels an older load. 10 s without `IsLoaded` -> status `Background didn't load` and the plain window.

- [ ] **Step 1: Write the failing tests** — sections and their assertions:
  - "a picture link": `M.http[url] = "\137PNG" .. string.rep("x", 64)`; set it -> `#M.httpLog == 1`, `M.fs` has `HappaTasPort/Backgrounds/<hash>.png`, `bg.view.Image == "rbxasset://custom/HappaTasPort/Backgrounds/<hash>.png"`, menu transparency `1 - 40/100`; set "" then the link again -> still 1 download (reused).
  - "fit and transparency": `classicBackgroundFit = "Stretch"` -> `ScaleType.Stretch`; transparency 75 -> menu `0.25`.
  - "Roblox ids": `"123"` -> `Image == "rbxassetid://123"`, no download; `"video:456"` -> a `VideoFrame`, `Video == "rbxassetid://456"`, `Looped`, `Volume == 0`.
  - "Review Focus: bad links": an html body, a 0-byte body, an `{ error = "HTTP 404" }`, a `.mp4` link (no download), an `ftyp` body -> no file written, `bg.kind == nil`, menu transparency 0.2, a status line each.
  - "without the functions": `HttpGet` missing (mock flag `M.noHttpGet`) -> status, an id still works.
  - "follows the menu": moving `MainMenu.Position` moves the view; `MainMenu.Visible = false` hides it.
  - "Review Focus: New and Unload": switching to New hides it with Classic; Unload leaves no `HappaTASBackground` anywhere.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** the Env helper, the mock, `background.lua`.
- [ ] **Step 4: Run** `classicbg`, `classiccolors`, `classiclook`, `smoke` -> PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: Classic background picture or Roblox video`.

### Task 6: Docs, release, gate, live check

**Files:**
- Modify: `src2/ui/win/helptext.lua` (a "Classic Look" topic: Main Colour and Auto, typing colours, the picker, Background values, the video limit), `README.md` (Classic section + settings table), the spec's colour table (23 colours + the final key names), `wow` (`bash tools/release3.sh`, then `git restore wow1`).
- Local only: CLAUDE.md conventions line "No network code anywhere" -> the one exception.

- [ ] **Step 1:** Docs as listed; `python3 tools/check_readme3.py` -> OK.
- [ ] **Step 2:** `timeout 3600 bash tools/test_all3.sh` in the background, alone -> `ALL PASSED`, traces SAME, `BENCH OK`.
- [ ] **Step 3:** Live (Real MCP): Classic with the Main Colour red and one typed colour, the picker, a picture link downloaded once and reused after a reload, a Roblox image id, a Roblox video id, the New interface's Settings window unchanged; restore Settings3.json / place files byte-identical, delete the test files and `HappaTasPort/Backgrounds` test pictures, FPS cap as found.
- [ ] **Step 4: Commit** `HappaTAS 3: help, README and spec for Classic Look; wow`.
