-- ================================================================================================
--  FILES  (HappaTAS 3 platform): the executor's file functions, each call protected. A failure comes
--  back as nil / false and a message, never as an error. Paths use "/". Names follow V2's rules
--  (Store.CleanName): a name can never leave its folder.
-- ================================================================================================
local Files = {}
Files.__index = Files

local RESERVED = { CON = true, PRN = true, AUX = true, NUL = true }
for i = 1, 9 do
	RESERVED["COM" .. i] = true
	RESERVED["LPT" .. i] = true
end

-- a file or folder name, or nil when nothing is left (V2.38.16 Store.CleanName, exactly)
function Files.cleanName(s)
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

function Files.join(...)
	return table.concat({ ... }, "/")
end

local function lastSegment(p)
	return tostring(p):gsub("\\", "/"):match("([^/]+)/*$")
end

function Files.new(Env)
	return setmetatable({ Env = Env, available = Env.has("files") }, Files)
end

local function call(f, ...)
	if not f then return false, "this executor has no file functions" end
	local ok, res = pcall(f, ...)
	if ok then return true, res end
	return false, tostring(res)
end

function Files:read(path)
	if not self.Env.isfile then return nil, "this executor has no file functions" end
	local okE, exists = call(self.Env.isfile, path)
	if not okE or exists ~= true then return nil, "the file does not exist" end
	local ok, res = call(self.Env.readfile, path)
	if not ok then return nil, res end
	if type(res) ~= "string" then return nil, "the file could not be read" end
	return res
end

function Files:write(path, s)
	local ok, err = call(self.Env.writefile, path, s)
	if not ok then return false, err end
	return true
end

function Files:exists(path)
	local ok, res = call(self.Env.isfile, path)
	return ok and res == true
end

function Files:isFolder(path)
	local ok, res = call(self.Env.isfolder, path)
	return ok and res == true
end

-- creates the folder and any missing parents
function Files:makeFolder(path)
	local sofar = nil
	for seg in tostring(path):gmatch("[^/]+") do
		sofar = sofar and (sofar .. "/" .. seg) or seg
		if not self:isFolder(sofar) then
			local ok = call(self.Env.makefolder, sofar)
			if not ok or not self:isFolder(sofar) then return false end
		end
	end
	return true
end

local function list(self, folder, wantFolders)
	local out = {}
	local ok, res = call(self.Env.listfiles, folder)
	if not ok or type(res) ~= "table" then return out end
	for _, p in ipairs(res) do
		local name = lastSegment(p)
		if name then
			local full = folder .. "/" .. name
			if self:isFolder(full) == wantFolders then out[#out + 1] = name end
		end
	end
	return out
end

-- the names of the files (not folders) in a folder
function Files:listFiles(folder) return list(self, folder, false) end
-- the names of the folders in a folder
function Files:listFolders(folder) return list(self, folder, true) end

function Files:delete(path)
	local ok, err = call(self.Env.delfile, path)
	if not ok then return false, err end
	return true
end

return Files
