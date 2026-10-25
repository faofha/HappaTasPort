-- ================================================================================================
--  LIBRARY  (HappaTAS 3 persist): the runs of one place, HappaTasPort/<PlaceId>/ and its folders (real
--  subfolders, at most 3 levels). Each run's header info is cached in <root>/library.cache, so listing
--  reads only files it hasn't seen (Library:refresh reads every header again). Names follow V2's rules
--  (Files.cleanName) and never clash on Windows: "run" and "Run" are the same name.
--  Attempts: "Name (2)", "Name (3)"... next to "Name" belong to it (newest first).
--  Safe saving: <file>.tmp written and read back, then the file written and read back, then the .tmp
--  deleted; whatever fails, the old file keeps its bytes and no .tmp is left.
--  Paths in and out are relative to the root, "/" separated ("Tower A/Run (2).tas").
-- ================================================================================================
local Env = import("platform/env")
local Files = import("platform/files")
local Bytes = import("persist/bytes")
local Codec6 = import("persist/codec6")

local Library = {}
Library.__index = Library

local MAX_DEPTH = 3
-- (not .json: V2 lists every .json in the place folder as a legacy slot)
local CACHE = "library.cache"
local UNAVAILABLE = "Saving is unavailable on this executor"

function Library.new(files, root)
	return setmetatable({ files = files, root = root, cache = nil, http = Env.svc("HttpService") }, Library)
end

-- ------------------------------------------------------------------------------------------------ names
local function lower(s) return string.lower(s) end

-- "a/b" with every segment cleaned, "" for the root; nil when it is deeper than MAX_DEPTH
local function cleanFolder(folder)
	local segs = {}
	for seg in tostring(folder or ""):gmatch("[^/\\]+") do
		local c = Files.cleanName(seg)
		if c then segs[#segs + 1] = c end
	end
	if #segs > MAX_DEPTH then return nil end
	return table.concat(segs, "/")
end

local function join(folder, file)
	if folder == "" then return file end
	return folder .. "/" .. file
end

-- folder, base name, extension of a relative path; nil when the path isn't one the library could have made
local function splitPath(path)
	path = tostring(path or ""):gsub("\\", "/")
	local folder, file = path:match("^(.*)/([^/]+)$")
	if not folder then folder, file = "", path end
	if cleanFolder(folder) ~= folder then return nil end
	local base, ext = file:match("^(.+)(%.[^%.]+)$")
	if not base or Files.cleanName(base) ~= base then return nil end
	return folder, base, ext
end

-- V2's natural sort key ("Run 2" before "Run 10")
local function naturalKey(s)
	return (lower(s):gsub("%d+", function(d)
		if #d < 12 then d = string.rep("0", 12 - #d) .. d end
		return d
	end))
end

local function isRunFile(name)
	if name:find("~rename", 1, true) then return nil end
	local base, ext = name:match("^(.+)(%.[Tt][Aa][Ss])$")
	if not base then base, ext = name:match("^(.+)(%.[Jj][Ss][Oo][Nn])$") end
	return base, ext
end

-- ------------------------------------------------------------------------------------------------ cache
local function readCache(self)
	if self.cache then return self.cache end
	local cache = { version = 1, entries = {} }
	local raw = self.files:read(self.root .. "/" .. CACHE)
	if raw and self.http then
		local ok, t = pcall(self.http.JSONDecode, self.http, raw)
		if ok and type(t) == "table" and t.version == 1 and type(t.entries) == "table" then cache = t end
	end
	self.cache = cache
	return cache
end

local function writeCache(self)
	if not self.http or not self.cache then return end
	local ok, json = pcall(self.http.JSONEncode, self.http, self.cache)
	if ok then self.files:write(self.root .. "/" .. CACHE, json) end
end

-- what a file's first bytes say about it
local function headerInfo(data)
	local info = { size = #data }
	local h = Codec6.readHeader(data)
	if h then
		info.version = 6
		info.frames, info.length, info.created, info.saved = h.frames, h.length, h.created, h.saved
		info.script, info.kit, info.speedHack = h.script, h.kit, h.speedHack
	elseif data:sub(1, 4) == "HTAS" then
		local v = string.byte(data, 5) or 0
		info.version = v
		local ok, frames = pcall(function() return Bytes.reader(data, 7):varint() end)
		if ok then info.frames = frames end
	else
		info.version = 0 -- (a legacy JSON slot, or V2.34's wrapped file)
	end
	return info
end

-- ------------------------------------------------------------------------------------------------ listing
local function walk(self, folder, depth, out)
	local abs = (folder == "") and self.root or (self.root .. "/" .. folder)
	local byLower = {}
	for _, name in ipairs(self.files:listFiles(abs)) do
		local base, ext = isRunFile(name)
		if base and not (folder == "" and lower(name) == CACHE) then
			local key = lower(base)
			local had = byLower[key]
			-- (a .tas and a legacy .json of the same name: the .tas, like V2's findSlotFile)
			if not had or lower(had.ext) == ".json" then byLower[key] = { base = base, ext = ext } end
		end
	end
	for _, f in pairs(byLower) do out[#out + 1] = { folder = folder, name = f.base, ext = f.ext } end
	if depth < MAX_DEPTH then
		for _, sub in ipairs(self.files:listFolders(abs)) do walk(self, join(folder, sub), depth + 1, out) end
	end
end

local function makeEntry(f, info)
	local e = { path = join(f.folder, f.name .. f.ext), name = f.name, folder = f.folder, ext = f.ext }
	for k, v in pairs(info) do e[k] = v end
	local base, n = f.name:match("^(.*) %((%d+)%)$")
	if base and tonumber(n) >= 2 then e.base, e.attempt = base, tonumber(n) end
	return e
end

-- every run of the place (headers from the cache, files not in it read once)
function Library:list(force)
	if not self.files.available then return {} end
	local cache = readCache(self)
	local found = {}
	walk(self, "", 0, found)
	local changed, seen, out = false, {}, {}
	for _, f in ipairs(found) do
		local path = join(f.folder, f.name .. f.ext)
		seen[path] = true
		local info = cache.entries[path]
		if force or not info then
			local data = self.files:read(self.root .. "/" .. path)
			info = data and headerInfo(data) or { size = 0, unreadable = true }
			cache.entries[path] = info
			changed = true
		end
		out[#out + 1] = makeEntry(f, info)
	end
	for path in pairs(cache.entries) do
		if not seen[path] then
			cache.entries[path] = nil
			changed = true
		end
	end
	if changed then writeCache(self) end
	return out
end

-- every header read again
function Library:refresh() return self:list(true) end

function Library:sorted(entries, by, descending)
	local out = table.clone(entries)
	local function primary(e)
		if by == "date" then return e.saved or 0 end
		if by == "length" then return e.length or 0 end
		return naturalKey(e.name)
	end
	table.sort(out, function(a, b)
		local pa, pb = primary(a), primary(b)
		if pa ~= pb then
			if descending then return pa > pb end
			return pa < pb
		end
		return a.path < b.path
	end)
	return out
end

function Library:search(entries, text)
	text = lower(tostring(text or ""))
	if text == "" then return table.clone(entries) end
	local out = {}
	for _, e in ipairs(entries) do
		if lower(e.name):find(text, 1, true) then out[#out + 1] = e end
	end
	return out
end

-- runs with their attempts ("X (n)", n >= 2, next to an "X"), attempts newest first
function Library:groups(entries)
	local runs, out = {}, {}
	for _, e in ipairs(entries) do
		runs[e.folder .. "\0" .. lower(e.name)] = e
	end
	-- (the run an attempt belongs to: "Run (2) (2)" -> "Run (2)" -> "Run", up to the first name that isn't an
	-- attempt of a listed run)
	local function rootOf(e)
		local steps = 0
		while e.attempt and steps < 64 do
			local parent = runs[e.folder .. "\0" .. lower(e.base)]
			if not parent then break end
			e, steps = parent, steps + 1
		end
		return e
	end
	local groupOf = {}
	for _, e in ipairs(entries) do
		if rootOf(e) == e then
			local g = { run = e, attempts = {} }
			groupOf[e] = g
			out[#out + 1] = g
		end
	end
	for _, e in ipairs(entries) do
		local root = rootOf(e)
		if root ~= e then table.insert(groupOf[root].attempts, e) end
	end
	for _, g in ipairs(out) do
		table.sort(g.attempts, function(a, b) return a.attempt > b.attempt end)
	end
	return out
end

-- the actual file name of `name` + ext in a folder, whatever its case
local function findCI(self, folder, name, ext)
	local abs = (folder == "") and self.root or (self.root .. "/" .. folder)
	local want = lower(name .. ext)
	for _, f in ipairs(self.files:listFiles(abs)) do
		if lower(f) == want then return f end
	end
	return nil
end

function Library:nextAttemptName(name, folder)
	folder = cleanFolder(folder) or ""
	-- (an attempt of "Run" counts on from "Run": "Run (3)", not "Run (2) (2)")
	local runName = name:match("^(.*) %(%d+%)$")
	if runName and (findCI(self, folder, runName, ".tas") or findCI(self, folder, runName, ".json")) then name = runName end
	local want = lower(name)
	local highest = 1
	local abs = (folder == "") and self.root or (self.root .. "/" .. folder)
	for _, f in ipairs(self.files:listFiles(abs)) do
		local base = isRunFile(f)
		if base then
			local b, n = base:match("^(.*) %((%d+)%)$")
			if b and lower(b) == want then highest = math.max(highest, tonumber(n)) end
		end
	end
	return name .. " (" .. (highest + 1) .. ")"
end

-- ------------------------------------------------------------------------------------------------ files
function Library:read(path)
	local folder, base, ext = splitPath(path)
	if not folder then return nil, "Invalid path" end
	return self.files:read(self.root .. "/" .. join(folder, base .. ext))
end

local function setEntry(self, path, info)
	local cache = readCache(self)
	cache.entries[path] = info
	writeCache(self)
end

-- saves data as <folder>/<name>.tas; returns true and the path, or false and a message
function Library:save(name, folder, data)
	if not self.files.available then return false, UNAVAILABLE end
	name = Files.cleanName(name)
	if not name then return false, "Invalid name" end
	folder = cleanFolder(folder)
	if not folder then return false, "Folders go at most " .. MAX_DEPTH .. " levels deep" end
	local existing = findCI(self, folder, name, ".tas")
	if existing and existing ~= name .. ".tas" then
		return false, "A run named " .. existing:sub(1, -5) .. " already exists"
	end
	local files = self.files
	if folder ~= "" and not files:makeFolder(self.root .. "/" .. folder) then return false, "Could not make the folder" end
	if folder == "" then files:makeFolder(self.root) end
	local rel = join(folder, name .. ".tas")
	local full = self.root .. "/" .. rel
	local tmp = full .. ".tmp"
	local old = files:exists(full) and files:read(full) or nil
	local function fail(msg)
		files:delete(tmp)
		return false, msg
	end
	local ok, err = files:write(tmp, data)
	if not ok then return fail("Could not write the file (" .. tostring(err) .. ")") end
	local back = files:read(tmp)
	if not back or #back ~= #data then return fail("The file could not be checked after writing") end
	ok, err = files:write(full, data)
	if not ok then
		if old and files:read(full) ~= old then files:write(full, old) end
		return fail("Could not write the file (" .. tostring(err) .. ")")
	end
	back = files:read(full)
	if not back or #back ~= #data then
		if old then files:write(full, old) else files:delete(full) end
		return fail("The file could not be checked after writing")
	end
	files:delete(tmp)
	local legacy = findCI(self, folder, name, ".json")
	if legacy then
		files:delete(self.root .. "/" .. join(folder, legacy))
		readCache(self).entries[join(folder, legacy)] = nil
	end
	setEntry(self, rel, headerInfo(data))
	return true, rel
end

-- moves a file to another path (same data), refusing names that clash
local function relocate(self, path, newFolder, newBase)
	local folder, base, ext = splitPath(path)
	if not folder then return false, "Invalid path" end
	local from = join(folder, base .. ext)
	local to = join(newFolder, newBase .. ext)
	if to == from then return true, to end
	local files = self.files
	local data = files:read(self.root .. "/" .. from)
	if not data then return false, "The file does not exist" end
	local sameFile = lower(to) == lower(from)
	-- (a .tas and a legacy .json never share a name, like V2's RenameSlot)
	if not sameFile and (findCI(self, newFolder, newBase, ".tas") or findCI(self, newFolder, newBase, ".json")) then
		return false, "A run named " .. newBase .. " already exists there"
	end
	if newFolder ~= "" and not files:makeFolder(self.root .. "/" .. newFolder) then return false, "Could not make the folder" end
	local ok = pcall(function()
		if sameFile then
			-- (a case-only rename on Windows: through a temporary name, like V2's RenameSlot)
			local tmp = self.root .. "/" .. join(folder, base .. "~rename" .. ext)
			assert(files:write(tmp, data))
			assert(files:delete(self.root .. "/" .. from))
			assert(files:write(self.root .. "/" .. to, data))
			files:delete(tmp)
		else
			assert(files:write(self.root .. "/" .. to, data))
			assert(files:exists(self.root .. "/" .. to))
			assert(files:delete(self.root .. "/" .. from))
		end
	end)
	if not ok then return false, "Could not move the file" end
	local cache = readCache(self)
	cache.entries[to] = cache.entries[from] or headerInfo(data)
	cache.entries[from] = nil
	writeCache(self)
	return true, to
end

function Library:rename(path, newName)
	local folder = splitPath(path)
	if not folder then return false, "Invalid path" end
	local name = Files.cleanName(newName)
	if not name then return false, "Invalid name" end
	return relocate(self, path, folder, name)
end

function Library:move(path, newFolder)
	local _, base = splitPath(path)
	if not base then return false, "Invalid path" end
	local folder = cleanFolder(newFolder)
	if not folder then return false, "Folders go at most " .. MAX_DEPTH .. " levels deep" end
	return relocate(self, path, folder, base)
end

function Library:delete(path)
	local folder, base, ext = splitPath(path)
	if not folder then return false, "Invalid path" end
	local rel = join(folder, base .. ext)
	local ok, err = self.files:delete(self.root .. "/" .. rel)
	if not ok then return false, err end
	readCache(self).entries[rel] = nil
	writeCache(self)
	return true
end

function Library:createFolder(folder)
	folder = cleanFolder(folder)
	if not folder or folder == "" then return false, "Invalid folder" end
	if not self.files:makeFolder(self.root .. "/" .. folder) then return false, "Could not make the folder" end
	return true, folder
end

-- only an empty folder
function Library:deleteFolder(folder)
	folder = cleanFolder(folder)
	if not folder or folder == "" then return false, "Invalid folder" end
	local abs = self.root .. "/" .. folder
	if #self.files:listFiles(abs) > 0 or #self.files:listFolders(abs) > 0 then return false, "The folder is not empty" end
	return self.files:deleteFolder(abs)
end

return Library
