-- ================================================================================================
-- HappaTAS 3, phase 1: the state store (mode, frame, ... with change watchers) and the event bus
-- ================================================================================================
check(boot(3), "boots")
local State = __T3("kernel/state")
local Bus = __T3("kernel/bus")
local Errors = __T3("kernel/errors")
local printed = {}
local errs = Errors.new(function(m) printed[#printed + 1] = m end)

section("state: watchers see changes only")
do
	local st = State.new({ mode = "Idle" }, errs)
	eq(st:get("mode"), "Idle", "initial value")
	local calls = {}
	st:watch("mode", function(v, old) calls[#calls + 1] = tostring(old) .. ">" .. tostring(v) end)
	st:set("mode", "Idle")
	eq(#calls, 0, "setting the same value calls nobody")
	st:set("mode", "Paused")
	eq(calls[1], "Idle>Paused", "watcher gets (value, old)")
	st:set("frame", 3)
	eq(#calls, 1, "other keys don't call this watcher")
	eq(st:get("frame"), 3, "a new key is stored")
end

section("state: unwatch, errors, order")
do
	local st = State.new(nil, errs)
	local order = {}
	local stop = st:watch("x", function() order[#order + 1] = "a" end)
	st:watch("x", function() error("watcher broke") end)
	st:watch("x", function() order[#order + 1] = "c" end)
	st:set("x", 1)
	eq(table.concat(order, ","), "a,c", "watchers in order, an erroring one doesn't stop the next")
	eq(#printed, 1, "the error is reported")
	check(printed[1] and printed[1]:find("state:x", 1, true) ~= nil, "reported with the key (" .. tostring(printed[1]) .. ")")
	stop()
	st:set("x", 2)
	eq(table.concat(order, ","), "a,c,c", "unwatch stops calls")
	local snap = st:snapshot()
	snap.x = 99
	eq(st:get("x"), 2, "changing a snapshot doesn't change the store")
end

section("bus")
do
	local bus = Bus.new(errs)
	local got = {}
	local offB
	bus:on("e", function(a, b) got[#got + 1] = "1:" .. tostring(a) .. tostring(b); offB() end)
	offB = bus:on("e", function() got[#got + 1] = "2" end)
	bus:on("e", function() got[#got + 1] = "3" end)
	bus:emit("e", "x", "y")
	eq(table.concat(got, ","), "1:xy,3", "args pass through; a listener removed during the emit isn't called")
	bus:emit("nobody")
	check(true, "emit with no listeners is fine")
	local off = bus:on("f", function() error("listener broke") end)
	bus:on("f", function() got[#got + 1] = "after" end)
	bus:emit("f")
	eq(got[#got], "after", "an erroring listener doesn't stop the next")
	off()
end
finish()
