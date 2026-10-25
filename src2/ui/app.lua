-- ================================================================================================
--  APP  (HappaTAS 3 ui): starts the interface after the engine (E.ui). It owns the root, the pointer and
--  the Menu key, tells the engine when the pointer is on the interface (E.inputs.mouseOverOwn: a click
--  there is never a Pause / Unpause) and when a window is open (E.modalOpen: the mouse is free), and has
--  its text boxes count as typing (E.typing:watch). Everything is undone on Unload (its own scope).
--  The Menu key shows / hides the whole interface; it works even when the game took the key, never while
--  the player types (V2.37.1).
-- ================================================================================================
local Env = import("platform/env")
local Root = import("ui/root")
local Pointer = import("ui/pointer")
local Theme = import("ui/theme")
local Tween = import("ui/tween")

local UI = {}
UI.__index = UI

function UI.start(E)
	local life = E.life:scope("ui")
	local self = setmetatable({ E = E, life = life, shown = true, wm = nil }, UI)
	E.ui = self
	self.root = Root.new(E)
	life:own(function() self.root:destroy() end)
	if self.root.refused then
		E.bus:emit("status", "The interface needs gethui, CoreGui or \"Allow PlayerGui Interface\"", true)
		return self
	end
	self.pointer = Pointer.new(E, self.root, life)
	self.theme = Theme.new(E, life)
	self.tween = Tween.new(E, life)
	E.inputs.mouseOverOwn = function() return self:pointerOver() end
	E.modalOpen = function() return self:anyWindowOpen() end
	life:own(function()
		E.inputs.mouseOverOwn = nil
		E.modalOpen = nil
	end)
	E.typing:watch(self.root.gui)
	local uis = Env.svc("UserInputService")
	life:connect(uis.InputBegan, function(inp)
		if E.typing:active(inp) then return end
		if E.controls:matches(inp, "menu") then self:toggle() end
	end)
	return self
end

function UI:setShown(on)
	self.shown = on == true
	self.root:setShown(self.shown)
	self.E.bus:emit("uiShown", self.shown)
end

function UI:toggle() self:setShown(not self.shown) end

-- the pointer is on the interface (or a press that started on it isn't released yet)
function UI:pointerOver()
	return self.shown and self.pointer ~= nil and self.pointer:busy()
end

-- a window is open (the window manager comes in with the windows)
function UI:anyWindowOpen()
	return self.shown and self.wm ~= nil and self.wm:anyOpen()
end

return UI
