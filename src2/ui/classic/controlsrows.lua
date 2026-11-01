-- ================================================================================================
--  CLASSIC CONTROLS ROWS  (HappaTAS 3 ui, spec 8.5): the classic Controls tab, one V2.38.17 row (the tree's
--  "Control" template) per control. A click on a key waits for the next key or mouse button ("Press Any
--  Key"): the engine's keys are off meanwhile (Typing.rebinding), the press that binds never runs a control
--  (Typing.boundInput), Esc cancels. The rows follow E.controls, so a key bound in the new interface shows
--  here at once.
-- ================================================================================================
local Env = import("platform/env")
local Controls = import("engine/controls")
local Keys = import("engine/keys")
local ClassicTree = import("ui/classic/tree")
local ClassicBuild = import("ui/classic/build")

local ControlsRows = {}

local WAITING = "Press Any Key"
local ROW_H = 30
local MOUSE = { [Enum.UserInputType.MouseButton1] = true, [Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true }

-- every row into classic's Controls list; returns { [key] = { frame, label, key, ctl } } and sets
-- classic.stopWaiting (ends a wait: the interface switch calls it)
function ControlsRows.build(classic)
	local E, life = classic.E, classic.ui.life
	local c = E.controls
	local list = classic.byPath["MainMenu.ControlsFrame.List"]
	local rows, waiting, since = {}, nil, nil
	local function stop()
		local r = waiting
		waiting = nil
		E.typing.rebinding = false
		if r then r.key.Text = c:get(r.ctl.key) end
	end
	classic.stopWaiting = stop
	for i, ctl in ipairs(Controls.LIST) do
		local f = ClassicBuild.node(ClassicTree.TEMPLATES.Control, ClassicTree.STYLES)
		f.Name = ctl.key
		f.LayoutOrder = i
		f.N.Text = ctl.v2
		f.Key.Text = c:get(ctl.key)
		f.Parent = list
		local r = { frame = f, label = f.N, key = f.Key, ctl = ctl }
		rows[ctl.key] = r
		life:connect(f.Key.MouseButton1Down, function()
			if waiting then stop() end
			waiting, since = r, E.pipe and E.pipe.frame or 0
			E.typing.rebinding = true
			f.Key.Text = WAITING
		end)
	end
	local uis = Env.svc("UserInputService")
	life:connect(uis.InputBegan, function(inp)
		local r = waiting
		if not r then return end
		-- (the mouse press on the key itself: V2 waited a frame before listening)
		if MOUSE[inp.UserInputType] and E.pipe and E.pipe.frame == since then return end
		if inp.KeyCode == Enum.KeyCode.Escape then
			E.typing.boundInput = inp
			stop()
			return
		end
		local name = Keys.fromKey[inp.KeyCode] or Keys.fromKey[inp.UserInputType]
		if not name then return end
		E.typing.boundInput = inp
		waiting = nil
		E.typing.rebinding = false
		c:set(r.ctl.key, name)
		r.key.Text = c:get(r.ctl.key)
	end)
	classic.offs[#classic.offs + 1] = c:changed(function()
		for _, r in pairs(rows) do
			if r ~= waiting then r.key.Text = c:get(r.ctl.key) end
		end
	end)
	classic.offs[#classic.offs + 1] = stop
	list.Size = UDim2.new(0, 360, 0, #Controls.LIST * ROW_H)
	classic.byPath["MainMenu.ControlsFrame"].CanvasSize = UDim2.new(0, 0, 0, #Controls.LIST * ROW_H + 60)
	return rows
end

return ControlsRows
