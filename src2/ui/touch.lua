-- ================================================================================================
--  TOUCH  (HappaTAS 3 ui, spec 2 / 8.2): touch buttons on a touch screen without a keyboard (phones,
--  tablets; a touch laptop has its keys), for the new interface: Idle / Create / Test always; in Create
--  return, unpause 1 frame, look around, back and forward (held: the press holds, the release lets go),
--  pause / unpause (its icon follows), back / forward 1 frame, delete TAS and optimize (V2's mobile calls);
--  and a Menu button that shows / hides the interface (the Menu key's job). Every button goes through
--  E.modes:request and is dimmed when the request isn't allowed. A column at the left, above Roblox's
--  thumbstick area. Also, for either interface: during Test one tap asks "Tap again to quit Test" and a
--  second tap within 1 s ends playback (V2's TouchTap quit); a single tap never does.
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local Env = import("platform/env")
local Icon = import("ui/kit/icon")

local Touch = {}
Touch.__index = Touch

local Z = 30000000
local BTN_W, BTN_H, GAP = 56, 40, 6
local QUIT_WINDOW = 1
-- { name, icon kind or text, action, Create only, held }
local BUTTONS = {
	{ "idle", "Idle", "idle" }, { "create", "Create", "create" }, { "test", "Test", "test" },
	{ "ret", "Return", "return", true }, { "unpause1", "+1", "unpause1", true }, { "look", "Look", "lookAround", true },
	{ "back", "@rewind", "back", true, true }, { "pause", "@play", "pause", true }, { "forward", "@fastforward", "forward", true, true },
	{ "back1", "@back1", "back1", true }, { "forward1", "@forward1", "forward1", true }, { "menu", "Menu", nil },
	{ "delete", "Delete", "deleteTas", true }, { "optimize", "Optimize", "optimize", true },
}

-- a touch screen without a keyboard (the plan's touch rule, also phase 5a's sheets)
function Touch.wanted(uis)
	return uis ~= nil and uis.TouchEnabled == true and uis.KeyboardEnabled ~= true
end

function Touch.new(ui)
	local E = ui.E
	local uis = Env.svc("UserInputService")
	local self = setmetatable({ ui = ui, E = E, buttons = {}, offs = {}, rects = {}, lastTap = nil }, Touch)
	self.ctx = { E = E, ui = ui, theme = ui.theme, tween = ui.tween, typing = E.typing,
		pointer = {
			add = function(r, z)
				r.z = Z + (z or 0)
				r.group = r.group or self.gui
				self.rects[#self.rects + 1] = r
				ui.pointer:add(r)
				return r
			end,
			remove = function(r) ui.pointer:remove(r) end,
		} }
	local gui = K.frame("TouchPad", ui.root.padLayer)
	gui.Position = UDim2.new(0, 8, 0.16, 0)
	gui.Size = UDim2.new(0, BTN_W * 3 + GAP * 2, 0, (BTN_H + GAP) * 5)
	gui.ZIndex = 300000
	self.gui = gui
	for i, def in ipairs(BUTTONS) do self:button(i, def) end
	self.offs[#self.offs + 1] = E.state:watch("mode", function() self:refresh() end)
	self.offs[#self.offs + 1] = E.bus:on("uiShown", function() self:refresh() end)
	self.offs[#self.offs + 1] = ui.theme:changed(function() self:restyle() end)
	-- Test's double-tap quit (either interface)
	ui.life:connect(uis.TouchTap, function() self:tap() end)
	ui.life:own(function() self:destroy() end)
	self:restyle()
	self:refresh()
	return self
end

function Touch:button(i, def)
	local name, face, action, createOnly, held = def[1], def[2], def[3], def[4], def[5]
	local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
	local f = K.frame("Button_" .. name, self.gui, Color3.new(1, 1, 1))
	f.Position = UDim2.new(0, col * (BTN_W + GAP), 0, row * (BTN_H + GAP))
	f.Size = UDim2.new(0, BTN_W, 0, BTN_H)
	f.ZIndex = 300001
	K.corner(f, 10)
	local b = { name = name, gui = f, action = action, createOnly = createOnly, held = held, enabled = true }
	if face:sub(1, 1) == "@" then
		local icon = Icon.new(self.ctx, f, face:sub(2), 16)
		icon.gui.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.gui.Position = UDim2.new(0.5, 0, 0.5, 0)
		b.icon = icon
	else
		local l = K.text("TextLabel", "Label", f)
		l.Text = face
		l.Size = UDim2.new(1, 0, 1, 0)
		l.ZIndex = 300002
		b.label = l
	end
	self.buttons[name] = b
	self.ctx.pointer.add({ gui = f,
		onPress = function()
			if not b.enabled then return end
			if held then
				self.E.modes:request(action)
				b.holding = true
			end
		end,
		onRelease = function(_, clicked)
			if held then
				if b.holding then
					b.holding = false
					self.E.modes:release(action)
				end
			elseif clicked and b.enabled then
				self:press(b)
			end
			self:refresh()
		end }, 1)
end

function Touch:press(b)
	local E = self.E
	if b.name == "menu" then
		self.ui:toggle()
	elseif b.name == "pause" then
		E.modes:request(E.paused and "unpause" or "pause")
	elseif b.action == "deleteTas" or b.action == "optimize" then
		E.modes:request(b.action, { mobile = true })
	else
		E.modes:request(b.action)
	end
	-- (the mode machine runs its steps on the next frame: the buttons follow then too)
	task.defer(function() if not self.dead then self:refresh() end end)
end

function Touch:restyle()
	local th = self.ui.theme
	for _, b in pairs(self.buttons) do
		W.set(b.gui, "BackgroundColor3", th.c.glass)
		if b.label then
			W.set(b.label, "FontFace", th.font("bold"))
			W.set(b.label, "TextSize", th.size(12))
			W.set(b.label, "TextColor3", th.c.text)
		end
	end
	self:refresh()
end

-- which buttons show (Create's only in Create, none during Test but Menu), which are dimmed, the pause icon
function Touch:refresh()
	local E, ui = self.E, self.ui
	local active = ui.live == "New"
	W.set(self.gui, "Visible", active)
	if not active then return end
	local inCreate = E.mode == 2
	for _, b in pairs(self.buttons) do
		local show = (not b.createOnly or inCreate) and (E.mode ~= 3 or b.name == "menu")
		W.set(b.gui, "Visible", show)
		local on
		if b.name == "menu" then on = true
		elseif b.name == "pause" then on = E.modes:allowed(E.paused and "unpause" or "pause")
		else on = E.modes:allowed(b.action) end
		b.enabled = on
		W.set(b.gui, "BackgroundTransparency", on and 0.35 or 0.7)
	end
	local p = self.buttons.pause
	if p and p.icon then p.icon:setKind(E.paused and "play" or "pause") end
end

-- a tap during Test: the first asks, a second within QUIT_WINDOW s ends playback
function Touch:tap()
	local E = self.E
	if E.mode ~= 3 then
		self.lastTap = nil
		return
	end
	local now = os.clock()
	if self.lastTap and now - self.lastTap <= QUIT_WINDOW then
		self.lastTap = nil
		E.quitTest = true
		E.modes:finishTest()
		E.quitTest = false
		E.bus:emit("status", "Test Quit")
		return
	end
	self.lastTap = now
	E.bus:emit("status", "Tap again to quit Test")
end

function Touch:destroy()
	if self.dead then return end
	self.dead = true
	for _, off in ipairs(self.offs) do off() end
	for _, r in ipairs(self.rects) do self.ui.pointer:remove(r) end
	pcall(function() self.gui:Destroy() end)
end

return Touch
