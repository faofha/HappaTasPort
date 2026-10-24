-- ================================================================================================
-- HappaTAS 3, phase 2: merging two runs, and the plugin registry's hook names
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local UIS = M.services.UserInputService
local tl = E.tl
local MG = E.mergeRun
local statuses = {}
E.bus:on("status", function(t) statuses[#statuses + 1] = t end)
local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
local function click()
	UIS.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	UIS.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
end
local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[k] = deepCopy(v) end
	return c
end
local function hitboxes()
	local n = 0
	for _, ch in ipairs(workspace.CurrentCamera:GetChildren()) do
		if ch.Name == "startHitbox" or ch.Name == "endHitbox" then n = n + 1 end
	end
	return n
end

section("no plugin method uses a registry hook's name")
do
	local expected = { begin = { character = true, camera = true, inputs = true }, fill = { character = true, animation = true, tools = true },
		attach = { animation = true, tools = true }, lateRender = {} }
	local ok, bad = true, ""
	for _, p in ipairs(E.plugins.list) do
		for hook, owners in pairs(expected) do
			if type(p[hook]) == "function" and not owners[p.name] then ok = false; bad = bad .. p.name .. "." .. hook .. " " end
		end
	end
	check(ok, "begin / fill / attach only where meant (" .. bad .. ")")
end

-- record a run: 10 frames moving +x, W held from frame 3
local function record(n, vx, perFrame)
	click()
	for f = 1, n + 1 do
		E.char.hrp.AssemblyLinearVelocity = Vector3.new(vx, 0, 0)
		if perFrame then perFrame(f) end
		M.step(1 / 60)
	end
	click()
	M.steps(2)
end
key(Enum.KeyCode.Two)
M.steps(2)
record(10, 30, function(f) if f == 4 then M.pressKey(Enum.KeyCode.W) end end)
local runA = tl:toV2All()
eq(#runA, 10, "run A: 10 frames")

section("merge after: the run before keeps its last frame as the start; the keys it held carry on")
key(Enum.KeyCode.One)
M.steps(2)
-- run B starts 1 stud away from where A ends
local endA = runA[#runA].Cframe
local runB = deepCopy(runA)
for i, fr in ipairs(runB) do fr.Cframe[1] = endA[1] + 1 + i * 0.1 end
check(MG:startMerge(deepCopy(runB), "after"), "merge started")
eq(E.merge, true, "merging")
eq(E.mode, 2, "Create")
eq(tl:count(), 1, "the run has the before-run's last frame")
eq(hitboxes(), 2, "two hitboxes")
check(E.mergeBaseHeld[23], "W (held at the end of run A) is the recording's base")
M.releaseKey(Enum.KeyCode.W)
key(Enum.KeyCode.One)
eq(E.mode, 2, "Idle is blocked while merging")
-- record towards run B's start
local goal = Vector3.new(runB[1].Cframe[1], runB[1].Cframe[2], runB[1].Cframe[3])
click()
for _ = 1, 8 do
	E.char.hrp.AssemblyLinearVelocity = Vector3.zero
	E.char.hrp.CFrame = CFrame.new(E.char.hrp.Position:Lerp(goal, 0.5))
	M.step(1 / 60)
end
click()
M.steps(3)
check(E.mergeCanComplete, "close enough to complete (" .. tostring(E.mergeDistance) .. ")")
local recorded = tl:toV2All()
MG:finishMerge()
eq(statuses[#statuses], "Merge Complete", "completed")
eq(E.merge, false, "not merging")
eq(E.mode, 1, "Idle")
eq(hitboxes(), 0, "hitboxes gone")
eq(tl:count(), #runA - 1 + #recorded + #runB, "A (without its last) + the recording + B")
-- V2's retiming: from frame max(2, #A) on, TotalTime = the sum of FrameTimes
local ok = true
for i = #runA, tl:count() do
	local want = math.round((tl:get("FrameTime", i, 1) + tl:get("TotalTime", i - 1, 1)) * 1e6) / 1e6
	if tl:get("TotalTime", i, 1) ~= want then ok = false end
end
check(ok, "times summed again from where they join")
eq(tl:get("Cframe", tl:count(), 1), runB[#runB].Cframe[1], "ends on run B's last frame")

section("merge before, then cancel: the old run comes back")
local runC = tl:toV2All()
local n0 = #runC
check(MG:startMerge(deepCopy(runA), "before"), "merge started")
eq(tl:count(), 1, "run A's last frame")
MG:finishMerge() -- (too far: cancels)
eq(statuses[#statuses], "Merge Cancelled", "cancelled")
eq(tl:count(), n0, "the old run is back")
eq(hitboxes(), 0, "hitboxes gone")

section("an empty run can't be merged")
eq(MG:startMerge({}, "after"), false, "refused")
eq(statuses[#statuses], "Cannot merge: one of the TAS runs is empty", "status")
eq(E.merge, false, "not merging")
finish()
