-- ================================================================================================
--  LIVE PART F, interface (test tool, never shipped): scenarios 16-18.
--  U.look(): V2.38.17 (HappaTasTest/v2ref.lua) and HappaTAS 3's Classic interface side by side: every GUI
--    object under each one's ScreenGui by path, font / text colour / text size / background colour / stroke
--    colour compared; which settings rows each shows.
--  U.switch(n): the Classic interface switch (classic row, real mouse clicks through VirtualInputManager) and
--    the New interface's toggle; n switches back and forth: Settings3.json the same bytes before and after.
--  U.oldFiles(): dzr's Settings3.json from before Part E loads (every saved value = the store); V2's
--    Settings.json still converts when there is no Settings3.json (Settings3.json put back right after).
--  U.inspector(): the Inspector, standing still, in Live, Create recording, Create paused, Test: how often each
--    row's text changes over 3 s, and the Inspector's own cost per frame.
--  Results: HappaTasTest/pfu.json
-- ================================================================================================
local HttpService = game:GetService("HttpService")
local RS = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local P = loadfile("HappaTasTest/phys3.lua")()
local U = {}
local results = {}
local function save() writefile("HappaTasTest/pfu.json", HttpService:JSONEncode(results)) end

local function pathOf(o, root)
	local parts = {}
	while o and o ~= root do table.insert(parts, 1, o.Name); o = o.Parent end
	return table.concat(parts, ".")
end
local function dump(root)
	local t = {}
	for _, o in ipairs(root:GetDescendants()) do
		local row
		if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
			row = string.format("font %s/%s text %s size %d bg %s", o.FontFace.Family:match("[^/]+$") or "", o.FontFace.Weight.Name,
				o.TextColor3:ToHex(), o.TextSize, o.BackgroundColor3:ToHex())
		elseif o:IsA("GuiObject") then
			row = "bg " .. o.BackgroundColor3:ToHex()
		elseif o:IsA("UIStroke") then
			row = "stroke " .. o.Color:ToHex()
		end
		if row then
			local p = pathOf(o, root)
			if not t[p] then t[p] = row end
		end
	end
	return t
end
local function findGui(name)
	local places = {}
	pcall(function() places[#places + 1] = gethui() end)
	pcall(function() places[#places + 1] = game:GetService("CoreGui") end)
	pcall(function() places[#places + 1] = game:GetService("Players").LocalPlayer.PlayerGui end)
	for _, pl in ipairs(places) do
		local g = pl:FindFirstChild(name, true)
		if g then return g end
	end
end

function U.look()
	P.unloadAll()
	-- V2.38.17
	assert(loadfile("HappaTasTest/v2ref.lua", "=V2.38.17"))()
	task.wait(3)
	local g2 = assert(findGui("TASUserInterface"), "no V2 interface")
	local d2 = dump(g2)
	pcall(getgenv().__HappaTAS.Unload)
	task.wait(1)
	-- HappaTAS 3, Classic
	P.use("h3", "HappaTasTest/h3.lua")
	local E = getgenv().__HappaTAS3_T.engine
	local was = E.settings:get("interface")
	E.settings:set("interface", "Classic")
	task.wait(1)
	local c = E.ui.classic
	local d3 = dump(c.gui)
	local both, diff, only2, only3, rows = 0, 0, 0, 0, {}
	for p, r in pairs(d2) do
		if d3[p] then
			both = both + 1
			if d3[p] ~= r then
				diff = diff + 1
				if #rows < 40 then rows[#rows + 1] = p .. ": V2 " .. r .. " | 3 " .. d3[p] end
			end
		else only2 = only2 + 1 end
	end
	for p in pairs(d3) do if not d2[p] then only3 = only3 + 1 end end
	local shown = {}
	for k in pairs(c.settingsRows) do shown[#shown + 1] = k end
	table.sort(shown)
	results.look = { objectsInBoth = both, different = diff, onlyV2 = only2, onlyV3 = only3, diffRows = rows,
		classicRows = #shown, rowKeys = table.concat(shown, " ") }
	E.settings:set("interface", was)
	task.wait(1)
	save()
end

-- a real click (VirtualInputManager, screen coordinates) on a GUI button
local function click(b)
	local vim = game:GetService("VirtualInputManager")
	local inset = GuiService:GetGuiInset()
	local p = b.AbsolutePosition + b.AbsoluteSize / 2 + Vector2.new(0, inset.Y)
	vim:SendMouseMoveEvent(p.X, p.Y, game); task.wait()
	vim:SendMouseButtonEvent(p.X, p.Y, 0, true, game, 1); task.wait()
	vim:SendMouseButtonEvent(p.X, p.Y, 0, false, game, 1); task.wait()
end

function U.switch(n)
	P.use("h3", "HappaTasTest/h3.lua")
	local E = getgenv().__HappaTAS3_T.engine
	local ui = E.ui
	local res = {}
	local start = E.settings:get("interface")
	task.wait(1.5)
	local before = readfile("HappaTasPort/Settings3.json")
	-- the classic row: a switch named Classic interface; clicking it with the real mouse
	E.settings:set("interface", "Classic"); task.wait(1)
	local c = ui.classic
	c.menu.Visible = true
	c:tab("Settings"); task.wait(0.3)
	local ir = c.settingsRows.interface
	res.classicRow = string.format("switch %s, text box %s, label %q, on %s", tostring(ir.switch ~= nil), tostring(ir.input ~= nil), ir.label.Text, tostring(ir.on))
	-- scroll the row into view, then click it
	local list = c.byPath["MainMenu.SettingsFrame.List"]
	pcall(function() list.CanvasPosition = Vector2.new(0, math.max(0, ir.switch.AbsolutePosition.Y - list.AbsolutePosition.Y + list.CanvasPosition.Y - 40)) end)
	task.wait(0.2)
	click(ir.switch); task.wait(1)
	res.afterClassicClick = string.format("saved %s, live %s", E.settings:get("interface"), tostring(ui.live))
	-- the New interface's Settings window: a toggle
	ui.wm:open("settings"); task.wait(0.5)
	local nr = ui.settingsWin and ui.settingsWin.rows.interface
	res.newRow = nr and ("kind " .. tostring(nr.kind) .. ", value " .. tostring(nr.ctl.value)) or "no row"
	if nr then nr.ctl.onChange(true); task.wait(1) end
	res.afterNewToggle = string.format("saved %s, live %s", E.settings:get("interface"), tostring(ui.live))
	ui.wm:close("settings")
	E.settings:set("interface", start); task.wait(1.5)
	-- n switches through the store, then the file
	local mid = readfile("HappaTasPort/Settings3.json")
	for _ = 1, n do
		E.settings:set("interface", start == "New" and "Classic" or "New"); task.wait(0.3)
		E.settings:set("interface", start); task.wait(0.3)
	end
	task.wait(1.5)
	local after = readfile("HappaTasPort/Settings3.json")
	res.fileSameAfterSwitches = after == mid
	res.fileSameAsBeforeTest = after == before
	res.switches = n
	results.switch = res
	P.unloadAll()
	save()
end

function U.oldFiles()
	P.unloadAll()
	local res = {}
	local s3 = readfile("HappaTasPort/Settings3.json")
	local file = HttpService:JSONDecode(s3)
	P.use("h3", "HappaTasTest/h3.lua")
	local E = getgenv().__HappaTAS3_T.engine
	local bad, n = {}, 0
	for k, v in pairs(file.settings or {}) do
		n = n + 1
		if E.settings:get(k) ~= v then bad[#bad + 1] = k .. "=" .. tostring(v) .. " vs " .. tostring(E.settings:get(k)) end
	end
	res.settings3 = string.format("%d saved values, %d not in the store [%s]; interface %s live %s", n, #bad, table.concat(bad, ", "),
		tostring(E.settings:get("interface")), tostring(E.ui.live))
	P.unloadAll()
	-- V2's Settings.json with no Settings3.json: converted
	writefile("HappaTasTest/Settings3_keep.json", s3)
	delfile("HappaTasPort/Settings3.json")
	local ok, err = pcall(function()
		local v2 = HttpService:JSONDecode(readfile("HappaTasPort/Settings.json"))
		P.use("h3", "HappaTasTest/h3.lua")
		local E2 = getgenv().__HappaTAS3_T.engine
		local mt = getmetatable(E2.settings)
		local Settings = mt and mt.__index
		local checked, wrong = 0, {}
		local src = v2.Settings or v2.settings or v2
		for name, val in pairs(src) do
			local def = Settings and Settings.byV2 and Settings.byV2[name]
			if def then
				checked = checked + 1
				local got = E2.settings:get(def.key)
				if got ~= val and not (type(val) == "boolean" and got == (val and 1 or 0)) then wrong[#wrong + 1] = name .. "=" .. tostring(val) .. " vs " .. tostring(got) end
			end
		end
		res.v2convert = string.format("%d V2 values checked, %d different [%s]; Settings3.json written: %s", checked, #wrong,
			table.concat(wrong, ", "), tostring(isfile("HappaTasPort/Settings3.json")))
		P.unloadAll()
	end)
	writefile("HappaTasPort/Settings3.json", readfile("HappaTasTest/Settings3_keep.json"))
	res.restored = readfile("HappaTasPort/Settings3.json") == s3
	res.err = not ok and tostring(err) or nil
	results.oldFiles = res
	save()
end

function U.inspector()
	P.use("h3", "HappaTasTest/h3.lua")
	local E = getgenv().__HappaTAS3_T.engine
	local ui = E.ui
	local res = {}
	local wasIface = E.settings:get("interface")
	E.settings:set("interface", "New"); task.wait(0.5)
	E.settings:set("speedHack", 0)
	E.modes:request("idle"); task.wait(0.3); E.modes:setRun({}); task.wait(0.2)
	P.placeAtV(Vector3.new(0, 0, 0), P.SURF.plat)
	ui.wm:open("inspector"); task.wait(1)
	local insp = ui.inspector
	local function watch(label)
		local counts, last = {}, {}
		for key, row in pairs(insp.rows) do last[key] = row.value.Text; counts[key] = 0 end
		local orig = insp.step
		local cost, frames = 0, 0
		insp.step = function(self, dt) local c = os.clock(); orig(self, dt); cost = cost + os.clock() - c; frames = frames + 1 end
		local conn = RS.RenderStepped:Connect(function()
			for key, row in pairs(insp.rows) do
				local t = row.value.Text
				if t ~= last[key] then counts[key] = counts[key] + 1; last[key] = t end
			end
		end)
		local t0 = os.clock()
		task.wait(3)
		local el = os.clock() - t0
		conn:Disconnect()
		insp.step = orig
		local r = {}
		for _, k in ipairs({ "frame", "frameTime", "totalTime", "state", "position", "velocity", "cameraRotation", "fps", "happaMs", "zoom" }) do
			r[#r + 1] = string.format("%s %.1f/s", k, (counts[k] or 0) / el)
		end
		res[label] = table.concat(r, ", ") .. string.format(" | cost %.2f us/frame", cost / math.max(1, frames) * 1e6)
	end
	watch("live")
	E.modes:create(true); task.wait(0.4); E.modes:unpause(); task.wait(0.5)
	watch("recording")
	E.modes:pause(); task.wait(0.4)
	watch("paused")
	E.modes:request("test"); task.wait(0.3)
	watch("test")
	E.modes:request("idle"); task.wait(0.3)
	ui.wm:close("inspector")
	E.settings:set("interface", wasIface)
	results.inspector = res
	P.done()
	save()
end

return U
