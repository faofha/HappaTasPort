--[[
	HappaTAS - Executor Port  (single file, client side only)

	One script instead of the old two-file setup (initializer + MainModule). Everything that used to run on the
	server (DataStore saving, slots, settings) now runs locally and writes to your executor's workspace folder:

		<workspace>/HappaTasPort/Settings.json         keybinds + settings
		<workspace>/HappaTasPort/<PlaceId>/<Slot>.tas  one compact file per slot, only that place's slots are listed
		                                               (slots saved by earlier versions, <Slot>.json, still load)

	There is no slot limit and no size limit. Needs these executor functions:
		writefile / readfile / isfile / isfolder / makefolder / listfiles / delfile
	Optional (the script works without them, those parts are just skipped):
		lz4compress / lz4decompress       smaller slot files
		keypress / keyrelease / mouse1press / mouse1release / mouse2press / mouse2release /
		mousemoveabs / mousescroll / isrbxactive      replaying the recorded keyboard + mouse while testing
		cloneref, getgenv, gethui

	Your keyboard, right click, mouse wheel and mouse position are recorded with every frame and replayed in test
	mode (three switches in the Settings tab). The keys you bound to the TAS tool itself are never recorded.

	Run it again to reload it (the previous copy unloads itself). Unload from the "More" tab or with
	getgenv().__HappaTAS.Unload()

	Credits: Happy_Liam / happa (HappaTAS), plusgiant5 (TASability), TestMicrowaveDinner (scripting help).
]]

local VERSION = "V2.32"

-- ------------------------------------------------------------------------------------------------ config
local CONFIG = {
	RootFolder      = "HappaTasPort", -- folder inside the executor workspace
	TakeOverAnimate = true,           -- R6 only: swap the game's Animate for the TAS-aware one (exact animation record/replay)
	DisableAutoJump = true,           -- original did StarterPlayer.AutoJumpEnabled = false
	Debug           = false,
}

-- ------------------------------------------------------------------------------------------------ env
local genv = (type(getgenv) == "function" and getgenv()) or _G

do -- unload a previous copy first so re-executing never stacks two TAS tools
	local old = genv.__HappaTAS
	if type(old) == "table" and type(old.Unload) == "function" then
		pcall(old.Unload)
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

local Players          = svc("Players")
local RunService       = svc("RunService")
local UIS              = svc("UserInputService")
local CAS              = svc("ContextActionService")
local TweenService     = svc("TweenService")
local HttpService      = svc("HttpService")
local StarterGui       = svc("StarterGui")
local LocalPlayer      = Players.LocalPlayer
while not LocalPlayer do
	task.wait()
	LocalPlayer = Players.LocalPlayer
end

local function log(...)
	if CONFIG.Debug then print("[HappaTAS]", ...) end
end
local function warnf(...)
	warn("[HappaTAS]", ...)
end

-- ------------------------------------------------------------------------------------------------ janitor
local Janitor = { items = {}, unloading = false }

function Janitor.add(x)
	Janitor.items[#Janitor.items + 1] = x
	return x
end

function Janitor.cleanup()
	Janitor.unloading = true
	for i = #Janitor.items, 1, -1 do
		local x = Janitor.items[i]
		local t = typeof(x)
		pcall(function()
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

-- connect + remember, so Unload() can disconnect everything
local function on(signal, fn)
	local c = signal:Connect(fn)
	Janitor.add(c)
	return c
end

-- run fn in its own thread and swallow nothing: errors still print, but never kill the caller
local function spawn(fn, ...)
	return task.spawn(fn, ...)
end

-- ------------------------------------------------------------------------------------------------ datatype shorthands (used by the generated UI data)
local c  = function(r, g, b) return Color3.fromRGB(r, g, b) end
local u  = UDim2.new
local v2 = Vector2.new
local rc = Rect.new
local ud = UDim.new
local function F(family, weight, style)
	return Font.new(family, Enum.FontWeight:FromValue(weight), Enum.FontStyle:FromValue(style))
end

-- ------------------------------------------------------------------------------------------------ small helpers
local function r(n, decimal) -- round helper from the original
	local round = math.round(n * decimal) / decimal
	if round == -0 then round = 0 end
	return round
end

local function finite(n)
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then return 0 end
	return n
end

local ControlsTable = {
	{ "Idle", "1" },
	{ "Create", "2" },
	{ "Test", "3" },
	{ "Pause", "Left Click" },
	{ "Unpause", "Left Click" },
	{ "Forward", "T" },
	{ "Back", "R" },
	{ "Forward 1 Frame", "G" },
	{ "Back 1 Frame", "F" },
	{ "Unpause 1 Frame", "V" },
	{ "Return", "E" },
	{ "Look Around", "L" },
	{ "Optimize TAS", "Q" },
	{ "Delete TAS", "Backspace" },
	{ "Menu", "M" },
}

local SettingsTable = {
	{ "Lock Camera (Paused)", 1 },
	{ "Lock Camera (Test)", 1 },
	{ "Interpolate Playback", 1 },
	{ "Playback Speed", 1 },
	{ "Show Stats (Idle)", 1 },
	{ "Show Stats (Create)", 1 },
	{ "Show Stats (Test)", 1 },
	{ "Stats Text Size", 11 },
	{ "Restart When Testing", 1 },
	{ "Replay Keyboard", 1 },
	{ "Replay Mouse Clicks", 1 },
	{ "Replay Mouse Movement", 1 },
}

-- key name <-> input tables (the original "Inputs" module)
local ToKey, FromKey = {}, {}
do
	local letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	for i = 1, #letters do
		local ch = letters:sub(i, i)
		ToKey[ch] = Enum.KeyCode[ch]
	end
	local digits = { "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
	for n = 0, 9 do
		ToKey[tostring(n)] = Enum.KeyCode[digits[n + 1]]
	end
	local other = {
		["Return"] = Enum.KeyCode.Return, ["Backspace"] = Enum.KeyCode.Backspace, ["Delete"] = Enum.KeyCode.Delete,
		["-"] = Enum.KeyCode.Minus, ["="] = Enum.KeyCode.Equals, ["'"] = Enum.KeyCode.Quote,
		["/"] = Enum.KeyCode.Slash, ["\\"] = Enum.KeyCode.BackSlash, [";"] = Enum.KeyCode.Semicolon,
		[","] = Enum.KeyCode.Comma, ["."] = Enum.KeyCode.Period, ["["] = Enum.KeyCode.LeftBracket,
		["]"] = Enum.KeyCode.RightBracket, ["LeftControl"] = Enum.KeyCode.LeftControl,
		["RightControl"] = Enum.KeyCode.RightControl, ["Tab"] = Enum.KeyCode.Tab,
		["Left Click"] = Enum.UserInputType.MouseButton1, ["Right Click"] = Enum.UserInputType.MouseButton2,
		["Scroll Click"] = Enum.UserInputType.MouseButton3,
	}
	for k, v in pairs(other) do ToKey[k] = v end
	for k, v in pairs(ToKey) do FromKey[v] = k end -- (the original mapped the 0 key to "10" by mistake; fixed here)
end
-- GENERATED from MainModule.rbxm (TASUserInterface). Styles are shared property sets; every node is
-- {ClassName, Name, StyleId, InstanceProps, Children}
local UI_STYLES = {
	[1] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,35,73),BackgroundTransparency=0.2,BorderColor3=c(27,42,53),BorderSizePixel=0,ClipsDescendants=false,Rotation=0}},
	[2] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",500,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=0,TextYAlignment=1,LineHeight=1}},
	[3] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",700,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=0,TextYAlignment=1,LineHeight=1}},
	[4] = {"TextButton", {Active=true,AutomaticSize=0,BackgroundColor3=c(0,41,91),BackgroundTransparency=0.5,BorderColor3=c(27,42,53),BorderSizePixel=0,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/SourceSansPro.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[5] = {"UICorner", {TopLeftRadius=ud(0,8),TopRightRadius=ud(0,8),BottomLeftRadius=ud(0,8),BottomRightRadius=ud(0,8)}},
	[6] = {"UIStroke", {ApplyStrokeMode=1,BorderOffset=ud(0,0),BorderStrokePosition=0,Color=c(0,77,205),Enabled=true,LineJoinMode=0,StrokeSizingMode=0,Thickness=1,Transparency=0.5}},
	[7] = {"UIStroke", {ApplyStrokeMode=0,BorderOffset=ud(0,0),BorderStrokePosition=0,Color=c(0,141,237),Enabled=true,LineJoinMode=0,StrokeSizingMode=0,Thickness=1,Transparency=0}},
	[8] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,35,73),BackgroundTransparency=0.2,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0}},
	[9] = {"UIListLayout", {FillDirection=1,HorizontalAlignment=1,HorizontalFlex=0,ItemLineAlignment=0,Padding=ud(0,0),SortOrder=0,VerticalAlignment=1,VerticalFlex=0,Wraps=false}},
	[10] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=0,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=0,TextYAlignment=1,LineHeight=1}},
	[11] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=true,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=2,TextYAlignment=1,LineHeight=1}},
	[12] = {"Folder", {}},
	[13] = {"TextButton", {Active=true,AutomaticSize=0,BackgroundColor3=c(0,35,73),BackgroundTransparency=0.2,BorderColor3=c(255,255,255),BorderSizePixel=0,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",700,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[14] = {"ImageLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,ImageColor3=c(255,255,255),ImageTransparency=0,ResampleMode=0,ScaleType=0,SliceCenter=rc(0,0,0,0),SliceScale=1,TileSize=u(1,0,1,0)}},
	[15] = {"ImageLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=185,ImageColor3=c(255,255,255),ImageTransparency=0,ResampleMode=0,ScaleType=0,SliceCenter=rc(0,0,0,0),SliceScale=1,TileSize=u(1,0,1,0)}},
	[16] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",700,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=2,TextYAlignment=1,LineHeight=1}},
	[17] = {"UIStroke", {ApplyStrokeMode=0,BorderOffset=ud(0,0),BorderStrokePosition=0,Color=c(0,77,205),Enabled=true,LineJoinMode=0,StrokeSizingMode=0,Thickness=1,Transparency=0}},
	[18] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=2,TextYAlignment=1,LineHeight=1}},
	[19] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0}},
	[20] = {"TextButton", {Active=true,AutomaticSize=0,BackgroundColor3=c(0,52,129),BackgroundTransparency=0.5,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[21] = {"UICorner", {TopLeftRadius=ud(0,12),TopRightRadius=ud(0,12),BottomLeftRadius=ud(0,12),BottomRightRadius=ud(0,12)}},
	[22] = {"UIStroke", {ApplyStrokeMode=1,BorderOffset=ud(0,0),BorderStrokePosition=0,Color=c(255,255,255),Enabled=true,LineJoinMode=0,StrokeSizingMode=0,Thickness=1,Transparency=0.5}},
	[23] = {"TextButton", {Active=true,AutomaticSize=0,BackgroundColor3=c(142,11,0),BackgroundTransparency=0.5,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[24] = {"TextButton", {Active=false,AutomaticSize=0,BackgroundColor3=c(100,0,0),BackgroundTransparency=0.2,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=true,Rotation=0,FontFace=F("rbxasset://fonts/families/LegacyArial.json",400,0),RichText=false,TextColor3=c(27,42,53),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0.2,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[25] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=0,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",700,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1}},
	[26] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,77,205),BackgroundTransparency=0,BorderColor3=c(27,42,53),BorderSizePixel=0,ClipsDescendants=false,Rotation=0}},
	[27] = {"TextButton", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,0,0),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=0,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[28] = {"TextButton", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,0,0),BackgroundTransparency=0.75,BorderColor3=c(27,42,53),BorderSizePixel=0,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[29] = {"ScrollingFrame", {Active=true,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=0,ClipsDescendants=true,Rotation=0,AutomaticCanvasSize=0,BottomImage="rbxasset://textures/ui/Scroll/scroll-bottom.png",ElasticBehavior=0,HorizontalScrollBarInset=0,MidImage="rbxasset://textures/ui/Scroll/scroll-middle.png",ScrollBarImageColor3=c(0,0,0),ScrollBarImageTransparency=0,ScrollBarThickness=12,ScrollingDirection=4,ScrollingEnabled=true,TopImage="rbxasset://textures/ui/Scroll/scroll-top.png",VerticalScrollBarInset=0,VerticalScrollBarPosition=0}},
	[30] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1}},
	[31] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,41,91),BackgroundTransparency=0.2,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0}},
	[32] = {"UIListLayout", {FillDirection=1,HorizontalAlignment=1,HorizontalFlex=0,ItemLineAlignment=0,Padding=ud(0,0),SortOrder=2,VerticalAlignment=1,VerticalFlex=0,Wraps=false}},
	[33] = {"UIStroke", {ApplyStrokeMode=0,BorderOffset=ud(0,0),BorderStrokePosition=0,Color=c(0,169,244),Enabled=true,LineJoinMode=0,StrokeSizingMode=0,Thickness=1,Transparency=0}},
	[34] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,0,0),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=true,Rotation=0}},
	[35] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=0,TextYAlignment=1,LineHeight=1}},
	[36] = {"TextButton", {Active=true,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=0.5,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(0,0,0),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[37] = {"UICorner", {TopLeftRadius=ud(100,100),TopRightRadius=ud(100,100),BottomLeftRadius=ud(100,100),BottomRightRadius=ud(100,100)}},
	[38] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=0,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0}},
	[39] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,196,248),BackgroundTransparency=0.5,BorderColor3=c(27,42,53),BorderSizePixel=0,ClipsDescendants=false,Rotation=0}},
	[40] = {"TextBox", {Active=true,AutomaticSize=0,BackgroundColor3=c(0,52,129),BackgroundTransparency=0.5,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1,ClearTextOnFocus=true,MultiLine=false,PlaceholderColor3=c(178,178,178),ShowNativeInput=true,TextEditable=true}},
	[41] = {"UIStroke", {ApplyStrokeMode=1,BorderOffset=ud(0,0),BorderStrokePosition=0,Color=c(0,169,244),Enabled=true,LineJoinMode=0,StrokeSizingMode=0,Thickness=1,Transparency=0.8}},
	[42] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,41,91),BackgroundTransparency=0.5,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0}},
	[43] = {"UIListLayout", {FillDirection=1,HorizontalAlignment=1,HorizontalFlex=0,ItemLineAlignment=0,Padding=ud(0,5),SortOrder=2,VerticalAlignment=1,VerticalFlex=0,Wraps=false}},
	[44] = {"UIListLayout", {FillDirection=1,HorizontalAlignment=1,HorizontalFlex=0,ItemLineAlignment=0,Padding=ud(0,5),SortOrder=0,VerticalAlignment=1,VerticalFlex=0,Wraps=false}},
	[45] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,0,0),BackgroundTransparency=0.75,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=true,Rotation=0}},
	[46] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,0,0),BackgroundTransparency=0.75,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0}},
	[47] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=0,TextYAlignment=1,LineHeight=1}},
	[48] = {"UIStroke", {ApplyStrokeMode=1,BorderOffset=ud(0,0),BorderStrokePosition=0,Color=c(0,196,248),Enabled=true,LineJoinMode=0,StrokeSizingMode=0,Thickness=1,Transparency=0.5}},
	[49] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=0,TextYAlignment=0,LineHeight=1}},
	[50] = {"TextButton", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,41,91),BackgroundTransparency=0.5,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/LegacyArial.json",400,0),RichText=false,TextColor3=c(27,42,53),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0.75,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[51] = {"TextLabel", {Active=true,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=0,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/LegacyArial.json",400,0),RichText=false,TextColor3=c(0,0,0),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1}},
	[52] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,41,91),BackgroundTransparency=0.75,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0}},
	[53] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=true,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=0,TextYAlignment=0,LineHeight=1}},
	[54] = {"TextButton", {Active=true,AutomaticSize=0,BackgroundColor3=c(0,52,129),BackgroundTransparency=0,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[55] = {"Frame", {Active=true,AutomaticSize=0,BackgroundColor3=c(0,52,129),BackgroundTransparency=0,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0}},
	[56] = {"TextButton", {Active=true,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[57] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=0.5,BorderColor3=c(27,42,53),BorderSizePixel=0,ClipsDescendants=false,Rotation=0}},
	[58] = {"ImageButton", {Active=true,AutomaticSize=0,BackgroundColor3=c(163,162,165),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,ImageColor3=c(255,255,255),ImageTransparency=0,ResampleMode=0,ScaleType=3,SliceCenter=rc(0,0,0,0),SliceScale=1,TileSize=u(1,0,1,0),AutoButtonColor=true,HoverImage="",PressedImage=""}},
	[59] = {"TextLabel", {Active=true,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=0,TextYAlignment=1,LineHeight=1}},
	[60] = {"TextBox", {Active=true,AutomaticSize=0,BackgroundColor3=c(0,52,129),BackgroundTransparency=0.5,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=2,TextYAlignment=1,LineHeight=1,ClearTextOnFocus=true,MultiLine=false,PlaceholderColor3=c(178,178,178),ShowNativeInput=true,TextEditable=true}}
}
local UI_TREE = {
		{"Frame","JoinMessage",1,{Position=u(0,10,1,150),Size=u(0,280,0,75),AnchorPoint=v2(0,1)},{
			{"TextLabel","M",2,{Position=u(0,15,0,40),Size=u(0,200,0,30),Text="M - Main Menu",TextSize=20}},
			{"TextLabel","Title",3,{Position=u(0,15,0,5),Size=u(0,220,0,30),Text="HappaTAS Loaded",TextSize=20}},
			{"TextButton","Close",4,{Position=u(1,-5,0,5),Size=u(0,30,0,30),AnchorPoint=v2(1,0),ZIndex=2,Text="X",TextSize=14},{
				{"UICorner","UICorner",5,{}},
				{"UIStroke","UIStroke",6,{}}
			}},
			{"UICorner","UICorner",5,{}},
			{"TextLabel","FailureMessage",2,{Position=u(0,15,0,65),Size=u(0,250,0,40),Visible=false,Text="Note: your executor has no file functions, so saving to disk is disabled (recording and testing still work).",TextSize=12}},
			{"UIStroke","UIStroke",7,{}}
		}},
		{"Frame","IdleStats",8,{Position=u(1,-10,1,-10),Size=u(0,240,0,144),AnchorPoint=v2(1,1),Visible=false},{
			{"UIListLayout","UIListLayout",9,{}},
			{"TextLabel","2",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Root Position: ",TextSize=11}},
			{"TextLabel","3",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Root Rotation:",TextSize=11}},
			{"TextLabel","4",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Root Linear Velocity:",TextSize=11}},
			{"TextLabel","5",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Root Angular Velocity:",TextSize=11}},
			{"TextLabel","7",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Humanoid State: ",TextSize=11}},
			{"TextLabel","8",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Zoom:",TextSize=11}},
			{"UICorner","UICorner",5,{}},
			{"TextLabel","1",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Frame Time: ",TextSize=11}},
			{"TextLabel","6",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Camera Rotation: ",TextSize=11}}
		}},
		{"Frame","TestStats",8,{Position=u(1,-10,1,-10),Size=u(0,240,0,54),AnchorPoint=v2(1,1),Visible=false},{
			{"UIListLayout","UIListLayout",9,{}},
			{"UICorner","UICorner",5,{}},
			{"TextLabel","1",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Time: ",TextSize=11}},
			{"TextLabel","2",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Playback Speed: ",TextSize=11}},
			{"TextLabel","3",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Keys: ",TextSize=11}},
			{"TextLabel","4",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Mouse: ",TextSize=11}}
		}},
		{"TextLabel","Status",11,{Position=u(0.5,0,1,-10),Size=u(0.8,0,0,35),AnchorPoint=v2(0.5,1),Text="",TextSize=30}},
		{"Folder","Mobile",12,{},{
			{"Folder","MobileCreate",12,{},{
				{"TextButton","Pause",13,{Position=u(0.00664428,0,0.381293,0),Size=u(0.15625,0,0.075528,0),Visible=false,Text="",TextSize=30},{
					{"UICorner","UICorner",5,{}},
					{"ImageLabel","Icon",14,{Position=u(0.357,0,0.132,0),Size=u(0.285338,0,0.7,0),Image="rbxassetid://10392248278"}}
				}},
				{"TextButton","Back",13,{Position=u(0.00664428,0,0.237446,0),Size=u(0.0733061,0,0.062283,0),Visible=false,Text="<<",TextSize=30},{
					{"UICorner","UICorner",5,{}}
				}},
				{"TextButton","Forward",13,{Position=u(0.0895882,0,0.237446,0),Size=u(0.0733061,0,0.062283,0),Visible=false,Text=">>",TextSize=30},{
					{"UICorner","UICorner",5,{}}
				}},
				{"TextButton","Back1Frame",13,{Position=u(0.0074832,0,0.308445,0),Size=u(0.0733061,0,0.062283,0),Visible=false,Text="<",TextSize=30},{
					{"UICorner","UICorner",5,{}}
				}},
				{"TextButton","Forward1Frame",13,{Position=u(0.0905369,0,0.308445,0),Size=u(0.0733061,0,0.062283,0),Visible=false,Text=">",TextSize=30},{
					{"UICorner","UICorner",5,{}}
				}},
				{"TextButton","Unpause1Frame",13,{Position=u(0.0900725,0,0.162749,0),Size=u(0.0733061,0,0.062283,0),Visible=false,Text="II 1",TextSize=30},{
					{"UICorner","UICorner",5,{}}
				}},
				{"TextButton","Return",13,{Position=u(0.00748319,0,0.162749,0),Size=u(0.0733061,0,0.062283,0),Visible=false,Text="",TextSize=30},{
					{"UICorner","UICorner",5,{}},
					{"ImageLabel","Icon",15,{Position=u(0.129391,0,0.0531647,0),Size=u(0.725668,0,0.858582,0),Image="rbxassetid://6933655858"}}
				}},
				{"TextButton","LookAround",13,{Position=u(0.177126,0,0.162749,0),Size=u(0.0733061,0,0.062283,0),Visible=false,Text="",TextSize=30},{
					{"UICorner","UICorner",5,{}},
					{"ImageLabel","Icon",14,{Position=u(0.22074,0,0.0531647,0),Size=u(0.542971,0,0.858582,0),Image="rbxassetid://6523858394"}}
				}}
			}},
			{"Folder","MobileModes",12,{},{
				{"TextButton","Mode1Mobile",13,{Position=u(0.0078125,0,0.540233,0),Size=u(0.041005,0,0.0639386,0),Visible=false,Text="1",TextSize=30},{
					{"UICorner","UICorner",5,{}}
				}},
				{"TextButton","Mode2Mobile",13,{Position=u(0.065,0,0.54,0),Size=u(0.041,0,0.064,0),Visible=false,Text="2",TextSize=30},{
					{"UICorner","UICorner",5,{}}
				}},
				{"TextButton","Mode3Mobile",13,{Position=u(0.122483,0,0.538577,0),Size=u(0.041,0,0.064,0),Visible=false,Text="3",TextSize=30},{
					{"UICorner","UICorner",5,{}}
				}}
			}},
			{"Folder","MobileOptions",12,{},{
				{"TextButton","Delete",13,{Position=u(0.174869,0,0.553478,0),Size=u(0.111346,0,0.049038,0),Visible=false,Text="Delete",TextSize=30},{
					{"UICorner","UICorner",5,{}}
				}},
				{"TextButton","Optimize",13,{Position=u(0.174869,0,0.614736,0),Size=u(0.111313,0,0.049038,0),Visible=false,Text="Optimize",TextSize=30},{
					{"UICorner","UICorner",5,{}}
				}}
			}},
			{"TextButton","MenuOpener",13,{Position=u(0.0078125,0,0.468031,0),Size=u(0.15625,0,0.0639386,0),Visible=false,Text="Menu",TextSize=30},{
				{"UICorner","UICorner",5,{}}
			}},
			{"TextButton","More",13,{Position=u(0.17408,0,0.467385,0),Size=u(0.111221,0,0.075528,0),Visible=false,Text="More",TextSize=30},{
				{"UICorner","UICorner",5,{}}
			}}
		}},
		{"Frame","Merge",8,{Position=u(0.5,0,0.5,0),Size=u(0,400,0,230),AnchorPoint=v2(0.5,0.5),Visible=false},{
			{"TextLabel","Title",16,{Position=u(0,15,0,5),Size=u(0,370,0,30),Text="Merge",TextSize=20}},
			{"UICorner","UICorner",5,{}},
			{"UIStroke","UIStroke",17,{}},
			{"TextLabel","Desc",18,{Position=u(0,15,0,35),Size=u(0,370,0,100),Text="You can only merge a TAS before or after your currently loaded TAS if you are standing (idle or walking) at the endpoint where it will be merged. You will be forced to record a smooth transition inbetween segments.",TextSize=19}},
			{"Frame","Options",19,{Position=u(0,0,0,150),Size=u(1,0,0,30)},{
				{"TextButton","Before",20,{Position=u(0.25,0,0.5,0),Size=u(0.4,0,0.8,0),AnchorPoint=v2(0.5,0.5),Text="Merge Before",TextSize=16},{
					{"UICorner","UICorner",21,{}},
					{"UIStroke","UIStroke",22,{}}
				}},
				{"TextButton","After",20,{Position=u(0.75,0,0.5,0),Size=u(0.4,0,0.8,0),AnchorPoint=v2(0.5,0.5),Text="Merge After",TextSize=16},{
					{"UICorner","UICorner",21,{}},
					{"UIStroke","UIStroke",22,{}}
				}}
			}},
			{"TextButton","Cancel",23,{Position=u(0.5,0,0,200),Size=u(0.4,0,0,24),AnchorPoint=v2(0.5,0.5),Text="Cancel",TextSize=16},{
				{"UICorner","UICorner",21,{}},
				{"UIStroke","UIStroke",22,{}}
			}}
		}},
		{"Frame","CreateStats",8,{Position=u(1,-10,1,-10),Size=u(0,240,0,180),AnchorPoint=v2(1,1),Visible=false},{
			{"UIListLayout","UIListLayout",9,{}},
			{"TextLabel","3",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Total Time:",TextSize=11}},
			{"TextLabel","5",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Root Rotation:",TextSize=11}},
			{"TextLabel","6",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Root Linear Velocity:",TextSize=11}},
			{"TextLabel","7",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Root Angular Velocity:",TextSize=11}},
			{"TextLabel","9",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Humanoid State: ",TextSize=11}},
			{"TextLabel","91",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Zoom:",TextSize=11}},
			{"UICorner","UICorner",5,{}},
			{"TextLabel","2",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Frame Time:",TextSize=11}},
			{"TextLabel","1",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Frame: ",TextSize=11}},
			{"TextLabel","4",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Root Position: ",TextSize=11}},
			{"TextLabel","8",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Camera Rotation: ",TextSize=11}},
			{"TextLabel","92",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Keys: ",TextSize=11}},
			{"TextLabel","93",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Mouse: ",TextSize=11}}
		}},
		{"TextButton","MergeStats",24,{Position=u(1,-10,1,-200),Size=u(0,240,0,54),AnchorPoint=v2(1,1),Visible=false,Text="",TextSize=8},{
			{"UIListLayout","UIListLayout",9,{}},
			{"TextLabel","3",25,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Click here to cancel merge",TextSize=11}},
			{"UICorner","UICorner",5,{}},
			{"TextLabel","2",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Distance Required: ",TextSize=11}},
			{"TextLabel","1",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Current Distance: ",TextSize=11}}
		}},
		{"Frame","MainMenu",8,{Position=u(0.5,0,0.5,0),Size=u(0,400,0,400),AnchorPoint=v2(0.5,0.5),Visible=false},{
			{"TextLabel","Title",16,{Position=u(0,15,0,5),Size=u(0,370,0,30),Text="HappaTAS",TextSize=20}},
			{"UICorner","UICorner",5,{}},
			{"Frame","Line",26,{Position=u(0,0,0,40),Size=u(0,400,0,1)}},
			{"TextButton","ControlsToggle",27,{Position=u(0,0,0,41),Size=u(0,80,0,30),ZIndex=3,Text="Controls",TextSize=15}},
			{"TextButton","SettingsToggle",28,{Position=u(0,80,0,41),Size=u(0,80,0,30),ZIndex=3,Text="Settings",TextSize=15}},
			{"TextButton","SavesToggle",28,{Position=u(0,160,0,41),Size=u(0,80,0,30),ZIndex=3,Text="Saves",TextSize=15}},
			{"ScrollingFrame","ControlsFrame",29,{Position=u(0,0,0,71),Size=u(0,400,1,-71),CanvasSize=u(0,0,0,0)},{
				{"TextLabel","Instruct",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Click on any control to change the keybind.",TextSize=14}},
				{"Frame","List",31,{Position=u(0,20,0,40),Size=u(0,360,0,450)},{
					{"UIListLayout","UIListLayout",32,{}},
					{"UICorner","UICorner",5,{}},
					{"UIStroke","UIStroke",33,{}}
				}}
			}},
			{"ScrollingFrame","SettingsFrame",29,{Position=u(0,0,0,71),Size=u(0,400,1,-71),Visible=false,CanvasSize=u(0,0,0,0)},{
				{"Frame","List",31,{Position=u(0,20,0,20),Size=u(0,360,0,360)},{
					{"UIListLayout","UIListLayout",9,{}},
					{"UICorner","UICorner",5,{}},
					{"UIStroke","UIStroke",33,{}},
					{"Frame","Lock Camera (Paused)",34,{Position=u(0,0,0,0),Size=u(1,0,0,30)},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",35,{Position=u(0,10,0,0),Size=u(0.75,0,1,0),Text="Lock Camera (Paused)",TextSize=16}},
						{"TextButton","Switch",36,{Position=u(0.9,0,0.5,0),Size=u(0,30,0,15),AnchorPoint=v2(0.5,0.5),Text="",TextSize=13},{
							{"UICorner","UICorner",37,{}},
							{"Frame","Switcher",38,{Position=u(0,0,0.5,0),Size=u(0,22,0,22),AnchorPoint=v2(0.5,0.5)},{
								{"UICorner","UICorner",37,{}}
							}}
						}},
						{"Frame","Border",39,{Position=u(0,0,1,0),Size=u(1,0,0,1),AnchorPoint=v2(0,1)}}
					}},
					{"Frame","Lock Camera (Test)",34,{Position=u(0,0,0,0),Size=u(1,0,0,30)},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",35,{Position=u(0,10,0,0),Size=u(0.75,0,1,0),Text="Lock Camera (Test)",TextSize=16}},
						{"TextButton","Switch",36,{Position=u(0.9,0,0.5,0),Size=u(0,30,0,15),AnchorPoint=v2(0.5,0.5),Text="",TextSize=13},{
							{"UICorner","UICorner",37,{}},
							{"Frame","Switcher",38,{Position=u(0,0,0.5,0),Size=u(0,22,0,22),AnchorPoint=v2(0.5,0.5)},{
								{"UICorner","UICorner",37,{}}
							}}
						}},
						{"Frame","Border",39,{Position=u(0,0,1,0),Size=u(1,0,0,1),AnchorPoint=v2(0,1)}}
					}},
					{"Frame","Playback Speed",34,{Position=u(0,0,0,0),Size=u(1,0,0,30)},{
						{"UICorner","UICorner",5,{}},
						{"TextBox","Input",40,{Position=u(0.9,0,0.5,0),Size=u(0.15,0,0.7,0),AnchorPoint=v2(0.5,0.5),Text="1",TextSize=13,PlaceholderText=""},{
							{"UICorner","UICorner",5,{}},
							{"UIStroke","UIStroke",41,{}}
						}},
						{"TextLabel","N",35,{Position=u(0,10,0,0),Size=u(0.75,0,1,0),Text="Playback Speed",TextSize=16}},
						{"Frame","Border",39,{Position=u(0,0,1,0),Size=u(1,0,0,1),AnchorPoint=v2(0,1)}}
					}},
					{"Frame","Restart When Testing",34,{Position=u(0,0,0,0),Size=u(1,0,0,30)},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",35,{Position=u(0,10,0,0),Size=u(0.75,0,1,0),Text="Restart When Testing",TextSize=16}},
						{"Frame","Border",39,{Position=u(0,0,1,0),Size=u(1,0,0,1),AnchorPoint=v2(0,1)}},
						{"TextButton","Switch",36,{Position=u(0.9,0,0.5,0),Size=u(0,30,0,15),AnchorPoint=v2(0.5,0.5),Text="",TextSize=13},{
							{"UICorner","UICorner",37,{}},
							{"Frame","Switcher",38,{Position=u(0,0,0.5,0),Size=u(0,22,0,22),AnchorPoint=v2(0.5,0.5)},{
								{"UICorner","UICorner",37,{}}
							}}
						}}
					}},
					{"Frame","Show Stats (Create)",34,{Position=u(0,0,0,0),Size=u(1,0,0,30)},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",35,{Position=u(0,10,0,0),Size=u(0.75,0,1,0),Text="Show Stats (Create)",TextSize=16}},
						{"Frame","Border",39,{Position=u(0,0,1,0),Size=u(1,0,0,1),AnchorPoint=v2(0,1)}},
						{"TextButton","Switch",36,{Position=u(0.9,0,0.5,0),Size=u(0,30,0,15),AnchorPoint=v2(0.5,0.5),Text="",TextSize=13},{
							{"UICorner","UICorner",37,{}},
							{"Frame","Switcher",38,{Position=u(0,0,0.5,0),Size=u(0,22,0,22),AnchorPoint=v2(0.5,0.5)},{
								{"UICorner","UICorner",37,{}}
							}}
						}}
					}},
					{"Frame","Show Stats (Idle)",34,{Position=u(0,0,0,0),Size=u(1,0,0,30)},{
						{"UICorner","UICorner",5,{}},
						{"Frame","Border",39,{Position=u(0,0,1,0),Size=u(1,0,0,1),AnchorPoint=v2(0,1)}},
						{"TextButton","Switch",36,{Position=u(0.9,0,0.5,0),Size=u(0,30,0,15),AnchorPoint=v2(0.5,0.5),Text="",TextSize=13},{
							{"UICorner","UICorner",37,{}},
							{"Frame","Switcher",38,{Position=u(0,0,0.5,0),Size=u(0,22,0,22),AnchorPoint=v2(0.5,0.5)},{
								{"UICorner","UICorner",37,{}}
							}}
						}},
						{"TextLabel","N",35,{Position=u(0,10,0,0),Size=u(0.75,0,1,0),Text="Show Stats (Idle)",TextSize=16}}
					}},
					{"Frame","Show Stats (Test)",34,{Position=u(0,0,0,0),Size=u(1,0,0,30)},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",35,{Position=u(0,10,0,0),Size=u(0.75,0,1,0),Text="Show Stats (Test)",TextSize=16}},
						{"Frame","Border",39,{Position=u(0,0,1,0),Size=u(1,0,0,1),AnchorPoint=v2(0,1)}},
						{"TextButton","Switch",36,{Position=u(0.9,0,0.5,0),Size=u(0,30,0,15),AnchorPoint=v2(0.5,0.5),Text="",TextSize=13},{
							{"UICorner","UICorner",37,{}},
							{"Frame","Switcher",38,{Position=u(0,0,0.5,0),Size=u(0,22,0,22),AnchorPoint=v2(0.5,0.5)},{
								{"UICorner","UICorner",37,{}}
							}}
						}}
					}},
					{"Frame","Stats Text Size",34,{Position=u(0,0,0,0),Size=u(1,0,0,30)},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",35,{Position=u(0,10,0,0),Size=u(0.75,0,1,0),Text="Stats Text Size",TextSize=16}},
						{"TextBox","Input",40,{Position=u(0.9,0,0.5,0),Size=u(0.15,0,0.7,0),AnchorPoint=v2(0.5,0.5),Text="11",TextSize=13,PlaceholderText=""},{
							{"UICorner","UICorner",5,{}},
							{"UIStroke","UIStroke",41,{}}
						}}
					}},
					{"Frame","Interpolate Playback",34,{Position=u(0,0,0,0),Size=u(1,0,0,30)},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",35,{Position=u(0,10,0,0),Size=u(0.75,0,1,0),Text="Interpolate Playback",TextSize=16}},
						{"Frame","Border",39,{Position=u(0,0,1,0),Size=u(1,0,0,1),AnchorPoint=v2(0,1)}},
						{"TextButton","Switch",36,{Position=u(0.9,0,0.5,0),Size=u(0,30,0,15),AnchorPoint=v2(0.5,0.5),Text="",TextSize=13},{
							{"UICorner","UICorner",37,{}},
							{"Frame","Switcher",38,{Position=u(0,0,0.5,0),Size=u(0,22,0,22),AnchorPoint=v2(0.5,0.5)},{
								{"UICorner","UICorner",37,{}}
							}}
						}}
					}},
					{"Frame","Replay Keyboard",34,{Position=u(0,0,0,0),Size=u(1,0,0,30)},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",35,{Position=u(0,10,0,0),Size=u(0.75,0,1,0),Text="Replay Keyboard",TextSize=16}},
						{"Frame","Border",39,{Position=u(0,0,1,0),Size=u(1,0,0,1),AnchorPoint=v2(0,1)}},
						{"TextButton","Switch",36,{Position=u(0.9,0,0.5,0),Size=u(0,30,0,15),AnchorPoint=v2(0.5,0.5),Text="",TextSize=13},{
							{"UICorner","UICorner",37,{}},
							{"Frame","Switcher",38,{Position=u(0,0,0.5,0),Size=u(0,22,0,22),AnchorPoint=v2(0.5,0.5)},{
								{"UICorner","UICorner",37,{}}
							}}
						}}
					}},
					{"Frame","Replay Mouse Clicks",34,{Position=u(0,0,0,0),Size=u(1,0,0,30)},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",35,{Position=u(0,10,0,0),Size=u(0.75,0,1,0),Text="Replay Mouse Clicks",TextSize=16}},
						{"Frame","Border",39,{Position=u(0,0,1,0),Size=u(1,0,0,1),AnchorPoint=v2(0,1)}},
						{"TextButton","Switch",36,{Position=u(0.9,0,0.5,0),Size=u(0,30,0,15),AnchorPoint=v2(0.5,0.5),Text="",TextSize=13},{
							{"UICorner","UICorner",37,{}},
							{"Frame","Switcher",38,{Position=u(0,0,0.5,0),Size=u(0,22,0,22),AnchorPoint=v2(0.5,0.5)},{
								{"UICorner","UICorner",37,{}}
							}}
						}}
					}},
					{"Frame","Replay Mouse Movement",34,{Position=u(0,0,0,0),Size=u(1,0,0,30)},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",35,{Position=u(0,10,0,0),Size=u(0.75,0,1,0),Text="Replay Mouse Movement",TextSize=16}},
						{"Frame","Border",39,{Position=u(0,0,1,0),Size=u(1,0,0,1),AnchorPoint=v2(0,1)}},
						{"TextButton","Switch",36,{Position=u(0.9,0,0.5,0),Size=u(0,30,0,15),AnchorPoint=v2(0.5,0.5),Text="",TextSize=13},{
							{"UICorner","UICorner",37,{}},
							{"Frame","Switcher",38,{Position=u(0,0,0.5,0),Size=u(0,22,0,22),AnchorPoint=v2(0.5,0.5)},{
								{"UICorner","UICorner",37,{}}
							}}
						}}
					}}
				}}
			}},
			{"ScrollingFrame","SavesFrame",29,{Position=u(0,0,0,71),Size=u(0,400,1,-71),Visible=false,CanvasSize=u(0,0,4,0)},{
				{"Frame","YourSlots",42,{Position=u(0,20,0,20),Size=u(0,360,0,30)},{
					{"UIListLayout","UIListLayout",43,{}},
					{"UICorner","UICorner",5,{}},
					{"UIStroke","UIStroke",33,{}},
					{"Frame","Top",19,{Position=u(0,0,0,0),Size=u(1,0,0,30)},{
						{"TextLabel","Title",30,{Position=u(0,0,0,0),Size=u(0.333,0,1,0),Text="Your Slots",TextSize=16}},
						{"TextLabel","Count",30,{Position=u(0.333,0,0,0),Size=u(0.333,0,1,0),Text="0 slots",TextSize=16}},
						{"TextButton","AddSlot",20,{Position=u(0.8325,0,0.5,0),Size=u(0.3,0,0.7,0),AnchorPoint=v2(0.5,0.5),Text="Add Slot",TextSize=16},{
							{"UICorner","UICorner",21,{}},
							{"UIStroke","UIStroke",22,{}}
						}}
					}}
				}}
			}},
			{"TextButton","HelpToggle",28,{Position=u(0,240,0,41),Size=u(0,80,0,30),ZIndex=3,Text="Help",TextSize=15}},
			{"TextButton","MoreToggle",28,{Position=u(0,320,0,41),Size=u(0,80,0,30),ZIndex=3,Text="More",TextSize=15}},
			{"ScrollingFrame","MoreFrame",29,{Position=u(0,0,0,71),Size=u(0,400,1,-71),Visible=false,CanvasSize=u(0,0,4.3,0)},{
				{"Frame","List",19,{Position=u(0,20,0,0),Size=u(0,360,1,-60)},{
					{"TextLabel","2UpdateLogN",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Update Log",TextSize=14}},
					{"UIListLayout","UIListLayout",44,{}},
					{"Frame","5Credits",45,{Position=u(0,0,0,0),Size=u(1,0,0,90)},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","0",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" Happy_Liam/happa - Main Scripter/UI Design",TextSize=16}},
						{"UIListLayout","UIListLayout",9,{}},
						{"TextLabel","2",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" plusgiant5 - TASability creator",TextSize=16}},
						{"TextLabel","1",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" TestMicrowaveDinner - Scripting Help",TextSize=16}}
					}},
					{"TextLabel","4CreditsN",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Credits",TextSize=14}},
					{"TextLabel","0ModelN",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Executor port - client side script",TextSize=14}},
					{"Frame","3UpdateLog",46,{Position=u(0,0,0,0),Size=u(1,0,0,1430)},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","999",35,{Position=u(0,0,0.158824,0),Size=u(1,0,0,30),Text=" 7/13/22 - 2.0 Release (Happy_Liam -> HappaTAS)",TextSize=16}},
						{"TextLabel","998_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Script still usable in studio when API services are turned off",TextSize=12}},
						{"TextLabel","998",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 7/14/22 - 2.01",TextSize=16}},
						{"TextLabel","997",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 7/16/22 - 2.02",TextSize=16}},
						{"TextLabel","997_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Fixed issue with the shiftlock cursor",TextSize=12}},
						{"TextLabel","997_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Fixed issue with the \"Delete\" keybind",TextSize=12}},
						{"TextLabel","997_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Fixed timer skipping forward after TAS is optimized",TextSize=12}},
						{"TextLabel","996",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 7/21/22 - 2.03",TextSize=16}},
						{"TextLabel","994_4",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Unpause 1 works on any humanoid state except \"Landed\"",TextSize=12}},
						{"TextLabel","996_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Timers now show in minutes and seconds",TextSize=12}},
						{"TextLabel","996_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Message on the bottom when the TAS playback is complete",TextSize=12}},
						{"UIListLayout","UIListLayout",9,{}},
						{"TextLabel","996_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  You can see others move while they are testing",TextSize=12}},
						{"TextLabel","996_4",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Removed manually toggling shiftlock while in test",TextSize=12}},
						{"TextLabel","995",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 7/24/22 - 2.04",TextSize=16}},
						{"TextLabel","995_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  New Setting 'Restart When Testing'",TextSize=12}},
						{"TextLabel","995_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Fixed animations",TextSize=12}},
						{"TextLabel","995_4",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Fixed transparency when testing",TextSize=12}},
						{"TextLabel","995_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  New Control 'Look Around' while paused with camera lock ",TextSize=12}},
						{"TextLabel","994",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 7/25/22 - 2.05",TextSize=16}},
						{"TextLabel","994_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Save/Load is a lot faster now",TextSize=12}},
						{"TextLabel","994_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Fixed getting kicked by saving large files",TextSize=12}},
						{"TextLabel","994_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Max slots increased",TextSize=12}},
						{"TextLabel","994_5",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  New setting 'Stats Text Size'",TextSize=12}},
						{"TextLabel","993",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 7/25/22 - 2.1",TextSize=16}},
						{"TextLabel","993_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Added Help menu",TextSize=12}},
						{"TextLabel","993_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  A couple minor bug fixes",TextSize=12}},
						{"TextLabel","992",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 11/5/22 - 2.2",TextSize=16}},
						{"TextLabel","992_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Mobile support",TextSize=12}},
						{"TextLabel","992_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Playback speed controller",TextSize=12}},
						{"TextLabel","992_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Replay matches the timer of recording (no FPS/lag abuse)",TextSize=12}},
						{"TextLabel","992_4",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Fixes to animations, camera, and player transparency",TextSize=12}},
						{"TextLabel","992_5",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Patched physics bug \"super bounce\"",TextSize=12}},
						{"TextLabel","992_6",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Discord Server (link in description of main game)",TextSize=12}},
						{"TextLabel","991",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 12/14/22 - 2.21",TextSize=16}},
						{"TextLabel","991_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Data limit removed  : }",TextSize=12}},
						{"TextLabel","991_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Better animations (real)",TextSize=12}},
						{"TextLabel","991_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Fixed a couple TAS breaking bugs",TextSize=12}},
						{"TextLabel","990",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 1/2/23 - 2.22",TextSize=16}},
						{"TextLabel","990_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Patched physics bugs and cheats",TextSize=12}},
						{"TextLabel","990_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Fixed animations (not fake at all)",TextSize=12}},
						{"TextLabel","989",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 1/11/23 - 2.23",TextSize=16}},
						{"TextLabel","989_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Patched boosted bounce (lied last time)",TextSize=12}},
						{"TextLabel","989_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Fixed repeating slot IDs",TextSize=12}},
						{"TextLabel","989_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Small adjustments/fixes for quality of life",TextSize=12}},
						{"TextLabel","988",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 9/16/25 - 2.23.1",TextSize=16}},
						{"TextLabel","988_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Fixed saving and loading crashing (i think)",TextSize=12}},
						{"TextLabel","987",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 9/19/25 - 2.3",TextSize=16}},
						{"TextLabel","987_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   GUI Redesign/recolor",TextSize=12}},
						{"TextLabel","987_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Public Save Slots",TextSize=12}},
						{"TextLabel","987_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Merge TAS (refer to help)",TextSize=12}},
						{"TextLabel","987_4",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Interpolate Playback Setting (refer to help)",TextSize=12}},
						{"TextLabel","987_9",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Fixed TAS not loading in studio (must update HappaTAS loader)",TextSize=12}},
						{"TextLabel","987_5",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Fixed save slot order/IDs (new slots only)",TextSize=12}},
						{"TextLabel","987_6",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Update to character animations",TextSize=12}},
						{"TextLabel","987_7",47,{Position=u(0,0,0,0),Size=u(1,0,0,35),Text="   -   You can jump if you unpause after you walk off a part while humanoid state is \"running\"",TextSize=12}},
						{"TextLabel","987_8",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Renamed \"Spectate\" mode to \"Idle\"",TextSize=12}},
						{"TextLabel","986",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 10/11/25 - 2.31",TextSize=16}},
						{"TextLabel","986_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Emotes 😛",TextSize=12}},
						{"TextLabel","986_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Animation fixes (PLEASE dont be bad)",TextSize=12}},
						{"TextLabel","986_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Fixed coyote frame abuse",TextSize=12}},
						{"TextLabel","985",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 07/03/26 - 2.32",TextSize=16}},
						{"TextLabel","985_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Compatability with Roblox update",TextSize=12}}
					}},
					{"TextButton","1Model",20,{Position=u(0.25,0,0.5,0),Size=u(1,0,0,30),AnchorPoint=v2(0.5,0.5),Text="Unload HappaTAS",TextSize=16},{
						{"UICorner","UICorner",21,{}},
						{"UIStroke","UIStroke",48,{}}
					}}
				}}
			}},
			{"ScrollingFrame","HelpFrame",29,{Position=u(0,0,0,71),Size=u(0,400,1,-71),Visible=false,CanvasSize=u(0,0,4,0)},{
				{"Frame","List",19,{Position=u(0,20,0,10),Size=u(0,360,1,-60)},{
					{"UIListLayout","UIListLayout",44,{}},
					{"TextLabel","00",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="What is HappaTAS?",TextSize=16}},
					{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,83),AnchorPoint=v2(0.5,0),Text="      HappaTAS is the most powerful public tool on Roblox used to make Tool Assisted Speedruns (TAS). This is the executor port: one client-side script that saves to your executor's workspace folder. The original 1.0 version was called Happy_Liam's TAS Maker.",TextSize=14}},
					{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,50),AnchorPoint=v2(0.5,0),Text="      A Tool Assisted Speedrun or Tool Assisted Superplay (TAS for short) is a run of an obby that's already been created, and is not being played in real time.",TextSize=14}},
					{"TextLabel","03",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,75),AnchorPoint=v2(0.5,0),Text="      The controls in this tool will allow you to create a TAS, and replay it ingame. Start at the top of the list of controls and make your way down to figure out how it works! If you don't like the preset controls, you can change their keybind in the Controls menu.",TextSize=14}},
					{"TextLabel","04",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Basic Controls",TextSize=16}},
					{"TextButton","05",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Idle",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,84),Visible=false},{
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,64),AnchorPoint=v2(0.5,0),Text="      Idle is the default mode. Switching to Idle exits everything TAS related so you can play the obby like normal.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","06",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Create",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,100),Visible=false},{
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1.03,0,0,34),AnchorPoint=v2(0.5,0),Text="      The create control switches you to create mode and pauses you, so you can start recording your TAS.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,50),AnchorPoint=v2(0.5,0),Text="      Once you are in create mode, the controls below will give you further instructions on how to record gameplay.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","07",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Unpause",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,133),Visible=false},{
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,34),AnchorPoint=v2(0.5,0),Text="      The unpause control can be pressed while in create mode and paused.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,50),AnchorPoint=v2(0.5,0),Text="      Once you unpause, the TAS will begin recording. Any movement you do will show up in your recorded TAS unless you go back and remove it.",TextSize=14}},
								{"TextLabel","03",53,{Position=u(0.5,0,0,0),Size=u(1,0,0,33),AnchorPoint=v2(0.5,0),Text="      Exception: If you unpause the frame you jump off a ladder, you will be unpaused a frame earlier.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","08",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Pause",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,100),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,34),AnchorPoint=v2(0.5,0),Text="      The unpause control can be pressed while in create mode and unpaused.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,50),AnchorPoint=v2(0.5,0),Text="      Once you unpause, the TAS will stop recording. When paused, you can use other controls to remove parts of the TAS you don't want.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","09",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Back/Forward",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,140),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,50),AnchorPoint=v2(0.5,0),Text="      The back and forward keys can be pressed while in create mode, they will pause you if you are unpaused.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,78),AnchorPoint=v2(0.5,0),Text="      While paused, holding these keys will move you back and forward in time. You can use them to back if you mess up a jump, or want to be faster. Once you unpause, you will resume from where you moved back to.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","10",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Test",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,70),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,50),AnchorPoint=v2(0.5,0),Text="      Using the Test control will play the TAS that you created. Just sit back, relax, and feel free to flex on your friends as you watch your character go.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","11",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Optimize TAS",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,95),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,78),AnchorPoint=v2(0.5,0),Text="      Want to improve the speed of your TAS? Use the optimize control while in idle mode and the still frames will be removed. (Removes frames where the camera is positioned the same as the previous frame, and there are no new animations playing.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","12",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Delete TAS",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,38),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,20),AnchorPoint=v2(0.5,0),Text="      RIP all your hard work :(",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextLabel","13",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Advanced Controls",TextSize=16}},
					{"TextButton","14",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Back/Forward 1 Frame",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,66),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      The Back 1 Frame and Forward 1 Frame controls are the same as the Back and Forward controls, but holding them down has no effect.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","15",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Return",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,100),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      The Return control can be used while in create mode, pressing it while unpaused will automatically pause you.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,34),AnchorPoint=v2(0.5,0),Text="      This will bring you back to the most recent frame that you unpaused at.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","16",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Unpause 1 Frame",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,165),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,33),AnchorPoint=v2(0.5,0),Text="      The Unpause 1 Frame control can be used while paused in create mode.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      It is reccomend that you have Camera Lock (Paused) off if you are trying to control the camera while using this.",TextSize=14}},
								{"TextLabel","03",53,{Position=u(0.5,0,0,0),Size=u(1,0,0,64),AnchorPoint=v2(0.5,0),Text="      Exceptions: If you unpause the frame you jump off a ladder, you will be unpaused a frame earlier and for 2 frames. If you just landed a jump, you will be unpaused for 2 frames.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","17",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Look Around",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,142),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      The look around control can be used while paused in create mode, with the setting Camera Lock (Paused) on.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,76),AnchorPoint=v2(0.5,0),Text="      This will allow you to unlock the camera and look, around, pressing the key again will re-lock the camera. The camera will automatically go back to it's intended position if you unpause while looking around.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextLabel","18",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Settings",TextSize=16}},
					{"TextButton","20",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Lock Camera (Mode)",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,54),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,34),AnchorPoint=v2(0.5,0),Text="      Changes whether the camera can be controlled or not in the specified mode.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","23",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Show Stats (Mode)",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,54),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,34),AnchorPoint=v2(0.5,0),Text="      Changes whether or not the stats menu is open in the specified mode.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","22",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Restart When Testing",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,68),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      Changes whether or not you go back to frame 1 when testing, useful to have off when you want to start from a certain frame while in create.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","24",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Stats Text Size",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,40),Visible=false},{
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,20),AnchorPoint=v2(0.5,0),Text="      Sets the size and text size of the stats menu.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextLabel","30",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Have fun :)",TextSize=16}},
					{"Frame","Spacer",19,{Position=u(0,0,0,0),Size=u(0,0,0,100)}},
					{"TextButton","21",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Playback Speed",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,80),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      Changes the speed that the TAS will be replayed in test mode. Testing stats will always show when playback speed is not 1.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,34),AnchorPoint=v2(0.5,0),Text="      Negative/Backwards breaks animations but you can still try it out",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","19",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Interpolate Playback",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,200),Visible=false},{
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,30),AnchorPoint=v2(0.5,0),Text="      When Interpolate Playback is off, test mode will run the TAS by playing it one frame at a time.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,75),AnchorPoint=v2(0.5,0),Text="      When Interpolate Playback is on, a timer will begin when the playback starts. The position and properties of the character are set to be inbetween the two frames that were recorded at the time of playback (this was default starting in 2.23)",TextSize=14}},
								{"TextLabel","03",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,75),AnchorPoint=v2(0.5,0),Text="      It is recommended that you always keep interpolate on, because it is more stable under varying framerates. If you keep the same framerate throughout the recording and don't lag, turning this off might make the run look more smooth or realistic.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextLabel","25",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Saving and Loading",TextSize=16}},
					{"TextLabel","26",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,112),AnchorPoint=v2(0.5,0),Text="      In the save menu, add slots to save your TAS. Every slot is a compact .tas file inside HappaTasPort/<PlaceId>/ in your executor workspace, so slots only show up in the place they were saved in. Type in the name box to rename a slot (the file is renamed). There is no size or slot limit.",TextSize=14}},
					{"TextLabel","27",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Merging a TAS",TextSize=16}},
					{"TextLabel","28",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,114),AnchorPoint=v2(0.5,0),Text="      You are able to merge your TAS with one of your other saved TASes. By pressing the merge button, the TAS you load in from a save slot will load either before or after your current TAS. You will then be prompted to record a segment that stretches from the end of the first TAS to the beginning of the second TAS. The transition segment must end on the ground.",TextSize=14}},
					{"TextLabel","29",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Keyboard and Mouse Inputs",TextSize=16}},
					{"TextLabel","29a",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,147),AnchorPoint=v2(0.5,0),Text="      Your keys, right click, mouse wheel and mouse position are recorded together with every frame and replayed while testing, using the executor's input functions (keypress, mouse2press, mousemoveabs, mousescroll). The keys you use for the TAS menu are never recorded. Typing in a text box or clicking this menu is ignored. Keep the Roblox window focused during playback and keep your hands off the keyboard and mouse. The three Replay switches in Settings turn each part off.",TextSize=14}}
				}}
			}},
			{"UIStroke","UIStroke",17,{}}
		}}
}
local UI_TEMPLATES = {
	Control = {"Frame","ControlTemp",34,{Position=u(0,0,0,0),Size=u(1,0,0,30)},{
		{"TextLabel","N",30,{Position=u(0,0,0,0),Size=u(0.5,0,1,0),Text="Control",TextSize=16}},
		{"TextButton","Key",54,{Position=u(0.75,0,0.5,0),Size=u(0.4,0,0.7,0),AnchorPoint=v2(0.5,0.5),Text="Press Any Key",TextSize=16},{
			{"UICorner","UICorner",21,{}},
			{"UIStroke","UIStroke",22,{}}
		}},
		{"Frame","Border",39,{Position=u(0,0,1,0),Size=u(1,0,0,1),AnchorPoint=v2(0,1)}}
	}},
	Slot = {"Frame","SlotTemp",34,{Position=u(0,0,0,0),Size=u(1,0,0,30)},{
		{"Frame","Buttons",55,{Position=u(0.75,0,0,15),Size=u(0.45,0,0,21),AnchorPoint=v2(0.5,0.5)},{
			{"UICorner","UICorner",5,{}},
			{"TextButton","Save",56,{Position=u(0,0,0,0),Size=u(0.4,0,1,0),Text="Save",TextSize=16}},
			{"TextButton","Load",56,{Position=u(0.4,0,0,0),Size=u(0.4,0,1,0),Text="Load",TextSize=16}},
			{"Frame","Line",57,{Position=u(0.4,0,0,0),Size=u(0,1,1,0),AnchorPoint=v2(0.5,0)}},
			{"Frame","Line",57,{Position=u(0.8,0,0,0),Size=u(0,1,1,0),AnchorPoint=v2(0.5,0)}},
			{"UIStroke","UIStroke",22,{}},
			{"ImageButton","Close",58,{Position=u(0.9,0,0.5,0),Size=u(0,30,0,20),AnchorPoint=v2(0.5,0.5),Visible=false,LayoutOrder=28,ZIndex=2,Image="rbxassetid://3926307971",ImageRectOffset=v2(164,524),ImageRectSize=v2(36,36)}},
			{"ImageButton","Expand",58,{Position=u(0.9,0,0.5,0),Size=u(0,30,0,20),AnchorPoint=v2(0.5,0.5),LayoutOrder=24,ZIndex=2,Image="rbxassetid://3926307971",ImageRectOffset=v2(204,484),ImageRectSize=v2(36,36)}}
		}},
		{"TextLabel","IDtext",59,{Position=u(0,5,0,27),Size=u(0.15,0,0,30),Text="ID: 0",TextSize=12}},
		{"Frame","Border",39,{Position=u(0,0,0,0),Size=u(1,0,0,1),AnchorPoint=v2(0,1)}},
		{"TextBox","N",60,{Position=u(0.25,0,0,15),Size=u(0.48,0,0,21),AnchorPoint=v2(0.5,0.5),Text="",TextSize=13,PlaceholderText="Unnamed TAS"},{
			{"UICorner","UICorner",5,{}},
			{"UIStroke","UIStroke",41,{}}
		}},
		{"Frame","MoreButtons",55,{Position=u(0.75,0,0,42),Size=u(0.45,0,0,21),AnchorPoint=v2(0.5,0.5)},{
			{"UICorner","UICorner",5,{}},
			{"TextButton","Merge",56,{Position=u(0,0,0,0),Size=u(0.5,0,1,0),Text="Merge",TextSize=16}},
			{"TextButton","Delete",56,{Position=u(0.5,0,0,0),Size=u(0.5,0,1,0),Text="Delete",TextSize=16}},
			{"Frame","Line",57,{Position=u(0.5,0,0,0),Size=u(0,1,1,0),AnchorPoint=v2(0.5,0)}},
			{"UIStroke","UIStroke",22,{}}
		}}
	}},
	Z = {"Frame","Z",19,{Position=u(0,0,0,0),Size=u(0,1,0,1)}}
}

-- ================================================================================================
--  UI BUILDER  (turns UI_STYLES / UI_TREE / UI_TEMPLATES into Instances)
-- ================================================================================================
local UI = {}
do
	-- numbers in the data are raw enum values; this says which Enum each property uses
	local ENUM_FOR = {
		AutomaticSize = "AutomaticSize", AutomaticCanvasSize = "AutomaticSize",
		TextXAlignment = "TextXAlignment", TextYAlignment = "TextYAlignment", TextTruncate = "TextTruncate",
		ResampleMode = "ResamplerMode", ScaleType = "ScaleType",
		ElasticBehavior = "ElasticBehavior", ScrollingDirection = "ScrollingDirection",
		HorizontalScrollBarInset = "ScrollBarInset", VerticalScrollBarInset = "ScrollBarInset",
		VerticalScrollBarPosition = "VerticalScrollBarPosition",
		ApplyStrokeMode = "ApplyStrokeMode", LineJoinMode = "LineJoinMode",
		BorderStrokePosition = "BorderStrokePosition", StrokeSizingMode = "StrokeSizingMode",
		FillDirection = "FillDirection", HorizontalAlignment = "HorizontalAlignment",
		VerticalAlignment = "VerticalAlignment", SortOrder = "SortOrder",
		HorizontalFlex = "UIFlexAlignment", VerticalFlex = "UIFlexAlignment", ItemLineAlignment = "ItemLineAlignment",
	}

	local function setProp(inst, k, v)
		local enumName = ENUM_FOR[k]
		if enumName then
			local okE, item = pcall(function() return Enum[enumName]:FromValue(v) end)
			if not okE or item == nil then return end
			v = item
		end
		pcall(function() inst[k] = v end) -- unknown/renamed properties are skipped instead of breaking the build
	end

	local function applyProps(inst, cls, props)
		if cls == "UICorner" then
			-- newer clients have 4 corner radii, older ones only CornerRadius
			local tl = props.TopLeftRadius
			if tl and tl == props.TopRightRadius and tl == props.BottomLeftRadius and tl == props.BottomRightRadius then
				pcall(function() inst.CornerRadius = tl end)
			else
				for k, v in pairs(props) do setProp(inst, k, v) end
			end
			return
		end
		for k, v in pairs(props) do setProp(inst, k, v) end
	end

	local function build(node)
		local cls, name, sid, props, kids = node[1], node[2], node[3], node[4], node[5]
		local inst = Instance.new(cls)
		inst.Name = name
		local style = UI_STYLES[sid]
		applyProps(inst, cls, style[2])
		if props then applyProps(inst, cls, props) end
		if kids then
			for _, k in ipairs(kids) do
				build(k).Parent = inst
			end
		end
		return inst
	end
	UI.BuildNode = build

	-- clones of the three templates that lived inside the MenuManager script
	UI.Templates = {}
	for name, node in pairs(UI_TEMPLATES) do
		UI.Templates[name] = build(node)
	end
	function UI.Template(name)
		return UI.Templates[name]:Clone()
	end

	function UI.Create()
		local gui = Instance.new("ScreenGui")
		gui.Name = "TASUserInterface"
		gui.ResetOnSpawn = false
		pcall(function() gui.ZIndexBehavior = Enum.ZIndexBehavior.Global end)
		pcall(function() gui.DisplayOrder = 0 end)
		for _, node in ipairs(UI_TREE) do
			build(node).Parent = gui
		end
		return gui
	end

	-- parent order: CoreGui (hidden from game scripts) -> gethui() -> PlayerGui
	function UI.Attach(gui)
		local candidates = {}
		local core = svc("CoreGui")
		if core then candidates[#candidates + 1] = core end
		if type(gethui) == "function" then
			local ok, h = pcall(gethui)
			if ok and h then candidates[#candidates + 1] = h end
		end
		local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
		if pg then candidates[#candidates + 1] = pg end
		for _, parent in ipairs(candidates) do
			local ok = pcall(function() gui.Parent = parent end)
			if ok and gui.Parent ~= nil then
				UI.ParentName = tostring(parent)
				return true
			end
		end
		return false
	end
end

-- ================================================================================================
--  COMPACT FILE FORMAT  (.tas)
--  Instead of one big JSON array per frame, the frames are split into COLUMNS (all dt values together, all
--  x deltas together, ...). Every number is stored as a delta from the previous frame in a variable
--  length integer, fields that did not change cost nothing (one flag bit), and the whole blob is
--  LZ4 compressed with the executor's lz4compress. It is lossless for everything the recorder produces
--  (positions/velocities/camera = 1/1000 stud, times = 1 microsecond).
--
--  file   = "HTAS" | u8 version | u8 flags | varint frameCount | varint rawLength | zigzag mouseX0 | zigzag mouseY0 | payload
--  flags  = bit0: payload is LZ4 compressed, bit1: frames carry mouse positions
--  raw    = for each column: varint byteLength | bytes          (columns in the fixed order of COLUMNS)
-- ================================================================================================
local Codec = {}
do
	local MAGIC = "HTAS"
	local VERSION_BYTE = 1
	local SCROLL_MARK = 0x7F -- inside the input column: a scroll event follows (zigzag notches)
	Codec.ScrollBase = 10000 -- runtime events: key press = id, release = -id, scroll = ScrollBase + notches

	local COLUMNS = { "FA", "FB", "DT", "TA", "PX", "PY", "PZ", "ROT", "LV", "AV", "ST", "CR", "CP", "ZM", "PO", "JT", "SP", "AN", "MS", "IN", "MB" }

	local floor, abs = math.floor, math.abs
	local char, byte, sub = string.char, string.byte, string.sub

	local function q(v, scale) -- quantise to an integer (what r(x, scale) stored, scaled back up)
		if v ~= v or v == math.huge or v == -math.huge then return 0 end
		local n = floor(v * scale + 0.5)
		return n
	end

	-- ------------------------------------------------------------------ byte buffers
	local function putVar(buf, n) -- n >= 0
		while n >= 128 do
			local m = n % 128
			buf[#buf + 1] = m + 128
			n = (n - m) / 128
		end
		buf[#buf + 1] = n
	end
	local function putZig(buf, v)
		if v >= 0 then putVar(buf, v * 2) else putVar(buf, -v * 2 - 1) end
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

	-- ------------------------------------------------------------------ reader
	local function newReader(s)
		return { s = s, p = 1, n = #s }
	end
	local function getByte(rd)
		local p = rd.p
		if p > rd.n then error("unexpected end of data") end
		rd.p = p + 1
		return byte(rd.s, p)
	end
	local function getVar(rd)
		local result, mul = 0, 1
		while true do
			local b = getByte(rd)
			if b < 128 then
				return result + b * mul
			end
			result = result + (b - 128) * mul
			mul = mul * 128
			if mul > 2 ^ 56 then error("bad varint") end
		end
	end
	local function getZig(rd)
		local z = getVar(rd)
		if z % 2 == 0 then return floor(z / 2) else return -floor((z + 1) / 2) end
	end

	-- ------------------------------------------------------------------ LZ4 helpers
	-- pure Lua decompressor (only used when the executor has no lz4decompress)
	local function lz4Fallback(src, usize)
		local out, on = {}, 0
		local i, n = 1, #src
		while i <= n do
			local token = byte(src, i); i = i + 1
			local lit = floor(token / 16)
			if lit == 15 then
				repeat
					local b = byte(src, i); i = i + 1
					lit = lit + b
				until b ~= 255
			end
			for k = 0, lit - 1 do out[on + k + 1] = byte(src, i + k) end
			on = on + lit
			i = i + lit
			if i > n then break end
			local off = byte(src, i) + byte(src, i + 1) * 256; i = i + 2
			local ml = token % 16
			if ml == 15 then
				repeat
					local b = byte(src, i); i = i + 1
					ml = ml + b
				until b ~= 255
			end
			ml = ml + 4
			local start = on - off
			for k = 1, ml do out[on + k] = out[start + k] end
			on = on + ml
			if on % 20000 < 8 then task.wait() end
		end
		if on ~= usize then error("lz4 size mismatch") end
		return bufToString(out)
	end

	local function haveLz4()
		return type(lz4compress) == "function" and type(lz4decompress) == "function"
	end
	Codec.HaveLz4 = haveLz4

	local function lz4Decompress(data, usize)
		if type(lz4decompress) == "function" then
			local ok, res = pcall(lz4decompress, data, usize)
			if ok and type(res) == "string" and #res == usize then return res end
		end
		return lz4Fallback(data, usize)
	end

	-- ------------------------------------------------------------------ encode
	-- frames: runtime frames (see TASMain). progress(i, n) optional, yields every few thousand frames
	function Codec.Encode(frames, progress)
		local cols = {}
		for _, name in ipairs(COLUMNS) do cols[name] = {} end
		local FA, FB, DT, TA, PX, PY, PZ = cols.FA, cols.FB, cols.DT, cols.TA, cols.PX, cols.PY, cols.PZ
		local ROT, LV, AV, ST, CR, CP, ZM = cols.ROT, cols.LV, cols.AV, cols.ST, cols.CR, cols.CP, cols.ZM
		local PO, JT, SP, AN, MS, IN, MB = cols.PO, cols.JT, cols.SP, cols.AN, cols.MS, cols.IN, cols.MB

		local total = #frames
		-- does any frame carry a mouse position? (old/legacy frames do not)
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

		for i = 1, total do
			local f = frames[i]
			local fa, fb = 0, 0

			-- timing ----------------------------------------------------------------
			local dt = q(f.FrameTime, 1000000)
			local tot = q(f.TotalTime, 1000000)
			putZig(DT, dt - pDT)
			putZig(TA, tot - (pTotal + dt))
			pDT, pTotal = dt, tot

			-- root cframe: x y z r00 r01 r02 r10 r11 r12 r20 r21 r22 -------------------
			local cf = f.Cframe
			local x, y, z = q(cf[1], 1000), q(cf[2], 1000), q(cf[3], 1000)
			putZig(PX, x - pPos[1]); putZig(PY, y - pPos[2]); putZig(PZ, z - pPos[3])
			pPos[1], pPos[2], pPos[3] = x, y, z
			local rotChanged = false
			local rv = {}
			for k = 1, 9 do
				local v = q(cf[3 + k], 1000)
				rv[k] = v
				if v ~= pRot[k] then rotChanged = true end
			end
			if rotChanged then
				fa = fa + 1
				for k = 1, 9 do putZig(ROT, rv[k] - pRot[k]); pRot[k] = rv[k] end
			end

			-- velocities --------------------------------------------------------------
			local lin, ang = f.Velocity.Linear, f.Velocity.Angular
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

			-- humanoid state ------------------------------------------------------------
			local st = f.State
			if st ~= pState then
				fa = fa + 8
				ST[#ST + 1] = st % 256
				pState = st
			end

			-- camera --------------------------------------------------------------------
			local cc = f.CamCframe
			local camChanged = false
			local cv = {}
			for k = 1, 9 do
				local v = q(cc[3 + k], 1000)
				cv[k] = v
				if v ~= pCamRot[k] then camChanged = true end
			end
			if camChanged then
				fa = fa + 16
				for k = 1, 9 do putZig(CR, cv[k] - pCamRot[k]); pCamRot[k] = cv[k] end
			end
			-- camera position is stored relative to the root: it only changes when the camera turns/zooms
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

			-- animation -----------------------------------------------------------------
			local an = f.Anim
			if an then
				local pose = an.Pose or 0
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
						AN[#AN + 1] = (a[1] or 0) % 256
						putVar(AN, math.max(0, q(a[2] or 0, 1000)))
					end
				end
			end

			-- mouse ---------------------------------------------------------------------
			if hasMouse and f.MX then
				local mx, my = q(f.MX, 1), q(f.MY or 0, 1)
				if mx ~= pMX or my ~= pMY then
					fb = fb + 16
					putZig(MS, mx - pMX); putZig(MS, my - pMY)
					pMX, pMY = mx, my
				end
			end

			-- keyboard / mouse buttons / wheel ------------------------------------------
			local ev = f.Input
			if ev and #ev > 0 then
				fb = fb + 32
				putVar(IN, #ev)
				for _, e in ipairs(ev) do
					if e >= Codec.ScrollBase - 5000 then
						IN[#IN + 1] = SCROLL_MARK
						putZig(IN, e - Codec.ScrollBase)
					elseif e > 0 then
						IN[#IN + 1] = e
					else
						IN[#IN + 1] = -e + 128
					end
				end
			end

			-- touch controls --------------------------------------------------------------
			local mob = f.Mobile
			if type(mob) == "table" then
				fb = fb + 64
				local hasStick = mob.JoystickX ~= nil and mob.JoystickY ~= nil
				MB[#MB + 1] = (mob.Jumping == 1 and 1 or 0) + (hasStick and 2 or 0)
				if hasStick then
					putZig(MB, q(mob.JoystickX, 1)); putZig(MB, q(mob.JoystickY, 1))
				end
			end

			FA[#FA + 1] = fa
			FB[#FB + 1] = fb

			if i % 1500 == 0 then
				if progress then progress(i, total) end
				task.wait()
			end
		end

		-- assemble the raw blob
		local rawParts = {}
		for _, name in ipairs(COLUMNS) do
			local s = bufToString(cols[name])
			local hdr = {}
			putVar(hdr, #s)
			rawParts[#rawParts + 1] = bufToString(hdr)
			rawParts[#rawParts + 1] = s
		end
		local raw = table.concat(rawParts)

		local compressed, flags = nil, 0
		if hasMouse then flags = flags + 2 end
		if haveLz4() and #raw > 0 then
			local ok, res = pcall(lz4compress, raw)
			if ok and type(res) == "string" and #res < #raw then
				local okD, back = pcall(lz4decompress, res, #raw) -- never trust a compressor blindly: prove the round trip
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
		local file = MAGIC .. char(VERSION_BYTE, flags) .. bufToString(head) .. (compressed or raw)
		return file, { frames = total, rawBytes = #raw, fileBytes = #file, compressed = compressed ~= nil }
	end

	-- ------------------------------------------------------------------ decode
	function Codec.IsCompact(data)
		return type(data) == "string" and sub(data, 1, 4) == MAGIC
	end

	function Codec.Decode(data, progress)
		if not Codec.IsCompact(data) then error("not a HappaTAS binary file") end
		local version, flags = byte(data, 5), byte(data, 6)
		if version ~= VERSION_BYTE then error("unsupported file version " .. tostring(version)) end
		local rd = newReader(data)
		rd.p = 7
		local total = getVar(rd)
		local rawLen = getVar(rd)
		local mouse0x = getZig(rd)
		local mouse0y = getZig(rd)
		local payload = sub(data, rd.p)
		local raw
		if flags % 2 == 1 then
			raw = lz4Decompress(payload, rawLen)
		else
			raw = payload
		end
		if #raw ~= rawLen then error("size mismatch") end
		local hasMouse = floor(flags / 2) % 2 == 1

		-- split the columns
		local R = {}
		local pos = 1
		local rr = newReader(raw)
		for _, name in ipairs(COLUMNS) do
			local len = getVar(rr)
			local start = rr.p
			if start + len - 1 > #raw then error("column " .. name .. " is cut off") end
			R[name] = { s = raw, p = start, n = start + len - 1 }
			rr.p = start + len
		end
		if rr.p ~= #raw + 1 then error("trailing data") end

		local frames = {}
		local FA, FB, DT, TA, PX, PY, PZ = R.FA, R.FB, R.DT, R.TA, R.PX, R.PY, R.PZ
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

		for i = 1, total do
			local fa, fb = getByte(FA), getByte(FB)
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
				f.Mobile = mob
			else
				f.Mobile = 0
			end

			frames[i] = f
			if i % 1500 == 0 then
				if progress then progress(i, total) end
				task.wait()
			end
		end

		-- every column must be consumed exactly, otherwise the file is damaged
		for name, rdr in pairs(R) do
			if rdr.p ~= rdr.n + 1 then error("column " .. name .. " was not read completely") end
		end
		return frames
	end
end
-- ================================================================================================
--  STORAGE  (replaces TASServer + DataStores)
--  HappaTasPort/Settings.json            keybinds + settings
--  HappaTasPort/<PlaceId>/<SlotName>.tas   one TAS per file (compact binary); the slot name IS the file name
--                                          older <SlotName>.json slots still load and are converted when saved again
-- ================================================================================================
local Store = {}
do
	local ROOT = CONFIG.RootFolder
	local PLACE = tostring(game.PlaceId)
	local PLACE_PATH = ROOT .. "/" .. PLACE
	local SETTINGS_PATH = ROOT .. "/Settings.json"

	local hasFS = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
		and type(isfolder) == "function" and type(makefolder) == "function" and type(listfiles) == "function"
		and type(delfile) == "function"

	Store.Available = hasFS
	Store.Ready = false
	Store.RootPath = ROOT
	Store.PlacePath = PLACE_PATH

	function Store.Init()
		if not hasFS then return false end
		local ok = pcall(function()
			if not isfolder(ROOT) then makefolder(ROOT) end
			if not isfolder(PLACE_PATH) then makefolder(PLACE_PATH) end
		end)
		Store.Ready = ok and isfolder(PLACE_PATH) == true
		return Store.Ready
	end

	-- -------------------------------------------------------------------------------- names
	local RESERVED = { CON = true, PRN = true, AUX = true, NUL = true }
	for i = 1, 9 do
		RESERVED["COM" .. i] = true
		RESERVED["LPT" .. i] = true
	end

	-- makes a legal Windows file name out of whatever was typed. returns nil when nothing usable is left
	function Store.CleanName(s)
		s = tostring(s or "")
		s = s:gsub("[%c<>:\"/\\|%?%*]", "")
		s = s:gsub("^%s+", "")
		s = s:gsub("%s+$", "")
		s = s:gsub("[%. ]+$", "")
		local n = utf8.len(s)
		if n and n > 60 then
			s = s:sub(1, utf8.offset(s, 61) - 1)
		elseif not n then
			s = s:gsub("[\128-\255]", "") -- invalid utf8, drop the bad bytes
		end
		if s == "" then return nil end
		if RESERVED[s:upper()] then s = "_" .. s end
		return s
	end

	-- slots are saved as compact .tas files; slots saved by earlier versions of this port are .json and still load
	local EXT_NEW, EXT_OLD = ".tas", ".json"
	local function slotPath(name, ext)
		return PLACE_PATH .. "/" .. name .. (ext or EXT_NEW)
	end
	Store.SlotPath = slotPath

	local function fileExists(path)
		local ok, res = pcall(isfile, path)
		return ok and res == true
	end

	-- the file that currently holds slot `name` (the new format wins when both exist)
	local function findSlotFile(name)
		local p = slotPath(name, EXT_NEW)
		if fileExists(p) then return p, EXT_NEW end
		p = slotPath(name, EXT_OLD)
		if fileExists(p) then return p, EXT_OLD end
		return nil
	end

	local function ensureFolders()
		pcall(function()
			if not isfolder(ROOT) then makefolder(ROOT) end
			if not isfolder(PLACE_PATH) then makefolder(PLACE_PATH) end
		end)
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

	-- every slot file (.tas or .json) in this place's folder, naturally sorted ("Slot 2" before "Slot 10")
	function Store.ListSlots()
		local out, seen = {}, {}
		if not Store.Ready then return out end
		local ok, files = pcall(listfiles, PLACE_PATH)
		if not ok or type(files) ~= "table" then return out end
		for _, path in ipairs(files) do
			local fname = tostring(path):match("([^/\\]+)$")
			if fname then
				local base = fname:match("^(.+)%.[Tt][Aa][Ss]$") or fname:match("^(.+)%.[Jj][Ss][Oo][Nn]$")
				if base and not seen[base] and fileExists(PLACE_PATH .. "/" .. fname) then
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

	-- "Slot 1", "Slot 2", ... first one that is not taken
	function Store.NextDefaultName()
		local n = 1
		while Store.Exists("Slot " .. n) do n = n + 1 end
		return "Slot " .. n
	end

	-- -------------------------------------------------------------------------------- (de)serialising a TAS
	-- legacy json layout (earlier versions of this port): array frames -> runtime frames
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

	local function validFrame(frame)
		return type(frame) == "table" and type(frame[1]) == "table" and #frame[1] >= 12
			and type(frame[2]) == "table" and type(frame[2][1]) == "table" and type(frame[2][2]) == "table"
			and type(frame[3]) == "number" and type(frame[4]) == "table" and #frame[4] >= 12
			and type(frame[7]) == "table" and type(frame[8]) == "number"
			and type(frame[9]) == "number" and type(frame[10]) == "number"
	end

	-- -------------------------------------------------------------------------------- slot operations
	-- every function returns ok, errorMessage|result

	-- writes the slot file and proves it landed. If the executor refuses the .tas extension it falls back to .json
	-- (the content is detected by its first bytes, never by the extension)
	local function writeSlotFile(name, bytes)
		ensureFolders()
		local lastErr = "write failed"
		for _, ext in ipairs({ EXT_NEW, EXT_OLD }) do
			local path = slotPath(name, ext)
			local ok, err = pcall(writefile, path, bytes)
			if ok then
				local okR, back = pcall(readfile, path)
				if okR and type(back) == "string" and #back == #bytes then
					return true, path, ext
				end
				lastErr = "the file could not be verified after writing"
			else
				lastErr = tostring(err)
			end
		end
		return false, lastErr
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

	-- frames: runtime frames. progress(i, n) is optional. This yields, so call it from its own thread.
	-- returns true, frameCount, fileBytes
	function Store.SaveSlot(name, allFrames, progress)
		if not Store.Ready then return false, "Saving is unavailable" end
		-- a frame that is still being recorded can be missing its position/state; those are skipped
		local frames = {}
		for _, f in ipairs(allFrames) do
			if type(f.Cframe) == "table" and f.State and f.Velocity and f.CamCframe and f.FrameTime and f.TotalTime then
				frames[#frames + 1] = f
			end
		end
		local okE, bytes = pcall(Codec.Encode, frames, progress)
		if not okE then return false, tostring(bytes) end
		local ok, path, ext = writeSlotFile(name, bytes)
		if not ok then return false, path end
		if ext == EXT_NEW then
			pcall(delfile, slotPath(name, EXT_OLD)) -- an old .json copy of this slot is replaced by the new file
		end
		return true, #frames, #bytes
	end

	-- the json layout written by the first version of this port (batches of frames, one per line) and plain arrays
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

		-- any other json (hand made / older exports): decode in one go
		local okD, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if not okD or type(decoded) ~= "table" then return false, "This is not a HappaTAS slot file" end
		local lists
		if type(decoded.batches) == "table" then
			lists = decoded.batches -- a batched file that was re-saved by an editor
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

	-- returns true, frames (possibly empty) or false, error. Yields while decoding big files.
	function Store.LoadSlot(name, progress)
		if not Store.Ready then return false, "Saving is unavailable" end
		local path = findSlotFile(name)
		if not path then return false, "The slot file does not exist" end
		local okR, raw = pcall(readfile, path)
		if not okR or type(raw) ~= "string" then return false, "Could not read the slot file" end
		if Codec.IsCompact(raw) then
			local okD, frames = pcall(Codec.Decode, raw, progress)
			if not okD then
				local why = tostring(frames):gsub("^[^:]*:%d+: ", "")
				return false, "The slot file is damaged (" .. why .. ")"
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
				local ok, err = pcall(delfile, p)
				if not ok then return false, tostring(err) end
			end
		end
		return true
	end

	-- renames by writing the new file first and only then removing the old one
	function Store.RenameSlot(old, newName)
		if not Store.Ready then return false, "Saving is unavailable" end
		newName = Store.CleanName(newName)
		if not newName then return false, "Invalid name" end
		if newName == old then return true, old end
		local oldPath, ext = findSlotFile(old)
		if not oldPath then return false, "The slot file does not exist" end
		local sameFile = newName:lower() == old:lower() -- windows paths ignore case
		if not sameFile and Store.Exists(newName) then return false, "A slot with that name already exists" end
		local okR, data = pcall(readfile, oldPath)
		if not okR or type(data) ~= "string" then return false, "Could not read the slot file" end
		local newPath = slotPath(newName, ext)
		if sameFile then
			local tmp = PLACE_PATH .. "/" .. old .. "~rename" .. ext -- (a normal extension: odd ones may be refused)
			local ok = pcall(function()
				writefile(tmp, data)
				delfile(oldPath)
				writefile(newPath, data)
				delfile(tmp)
			end)
			if not ok then return false, "Rename failed" end
			return true, newName
		end
		local ok = pcall(function()
			writefile(newPath, data)
			if not isfile(newPath) then error("write failed") end
			delfile(oldPath)
		end)
		if not ok then return false, "Rename failed" end
		return true, newName
	end

	-- -------------------------------------------------------------------------------- settings
	function Store.LoadSettings()
		if not Store.Ready then return nil end
		local okE, exists = pcall(isfile, SETTINGS_PATH)
		if not okE or not exists then return nil end
		local okR, raw = pcall(readfile, SETTINGS_PATH)
		if not okR or type(raw) ~= "string" then return nil end
		local okD, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if okD and type(decoded) == "table" then return decoded end
		return nil
	end

	function Store.SaveSettings(tbl)
		if not Store.Ready then return false end
		local okE, json = pcall(HttpService.JSONEncode, HttpService, tbl)
		if not okE then return false end
		ensureFolders()
		return (pcall(writefile, SETTINGS_PATH, json))
	end
end

-- ================================================================================================
--  CONTROLS + SETTINGS STATE  (the original kept these as Value objects under Player.TAS)
--  They stay Value objects so the UI/TAS code below can use .Value and .Changed unchanged.
-- ================================================================================================
local TASState = Instance.new("Folder")
TASState.Name = "TAS"
local ControlValues = Instance.new("Folder")
ControlValues.Name = "Controls"
ControlValues.Parent = TASState
local SettingValues = Instance.new("Folder")
SettingValues.Name = "Settings"
SettingValues.Parent = TASState
Janitor.add(TASState)

Store.Init()

do
	local saved = Store.LoadSettings() or {}
	local savedControls = type(saved.controls) == "table" and saved.controls or {}
	local savedSettings = type(saved.settings) == "table" and saved.settings or {}

	local saveQueued = false
	local function queueSave()
		if saveQueued or Janitor.unloading then return end
		saveQueued = true
		task.delay(0.4, function()
			saveQueued = false
			local out = { controls = {}, settings = {} }
			for _, v in ipairs(ControlValues:GetChildren()) do out.controls[v.Name] = v.Value end
			for _, v in ipairs(SettingValues:GetChildren()) do out.settings[v.Name] = v.Value end
			Store.SaveSettings(out)
		end)
	end

	for _, control in ipairs(ControlsTable) do
		local V = Instance.new("StringValue")
		V.Name = control[1]
		local s = savedControls[control[1]]
		V.Value = (type(s) == "string" and ToKey[s]) and s or control[2]
		V.Parent = ControlValues
		on(V.Changed, queueSave)
	end
	for _, setting in ipairs(SettingsTable) do
		local V = Instance.new("NumberValue")
		V.Name = setting[1]
		local s = savedSettings[setting[1]]
		V.Value = type(s) == "number" and s or setting[2]
		V.Parent = SettingValues
		on(V.Changed, queueSave)
	end
end

-- ================================================================================================
--  BRIDGE  (replaces the forked PlayerModule + Animate "TASRS" bindables)
--  The original shipped its own copy of the PlayerModule and Animate. An executor can't swap those
--  cleanly, so instead we require() the game's live PlayerModule and wrap the few functions the fork edited.
--  Everything is pcall-guarded: if a game uses a custom camera, only the zoom/shiftlock sync degrades.
-- ================================================================================================
local Bridge = {}
do
	local UserGameSettings
	pcall(function() UserGameSettings = UserSettings():GetService("UserGameSettings") end)

	local cameras          -- the live CameraModule object (PlayerModule:GetCameras())
	local patched = false
	local originals = {}   -- { table, key, originalFunction }  put back on unload
	local rotate = true         -- BaseCamera "rotate" flag from the fork
	local shiftlockBlocked = false -- MouseLockController "LockShiftlock" flag from the fork
	local springRemoved = false -- ZoomController "SpringRemoved" flag from the fork

	local function patch(tbl, key, makeWrapper)
		if type(tbl) ~= "table" then return false end
		local ok = pcall(function()
			local orig = tbl[key]
			if type(orig) ~= "function" then error("missing function " .. tostring(key)) end
			local wrapper = makeWrapper(orig)
			tbl[key] = wrapper
			originals[#originals + 1] = { tbl, key, orig, wrapper }
		end)
		if not ok then log("could not patch", key) end
		return ok
	end

	local function applyPatches(playerModule)
		if patched then return end
		patched = true
		local camMod = playerModule:FindFirstChild("CameraModule")
		if camMod then
			-- BaseCamera:UpdateMouseBehavior  -> character must not turn with the camera while anchored
			local baseCam = camMod:FindFirstChild("BaseCamera")
			if baseCam then
				local okR, BaseCamera = pcall(require, baseCam)
				if okR then
					patch(BaseCamera, "UpdateMouseBehavior", function(orig)
						return function(self, ...)
							local res = orig(self, ...)
							if rotate == false and UserGameSettings and (self.inFirstPerson or self.inMouseLockedMode) then
								pcall(function() UserGameSettings.RotationType = Enum.RotationType.MovementRelative end)
							end
							return res
						end
					end)
				end
			end
			-- ZoomController.Update -> snap the zoom spring (same maths as the fork's freq * 1000000)
			local zoomMod = camMod:FindFirstChild("ZoomController")
			if zoomMod then
				local okR, Zoom = pcall(require, zoomMod)
				if okR then
					patch(Zoom, "Update", function(orig)
						return function(renderDt, ...)
							if springRemoved and type(renderDt) == "number" then
								renderDt = renderDt * 1000000
							end
							return orig(renderDt, ...)
						end
					end)
				end
			end
		end
		-- MouseLockController:DoMouseLockSwitch -> ignore the shiftlock key while a TAS is being tested
		local ctrl = cameras and cameras.activeMouseLockController
		if ctrl then
			local cls = getmetatable(ctrl)
			if type(cls) == "table" then
				patch(cls, "DoMouseLockSwitch", function(orig)
					return function(self, name, state, input, ...)
						if shiftlockBlocked then return Enum.ContextActionResult.Pass end
						return orig(self, name, state, input, ...)
					end
				end)
			end
		end
	end

	local function resolve()
		if cameras then return cameras end
		if not LocalPlayer.Character then return nil end -- the game has surely loaded its PlayerModule by now
		local ps = LocalPlayer:FindFirstChild("PlayerScripts")
		local pm = ps and ps:FindFirstChild("PlayerModule")
		if not pm then return nil end
		local ok, mod = pcall(require, pm)
		if not ok or type(mod) ~= "table" or type(mod.GetCameras) ~= "function" then return nil end
		local ok2, cams = pcall(function() return mod:GetCameras() end)
		if not ok2 or type(cams) ~= "table" then return nil end
		cameras = cams
		applyPatches(pm)
		return cameras
	end

	-- keeps trying in the background until the game's camera scripts are reachable
	function Bridge.Init()
		task.spawn(function()
			local t0 = os.clock()
			while not Janitor.unloading and not resolve() and os.clock() - t0 < 120 do
				task.wait(0.5)
			end
			if not cameras and not Janitor.unloading then
				warnf("Could not find the game's PlayerModule, zoom/shiftlock syncing is limited.")
			end
		end)
	end

	function Bridge.GetZoom()
		local cams = resolve()
		local ctrl = cams and cams.activeCameraController
		if ctrl and type(ctrl.GetCameraToSubjectDistance) == "function" then
			local ok, z = pcall(ctrl.GetCameraToSubjectDistance, ctrl)
			if ok and type(z) == "number" then return z end
		end
		local cam = workspace.CurrentCamera -- fallback: how far the camera sits from its focus
		return (cam.CFrame.Position - cam.Focus.Position).Magnitude
	end

	function Bridge.RemoveZoomSpring()
		springRemoved = true
		task.spawn(function()
			RunService.Heartbeat:Wait()
			springRemoved = false
		end)
	end

	function Bridge.SetZoom(zoom, static)
		if static then Bridge.RemoveZoomSpring() end
		local cams = resolve()
		local ctrl = cams and cams.activeCameraController
		if ctrl and type(ctrl.SetCameraToSubjectDistance) == "function" then
			pcall(ctrl.SetCameraToSubjectDistance, ctrl, zoom)
		end
	end

	function Bridge.IsShiftlocked() -- true when shiftlock is currently on
		local cams = resolve()
		local ctrl = cams and cams.activeMouseLockController
		if ctrl and type(ctrl.isMouseLocked) == "boolean" then return ctrl.isMouseLocked end
		local ok, icon = pcall(function() return LocalPlayer:GetMouse().Icon end)
		return ok and icon == "rbxasset://textures/MouseLockedCursor.png"
	end

	function Bridge.ShiftlockSwitch() -- scripted toggle, works even while the key is blocked
		local cams = resolve()
		local ctrl = cams and cams.activeMouseLockController
		if ctrl and type(ctrl.OnMouseLockToggled) == "function" then
			pcall(ctrl.OnMouseLockToggled, ctrl)
		end
	end

	function Bridge.LockShiftlock(lock)
		shiftlockBlocked = lock and true or false
	end

	function Bridge.ShiftlockRotation(value)
		rotate = value and true or false
		local cams = resolve()
		local ctrl = cams and cams.activeCameraController
		if ctrl and type(ctrl.UpdateMouseBehavior) == "function" then
			pcall(ctrl.UpdateMouseBehavior, ctrl)
		end
	end

	function Bridge.Restore()
		shiftlockBlocked = false
		rotate = true
		springRemoved = false
		for i = #originals, 1, -1 do
			local o = originals[i]
			pcall(function()
				if o[1][o[2]] == o[4] then o[1][o[2]] = o[3] end -- only if nobody wrapped us again
			end)
		end
		originals = {}
		local cams = cameras
		local ctrl = cams and cams.activeCameraController
		if ctrl and type(ctrl.UpdateMouseBehavior) == "function" then
			pcall(ctrl.UpdateMouseBehavior, ctrl)
		end
	end

	-- animation hooks are filled in by the Animate engine below
	function Bridge.GetAnimation(startOfTAS) return nil end
	function Bridge.SetAnimation(animData, anim, playbackSpeed, timeDifference) end
	function Bridge.LockAnimations(lock) end
end

-- ================================================================================================
--  INPUTS  (keyboard / mouse capture while recording, replay through the executor while testing)
--  Based on how Tasability does it (record key events per frame, replay with keypress / mouse2press /
--  mousemoveabs / mousescroll), with these improvements:
--    * events are stored only on the frame they happen (a key held for 5 seconds = 2 events, not 300 frames)
--    * every key on the keyboard that a game can use is supported, not just A-Z / Space / Shift
--    * the keys that control the TAS itself (your keybinds) are never recorded or replayed
--    * typing in a text box, the Roblox menu and clicks on this tool's own windows are ignored
--    * the held keys are tracked, so recording can start while a key is already held, rewinding keeps the
--      right keys down, and every key is released when a test stops, you die, or the script unloads
--    * the wheel uses the native mousescroll() (no AutoHotkey needed)
-- ================================================================================================
local InputSys = {}
do
	local GuiService = svc("GuiService")
	local floor = math.floor

	-- the executor's input functions, with the common alternative names
	local fKeyDown   = keypress or keydown
	local fKeyUp     = keyrelease or keyup
	local fM1Down    = mouse1press or mouse1down
	local fM1Up      = mouse1release or mouse1up
	local fM2Down    = mouse2press or mouse2down
	local fM2Up      = mouse2release or mouse2up
	local fMoveAbs   = mousemoveabs
	local fScroll    = mousescroll
	local fActive    = isrbxactive or isgameactive or iswindowactive

	InputSys.Available = {
		Keys = type(fKeyDown) == "function" and type(fKeyUp) == "function",
		Clicks = type(fM1Down) == "function" and type(fM2Down) == "function" and type(fM1Up) == "function" and type(fM2Up) == "function",
		Move = type(fMoveAbs) == "function",
		Scroll = type(fScroll) == "function",
	}

	local SCROLL_BASE = Codec.ScrollBase -- event numbers: key press = id, release = -id, scroll = SCROLL_BASE + notches
	local SCROLL_LIMIT = SCROLL_BASE - 5000
	local SCROLL_UNIT = 120               -- one notch of the wheel (WHEEL_DELTA); Real passes the amount straight to Windows

	-- ------------------------------------------------------------------ key table
	-- The ORDER of this list is part of the file format (an id is stored per event): only ever append to it.
	-- { Enum.KeyCode name, Windows virtual-key code, short name for the stats panel }
	local KEYLIST = {
		{ "A", 0x41, "A" }, { "B", 0x42, "B" }, { "C", 0x43, "C" }, { "D", 0x44, "D" }, { "E", 0x45, "E" }, { "F", 0x46, "F" },
		{ "G", 0x47, "G" }, { "H", 0x48, "H" }, { "I", 0x49, "I" }, { "J", 0x4A, "J" }, { "K", 0x4B, "K" }, { "L", 0x4C, "L" },
		{ "M", 0x4D, "M" }, { "N", 0x4E, "N" }, { "O", 0x4F, "O" }, { "P", 0x50, "P" }, { "Q", 0x51, "Q" }, { "R", 0x52, "R" },
		{ "S", 0x53, "S" }, { "T", 0x54, "T" }, { "U", 0x55, "U" }, { "V", 0x56, "V" }, { "W", 0x57, "W" }, { "X", 0x58, "X" },
		{ "Y", 0x59, "Y" }, { "Z", 0x5A, "Z" },                                                              -- 1-26
		{ "Zero", 0x30, "0" }, { "One", 0x31, "1" }, { "Two", 0x32, "2" }, { "Three", 0x33, "3" }, { "Four", 0x34, "4" },
		{ "Five", 0x35, "5" }, { "Six", 0x36, "6" }, { "Seven", 0x37, "7" }, { "Eight", 0x38, "8" }, { "Nine", 0x39, "9" }, -- 27-36
		{ "Space", 0x20, "Space" }, { "Return", 0x0D, "Enter" }, { "Tab", 0x09, "Tab" }, { "Backspace", 0x08, "Bksp" }, -- 37-40
		{ "LeftShift", 0xA0, "LShift" }, { "RightShift", 0xA1, "RShift" }, { "LeftControl", 0xA2, "LCtrl" },
		{ "RightControl", 0xA3, "RCtrl" }, { "LeftAlt", 0xA4, "LAlt" }, { "RightAlt", 0xA5, "RAlt" },         -- 41-46
		{ "Up", 0x26, "Up" }, { "Down", 0x28, "Down" }, { "Left", 0x25, "Left" }, { "Right", 0x27, "Right" },   -- 47-50
		{ "Insert", 0x2D, "Ins" }, { "Delete", 0x2E, "Del" }, { "Home", 0x24, "Home" }, { "End", 0x23, "End" },
		{ "PageUp", 0x21, "PgUp" }, { "PageDown", 0x22, "PgDn" },                                              -- 51-56
		{ "F1", 0x70, "F1" }, { "F2", 0x71, "F2" }, { "F3", 0x72, "F3" }, { "F4", 0x73, "F4" }, { "F5", 0x74, "F5" },
		{ "F6", 0x75, "F6" }, { "F7", 0x76, "F7" }, { "F8", 0x77, "F8" }, { "F9", 0x78, "F9" }, { "F10", 0x79, "F10" },
		{ "F11", 0x7A, "F11" }, { "F12", 0x7B, "F12" },                                                        -- 57-68
		{ "Minus", 0xBD, "-" }, { "Equals", 0xBB, "=" }, { "LeftBracket", 0xDB, "[" }, { "RightBracket", 0xDD, "]" },
		{ "BackSlash", 0xDC, "\\" }, { "Semicolon", 0xBA, ";" }, { "Quote", 0xDE, "'" }, { "Comma", 0xBC, "," },
		{ "Period", 0xBE, "." }, { "Slash", 0xBF, "/" }, { "Backquote", 0xC0, "`" }, { "CapsLock", 0x14, "Caps" }, -- 69-80
		{ "KeypadZero", 0x60, "Num0" }, { "KeypadOne", 0x61, "Num1" }, { "KeypadTwo", 0x62, "Num2" },
		{ "KeypadThree", 0x63, "Num3" }, { "KeypadFour", 0x64, "Num4" }, { "KeypadFive", 0x65, "Num5" },
		{ "KeypadSix", 0x66, "Num6" }, { "KeypadSeven", 0x67, "Num7" }, { "KeypadEight", 0x68, "Num8" },
		{ "KeypadNine", 0x69, "Num9" }, { "KeypadMultiply", 0x6A, "Num*" }, { "KeypadPlus", 0x6B, "Num+" },
		{ "KeypadMinus", 0x6D, "Num-" }, { "KeypadPeriod", 0x6E, "Num." }, { "KeypadDivide", 0x6F, "Num/" }, -- 81-95
		{ false, false, "LMB" }, { false, false, "RMB" },                                                      -- 96, 97 = mouse buttons
	}
	local ID_M1, ID_M2 = 96, 97

	local KEY_BY_ENUM = {}  -- Enum.KeyCode item -> id
	local KEY_VK = {}       -- id -> virtual key code
	local KEY_SHORT = {}    -- id -> short name
	for id, k in ipairs(KEYLIST) do
		KEY_SHORT[id] = k[3]
		if k[1] then
			local ok, item = pcall(function() return Enum.KeyCode[k[1]] end)
			if ok and item then
				KEY_BY_ENUM[item] = id
				KEY_VK[id] = k[2]
			end
		end
	end

	local function isMouseId(id) return id == ID_M1 or id == ID_M2 end

	-- ------------------------------------------------------------------ the keys that control the TAS tool itself
	local controlIds, controlDirty = {}, true
	local function getControlIds()
		if controlDirty then
			controlDirty = false
			controlIds = {}
			for _, v in ipairs(ControlValues:GetChildren()) do
				local item = ToKey[v.Value]
				if item then
					if item == Enum.UserInputType.MouseButton1 then controlIds[ID_M1] = true
					elseif item == Enum.UserInputType.MouseButton2 then controlIds[ID_M2] = true
					elseif KEY_BY_ENUM[item] then controlIds[KEY_BY_ENUM[item]] = true end
				end
			end
		end
		return controlIds
	end

	local function setting(name)
		local v = SettingValues:FindFirstChild(name)
		return v ~= nil and v.Value ~= 0
	end

	-- ------------------------------------------------------------------ live capture
	local live = { held = {} } -- keys that are physically down right now (ids), without the TAS control keys
	local queue = {}           -- events since the last recorded frame
	local ownWindows = {}      -- this tool's own windows (set in Start)
	InputSys.Live = live

	local function pushEvent(e)
		queue[#queue + 1] = e
		if #queue > 256 then table.remove(queue, 1) end
	end

	local function overOwnUI()
		local okM, m = pcall(UIS.GetMouseLocation, UIS)
		if not okM then return false end
		local inset = Vector2.new(0, 0)
		if GuiService then pcall(function() inset = GuiService:GetGuiInset() end) end
		for _, f in ipairs(ownWindows) do
			if f.Visible then
				local p, s = f.AbsolutePosition, f.AbsoluteSize
				for _, pt in ipairs({ m, m - inset }) do -- gui coordinates may or may not include the top bar
					if pt.X >= p.X and pt.X <= p.X + s.X and pt.Y >= p.Y and pt.Y <= p.Y + s.Y then
						return true
					end
				end
			end
		end
		return false
	end

	local function idOf(inp)
		local t = inp.UserInputType
		if t == Enum.UserInputType.Keyboard then
			return KEY_BY_ENUM[inp.KeyCode]
		elseif t == Enum.UserInputType.MouseButton1 then
			return ID_M1
		elseif t == Enum.UserInputType.MouseButton2 then
			return ID_M2
		end
		return nil
	end

	local function ignoring()
		if UIS:GetFocusedTextBox() ~= nil then return true end -- typing (chat, text boxes)
		if GuiService and GuiService.MenuIsOpen then return true end -- Roblox's escape menu
		return false
	end

	local function onBegan(inp)
		local id = idOf(inp)
		if not id or getControlIds()[id] or ignoring() then return end
		if isMouseId(id) and overOwnUI() then return end
		if live.held[id] then return end
		live.held[id] = true
		pushEvent(id)
	end

	local function onEnded(inp)
		local id = idOf(inp)
		if id and live.held[id] then
			live.held[id] = nil
			pushEvent(-id)
		end
	end

	local function onChanged(inp)
		if inp.UserInputType ~= Enum.UserInputType.MouseWheel then return end
		if ignoring() or overOwnUI() then return end
		pushEvent(SCROLL_BASE + (inp.Position.Z > 0 and 1 or -1))
	end

	-- the window lost focus: Roblox may never send the key-up events
	local function onFocusLost()
		for id in pairs(live.held) do pushEvent(-id) end
		live.held = {}
	end

	-- ------------------------------------------------------------------ recording side
	-- events since the last recorded frame (or nil), clears the queue
	function InputSys.Take()
		if #queue == 0 then return nil end
		local q = queue
		queue = {}
		return q
	end

	function InputSys.Clear()
		if #queue > 0 then queue = {} end
	end

	function InputSys.Mouse()
		local v = UIS:GetMouseLocation()
		return floor(v.X + 0.5), floor(v.Y + 0.5)
	end

	-- the keys the recording says are held after frame `upTo` (a plain set of ids). `base` = state before frame 1.
	function InputSys.HeldAt(data, upTo, base)
		local set = {}
		if base then for id in pairs(base) do set[id] = true end end
		for i = 1, math.min(upTo, #data) do
			local ev = data[i].Input
			if ev then
				for k = 1, #ev do
					local e = ev[k]
					if e < SCROLL_LIMIT then
						if e > 0 then set[e] = true else set[-e] = nil end
					end
				end
			end
		end
		return set
	end

	-- called right before recording continues after `data`: the new part of the TAS must start from the keys the
	-- player is physically holding now, so the difference to the recorded state becomes the first events
	function InputSys.BeginRecording(data, base)
		queue = {}
		local want = InputSys.HeldAt(data, #data, base)
		local ids = {}
		for id in pairs(want) do if not live.held[id] then ids[#ids + 1] = -id end end
		for id in pairs(live.held) do if not want[id] then ids[#ids + 1] = id end end
		table.sort(ids, function(a, b) return math.abs(a) < math.abs(b) end)
		for _, e in ipairs(ids) do queue[#queue + 1] = e end
	end

	-- ------------------------------------------------------------------ display helpers
	function InputSys.Describe(set)
		local ids = {}
		for id in pairs(set) do ids[#ids + 1] = id end
		table.sort(ids)
		local names = {}
		for i, id in ipairs(ids) do names[i] = KEY_SHORT[id] or "?" end
		if #names == 0 then return "-" end
		return table.concat(names, " ")
	end

	-- ------------------------------------------------------------------ replay side
	local replay = { active = false, applied = 0, injected = {}, state = {} }
	InputSys.Replay = replay

	local function windowActive()
		if type(fActive) ~= "function" then return true end
		local ok, a = pcall(fActive)
		return (not ok) or a ~= false
	end

	local function allowed(id) -- may this id be sent right now?
		if getControlIds()[id] then return false end -- never press the keys that run this tool
		if isMouseId(id) then return InputSys.Available.Clicks and setting("Replay Mouse Clicks") end
		return InputSys.Available.Keys and setting("Replay Keyboard") and KEY_VK[id] ~= nil
	end

	local function sendDown(id)
		local ok = pcall(function()
			if id == ID_M1 then fM1Down() elseif id == ID_M2 then fM2Down() else fKeyDown(KEY_VK[id]) end
		end)
		return ok
	end
	local function sendUp(id)
		pcall(function()
			if id == ID_M1 then fM1Up() elseif id == ID_M2 then fM2Up() else fKeyUp(KEY_VK[id]) end
		end)
	end

	local function press(id)
		replay.state[id] = true
		if replay.injected[id] or not allowed(id) or not windowActive() then return end
		if sendDown(id) then replay.injected[id] = true end
	end
	local function release(id)
		replay.state[id] = nil
		if replay.injected[id] then
			sendUp(id) -- release even if the setting was switched off in the meantime
			replay.injected[id] = nil
		end
	end

	local function applyEvent(e)
		if e >= SCROLL_LIMIT then
			local notches = e - SCROLL_BASE
			if notches ~= 0 and InputSys.Available.Scroll and setting("Replay Mouse Clicks") and windowActive() then
				pcall(fScroll, notches * SCROLL_UNIT)
			end
		elseif e > 0 then
			press(e)
		else
			release(-e)
		end
	end

	local function syncTo(desired)
		for id in pairs(replay.injected) do
			if not desired[id] then release(id) end
		end
		for id in pairs(replay.state) do
			if not desired[id] then replay.state[id] = nil end
		end
		for id in pairs(desired) do
			if not replay.state[id] or not replay.injected[id] then press(id) end
		end
	end

	function InputSys.IsReplaying() return replay.active end

	-- a test starts at `startFrame`: put the keys in the state the recording had just before it
	function InputSys.ReplayBegin(data, startFrame)
		InputSys.ReplayEnd()
		replay.active = true
		replay.applied = startFrame - 1
		syncTo(InputSys.HeldAt(data, startFrame - 1))
	end

	-- the test has reached `frame`: send the events of every frame that was passed since the last call
	function InputSys.ReplayTo(data, frame)
		if not replay.active then return end
		if frame > replay.applied then
			for f = replay.applied + 1, math.min(frame, #data) do
				local ev = data[f].Input
				if ev then
					for k = 1, #ev do applyEvent(ev[k]) end
				end
			end
		elseif frame < replay.applied then
			syncTo(InputSys.HeldAt(data, frame)) -- went backwards: only fix the held keys, never replay events
		end
		replay.applied = frame
	end

	-- the cursor goes to the recorded spot, or to the middle of the screen while the mouse is locked (shift lock /
	-- first person) so the camera doesn't get pushed around. Unlike Tasability it is only moved when the recorded
	-- spot CHANGES: re-sending the same position every frame fights with a locked cursor (right click drag).
	function InputSys.ReplayMouse(fr)
		if not replay.active or not fr or fr.MX == nil then return end
		if not (InputSys.Available.Move and setting("Replay Mouse Movement")) then return end
		if not windowActive() then return end
		local tx, ty = fr.MX, fr.MY
		if fr.ShiftLock == 1 or (fr.Zoom or 99) <= 0.52 then
			local vs = workspace.CurrentCamera.ViewportSize
			tx, ty = floor(vs.X / 2), floor(vs.Y / 2)
		end
		if tx ~= replay.lastMX or ty ~= replay.lastMY then
			replay.lastMX, replay.lastMY = tx, ty
			pcall(fMoveAbs, tx, ty)
		end
	end

	-- releases everything this tool pressed
	function InputSys.ReplayEnd()
		local had = replay.active
		for id in pairs(replay.injected) do sendUp(id) end
		replay.injected = {}
		replay.state = {}
		replay.active = false
		replay.applied = 0
		replay.lastMX, replay.lastMY = nil, nil
		return had
	end

	-- ------------------------------------------------------------------ start
	function InputSys.Start(gui)
		ownWindows = { gui.MainMenu, gui.Merge, gui.MergeStats, gui.JoinMessage }
		on(UIS.InputBegan, onBegan)
		on(UIS.InputEnded, onEnded)
		on(UIS.InputChanged, onChanged)
		pcall(function() on(UIS.WindowFocusReleased, onFocusLost) end)
		for _, v in ipairs(ControlValues:GetChildren()) do
			on(v.Changed, function() controlDirty = true end)
		end
		Janitor.add(function() InputSys.ReplayEnd() end)
		local miss = {}
		for k, v in pairs(InputSys.Available) do if not v then miss[#miss + 1] = k end end
		if #miss > 0 then
			table.sort(miss)
			warnf("Your executor is missing input functions for: " .. table.concat(miss, ", ") .. " (those parts are recorded but not replayed)")
		end
	end
end

-- ================================================================================================
--  ANIMATE ENGINE  (port of the forked R6 Animate LocalScript)
--  Only used on R6 characters. It records which animation starts on which frame and can replay them,
--  which a stock Animate can't do. Other rigs keep the game's own animations (positions still replay).
-- ================================================================================================
local AnimEngine = { current = nil, disabledAnimate = nil, emotesWereEnabled = nil }
do
	local function A(id) return "http://www.roblox.com/asset/?id=" .. id end
	-- effective animation sets of the original script (its config children + built in defaults)
	local ANIM_DEFS = {
		idle      = { { id = A(180435571), weight = 9 }, { id = A(180435792), weight = 1 } },
		walk      = { { id = A(180426354), weight = 1 } },
		run       = { { id = A(180426354), weight = 1 } },
		jump      = { { id = A(125750702), weight = 1 } },
		fall      = { { id = A(180436148), weight = 1 } },
		climb     = { { id = A(180436334), weight = 1 } },
		sit       = { { id = A(178130996), weight = 1 } },
		toolnone  = { { id = A(182393478), weight = 1 } },
		toolslash = { { id = A(129967390), weight = 10 } },
		toollunge = { { id = A(129967478), weight = 10 } },
		wave      = { { id = A(128777973), weight = 10 } },
		point     = { { id = A(128853357), weight = 10 } },
		dance1    = { { id = A(182435998), weight = 10 }, { id = A(182491037), weight = 10 }, { id = A(182491065), weight = 10 } },
		dance2    = { { id = A(182436842), weight = 10 }, { id = A(182491248), weight = 10 }, { id = A(182491277), weight = 10 } },
		dance3    = { { id = A(182436935), weight = 10 }, { id = A(182491368), weight = 10 }, { id = A(182491423), weight = 10 } },
		laugh     = { { id = A(129423131), weight = 10 } },
		cheer     = { { id = A(129423030), weight = 10 } },
	}
	local dances = { "dance1", "dance2", "dance3" }
	-- existence in this list means "is an emote", the value says whether the emote loops
	local emoteNames = { wave = false, point = false, dance1 = true, dance2 = true, dance3 = true, laugh = false, cheer = false }

	-- numbers stored inside saved TAS files (do not reorder). 'dance' was the old name of dance1
	local AnimToNumber = {
		idle = 1, walk = 2, fall = 3, jump = 4, climb = 5, sit = 6, dance = 7, dance1 = 7, dance2 = 8, dance3 = 9,
		wave = 10, cheer = 11, point = 12, laugh = 13,
	}
	local NumberToAnim = { "idle", "walk", "fall", "jump", "climb", "sit", "dance1", "dance2", "dance3", "wave", "cheer", "point", "laugh" }

	local PoseToNumber = {
		Running = 1, Standing = 2, Jumping = 3, Climbing = 4, GettingUp = 5, FreeFall = 6, FallingDown = 7,
		Seated = 8, PlatformStanding = 9,
	}
	local NumberToPose = { "Running", "Standing", "Jumping", "Climbing", "GettingUp", "FreeFall", "FallingDown", "Seated", "PlatformStanding" }

	local EMOTE_TRANSITION_TIME = 0.1

	local function newEngine(Figure, Humanoid, Torso)
		local self = { alive = true }
		local conns = {}
		local function connect(sig, fn)
			local cn = sig:Connect(fn)
			conns[#conns + 1] = cn
			return cn
		end

		local RightShoulder = Torso:FindFirstChild("Right Shoulder")
		local LeftShoulder = Torso:FindFirstChild("Left Shoulder")
		local RightHip = Torso:FindFirstChild("Right Hip")
		local LeftHip = Torso:FindFirstChild("Left Hip")
		if not (RightShoulder and LeftShoulder and RightHip and LeftHip) then return nil end

		-- TAS variables
		local FrameAnims = {}
		local LockAnimations = false

		local pose = "Standing"
		local userAnimateScaleRun = false
		pcall(function() userAnimateScaleRun = UserSettings():IsUserFeatureEnabled("UserAnimateScaleRun") end)
		local function getRigScale()
			if userAnimateScaleRun then
				local ok, s = pcall(function() return Figure:GetScale() end)
				if ok and s then return s end
			end
			return 1
		end

		local currentAnim = ""
		local currentAnimInstance = nil
		local currentAnimTrack = nil
		local currentAnimKeyframeHandler = nil
		local currentAnimSpeed = 1.0

		local animTable = {}
		for name, list in pairs(ANIM_DEFS) do
			local t = { count = 0, totalWeight = 0 }
			for i, a in ipairs(list) do
				local anim = Instance.new("Animation")
				anim.Name = name
				anim.AnimationId = a.id
				t[i] = { anim = anim, weight = a.weight }
				t.count = t.count + 1
				t.totalWeight = t.totalWeight + a.weight
			end
			animTable[name] = t
		end

		-- clear any existing animation tracks (the game's own Animate may have started some)
		local animator = Humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				pcall(function() track:Stop(0) track:Destroy() end)
			end
		end

		local toolAnim = "None"
		local toolAnimTime = 0

		local jumpAnimTime = 0
		local jumpAnimDuration = 0.3

		local toolTransitionTime = 0.1
		local fallTransitionTime = 0.3

		local playAnimation, stopAllAnimations, setAnimationSpeed, keyFrameReachedFunc
		local playToolAnimation, stopToolAnimations, toolKeyFrameReachedFunc

		function stopAllAnimations()
			local oldAnim = currentAnim

			-- return to idle if finishing an emote
			if emoteNames[oldAnim] ~= nil and emoteNames[oldAnim] == false then
				oldAnim = "idle"
			end

			currentAnim = ""
			currentAnimInstance = nil
			if currentAnimKeyframeHandler ~= nil then
				currentAnimKeyframeHandler:Disconnect()
				currentAnimKeyframeHandler = nil
			end

			if currentAnimTrack ~= nil then
				currentAnimTrack:Stop()
				currentAnimTrack:Destroy()
				currentAnimTrack = nil
			end
			return oldAnim
		end

		function setAnimationSpeed(speed, TASanim)
			if (speed ~= currentAnimSpeed and LockAnimations == false) or TASanim then
				currentAnimSpeed = speed
				if currentAnimTrack then currentAnimTrack:AdjustSpeed(currentAnimSpeed) end
			end
		end

		function keyFrameReachedFunc(frameName)
			if frameName == "End" then
				local repeatAnim = currentAnim
				-- return to idle if finishing an emote
				if emoteNames[repeatAnim] ~= nil and emoteNames[repeatAnim] == false then
					repeatAnim = "idle"
				end

				local animSpeed = currentAnimSpeed
				playAnimation(repeatAnim, 0.0, Humanoid)
				setAnimationSpeed(animSpeed, false)
			end
		end

		function playAnimation(animName, transitionTime, humanoid, TASanim)
			if not TASanim and LockAnimations then
				return
			end
			if not animTable[animName] then return end

			local roll = math.random(1, animTable[animName].totalWeight)
			local idx = 1
			while roll > animTable[animName][idx].weight do
				roll = roll - animTable[animName][idx].weight
				idx = idx + 1
			end
			local anim = animTable[animName][idx].anim

			-- switch animation
			if anim ~= currentAnimInstance then

				if not TASanim and AnimToNumber[animName] then
					table.insert(FrameAnims, { AnimToNumber[animName], transitionTime })
				end

				if currentAnimTrack ~= nil then
					currentAnimTrack:Stop(transitionTime)
					currentAnimTrack:Destroy()
				end

				currentAnimSpeed = 1.0

				-- load it to the humanoid; get AnimationTrack
				currentAnimTrack = humanoid:LoadAnimation(anim)
				currentAnimTrack.Priority = Enum.AnimationPriority.Core

				-- play the animation
				currentAnimTrack:Play(transitionTime)
				currentAnim = animName
				currentAnimInstance = anim

				-- set up keyframe name triggers
				if currentAnimKeyframeHandler ~= nil then
					currentAnimKeyframeHandler:Disconnect()
				end
				currentAnimKeyframeHandler = currentAnimTrack.KeyframeReached:Connect(keyFrameReachedFunc)
			end
		end

		-------------------------------------------------------------------------------------------
		local toolAnimName = ""
		local toolAnimTrack = nil
		local toolAnimInstance = nil
		local currentToolAnimKeyframeHandler = nil

		function toolKeyFrameReachedFunc(frameName)
			if frameName == "End" then
				playToolAnimation(toolAnimName, 0.0, Humanoid)
			end
		end

		function playToolAnimation(animName, transitionTime, humanoid, priority)
			if not animTable[animName] then return end
			local roll = math.random(1, animTable[animName].totalWeight)
			local idx = 1
			while roll > animTable[animName][idx].weight do
				roll = roll - animTable[animName][idx].weight
				idx = idx + 1
			end
			local anim = animTable[animName][idx].anim

			if toolAnimInstance ~= anim then

				if toolAnimTrack ~= nil then
					toolAnimTrack:Stop()
					toolAnimTrack:Destroy()
					transitionTime = 0
				end

				-- load it to the humanoid; get AnimationTrack
				toolAnimTrack = humanoid:LoadAnimation(anim)
				if priority then
					toolAnimTrack.Priority = priority
				end

				-- play the animation
				toolAnimTrack:Play(transitionTime)
				toolAnimName = animName
				toolAnimInstance = anim

				currentToolAnimKeyframeHandler = toolAnimTrack.KeyframeReached:Connect(toolKeyFrameReachedFunc)
			end
		end

		function stopToolAnimations()
			local oldAnim = toolAnimName

			if currentToolAnimKeyframeHandler ~= nil then
				currentToolAnimKeyframeHandler:Disconnect()
			end

			toolAnimName = ""
			toolAnimInstance = nil
			if toolAnimTrack ~= nil then
				toolAnimTrack:Stop()
				toolAnimTrack:Destroy()
				toolAnimTrack = nil
			end

			return oldAnim
		end

		-------------------------------------------------------------------------------------------
		local function onRunning(speed)
			speed = speed / getRigScale()

			if speed > 0.01 then
				playAnimation("walk", 0.1, Humanoid)
				if currentAnimInstance and currentAnimInstance.AnimationId == "http://www.roblox.com/asset/?id=180426354" then
					setAnimationSpeed(speed / 14.5, false)
				end
				pose = "Running"
			else
				if emoteNames[currentAnim] == nil then
					playAnimation("idle", 0.1, Humanoid)
					pose = "Standing"
				end
			end
		end

		local function onDied()
			pose = "Dead"
		end

		local function onJumping()
			playAnimation("jump", 0.1, Humanoid)
			jumpAnimTime = jumpAnimDuration
			pose = "Jumping"
		end

		local function onClimbing(speed)
			speed = speed / getRigScale()

			playAnimation("climb", 0.1, Humanoid)
			setAnimationSpeed(speed / 12.0, false)
			pose = "Climbing"
		end

		local function onGettingUp()
			pose = "GettingUp"
		end

		local function onFreeFall()
			if jumpAnimTime <= 0 then
				playAnimation("fall", fallTransitionTime, Humanoid)
			end
			pose = "FreeFall"
		end

		local function onFallingDown()
			pose = "FallingDown"
		end

		local function onSeated()
			pose = "Seated"
		end

		local function onPlatformStanding()
			pose = "PlatformStanding"
		end

		local function onSwimming(speed)
			if speed > 0 then
				pose = "Running"
			else
				pose = "Standing"
			end
		end

		local function getTool()
			for _, kid in ipairs(Figure:GetChildren()) do
				if kid.ClassName == "Tool" then return kid end
			end
			return nil
		end

		local function getToolAnim(tool)
			for _, ch in ipairs(tool:GetChildren()) do
				if ch.Name == "toolanim" and ch.ClassName == "StringValue" then
					return ch
				end
			end
			return nil
		end

		local function animateTool()
			if toolAnim == "None" then
				playToolAnimation("toolnone", toolTransitionTime, Humanoid, Enum.AnimationPriority.Idle)
				return
			end

			if toolAnim == "Slash" then
				playToolAnimation("toolslash", 0, Humanoid, Enum.AnimationPriority.Action)
				return
			end

			if toolAnim == "Lunge" then
				playToolAnimation("toollunge", 0, Humanoid, Enum.AnimationPriority.Action)
				return
			end
		end

		local function move(time)
			local amplitude = 1
			local frequency = 1
			local climbFudge = 0
			local setAngles = false

			if pose == "FreeFall" and jumpAnimTime <= 0 then
				playAnimation("fall", fallTransitionTime, Humanoid)
			elseif pose == "Seated" then
				playAnimation("sit", 0.5, Humanoid)
				return
			elseif pose == "Running" then
				playAnimation("walk", 0.1, Humanoid)
			elseif pose == "Dead" or pose == "GettingUp" or pose == "FallingDown" or pose == "Seated" or pose == "PlatformStanding" then
				stopAllAnimations()
				amplitude = 0.1
				frequency = 1
				setAngles = true
			end

			if setAngles then
				local desiredAngle = amplitude * math.sin(time * frequency)

				RightShoulder:SetDesiredAngle(desiredAngle + climbFudge)
				LeftShoulder:SetDesiredAngle(desiredAngle - climbFudge)
				RightHip:SetDesiredAngle(-desiredAngle)
				LeftHip:SetDesiredAngle(-desiredAngle)
			end

			-- Tool Animation handling
			local tool = getTool()
			if tool and tool:FindFirstChild("Handle") then

				local animStringValueObject = getToolAnim(tool)

				if animStringValueObject then
					toolAnim = animStringValueObject.Value
					-- message recieved, delete StringValue
					animStringValueObject.Parent = nil
					toolAnimTime = time + .3
				end

				if time > toolAnimTime then
					toolAnimTime = 0
					toolAnim = "None"
				end

				animateTool()
			else
				stopToolAnimations()
				toolAnim = "None"
				toolAnimInstance = nil
				toolAnimTime = 0
			end
		end

		-- connect events
		connect(Humanoid.Died, onDied)
		connect(Humanoid.Running, onRunning)
		connect(Humanoid.Jumping, onJumping)
		connect(Humanoid.Climbing, onClimbing)
		connect(Humanoid.GettingUp, onGettingUp)
		connect(Humanoid.FreeFalling, onFreeFall)
		connect(Humanoid.FallingDown, onFallingDown)
		connect(Humanoid.Seated, onSeated)
		connect(Humanoid.PlatformStanding, onPlatformStanding)
		connect(Humanoid.Swimming, onSwimming)

		---- emote chat hook (/e dance, /e wave ...)
		connect(LocalPlayer.Chatted, function(msg)
			local emote = ""
			if msg == "/e dance" then
				emote = dances[math.random(1, #dances)]
			elseif string.sub(msg, 1, 3) == "/e " then
				emote = string.sub(msg, 4)
			elseif string.sub(msg, 1, 7) == "/emote " then
				emote = string.sub(msg, 8)
			end

			if pose == "Standing" and emoteNames[emote] ~= nil then
				playAnimation(emote, EMOTE_TRANSITION_TIME, Humanoid)
			end
		end)

		-- TAS hooks (these were the GetAnimation / SetAnimation / LockAnimations bindables) ------
		function self.Get(StartOfTAS)
			if currentAnimTrack ~= nil then
				return {
					Pose = PoseToNumber[pose] or 0,
					JumpTime = math.round(jumpAnimTime * 1000) / 1000,
					Speed = math.round(currentAnimSpeed * 1000) / 1000,
					Anims = StartOfTAS and { { AnimToNumber[currentAnim] or 1, 0 } } or FrameAnims,
				}
			end
			return nil
		end

		function self.Set(AnimData, anim, PlaybackSpeed, TimeDifference)
			if anim then
				for _, v in pairs(anim) do
					local name = NumberToAnim[v[1]]
					if name and name ~= currentAnim then
						playAnimation(name, v[2] or 0, Humanoid, true)
					end
				end
			end

			pose = NumberToPose[AnimData.Pose] or pose
			jumpAnimTime = AnimData.JumpTime or 0
			setAnimationSpeed((AnimData.Speed or 1) * (PlaybackSpeed or 1), true)
			if TimeDifference and currentAnimTrack then
				currentAnimTrack.TimePosition = TimeDifference
			end
		end

		function self.Lock(lock)
			LockAnimations = lock
		end

		function self.Destroy()
			if not self.alive then return end
			self.alive = false
			for _, cn in ipairs(conns) do pcall(function() cn:Disconnect() end) end
			conns = {}
			pcall(stopToolAnimations)
			pcall(function()
				if currentAnimKeyframeHandler then currentAnimKeyframeHandler:Disconnect() end
				if currentAnimTrack then currentAnimTrack:Stop(0) currentAnimTrack:Destroy() currentAnimTrack = nil end
			end)
		end

		-- initialize to idle (and catch up with whatever the humanoid is doing right now)
		playAnimation("idle", 0.1, Humanoid)
		pose = "Standing"
		local st = Humanoid:GetState()
		if st == Enum.HumanoidStateType.Running or st == Enum.HumanoidStateType.RunningNoPhysics then
			onRunning(Humanoid.RootPart and Vector3.new(Humanoid.RootPart.AssemblyLinearVelocity.X, 0, Humanoid.RootPart.AssemblyLinearVelocity.Z).Magnitude or 0)
		elseif st == Enum.HumanoidStateType.Freefall then
			onFreeFall()
		elseif st == Enum.HumanoidStateType.Climbing then
			onClimbing(0)
		end

		connect(RunService.Heartbeat, function(deltaTime)
			FrameAnims = {} -- a NEW table every frame: the recorded frames keep the old one
			if jumpAnimTime > 0 then
				jumpAnimTime = jumpAnimTime - deltaTime
			end
		end)

		task.spawn(function()
			while self.alive and Figure.Parent ~= nil do
				task.wait(0.1)
				if not self.alive then break end
				local ok, err = pcall(move, os.clock())
				if not ok then log("animate move error", err) end
			end
		end)

		return self
	end

	-- ---------------------------------------------------------------------------- attach / detach
	function AnimEngine.Detach()
		if AnimEngine.current then
			pcall(AnimEngine.current.Destroy)
			AnimEngine.current = nil
		end
		local old = AnimEngine.disabledAnimate
		AnimEngine.disabledAnimate = nil
		if old and old.Parent then
			pcall(function() old.Disabled = false end)
		end
	end

	function AnimEngine.Attach(char)
		AnimEngine.Detach()
		if not CONFIG.TakeOverAnimate then return end
		task.spawn(function()
			local hum = char:WaitForChild("Humanoid", 10)
			if not hum or Janitor.unloading then return end
			if hum.RigType ~= Enum.HumanoidRigType.R6 then
				log("not an R6 rig, the game's animations are left alone")
				return
			end
			local torso = char:WaitForChild("Torso", 5)
			if not torso or Janitor.unloading or char.Parent == nil then return end

			-- two Animate scripts would fight over the tracks, so the game's one is switched off
			local old = char:FindFirstChild("Animate")
			if old and old:IsA("LocalScript") then
				local okD = pcall(function() old.Disabled = true end)
				if okD then AnimEngine.disabledAnimate = old end
			end
			if AnimEngine.emotesWereEnabled == nil and StarterGui then
				local okG, enabled = pcall(function() return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu) end)
				if okG then
					AnimEngine.emotesWereEnabled = enabled
					pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false) end)
				end
			end

			local okE, engine = pcall(newEngine, char, hum, torso)
			if okE and engine then
				if Janitor.unloading or char.Parent == nil then
					engine.Destroy()
					return
				end
				AnimEngine.current = engine
			else
				warnf("Animate engine failed to start:", tostring(engine))
				-- give the game's own animations back
				local o = AnimEngine.disabledAnimate
				AnimEngine.disabledAnimate = nil
				if o and o.Parent then pcall(function() o.Disabled = false end) end
			end
		end)
	end

	function AnimEngine.Shutdown()
		AnimEngine.Detach()
		if AnimEngine.emotesWereEnabled ~= nil and StarterGui then
			local was = AnimEngine.emotesWereEnabled
			AnimEngine.emotesWereEnabled = nil
			pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, was) end)
		end
	end

	-- plug into the bridge ---------------------------------------------------------------------
	local EMPTY_ANIM_FRAME = function()
		return { Pose = 0, JumpTime = 0, Speed = 1, Anims = {} }
	end
	function Bridge.GetAnimation(startOfTAS)
		local e = AnimEngine.current
		if e then
			local d = e.Get(startOfTAS)
			if d then return d end
		end
		return EMPTY_ANIM_FRAME() -- keeps the saved frame layout valid on rigs we don't animate
	end
	function Bridge.SetAnimation(animData, anim, playbackSpeed, timeDifference)
		local e = AnimEngine.current
		if e and animData then e.Set(animData, anim, playbackSpeed, timeDifference) end
	end
	function Bridge.LockAnimations(lock)
		local e = AnimEngine.current
		if e then e.Lock(lock) end
	end
end

-- ================================================================================================
--  TAS CORE  (port of the TASMain LocalScript + SetStats module)
-- ================================================================================================
local Core = {}
do
	local p = LocalPlayer
	local rs = RunService
	local uis = UIS
	local Controls = ControlValues
	local Settings = SettingValues

	local Gui, MobileUI, MergeStats, IdleStatsF, CreateStatsF, TestStatsF

	local data = {}
	local mode = 1
	local frame = 1
	local paused = true
	local back = false
	local forw = false
	local LastPause = 1
	local FirstFrameRecord = false
	local LastFrameTime = 0
	local LookAround = false
	local TestingTimer = 0
	local CurrentFrameInput = false
	local InputDebounce = 0
	local FreezeTimeRemaining = 0

	local merge = false
	local mergeBefore = {}
	local mergeAfter = {}
	local oldTAS = {}
	local mergeReqDist = nil
	local mergeCFrame = nil
	local mergeCanComplete = false -- was MergeStats["3"].CanComplete (a BoolValue)
	local mergeBaseHeld = nil -- keys that were held when the first half of a merge ended

	local IsMobile = uis.TouchEnabled
	local QuitTestEvent = nil

	local Humanoid, Char, HRP

	-- forward declarations (the original used global functions)
	local GetSetting, SetCam, charload, NotDead, CharLoaded, SetStats, GetCameraZoom, SetCameraZoom
	local Vector3ToTable, TableToVector3, CFrameToTable, TableToCFrame, UpdateCamera, LoadFrame, anchor
	local RemoveCutFrames, CheckInput, SetStatus, ToTime, AveragedFrame, CanCoyoteJump, DoubleInput
	local JumpedOffLader, SetPauseButton, ShowCreateButtons, CreateMergeHitboxes, DestroyMergeHitboxes
	local inputs = {}
	local hitboxes = {}

	-- ---------------------------------------------------------------------------- SetStats module
	local SS = {}
	local NumberToState = {
		["0"] = "FallingDown", ["8"] = "Running", ["10"] = "RunningNoPhysics", ["12"] = "Climbing",
		["11"] = "StrafingNoPhysics", ["1"] = "Ragdoll", ["2"] = "GettingUp", ["3"] = "Jumping", ["7"] = "Landed",
		["6"] = "Flying", ["5"] = "Freefall", ["13"] = "Seated", ["14"] = "PlatformStanding", ["15"] = "Dead",
		["4"] = "Swimming", ["16"] = "Physics", ["18"] = "None",
	}

	local function TableToCFrameSafe(t)
		if t then
			return CFrame.new(table.unpack(t))
		else
			return CFrame.new(0, 0, 0)
		end
	end

	function ToTime(t)
		local secs = t - (t - t % 60)
		local mins = (t - t % 60) / 60

		secs = r(secs, 1000)
		local s = tostring(secs)
		local intPart = s:match("^%-?(%d+)") or "0"
		if #intPart < 2 then s = "0" .. s end

		return mins .. ":" .. s
	end

	-- held keys shown in the stat panels. While scrubbing a paused TAS the recording has to be scanned, so that is
	-- throttled (and only redone when the frame changed)
	local keysCache = { frame = -1, data = nil, text = "-", t = 0 }
	local function PausedKeysText(frameNo)
		if keysCache.data ~= data or keysCache.frame ~= frameNo then
			local now = os.clock()
			if keysCache.data ~= data or now - keysCache.t > 0.1 then
				keysCache.data, keysCache.frame, keysCache.t = data, frameNo, now
				keysCache.text = InputSys.Describe(InputSys.HeldAt(data, frameNo))
			end
		end
		return keysCache.text
	end
	local function MouseText(fr)
		if fr and fr.MX then return fr.MX .. ", " .. fr.MY end
		local x, y = InputSys.Mouse()
		return x .. ", " .. y
	end

	function SS.Hide()
		IdleStatsF.Visible = false
		CreateStatsF.Visible = false
		TestStatsF.Visible = false
	end

	function SS.Idle(FrameTime, zoom)
		local root = Char and Char:FindFirstChild("HumanoidRootPart")
		if not root then return end
		IdleStatsF.Visible = true
		CreateStatsF.Visible = false
		TestStatsF.Visible = false
		local CAX, CAY, CAZ = workspace.CurrentCamera.CFrame:ToEulerAnglesYXZ()
		local lv, av = root.AssemblyLinearVelocity, root.AssemblyAngularVelocity
		IdleStatsF["1"].Text = " Frame Time: " .. r(FrameTime, 1000000)
		IdleStatsF["2"].Text = " Root Position: " .. r(root.Position.X, 1000) .. ", " .. r(root.Position.Y, 1000) .. ", " .. r(root.Position.Z, 1000)
		IdleStatsF["3"].Text = " Root Rotation: " .. r(root.Orientation.X, 1000) .. ", " .. r(root.Orientation.Y, 1000) .. ", " .. r(root.Orientation.Z, 1000)
		IdleStatsF["4"].Text = " Root Linear Velocity: " .. r(lv.X, 1000) .. ", " .. r(lv.Y, 1000) .. ", " .. r(lv.Z, 1000)
		IdleStatsF["5"].Text = " Root Angular Velocity: " .. r(av.X, 1000) .. ", " .. r(av.Y, 1000) .. ", " .. r(av.Z, 1000)
		IdleStatsF["6"].Text = " Camera Rotation: " .. r(math.deg(CAX), 1000) .. ", " .. r(math.deg(CAY), 1000) .. ", " .. r(math.deg(CAZ), 1000)
		IdleStatsF["7"].Text = " Humanoid State: " .. Humanoid:GetState().Name
		IdleStatsF["8"].Text = " Zoom: " .. r(zoom, 1000)
	end

	function SS.Create(pausedNow, frameNo, FrameData)
		IdleStatsF.Visible = false
		CreateStatsF.Visible = true
		TestStatsF.Visible = false
		if pausedNow then
			CreateStatsF.BackgroundTransparency = .1
		else
			CreateStatsF.BackgroundTransparency = .2
		end
		CreateStatsF["1"].Text = " Frame: " .. frameNo
		if FrameData and FrameData.FrameTime and NumberToState[tostring(FrameData.State)] then
			local X, Y, Z = TableToCFrameSafe(FrameData.Cframe):GetComponents()
			local AX, AY, AZ = TableToCFrameSafe(FrameData.Cframe):ToEulerAnglesYXZ()
			local CAX, CAY, CAZ = TableToCFrameSafe(FrameData.CamCframe):ToEulerAnglesYXZ()
			CreateStatsF["2"].Text = " Frame Time: " .. FrameData.FrameTime
			CreateStatsF["3"].Text = " Total Time: " .. ToTime(FrameData.TotalTime)
			CreateStatsF["4"].Text = " Root Position: " .. r(X, 1000) .. ", " .. r(Y, 1000) .. ", " .. r(Z, 1000)
			CreateStatsF["5"].Text = " Root Rotation: " .. r(math.deg(AX), 1000) .. ", " .. r(math.deg(AY), 1000) .. ", " .. r(math.deg(AZ), 1000)
			CreateStatsF["6"].Text = " Root Linear Velocity: " .. FrameData.Velocity.Linear[1] .. ", " .. FrameData.Velocity.Linear[2] .. ", " .. FrameData.Velocity.Linear[3]
			CreateStatsF["7"].Text = " Root Angular Velocity: " .. FrameData.Velocity.Angular[1] .. ", " .. FrameData.Velocity.Angular[2] .. ", " .. FrameData.Velocity.Angular[3]
			CreateStatsF["8"].Text = " Camera Rotation: " .. r(math.deg(CAX), 1000) .. ", " .. r(math.deg(CAY), 1000) .. ", " .. r(math.deg(CAZ), 1000)
			CreateStatsF["9"].Text = " Humanoid State: " .. NumberToState[tostring(FrameData.State)]
			CreateStatsF["91"].Text = " Zoom: " .. FrameData.Zoom
			CreateStatsF["92"].Text = " Keys: " .. (pausedNow and PausedKeysText(frameNo) or InputSys.Describe(InputSys.Live.held))
			CreateStatsF["93"].Text = " Mouse: " .. MouseText(FrameData)
		else
			local root = Char and Char:FindFirstChild("HumanoidRootPart")
			if not root then return end
			local CAX, CAY, CAZ = workspace.CurrentCamera.CFrame:ToEulerAnglesYXZ()
			local lv, av = root.AssemblyLinearVelocity, root.AssemblyAngularVelocity
			CreateStatsF["2"].Text = " Frame Time: 0"
			CreateStatsF["3"].Text = " Total Time: 0"
			CreateStatsF["4"].Text = " Root Position: " .. r(root.Position.X, 1000) .. ", " .. r(root.Position.Y, 1000) .. ", " .. r(root.Position.Z, 1000)
			CreateStatsF["5"].Text = " Root Rotation: " .. r(root.Orientation.X, 1000) .. ", " .. r(root.Orientation.Y, 1000) .. ", " .. r(root.Orientation.Z, 1000)
			CreateStatsF["6"].Text = " Root Linear Velocity: " .. r(lv.X, 1000) .. ", " .. r(lv.Y, 1000) .. ", " .. r(lv.Z, 1000)
			CreateStatsF["7"].Text = " Root Angular Velocity: " .. r(av.X, 1000) .. ", " .. r(av.Y, 1000) .. ", " .. r(av.Z, 1000)
			CreateStatsF["8"].Text = " Camera Rotation: " .. r(math.deg(CAX), 1000) .. ", " .. r(math.deg(CAY), 1000) .. ", " .. r(math.deg(CAZ), 1000)
			CreateStatsF["9"].Text = " Humanoid State: " .. Humanoid:GetState().Name
			CreateStatsF["91"].Text = " Zoom: " .. r(Bridge.GetZoom(), 1000)
			CreateStatsF["92"].Text = " Keys: " .. InputSys.Describe(InputSys.Live.held)
			CreateStatsF["93"].Text = " Mouse: " .. MouseText(nil)
		end
	end

	function SS.Merge(reqDist, goalCFrame, FrameData)
		if type(FrameData) == "table" and FrameData.Cframe then
			local dist = (Vector3.new(FrameData.Cframe[1], FrameData.Cframe[2], FrameData.Cframe[3]) - Vector3.new(goalCFrame[1], goalCFrame[2], goalCFrame[3])).Magnitude
			MergeStats["1"].Text = " Current Distance: " .. r(dist, 1000)
			if dist < reqDist then
				MergeStats["3"].Text = " Click here to complete merge"
				MergeStats.BackgroundColor3 = Color3.fromRGB(0, 80, 0)
				mergeCanComplete = true
			else
				MergeStats["3"].Text = " Click here to cancel merge"
				MergeStats.BackgroundColor3 = Color3.fromRGB(100, 0, 0)
				mergeCanComplete = false
			end
		end
		MergeStats["2"].Text = " Distance Required: " .. r(reqDist, 1000)
	end

	function SS.Test(Timer, Speed)
		IdleStatsF.Visible = false
		CreateStatsF.Visible = false
		TestStatsF.Visible = true
		TestStatsF["1"].Text = " Time: " .. ToTime(r(Timer, 1000000))
		TestStatsF["2"].Text = " Playback Speed: " .. Speed
		TestStatsF["3"].Text = " Keys: " .. InputSys.Describe(InputSys.Replay.state)
		TestStatsF["4"].Text = " Mouse: " .. MouseText(data[frame])
	end

	-- ---------------------------------------------------------------------------- helpers
	function GetSetting(name)
		return Settings[name].Value
	end

	-- returns whether the camera cframe should change or not. This also affects player transparency and zoom. See LoadFrame function
	function SetCam()
		return (mode == 3 and GetSetting("Lock Camera (Test)") == 1) or (mode == 2 and GetSetting("Lock Camera (Paused)") == 1)
	end

	function charload(char)
		local hum = char:WaitForChild("Humanoid")
		local root = char:WaitForChild("HumanoidRootPart")
		Humanoid, HRP, Char = hum, root, char -- Char last: the frame loops only run once everything is ready
		hum.Died:Connect(function()
			mode = 1
			if #data > 0 then
				table.remove(data, #data)
			end
			Bridge.LockShiftlock(false) -- the original left shiftlock blocked if you died while testing
			Bridge.LockAnimations(false)
		end)
	end

	function NotDead()
		return Humanoid:GetState() ~= Enum.HumanoidStateType.Dead
	end

	function CharLoaded()
		return Char and Char:FindFirstChild("HumanoidRootPart") and Char:FindFirstChild("Humanoid")
	end

	function SetStats(statMode, FrameData, FrameTime, frameNo)
		if (GetSetting("Show Stats (" .. statMode .. ")") == 1) or (statMode == 3 and GetSetting("Playback Speed") ~= 1) then
			if statMode == "Idle" then
				SS.Idle(FrameTime, GetCameraZoom())
			elseif statMode == "Create" then
				SS.Create(paused, frameNo, FrameData)
			elseif statMode == "Test" then
				SS.Test(TestingTimer, GetSetting("Playback Speed"))
			end
		else
			SS.Hide()
		end
		if merge then
			SS.Merge(mergeReqDist, mergeCFrame, FrameData)
			MergeStats.Visible = true
		else
			MergeStats.Visible = false
		end
	end

	function GetCameraZoom()
		return Bridge.GetZoom()
	end

	function SetCameraZoom(zoom, static)
		Bridge.SetZoom(zoom, static)
	end

	function Vector3ToTable(V)
		return { r(V.X, 1000), r(V.Y, 1000), r(V.Z, 1000) }
	end
	function TableToVector3(t)
		return Vector3.new(table.unpack(t))
	end

	function CFrameToTable(C)
		local components = { C:GetComponents() }
		for i, v in pairs(components) do
			components[i] = r(v, 1000)
		end
		return components
	end
	function TableToCFrame(t)
		return CFrame.new(table.unpack(t))
	end

	function UpdateCamera(FrameData, UnlockShift)
		if not SetCam() then return end

		workspace.CurrentCamera.CFrame = TableToCFrame(FrameData.CamCframe)

		if not UnlockShift then
			local IsShiftLock = Bridge.IsShiftlocked() and 1 or 0
			if IsShiftLock ~= FrameData.ShiftLock then
				Bridge.ShiftlockSwitch()
			end
		end

		SetCameraZoom(FrameData.Zoom, mode == 2)
	end

	function LoadFrame(FrameData, unpausing, backtrack)
		if #data == 0 or not FrameData then return end
		-- a frame that is still being recorded has no position/state yet, there is nothing to load from it
		if not FrameData.Cframe or not FrameData.State or not FrameData.Velocity then return end

		local c = p.Character

		if not unpausing then
			if HRP.Anchored ~= (mode ~= 3) then
				anchor(mode ~= 3)
			end

			HRP.CFrame = TableToCFrame(FrameData.Cframe)
			UpdateCamera(FrameData)

		else -- when unpausing
			if SetCam() then
				SetCameraZoom(FrameData.Zoom, true)
			end
			LastPause = frame
			anchor(false)
		end

		HRP.AssemblyLinearVelocity = TableToVector3(FrameData.Velocity.Linear)
		HRP.AssemblyAngularVelocity = TableToVector3(FrameData.Velocity.Angular)

		c.Humanoid:ChangeState(FrameData.State)

		-- Backtracking finds the most recent animation to play when going back frames
		-- Since animations can be played multiple times in a row, it searches for the first occurance to match the AnimTime
		local BacktrackAnim, BacktrackAnimSpeed
		local AnimTime = 0
		if backtrack and frame > 2 then
			for i = frame, 1, -1 do
				local anims = data[i].Anim.Anims
				local speed = data[i].Anim.Speed
				AnimTime = AnimTime + data[i].FrameTime * speed
				if #anims > 0 then
					if BacktrackAnim and BacktrackAnim[1][1] ~= anims[#anims][1] then
						break
					end
					BacktrackAnim = { anims[#anims] }
					BacktrackAnimSpeed = speed
					break
				end
			end
		end

		if not BacktrackAnimSpeed then
			BacktrackAnimSpeed = 1
		end

		if FrameData.Anim and mode == 2 then
			Bridge.SetAnimation(FrameData.Anim, BacktrackAnim, (not unpausing) and 0 or BacktrackAnimSpeed, backtrack and AnimTime or nil)
		end
	end

	function anchor(value)
		HRP.Anchored = value
		Bridge.ShiftlockRotation(not value) -- so ur character doesnt look at camera when anchored
	end

	function RemoveCutFrames() -- job: remove all frames after unpaused
		for i = frame + 1, #data do
			table.remove(data, #data)
		end
	end

	function CheckInput(inp, control)
		return inp.KeyCode == ToKey[Controls[control].Value] or inp.UserInputType == ToKey[Controls[control].Value]
	end

	-- this script isnt supposed to have gui but whatever
	local ConfirmDelete, ConfirmOptimize = false, false
	function SetStatus(text, inverse)
		local old = Gui:FindFirstChild("Status")
		local status = old:Clone()
		old:Destroy()
		status.Text = text
		status.Parent = Gui
		if not inverse then
			for i = 0, 1.05, .05 do
				status.TextTransparency = i
				task.wait(.05)
			end
		else
			for i = 1, -.05, .05 do
				if QuitTestEvent then
					status.TextTransparency = i
					task.wait(.15)
				end
			end
		end
	end

	function AveragedFrame(Frame1, Frame2)
		local RootCFrame, CameraCFrame, LinearVelocity, AngularVelocity = {}, {}, {}, {}

		local t1 = TestingTimer - Frame1.TotalTime
		local t2 = Frame2.TotalTime - TestingTimer
		local total = t1 + t2
		local Weight1 = 1 - (t1 / total)
		local Weight2 = 1 - (t2 / total)

		for i = 1, 12 do
			table.insert(RootCFrame, Frame1.Cframe[i] * Weight1 + Frame2.Cframe[i] * Weight2)
			table.insert(CameraCFrame, Frame1.CamCframe[i] * Weight1 + Frame2.CamCframe[i] * Weight2)
		end
		for i = 1, 3 do
			table.insert(LinearVelocity, Frame1.Velocity.Linear[i] * Weight1 + Frame2.Velocity.Linear[i] * Weight2)
			table.insert(AngularVelocity, Frame1.Velocity.Angular[i] * Weight1 + Frame2.Velocity.Angular[i] * Weight2)
		end

		return RootCFrame, CameraCFrame, LinearVelocity, AngularVelocity
	end

	function CanCoyoteJump()
		return Humanoid:GetState() == Enum.HumanoidStateType.Running and
			data[frame].State == Enum.HumanoidStateType.Running.Value and
			data[frame - 1].State == Enum.HumanoidStateType.Running.Value -- fix climbing bug
	end

	function DoubleInput()
		CurrentFrameInput = true
		return false
	end

	function JumpedOffLader()
		return data[frame].State == Enum.HumanoidStateType.Jumping.Value and data[frame - 1].State == Enum.HumanoidStateType.Climbing.Value
	end

	local function readMobile()
		local ok, res = pcall(function()
			local tcf = p.PlayerGui.TouchGui.TouchControlFrame
			local Jumping = (tcf.JumpButton.ImageRectOffset.X == 146) and 1 or 0
			local M = { Jumping = Jumping }
			if UserSettings().GameSettings.TouchMovementMode == Enum.TouchMovementMode.Thumbstick then
				local pos = tcf.ThumbstickFrame.StickImage.Position
				M.JoystickX = r(pos.X.Offset, 1)
				M.JoystickY = r(pos.Y.Offset, 1)
			end
			return M
		end)
		if ok and res then return res end
		return { Jumping = 0 }
	end

	-- ---------------------------------------------------------------------------- inputs table
	function inputs.Idle()
		mode, frame = 1, 1
		anchor(false)
		Bridge.LockShiftlock(false)
		Bridge.LockAnimations(false)
	end

	function inputs.Create(force)
		if DoubleInput() and not force then return end
		frame = #data
		mode = 2
		paused = true
		LookAround = false
		LoadFrame(data[#data], false, true)
		anchor(true)
		Bridge.LockShiftlock(false)
		Bridge.LockAnimations(true)
	end

	function inputs.Test()
		if DoubleInput() then return end

		local speed = GetSetting("Playback Speed")
		if GetSetting("Restart When Testing") ~= 0 then -- (a NumberValue is always truthy in Lua, so the original always restarted; 0 now really turns it off)
			frame = (speed > 0) and 1 or #data - 1
			TestingTimer = (speed > 0) and 0 or data[#data - 1].TotalTime
			if speed > 0 and data[frame].Anim then
				Bridge.SetAnimation(data[frame].Anim, data[frame].Anim.Anims, speed)
			end
		else
			TestingTimer = data[frame].TotalTime
		end
		anchor(false)
		Bridge.LockShiftlock(true)
		Bridge.LockAnimations("ReplayAnimationsOnly")
		if speed > 0 then InputSys.ReplayBegin(data, frame) end -- (inputs are not replayed when playing backwards)
		mode = 3
	end

	function inputs.Unpause()
		if DoubleInput() then return end
		if #data > 1 and frame > 1 and JumpedOffLader() then frame = frame - 1 end

		RemoveCutFrames()
		LookAround = false
		Bridge.LockAnimations(false)
		if #data > 0 then
			UpdateCamera(data[#data], true)
		end
		LoadFrame(data[#data], true)
		anchor(false)
		InputSys.BeginRecording(data, merge and mergeBaseHeld or nil)
		FirstFrameRecord = true
		paused = false
		Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		rs.Heartbeat:Wait()
		rs.RenderStepped:Wait()
		Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		FirstFrameRecord = false
	end

	function inputs.Pause()
		if DoubleInput() then return end

		Bridge.LockAnimations(true)
		paused = true
		LoadFrame(data[#data])
	end

	function inputs.Unpause1F()
		if DoubleInput() then return end
		local FrameCount = 1
		if #data > 1 and frame > 1 and JumpedOffLader() then
			frame = frame - 1
			FrameCount = 2
		end
		if #data > 1 and (data[frame].State == Enum.HumanoidStateType.Landed.Value) then FrameCount = 2 end

		RemoveCutFrames()
		LookAround = false
		Bridge.LockAnimations(false)
		if #data > 0 then
			UpdateCamera(data[#data], true)
		end
		anchor(false)
		InputSys.BeginRecording(data, merge and mergeBaseHeld or nil)
		FirstFrameRecord = true
		LoadFrame(data[#data], true)
		Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

		rs.Heartbeat:Wait()
		rs.RenderStepped:Wait()

		Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		paused = false
		FirstFrameRecord = false

		for i = 1, FrameCount do
			rs.RenderStepped:Wait()
		end

		Bridge.LockAnimations(true)
		paused = true
		LoadFrame(data[#data], false, true)
	end

	function inputs.Return()
		if DoubleInput() then return end

		frame = LastPause
		RemoveCutFrames()
		paused = true
		Bridge.LockAnimations(true)
		LoadFrame(data[frame], false, true)
	end

	function inputs.Back1F()
		if DoubleInput() then return end

		frame = frame - 1
		paused = true
		Bridge.LockAnimations(true)
		LoadFrame(data[frame], false, true)
	end

	function inputs.Forward1F()
		if DoubleInput() then return end

		frame = frame + 1
		paused = true
		Bridge.LockAnimations(true)
		LoadFrame(data[frame], false, true)
	end

	function inputs.Back()
		if DoubleInput() then return end

		back, paused = true, true
		Bridge.LockAnimations(true)
		LoadFrame(data[frame], false, true)
	end

	function inputs.Forward()
		if DoubleInput() then return end

		forw, paused = true, true
		Bridge.LockAnimations(true)
		LoadFrame(data[frame], false, true)
	end

	function inputs.Delete(mobile)
		if ConfirmDelete then
			data = {}
			LastPause = 1
			frame = 0
			SetStatus("TAS Deleted")
		else
			ConfirmDelete = true
			if mobile then
				SetStatus("Delete TAS? Click To Confirm")
			else
				SetStatus("Delete TAS? [" .. Controls["Delete TAS"].Value .. "] To Confirm")
			end
			ConfirmDelete = false
		end
	end

	function inputs.Optimize(mobile)
		if mode == 1 then
			local NewData = {}
			if ConfirmOptimize then
				local prev, prevMX, prevMY
				for i = 2, #data do
					local v = data[i]
					local values = v.CamCframe
					local SameCount = 0
					local mouseMoved = v.MX ~= nil and (v.MX ~= prevMX or v.MY ~= prevMY)
					prevMX, prevMY = v.MX, v.MY
					if prev then
						for y, z in pairs(values) do
							if prev[y] == z then
								SameCount = SameCount + 1
							end
						end
					end
					prev = values
					if SameCount < 12 or (v.Anim and v.Anim.Anims and #v.Anim.Anims > 0) or (v.Input and #v.Input > 0) or mouseMoved then
						table.insert(NewData, v)
						if #NewData > 1 then
							NewData[#NewData].TotalTime = r(NewData[#NewData - 1].TotalTime + v.FrameTime, 1000000)
						else
							NewData[#NewData].TotalTime = r(v.FrameTime, 1000000)
						end
					end
				end
				data = NewData
				SetStatus("TAS Optimized")
			else
				ConfirmOptimize = true
				if mobile then
					SetStatus("Optimize TAS? Click To Confirm")
				else
					SetStatus("Optimize TAS? [" .. Controls["Optimize TAS"].Value .. "] To Confirm")
				end
				ConfirmOptimize = false
			end
		else
			SetStatus("Switch to idle to optimize TAS")
		end
	end

	function inputs.LookAround()
		LookAround = not LookAround
	end

	-- ---------------------------------------------------------------------------- merge hitboxes
	function CreateMergeHitboxes()
		for _, hitboxName in ipairs({ "startHitbox", "endHitbox" }) do
			local hitbox = Instance.new("Part")
			hitbox.Name = hitboxName
			if hitboxName == "startHitbox" then
				hitbox.CFrame = TableToCFrame(mergeBefore[#mergeBefore].Cframe)
			else
				hitbox.CFrame = TableToCFrame(mergeAfter[1].Cframe)
			end
			hitbox.Anchored = true
			hitbox.Color = hitboxName == "startHitbox" and Color3.fromRGB(205, 10, 0) or Color3.fromRGB(0, 185, 8)
			hitbox.Transparency = .5
			hitbox.CanCollide = false
			hitbox.CanQuery = false
			hitbox.CanTouch = false
			hitbox.Size = Vector3.new(2.1, 2.1, 1.1)
			hitbox.TopSurface = Enum.SurfaceType.Smooth
			hitbox.Parent = workspace
			table.insert(hitboxes, hitbox)
		end
	end
	function DestroyMergeHitboxes()
		for _, hitbox in ipairs(hitboxes) do
			hitbox:Destroy()
		end
		hitboxes = {}
	end

	-- ---------------------------------------------------------------------------- public api (was GetTAS / SetTAS)
	function Core.GetTAS(length)
		if length then
			return #data
		else
			return data
		end
	end

	function Core.SetTAS(LoadedTAS, whenMerge)
		if whenMerge then
			oldTAS = LoadedTAS
			if whenMerge == "after" then
				mergeBefore = data
				mergeAfter = LoadedTAS
			else
				mergeBefore = LoadedTAS
				mergeAfter = data
			end
			data = { mergeBefore[#mergeBefore] }
			mergeBaseHeld = InputSys.HeldAt(mergeBefore, #mergeBefore - 1)
			merge = true
			inputs.Create()
			CreateMergeHitboxes()
			local t1 = mergeBefore[#mergeBefore].FrameTime
			local t2 = mergeAfter[1].FrameTime
			mergeReqDist = 16 * (t1 + t2) / 2
			mergeCFrame = mergeAfter[1].Cframe
		else
			data = LoadedTAS
			if mode == 2 then
				frame = #data
				LoadFrame(data[#data])
			end
		end
	end

	function Core.GetMode() return mode end
	function Core.IsMerging() return merge end
	function Core.SetStatus(text, inverse) return SetStatus(text, inverse) end

	-- returns the player to idle and removes everything the core created
	function Core.Shutdown()
		pcall(function()
			if HRP and HRP.Parent and mode ~= 1 then inputs.Idle() end
			if HRP and HRP.Parent then HRP.Anchored = false end
		end)
		pcall(DestroyMergeHitboxes)
		pcall(InputSys.ReplayEnd)
		pcall(Bridge.LockShiftlock, false)
		pcall(Bridge.LockAnimations, false)
	end

	function Core.CharLoad(char) -- called for every character the player gets
		charload(char)
	end

	-- ---------------------------------------------------------------------------- start
	function Core.Start(gui)
		Gui = gui
		MobileUI = gui.Mobile
		MergeStats = gui.MergeStats
		IdleStatsF = gui.IdleStats
		CreateStatsF = gui.CreateStats
		TestStatsF = gui.TestStats

		on(rs.PreRender, function(t)
			if not (mode == 2 and not paused) then InputSys.Clear() end -- only a recording keeps the events
			if CharLoaded() and mode == 2 then
				local IsShiftLock = Bridge.IsShiftlocked() and 1 or 0

				local Mobile
				if IsMobile then
					Mobile = readMobile()
				else
					Mobile = 0
				end

				local FrameData =
				{
					Cframe = nil, -- cframe of root [stepped]
					Velocity = { Linear = Vector3ToTable(HRP.AssemblyLinearVelocity), Angular = Vector3ToTable(HRP.AssemblyAngularVelocity) },
					State = nil, -- humanoidstatetype [stepped]
					CamCframe = CFrameToTable(workspace.CurrentCamera.CFrame),
					ShiftLock = IsShiftLock,
					Mobile = Mobile,
					Anim = nil, -- animation info {pose, jumpanimtime, currentanimspeed, frameanims}
					Zoom = r(GetCameraZoom(), 1000),
					FrameTime = nil, -- frame time [heartbeat]
					TotalTime = nil, -- total time [heartbeat]
				}
				if FirstFrameRecord and #data > 0 then
					FrameData.FrameTime = data[#data].FrameTime
					FrameData.TotalTime = data[#data].TotalTime
				end
				if FirstFrameRecord and NotDead() and #data > 0 then
					--data[#data] = FrameData
				elseif (not paused) and NotDead() then
					FrameData.Input = InputSys.Take() -- keys / clicks / wheel since the last frame (nil when nothing happened)
					FrameData.MX, FrameData.MY = InputSys.Mouse()
					table.insert(data, FrameData)
				end
				if paused and #data > 1 and not LookAround then
					UpdateCamera(data[frame], true)
				end
			end
		end)

		on(rs.PreSimulation, function()
			if CharLoaded() and mode == 2 and (not paused and not FirstFrameRecord) and NotDead() then
				data[#data].Cframe = CFrameToTable(HRP.CFrame)
				data[#data].State = Humanoid:GetState().Value
				data[#data].Anim = Bridge.GetAnimation(#data == 2)
			elseif mode == 3 and data[frame + 1] and TestingTimer >= 0 then
				Humanoid:Move(HRP.AssemblyLinearVelocity) -- for walking sound
			end
		end)

		on(rs.Heartbeat, function(dt)
			if mode ~= 3 and InputSys.IsReplaying() then InputSys.ReplayEnd() end -- left test mode in any way: let go of every key
			if not CharLoaded() then return end
			if mode == 1 then
				SetStats("Idle", nil, dt)
			end
			if mode == 2 then

				-- Create Mode / Paused
				if paused then
					if #data > 1 and back and frame > 1 then
						frame = frame - 1
						LoadFrame(data[frame], false, true)
					end
					if frame < #data and forw then
						frame = frame + 1
						LoadFrame(data[frame], false, true)
					end
				else

					-- Create Mode / Not Paused
					if (not paused) and ((FirstFrameRecord and #data == 1) or not FirstFrameRecord) then
						data[#data].FrameTime = r(LastFrameTime, 1000000)
						if #data > 2 then
							data[#data].TotalTime = r(data[#data - 1].TotalTime + LastFrameTime, 1000000)
						else
							data[#data].TotalTime = r(LastFrameTime, 1000000)
						end
					end

					if data[#data].Cframe == nil then
						table.remove(data, #data)
					end
					frame = #data

				end
				SetStats("Create", data[frame], paused, frame)

			elseif mode == 3 and data[frame + 1] and TestingTimer >= 0 then
				local speed = GetSetting("Playback Speed")
				local PlaybackMode = GetSetting("Interpolate Playback")

				TestingTimer = TestingTimer + LastFrameTime * speed

				if PlaybackMode == 1 then

					local prevFrame = frame
					while data[frame + 1] and TestingTimer > data[frame + 1].TotalTime do
						frame = frame + 1
					end
					while frame > 1 and TestingTimer < data[frame - 1].TotalTime do
						frame = frame - 1
					end
					if frame > 0 then InputSys.ReplayTo(data, frame) end -- keys / clicks of the frames we just passed
					if not data[frame + 1] or frame == 0 then return end
					InputSys.ReplayMouse(data[frame])

					if data[frame + 1].FrameTime > .1 then
						HRP.CFrame = TableToCFrame(data[frame].Cframe)
						UpdateCamera(data[frame])
						Bridge.SetAnimation(data[frame].Anim, data[frame].Anim.Anims, 0)
						return
					end

					local RootCFrame, CameraCFrame, LinearVelocity, AngularVelocity = AveragedFrame(data[frame], data[frame + 1])
					HRP.CFrame = TableToCFrame(RootCFrame)
					Humanoid:ChangeState(data[frame].State)
					HRP.AssemblyAngularVelocity = TableToVector3(AngularVelocity)
					HRP.AssemblyLinearVelocity = TableToVector3(LinearVelocity)
					UpdateCamera({ CamCframe = CameraCFrame, ShiftLock = data[frame].ShiftLock, Zoom = data[frame].Zoom })
					for f = prevFrame + 1, frame, 1 do
						Bridge.SetAnimation(data[f].Anim, { data[f].Anim.Anims[#data[f].Anim.Anims] }, speed)
					end

					SetStats("Test", "Timed")

				else

					frame = frame + 1
					InputSys.ReplayTo(data, frame)
					InputSys.ReplayMouse(data[frame])

					local FrameTime = data[frame].FrameTime
					if FreezeTimeRemaining > dt then
						HRP.CFrame = TableToCFrame(data[frame].Cframe)
						UpdateCamera(data[frame])
						Bridge.SetAnimation(data[frame].Anim, data[frame].Anim.Anims, 0)
						FreezeTimeRemaining = FreezeTimeRemaining - dt
						return
					end
					if FrameTime > 2 * dt then
						FreezeTimeRemaining = FrameTime - dt
						return
					end

					LoadFrame(data[frame])
					Bridge.SetAnimation(data[frame].Anim, data[frame].Anim.Anims, speed)

					SetStats("Test", "Showcase")
				end

				-- both timed and showcase modes
				if type(data[frame].Mobile) == "table" and uis.TouchEnabled then
					pcall(function()
						local tcf = p.PlayerGui.TouchGui.TouchControlFrame
						tcf.JumpButton.ImageRectOffset = Vector2.new(data[frame].Mobile.Jumping * 145 + 1, 146)
						if data[frame].Mobile.JoystickX and data[frame].Mobile.JoystickY then
							tcf.ThumbstickFrame.StickImage.Position = UDim2.new(0, data[frame].Mobile.JoystickX, 0, data[frame].Mobile.JoystickY)
						end
					end)
				end

				-- when the run is over
			elseif mode == 3 then
				InputSys.ReplayEnd()
				mode, frame = 1, 1
				Bridge.LockShiftlock(false)
				Bridge.LockAnimations(false)
				if not QuitTestEvent and data[#data].TotalTime then
					SetStatus("TAS Completed [Time: " .. ToTime(data[#data].TotalTime) .. "]")
				end
				if uis.TouchEnabled then
					for i, v in pairs(MobileUI.MobileModes:GetChildren()) do
						v.Visible = true
					end
					MobileUI.MenuOpener.Visible = true
					MobileUI.More.Visible = true
					if QuitTestEvent then
						QuitTestEvent:Disconnect()
						QuitTestEvent = nil
					end
				end
			end
			LastFrameTime = dt

			-- allow you to do another input after a 3 frame debounce
			if CurrentFrameInput then
				InputDebounce = InputDebounce + 1
				if InputDebounce == 3 then
					InputDebounce = 0
					CurrentFrameInput = false
				end
			end
		end)

		on(uis.JumpRequest, function()
			if Humanoid and mode == 2 and frame > 1 and CanCoyoteJump() then
				Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			end
		end)

		on(uis.InputBegan, function(inp, proc)
			if proc then return end
			if not Humanoid then return end

			if CheckInput(inp, "Idle") and not merge then
				inputs.Idle()
			elseif CheckInput(inp, "Create") and not merge then
				inputs.Create()
			elseif CheckInput(inp, "Test") and #data > 0 and not merge then
				inputs.Test()
			elseif CheckInput(inp, "Unpause") and mode == 2 and paused then
				inputs.Unpause()
			elseif CheckInput(inp, "Pause") and mode == 2 and not paused then
				inputs.Pause()
			elseif CheckInput(inp, "Unpause 1 Frame") and mode == 2 and paused then
				inputs.Unpause1F()
			elseif CheckInput(inp, "Return") and mode == 2 and #data > 0 then
				inputs.Return()
			elseif CheckInput(inp, "Back 1 Frame") and mode == 2 and #data > 1 and frame > 1 then
				inputs.Back1F()
			elseif CheckInput(inp, "Forward 1 Frame") and mode == 2 and frame < #data then
				inputs.Forward1F()
			elseif CheckInput(inp, "Back") and mode == 2 then
				inputs.Back()
			elseif CheckInput(inp, "Forward") and mode == 2 then
				inputs.Forward()
			elseif CheckInput(inp, "Delete TAS") and not merge then
				inputs.Delete()
			elseif CheckInput(inp, "Optimize TAS") then
				inputs.Optimize()
			elseif CheckInput(inp, "Look Around") and mode == 2 and paused and GetSetting("Lock Camera (Paused)") == 1 then
				inputs.LookAround()
			end
		end)

		-- ------------------------------------------------------------------------ mobile buttons
		function SetPauseButton(pausedNow)
			if pausedNow then
				MobileUI.MobileCreate.Pause.Icon.Image = "rbxassetid://10392248278"
				MobileUI.MobileCreate.Pause.Icon.Size = UDim2.new(0.285, 0, 0.7, 0)
				MobileUI.MobileCreate.Pause.Icon.Position = UDim2.new(0.357, 0, 0.132, 0)
			else
				MobileUI.MobileCreate.Pause.Icon.Image = "rbxassetid://4458862490"
				MobileUI.MobileCreate.Pause.Icon.Size = UDim2.new(0.471, 0, 1, 0)
				MobileUI.MobileCreate.Pause.Icon.Position = UDim2.new(0.262, 0, 0, 0)
			end
		end

		function ShowCreateButtons(visible)
			for i, Mode in pairs(MobileUI.MobileCreate:GetChildren()) do
				Mode.Visible = visible
			end
		end

		on(MobileUI.MobileModes.Mode1Mobile.MouseButton1Click, function()
			inputs.Idle()
			ShowCreateButtons(false)
		end)
		on(MobileUI.MobileModes.Mode2Mobile.MouseButton1Click, function()
			inputs.Create()
			ShowCreateButtons(true)
			SetPauseButton(true)
		end)
		on(MobileUI.MobileModes.Mode3Mobile.MouseButton1Click, function()
			if #data < 1 then return end
			inputs.Test()
			for _, v in pairs(MobileUI:GetChildren()) do
				if v:IsA("Folder") then
					for _, z in pairs(v:GetChildren()) do
						z.Visible = false
					end
				else
					v.Visible = false
				end
			end

			task.wait(.1)
			local ConfirmQuit
			QuitTestEvent = uis.TouchTap:Connect(function()
				if ConfirmQuit then
					frame = #data
					SetStatus("Test Quit")
				else
					ConfirmQuit = true
					SetStatus("Tap Again to Quit Test")
					ConfirmQuit = false
				end
			end)
			Janitor.add(QuitTestEvent)
		end)
		on(MobileUI.MobileCreate.Pause.MouseButton1Click, function()
			if paused then
				inputs.Unpause()
				SetPauseButton(false)
			else
				inputs.Pause()
				SetPauseButton(true)
			end
		end)
		on(MobileUI.MobileCreate.Unpause1Frame.MouseButton1Click, function()
			if paused then
				inputs.Unpause1F()
			end
		end)
		on(MobileUI.MobileCreate.Return.MouseButton1Click, function()
			if #data > 0 then
				inputs.Return()
				SetPauseButton(true)
			end
		end)
		on(MobileUI.MobileCreate.Back1Frame.MouseButton1Click, function()
			if #data > 1 and frame > 1 then
				inputs.Back1F()
				SetPauseButton(true)
			end
		end)
		on(MobileUI.MobileCreate.Forward1Frame.MouseButton1Click, function()
			if frame < #data then
				inputs.Forward1F()
				SetPauseButton(true)
			end
		end)
		on(MobileUI.MobileCreate.Back.MouseButton1Down, function()
			inputs.Back()
			SetPauseButton(true)
		end)
		on(MobileUI.MobileCreate.Forward.MouseButton1Down, function()
			inputs.Forward()
			SetPauseButton(true)
		end)
		on(MobileUI.MobileOptions.Delete.MouseButton1Click, function()
			inputs.Delete(true)
		end)
		on(MobileUI.MobileOptions.Optimize.MouseButton1Click, function()
			inputs.Optimize(true)
		end)
		on(MobileUI.MobileCreate.LookAround.MouseButton1Click, function()
			if paused and GetSetting("Lock Camera (Paused)") == 1 then
				inputs.LookAround()
			end
		end)

		on(MobileUI.MobileCreate.Back.MouseButton1Up, function()
			back = false
		end)
		on(MobileUI.MobileCreate.Forward.MouseButton1Click, function()
			forw = false
		end)

		on(uis.InputEnded, function(inp, proc)
			if proc then return end
			if CheckInput(inp, "Back") then back = false end
			if CheckInput(inp, "Forward") then forw = false end
		end)

		-- ------------------------------------------------------------------------ merge completion
		on(MergeStats.MouseButton1Click, function()
			if mergeCanComplete then
				merge = false
				inputs.Idle()
				DestroyMergeHitboxes()
				local newData = {}
				local beginRetiming = #mergeBefore
				table.move(mergeBefore, 1, #mergeBefore, 1, newData)
				table.move(data, 2, #data, #newData + 1, newData)
				table.move(mergeAfter, 1, #mergeAfter, #newData + 1, newData)
				for i = beginRetiming, #newData do
					newData[i].TotalTime = r(newData[i].FrameTime + newData[i - 1].TotalTime, 1000000)
				end
				oldTAS = {}
				mergeBefore = {}
				mergeAfter = {}
				mergeBaseHeld = nil
				data = newData
				SetStatus("Merge Complete")
			else
				merge = false
				inputs.Idle()
				DestroyMergeHitboxes()
				data = oldTAS
				oldTAS = {}
				mergeBefore = {}
				mergeAfter = {}
				mergeBaseHeld = nil
				SetStatus("Merge Cancelled")
			end
		end)

		on(Settings["Lock Camera (Paused)"].Changed, function()
			if mode == 2 and paused then
				LoadFrame(data[frame])
			end
		end)
	end
end

-- ================================================================================================
--  MENU  (port of the MenuManager LocalScript; the RemoteEvents are now direct calls into Store/Core)
-- ================================================================================================
local Menu = {}
do
	local uis = UIS
	local ts = TweenService

	local Gui, menu, MobileUI, MergeMenu, JoinMessage
	local ControlsFrame, SettingsFrame, SavesFrame, HelpFrame, MoreFrame
	local WaitInputConnection, ChangingInput = nil, nil
	local SavingOrLoading = false
	local slotFrames = {} -- slot name -> Slot frame
	local slotNameOf = {} -- Slot frame -> slot name
	local pendingMerge = nil -- the loaded TAS while the Before/After dialog is open

	-- ---------------------------------------------------------------------------- status text
	local function SetStatus(text, fade)
		local old = Gui:FindFirstChild("Status")
		local status = old:Clone()
		old:Destroy()
		status.TextTransparency = 0
		status.Text = text
		status.Parent = Gui
		if fade then
			task.wait(2)
			for i = 0, 1.05, .05 do
				task.wait(.05)
				status.TextTransparency = i
			end
		end
	end

	-- the scrolling area is as tall as its list (UIListLayout reports the real content height)
	local function autoCanvas(scroller, container, extra)
		local layout = container:FindFirstChildOfClass("UIListLayout")
		if not layout then return end
		local function fit()
			scroller.CanvasSize = UDim2.new(0, 0, 0, container.Position.Y.Offset + layout.AbsoluteContentSize.Y + (extra or 30))
		end
		on(layout:GetPropertyChangedSignal("AbsoluteContentSize"), fit)
		fit()
	end

	local function SetStatsSize(TextSize)
		for _, v in ipairs({ Gui.IdleStats, Gui.CreateStats, Gui.TestStats, Gui.MergeStats }) do
			v.Size = UDim2.new(0, 240 * TextSize / 11, 0, (#v:GetChildren() - 2) * 18 * TextSize / 11)
			for _, x in ipairs(v:GetChildren()) do
				if x:IsA("TextLabel") then
					x.Size = UDim2.new(1, 0, 0, 18 * TextSize / 11)
					x.TextSize = TextSize
				end
			end
			if v.Name == "MergeStats" then
				v.Position = UDim2.new(1, -10, 1, -180 * TextSize / 11 - 20)
			end
		end
	end

	-- ---------------------------------------------------------------------------- saving / loading
	local function progressText(verb)
		return function(i, n) SetStatus(verb .. " " .. i .. "/" .. n, false) end
	end

	local function SaveSlot(name)
		if not name then return end
		if SavingOrLoading then
			SetStatus("You are already saving or loading.", true)
			return
		end
		local source = Core.GetTAS()
		if #source == 0 then
			SetStatus("There is nothing to save", true)
			return
		end
		SavingOrLoading = true
		local copy = table.move(source, 1, #source, 1, {}) -- the TAS keeps changing while the file is written in pieces
		SetStatus("Saving...", false)
		local ok, res, size = Store.SaveSlot(name, copy, progressText("Saving"))
		SavingOrLoading = false
		if ok then
			local kb = size and (size >= 1048576 and string.format("%.2f MB", size / 1048576) or string.format("%.1f KB", size / 1024)) or "?"
			SetStatus("Save Success! (" .. res .. " frames, " .. kb .. ")", true)
		else
			SetStatus("Save Failed: " .. tostring(res), true)
		end
	end

	local function LoadSlot(name, mergeWhen)
		if not name then return end
		if SavingOrLoading then
			SetStatus("You are already saving or loading.", true)
			return
		end
		SavingOrLoading = true
		SetStatus("Loading...", false)
		local ok, result = Store.LoadSlot(name, progressText("Loading"))
		SavingOrLoading = false
		if ok then
			if #result == 0 then
				SetStatus("There is nothing to load", true)
				return
			end
			Core.SetTAS(result, mergeWhen)
			if mergeWhen then
				SetStatus("Move into the green hitbox to complete the merge")
			else
				SetStatus("Load Success!", true)
			end
		else
			SetStatus("Load Failed: " .. tostring(result), true)
		end
	end

	-- loads the slot first (the Before/After buttons depend on what its first/last frame is doing)
	local function MergeSlot(name)
		if not name then return end
		if Core.GetTAS(true) == 0 then
			SetStatus("You must have a TAS to merge", true)
			return
		end
		if SavingOrLoading then
			SetStatus("You are already saving or loading.", true)
			return
		end
		SavingOrLoading = true
		SetStatus("Loading...", false)
		local ok, result = Store.LoadSlot(name, progressText("Loading"))
		SavingOrLoading = false
		if not ok then
			SetStatus("Load Failed: " .. tostring(result), true)
			return
		end
		if #result == 0 then
			SetStatus("There is nothing to load", true)
			return
		end
		local running = Enum.HumanoidStateType.Running.Value
		local canBefore = result[#result].State == running -- the loaded TAS ends on the ground -> it can come before yours
		local canAfter = result[1].State == running        -- the loaded TAS starts on the ground -> it can come after yours
		pendingMerge = result
		SetStatus("")
		menu.Visible = false
		MergeMenu.Visible = true
		MergeMenu.Options.Before.Interactable = canBefore
		MergeMenu.Options.Before.BackgroundColor3 = canBefore and Color3.fromRGB(0, 52, 129) or Color3.fromRGB(50, 50, 50)
		MergeMenu.Options.After.Interactable = canAfter
		MergeMenu.Options.After.BackgroundColor3 = canAfter and Color3.fromRGB(0, 52, 129) or Color3.fromRGB(50, 50, 50)
	end

	-- ---------------------------------------------------------------------------- slot list
	local function updateSlotCount()
		local n = 0
		for _ in pairs(slotFrames) do n = n + 1 end
		SavesFrame.YourSlots.Top.Count.Text = n .. (n == 1 and " slot" or " slots")
	end

	local function reorderSlots(names)
		names = names or Store.ListSlots()
		for i, name in ipairs(names) do
			local f = slotFrames[name]
			if f then
				f.LayoutOrder = i
				f.IDtext.Text = "#" .. i
			end
		end
	end

	local function createSlotFrame(name)
		local Slot = UI.Template("Slot")
		Slot.Name = "Slot_" .. name
		Slot.N.Text = name
		slotFrames[name] = Slot
		slotNameOf[Slot] = name
		Slot.Parent = SavesFrame.YourSlots

		on(Slot.N.FocusLost, function()
			local old = slotNameOf[Slot]
			if not old then return end
			local clean = Store.CleanName(Slot.N.Text)
			if not clean or clean == old then
				Slot.N.Text = old
				return
			end
			local ok, res = Store.RenameSlot(old, clean)
			if ok then
				slotFrames[old] = nil
				slotFrames[res] = Slot
				slotNameOf[Slot] = res
				Slot.Name = "Slot_" .. res
				Slot.N.Text = res
				reorderSlots()
			else
				Slot.N.Text = old
				SetStatus(tostring(res), true)
			end
		end)

		local confirmDelete = false
		on(Slot.MoreButtons.Delete.MouseButton1Click, function()
			local nm = slotNameOf[Slot]
			if not nm then return end
			if not confirmDelete then -- this really deletes the file, so ask twice
				confirmDelete = true
				Slot.MoreButtons.Delete.Text = "Sure?"
				task.delay(3, function()
					confirmDelete = false
					if Slot.Parent then Slot.MoreButtons.Delete.Text = "Delete" end
				end)
				return
			end
			local ok, err = Store.DeleteSlot(nm)
			if ok then
				slotFrames[nm] = nil
				slotNameOf[Slot] = nil
				Slot:Destroy()
				updateSlotCount()
				reorderSlots()
			else
				SetStatus("Delete failed: " .. tostring(err), true)
			end
		end)

		on(Slot.Buttons.Save.MouseButton1Click, function() SaveSlot(slotNameOf[Slot]) end)
		on(Slot.Buttons.Load.MouseButton1Click, function() LoadSlot(slotNameOf[Slot]) end)
		on(Slot.MoreButtons.Merge.MouseButton1Click, function() MergeSlot(slotNameOf[Slot]) end)
		on(Slot.Buttons.Expand.MouseButton1Click, function()
			Slot.Size = Slot.Size + UDim2.new(0, 0, 0, 30)
			Slot.Buttons.Expand.Visible = false
			Slot.Buttons.Close.Visible = true
		end)
		on(Slot.Buttons.Close.MouseButton1Click, function()
			Slot.Size = Slot.Size - UDim2.new(0, 0, 0, 30)
			Slot.Buttons.Expand.Visible = true
			Slot.Buttons.Close.Visible = false
		end)
		return Slot
	end

	local function rebuildSlots()
		for _, f in pairs(slotFrames) do f:Destroy() end
		slotFrames, slotNameOf = {}, {}
		local names = Store.ListSlots()
		for _, name in ipairs(names) do createSlotFrame(name) end
		reorderSlots(names)
		updateSlotCount()
	end

	-- rescan the folder, but only rebuild when files appeared/disappeared from outside
	local function refreshSlotsIfChanged()
		if not Store.Ready then return end
		local names = Store.ListSlots()
		local same = true
		local count = 0
		for _, name in ipairs(names) do
			count = count + 1
			if not slotFrames[name] then same = false break end
		end
		if same then
			local shown = 0
			for _ in pairs(slotFrames) do shown = shown + 1 end
			same = shown == count
		end
		if not same then rebuildSlots() end
	end

	-- ---------------------------------------------------------------------------- start
	function Menu.Start(gui, onUnload)
		Gui = gui
		menu = gui.MainMenu
		MobileUI = gui.Mobile
		MergeMenu = gui.Merge
		JoinMessage = gui.JoinMessage
		ControlsFrame = menu.ControlsFrame
		SettingsFrame = menu.SettingsFrame
		SavesFrame = menu.SavesFrame
		HelpFrame = menu.HelpFrame
		MoreFrame = menu.MoreFrame

		if uis.TouchEnabled then
			MobileUI.MenuOpener.Visible = true
			MobileUI.More.Visible = true
			MobileUI.MobileModes.Mode1Mobile.Visible = true
			MobileUI.MobileModes.Mode2Mobile.Visible = true
			MobileUI.MobileModes.Mode3Mobile.Visible = true
			menu.ControlsFrame.Visible = false
			menu.ControlsToggle.Visible = false
			menu.HelpToggle.Position = UDim2.new(0.5, 0, 0.108, 0)
			menu.HelpToggle.Size = UDim2.new(0, 100, 0, 30)
			menu.MoreToggle.Position = UDim2.new(0.75, 0, 0.108, 0)
			menu.MoreToggle.Size = UDim2.new(0, 100, 0, 30)
			menu.SavesToggle.Position = UDim2.new(0.25, 0, 0.108, 0)
			menu.SavesToggle.Size = UDim2.new(0, 100, 0, 30)
			menu.SettingsToggle.Position = UDim2.new(0, 0, 0.108, 0)
			menu.SettingsToggle.Size = UDim2.new(0, 100, 0, 30)
		end

		local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
		if viewport.Y < 420 then
			menu.Size = UDim2.new(0, 400, 0.95, 0)
		end

		local JoinTween = ts:Create(JoinMessage, TweenInfo.new(1, Enum.EasingStyle.Quad), { Position = UDim2.new(0, 10, 1, -10) })
		local ReverseJoinTween = ts:Create(JoinMessage, TweenInfo.new(.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(0, 10, 1, 150) })

		-- ------------------------------------------------------------------------ controls
		for _, v in ipairs(ControlValues:GetChildren()) do
			local ControlBlock = UI.Template("Control")

			ControlBlock.Name = v.Name
			ControlBlock.N.Text = v.Name
			ControlBlock.Key.Text = v.Value
			ControlBlock.Parent = ControlsFrame.List
			on(ControlBlock.Key.MouseButton1Down, function()
				if ChangingInput then
					WaitInputConnection:Disconnect()
					ControlsFrame.List[ChangingInput].Key.Text = ControlValues[ChangingInput].Value
				end
				ControlBlock.Key.Text = "Press Any Key"
				ChangingInput = ControlBlock.Name
				RunService.RenderStepped:Wait()
				WaitInputConnection = uis.InputBegan:Connect(function(inp, proc)
					if proc and inp.UserInputType == Enum.UserInputType.Keyboard then return end
					local input
					if inp.UserInputType == Enum.UserInputType.Keyboard then
						input = inp.KeyCode
					elseif inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.MouseButton2 or inp.UserInputType == Enum.UserInputType.MouseButton3 then
						input = inp.UserInputType
					end

					if input and FromKey[input] then
						ControlBlock.Key.Text = FromKey[input]
						ControlValues[ChangingInput].Value = FromKey[input]
						WaitInputConnection:Disconnect()
						ChangingInput = nil
					end
				end)
				Janitor.add(WaitInputConnection)
			end)
		end

		-- ------------------------------------------------------------------------ settings
		for _, v in ipairs(SettingValues:GetChildren()) do
			local setting = SettingsFrame.List:FindFirstChild(v.Name)
			if setting then
				if setting:FindFirstChild("Switch") or setting:FindFirstChild("TextSwitch") then
					local switch = setting:FindFirstChildWhichIsA("TextButton")
					local tween1, tween2
					if switch.Name == "Switch" then
						tween1 = ts:Create(switch.Switcher, TweenInfo.new(.25), { Position = UDim2.new(1, 0, .5, 0), BackgroundColor3 = Color3.fromRGB(75, 75, 75) })
						tween2 = ts:Create(switch.Switcher, TweenInfo.new(.25), { Position = UDim2.new(0, 0, .5, 0), BackgroundColor3 = Color3.fromRGB(255, 255, 255) })
					elseif switch.Name == "TextSwitch" then
						tween1 = ts:Create(switch.Switcher, TweenInfo.new(.25), { Position = UDim2.new(.75, 0, .5, 0) })
						tween2 = ts:Create(switch.Switcher, TweenInfo.new(.25), { Position = UDim2.new(.25, 0, .5, 0) })
					end
					if v.Value == 1 then
						tween1:Play()
					end
					local isOn = v.Value
					on(switch.MouseButton1Click, function()
						if isOn == 0 then isOn = 1 else isOn = 0 end
						if isOn == 1 then
							tween1:Play()
						else
							tween2:Play()
						end
						v.Value = isOn
					end)
				elseif setting:FindFirstChild("Input") then
					local inp = setting.Input
					inp.Text = tostring(v.Value)
					on(inp.FocusLost, function()
						if tonumber(inp.Text) then
							v.Value = tonumber(inp.Text)
						else
							inp.Text = tostring(v.Value)
						end
					end)
				end
			end
		end

		SetStatsSize(SettingValues["Stats Text Size"].Value)
		on(SettingValues["Stats Text Size"].Changed, function(v)
			SetStatsSize(v)
		end)

		-- ------------------------------------------------------------------------ saves tab
		if Store.Ready then
			rebuildSlots()
			on(SavesFrame.YourSlots.Top.AddSlot.MouseButton1Click, function()
				local ok, res = Store.CreateSlot(nil)
				if ok then
					createSlotFrame(res)
					reorderSlots()
					updateSlotCount()
				else
					SetStatus("Could not add a slot: " .. tostring(res), true)
				end
			end)
		else
			SavesFrame.YourSlots.Top.Count.Text = "unavailable"
			SavesFrame.YourSlots.Top.AddSlot.Visible = false
		end

		on(MergeMenu.Cancel.MouseButton1Click, function()
			MergeMenu.Visible = false
			pendingMerge = nil
		end)
		on(MergeMenu.Options.Before.MouseButton1Click, function()
			MergeMenu.Visible = false
			if pendingMerge then
				local tas = pendingMerge
				pendingMerge = nil
				Core.SetTAS(tas, "before")
				SetStatus("Move into the green hitbox to complete the merge")
			end
		end)
		on(MergeMenu.Options.After.MouseButton1Click, function()
			MergeMenu.Visible = false
			if pendingMerge then
				local tas = pendingMerge
				pendingMerge = nil
				Core.SetTAS(tas, "after")
				SetStatus("Move into the green hitbox to complete the merge")
			end
		end)

		-- ------------------------------------------------------------------------ title / join message
		menu.Title.Text = "HappaTAS " .. VERSION
		JoinMessage.Title.Text = "HappaTAS " .. VERSION .. " Loaded"
		JoinMessage.M.Text = ControlValues["Menu"].Value .. " - Main Menu"
		if not Store.Ready then
			JoinMessage.Size = UDim2.new(0, 280, 0, 110)
			JoinMessage.FailureMessage.Visible = true
		end
		JoinTween:Play()
		on(JoinMessage.Close.MouseButton1Down, function()
			ReverseJoinTween:Play()
		end)

		on(uis.InputBegan, function(inp, proc)
			if proc then return end
			local key = ToKey[ControlValues["Menu"].Value]
			if inp.KeyCode == key or inp.UserInputType == key then
				menu.Visible = not menu.Visible
			end
		end)

		-- ------------------------------------------------------------------------ tabs
		local function tab(TabName)
			menu.ControlsToggle.BackgroundTransparency = .75
			menu.SettingsToggle.BackgroundTransparency = .75
			menu.SavesToggle.BackgroundTransparency = .75
			menu.HelpToggle.BackgroundTransparency = .75
			menu.MoreToggle.BackgroundTransparency = .75
			menu.ControlsFrame.Visible = false
			menu.SettingsFrame.Visible = false
			menu.SavesFrame.Visible = false
			menu.HelpFrame.Visible = false
			menu.MoreFrame.Visible = false
			menu[TabName .. "Toggle"].BackgroundTransparency = .5
			menu[TabName .. "Frame"].Visible = true
			if TabName == "Saves" then
				refreshSlotsIfChanged()
			end
		end

		on(menu.ControlsToggle.MouseButton1Click, function() tab("Controls") end)
		on(menu.SettingsToggle.MouseButton1Click, function() tab("Settings") end)
		on(menu.SavesToggle.MouseButton1Click, function() tab("Saves") end)
		on(menu.HelpToggle.MouseButton1Click, function() tab("Help") end)
		on(menu.MoreToggle.MouseButton1Click, function() tab("More") end)

		on(MoreFrame.List["1Model"].MouseButton1Click, function()
			if onUnload then onUnload() end
		end)

		-- ------------------------------------------------------------------------ help tab (expand/collapse)
		local hf = HelpFrame.List
		local SelectedHelp = "00"
		for _, v in ipairs(hf:GetChildren()) do
			if v:IsA("TextButton") then
				on(v.MouseButton1Click, function()
					if SelectedHelp ~= v.Name then
						if SelectedHelp ~= "00" then
							hf[SelectedHelp].Expansion.Visible = false
							hf[SelectedHelp].Expand.Text = "+"
							local oldSpacer = hf:FindFirstChild(SelectedHelp .. "Spacer")
							if oldSpacer then oldSpacer:Destroy() end
						end
						SelectedHelp = v.Name
						hf[SelectedHelp].Expansion.Visible = true
						hf[SelectedHelp].Expand.Text = "-"
						local spacer = hf.Spacer:Clone()
						spacer.Parent = hf
						spacer.Name = SelectedHelp .. "Spacer"
						spacer.Size = UDim2.new(0, 0, 0, hf[SelectedHelp].Expansion.Size.Y.Offset - 8)
					else
						hf[SelectedHelp].Expansion.Visible = false
						hf[SelectedHelp].Expand.Text = "+"
						local oldSpacer = hf:FindFirstChild(SelectedHelp .. "Spacer")
						if oldSpacer then oldSpacer:Destroy() end
						SelectedHelp = "00"
					end
				end)
			end
		end

		-- scroll areas follow their content height
		autoCanvas(ControlsFrame, ControlsFrame.List)
		autoCanvas(SettingsFrame, SettingsFrame.List)
		autoCanvas(HelpFrame, HelpFrame.List, 40)
		autoCanvas(MoreFrame, MoreFrame.List)
		autoCanvas(SavesFrame, SavesFrame.YourSlots, 60)

		-- ------------------------------------------------------------------------ mobile
		on(MobileUI.MenuOpener.MouseButton1Click, function()
			menu.Visible = not menu.Visible
		end)

		on(MobileUI.More.MouseButton1Click, function()
			for _, ui in ipairs(MobileUI.MobileOptions:GetChildren()) do
				ui.Visible = not ui.Visible
			end
		end)
	end

	function Menu.SetStatus(text, fade) return SetStatus(text, fade) end
end

-- ================================================================================================
--  START  (replaces the initializer script + MainModule glue)
-- ================================================================================================
local Gui = UI.Create()
if not UI.Attach(Gui) then
	Gui:Destroy()
	error("[HappaTAS] could not parent the interface anywhere (CoreGui / gethui / PlayerGui)")
end
Janitor.add(Gui)

local handle = { Version = VERSION, Config = CONFIG, Store = Store, Core = Core, Gui = Gui, Bridge = Bridge, AnimEngine = AnimEngine, Inputs = InputSys, Codec = Codec, Settings = SettingValues, Controls = ControlValues }

local function Unload()
	if Janitor.unloading then return end
	pcall(Core.Shutdown)
	pcall(AnimEngine.Shutdown)
	pcall(Bridge.Restore)
	Janitor.cleanup()
	if genv.__HappaTAS == handle then genv.__HappaTAS = nil end
end
handle.Unload = Unload
genv.__HappaTAS = handle

if CONFIG.DisableAutoJump then
	pcall(function() LocalPlayer.AutoJumpEnabled = false end)
end

Bridge.Init()
InputSys.Start(Gui)
Core.Start(Gui)
Menu.Start(Gui, Unload)

local function onCharacter(char)
	spawn(function()
		local ok, err = pcall(Core.CharLoad, char)
		if not ok then warnf("character setup failed:", tostring(err)) end
	end)
	AnimEngine.Attach(char)
end
on(LocalPlayer.CharacterAdded, onCharacter)
if LocalPlayer.Character then
	onCharacter(LocalPlayer.Character)
end

if not Store.Ready then
	warnf("File functions are missing or the workspace is not writable: slots can't be saved or loaded.")
end
log("loaded", VERSION, "ui parent:", UI.ParentName, "save folder:", Store.PlacePath)
