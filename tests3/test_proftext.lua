-- ================================================================================================
-- HappaTAS 3: the MicroProfiler's text height (run once per line of tests3/proftext.variants).
--   em:   the mock's default model, a text line is one em tall -> moved up 1 px
--   live: the metrics Roblox reported live (2026-11-15): each character's width rounded to whole pixels,
--         0.46 x the size ("M" x 20: 100 px at size 10, 920 at 100), the line as tall as the size. Measured at
--         size 10 the font came out 12 (letters 1 px short: the top row of d, F, H missing, "Moce" next to
--         Roblox's own profiler); at 100 it is 600 / 46 = 13.04, the line holds the whole ascender ..
--         descender, the baseline 13.04 x 2146 / 2701 = 10.36 px under the top -> moved up 3 px
-- ================================================================================================
check(boot(3), "boots")
local P = getgenv().__HappaTAS3_T.engine.profiler
local _, auto = P.TextOffset()
if VARIANT == "live" then
	near(P.TextSize, 600 / 46, 1e-6, "TextSize 13.04 keeps the 6 px grid (not 12 from the rounded size-10 width)")
	eq(auto, -3, "moved up 3 px: the baseline on Roblox's row 7.5")
else
	eq(auto, -1, "an em-high line: moved up 1 px")
end
finish()
