-- ================================================================================================
--  SOUNDS  (keyboard / mouse click feedback)
--  Your own sounds can be used: put key.mp3 / click.mp3 (or .ogg / .wav) in HappaTasPort/Sounds/.
--  The sounds live inside the HappaTAS interface (not in SoundService where game scripts can see them).
-- ================================================================================================
do
	local POOL = 6
	-- checked in the live client: 9119713951 is the audio "Switch 2 (SFX)" (ProSoundEffects). The click used
	-- to be 9119714049, which is a Place, not audio: click sounds never played and Roblox printed "Failed to
	-- load sound ... Asset type does not match requested type" six times on every start. The click is now a
	-- sound file that ships with the Roblox client itself (content/sounds), so it can't go missing.
	local DEFAULT_KEY = "rbxassetid://9119713951"
	local DEFAULT_CLICK = "rbxasset://sounds/clickfast.wav"
	local keyPool, clickPool = {}, {}
	local keyIndex, clickIndex = 1, 1
	local lastKeyClock = 0
	local holder

	function Sounds.Init(parent)
		if holder then return end
		holder = Instance.new("Folder")
		holder.Name = "Sounds"
		holder.Parent = parent
		local keyId = Store.CustomAsset("key") or DEFAULT_KEY
		local clickId = Store.CustomAsset("click") or DEFAULT_CLICK
		for i = 1, POOL do
			local sk = Instance.new("Sound")
			sk.Name = "K" .. i
			sk.SoundId = keyId
			sk.Volume = 0.5
			sk.Parent = holder
			keyPool[i] = sk
			local sc = Instance.new("Sound")
			sc.Name = "C" .. i
			sc.SoundId = clickId
			sc.Volume = 0.5
			sc.Parent = holder
			clickPool[i] = sc
		end
	end

	local function volume()
		return clampn(Settings.Get("Sound Volume") / 100, 0, 1)
	end

	-- trigger mode: 0 = live input, 1 = replayed input, 2 = both
	local function allowed(isLive)
		local m = Settings.Get("Sound Trigger Mode")
		if isLive then return m == 0 or m == 2 end
		return m == 1 or m == 2
	end

	local function playKey()
		if not Settings.On("Enable Keyboard Sounds") or #keyPool == 0 then return end
		local now = os.clock()
		local pace = clampn(now - lastKeyClock, 0.04, 0.5)
		lastKeyClock = now
		local snd = keyPool[keyIndex]
		keyIndex = (keyIndex % POOL) + 1
		local pitch = 1
		if Settings.On("Dynamic Pitch Variation") then
			pitch = clampn(1 + (0.2 - pace) * 0.3 + (math.random() - 0.5) * 0.08, 0.88, 1.15)
		end
		snd.Volume = volume()
		snd.PlaybackSpeed = pitch
		snd:Play()
	end

	local function playClick(isRight)
		if not Settings.On("Enable Click Sounds") or #clickPool == 0 then return end
		local snd = clickPool[clickIndex]
		clickIndex = (clickIndex % POOL) + 1
		local pitch = isRight and 0.95 or 1.05
		if Settings.On("Dynamic Pitch Variation") then pitch = pitch + (math.random() - 0.5) * 0.06 end
		snd.Volume = volume()
		snd.PlaybackSpeed = pitch
		snd:Play()
	end

	local function play(isLive, isMouse, isRight)
		if not holder or not allowed(isLive) then return end
		if Typing.Active() then return end
		pcall(function()
			if isMouse then playClick(isRight) else playKey() end
		end)
	end

	function Sounds.PlayLive(_, isMouse, isRight) play(true, isMouse, isRight) end
	function Sounds.PlayReplay(_, isMouse, isRight) play(false, isMouse, isRight) end
end

