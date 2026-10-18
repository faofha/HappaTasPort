-- ================================================================================================
--  CODEC  (.tas binary format)
--
--  "HTAS" | u8 version | u8 flags (bit0 LZ4, bit1 has mouse) | varint frames | varint rawLen
--  | zigzag mouseX0 | zigzag mouseY0 | payload (raw or LZ4 block)
--  raw = for every column: varint length + bytes.
--    v1 columns: FA FB DT TA PX PY PZ ROT LV AV ST CR CP ZM PO JT SP AN MS IN MB
--    v2 adds:    CO OB                      (client objects + object table)
--    v3 adds:    FC VP TL TS BE BK          (extra flags, viewport, tools, tool names, buttons, button table)
--    v4:         the v3 columns; the client object frames use their v3 layout (clocks + screw motion), so
--                older versions refuse the file instead of playing its client objects wrong
--    v5 adds:    KE SK KK                  (kit events, speed hack factor, kit table: rules version + keys)
--                KE per frame: varint count, then per event a type byte and its fields:
--                  1 turret bullet fired: varint turret id, varint bullet number, 3 zigzag position x1000,
--                    3 zigzag rotation (axis x angle) x100000, 3 zigzag velocity x1000, varint lifetime x1000
--                  2 bullet ended: varint bullet number, varint damage x1000
--                  3 pushbox spawner: varint spawner id, byte 1 spawned / 0 there when the TAS started
--                SK per frame: varint factor x10000 (frames recorded in slow motion)
--                KK: varint rules version (1 = kit objects on the TAS clock), varint count, { varint id, key }
--  FC bits: 1 viewport changed, 2 tool events, 4 died this frame, 8 button events, 16 kit events,
--           32 speed hack factor
--  Old v1 / v2 / v3 files load exactly like before.
-- ================================================================================================
local Codec = {}
do
	local MAGIC = "HTAS"
	local SCROLL_MARK = 0x7F
	Codec.ScrollBase = 10000

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

	local function q(v, scale)
		if type(v) ~= "number" or v ~= v or v == HUGE or v == -HUGE then return 0 end
		return floor(v * scale + 0.5)
	end

	local function putVar(buf, n)
		n = floor(n or 0)
		if n < 0 then n = 0 end
		local i = #buf
		while n >= 128 do
			local m = n % 128
			i = i + 1
			buf[i] = m + 128
			n = (n - m) / 128
		end
		buf[i + 1] = n
	end
	local function putZig(buf, v)
		v = floor(v or 0)
		if v >= 0 then putVar(buf, v * 2) else putVar(buf, -v * 2 - 1) end
	end
	local function putStr(buf, s)
		putVar(buf, #s)
		local i = #buf
		for k = 1, #s do buf[i + k] = byte(s, k) end
	end

	local function bufToString(buf)
		local parts = {}
		local n = #buf
		local i = 1
		while i <= n do
			local j = i + 3999
			if j > n then j = n end
			parts[#parts + 1] = char(table.unpack(buf, i, j))
			i = j + 1
		end
		return table.concat(parts)
	end

	Codec.PutVar, Codec.PutZig, Codec.BufToString = putVar, putZig, bufToString

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

	-- pure Lua LZ4 block decoder (only used when the executor has no lz4decompress)
	local function lz4Fallback(src, usize)
		local out, on = {}, 0
		local i, n = 1, #src
		while i <= n do
			local token = byte(src, i); i = i + 1
			local lit = floor(token / 16)
			if lit == 15 then
				repeat
					local b = byte(src, i); i = i + 1
					if not b then error("lz4: bad literal length", 0) end
					lit = lit + b
				until b ~= 255
			end
			if i + lit - 1 > n or on + lit > usize then error("lz4: literals out of range", 0) end
			for k = 0, lit - 1 do out[on + k + 1] = byte(src, i + k) end
			on = on + lit
			i = i + lit
			if i > n then break end
			local b1, b2 = byte(src, i, i + 1)
			if not b2 then error("lz4: bad offset", 0) end
			local off = b1 + b2 * 256; i = i + 2
			if off == 0 or off > on then error("lz4: bad offset", 0) end
			local ml = token % 16
			if ml == 15 then
				repeat
					local b = byte(src, i); i = i + 1
					if not b then error("lz4: bad match length", 0) end
					ml = ml + b
				until b ~= 255
			end
			ml = ml + 4
			if on + ml > usize then error("lz4: output too big", 0) end
			local start = on - off
			for k = 1, ml do out[on + k] = out[start + k] end
			on = on + ml
			if on % 65536 < ml then task.wait() end
		end
		if on ~= usize then error("lz4 size mismatch", 0) end
		return bufToString(out)
	end

	local function lz4Decompress(data, usize)
		if Env.lz4decompress then
			local ok, res = pcall(Env.lz4decompress, data, usize)
			if ok and type(res) == "string" and #res == usize then return res end
		end
		return lz4Fallback(data, usize)
	end
	Codec.Lz4Decompress = lz4Decompress

	-- frames: list of frame tables, objects: { {id, key} } client objects, buttons: { {id, key} } buttons,
	-- kit: { version, keys = { {id, key} } } (KitObjects.Export)
	function Codec.Encode(frames, progress, objects, buttons, kit)
		local total = #frames
		local cols = {}
		for _, name in ipairs(COLUMNS_V5) do cols[name] = (name == "FA" or name == "FB" or name == "FC") and table.create(total) or {} end
		local KE, SKc = cols.KE, cols.SK
		local v5 = kit ~= nil and (kit.version or 0) >= 1
		local coParts = {}
		local hasCO, coV3 = false, false
		local FA, FB, DT, TA, PX, PY, PZ = cols.FA, cols.FB, cols.DT, cols.TA, cols.PX, cols.PY, cols.PZ
		local ROT, LV, AV, ST, CR, CP, ZM = cols.ROT, cols.LV, cols.AV, cols.ST, cols.CR, cols.CP, cols.ZM
		local PO, JT, SP, AN, MS, IN, MB = cols.PO, cols.JT, cols.SP, cols.AN, cols.MS, cols.IN, cols.MB
		local FC, VP, TL, BE = cols.FC, cols.VP, cols.TL, cols.BE
		local v3 = (buttons and #buttons > 0) or false

		local hasMouse, mouse0x, mouse0y = false, 0, 0
		for i = 1, total do
			local f = frames[i]
			if f.MX then
				hasMouse = true
				mouse0x, mouse0y = q(f.MX, 1), q(f.MY or 0, 1)
				break
			end
		end

		local pPos = { 0, 0, 0 }
		local pRot = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
		local pLV = { 0, 0, 0 }
		local pAV = { 0, 0, 0 }
		local pState = -1
		local pCamRot = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
		local pCamOff = { 0, 0, 0 }
		local pZoom = 0
		local pPose = -1
		local pJump, pSpeed = 0, 0
		local pMX, pMY = mouse0x, mouse0y
		local pDT, pTotal = 0, 0
		local pVX, pVY = 0, 0
		local toolIndex, toolNames = {}, {}
		local rv, cv = {}, {}

		for i = 1, total do
			local f = frames[i]
			local fa, fb, fc = 0, 0, 0

			local dt = q(f.FrameTime, 1000000)
			local tot = q(f.TotalTime, 1000000)
			putZig(DT, dt - pDT)
			putZig(TA, tot - (pTotal + dt))
			pDT, pTotal = dt, tot

			local cf = f.Cframe
			local x, y, z = q(cf[1], 1000), q(cf[2], 1000), q(cf[3], 1000)
			putZig(PX, x - pPos[1]); putZig(PY, y - pPos[2]); putZig(PZ, z - pPos[3])
			pPos[1], pPos[2], pPos[3] = x, y, z
			local rotChanged = false
			for k = 1, 9 do
				local v = q(cf[3 + k], 1000)
				rv[k] = v
				if v ~= pRot[k] then rotChanged = true end
			end
			if rotChanged then
				fa = fa + 1
				for k = 1, 9 do putZig(ROT, rv[k] - pRot[k]); pRot[k] = rv[k] end
			end

			local vel = f.Velocity
			local lin, ang = vel.Linear, vel.Angular
			local l1, l2, l3 = q(lin[1], 1000), q(lin[2], 1000), q(lin[3], 1000)
			if l1 ~= pLV[1] or l2 ~= pLV[2] or l3 ~= pLV[3] then
				fa = fa + 2
				putZig(LV, l1 - pLV[1]); putZig(LV, l2 - pLV[2]); putZig(LV, l3 - pLV[3])
				pLV[1], pLV[2], pLV[3] = l1, l2, l3
			end
			local a1, a2, a3 = q(ang[1], 1000), q(ang[2], 1000), q(ang[3], 1000)
			if a1 ~= pAV[1] or a2 ~= pAV[2] or a3 ~= pAV[3] then
				fa = fa + 4
				putZig(AV, a1 - pAV[1]); putZig(AV, a2 - pAV[2]); putZig(AV, a3 - pAV[3])
				pAV[1], pAV[2], pAV[3] = a1, a2, a3
			end

			local st = floor(tonumber(f.State) or 0)
			if st ~= pState then
				fa = fa + 8
				ST[#ST + 1] = st % 256
				pState = st
			end

			local cc = f.CamCframe
			local camChanged = false
			for k = 1, 9 do
				local v = q(cc[3 + k], 1000)
				cv[k] = v
				if v ~= pCamRot[k] then camChanged = true end
			end
			if camChanged then
				fa = fa + 16
				for k = 1, 9 do putZig(CR, cv[k] - pCamRot[k]); pCamRot[k] = cv[k] end
			end
			local o1, o2, o3 = q(cc[1], 1000) - x, q(cc[2], 1000) - y, q(cc[3], 1000) - z
			if o1 ~= pCamOff[1] or o2 ~= pCamOff[2] or o3 ~= pCamOff[3] then
				fa = fa + 32
				putZig(CP, o1 - pCamOff[1]); putZig(CP, o2 - pCamOff[2]); putZig(CP, o3 - pCamOff[3])
				pCamOff[1], pCamOff[2], pCamOff[3] = o1, o2, o3
			end
			local zoom = q(f.Zoom, 1000)
			if zoom ~= pZoom then
				fa = fa + 64
				putZig(ZM, zoom - pZoom)
				pZoom = zoom
			end
			if f.ShiftLock == 1 then fa = fa + 128 end

			local an = f.Anim
			if an then
				local pose = floor(tonumber(an.Pose) or 0)
				if pose ~= pPose then
					fb = fb + 1
					PO[#PO + 1] = pose % 256
					pPose = pose
				end
				local jt = q(an.JumpTime or 0, 1000)
				if jt ~= pJump then
					fb = fb + 2
					putZig(JT, jt - pJump)
					pJump = jt
				end
				local sp = q(an.Speed or 1, 1000)
				if sp ~= pSpeed then
					fb = fb + 4
					putZig(SP, sp - pSpeed)
					pSpeed = sp
				end
				local list = an.Anims
				if list and #list > 0 then
					fb = fb + 8
					local cnt = math.min(#list, 255)
					AN[#AN + 1] = cnt
					for k = 1, cnt do
						local a = list[k]
						AN[#AN + 1] = floor(tonumber(a[1]) or 0) % 256
						putVar(AN, math.max(0, q(a[2] or 0, 1000)))
					end
				end
			end

			if hasMouse and f.MX then
				local mx, my = q(f.MX, 1), q(f.MY or 0, 1)
				if mx ~= pMX or my ~= pMY then
					fb = fb + 16
					putZig(MS, mx - pMX); putZig(MS, my - pMY)
					pMX, pMY = mx, my
				end
			end

			local ev = f.Input
			if ev and #ev > 0 then
				fb = fb + 32
				putVar(IN, #ev)
				for _, e in ipairs(ev) do
					if e >= Codec.ScrollBase - 5000 then
						IN[#IN + 1] = SCROLL_MARK
						putZig(IN, e - Codec.ScrollBase)
					elseif e > 0 then
						IN[#IN + 1] = e % 128
					else
						IN[#IN + 1] = (-e) % 128 + 128
					end
				end
			end

			local mob = f.Mobile
			if type(mob) == "table" then
				fb = fb + 64
				local hasStick = mob.JoystickX ~= nil and mob.JoystickY ~= nil
				local d = mob.Dynamic
				local hasDyn = type(d) == "table" and d.Start ~= nil and d.End ~= nil
				MB[#MB + 1] = (mob.Jumping == 1 and 1 or 0) + (hasStick and 2 or 0) + (hasDyn and 4 or 0)
				if hasStick then
					putZig(MB, q(mob.JoystickX, 1)); putZig(MB, q(mob.JoystickY, 1))
				end
				if hasDyn then
					putZig(MB, q(d.Start[1], 1)); putZig(MB, q(d.Start[2], 1)); putVar(MB, q(d.Start[3], 100))
					putZig(MB, q(d.End[1], 1)); putZig(MB, q(d.End[2], 1)); putVar(MB, q(d.End[3], 100))
					local mList = d.Middles or {}
					local cnt = math.min(#mList, 15)
					putVar(MB, cnt)
					for k = 1, cnt do
						local m = mList[k]
						putZig(MB, q(m[1], 1)); putZig(MB, q(m[2], 1)); putVar(MB, q(m[3], 100))
						putVar(MB, math.max(0, q(m[4] or 0, 1)))
						putVar(MB, math.max(0, q(m[5] or 0, 1)))
					end
				end
			end

			if f.CO then
				hasCO = true
				if not coV3 and byte(f.CO, 1) >= 4 then coV3 = true end
				fb = fb + 128
				local hdr = {}
				putVar(hdr, #f.CO)
				coParts[#coParts + 1] = bufToString(hdr)
				coParts[#coParts + 1] = f.CO
			end

			-- v3 extras
			if hasMouse and f.VX then
				local vx, vy = q(f.VX, 10), q(f.VY or 0, 10)
				if vx ~= pVX or vy ~= pVY then
					fc = fc + 1
					putZig(VP, vx - pVX); putZig(VP, vy - pVY)
					pVX, pVY = vx, vy
				end
			end
			local tools = f.Tools
			if type(tools) == "table" and #tools > 0 then
				fc = fc + 2
				local cnt = math.min(#tools, 255)
				putVar(TL, cnt)
				for k = 1, cnt do
					local t = tools[k]
					local name = tostring(t.Name or "")
					local idx = toolIndex[name]
					if not idx then
						idx = #toolNames + 1
						toolNames[idx] = name
						toolIndex[name] = idx
					end
					TL[#TL + 1] = TOOL_CODE[t.Action] or 0
					putVar(TL, idx)
				end
			end
			if f.Died then fc = fc + 4 end
			local bt = f.BT
			if type(bt) == "table" and #bt > 0 then
				fc = fc + 8
				putVar(BE, #bt)
				for k = 1, #bt do
					local e = bt[k]
					putVar(BE, e[1])
					BE[#BE + 1] = (e[2] == 1) and 1 or 0
					putVar(BE, math.max(0, q(e[3] or 0, 1000)))
				end
			end
			local ke = f.KE
			if type(ke) == "table" and #ke > 0 then
				fc = fc + 16
				v5 = true
				putVar(KE, #ke)
				for k = 1, #ke do
					local e = ke[k]
					local typ = e[1]
					KE[#KE + 1] = typ
					if typ == 1 then
						putVar(KE, e[2]); putVar(KE, e[3])
						putZig(KE, q(e[4], 1000)); putZig(KE, q(e[5], 1000)); putZig(KE, q(e[6], 1000))
						putZig(KE, q(e[7], 100000)); putZig(KE, q(e[8], 100000)); putZig(KE, q(e[9], 100000))
						putZig(KE, q(e[10], 1000)); putZig(KE, q(e[11], 1000)); putZig(KE, q(e[12], 1000))
						putVar(KE, math.max(0, q(e[13], 1000)))
					elseif typ == 2 then
						putVar(KE, e[2]); putVar(KE, math.max(0, q(e[3] or 0, 1000)))
					elseif typ == 3 then
						putVar(KE, e[2]); KE[#KE + 1] = (e[3] == 0) and 0 or 1
					else
						error("unknown kit event " .. tostring(typ), 0)
					end
				end
			end
			local sk = tonumber(f.SK)
			if sk and sk ~= 1 and sk > 0 then
				fc = fc + 32
				v5 = true
				putVar(SKc, q(sk, 10000))
			end
			if fc ~= 0 then v3 = true end

			FA[#FA + 1] = fa
			FB[#FB + 1] = fb
			FC[#FC + 1] = fc

			if i % 1500 == 0 then
				if progress then progress(i, total) end
				task.wait()
			end
		end

		local version = 1
		if hasCO or (objects and #objects > 0) then version = 2 end
		if v3 then version = 3 end
		if coV3 then version = 4 end
		if v5 then version = 5 end
		if version >= 2 then
			local OB = cols.OB
			putVar(OB, #(objects or {}))
			for _, o in ipairs(objects or {}) do
				putVar(OB, o.id)
				putStr(OB, o.key)
			end
		end
		if version >= 3 then
			local TS = cols.TS
			putVar(TS, #toolNames)
			for _, name in ipairs(toolNames) do putStr(TS, name) end
			local BK = cols.BK
			putVar(BK, #(buttons or {}))
			for _, b in ipairs(buttons or {}) do
				putVar(BK, b.id)
				putStr(BK, b.key)
			end
		end
		if version >= 5 then
			local KK = cols.KK
			putVar(KK, (kit and kit.version) or 0)
			local keys = (kit and kit.keys) or {}
			putVar(KK, #keys)
			for _, k in ipairs(keys) do
				putVar(KK, k.id)
				putStr(KK, k.key)
			end
		end

		local rawParts = {}
		for _, name in ipairs(COLUMNS_FOR[version]) do
			local s
			if name == "CO" then s = table.concat(coParts) else s = bufToString(cols[name]) end
			local hdr = {}
			putVar(hdr, #s)
			rawParts[#rawParts + 1] = bufToString(hdr)
			rawParts[#rawParts + 1] = s
		end
		local raw = table.concat(rawParts)

		local compressed, flags = nil, 0
		if hasMouse then flags = flags + 2 end
		if Env.HasLZ4 and #raw > 64 then
			local ok, res = pcall(Env.lz4compress, raw)
			if ok and type(res) == "string" and #res < #raw then
				local okD, back = pcall(Env.lz4decompress, res, #raw)
				if okD and back == raw then
					compressed = res
					flags = flags + 1
				end
			end
		end

		local head = {}
		putVar(head, total)
		putVar(head, #raw)
		putZig(head, mouse0x)
		putZig(head, mouse0y)
		local file = MAGIC .. char(version, flags) .. bufToString(head) .. (compressed or raw)
		return file, { frames = total, rawBytes = #raw, fileBytes = #file, compressed = compressed ~= nil, version = version }
	end

	function Codec.IsCompact(data)
		return type(data) == "string" and sub(data, 1, 4) == MAGIC
	end

	function Codec.Decode(data, progress)
		if not Codec.IsCompact(data) then error("not a HappaTAS binary file", 0) end
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
			raw = lz4Decompress(payload, rawLen)
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
						ev[k] = Codec.ScrollBase + getZig(R.IN)
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
				task.wait()
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
end

