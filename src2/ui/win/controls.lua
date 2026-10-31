-- ================================================================================================
--  CONTROLS WINDOW  (HappaTAS 3 ui, spec 8.3): every action with its key. Click a key to rebind it: the
--  engine's keys are off while it waits (Typing.rebinding), the next key or mouse button binds it, and
--  that press never runs a control (Typing.boundInput: V2.37.2, Roblox doesn't promise the order of
--  InputBegan handlers). Esc cancels, ✕ unbinds, ↺ resets one, Reset all resets every key. Two actions on
--  the same key are marked (amber, with a note naming the other), except Pause / Unpause: only one of them
--  is ever allowed, and V2's defaults put both on Left Click.
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local Env = import("platform/env")
local Controls = import("engine/controls")
local Keys = import("engine/keys")
local Button = import("ui/kit/button")
local Row = import("ui/kit/row")

local ControlsWin = {}

local PAD = 18
local SHARED_OK = { pause = "unpause", unpause = "pause" }
local WAITING = "Press a key…"

function ControlsWin.define(ui)
	ui.wm:define("controls", { title = "Controls", w = 380, h = 560, minW = 320, minH = 260,
		build = function(body, win) ui.controlsWin = ControlsWin.build(ui, body, win) end })
	ui:addDockButton("controls")
end

local KeyCtl = {}
KeyCtl.__index = KeyCtl
KeyCtl.destroy = function(self) self.key:destroy(); self.clear:destroy(); K.destroy(self) end

function ControlsWin.build(ui, body, win)
	local E, c, ctx = ui.E, ui.E.controls, win.ctx
	local cw = { rows = {}, offs = {}, waiting = nil }
	local resetAll = Button.new(ctx, body, { text = "Reset all", kind = "plain", h = 22 })
	resetAll.gui.AnchorPoint, resetAll.gui.Position = Vector2.new(1, 0), UDim2.new(1, -PAD, 0, 10)
	cw.resetAll = resetAll
	local top = 40
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 0, 0, top)
	list.Size = UDim2.new(1, 0, 1, -top)
	list.ScrollBarThickness = 4
	list.Parent = body
	cw.list = list
	local lctx = {}
	for k, v in pairs(ctx) do lctx[k] = v end
	lctx.pointer = { add = function(r, z) r.clip = list; return ctx.pointer.add(r, z) end, remove = ctx.pointer.remove }
	local scrollConn = list:GetPropertyChangedSignal("CanvasPosition"):Connect(function() W.bump() end)
	cw.offs[#cw.offs + 1] = function() scrollConn:Disconnect() end

	local function stopWaiting()
		local r = cw.waiting
		cw.waiting = nil
		E.typing.rebinding = false
		if r then r.key:setText(c:get(r.ctl.key)) end
	end
	local function refresh()
		local byKey = {}
		for _, ctl in ipairs(Controls.LIST) do
			local k = c:get(ctl.key)
			if k ~= "None" then
				byKey[k] = byKey[k] or {}
				table.insert(byKey[k], ctl)
			end
		end
		for _, ctl in ipairs(Controls.LIST) do
			local r = cw.rows[ctl.key]
			local k = c:get(ctl.key)
			if cw.waiting ~= r then r.key:setText(k) end
			local others = {}
			for _, o in ipairs(byKey[k] or {}) do
				if o.key ~= ctl.key and SHARED_OK[ctl.key] ~= o.key then others[#others + 1] = o.v2 end
			end
			r.conflict = #others > 0
			if r.row.desc then W.set(r.row.desc, "Text", r.conflict and ("Also: " .. table.concat(others, ", ")) or "") end
			W.set(r.key.gui, "BackgroundColor3", r.conflict and ui.theme.c.reset2 or Color3.new(1, 1, 1))
			W.set(r.key.gui, "BackgroundTransparency", r.conflict and 0.2 or 0.88)
			r.row:setReset(k ~= ctl.default)
		end
	end
	cw.refresh = refresh

	local y = 0
	for _, ctl in ipairs(Controls.LIST) do
		local kc = K.new(lctx, KeyCtl)
		local gui = K.frame("Key", nil)
		gui.Size = UDim2.new(0, 142, 0, 24)
		kc.gui = gui
		local key = Button.new(lctx, gui, { text = c:get(ctl.key), kind = "plain", w = 110 })
		local clear = Button.new(lctx, gui, { text = "✕", kind = "plain", w = 26 })
		clear.gui.Position = UDim2.new(0, 116, 0, 0)
		kc.key, kc.clear = key, clear
		local row = Row.new(lctx, list, { name = ctl.v2, desc = " ", control = kc })
		W.set(row.desc, "Text", "")
		W.set(row.gui, "Position", UDim2.new(0, 0, 0, y))
		y = y + row.h
		local r = { row = row, key = key, clear = clear, ctl = ctl, conflict = false }
		cw.rows[ctl.key] = r
		key.onClick = function()
			if cw.swallow then return end -- (the release of the mouse press that just bound a key)
			if cw.waiting then stopWaiting() end
			cw.waiting = r
			E.typing.rebinding = true
			key:setText(WAITING)
		end
		clear.onClick = function() stopWaiting(); c:set(ctl.key, "None") end
		row.onReset = function() stopWaiting(); c:set(ctl.key, ctl.default) end
	end
	W.set(list, "CanvasSize", UDim2.new(0, 0, 0, y + 12))
	resetAll.onClick = function()
		stopWaiting()
		for _, ctl in ipairs(Controls.LIST) do c:set(ctl.key, ctl.default) end
	end
	-- the key that binds (the engine's keys are off: Typing.rebinding; the press itself stays ignored:
	-- Typing.boundInput)
	local uis = Env.svc("UserInputService")
	local conn = uis.InputBegan:Connect(function(inp)
		local r = cw.waiting
		if not r then return end
		if inp.KeyCode == Enum.KeyCode.Escape then
			E.typing.boundInput = inp
			stopWaiting()
			return
		end
		local name = Keys.fromKey[inp.KeyCode] or Keys.fromKey[inp.UserInputType]
		if not name then return end
		E.typing.boundInput = inp
		cw.waiting = nil
		E.typing.rebinding = false
		if inp.UserInputType ~= Enum.UserInputType.Keyboard then cw.swallow = inp.UserInputType end
		c:set(r.ctl.key, name)
		refresh()
	end)
	local endConn = uis.InputEnded:Connect(function(inp)
		if cw.swallow and inp.UserInputType == cw.swallow then
			task.defer(function() cw.swallow = nil end) -- (after the pointer has had this release)
		end
	end)
	cw.offs[#cw.offs + 1] = function() conn:Disconnect(); endConn:Disconnect() end
	cw.offs[#cw.offs + 1] = c:changed(function() refresh() end)
	cw.offs[#cw.offs + 1] = function() stopWaiting() end
	ui.life:own(function() for _, off in ipairs(cw.offs) do off() end end)
	refresh()
	return cw
end

return ControlsWin
