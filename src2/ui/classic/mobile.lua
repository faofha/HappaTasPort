-- ================================================================================================
--  CLASSIC MOBILE  (HappaTAS 3 ui, spec 8.5): V2.38.17's Mobile folder (p18_core.lua's mobile buttons) on
--  HappaTAS 3's engine, shown on a touch screen without a keyboard (ui/touch's rule): the menu button, More
--  (shows / hides the options), the three mode buttons, Create's buttons (shown in Create; Back / Forward
--  held from press to release) and the options (delete TAS, optimize, the MicroProfiler switch). During
--  Test the mobile buttons hide (V2) and ui/touch's double-tap ends playback.
-- ================================================================================================
local Touch = import("ui/touch")

local ClassicMobile = {}

local PAUSED_ICON, PLAYING_ICON = "rbxassetid://10392248278", "rbxassetid://4458862490"

function ClassicMobile.wire(classic)
	local E, ui = classic.E, classic.ui
	local life, b = ui.life, classic.byPath
	local wanted = Touch.wanted(classic.uis)
	local function setPause(paused)
		local icon = b["Mobile.MobileCreate.Pause.Icon"]
		if not icon then return end
		if paused then
			icon.Image = PAUSED_ICON
			icon.Size = UDim2.new(0.285, 0, 0.7, 0)
			icon.Position = UDim2.new(0.357, 0, 0.132, 0)
		else
			icon.Image = PLAYING_ICON
			icon.Size = UDim2.new(0.471, 0, 1, 0)
			icon.Position = UDim2.new(0.262, 0, 0, 0)
		end
	end
	-- what shows: nothing without touch, nothing but Create's buttons in Create, everything hidden in Test
	local function refresh()
		local mode = E.mode
		for _, f in ipairs({ "MobileModes", "MobileCreate", "MobileOptions" }) do
			for _, x in ipairs(b["Mobile." .. f]:GetChildren()) do
				local show = wanted and mode ~= 3
				if f == "MobileCreate" then show = show and mode == 2 end
				if f == "MobileOptions" then show = show and classic.mobileMore == true end
				if x.Visible ~= show then x.Visible = show end
			end
		end
		for _, n in ipairs({ "MenuOpener", "More" }) do
			local x = b["Mobile." .. n]
			local show = wanted and mode ~= 3
			if x.Visible ~= show then x.Visible = show end
		end
		setPause(E.paused or mode ~= 2)
	end
	classic.mobileRefresh = refresh
	local function request(action, opts)
		E.modes:request(action, opts)
		task.defer(refresh)
	end
	local function click(path, f) life:connect(b[path].MouseButton1Click, f) end
	click("Mobile.MenuOpener", function() classic:toggle() end)
	click("Mobile.More", function()
		classic.mobileMore = not classic.mobileMore
		refresh()
	end)
	click("Mobile.MobileModes.Mode1Mobile", function() request("idle") end)
	click("Mobile.MobileModes.Mode2Mobile", function() request("create") end)
	click("Mobile.MobileModes.Mode3Mobile", function() if E.tl:count() > 0 then request("test") end end)
	click("Mobile.MobileCreate.Pause", function() request(E.paused and "unpause" or "pause") end)
	click("Mobile.MobileCreate.Unpause1Frame", function() request("unpause1") end)
	click("Mobile.MobileCreate.Return", function() request("return") end)
	click("Mobile.MobileCreate.Back1Frame", function() request("back1") end)
	click("Mobile.MobileCreate.Forward1Frame", function() request("forward1") end)
	click("Mobile.MobileCreate.LookAround", function() request("lookAround") end)
	click("Mobile.MobileOptions.Delete", function() request("deleteTas", { mobile = true }) end)
	click("Mobile.MobileOptions.Optimize", function() request("optimize", { mobile = true }) end)
	click("Mobile.MobileOptions.MicroProfiler", function()
		E.settings:set("showMicroProfiler", E.settings:on("showMicroProfiler") and 0 or 1)
	end)
	for _, which in ipairs({ "back", "forward" }) do
		local btn = b["Mobile.MobileCreate." .. (which == "back" and "Back" or "Forward")]
		life:connect(btn.MouseButton1Down, function() E.modes:request(which) end)
		life:connect(btn.MouseButton1Up, function() E.modes:release(which) end)
	end
	classic.offs[#classic.offs + 1] = E.state:watch("mode", function() refresh() end)
	refresh()
end

return ClassicMobile
