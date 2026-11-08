-- ================================================================================================
--  DROPDOWN  (HappaTAS 3 ui kit): a pill with the value and ▾; a click opens a plain list in a popover
--  (closed by a pick, Esc or a press outside). With fontPreview each name is drawn in its own font, and
--  hovering one shows it on the whole interface (theme:preview); moving away or closing ends the preview,
--  a click keeps it (onChange: the owner stores it). With multi the value is "A,B" (some of the options, in their
--  order, "" for none): a click ticks or unticks one and the list stays open; the pill lists them ("None").
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local Popover = import("ui/kit/popover")

local Dropdown = {}
Dropdown.__index = Dropdown

local function family(name) return "rbxasset://fonts/families/" .. tostring(name) .. ".json" end

function Dropdown.new(ctx, parent, opts)
	local self = K.new(ctx, Dropdown)
	self.options, self.fontPreview, self.w = opts.options, opts.fontPreview == true, opts.w or 150
	self.multi = opts.multi == true
	self.value = self.multi and "" or opts.options[1]
	local gui = K.frame("Dropdown", parent, Color3.new(1, 1, 1))
	gui.BackgroundTransparency = 0.88
	gui.Size = UDim2.new(0, self.w, 0, 24)
	self.gui = gui
	self.cornerObj = K.corner(gui)
	local label = K.label(self, gui, "", "text", 12)
	label.Position = UDim2.new(0, 12, 0, 0)
	label.Size = UDim2.new(1, -34, 1, 0)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	self.label = label
	local arrow = K.label(self, gui, "▼", "bold", 10)
	arrow.AnchorPoint = Vector2.new(1, 0.5)
	arrow.Position = UDim2.new(1, -10, 0.5, 0)
	arrow.Size = UDim2.new(0, 12, 0, 12)
	K.style(self, function(th) W.set(self.cornerObj, "CornerRadius", UDim.new(0, th.corner("control"))) end)
	K.rect(self, { onRelease = function(_, clicked) if clicked then self:open() end end }, opts.z)
	self:show()
	return self
end

-- (multi: is option o one of those ticked)
function Dropdown:picked(o)
	if not self.multi then return o == self.value end
	return ("," .. tostring(self.value) .. ","):find("," .. o .. ",", 1, true) ~= nil
end

function Dropdown:show()
	local text = tostring(self.value)
	if self.multi then text = (text == "") and "None" or text:gsub(",", ", ") end
	W.set(self.label, "Text", text)
	if self.items then
		for o, it in pairs(self.items) do
			W.set(it.item, "BackgroundTransparency", self:picked(o) and 0.84 or 1)
			if it.dot then W.set(it.dot, "Visible", self:picked(o)) end
		end
	end
end

function Dropdown:set(v)
	if self.multi then
		if type(v) ~= "string" then return end
	elseif not table.find(self.options, v) then
		return
	end
	self.value = v
	self:show()
end

-- multi: the value with option o ticked or unticked
function Dropdown:toggled(o)
	local out = {}
	for _, x in ipairs(self.options) do
		local on = self:picked(x)
		if x == o then on = not on end
		if on then out[#out + 1] = x end
	end
	return table.concat(out, ",")
end

function Dropdown:open()
	if self.pop then return end
	local rowH = self.fontPreview and 25 or 24
	local pop = Popover.open(self.ctx, self.gui, self.w, rowH * #self.options + 8)
	self.pop = pop
	self.list = pop.frame
	local theme = self.ctx.theme
	self.items = {}
	pop.catcherRect.onHover = function(on) if on and self.fontPreview then theme:preview(nil) end end
	for i, o in ipairs(self.options) do
		local item = K.text("TextLabel", "Item", pop.frame)
		item.Text = o
		item.Position = UDim2.new(0, 4, 0, 4 + (i - 1) * rowH)
		item.Size = UDim2.new(1, -8, 0, rowH)
		item.TextXAlignment = Enum.TextXAlignment.Left
		item.BackgroundColor3 = Color3.new(1, 1, 1)
		item.BackgroundTransparency = self:picked(o) and 0.84 or 1
		item.ZIndex = 3
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.Parent = item
		K.corner(item, 8)
		item.FontFace = self.fontPreview and Font.new(family(o)) or theme.font("text")
		item.TextSize = theme.size(12.5)
		item.TextColor3 = theme.c.text
		local dot
		if self.multi then
			-- (a ticked one: highlighted, with a dot on the right)
			dot = K.text("TextLabel", "Dot", item)
			dot.Text = "•"
			dot.AnchorPoint = Vector2.new(1, 0.5)
			dot.Position = UDim2.new(1, -8, 0.5, 0)
			dot.Size = UDim2.new(0, 12, 1, 0)
			dot.TextColor3 = theme.c.text
			dot.TextSize = theme.size(14)
			dot.Visible = self:picked(o)
			dot.ZIndex = 4
		end
		self.items[o] = { item = item, dot = dot }
		pop:add({ gui = item,
			onHover = function(on)
				W.set(item, "BackgroundTransparency", (on or self:picked(o)) and 0.84 or 1)
				if self.fontPreview then theme:preview(on and o or nil) end
			end,
			onRelease = function(_, clicked)
				if not clicked then return end
				if self.multi then
					self.value = self:toggled(o)
					self:show()
					if self.onChange then self.onChange(self.value) end
					return
				end
				self.value = o
				self:show()
				self:close()
				if self.onChange then self.onChange(o) end
			end }, 2)
	end
	pop.onClose = function()
		if self.fontPreview then theme:preview(nil) end
		self.pop, self.list, self.items = nil, nil, nil
	end
end

function Dropdown:close()
	if self.pop then self.pop:close() end
end

function Dropdown:destroy()
	self:close()
	K.destroy(self)
end

return Dropdown
