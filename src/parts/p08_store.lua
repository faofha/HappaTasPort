-- ================================================================================================
--  STORAGE   <workspace>/HappaTasPort/<PlaceId>/<slot>.tas   +   HappaTasPort/Settings.json
-- ================================================================================================
do
	local ROOT = CONFIG.RootFolder
	local PLACE = tostring(game.PlaceId)
	local PLACE_PATH = ROOT .. "/" .. PLACE
	local SETTINGS_PATH = ROOT .. "/Settings.json"
	local LEGACY_WRAP = "\0LZ4\1"   -- V2.34 wrapped the (already compressed) file a second time

	Store.Available = Env.HasFiles
	Store.Ready = false
	Store.RootPath = ROOT
	Store.PlacePath = PLACE_PATH

	local function call(f, ...)
		local ok, a = pcall(f, ...)
		if ok then return true, a end
		return false, a
	end
	local function fileExists(path)
		local ok, res = call(Env.isfile, path)
		return ok and res == true
	end
	local function folderExists(path)
		local ok, res = call(Env.isfolder, path)
		return ok and res == true
	end
	local function ensureFolders()
		if not folderExists(ROOT) then call(Env.makefolder, ROOT) end
		if not folderExists(PLACE_PATH) then call(Env.makefolder, PLACE_PATH) end
	end

	function Store.Init()
		if not Env.HasFiles then return false end
		ensureFolders()
		Store.Ready = folderExists(PLACE_PATH)
		return Store.Ready
	end

	local RESERVED = { CON = true, PRN = true, AUX = true, NUL = true }
	for i = 1, 9 do
		RESERVED["COM" .. i] = true
		RESERVED["LPT" .. i] = true
	end

	-- a slot name can never leave the place folder (no separators, no dots at the end, no control chars)
	function Store.CleanName(s)
		s = tostring(s or "")
		s = s:gsub("[%c<>:\"/\\|%?%*]", "")
		s = s:gsub("^%s+", "")
		s = s:gsub("%s+$", "")
		s = s:gsub("[%. ]+$", "")
		s = s:gsub("^%.+", "")
		local n = utf8.len(s)
		if n and n > 60 then
			s = s:sub(1, utf8.offset(s, 61) - 1)
		elseif not n then
			s = s:gsub("[\128-\255]", "")
		end
		if s == "" then return nil end
		if RESERVED[s:upper()] then s = "_" .. s end
		return s
	end

	local EXT_NEW, EXT_OLD = ".tas", ".json"
	local function slotPath(name, ext)
		return PLACE_PATH .. "/" .. name .. (ext or EXT_NEW)
	end
	Store.SlotPath = slotPath

	local function findSlotFile(name)
		local p = slotPath(name, EXT_NEW)
		if fileExists(p) then return p, EXT_NEW end
		p = slotPath(name, EXT_OLD)
		if fileExists(p) then return p, EXT_OLD end
		return nil
	end

	local function naturalKey(s)
		return (s:lower():gsub("%d+", function(d)
			if #d < 12 then d = string.rep("0", 12 - #d) .. d end
			return d
		end))
	end

	function Store.Exists(name)
		return findSlotFile(name) ~= nil
	end

	function Store.ListSlots()
		local out, seen = {}, {}
		if not Store.Ready then return out end
		local ok, files = call(Env.listfiles, PLACE_PATH)
		if not ok or type(files) ~= "table" then return out end
		for _, path in ipairs(files) do
			local fname = tostring(path):match("([^/\\]+)$")
			if fname then
				local base = fname:match("^(.+)%.[Tt][Aa][Ss]$") or fname:match("^(.+)%.[Jj][Ss][Oo][Nn]$")
				if base and not seen[base] and not base:find("~rename", 1, true) and fileExists(PLACE_PATH .. "/" .. fname) then
					seen[base] = true
					out[#out + 1] = base
				end
			end
		end
		table.sort(out, function(a, b)
			local ka, kb = naturalKey(a), naturalKey(b)
			if ka == kb then return a < b end
			return ka < kb
		end)
		return out
	end

	function Store.NextDefaultName()
		local n = 1
		while Store.Exists("Slot " .. n) do n = n + 1 end
		return "Slot " .. n
	end

	-- legacy JSON slots (very old HappaTAS / first port versions)
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

	local function writeSlotFile(name, bytes)
		ensureFolders()
		local path = slotPath(name, EXT_NEW)
		local ok, err = call(Env.writefile, path, bytes)
		if not ok then return false, tostring(err) end
		local okR, back = call(Env.readfile, path)
		if not okR or type(back) ~= "string" or #back ~= #bytes then
			return false, "the file could not be verified after writing"
		end
		return true, path, EXT_NEW
	end

	function Store.CreateSlot(name)
		if not Store.Ready then return false, "Saving is unavailable" end
		name = Store.CleanName(name) or Store.NextDefaultName()
		if Store.Exists(name) then return false, "A slot with that name already exists" end
		local okE, bytes = pcall(Codec.Encode, {})
		if not okE then return false, tostring(bytes) end
		local ok, err = writeSlotFile(name, bytes)
		if not ok then return false, err end
		return true, name
	end

	local function frameIsComplete(f)
		return type(f.Cframe) == "table" and f.State ~= nil and type(f.Velocity) == "table" and type(f.CamCframe) == "table"
			and type(f.FrameTime) == "number" and type(f.TotalTime) == "number"
	end

	function Store.SaveSlot(name, allFrames, progress)
		if not Store.Ready then return false, "Saving is unavailable" end
		local frames = {}
		for _, f in ipairs(allFrames) do
			if frameIsComplete(f) then frames[#frames + 1] = f end
		end
		local okO, objects = pcall(ClientObjects.ExportObjects, frames)
		local okB, buttons = pcall(Buttons.ExportKeys, frames)
		local okE, bytes, info = pcall(Codec.Encode, frames, progress, okO and objects or nil, okB and buttons or nil)
		if not okE then return false, tostring(bytes) end
		local ok, path = writeSlotFile(name, bytes)
		if not ok then return false, path end
		if fileExists(slotPath(name, EXT_OLD)) then call(Env.delfile, slotPath(name, EXT_OLD)) end
		return true, #frames, #bytes, info
	end

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
				if b < nBatches then task.wait() end
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

	function Store.LoadSlot(name, progress)
		if not Store.Ready then return false, "Saving is unavailable" end
		local path = findSlotFile(name)
		if not path then return false, "The slot file does not exist" end
		local okR, raw = call(Env.readfile, path)
		if not okR or type(raw) ~= "string" then return false, "Could not read the slot file" end
		if #raw > CONFIG.MaxFileBytes then return false, "The slot file is too big" end

		if raw:sub(1, 5) == LEGACY_WRAP and #raw >= 9 then
			local b1, b2, b3, b4 = string.byte(raw, 6, 9)
			local uSize = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
			if uSize > CONFIG.MaxFileBytes then return false, "The slot file is too big" end
			local okD, decomp = pcall(Codec.Lz4Decompress, raw:sub(10), uSize)
			if not okD then return false, "The slot file is damaged (" .. tostring(decomp) .. ")" end
			raw = decomp
		end

		if Codec.IsCompact(raw) then
			local okD, frames, objects, buttons = pcall(Codec.Decode, raw, progress)
			if not okD then
				local why = tostring(frames):gsub("^[^:]*:%d+: ", "")
				return false, "The slot file is damaged (" .. why .. ")"
			end
			if objects and #objects > 0 then
				local okI, err = pcall(ClientObjects.ImportObjects, frames, objects)
				if not okI then warnf("could not map the client objects of this slot:", tostring(err)) end
			end
			if buttons and #buttons > 0 then
				local okI, err = pcall(Buttons.ImportKeys, frames, buttons)
				if not okI then warnf("could not map the buttons of this slot:", tostring(err)) end
			end
			return true, frames
		end
		return loadLegacyJson(raw, progress)
	end

	function Store.DeleteSlot(name)
		if not Store.Ready then return false, "Saving is unavailable" end
		for _, ext in ipairs({ EXT_NEW, EXT_OLD }) do
			local p = slotPath(name, ext)
			if fileExists(p) then
				local ok, err = call(Env.delfile, p)
				if not ok then return false, tostring(err) end
			end
		end
		return true
	end

	function Store.RenameSlot(old, newName)
		if not Store.Ready then return false, "Saving is unavailable" end
		newName = Store.CleanName(newName)
		if not newName then return false, "Invalid name" end
		if newName == old then return true, old end
		local oldPath, ext = findSlotFile(old)
		if not oldPath then return false, "The slot file does not exist" end
		local sameFile = newName:lower() == old:lower()
		if not sameFile and Store.Exists(newName) then return false, "A slot with that name already exists" end
		local okR, data = call(Env.readfile, oldPath)
		if not okR or type(data) ~= "string" then return false, "Could not read the slot file" end
		local newPath = slotPath(newName, ext)
		local ok = pcall(function()
			if sameFile then
				local tmp = PLACE_PATH .. "/" .. old .. "~rename" .. ext
				Env.writefile(tmp, data)
				Env.delfile(oldPath)
				Env.writefile(newPath, data)
				Env.delfile(tmp)
			else
				Env.writefile(newPath, data)
				if not Env.isfile(newPath) then error("write failed") end
				Env.delfile(oldPath)
			end
		end)
		if not ok then return false, "Rename failed" end
		return true, newName
	end

	function Store.LoadSettings()
		if not Store.Ready or not fileExists(SETTINGS_PATH) then return nil end
		local okR, raw = call(Env.readfile, SETTINGS_PATH)
		if not okR or type(raw) ~= "string" or #raw > 1048576 then return nil end
		local okD, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if okD and type(decoded) == "table" then return decoded end
		return nil
	end

	function Store.SaveSettings(tbl)
		if not Store.Ready then return false end
		local okE, json = pcall(HttpService.JSONEncode, HttpService, tbl)
		if not okE then return false end
		ensureFolders()
		return (call(Env.writefile, SETTINGS_PATH, json))
	end

	-- plain text file next to the slots (MicroProfiler dumps)
	local TEXT_EXT = { txt = true, csv = true, html = true }
	function Store.WriteText(fileName, text, ext)
		if not Store.Ready then return false, "Saving is unavailable" end
		fileName = Store.CleanName(fileName)
		if not fileName then return false, "Invalid name" end
		if not TEXT_EXT[ext or "txt"] then return false, "Invalid file type" end
		ensureFolders()
		local path = PLACE_PATH .. "/" .. fileName .. "." .. (ext or "txt")
		local ok, err = call(Env.writefile, path, text)
		if not ok then return false, tostring(err) end
		return true, path
	end

	-- optional custom sound files: HappaTasPort/Sounds/<name>.(mp3|ogg|wav)
	function Store.CustomAsset(name)
		if not Env.HasFiles or not Env.getcustomasset then return nil end
		for _, ext in ipairs({ ".mp3", ".ogg", ".wav" }) do
			local p = ROOT .. "/Sounds/" .. name .. ext
			if fileExists(p) then
				local ok, id = call(Env.getcustomasset, p)
				if ok and type(id) == "string" and id ~= "" then return id end
			end
		end
		return nil
	end
end

