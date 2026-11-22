-- ================================================================================================
--  COMPACT HOST  (HappaTAS 3 ui, V3.1): shows one of the New interface's windows inside a Compact page or side
--  panel. A window builder (XWin.build(ui, body, win)) is called with a stand-in window: { ctx, body, open, min,
--  hosted = true, compact = true }, its pointer rects clipped to the frame and grouped with the Compact window.
--  Hosting never writes ui.<x>Win: the New interface's own copy (if it was built) stays what the rest of the
--  code talks to. setOpen(on) sets win.open and tells listeners through ui.wm:fire(id, on), as opening the
--  window would.
-- ================================================================================================
local K = import("ui/kit/base")

local Host = {}
Host.__index = Host

-- compact: the Compact interface; id: the window's id; build: XWin.build; parent: where its frame goes;
-- opts.narrow: the builder may lay itself out for a narrow panel; opts.group: the frame its rects belong to (a
-- side panel outside the Compact window)
function Host.new(compact, id, build, parent, opts)
	opts = opts or {}
	local self = setmetatable({ compact = compact, id = id }, Host)
	local frame = K.frame("Host_" .. id, parent)
	frame.Size = UDim2.new(1, 0, 1, 0)
	self.frame = frame
	local base = compact.ctx
	local ctx = {}
	for k, v in pairs(base) do ctx[k] = v end
	ctx.pointer = {
		add = function(r, z)
			r.clip = r.clip or frame
			if opts.group then r.group = r.group or opts.group end
			return base.pointer.add(r, z)
		end,
		remove = base.pointer.remove,
	}
	self.win = { id = id, ctx = ctx, body = frame, open = false, min = false, hosted = true, compact = true,
		narrow = opts.narrow == true }
	ctx.win = self.win
	local ok, obj = pcall(build, compact.ui, frame, self.win)
	if ok then
		self.obj = obj
	else
		compact.E.errs:report("compact " .. id, obj)
	end
	return self
end

function Host:setOpen(on)
	on = on == true
	if self.win.open == on then return end
	self.win.open = on
	self.compact.ui.wm:fire(self.id, on)
end

return Host
