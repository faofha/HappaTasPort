-- ================================================================================================
--  CLASSIC BACKGROUND  (HappaTAS 3 ui, Classic Look): a picture or video behind Classic's main menu, from
--  the Background setting:
--    ""                                  none
--    http:// or https:// link            a picture, downloaded ONCE into HappaTasPort/Backgrounds/<hash>.<ext>
--                                        (game:HttpGet: HappaTAS's only network call), then loaded with
--                                        getcustomasset; the saved file is used from then on
--    123 or rbxassetid://123             a Roblox image
--    video:123 or video:rbxassetid://123 a Roblox video, looped and muted
--  Video FILES from links are refused: measured live (2026-11-13) a VideoFrame never loaded an MP4, a VP8 WebM
--  or a VP9 WebM through getcustomasset, while Roblox-hosted videos played at once. The picture sits right
--  behind the menu (same place and size, one ZIndex lower, following it); while one shows, the menu's window
--  colour lies over it at Background Transparency. A failure leaves V2's plain window and says why on the
--  status line. Nothing runs per frame.
-- ================================================================================================
local Env = import("platform/env")

local Background = {}
Background.__index = Background

local FOLDER = "HappaTasPort/Backgrounds"
local NAME = "HappaTASBackground"
local LOAD_TIME = 10
local VIDEO_EXT = { mp4 = true, webm = true, mov = true, mkv = true, ogv = true, avi = true, m4v = true }
local IMAGE_EXT = { png = "png", jpg = "jpg", jpeg = "jpg", bmp = "bmp", tga = "tga" }
local FIT = { Crop = Enum.ScaleType.Crop, Fit = Enum.ScaleType.Fit, Stretch = Enum.ScaleType.Stretch }
local VIDEO_REFUSED = "Roblox can't play video files from links: use a Roblox video id (video:123)"
local NOT_PICTURE = "Background: the link didn't give a picture"

local function trim(t) return (t:gsub("^%s+", ""):gsub("%s+$", "")) end

-- djb2 of the link, 8 hex digits (the saved file's name)
local function hash(t)
	local h = 5381
	for i = 1, #t do h = (h * 33 + t:byte(i)) % 4294967296 end
	return string.format("%08x", h)
end

-- the extension a link names (query and fragment dropped), lower case, or nil
local function extOf(url)
	local p = url:gsub("[?#].*$", "")
	local e = p:match("%.(%w+)$")
	return e and e:lower() or nil
end

-- what a downloaded body is: "png" / "jpg" / "bmp", "video", or nil
local function sniff(body)
	if body:sub(1, 4) == "\137PNG" then return "png" end
	if body:sub(1, 2) == "\255\216" then return "jpg" end
	if body:sub(1, 2) == "BM" then return "bmp" end
	if body:sub(5, 8) == "ftyp" or body:sub(1, 4) == "\26\69\223\163" then return "video" end
	return nil
end

function Background.new(classic)
	local self = setmetatable({ classic = classic, E = classic.E, menu = classic.menu, view = nil, kind = nil, gen = 0,
		menuTransparency = classic.menu.BackgroundTransparency }, Background)
	local s, offs = self.E.settings, classic.offs
	offs[#offs + 1] = s:changed("classicBackground", function() self:load() end)
	offs[#offs + 1] = s:changed("classicBackgroundTransparency", function() self:style() end)
	offs[#offs + 1] = s:changed("classicBackgroundFit", function() self:style() end)
	for _, prop in ipairs({ "Position", "Size", "AnchorPoint", "Visible" }) do
		local c = self.menu:GetPropertyChangedSignal(prop):Connect(function() self:follow() end)
		offs[#offs + 1] = function() c:Disconnect() end
	end
	-- (Classic hidden: the New interface is up or the interface is hidden)
	local ce = classic.gui:GetPropertyChangedSignal("Enabled"):Connect(function() self:follow() end)
	offs[#offs + 1] = function() ce:Disconnect() end
	offs[#offs + 1] = function() self.gen = self.gen + 1 end -- (a download still running finds itself stale)
	self:load()
	return self
end

function Background:status(text) self.classic:status(text) end

function Background:clear()
	if self.view then pcall(function() self.view:Destroy() end) end
	self.view, self.kind = nil, nil
	self:style()
end

-- can the background be seen now (the menu open, Classic the live interface)
function Background:seen()
	return self.menu.Visible == true and self.classic.gui.Enabled == true
end

-- the view on the menu's place; a video plays only while it can be seen (no decoding behind a closed menu)
function Background:follow()
	local v, m = self.view, self.menu
	if not v then return end
	v.AnchorPoint, v.Position, v.Size, v.Visible = m.AnchorPoint, m.Position, m.Size, m.Visible
	if self.kind == "video" then
		local on = self:seen()
		if v.Playing ~= on then pcall(function() if on then v:Play() else v:Pause() end end) end
	end
end

-- transparency and fit (the menu back to V2's transparency without a background)
function Background:style()
	local s, m = self.E.settings, self.menu
	if not self.view then
		m.BackgroundTransparency = self.menuTransparency
		return
	end
	m.BackgroundTransparency = 1 - s:get("classicBackgroundTransparency") / 100
	if self.kind == "image" then self.view.ScaleType = FIT[s:get("classicBackgroundFit")] or Enum.ScaleType.Crop end
end

-- shows `content` (an image or video address); gives up after LOAD_TIME seen without loading (hidden, Roblox
-- may not load it), deleting the saved file a link gave (`path`: the next try downloads it again)
function Background:show(kind, content, gen, path)
	self:clear()
	local v = Instance.new(kind == "video" and "VideoFrame" or "ImageLabel")
	v.Name, v.BorderSizePixel, v.BackgroundTransparency = NAME, 0, 1
	v:SetAttribute("HappaTASNoLook", true)
	v.ZIndex = self.menu.ZIndex - 1
	local mc = self.menu:FindFirstChildWhichIsA("UICorner")
	if mc then
		local cr = Instance.new("UICorner")
		cr.CornerRadius = mc.CornerRadius
		cr.Parent = v
	end
	if kind == "video" then
		v.Video, v.Looped, v.Volume = content, true, 0
	else
		v.Image = content
	end
	v.Parent = self.classic.gui
	self.view, self.kind = v, kind
	self:style()
	self:follow()
	task.spawn(function()
		local t = 0
		while t < LOAD_TIME do
			local ok, loaded = pcall(function() return v.IsLoaded end)
			if not ok or loaded ~= false then return end -- (loaded, or no way to tell)
			task.wait(0.5)
			if self:seen() then t = t + 0.5 end
			if self.gen ~= gen or self.view ~= v then return end
		end
		self:status("Background didn't load")
		self:clear()
		if path and Env.delfile then pcall(Env.delfile, path) end
	end)
end

-- the setting changed: what it is, then show it (a link: the saved file, or download it first)
function Background:load()
	self.gen = self.gen + 1
	local gen = self.gen
	self:clear()
	local v = trim(tostring(self.E.settings:get("classicBackground")))
	if v == "" then return end
	local vid = v:match("^video:%s*rbxassetid://(%d+)$") or v:match("^video:%s*(%d+)$")
	if vid then return self:show("video", "rbxassetid://" .. vid, gen) end
	local img = v:match("^rbxassetid://(%d+)$") or v:match("^(%d+)$")
	if img then return self:show("image", "rbxassetid://" .. img, gen) end
	if not v:lower():match("^https?://") then return self:status("Background: not a link or an id") end
	local ext = extOf(v)
	if ext and VIDEO_EXT[ext] then return self:status(VIDEO_REFUSED) end
	task.spawn(function() self:fetch(v, IMAGE_EXT[ext or ""], gen) end)
end

function Background:fetch(url, ext, gen)
	if not (Env.getcustomasset and Env.writefile and Env.isfile) then
		return self:status("Background links need getcustomasset and the file functions")
	end
	local base = FOLDER .. "/" .. hash(url) .. "."
	-- (saved already: no download)
	for _, e in ipairs(ext and { ext } or { "png", "jpg", "bmp", "tga" }) do
		if Env.isfile(base .. e) then
			local ok, asset = pcall(Env.getcustomasset, base .. e)
			if ok and asset and self.gen == gen then return self:show("image", asset, gen, base .. e) end
		end
	end
	local ok, body = Env.httpGet(url)
	if self.gen ~= gen then return end
	if not ok then return self:status("Background: the download failed (" .. tostring(body):sub(1, 60) .. ")") end
	if type(body) ~= "string" or #body < 16 or body:sub(1, 1) == "<" then return self:status(NOT_PICTURE) end
	local kind = sniff(body)
	if kind == "video" then return self:status(VIDEO_REFUSED) end
	if kind then
		ext = kind
	elseif ext ~= "tga" then
		return self:status(NOT_PICTURE)
	end
	local wrote = pcall(function()
		if Env.makefolder and not (Env.isfolder and Env.isfolder(FOLDER)) then Env.makefolder(FOLDER) end
		Env.writefile(base .. ext, body)
	end)
	if not wrote then return self:status("Background: couldn't save the picture") end
	local okA, asset = pcall(Env.getcustomasset, base .. ext)
	if not okA or not asset then return self:status("Background: couldn't load the saved picture") end
	self:show("image", asset, gen, base .. ext)
end

return Background
