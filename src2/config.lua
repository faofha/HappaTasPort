-- ================================================================================================
--  CONFIG  (HappaTAS 3)
-- ================================================================================================
return {
	VERSION = "3.0.0-dev",
	Debug = false, -- (tests turn this on)
	MaxFileBytes = 512 * 1024 * 1024, -- (V2's limit: anything bigger is refused, damaged or not)
	MaxFrames = 16777216,
	-- client objects (V2.38.17's CONFIG.ClientObjects, the same numbers)
	ClientObjects = {
		Radius        = 450,
		AlwaysRadius  = 35,
		FullEvery     = 2400, -- a full snapshot at least every 2400 recorded frames...
		FullSeconds   = 10,   -- ...and every 10 s of TAS time
		VisEvery      = 6,
		PosTolerance  = 0.015,
		RotTolerance  = 0.0015,
		MaxModelAge   = 2.0,
		MaxRegistered = 8000,
		MaxWatched    = 30000,
		WatchAnchored = true,
		Groups        = { ClientObjects = true },
	},
}
