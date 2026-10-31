-- ================================================================================================
--  LAYOUT  (HappaTAS 3 ui): the interface places its children itself (no UIListLayout / AutomaticSize:
--  exact positions in the mock, no layout pass in Roblox). vstack / hstack set Positions only, through
--  W.set; sizes are their owners'. textWidth measures with one hidden TextLabel (cached) that lives at the
--  interface's top (Layout.probeParent, set by the app), never inside a control.
-- ================================================================================================
local W = import("ui/write")

local Layout = {}

-- items = { { gui, h } }: top to bottom from opts.pad (0), opts.gap (0) apart, at x = opts.x (0); hidden
-- items are skipped. Returns the height used (with the bottom pad).
function Layout.vstack(items, opts)
	opts = opts or {}
	local y, gap, x = opts.pad or 0, opts.gap or 0, opts.x or 0
	local first = true
	for _, it in ipairs(items) do
		if it.gui.Visible then
			if not first then y = y + gap end
			first = false
			W.set(it.gui, "Position", UDim2.new(0, x, 0, y))
			y = y + it.h
		end
	end
	return y + (opts.pad or 0)
end

-- items = { { gui, w } }: left to right from opts.pad, opts.gap apart, at y = opts.y; opts.right = true lays
-- them out from the parent's right edge leftwards (the last item rightmost). Returns the width used.
function Layout.hstack(items, opts)
	opts = opts or {}
	local gap, y, pad = opts.gap or 0, opts.y or 0, opts.pad or 0
	local x = pad
	if opts.right then
		for i = #items, 1, -1 do
			local it = items[i]
			if it.gui.Visible then
				x = x + it.w
				W.set(it.gui, "Position", UDim2.new(1, -x, 0, y))
				x = x + gap
			end
		end
		return x - gap + pad
	end
	local first = true
	for _, it in ipairs(items) do
		if it.gui.Visible then
			if not first then x = x + gap end
			first = false
			W.set(it.gui, "Position", UDim2.new(0, x, 0, y))
			x = x + it.w
		end
	end
	return x + pad
end

local cache = {}
local probe = nil
Layout.probeParent = nil
-- the width text takes in font (a Font) at size, measured once
function Layout.textWidth(text, font, size, parent)
	local key = tostring(font.Family) .. "|" .. tostring(font.Weight) .. "|" .. size .. "|" .. text
	local w = cache[key]
	if w then return w end
	if not (probe and probe.Parent) then
		probe = Instance.new("TextLabel")
		probe.Name = "Measure"
		probe.Visible = false
		probe.BackgroundTransparency = 1
		probe.Size = UDim2.new(0, 10000, 0, 100)
		probe.Parent = Layout.probeParent or parent
	end
	probe.FontFace, probe.TextSize, probe.Text = font, size, text
	w = math.ceil(probe.TextBounds.X)
	probe.Text = "" -- (it holds no text the player could read or a search could find)
	cache[key] = w
	return w
end

return Layout
