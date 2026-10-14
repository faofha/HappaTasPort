-- ================================================================================================
--  ENVIRONMENT
--  Everything that talks to the executor or to Roblox services is looked up here once.
--  No network functions are used anywhere in this script (no HttpGet / request / loadstring).
-- ================================================================================================
local genv = (type(getgenv) == "function" and getgenv()) or _G
local HANDLE_KEY = "__HappaTAS"

do -- unload an older copy that is still running (re-executing the script)
	local old = rawget(genv, HANDLE_KEY)
	if type(old) == "table" and type(old.Unload) == "function" then
		-- in a thread of its own: the Unload of V2.37.1 and older could take its thread's access to
		-- CoreGui away (see gameCall in the bridge), which would stop this copy using gethui()
		task.spawn(pcall, old.Unload)
	end
end

local cloneref_ = (type(cloneref) == "function") and cloneref or function(x) return x end

local function svc(name)
	local ok, s = pcall(game.GetService, game, name)
	if not ok or s == nil then return nil end
	local ok2, c = pcall(cloneref_, s)
	if ok2 and c ~= nil then return c end
	return s
end

local Players      = svc("Players")
local RunService   = svc("RunService")
local UIS          = svc("UserInputService")
local TweenService = svc("TweenService")
local HttpService  = svc("HttpService")
local StarterGui   = svc("StarterGui")
local GuiService   = svc("GuiService")
local Stats        = svc("Stats")
local TextService  = svc("TextService")
local LocalPlayer  = Players.LocalPlayer
while not LocalPlayer do
	task.wait()
	LocalPlayer = Players.LocalPlayer
end

local Env = {}
do
	local function fn(...)
		for i = 1, select("#", ...) do
			local f = select(i, ...)
			if type(f) == "function" then return f end
		end
		return nil
	end
	local synT = (type(syn) == "table") and syn or {}

	Env.writefile   = fn(writefile)
	Env.readfile    = fn(readfile)
	Env.isfile      = fn(isfile)
	Env.isfolder    = fn(isfolder)
	Env.makefolder  = fn(makefolder)
	Env.listfiles   = fn(listfiles)
	Env.delfile     = fn(delfile)
	Env.lz4compress   = fn(lz4compress, synT.lz4compress)
	Env.lz4decompress = fn(lz4decompress, synT.lz4decompress)
	Env.getcustomasset = fn(getcustomasset, getsynasset)
	Env.gethui      = fn(gethui)
	Env.protectgui  = fn(synT.protect_gui)
	Env.getgc       = fn(getgc)
	Env.filtergc    = fn(filtergc)
	Env.isactive    = fn(isrbxactive, isgameactive, iswindowactive)

	Env.keypress     = fn(keypress, keydown)
	Env.keyrelease   = fn(keyrelease, keyup)
	Env.mouse1press  = fn(mouse1press, mouse1down)
	Env.mouse1release= fn(mouse1release, mouse1up)
	Env.mouse2press  = fn(mouse2press, mouse2down)
	Env.mouse2release= fn(mouse2release, mouse2up)
	Env.mousemoveabs = fn(mousemoveabs)
	Env.mousemoverel = fn(mousemoverel)
	Env.mousescroll  = fn(mousescroll)
	-- Roblox's VirtualInputManager hands a key to Roblox's input with its exact KeyCode (used for the keys
	-- the executor's keypress gets wrong, see the replay in InputSys)
	Env.VirtualInput = svc("VirtualInputManager")

	Env.HasFiles = Env.writefile and Env.readfile and Env.isfile and Env.isfolder and Env.makefolder
		and Env.listfiles and Env.delfile and true or false
	Env.HasLZ4 = (Env.lz4compress ~= nil and Env.lz4decompress ~= nil)

	-- set by the settings module ("Window Guarding")
	Env.Guarding = true
	-- true when the Roblox window has focus (or when the executor can't tell / guarding is off)
	function Env.WindowActive()
		if not Env.Guarding or not Env.isactive then return true end
		local ok, a = pcall(Env.isactive)
		return (not ok) or a ~= false
	end
end

local function log(...)
	if CONFIG.Debug then print("[HappaTAS]", ...) end
end
local function warnf(...)
	warn("[HappaTAS]", ...)
end
-- an error inside a frame handler or a listener: each distinct message is printed once (25 at most),
-- so a problem shows in the console without flooding it every frame
local reported = { n = 0 }
local function reportError(where, err)
	local msg = tostring(where) .. ": " .. tostring(err)
	if reported[msg] or reported.n >= 25 then return end
	reported[msg] = true
	reported.n = reported.n + 1
	warnf(msg)
end

-- ------------------------------------------------------------------------------------------------ janitor
-- Everything that must be undone on Unload is registered here (connections, instances, functions).
local Janitor = { items = {}, unloading = false }

function Janitor.add(x)
	Janitor.items[#Janitor.items + 1] = x
	return x
end

function Janitor.cleanup()
	Janitor.unloading = true
	for i = #Janitor.items, 1, -1 do
		local x = Janitor.items[i]
		pcall(function()
			local t = typeof(x)
			if t == "RBXScriptConnection" then
				x:Disconnect()
			elseif t == "Instance" then
				x:Destroy()
			elseif t == "function" then
				x()
			elseif type(x) == "table" and x.Disconnect then
				x:Disconnect()
			end
		end)
	end
	Janitor.items = {}
end

local function on(signal, fn)
	local c = signal:Connect(fn)
	Janitor.add(c)
	return c
end

-- ------------------------------------------------------------------------------------------------ typing
-- HappaTAS keys do nothing while the player types (chat, any text box) or has the Roblox menu open.
-- UserInputService:GetFocusedTextBox() doesn't see text boxes inside CoreGui, like the new chat bar
-- (TextChatService) or HappaTAS's own slot name and settings boxes (under gethui()), so those are checked
-- directly: ChatInputBarConfiguration.IsFocused ("whether the default chat input bar is focused", Roblox
-- docs) and the Focused / FocusLost events of our own boxes.
local TextChatService = svc("TextChatService")
-- rebinding: a control waits for its new key. boundInput: the key press that gave it the new key; Roblox
-- doesn't promise the order of the InputBegan handlers, so that press is recognised by its InputObject in
-- the handlers that run after the binding took it (found in the live client: it also ran its old control)
local Typing = { own = nil, bar = nil, rebinding = false, boundInput = nil }
do
	local function chatFocused()
		local bar = Typing.bar
		if not (bar and bar.Parent) then
			bar = TextChatService and TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
			Typing.bar = bar
		end
		return bar ~= nil and bar.IsFocused == true
	end
	-- every TextBox under root, also the ones added later (new save slots), counts as one of ours
	function Typing.Watch(root)
		local function add(d)
			if not d:IsA("TextBox") then return end
			-- (these connections go away with the box; the whole interface is destroyed on Unload)
			d.Focused:Connect(function() Typing.own = d end)
			d.FocusLost:Connect(function() if Typing.own == d then Typing.own = nil end end)
		end
		for _, d in ipairs(root:GetDescendants()) do add(d) end
		on(root.DescendantAdded, add)
	end
	function Typing.Active(inp)
		if Typing.rebinding or (inp ~= nil and inp == Typing.boundInput) then return true end
		if UIS:GetFocusedTextBox() ~= nil then return true end -- game text boxes, the old chat
		local own = Typing.own
		if own and own.Parent and own:IsFocused() then return true end
		if GuiService and GuiService.MenuIsOpen then return true end
		local ok, chat = pcall(chatFocused)
		return ok and chat == true
	end
end

-- ------------------------------------------------------------------------------------------------ small helpers
local function r(n, decimal)
	local v = math.round(n * decimal) / decimal
	if v == 0 then v = 0 end -- turns -0 into 0
	return v
end

local function clampn(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local ZERO3 = Vector3.zero

-- ------------------------------------------------------------------------------------------------ module tables
-- Declared up front so every module can call every other one (no forward-reference nil globals).
local Store, Bridge, InputSys, Cursor, AnimEngine = {}, {}, {}, {}, {}
local ClientObjects, Buttons, ToolSync, Sounds, Profiler = {}, {}, {}, {}, {}
local Core, Menu = {}, {}

