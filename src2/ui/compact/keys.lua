-- ================================================================================================
--  TASABILITY KEYS  (HappaTAS 3 ui, V3.1): the KEYS list on the Tasability interface's CONTROLS page: a key box
--  (ui/compact/parts) per control in engine/controls order. A click waits for a key (ui/rebind: the engine's keys
--  are off meanwhile, Esc cancels, Backspace and Delete bind like any key), × clears it to None, Reset all puts
--  every default back. Two controls on one key (except Pause / Unpause, which V2's defaults share) are marked, and
--  hovering one says "Also: <the other>" in the line under the list.
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local P = import("ui/compact/parts")
local Controls = import("engine/controls")
local Rebind = import("ui/rebind")

local TKeys = {}
TKeys.__index = TKeys

local ROW, GAP, HOVER = 22, 4, 16
local SHARED_OK = { pause = "unpause", unpause = "pause" }

-- the list's height for this many controls (rows, Reset all, the hover line)
function TKeys.height() return #Controls.LIST * (ROW + GAP) + ROW + GAP + HOVER end

function TKeys.build(cp, parent, ctx)
	local ui = cp.ui
	ctx = ctx or cp.ctx
	local E = ui.E
	local c = E.controls
	local self = setmetatable({ cp = cp, E = E, rows = {}, also = {}, parts = {}, offs = {} }, TKeys)
	local rb = Rebind.new(E, ui.life)
	self.rebind = rb
	local hover = K.text("TextLabel", "Hover", parent)
	hover.TextXAlignment = Enum.TextXAlignment.Left
	hover.TextTruncate = Enum.TextTruncate.AtEnd
	hover.Text = ""
	self.hover = hover
	local y = 0
	for _, ctl in ipairs(Controls.LIST) do
		local key = ctl.key
		local kb
		kb = P.keyBox(ctx, parent, ctl.v2, {
			onHover = function(on)
				if on then hover.Text = self.also[key] or ""
				elseif hover.Text == (self.also[key] or "") then hover.Text = "" end
			end,
			onClick = function()
				if rb.swallow then return end -- (the release of the mouse press that just bound a key)
				rb:start(key, function() kb:setWaiting(false); self:refresh() end)
				kb:setWaiting(true)
			end,
			onClear = function() rb:stop(); c:set(key, "None") end,
		})
		kb.gui.Position = UDim2.new(0, 0, 0, y)
		y = y + ROW + GAP
		self.rows[key] = kb
		self.parts[#self.parts + 1] = kb
	end
	local reset = P.button(ctx, parent, "Reset all", { onClick = function()
		rb:stop()
		for _, ctl in ipairs(Controls.LIST) do c:set(ctl.key, ctl.default) end
	end })
	reset.gui.Position = UDim2.new(0, 0, 0, y)
	self.resetAll = reset
	self.parts[#self.parts + 1] = reset
	hover.Position = UDim2.new(0, 2, 0, y + ROW + GAP)
	hover.Size = UDim2.new(1, -4, 0, HOVER)
	local function paint()
		local th = ui.theme
		W.set(hover, "FontFace", th.font("text"))
		W.set(hover, "TextSize", th.size(10.5))
		W.set(hover, "TextColor3", th.c.text2)
	end
	paint()
	self.offs[#self.offs + 1] = ui.theme:changed(paint)
	self.offs[#self.offs + 1] = c:changed(function() self:refresh() end)
	self:refresh()
	return self
end

-- every key shown, conflicts marked
function TKeys:refresh()
	local c = self.E.controls
	local byKey = {}
	for _, ctl in ipairs(Controls.LIST) do
		local k = c:get(ctl.key)
		if k ~= "None" then
			byKey[k] = byKey[k] or {}
			table.insert(byKey[k], ctl)
		end
	end
	for _, ctl in ipairs(Controls.LIST) do
		local kb = self.rows[ctl.key]
		local k = c:get(ctl.key)
		kb:set(k)
		local others = {}
		for _, o in ipairs(byKey[k] or {}) do
			if o.key ~= ctl.key and SHARED_OK[ctl.key] ~= o.key then others[#others + 1] = o.v2 end
		end
		kb.conflict = #others > 0
		kb:setConflict(kb.conflict)
		self.also[ctl.key] = (#others > 0) and ("Also: " .. table.concat(others, ", ")) or nil
	end
end

function TKeys:stopWaiting() self.rebind:stop() end

function TKeys:destroy()
	self.rebind:destroy()
	for _, off in ipairs(self.offs) do pcall(off) end
	self.offs = {}
	for _, p in ipairs(self.parts) do pcall(function() p:destroy() end) end
	self.parts = {}
end

return TKeys
