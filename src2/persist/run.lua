-- ================================================================================================
--  RUN  (HappaTAS 3 persist): any file into a timeline, and a timeline into a v6 file.
--  V2 files (v1-v5, the V2.34 wrap, legacy JSON) go through V2Reader and the timeline's V2 conversion.
--  Their data that no HappaTAS 3 plugin records yet (client objects CO, button events BT, kit events
--  KE, speed factors SK, mobile thumbsticks Mobile) stays in carry columns ("v2CO", ...), and the
--  files' tables in tl.meta (v2objects, v2buttons, v2kit, kitVersion), so saving keeps them all; phase
--  4's plugins take them over (a plugin that registers the V2 key itself replaces its carry column).
-- ================================================================================================
local CONFIG = import("config")
local Codec6 = import("persist/codec6")
local V2Reader = import("persist/v2reader")

local Run = {}

local CARRY = { "Mobile", "CO", "BT", "KE", "SK" }

-- a list column for each carried V2 key no column claims (once, after the plugins added theirs)
function Run.registerCarry(tl)
	local claimed = {}
	for _, col in ipairs(tl.order) do
		if col.v2 and col.v2.key then claimed[col.v2.key] = true end
	end
	for _, key in ipairs(CARRY) do
		if not claimed[key] then tl:addColumn("v2" .. key, "list", 1, { key = key, keep = true }) end
	end
end

local function isV6(data)
	return string.sub(data, 1, 4) == "HTAS" and string.byte(data, 5) == 6
end

-- replaces tl's frames with the file's; returns its header (V2 files: frames, length, kit, version)
function Run.load(tl, data, progress)
	if type(data) ~= "string" then error("not a HappaTAS file", 0) end
	if isV6(data) then return Codec6.decode(data, tl, progress) end
	local res = V2Reader.read(data, progress)
	tl:replaceFromV2(res.frames)
	tl.meta = { v2objects = res.objects, v2buttons = res.buttons, v2kit = res.kit, kitVersion = res.kitVersion,
		source = "v" .. tostring(res.version) }
	local n = #res.frames
	return { frames = n, length = (n > 0) and res.frames[n].TotalTime or 0, kit = res.kitVersion, version = res.version }
end

-- the v6 file of the run (tl.meta.created set the first time)
function Run.build(tl, name, progress)
	local n = tl:count()
	local now = os.time()
	tl.meta = tl.meta or {}
	tl.meta.created = tl.meta.created or now
	local speedHack = 0
	local sk = tl.cols.v2SK
	if sk then
		for i in pairs(sk.list) do
			if i <= n then speedHack = 1 break end
		end
	end
	local length = (n > 0 and tl.cols.TotalTime) and tl:get("TotalTime", n, 1) or 0
	return Codec6.encode(tl, { frames = n, length = length, created = tl.meta.created, saved = now, script = CONFIG.VERSION,
		place = game.PlaceId, kit = tl.meta.kitVersion or 0, speedHack = speedHack, name = name }, progress)
end

return Run
