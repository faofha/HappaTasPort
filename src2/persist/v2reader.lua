-- ================================================================================================
--  V2READER  (HappaTAS 3 persist): every file HappaTAS V2 could open, read the way V2.38.16 read it:
--  binary v1-v5 ("HTAS", p07_codec.lua Codec.Decode and its helpers), the V2.34 wrap ("\0LZ4\1" + size
--  around a whole file, p08_store.lua LoadSlot) and legacy JSON slots (p08_store.lua unpackFrame,
--  validFrame, loadLegacyJson). A port of commit b1569bd: the same frames, the same refusals; only the
--  names around it changed (Lz4 module, waits only on a thread that may yield, errors instead of
--  false + message). Client object / button / kit ids are left as the file has them (phase 4 maps them).
--  V2Reader.read(data, progress) -> { frames, objects, buttons, kit, version (1-5, 0 = JSON), kitVersion }
-- ================================================================================================
local CONFIG = import("config")
local Env = import("platform/env")
local Lz4 = import("persist/lz4")

local V2Reader = {}

local MAGIC = "HTAS"
local SCROLL_MARK = 0x7F
local SCROLL_BASE = 10000
local LEGACY_WRAP = "\0LZ4\1"

local COLUMNS_V1 = { "FA", "FB", "DT", "TA", "PX", "PY", "PZ", "ROT", "LV", "AV", "ST", "CR", "CP", "ZM", "PO", "JT", "SP", "AN", "MS", "IN", "MB" }
local COLUMNS_V2, COLUMNS_V3, COLUMNS_V5 = {}, {}, {}
for i, n in ipairs(COLUMNS_V1) do COLUMNS_V2[i] = n; COLUMNS_V3[i] = n end
for _, n in ipairs({ "CO", "OB" }) do COLUMNS_V2[#COLUMNS_V2 + 1] = n; COLUMNS_V3[#COLUMNS_V3 + 1] = n end
for _, n in ipairs({ "FC", "VP", "TL", "TS", "BE", "BK" }) do COLUMNS_V3[#COLUMNS_V3 + 1] = n end
for i, n in ipairs(COLUMNS_V3) do COLUMNS_V5[i] = n end
for _, n in ipairs({ "KE", "SK", "KK" }) do COLUMNS_V5[#COLUMNS_V5 + 1] = n end
local COLUMNS_FOR = { COLUMNS_V1, COLUMNS_V2, COLUMNS_V3, COLUMNS_V3, COLUMNS_V5 }

local TOOL_CODE = { Equip = 1, Unequip = 2, Activate = 3, Deactivate = 4 }
local TOOL_NAME = { "Equip", "Unequip", "Activate", "Deactivate" }

local floor = math.floor
local char, byte, sub = string.char, string.byte, string.sub
local HUGE = math.huge

local function clampn(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end
local function pause()
	if coroutine.isyieldable() then task.wait() end
end

local function newReader(s, p, n)
	return { s = s, p = p or 1, n = n or #s }
end
local function getByte(rd)
	local p = rd.p
	if p > rd.n then error("unexpected end of data", 0) end
	rd.p = p + 1
	return byte(rd.s, p)
end
local function getVar(rd)
	local result, mul = 0, 1
	while true do
		local b = getByte(rd)
		if b < 128 then return result + b * mul end
		result = result + (b - 128) * mul
		mul = mul * 128
		if mul > 2 ^ 49 then error("bad number", 0) end
	end
end
local function getZig(rd)
	local z = getVar(rd)
	if z % 2 == 0 then return floor(z / 2) end
	return -floor((z + 1) / 2)
end
local function getStr(rd)
	local len = getVar(rd)
	local p = rd.p
	if p + len - 1 > rd.n then error("text is cut off", 0) end
	rd.p = p + len
	return sub(rd.s, p, p + len - 1)
end

local function isCompact(data)
	return type(data) == "string" and sub(data, 1, 4) == MAGIC
end

local function decode(data, progress)
	if not isCompact(data) then error("not a HappaTAS binary file", 0) end
	if #data > CONFIG.MaxFileBytes then error("file is too big", 0) end
	local version, flags = byte(data, 5), byte(data, 6)
	if version < 1 or version > 5 then error("unsupported file version " .. tostring(version), 0) end
	local rd = newReader(data, 7)
	local total = getVar(rd)
	local rawLen = getVar(rd)
	local mouse0x = getZig(rd)
	local mouse0y = getZig(rd)
	if rawLen > CONFIG.MaxFileBytes then error("file is too big", 0) end
	if total > rawLen then error("frame count is broken", 0) end
	local payload = sub(data, rd.p)
	local raw
	if flags % 2 == 1 then
		raw = Lz4.decompress(payload, rawLen)
	else
		raw = payload
	end
	if #raw ~= rawLen then error("size mismatch", 0) end
	local hasMouse = floor(flags / 2) % 2 == 1

	local R = {}
	local rr = newReader(raw)
	for _, name in ipairs(COLUMNS_FOR[version]) do
		local len = getVar(rr)
		local start = rr.p
		if start + len - 1 > #raw then error("column " .. name .. " is cut off", 0) end
		R[name] = newReader(raw, start, start + len - 1)
		rr.p = start + len
	end
	if rr.p ~= #raw + 1 then error("trailing data", 0) end
	local function colLen(c) return c.n - c.p + 1 end
	if colLen(R.FA) ~= total or colLen(R.FB) ~= total or (R.FC and colLen(R.FC) ~= total) then
		error("frame flags don't match the frame count", 0)
	end

	-- v3 tables first (frames reference them)
	local toolNames = {}
	if R.TS then
		local cnt = getVar(R.TS)
		if cnt > colLen(R.TS) then error("tool table is broken", 0) end
		for k = 1, cnt do toolNames[k] = getStr(R.TS) end
	end

	local frames = table.create(total)
	local FA, FB, FC, DT, TA, PX, PY, PZ = R.FA, R.FB, R.FC, R.DT, R.TA, R.PX, R.PY, R.PZ
	local pPos = { 0, 0, 0 }
	local pRot = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
	local pLV = { 0, 0, 0 }
	local pAV = { 0, 0, 0 }
	local pState = 0
	local pCamRot = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
	local pCamOff = { 0, 0, 0 }
	local pZoom = 0
	local pPose = 0
	local pJump, pSpeed = 0, 0
	local pMX, pMY = mouse0x, mouse0y
	local pDT, pTotal = 0, 0
	local pVX, pVY = 0, 0

	for i = 1, total do
		local fa, fb = getByte(FA), getByte(FB)
		local fc = FC and getByte(FC) or 0
		local f = {}

		local dt = pDT + getZig(DT)
		local tot = pTotal + dt + getZig(TA)
		pDT, pTotal = dt, tot
		f.FrameTime = dt / 1000000
		f.TotalTime = tot / 1000000

		pPos[1] = pPos[1] + getZig(PX); pPos[2] = pPos[2] + getZig(PY); pPos[3] = pPos[3] + getZig(PZ)
		if fa % 2 == 1 then
			for k = 1, 9 do pRot[k] = pRot[k] + getZig(R.ROT) end
		end
		local cf = { pPos[1] / 1000, pPos[2] / 1000, pPos[3] / 1000 }
		for k = 1, 9 do cf[3 + k] = pRot[k] / 1000 end
		f.Cframe = cf

		if floor(fa / 2) % 2 == 1 then
			pLV[1] = pLV[1] + getZig(R.LV); pLV[2] = pLV[2] + getZig(R.LV); pLV[3] = pLV[3] + getZig(R.LV)
		end
		if floor(fa / 4) % 2 == 1 then
			pAV[1] = pAV[1] + getZig(R.AV); pAV[2] = pAV[2] + getZig(R.AV); pAV[3] = pAV[3] + getZig(R.AV)
		end
		f.Velocity = {
			Linear = { pLV[1] / 1000, pLV[2] / 1000, pLV[3] / 1000 },
			Angular = { pAV[1] / 1000, pAV[2] / 1000, pAV[3] / 1000 },
		}

		if floor(fa / 8) % 2 == 1 then pState = getByte(R.ST) end
		f.State = pState

		if floor(fa / 16) % 2 == 1 then
			for k = 1, 9 do pCamRot[k] = pCamRot[k] + getZig(R.CR) end
		end
		if floor(fa / 32) % 2 == 1 then
			pCamOff[1] = pCamOff[1] + getZig(R.CP); pCamOff[2] = pCamOff[2] + getZig(R.CP); pCamOff[3] = pCamOff[3] + getZig(R.CP)
		end
		local cc = { (pPos[1] + pCamOff[1]) / 1000, (pPos[2] + pCamOff[2]) / 1000, (pPos[3] + pCamOff[3]) / 1000 }
		for k = 1, 9 do cc[3 + k] = pCamRot[k] / 1000 end
		f.CamCframe = cc

		if floor(fa / 64) % 2 == 1 then pZoom = pZoom + getZig(R.ZM) end
		f.Zoom = pZoom / 1000
		f.ShiftLock = (fa >= 128) and 1 or 0

		if fb % 2 == 1 then pPose = getByte(R.PO) end
		if floor(fb / 2) % 2 == 1 then pJump = pJump + getZig(R.JT) end
		if floor(fb / 4) % 2 == 1 then pSpeed = pSpeed + getZig(R.SP) end
		local anims = {}
		if floor(fb / 8) % 2 == 1 then
			local cnt = getByte(R.AN)
			for k = 1, cnt do
				local num = getByte(R.AN)
				local ms = getVar(R.AN)
				anims[k] = { num, ms / 1000 }
			end
		end
		f.Anim = { Pose = pPose, JumpTime = pJump / 1000, Speed = pSpeed / 1000, Anims = anims }

		if hasMouse then
			if floor(fb / 16) % 2 == 1 then
				pMX = pMX + getZig(R.MS); pMY = pMY + getZig(R.MS)
			end
			f.MX, f.MY = pMX, pMY
		end

		if floor(fb / 32) % 2 == 1 then
			local cnt = getVar(R.IN)
			if cnt > colLen(R.IN) + 1 then error("input list is broken", 0) end
			local ev = {}
			for k = 1, cnt do
				local b = getByte(R.IN)
				if b == SCROLL_MARK then
					ev[k] = SCROLL_BASE + getZig(R.IN)
				elseif b >= 128 then
					ev[k] = -(b - 128)
				else
					ev[k] = b
				end
			end
			f.Input = ev
		end

		if floor(fb / 64) % 2 == 1 then
			local mf = getByte(R.MB)
			local mob = { Jumping = mf % 2 }
			if floor(mf / 2) % 2 == 1 then
				mob.JoystickX = getZig(R.MB)
				mob.JoystickY = getZig(R.MB)
			end
			if floor(mf / 4) % 2 == 1 then
				local sx = getZig(R.MB); local sy = getZig(R.MB); local str = getVar(R.MB) / 100
				local ex = getZig(R.MB); local ey = getZig(R.MB); local etr = getVar(R.MB) / 100
				local mCount = getVar(R.MB)
				if mCount > 15 then error("thumbstick data is broken", 0) end
				local mids = {}
				for k = 1, mCount do
					mids[k] = { getZig(R.MB), getZig(R.MB), getVar(R.MB) / 100, getVar(R.MB), getVar(R.MB) }
				end
				mob.Dynamic = { Start = { sx, sy, str }, End = { ex, ey, etr }, Middles = mids }
			end
			f.Mobile = mob
		else
			f.Mobile = 0
		end

		if floor(fb / 128) % 2 == 1 then
			if not R.CO then error("client object data is missing", 0) end
			local len = getVar(R.CO)
			local from = R.CO.p
			if len < 1 or from + len - 1 > R.CO.n then error("client object data is cut off", 0) end
			f.CO = sub(raw, from, from + len - 1)
			R.CO.p = from + len
		end

		if fc ~= 0 then
			if fc % 2 == 1 then
				pVX = pVX + getZig(R.VP); pVY = pVY + getZig(R.VP)
			end
			if floor(fc / 2) % 2 == 1 then
				local cnt = getVar(R.TL)
				local list = {}
				for k = 1, cnt do
					local code = getByte(R.TL)
					local idx = getVar(R.TL)
					local act, name = TOOL_NAME[code], toolNames[idx]
					if act and name then list[#list + 1] = { Action = act, Name = name } end
				end
				if #list > 0 then f.Tools = list end
			end
			if floor(fc / 4) % 2 == 1 then f.Died = true end
			if floor(fc / 8) % 2 == 1 then
				local cnt = getVar(R.BE)
				if cnt > colLen(R.BE) + 1 then error("button list is broken", 0) end
				local list = {}
				for k = 1, cnt do
					local id = getVar(R.BE)
					local stv = getByte(R.BE)
					local el = getVar(R.BE) / 1000
					list[k] = { id, stv == 1 and 1 or 0, el }
				end
				f.BT = list
			end
			if floor(fc / 16) % 2 == 1 then
				if not R.KE then error("kit events are missing", 0) end
				local cnt = getVar(R.KE)
				if cnt > colLen(R.KE) + 1 then error("kit event list is broken", 0) end
				local list = {}
				for k = 1, cnt do
					local typ = getByte(R.KE)
					if typ == 1 then
						local e = { 1, getVar(R.KE), getVar(R.KE) }
						for m = 4, 6 do e[m] = getZig(R.KE) / 1000 end
						for m = 7, 9 do e[m] = getZig(R.KE) / 100000 end
						for m = 10, 12 do e[m] = getZig(R.KE) / 1000 end
						e[13] = getVar(R.KE) / 1000
						list[k] = e
					elseif typ == 2 then
						list[k] = { 2, getVar(R.KE), getVar(R.KE) / 1000 }
					elseif typ == 3 then
						list[k] = { 3, getVar(R.KE), getByte(R.KE) }
					elseif typ == 4 then
						list[k] = { 4, getVar(R.KE), getByte(R.KE) }
					else
						error("unknown kit event " .. tostring(typ), 0)
					end
				end
				f.KE = list
			end
			if floor(fc / 32) % 2 == 1 then
				if not R.SK then error("speed factors are missing", 0) end
				f.SK = getVar(R.SK) / 10000
			end
		end
		if pVX > 0 and pVY > 0 then
			f.VX, f.VY = pVX / 10, pVY / 10
			if f.MX then
				f.UVX = clampn(f.MX / f.VX, 0, 1)
				f.UVY = clampn(f.MY / f.VY, 0, 1)
			end
		end

		frames[i] = f
		if i % 1500 == 0 then
			if progress then progress(i, total) end
			pause()
		end
	end

	for name, rdr in pairs(R) do
		if name ~= "OB" and name ~= "TS" and name ~= "BK" and name ~= "KK" and rdr.p ~= rdr.n + 1 then
			error("column " .. name .. " was not read completely", 0)
		end
	end

	local function readTable(rdr, what)
		local list = {}
		if rdr and rdr.n >= rdr.p then
			local cnt = getVar(rdr)
			if cnt > colLen(rdr) then error(what .. " table is broken", 0) end
			for k = 1, cnt do
				local id = getVar(rdr)
				list[k] = { id = id, key = getStr(rdr) }
			end
		end
		if rdr and rdr.p ~= rdr.n + 1 then error(what .. " table was not read completely", 0) end
		return list
	end
	local objects = R.OB and readTable(R.OB, "object") or nil
	local buttons = R.BK and readTable(R.BK, "button") or nil
	if R.TS and R.TS.p ~= R.TS.n + 1 then error("tool table was not read completely", 0) end
	local kit = nil
	if R.KK then
		local KK = R.KK
		kit = { version = getVar(KK), keys = {} }
		local cnt = getVar(KK)
		if cnt > colLen(KK) then error("kit table is broken", 0) end
		for k = 1, cnt do
			local id = getVar(KK)
			kit.keys[k] = { id = id, key = getStr(KK) }
		end
		if KK.p ~= KK.n + 1 then error("kit table was not read completely", 0) end
	end
	return frames, objects, buttons, kit
end

local function unpackFrame(frame)
	return {
		Cframe = frame[1],
		Velocity = { Linear = frame[2][1], Angular = frame[2][2] },
		State = frame[3],
		CamCframe = frame[4],
		ShiftLock = frame[5],
		Mobile = (type(frame[6]) == "table" and { Jumping = frame[6][1], JoystickX = frame[6][2], JoystickY = frame[6][3] }) or 0,
		Anim = { Pose = frame[7][1], JumpTime = frame[7][2], Speed = frame[7][3], Anims = frame[7][4] or {} },
		Zoom = frame[8],
		FrameTime = frame[9],
		TotalTime = frame[10],
	}
end
local function isNum(v) return type(v) == "number" and v == v end
local function validFrame(frame)
	return type(frame) == "table" and type(frame[1]) == "table" and #frame[1] >= 12
		and type(frame[2]) == "table" and type(frame[2][1]) == "table" and type(frame[2][2]) == "table"
		and isNum(frame[3]) and type(frame[4]) == "table" and #frame[4] >= 12
		and type(frame[7]) == "table" and isNum(frame[8]) and isNum(frame[9]) and isNum(frame[10])
end

local HttpService = Env.svc("HttpService")
local function loadLegacyJson(raw, progress)
	local frames = {}
	local nl = raw:find("\n", 1, true)
	local head = nl and raw:sub(1, nl - 1) or ""
	if head:sub(-11) == '"batches":[' then
		local lines = {}
		for line in raw:gmatch("[^\n]+") do lines[#lines + 1] = line end
		if #lines < 2 or lines[#lines] ~= "]}" then return false, "The slot file is incomplete" end
		local nBatches = #lines - 2
		for b = 1, nBatches do
			local line = lines[b + 1]
			if line:sub(-1) == "," then line = line:sub(1, -2) end
			local okD, batch = pcall(HttpService.JSONDecode, HttpService, line)
			if not okD or type(batch) ~= "table" then return false, "The slot file is corrupted" end
			for _, frame in ipairs(batch) do
				if not validFrame(frame) then return false, "Frame " .. (#frames + 1) .. " is corrupted" end
				frames[#frames + 1] = unpackFrame(frame)
			end
			if progress then progress(b, nBatches) end
			if b < nBatches then pause() end
		end
		return true, frames
	end

	local okD, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if not okD or type(decoded) ~= "table" then return false, "This is not a HappaTAS slot file" end
	local lists
	if type(decoded.batches) == "table" then
		lists = decoded.batches
	else
		lists = { decoded.frames or decoded }
	end
	for _, arr in ipairs(lists) do
		if type(arr) ~= "table" then return false, "The slot file is corrupted" end
		for _, frame in ipairs(arr) do
			if not validFrame(frame) then return false, "Frame " .. (#frames + 1) .. " is corrupted" end
			frames[#frames + 1] = unpackFrame(frame)
		end
	end
	return true, frames
end

-- the frames (and tables) of a V2 file; errors with V2's reason when it isn't one or is damaged
function V2Reader.read(data, progress)
	if type(data) ~= "string" then error("not a HappaTAS file", 0) end
	if #data > CONFIG.MaxFileBytes then error("The slot file is too big", 0) end
	local raw = data
	if sub(raw, 1, 5) == LEGACY_WRAP and #raw >= 9 then
		local b1, b2, b3, b4 = byte(raw, 6, 9)
		local uSize = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
		if uSize > CONFIG.MaxFileBytes then error("The slot file is too big", 0) end
		local okD, decomp = pcall(Lz4.decompress, sub(raw, 10), uSize)
		if not okD then error("The slot file is damaged (" .. tostring(decomp) .. ")", 0) end
		raw = decomp
	end
	if isCompact(raw) then
		local frames, objects, buttons, kit = decode(raw, progress)
		return { frames = frames, objects = objects, buttons = buttons, kit = kit, version = byte(raw, 5),
			kitVersion = kit and (kit.version or 0) or 0 }
	end
	local ok, frames = loadLegacyJson(raw, progress)
	if not ok then error(tostring(frames), 0) end
	return { frames = frames, version = 0, kitVersion = 0 }
end

return V2Reader
