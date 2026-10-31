-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5a: the interface's controls (button, toggle, slider with a typeable value, segmented,
-- field, row) in a window: clicks, drags, typed values (Review Focus 5), set() without events, the row's
-- layout, destroy (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local ui = E.ui
local wm = ui.wm
local Button = __T3("ui/kit/button")
local Toggle = __T3("ui/kit/toggle")
local Slider = __T3("ui/kit/slider")
local Segmented = __T3("ui/kit/segmented")
local Field = __T3("ui/kit/field")
local Row = __T3("ui/kit/row")
local win
wm:define("kit", { title = "Kit", w = 500, h = 600, minW = 300, minH = 200, build = function(body, w) win = w end })
wm:open("kit")
check(win ~= nil and win.ctx ~= nil, "the window has a ctx for its controls")
local ctx, body = win.ctx, win.body
local function holder(y, h)
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Position = UDim2.new(0, 0, 0, y)
	f.Size = UDim2.new(1, 0, 0, h or 40)
	f.Parent = body
	return f
end

section("button")
local clicks = 0
local btn = Button.new(ctx, holder(0), { text = "Apply", kind = "primary" })
btn.onClick = function() clicks = clicks + 1 end
UIH.click(btn.gui)
eq(clicks, 1, "a click")
UIH.press(UIH.center(btn.gui))
UIH.release(UIH.center(btn.gui) + Vector2.new(0, 200))
eq(clicks, 1, "a press released elsewhere isn't a click")
local reset = Button.new(ctx, holder(40), { kind = "reset" })
eq(reset.gui.Size, UDim2.new(0, 24, 0, 24), "the reset button is 24 px")

section("toggle")
local tg = Toggle.new(ctx, holder(80))
local got = {}
tg.onChange = function(v) got[#got + 1] = tostring(v) end
eq(tg.gui.Size, UDim2.new(0, 44, 0, 26), "44 x 26")
tg:set(false)
UIH.click(tg.gui)
eq(table.concat(got, ","), "true", "a click turns it on and reports")
eq(tg.value, true, "its value")
UIH.click(tg.gui)
eq(table.concat(got, ","), "true,false", "and off")
tg:set(true)
eq(#got, 2, "set() doesn't report")
eq(tg.value, true, "set() shows the value")

section("slider: drag, track click, steps")
local sl = Slider.new(ctx, holder(120), { min = 0, max = 200, step = 1, fmt = function(v) return v .. "%" end })
local sv = {}
sl.onChange = function(v) sv[#sv + 1] = v end
sl:set(100)
eq(sl.label.Text, "100%", "the value shown with its format")
local tr = sl.track
local x0, w = tr.AbsolutePosition.X, tr.AbsoluteSize.X
local cy = tr.AbsolutePosition.Y + tr.AbsoluteSize.Y / 2
UIH.click(Vector2.new(x0 + w * 0.25, cy))
eq(sl.value, 50, "a click on the track at a quarter: 50")
UIH.drag(Vector2.new(x0 + w * 0.25, cy), Vector2.new(x0 + w * 0.755, cy))
eq(sl.value, 151, "dragged to ~75.5 %: 151 (step 1)")
UIH.drag(Vector2.new(x0 + w * 0.5, cy), Vector2.new(x0 - 500, cy))
eq(sl.value, 0, "past the left end: the minimum")
eq(sv[#sv], 0, "reported")
local stepped = Slider.new(ctx, holder(160), { min = 0.05, max = 1, step = 0.05 })
stepped:set(0.2)
UIH.click(Vector2.new(stepped.track.AbsolutePosition.X + stepped.track.AbsoluteSize.X * 0.51, stepped.track.AbsolutePosition.Y + 2))
near(stepped.value, 0.55, 1e-9, "rounded to the step (0.05)")

section("slider: the typed value (Review Focus 5)")
sl:set(100)
sv = {}
UIH.click(sl.label)
local box = sl.box
check(box ~= nil and box.Visible, "clicking the number makes it typeable")
UIH.typeInto(box, "abc", true)
eq(sl.value, 100, "letters refused")
eq(sl.label.Text, "100%", "the label shows the stored value again")
UIH.click(sl.label)
UIH.typeInto(sl.box, "250", true)
eq(sl.value, 200, "250 for 0-200: clamped to 200")
UIH.click(sl.label)
UIH.typeInto(sl.box, "", true)
eq(sl.value, 200, "empty: unchanged")
UIH.click(sl.label)
UIH.typeInto(sl.box, "nan", true)
eq(sl.value, 200, "nan refused")
UIH.click(sl.label)
UIH.typeInto(sl.box, "42", false)
eq(sl.value, 42, "focus lost (not Enter) applies too")
UIH.click(sl.label)
sl.box:CaptureFocus()
sl.box.Text = "77"
M.pressKey(Enum.KeyCode.Escape)
M.releaseKey(Enum.KeyCode.Escape)
eq(sl.value, 42, "Esc: unchanged")
eq(sl.box.Visible, false, "Esc: back to the number")
-- (review: Roblox may drop the focus before InputBegan sees Esc; FocusLost's second argument says it was Esc)
local ESC = { KeyCode = Enum.KeyCode.Escape, UserInputType = Enum.UserInputType.Keyboard }
UIH.click(sl.label)
sl.box:CaptureFocus()
sl.box.Text = "88"
M.focusedBox = nil
sl.box.FocusLost:Fire(false, ESC)
eq(sl.value, 42, "Esc that ended the focus: the slider keeps its value")
eq(E.mode, 1, "typing never ran a control")
local custom = Slider.new(ctx, holder(200), { min = 0, max = 10, sanitize = function(v) local n = tonumber(v); if n and n % 2 == 0 then return n end return nil end })
custom:set(4)
UIH.click(custom.label)
UIH.typeInto(custom.box, "3", true)
eq(custom.value, 4, "the owner's sanitize refuses 3")
UIH.click(custom.label)
UIH.typeInto(custom.box, "6", true)
eq(custom.value, 6, "and takes 6")

section("segmented")
local sg = Segmented.new(ctx, holder(240), { options = { "Clear", "Tint", "Frost" } })
local sgv = {}
sg.onChange = function(v) sgv[#sgv + 1] = v end
sg:set("Tint")
local bubbleX = sg.bubble.Position.X.Offset
UIH.click(sg.segments[3])
eq(table.concat(sgv, ","), "Frost", "a click on Frost")
eq(sg.value, "Frost", "its value")
ui.tween:finishAll()
check(sg.bubble.Position.X.Offset > bubbleX, "the bubble moved right")
sg:set("Clear")
eq(#sgv, 1, "set() doesn't report")

section("field: commit on Enter and on focus lost")
local commits = {}
local fd = Field.new(ctx, holder(280), { placeholder = "Name", w = 160, onCommit = function(t) commits[#commits + 1] = t; return t ~= "bad" end })
UIH.typeInto(fd.box, "Night", true)
eq(commits[1], "Night", "Enter commits")
UIH.typeInto(fd.box, "Day", false)
eq(commits[2], "Day", "focus lost commits")
fd:set("Kept")
UIH.typeInto(fd.box, "bad", true)
eq(fd.box.Text, "Kept", "a refused commit shows the old text again")
local nc = #commits
fd.box:CaptureFocus()
fd.box.Text = "Typo"
M.focusedBox = nil
fd.box.FocusLost:Fire(false, ESC)
eq(#commits, nc, "Esc that ended the focus: no commit")
eq(fd.box.Text, "Kept", "and the old text back")
local search = Field.new(ctx, holder(320), { placeholder = "Search settings", search = true, w = 300 })
eq(search.gui.Size.Y.Offset, 32, "the search box is 32 px high")
eq(search.box.TextYAlignment, Enum.TextYAlignment.Center, "its text vertically centred")
check(search.icon ~= nil and search.icon.Position.X.Scale == 1, "the magnifier on the right")
local typed = {}
search.onInput = function(t) typed[#typed + 1] = t end
search.box.Text = "fra"
eq(typed[#typed], "fra", "onInput as you type")

section("row layout")
local rowHolder = holder(360, 44)
local rtg = Toggle.new(ctx, nil)
local row = Row.new(ctx, rowHolder, { name = "Shadows", desc = "Soft shadows under the windows", control = rtg })
local rw = row.gui.AbsoluteSize.X
local ctlRight = rtg.gui.AbsolutePosition.X + rtg.gui.AbsoluteSize.X - row.gui.AbsolutePosition.X
eq(ctlRight, rw - 18, "the control's right edge 18 px from the row's")
row:setReset(true)
local resetRight = row.reset.gui.AbsolutePosition.X + row.reset.gui.AbsoluteSize.X
eq(resetRight, rtg.gui.AbsolutePosition.X - 7, "the reset button just left of the control (7 px)")
row:setReset(false)
eq(row.reset.gui.Visible, false, "hidden when the value is the default")
local resets = 0
row.onReset = function() resets = resets + 1 end
row:setReset(true)
UIH.click(row.reset.gui)
eq(resets, 1, "the reset button reports")
check(UIH.find(row.gui, "Shadows") and UIH.find(row.gui, "Soft shadows under the windows"), "name and desc shown")

section("destroy removes the controls' rects")
local before = #ui.pointer.rects
tg:destroy()
sl:destroy()
check(#ui.pointer.rects < before, "fewer rects (" .. before .. " -> " .. #ui.pointer.rects .. ")")
got = {}
eq(tg.gui.Parent, nil, "the toggle gone")

section("controls over the game: the engine never sees their clicks")
E.modes:request("create")
M.steps(3)
UIH.click(btn.gui)
M.steps(3)
eq(E.paused, true, "a button click doesn't Unpause")
E.modes:request("idle")
M.steps(3)
finish()
