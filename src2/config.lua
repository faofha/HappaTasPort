-- ================================================================================================
--  CONFIG  (HappaTAS 3)
-- ================================================================================================
return {
	VERSION = "3.0.0-dev",
	Debug = false, -- (tests turn this on)
	MaxFileBytes = 512 * 1024 * 1024, -- (V2's limit: anything bigger is refused, damaged or not)
	MaxFrames = 16777216,
}
