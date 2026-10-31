-- ================================================================================================
--  FIELD  (HappaTAS 3 ui kit): a text box in a dark pill (the mockup's .field), with an accent ring while
--  typing. onCommit(text) -> accepted runs on Enter and when the box loses focus (Esc keeps the old text);
--  a refused text shows the old one again. The search variant (opts.search) is 32 px high with its text
--  vertically centred and a magnifier on the right, and reports onInput(text) as you type.
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local Env = import("platform/env")

local Field = {}
Field.__index = Field

function Field.new(ctx, parent, opts)
	opts = opts or {}
	local self = K.new(ctx, Field)
	self.text, self.onCommit = opts.text or "", opts.onCommit
	local h = opts.search and 32 or 24
	local gui = K.frame("Field", parent, Color3.new(0, 0, 0))
	gui.BackgroundTransparency = 0.75
	gui.Size = UDim2.new(0, opts.w or 120, 0, h)
	self.gui = gui
	self.cornerObj = K.corner(gui)
	local ring = K.stroke(gui, Color3.new(1, 1, 1), 1, 2)
	self.ring = ring
	local box = K.text("TextBox", "Box", gui)
	box.Text = self.text
	box.PlaceholderText = opts.placeholder or ""
	box.TextYAlignment = Enum.TextYAlignment.Center
	box.TextXAlignment = opts.search and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center
	box.Position = UDim2.new(0, opts.search and 16 or 8, 0, 0)
	box.Size = UDim2.new(1, opts.search and -44 or -16, 1, 0)
	self.box = box
	if opts.search then
		-- (a magnifier drawn from two frames: no listed font has a magnifier glyph, live)
		local icon = K.frame("Icon", gui)
		icon.AnchorPoint = Vector2.new(1, 0.5)
		icon.Position = UDim2.new(1, -14, 0.5, 0)
		icon.Size = UDim2.new(0, 14, 0, 14)
		local lens = K.frame("Lens", icon)
		lens.Size = UDim2.new(0, 10, 0, 10)
		K.corner(lens, 999)
		local rim = K.stroke(lens, Color3.new(1, 1, 1), 0, 1.5)
		local handle = K.frame("Handle", icon, Color3.new(1, 1, 1))
		handle.BackgroundTransparency = 0
		handle.AnchorPoint = Vector2.new(0.5, 0.5)
		handle.Position = UDim2.new(0, 11.5, 0, 11.5)
		handle.Size = UDim2.new(0, 5, 0, 1.5)
		handle.Rotation = 45
		K.style(self, function(th)
			W.set(rim, "Color", th.c.text2)
			W.set(handle, "BackgroundColor3", th.c.text2)
		end)
		self.icon = icon
	end
	local size = opts.search and 13.5 or 12
	K.style(self, function(th)
		W.set(self.cornerObj, "CornerRadius", UDim.new(0, th.corner("control")))
		W.set(box, "FontFace", th.font(opts.number and "number" or "text"))
		W.set(box, "TextSize", th.size(size))
		W.set(box, "TextColor3", th.c.text)
		W.set(box, "PlaceholderColor3", th.c.text2)
		W.set(ring, "Color", th.c.accent)
	end)
	K.rect(self, { onRelease = function(_, clicked) if clicked then box:CaptureFocus() end end }, opts.z)
	self.cancel = false
	local uis = Env.svc("UserInputService")
	local conns = {
		box.Focused:Connect(function() W.set(ring, "Transparency", 0) end),
		box.FocusLost:Connect(function(_, cause)
			if cause and cause.KeyCode == Enum.KeyCode.Escape then self.cancel = true end
			self:commit()
		end),
		box:GetPropertyChangedSignal("Text"):Connect(function() if self.onInput then self.onInput(box.Text) end end),
	}
	for _, c in ipairs(conns) do self.offs[#self.offs + 1] = function() c:Disconnect() end end
	K.connect(self, uis.InputBegan, function(inp)
		if inp.KeyCode == Enum.KeyCode.Escape and box:IsFocused() then
			self.cancel = true
			box:ReleaseFocus()
		end
	end)
	return self
end

function Field:commit()
	W.set(self.ring, "Transparency", 1)
	local box = self.box
	if self.cancel then
		self.cancel = false
		box.Text = self.text
		return
	end
	local t = box.Text
	local ok = true
	if self.onCommit then ok = self.onCommit(t) ~= false end
	if ok then self.text = t else box.Text = self.text end
end

function Field:set(text)
	self.text = text
	self.box.Text = text
end

Field.destroy = K.destroy

return Field
