-- ================================================================================================
-- HappaTAS 3, phase 1: the bundle's module loader (src2/ modules built into one file)
-- ================================================================================================
check(boot(3), "boots")
eq(__T3("config").VERSION, "3.0.0-dev", "config module loads")
check(__T3("config") == __T3("config"), "a module is loaded once")
local ok, err = pcall(__T3, "nope")
check(not ok and tostring(err):find("HappaTAS3: no module nope", 1, true) ~= nil, "unknown module errors clearly")
finish()
