-- ================================================================================================
-- HappaTAS 3, phase 2: the tools plugin (tool events recorded per frame; state-based replay)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local UIS = M.services.UserInputService
local tl = E.tl
local T = E.tools
local bp = M.player:FindFirstChildOfClass("Backpack")
local sword = Instance.new("Tool"); sword.Name = "Sword"; sword.Parent = bp
local handle = Instance.new("Part"); handle.Name = "Handle"; handle.Parent = sword
M.steps(2)
local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
local function click()
	UIS.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	UIS.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
end
local function equipped()
	local t = M.player.Character:FindFirstChildOfClass("Tool")
	return t and t.Name or false
end
local function eventsOf(i)
	local out = {}
	for _, e in ipairs(tl:getList("Tools", i) or {}) do out[#out + 1] = e.Action .. ":" .. e.Name end
	return table.concat(out, ",")
end

section("recording: equip, activate, deactivate, unequip on their frames")
key(Enum.KeyCode.Two)
M.steps(2)
click()
M.steps(3)
local hum = E.char.hum
hum:EquipTool(sword)
M.step(1 / 60)
local fEquip = tl:count()
sword:Activate()
sword:Deactivate()
M.step(1 / 60)
local fAct = tl:count()
M.steps(3)
hum:UnequipTools()
M.step(1 / 60)
local fUnequip = tl:count()
M.steps(10)
click()
M.steps(2)
eq(eventsOf(fEquip), "Equip:Sword", "equip on its frame")
eq(eventsOf(fAct), "Activate:Sword,Deactivate:Sword", "activate and deactivate")
eq(eventsOf(fUnequip), "Unequip:Sword", "unequip")
eq(eventsOf(fEquip - 1), "", "nothing on the frame before")

section("replay: a tool the replay didn't equip is equipped after 4 frames, not before")
key(Enum.KeyCode.One)
M.steps(2)
hum:UnequipTools()
key(Enum.KeyCode.Three)
local fixedAt
local g = 0
while E.mode == 3 and g < 300 do
	M.step(1 / 60)
	g = g + 1
	if not fixedAt and equipped() == "Sword" then fixedAt = E.frame end
	if E.frame > fUnequip - 1 then break end
end
check(fixedAt ~= nil, "equipped by HappaTAS")
check(fixedAt and fixedAt >= fEquip + 3, "only after 4 frames of mismatch (frame " .. tostring(fixedAt) .. ", equip frame " .. fEquip .. ")")
g = 0
while E.mode == 3 and g < 300 do M.step(1 / 60); g = g + 1 end
eq(equipped(), false, "unequipped again after its unequip frame")

section("no double toggle: a tool the key replay equipped is left alone")
key(Enum.KeyCode.Three)
local toggles = 0
local conn = M.player.Character.ChildAdded:Connect(function(ch) if ch:IsA("Tool") then toggles = toggles + 1 end end)
g = 0
while E.mode == 3 and g < 300 do
	if E.frame == fEquip and equipped() == false then hum:EquipTool(sword) end -- (as the replayed key would)
	M.step(1 / 60)
	g = g + 1
end
conn:Disconnect()
eq(toggles, 1, "equipped once")

section("Record Tool Actions off: nothing recorded")
E.settings:set("recordTools", 0)
key(Enum.KeyCode.Two)
M.steps(2)
click()
M.steps(2)
local n0 = tl:count()
hum:EquipTool(sword)
M.steps(2)
hum:UnequipTools()
M.steps(2)
click()
M.steps(2)
local any = false
for i = n0, tl:count() do if tl:getList("Tools", i) then any = true end end
check(not any, "no tool events")
E.settings:set("recordTools", 1)
finish()
