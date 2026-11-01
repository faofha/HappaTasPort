-- ================================================================================================
--  APP  (HappaTAS 3 ui): starts the interface after the engine (E.ui). It owns the root, the pointer and
--  the Menu key, tells the engine when the pointer is on the interface (E.inputs.mouseOverOwn: a click
--  there is never a Pause / Unpause) and when a window is open (E.modalOpen: the mouse is free), and has
--  its text boxes count as typing (E.typing:watch). Everything is undone on Unload (its own scope).
--  The Menu key shows / hides the whole interface; it works even when the game took the key, never while
--  the player types (V2.37.1).
--  Interface: New / Classic (spec 8.5): only one interface is live; the other is hidden and does no
--  per-frame work (bus "uiShown" with newActive()), and the engine's hooks answer for the live one.
-- ================================================================================================
local Env = import("platform/env")
local Root = import("ui/root")
local Pointer = import("ui/pointer")
local Theme = import("ui/theme")
local Tween = import("ui/tween")
local Windows = import("ui/windows")
local Layout = import("ui/layout")
local Dock = import("ui/dock")
local Toast = import("ui/toast")
local SettingsWin = import("ui/win/settings")
local ControlsWin = import("ui/win/controls")
local Frost = import("ui/frost")
local Bar = import("ui/bar/bar")
local InspectorWin = import("ui/win/inspector")
local LibraryWin = import("ui/win/library")
local MergeWin = import("ui/win/merge")
local HelpWin = import("ui/win/help")
local Classic = import("ui/classic/classic")

local UI = {}
UI.__index = UI

function UI.start(E)
	local life = E.life:scope("ui")
	local self = setmetatable({ E = E, life = life, shown = true, wm = nil, modal = false, live = "New", classic = nil }, UI)
	E.ui = self
	self.root = Root.new(E)
	life:own(function() self.root:destroy() end)
	if self.root.refused then
		E.bus:emit("status", "The interface needs gethui, CoreGui or \"Allow PlayerGui Interface\"", true)
		return self
	end
	self.pointer = Pointer.new(E, self.root, life)
	Layout.probeParent = self.root.gui
	self.theme = Theme.new(E, life)
	self.tween = Tween.new(E, life)
	self.wm = Windows.new(E, self)
	self.dock = Dock.new(self)
	self.toast = Toast.new(self)
	self.frost = Frost.new(self)
	self.bar = Bar.new(self)
	SettingsWin.define(self)
	ControlsWin.define(self)
	InspectorWin.define(self)
	LibraryWin.define(self)
	MergeWin.define(self)
	HelpWin.define(self)
	E.inputs.mouseOverOwn = function(m)
		if self.live == "Classic" then return self.classic ~= nil and self.classic:pointerOver(m) end
		return self:pointerOver()
	end
	-- (asked several times a frame by the camera and the cursor: a stored answer, kept up to date below)
	E.modalOpen = function() return self.modal end -- (E.modal: the same answer as a field, for per-frame readers)
	life:own(self.wm:changed(function() self:updateModal() end))
	self.wm:restoreOpen() -- (the windows open when the script last ran, or open by default)
	self:updateModal()
	life:own(function()
		E.inputs.mouseOverOwn = nil
		E.modalOpen = nil
		E.modal = nil
	end)
	E.typing:watch(self.root.gui)
	local uis = Env.svc("UserInputService")
	life:connect(uis.InputBegan, function(inp)
		if E.typing:active(inp) then return end
		if E.controls:matches(inp, "menu") then
			if self.live == "Classic" and self.classic then self.classic:toggle() else self:toggle() end
		end
	end)
	-- (the interface chosen, now and whenever the setting changes)
	life:own(E.settings:changed("interface", function(v) self:setInterface(v) end))
	self:setInterface(E.settings:get("interface"))
	return self
end

-- the new interface is live and shown (its per-frame work runs only then)
function UI:newActive() return self.live == "New" and self.shown end

-- the live interface is shown
function UI:liveShown()
	if self.live == "Classic" then return self.classic ~= nil and self.classic.shown end
	return self.shown
end

-- typing in a box of ours and waiting for a key to bind end (they belong to the interface going away)
function UI:endTyping()
	local E = self.E
	local own = E.typing.own
	if own then pcall(function() own:ReleaseFocus() end) end
	E.typing.own = nil
	if self.controlsWin and self.controlsWin.stopWaiting then self.controlsWin.stopWaiting() end
	if self.classic and self.classic.stopWaiting then self.classic.stopWaiting() end
	E.typing.rebinding = false
end

-- "New" or "Classic" (anything else is New): the other one hidden, in the same frame
function UI:setInterface(name)
	if name ~= "Classic" then name = "New" end
	if name == self.live and (name == "New" or self.classic) then return end
	self:endTyping()
	if name == "Classic" and not self.classic then
		self.classic = Classic.new(self)
		local c = self.classic
		self.life:own(function() c:destroy() end)
		self.E.typing:watch(c.gui)
	end
	self.live = name
	self.root.shown = self:newActive()
	self.root.gui.Enabled = self:newActive()
	if self.classic then self.classic.gui.Enabled = name == "Classic" and self.classic.shown end
	self:updateModal()
	self.E.bus:emit("uiShown", self:newActive())
end

function UI:updateModal()
	if self.live == "Classic" then
		self.modal = self.classic ~= nil and self.classic:modal()
	else
		self.modal = self.shown and self.wm ~= nil and self.wm:anyModalOpen()
	end
	self.E.modal = self.modal
end

-- the new interface shown / hidden (the Menu key while it is live)
function UI:setShown(on)
	self.shown = on == true
	self.root.shown = self:newActive() -- (the pointer ignores a hidden interface: Pointer:over)
	self.root.gui.Enabled = self:newActive()
	self:updateModal()
	self.E.bus:emit("uiShown", self:newActive())
end

function UI:toggle() self:setShown(not self.shown) end

-- a Dock button for window id (defined with ui.wm:define first)
function UI:addDockButton(id) return self.dock and self.dock:add(id) end

-- the pointer is on the interface (or a press that started on it isn't released yet)
function UI:pointerOver()
	return self:newActive() and self.pointer ~= nil and self.pointer:busy()
end

-- a window is open (the window manager comes in with the windows)
function UI:anyWindowOpen()
	return self:newActive() and self.wm ~= nil and self.wm:anyOpen()
end

return UI
