-- ================================================================================================
--  SOUNDS  (HappaTAS 3 ui): the New interface's sounds: a click (buttons, switches, choices, dropdown picks), a
--  window opening / closing, a status message. HappaTAS writes its own short sounds as .wav files into
--  HappaTasPort/Sounds once (a file already there is kept, so yours replaces one) and loads them with
--  getcustomasset; nothing is downloaded. They play from the interface's own ScreenGui, only while the New
--  interface is up and "Interface sounds" is on, at "Sound volume". Without getcustomasset or the file
--  functions: silent.
-- ================================================================================================
local Env = import("platform/env")

local Sounds = {}
Sounds.__index = Sounds

local FOLDER = "HappaTasPort/Sounds"
local RATE = 22050

-- 16-bit mono PCM .wav from samples (-1..1)
local function wav(samples)
	local parts = {}
	for i, v in ipairs(samples) do
		local x = math.floor(math.clamp(v, -1, 1) * 32767 + 0.5)
		if x < 0 then x = x + 65536 end
		parts[i] = string.char(x % 256, math.floor(x / 256))
	end
	local data = table.concat(parts)
	local function u32(n) return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256) end
	local function u16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
	return "RIFF" .. u32(36 + #data) .. "WAVE" .. "fmt " .. u32(16) .. u16(1) .. u16(1) .. u32(RATE) .. u32(RATE * 2) .. u16(2) .. u16(16)
		.. "data" .. u32(#data) .. data
end

-- a tone from f0 to f1 Hz over secs, fading out with time constant tau, at amplitude amp
local function sweep(out, secs, f0, f1, tau, amp)
	local n = math.floor(secs * RATE)
	local phase = 0
	for i = 0, n - 1 do
		local t = i / RATE
		local f = f0 + (f1 - f0) * (i / math.max(1, n - 1))
		phase = phase + 2 * math.pi * f / RATE
		local attack = math.min(1, i / (0.002 * RATE)) -- (2 ms: no click at the start)
		out[#out + 1] = math.sin(phase) * amp * attack * math.exp(-t / tau)
	end
	return out
end

local BUILT_IN = {
	click = function() return sweep({}, 0.035, 1900, 1500, 0.007, 0.55) end,
	open = function() return sweep({}, 0.09, 520, 980, 0.03, 0.4) end,
	close = function() return sweep({}, 0.09, 980, 520, 0.03, 0.4) end,
	status = function()
		local out = sweep({}, 0.06, 880, 880, 0.03, 0.35)
		return sweep(out, 0.08, 1320, 1320, 0.035, 0.35)
	end,
}
Sounds.NAMES = { "click", "open", "close", "status" }

function Sounds.new(ui)
	local self = setmetatable({ ui = ui, E = ui.E, sounds = {}, last = nil }, Sounds)
	local asset = Env.getcustomasset
	if not (asset and Env.writefile and Env.isfile) then
		Env.debugNote("getcustomasset or the file functions unavailable; interface sounds off")
		return self
	end
	pcall(function() if Env.makefolder and not (Env.isfolder and Env.isfolder(FOLDER)) then Env.makefolder(FOLDER) end end)
	for _, name in ipairs(Sounds.NAMES) do
		local path = FOLDER .. "/" .. name .. ".wav"
		local ok, err = pcall(function()
			if not Env.isfile(path) then Env.writefile(path, wav(BUILT_IN[name]())) end
			local id = asset(path)
			if type(id) ~= "string" or id == "" then error("no asset id") end
			local snd = Instance.new("Sound")
			snd.Name = "HappaTASSound_" .. name
			snd.SoundId = id
			snd.Volume = 0.5
			snd.Parent = ui.root.gui
			self.sounds[name] = snd
		end)
		if not ok then Env.debugNote("interface sound " .. name .. ": " .. tostring(err)) end
	end
	ui.life:own(function()
		for _, snd in pairs(self.sounds) do pcall(function() snd:Destroy() end) end
		self.sounds = {}
	end)
	return self
end

-- plays one sound (only the New interface, only with Interface sounds on)
function Sounds:play(name)
	local snd = self.sounds[name]
	if not snd then return end
	local s = self.E.settings
	if not s:on("uiSounds") or self.ui.live ~= "New" then return end
	self.last = name
	pcall(function()
		snd.Volume = math.clamp((tonumber(s:get("uiSoundVolume")) or 50) / 100, 0, 1)
		snd.TimePosition = 0
		snd:Play()
	end)
end

return Sounds
