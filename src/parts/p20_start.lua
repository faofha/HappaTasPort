-- ================================================================================================
--  START
-- ================================================================================================
Store.Init()

do -- saved settings / controls / profiler layout
	local saved = Store.LoadSettings()
	Settings.ApplySaved(saved, isValidKeyName)
	if type(saved) == "table" and type(saved.profiler) == "table" then Profiler.LoadConfig(saved.profiler) end
	Env.Guarding = Settings.On("Window Guarding")
	local queued = false
	local function queueSave()
		if queued or Janitor.unloading then return end
		queued = true
		task.delay(0.4, function()
			queued = false
			if Janitor.unloading then return end
			Store.SaveSettings(Settings.Serialize({ profiler = Profiler.SerializeConfig() }))
		end)
	end
	Settings.onAnyChange = queueSave
	Controls.onAnyChange = queueSave
	Profiler.SaveConfig = queueSave
end

UI.RemoveStale()
local Gui = UI.Create()
if not UI.Attach(Gui, true) then
	Gui:Destroy()
	error("[HappaTAS] could not parent the interface anywhere (gethui / CoreGui / PlayerGui)")
end
Janitor.add(Gui)
Typing.Watch(Gui) -- typing a slot name or a setting never triggers HappaTAS keys

-- what HappaTAS changes on the player, so Unload can put it back exactly
local restore = {}
pcall(function() restore.autoJump = LocalPlayer.AutoJumpEnabled end)

local handle = { Version = VERSION }

local function Unload()
	if Janitor.unloading then return end
	pcall(Core.Shutdown)
	pcall(Cursor.Reset)
	pcall(ClientObjects.Disable)
	pcall(Buttons.Disable)
	pcall(ToolSync.ReplayEnd)
	pcall(AnimEngine.Shutdown)
	pcall(Bridge.Restore)
	if restore.autoJump ~= nil then
		pcall(function() LocalPlayer.AutoJumpEnabled = restore.autoJump end)
	end
	Janitor.cleanup()
	if rawget(genv, HANDLE_KEY) == handle then genv[HANDLE_KEY] = nil end
end
handle.Unload = Unload
genv[HANDLE_KEY] = handle -- only the version and Unload are shared, nothing else is reachable

if CONFIG.DisableAutoJump then
	pcall(function() LocalPlayer.AutoJumpEnabled = false end)
end

Bridge.Init()
InputSys.Start(Gui)
Core.Start(Gui)
Menu.Start(Gui, Unload)
Sounds.Init(Gui)
ClientObjects.OnStatus = function(text) Menu.SetStatus(text, true) end
ClientObjects.Start()
Buttons.Start()
Profiler.Start()

local function onCharacter(char)
	task.spawn(function()
		local ok, err = pcall(Core.CharLoad, char)
		if not ok then warnf("character setup failed:", tostring(err)) end
	end)
	AnimEngine.Attach(char)
	ToolSync.AttachCharacter(char)
end
on(LocalPlayer.CharacterAdded, onCharacter)
if LocalPlayer.Character then
	onCharacter(LocalPlayer.Character)
end

if not Store.Ready then
	warnf("File functions are missing or the workspace is not writable: slots can't be saved or loaded.")
end
log("loaded", VERSION, "ui parent:", UI.ParentName, "save folder:", Store.PlacePath)

