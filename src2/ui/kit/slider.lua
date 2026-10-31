-- ================================================================================================
--  SLIDER  (HappaTAS 3 ui kit): the mockup's slider (a 112 x 4 track, accent fill, a 22 px glass knob)
--  with its value as a number beside it. Click or drag on the track; click the number to type a value
--  (Enter or leaving the box applies it, Esc keeps the old one). A typed value goes through
--  opts.sanitize(text) -> value | nil when given, else: a number, clamped to min / max, on the step
--  (letters, empty and nan refused: Review Focus 5). onChange(value) for the player's changes only.
--  opts = { min, max, step, fmt = f(v) -> text, w (track, 112), sanitize, z }
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local Env = import("platform/env")

local Slider = {}
Slider.__index = Slider

local LABEL_W, GAP, KNOB = 48, 8, 22

local function fmtDefault(v)
	if v == math.floor(v) then return tostring(v) end
	return string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
end

function Slider.new(ctx, parent, opts)
	local self = K.new(ctx, Slider)
	self.min, self.max, self.step = opts.min or 0, opts.max or 1, opts.step
	self.fmt, self.sanitizeOpt = opts.fmt or fmtDefault, opts.sanitize
	self.value = self.min
	local tw = opts.w or 112
	local gui = K.frame("Slider", parent)
	gui.Size = UDim2.new(0, LABEL_W + GAP + tw, 0, 24)
	self.gui = gui
	local label = K.label(self, gui, "", "number", 12)
	label.Size = UDim2.new(0, LABEL_W, 1, 0)
	label.TextXAlignment = Enum.TextXAlignment.Right
	self.label = label
	local box = K.text("TextBox", "Value", gui)
	box.Size = label.Size
	box.Visible = false
	box.TextXAlignment = Enum.TextXAlignment.Right
	self.box = box
	K.style(self, function(th)
		W.set(box, "FontFace", th.font("number"))
		W.set(box, "TextSize", th.size(12))
		W.set(box, "TextColor3", th.c.text)
	end)
	local hit = K.frame("Hit", gui)
	hit.Position = UDim2.new(0, LABEL_W + GAP, 0, 1)
	hit.Size = UDim2.new(0, tw, 0, KNOB)
	local track = K.frame("Track", hit, Color3.new(1, 1, 1))
	track.Position = UDim2.new(0, 0, 0.5, -2)
	track.Size = UDim2.new(1, 0, 0, 4)
	K.corner(track, 2)
	self.track, self.hit = track, hit
	local fill = K.frame("Fill", track, Color3.new(1, 1, 1))
	fill.Size = UDim2.new(0, 0, 1, 0)
	K.corner(fill, 2)
	self.fill = fill
	local knob = K.frame("Knob", hit, Color3.new(1, 1, 1))
	knob.Size = UDim2.new(0, KNOB, 0, KNOB)
	knob.AnchorPoint = Vector2.new(0.5, 0)
	K.corner(knob, KNOB / 2)
	K.stroke(knob, Color3.new(1, 1, 1), 0.05, 1)
	self.knob = knob
	K.style(self, function(th)
		W.set(track, "BackgroundTransparency", 0.75)
		W.set(fill, "BackgroundColor3", th.c.accent)
	end)
	local function fromX(pos)
		local x0, w = track.AbsolutePosition.X, track.AbsoluteSize.X
		if w <= 0 then return end
		local a = math.clamp((pos.X - x0) / w, 0, 1)
		self:userSet(self.min + a * (self.max - self.min))
	end
	K.rect(self, { gui = hit, onPress = fromX, onDrag = function(pos) fromX(pos) end }, opts.z)
	K.rect(self, { gui = label, onRelease = function(_, clicked) if clicked then self:edit() end end }, opts.z)
	-- (Esc while typing: keep the old value; FocusLost alone can't tell Esc from a click elsewhere)
	self.cancel = false
	local uis = Env.svc("UserInputService")
	local escConn = uis.InputBegan:Connect(function(inp)
		if inp.KeyCode == Enum.KeyCode.Escape and box.Visible and box:IsFocused() then
			self.cancel = true
			box:ReleaseFocus()
		end
	end)
	self.offs[#self.offs + 1] = function() escConn:Disconnect() end
	local lostConn = box.FocusLost:Connect(function() self:commit() end)
	self.offs[#self.offs + 1] = function() lostConn:Disconnect() end
	self:show()
	return self
end

function Slider:round(v)
	v = math.clamp(v, self.min, self.max)
	if self.step and self.step > 0 then
		v = self.min + math.floor((v - self.min) / self.step + 0.5) * self.step
		v = math.clamp(v, self.min, self.max)
	end
	return math.floor(v * 1e9 + 0.5) / 1e9
end

function Slider:show()
	local a = (self.max > self.min) and (self.value - self.min) / (self.max - self.min) or 0
	W.set(self.fill, "Size", UDim2.new(a, 0, 1, 0))
	W.set(self.knob, "Position", UDim2.new(a, 0, 0, 0))
	W.set(self.label, "Text", self.fmt(self.value))
end

function Slider:set(v)
	v = tonumber(v)
	if not v then return end
	self.value = self:round(v)
	self:show()
end

function Slider:userSet(v)
	v = self:round(v)
	if v == self.value then return end
	self.value = v
	self:show()
	if self.onChange then self.onChange(v) end
end

function Slider:edit()
	self.cancel = false
	self.box.Text = tostring(self.value)
	W.set(self.label, "Visible", false)
	W.set(self.box, "Visible", true)
	self.box:CaptureFocus()
end

function Slider:sanitize(text)
	if self.sanitizeOpt then return self.sanitizeOpt(text) end
	local n = tonumber(text)
	if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
	return self:round(n)
end

function Slider:commit()
	if not self.box.Visible then return end -- (FocusLost after Esc already handled)
	W.set(self.box, "Visible", false)
	W.set(self.label, "Visible", true)
	if self.cancel then
		self.cancel = false
		self:show()
		return
	end
	local v = self:sanitize(self.box.Text)
	if v == nil then
		self:show()
		return
	end
	self.value = nil
	self:userSet(v)
end

Slider.destroy = K.destroy

return Slider
