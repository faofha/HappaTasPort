-- ================================================================================================
--  CLASSIC LOOK  (HappaTAS 3 ui, spec 8.5): the Appearance values the classic interface draws, and only
--  these: accent colour (V2's bright blues: strokes, the line under the tabs, row borders; the selected tab;
--  an on switch), text colour (V2's white texts), secondary text colour (section headers, placeholders),
--  recording colour (an outline on the Create stats panel while recording), font (every Gotham face, its
--  weight kept), number font (the stats panels), text size (the menu, merge dialog, join message and status
--  line, scaled from V2's sizes by textSize / 13; the stats panels keep Stats Text Size) and interface scale
--  (a UIScale on each top-level panel). Glass, blur, edge light, corners, button shape, shadows and
--  animations are left to the new interface: nothing here reads or writes them.
-- ================================================================================================
local ClassicLook = {}
ClassicLook.__index = ClassicLook

local KEYS = { "accentColor", "textColor", "secondaryTextColor", "recordingColor", "font", "numberFont", "textSize", "interfaceScale" }
local BLUES = { "008DED", "004DCD", "00A9F4", "00C4F8" } -- (V2's c(0,141,237), c(0,77,205), c(0,169,244), c(0,196,248))
local WHITE = Color3.new(1, 1, 1)
local STATS = { IdleStats = true, CreateStats = true, TestStats = true, MergeStats = true }
local SIZED = { MainMenu = true, Merge = true, JoinMessage = true, Status = true }
local SCALED = { "MainMenu", "IdleStats", "CreateStats", "TestStats", "Merge", "MergeStats", "JoinMessage", "Status" }

local function hex(c3) return c3:ToHex():upper() end
local function family(name) return "rbxasset://fonts/families/" .. tostring(name) .. ".json" end
local function color(v) return Color3.fromHex(tostring(v):sub(2)) end

-- the top-level panel an instance is in (its ancestor right under the ScreenGui)
local function topOf(inst, gui)
	local x = inst
	while x and x.Parent ~= gui do x = x.Parent end
	return x and x.Name
end

function ClassicLook.new(classic)
	local E = classic.E
	local self = setmetatable({ classic = classic, E = E, strokes = {}, fills = {}, whites = {}, seconds = {}, gotham = {}, numbers = {},
		sizes = {}, scales = {} }, ClassicLook)
	local isBlue = {}
	for _, h in ipairs(BLUES) do isBlue[h] = true end
	self.isBlue = isBlue
	for _, d in ipairs(classic.gui:GetDescendants()) do self:adopt(d) end
	for _, name in ipairs(SCALED) do
		local f = classic.byPath[name]
		if f then
			local sc = Instance.new("UIScale")
			sc.Parent = f
			self.scales[#self.scales + 1] = sc
		end
	end
	local rec = Instance.new("UIStroke")
	rec.Name = "RecStroke"
	rec.Thickness = 2
	rec.Enabled = false
	rec.Parent = classic.byPath.CreateStats
	self.rec = rec
	for _, key in ipairs(KEYS) do
		classic.offs[#classic.offs + 1] = E.settings:changed(key, function() self:apply() end)
	end
	self:apply()
	return self
end

-- one instance (and nothing below it): what of it follows which value
function ClassicLook:adopt(d)
	local gui = self.classic.gui
	if d:IsA("UIStroke") then
		if self.isBlue[hex(d.Color)] then self.strokes[#self.strokes + 1] = d end
		return
	end
	if not d:IsA("GuiObject") then return end
	if self.isBlue[hex(d.BackgroundColor3)] and d.BackgroundTransparency < 1 then self.fills[#self.fills + 1] = d end
	if not (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) then return end
	local top = topOf(d, gui)
	if d.Name:sub(1, 8) == "Section_" then
		self.seconds[#self.seconds + 1] = { label = d }
	elseif d.TextColor3 == WHITE then
		self.whites[#self.whites + 1] = d
	end
	if d:IsA("TextBox") then self.seconds[#self.seconds + 1] = { placeholder = d } end
	if STATS[top] then
		self.numbers[#self.numbers + 1] = { d, d.FontFace.Weight, d.FontFace.Style }
	elseif tostring(d.FontFace.Family):find("GothamSSm", 1, true) then
		self.gotham[#self.gotham + 1] = { d, d.FontFace.Weight, d.FontFace.Style }
	end
	if SIZED[top] then self.sizes[#self.sizes + 1] = { d, d.TextSize } end
end

-- every instance below root (a slot row made later), then the values on it
function ClassicLook:adoptAll(root)
	self:adopt(root)
	for _, d in ipairs(root:GetDescendants()) do self:adopt(d) end
	self:apply()
end

function ClassicLook:accent() return color(self.E.settings:get("accentColor")) end

function ClassicLook:apply()
	local s = self.E.settings
	local acc = color(s:get("accentColor"))
	local text, second = color(s:get("textColor")), color(s:get("secondaryTextColor"))
	for _, x in ipairs(self.strokes) do if x.Color ~= acc then x.Color = acc end end
	for _, x in ipairs(self.fills) do if x.BackgroundColor3 ~= acc then x.BackgroundColor3 = acc end end
	for _, x in ipairs(self.whites) do if x.TextColor3 ~= text then x.TextColor3 = text end end
	for _, x in ipairs(self.seconds) do
		if x.placeholder then
			if x.placeholder.PlaceholderColor3 ~= second then x.placeholder.PlaceholderColor3 = second end
		elseif x.label.TextColor3 ~= second then
			x.label.TextColor3 = second
		end
	end
	local f, nf = family(s:get("font")), family(s:get("numberFont"))
	for _, x in ipairs(self.gotham) do
		local face = Font.new(f, x[2], x[3])
		if x[1].FontFace ~= face then x[1].FontFace = face end
	end
	for _, x in ipairs(self.numbers) do
		local face = Font.new(nf, x[2], x[3])
		if x[1].FontFace ~= face then x[1].FontFace = face end
	end
	local k = s:get("textSize") / 13
	for _, x in ipairs(self.sizes) do
		local size = math.floor(x[2] * k + 0.5)
		if x[1].TextSize ~= size then x[1].TextSize = size end
	end
	local scale = s:get("interfaceScale") / 100
	for _, sc in ipairs(self.scales) do if sc.Scale ~= scale then sc.Scale = scale end end
	self.rec.Color = color(s:get("recordingColor"))
	local c = self.classic
	if c.tabName then c:tab(c.tabName) end -- (the selected tab in the accent colour)
	if c.settingsRows then
		for _, r in pairs(c.settingsRows) do
			if r.knob and r.on then r.knob.BackgroundColor3 = acc end
		end
	end
end

-- the Create panel's outline while recording
function ClassicLook:recording(on)
	if self.rec.Enabled ~= on then self.rec.Enabled = on end
end

return ClassicLook
