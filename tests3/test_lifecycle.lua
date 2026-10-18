-- ================================================================================================
-- HappaTAS 3, phase 1: lifecycle (everything HappaTAS owns is undone on Unload) and error reporting
-- ================================================================================================
check(boot(3), "boots")
local Lifecycle = __T3("kernel/lifecycle")
local Errors = __T3("kernel/errors")

section("cleanup undoes everything, newest first")
do
	local life = Lifecycle.new()
	local order = {}
	life:own(function() order[#order + 1] = "1" end)
	life:own(function() order[#order + 1] = "2" end)
	life:own(function() order[#order + 1] = "3" end)
	local ev = M.newSignal("test")
	local fired = 0
	local c = life:connect(ev, function() fired = fired + 1 end)
	local part = Instance.new("Part")
	part.Parent = workspace
	eq(life:own(part), part, "own returns what it got")
	life:cleanup()
	eq(table.concat(order, ","), "3,2,1", "functions run newest first")
	check(not c.Connected, "the connection is disconnected")
	ev:Fire()
	eq(fired, 0, "a disconnected handler isn't called")
	eq(part.Parent, nil, "the instance is destroyed")
	check(life.unloading, "unloading is set")
	life:cleanup()
	eq(table.concat(order, ","), "3,2,1", "cleanup twice runs nothing again")
end

section("one failing step doesn't stop the others")
do
	local life = Lifecycle.new()
	local ran = false
	life:own(function() ran = true end)
	life:own(function() error("broken cleanup") end)
	life:cleanup()
	check(ran, "the step before the failing one still ran")
end

section("property changes are put back")
do
	local life = Lifecycle.new()
	local part = Instance.new("Part")
	part.Transparency = 0
	part.Parent = workspace
	life:setProp(part, "Transparency", 0.5)
	eq(part.Transparency, 0.5, "setProp writes")
	life:setProp(part, "Transparency", 0.7)
	life:cleanup()
	eq(part.Transparency, 0, "cleanup restores the value from before HappaTAS's first write")

	local life2 = Lifecycle.new()
	local part2 = Instance.new("Part")
	part2.Transparency = 0
	life2:setProp(part2, "Transparency", 0.5)
	part2.Transparency = 0.8 -- (the game wrote its own value since)
	life2:cleanup()
	eq(part2.Transparency, 0.8, "a value the game wrote since is kept")
end

section("scopes: one module's things can be undone on their own")
do
	local life = Lifecycle.new()
	local order = {}
	life:own(function() order[#order + 1] = "root" end)
	local rec = life:scope("recorder")
	eq(rec.name, "recorder", "a scope has its module's name")
	rec:own(function() order[#order + 1] = "rec" end)
	rec:cleanup()
	eq(table.concat(order, ","), "rec", "cleaning a scope undoes only its things")
	life:cleanup()
	eq(table.concat(order, ","), "rec,root", "the scope isn't undone twice; the rest is undone on cleanup")
	local life2 = Lifecycle.new()
	local s2 = life2:scope("kit")
	local ran = false
	s2:own(function() ran = true end)
	life2:cleanup()
	check(ran, "cleaning the parent cleans its scopes")
end

section("drop: undo one thing now (short-lived parts, per-respawn connections)")
do
	local life = Lifecycle.new()
	local n = 0
	local f = function() n = n + 1 end
	life:own(f)
	eq(life:drop(f), true, "drop finds it")
	eq(n, 1, "undone at once")
	life:cleanup()
	eq(n, 1, "not undone again on cleanup")
	eq(#life.items, 0, "nothing kept")
	eq(life:drop(f), false, "dropping something unknown is false")
	local part = Instance.new("Part")
	part.Transparency = 0
	life:setProp(part, "Transparency", 0.5)
	life:forgetProps(part)
	life:cleanup()
	eq(part.Transparency, 0.5, "forgetProps: that part's writes are no longer put back")
end

section("anything owned after cleanup is undone at once")
do
	local life = Lifecycle.new()
	life:cleanup()
	local ev = M.newSignal("late")
	local c = life:connect(ev, function() end)
	check(not c.Connected, "a connection made after Unload is disconnected at once")
	local ran = false
	life:own(function() ran = true end)
	check(ran, "a cleanup function owned after Unload runs at once")
	local s = life:scope("late")
	local ran2 = false
	s:own(function() ran2 = true end)
	check(ran2, "a scope made after Unload undoes at once too")
end

section("errors: once per message, at most 25 printed")
do
	local printed = {}
	local errs = Errors.new(function(msg) printed[#printed + 1] = msg end)
	errs:report("Pipeline", "boom")
	errs:report("Pipeline", "boom")
	eq(#printed, 1, "the same message prints once")
	check(printed[1]:find("[HappaTAS3] Pipeline: boom", 1, true) ~= nil, "message format (" .. tostring(printed[1]) .. ")")
	for i = 1, 29 do errs:report("Pipeline", "error " .. i) end
	eq(#printed, 25, "at most 25 distinct messages printed")
	eq(errs:count("Pipeline"), 31, "every report is counted")
	eq(errs:count("Other"), 0, "an unknown source counts 0")
end
finish()
