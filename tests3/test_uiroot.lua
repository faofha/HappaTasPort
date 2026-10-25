-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5a: the interface's root (where its ScreenGui goes, V2's rules), changed-only writes,
-- its own pointer (click = release within 3 px, a press keeps its rect), the Menu key, Unload
-- (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local W = __T3("ui/write")
local Root = __T3("ui/root")
local Pointer = __T3("ui/pointer")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local function all(name)
	local out = {}
	for _, root in ipairs({ CoreGui, Players.LocalPlayer:FindFirstChildOfClass("PlayerGui") }) do
		for _, d in ipairs(root:GetDescendants()) do if d:IsA("ScreenGui") and d.Name == name then out[#out + 1] = d end end
	end
	return out
end

section("the interface is started with the engine")
local ui = E.ui
check(ui ~= nil and ui.root ~= nil and ui.pointer ~= nil, "E.ui with a root and a pointer")
local gui = ui.root.gui
eq(gui.Name, "TASUserInterface", "its name")
eq(gui.Parent, gethui(), "under gethui()")
eq(ui.root.parentName, "gethui", "parentName")
eq(gui.ResetOnSpawn, false, "ResetOnSpawn off")
eq(gui.IgnoreGuiInset, true, "IgnoreGuiInset")
eq(gui.AutoLocalize, false, "AutoLocalize off (texts cost ~30x more with it)")
eq(gui.DisplayOrder, 10, "DisplayOrder 10")
eq(#all("TASUserInterface"), 1, "one interface")

section("W.set writes only changes")
do
	local f = Instance.new("Frame")
	local w0 = M.propWrites
	eq(W.set(f, "BackgroundTransparency", 0.5), true, "first write")
	eq(W.set(f, "BackgroundTransparency", 0.5), false, "the same value: no write")
	eq(W.set(f, "Size", UDim2.new(0, 10, 0, 10)), true, "another property")
	eq(W.set(f, "Size", UDim2.new(0, 10, 0, 10)), false, "an equal UDim2: no write")
	eq(M.propWrites - w0, 2, "two property writes in the engine")
end

section("the pointer: hover, click, press capture")
local layer = ui.root.layer
local a = Instance.new("Frame"); a.Name = "A"; a.Position = UDim2.new(0, 100, 0, 100); a.Size = UDim2.new(0, 100, 0, 50); a.Parent = layer
local b = Instance.new("Frame"); b.Name = "B"; b.Position = UDim2.new(0, 150, 0, 120); b.Size = UDim2.new(0, 100, 0, 50); b.Parent = layer
local log = {}
local function rect(gui, name, z)
	return { gui = gui, z = z,
		onHover = function(on) log[#log + 1] = name .. (on and ":in" or ":out") end,
		onPress = function() log[#log + 1] = name .. ":press" end,
		onRelease = function(_, clicked) log[#log + 1] = name .. (clicked and ":click" or ":release") end,
		onDrag = function(_, d) log[#log + 1] = name .. ":drag" end,
		onWheel = function(z2) log[#log + 1] = name .. ":wheel" .. z2 end }
end
local ra, rb = rect(a, "A", 1), rect(b, "B", 2)
ui.pointer:add(ra)
ui.pointer:add(rb)
UIH.move(Vector2.new(120, 110))
eq(table.concat(log, ","), "A:in", "hover A")
log = {}
UIH.move(Vector2.new(170, 130))
eq(table.concat(log, ","), "A:out,B:in", "B is on top (higher z) where they overlap")
log = {}
UIH.click(Vector2.new(170, 130))
eq(table.concat(log, ","), "B:press,B:click", "click on B")
log = {}
UIH.press(Vector2.new(170, 130))
UIH.release(Vector2.new(174, 130))
eq(table.concat(log, ","), "B:press,B:drag,B:release", "4 px away: a release, not a click (V2.36: within 3 px)")
UIH.move(Vector2.new(120, 110))
log = {}
UIH.press(Vector2.new(120, 110))
UIH.move(Vector2.new(600, 600))
UIH.release(Vector2.new(600, 600))
local joined = table.concat(log, ",")
check(log[1] == "A:press" and joined:find("A:release", 1, true) ~= nil and joined:find("click", 1, true) == nil,
	"a press keeps its rect: the release outside goes to A, not a click (" .. joined .. ")")
log = {}
UIH.wheel(Vector2.new(120, 110), 1)
check(table.concat(log, ","):find("A:wheel1", 1, true) ~= nil, "wheel over A")
a.Visible = false
log = {}
UIH.click(Vector2.new(120, 110))
local hit = table.concat(log, ","):find("press", 1, true)
eq(hit, nil, "a hidden rect isn't hit (" .. table.concat(log, ",") .. ")")
a.Visible = true

section("a click on the interface never reaches the engine (Review Focus 2)")
E.modes:request("create")
M.steps(3)
check(E.mode == 2 and E.paused, "Create, paused")
UIH.click(Vector2.new(120, 110))
M.steps(3)
eq(E.paused, true, "a click on a rect doesn't Unpause")
UIH.click(Vector2.new(700, 500))
M.steps(3)
eq(E.paused, false, "a click on the game does")
UIH.press(Vector2.new(120, 110))
UIH.move(Vector2.new(700, 500))
M.mouseUp(1, false)
M.steps(3)
eq(E.paused, false, "a press on the interface released over the game: nothing for the engine")
E.modes:request("pause")
M.steps(3)
E.modes:request("idle")
M.steps(3)

section("the Menu key")
eq(ui.shown, true, "shown at start")
UIH.key(Enum.KeyCode.M)
eq(ui.shown, false, "M hides the interface")
eq(gui.Enabled, false, "the ScreenGui off")
E.settings:set("ignoreGameProcessed", 0)
M.pressKey(Enum.KeyCode.M, true)
M.releaseKey(Enum.KeyCode.M, true)
eq(ui.shown, true, "M works even when the game took the key and Ignore Game Processed is off")
local box = Instance.new("TextBox"); box.Parent = layer
M.steps(1)
box:CaptureFocus()
UIH.key(Enum.KeyCode.M)
eq(ui.shown, true, "typing in one of the interface's boxes: M types (Review Focus 1)")
box:ReleaseFocus()
check(E.typing:active(nil) == false, "not typing after the box lost focus")

section("Interface scale")
local scale = layer:FindFirstChildOfClass("UIScale")
check(scale ~= nil, "a UIScale on the layer")
near(scale.Scale, 1, 1e-9, "100 %")
E.settings:set("interfaceScale", 150)
near(scale.Scale, 1.5, 1e-9, "150 %")
E.settings:set("interfaceScale", 100)

-- (each Root.new removes the interface above as a stale copy: these come last)
section("where the root goes without gethui / CoreGui (V2's rules)")
do
	M.noHui = true
	local r1 = Root.new(E)
	eq(r1.parentName, "CoreGui", "no gethui: CoreGui")
	eq(r1.gui.Parent, CoreGui, "parented to CoreGui")
	r1:destroy()
	M.coreGuiLocked = true
	E.settings:set("allowPlayerGuiInterface", 0)
	local r2 = Root.new(E)
	eq(r2.refused, true, "neither and the setting off: refused")
	eq(r2.gui.Parent, nil, "not parented anywhere")
	r2:destroy()
	E.settings:set("allowPlayerGuiInterface", 1)
	local r3 = Root.new(E)
	eq(r3.parentName, "PlayerGui", "with the setting on: PlayerGui")
	check(r3.gui.Name ~= "TASUserInterface" and #r3.gui.Name == 12, "not an obvious name there (" .. r3.gui.Name .. ")")
	r3:destroy()
	E.settings:set("allowPlayerGuiInterface", 0)
	M.noHui, M.coreGuiLocked = false, false
end

section("a stale TASUserInterface (an older copy's) is removed")
do
	local stale = Instance.new("ScreenGui")
	stale.Name = "TASUserInterface"
	stale.Parent = gethui()
	local r = Root.new(E)
	check(stale.Parent == nil, "the stale one is gone")
	r:destroy()
end

section("Unload leaves nothing")
getgenv().__HappaTAS3.Unload()
M.steps(2)
eq(#all("TASUserInterface"), 0, "no TASUserInterface anywhere")
eq(gui.Parent, nil, "the root destroyed")
log = {}
UIH.click(Vector2.new(120, 110))
eq(#log, 0, "the pointer listens to nothing any more")
finish()
