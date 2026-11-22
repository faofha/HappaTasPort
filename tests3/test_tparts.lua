-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1 Tasability (Task 2): the Tasability parts: checkbox, value box, dropdown, colour box, button,
-- key box, slider (square, compact shades, accent) (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local th = ui.theme
local P = __T3("ui/compact/parts")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
th:setCompact(true)
local holder = Instance.new("Frame")
holder.BackgroundTransparency = 1
holder.Position = UDim2.new(0, 200, 0, 150)
holder.Size = UDim2.new(0, 300, 0, 400)
holder.Parent = ui.root.layer
local ctx = { E = E, ui = ui, theme = th, tween = ui.tween, typing = E.typing,
	pointer = { add = function(r, z) r.z = 50 + (z or 0); ui.pointer:add(r); return r end, remove = function(r) ui.pointer:remove(r) end } }
local listeners0 = #th.listeners
local function place(p, y) p.gui.Position = UDim2.new(0, 0, 0, y) end
local function rounded(gui)
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("UICorner") and (d.CornerRadius.Offset > 0 or d.CornerRadius.Scale > 0) then return true end
	end
	return false
end
local function popovers()
	local n = 0
	for _, d in ipairs(ui.root.layer:GetDescendants()) do if d.Name == "Popover" then n = n + 1 end end
	return n
end
local parts = {}

section("checkbox")
local changes = {}
local cb = P.checkbox(ctx, holder, "Replay Keyboard", { onChange = function(v) changes[#changes + 1] = v end })
place(cb, 0)
parts[#parts + 1] = cb
eq(cb.box.Size, UDim2.new(0, 12, 0, 12), "a 12 x 12 box")
eq(cb.gui.Size.Y.Offset, 18, "18 high")
eq(cb.tick.Visible, false, "off: no tick")
UIH.click(cb.gui)
eq(cb.value, true, "a click ticks it")
eq(changes[1], true, "and reports it")
eq(cb.tick.Visible, true, "the tick shows")
eq(cb.tick.Size, UDim2.new(0, 6, 0, 6), "a 6 x 6 tick")
eq(cb.tick.BackgroundColor3, th.c.accent, "in the accent")
eq(cb.box.BackgroundColor3, th.c.accent:Lerp(th.shades.deep, 0.7), "the box: a dim accent")
cb:set(false)
eq(cb.tick.Visible, false, "set(false) clears it")
eq(#changes, 1, "set doesn't report")

section("value box")
local stored, commits = "13", 0
local vb = P.valueBox(ctx, holder, "Text size", { current = function() return stored end,
	commit = function(t) if tonumber(t) then commits = commits + 1; stored = t; return true end return false end })
place(vb, 30)
parts[#parts + 1] = vb
vb:set(stored)
eq(vb.gui.Size.Y.Offset, 22, "22 high")
eq(vb.label.TextColor3, th.c.text2, "a dim label")
UIH.click(vb.box)
M.steps(1)
eq(vb.box:IsFocused(), true, "a click on the box focuses it (live: the pointer sits over Roblox's own text box)")
vb.box:ReleaseFocus()
M.steps(1)
commits = 0 -- (leaving the box commits what it shows: the same 13)
UIH.typeInto(vb.box, "abc", true)
eq(vb.box.Text, "13", "refused: the stored value again")
eq(commits, 0, "nothing committed")
UIH.typeInto(vb.box, "15", true)
eq(commits, 1, "a good value commits once")

section("dropdown")
local picked = {}
local dd = P.dropdown(ctx, holder, "Interface", { "New", "Classic", "Tasability" }, { onChange = function(v) picked[#picked + 1] = v end })
place(dd, 60)
parts[#parts + 1] = dd
dd:set("New")
check(UIH.find(dd.button, "New") ~= nil, "shows its value")
check(UIH.find(dd.gui, "▼") ~= nil, "a ▼")
UIH.click(dd.button)
M.steps(1)
check(dd.list ~= nil, "a click opens the list")
local item = UIH.find(dd.list, "Classic")
check(item ~= nil and item.Parent.Size.Y.Offset == 20 or (item and item.Size.Y.Offset == 20), "items 20 high")
UIH.click(item.Parent:IsA("Frame") and item.Parent.Name == "Item" and item.Parent or item)
M.steps(1)
eq(dd.value, "Classic", "picked")
eq(picked[1], "Classic", "reported")
eq(dd.list, nil, "closed")
UIH.click(dd.button)
M.steps(1)
UIH.key(Enum.KeyCode.Escape)
M.steps(1)
eq(dd.list, nil, "Esc closes it")
UIH.click(dd.button)
M.steps(1)
dd:close()
M.steps(1)
eq(popovers(), 0, "close() leaves no popover (Review Focus 5)")

section("colour box")
local hex, applied = "#3FB950", {}
local co = P.colorBox(ctx, holder, "Accent colour", { value = function() return hex end, default = "#3FB950",
	onPreview = function(h) hex = h end, onApply = function(h) hex = h; applied[#applied + 1] = h end })
place(co, 90)
parts[#parts + 1] = co
co:set(hex)
eq(co.swatch.BackgroundColor3, Color3.fromHex("3FB950"), "the swatch shows the colour")
eq(co.swatch.Size, UDim2.new(0, 14, 0, 12), "14 x 12")
UIH.typeInto(co.box, "10, 20, 30", true)
eq(applied[#applied], "#0A141E", "r, g, b typed: applied as hex")
UIH.click(co.swatch)
M.steps(1)
eq(popovers(), 1, "the swatch opens the picker")
UIH.key(Enum.KeyCode.Escape)
M.steps(1)

section("button")
local clicks = 0
local bt = P.button(ctx, holder, "Reset all", { onClick = function() clicks = clicks + 1 end })
place(bt, 120)
parts[#parts + 1] = bt
eq(bt.gui.Size.Y.Offset, 22, "22 high")
UIH.click(bt.gui)
eq(clicks, 1, "a click")

section("key box")
local kclicks, cleared = 0, 0
local kb = P.keyBox(ctx, holder, "Back", { onClick = function() kclicks = kclicks + 1 end, onClear = function() cleared = cleared + 1 end })
place(kb, 150)
parts[#parts + 1] = kb
kb:set("R")
eq(kb.key.Text, "R", "the key")
eq(kb.key.TextColor3, th.c.accent, "in the accent")
kb:setWaiting(true)
eq(kb.key.Text, "...", "waiting: ...")
eq(kb.key.TextColor3, Color3.fromHex("DCC83C"), "in yellow")
kb:setWaiting(false)
eq(kb.key.Text, "R", "the key again")
UIH.click(kb.clear.gui)
eq(cleared, 1, "the × clears")
eq(kclicks, 0, "without starting a wait")
UIH.click(kb.gui.AbsolutePosition + Vector2.new(10, 11))
eq(kclicks, 1, "a click on the row starts a wait")
kb:setConflict(true)
eq(kb.insetStroke.Color, th.c.rec, "a conflict: the inset outline in the recording colour")
kb:setConflict(false)

section("slider")
local sl = P.slider(ctx, holder, { min = 0.1, max = 1, fmt = function(v) return string.format("%.2fx", v) end })
place(sl, 180)
parts[#parts + 1] = sl
sl:set(0.5)
eq(sl.valueLabel.Text, "0.50x", "the value, formatted")
UIH.click(sl.valueLabel)
M.steps(1)
eq(sl.valueLabel:IsFocused(), true, "a click on the value edits it")
sl.valueLabel:ReleaseFocus()
M.steps(1)
eq(sl.track.Size.Y.Offset, 6, "a 6-high track")
eq(sl.knob.Size, UDim2.new(0, 10, 0, 10), "a 10 x 10 knob")
local got
sl.onChange = function(v) got = v end
UIH.click(sl.track.AbsolutePosition + Vector2.new(sl.track.AbsoluteSize.X / 2, 3))
near(got, 0.55, 0.01, "the middle: 0.55")

section("the look")
for _, p in ipairs(parts) do check(not rounded(p.gui), "square: " .. p.gui.Name) end
E.settings:set("secondaryTextColor", "#808080")
eq(vb.label.TextColor3, Color3.fromHex("808080"), "labels follow the secondary text colour")
E.settings:set("secondaryTextColor", "#B4BBC8")

section("destroy")
for _, p in ipairs(parts) do p:destroy() end
eq(#th.listeners, listeners0, "no theme listener left")
th:setCompact(false)
holder:Destroy()
finish()
