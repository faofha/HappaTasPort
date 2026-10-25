-- ================================================================================================
--  TWEEN  (HappaTAS 3 ui): the interface's own tweens. One pipeline handler (PreRender, order 200) moves
--  every running tween; it is only in the pipeline while a tween runs (an idle handler still costs a
--  resume a frame: the bench's Idle line). Curves (spec 8.4): Animations Off = no time;
--  Easing "Preset" follows Animations (Smooth: Quad Out, Snappy: Quint Out in 0.6 x the length, Bouncy:
--  Back Out); a Roblox easing style uses TweenService:GetValue; Custom is a cubic bezier (TweenService has
--  none), solved for x with Newton steps and bisection as the fallback.
-- ================================================================================================
local Env = import("platform/env")
local W = import("ui/write")

local Tween = {}
Tween.__index = Tween

local PRESET = { Smooth = { "Quad", "Out" }, Snappy = { "Quint", "Out" }, Bouncy = { "Back", "Out" } }

-- y(x) of the cubic bezier from (0, 0) to (1, 1) with handles (x1, y1), (x2, y2)
function Tween.bezier(x1, y1, x2, y2)
	local function at(a, b, t) local u = 1 - t; return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t end
	local function slope(a, b, t) local u = 1 - t; return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b) end
	return function(x)
		if x <= 0 then return 0 end
		if x >= 1 then return 1 end
		local t = x
		for _ = 1, 8 do
			local err = at(x1, x2, t) - x
			if math.abs(err) < 1e-6 then return at(y1, y2, t) end
			local d = slope(x1, x2, t)
			if math.abs(d) < 1e-6 then break end
			t = t - err / d
		end
		local lo, hi = 0, 1
		t = x
		for _ = 1, 30 do
			local v = at(x1, x2, t)
			if math.abs(v - x) < 1e-6 then break end
			if v < x then lo = t else hi = t end
			t = (lo + hi) / 2
		end
		return at(y1, y2, t)
	end
end

-- the curve the settings ask for: f(alpha 0..1) -> progress
function Tween.curve(settings)
	local easing = settings:get("easing")
	if easing == "Custom" then
		return Tween.bezier(settings:get("bezierX1"), settings:get("bezierY1"), settings:get("bezierX2"), settings:get("bezierY2"))
	end
	local style, dir
	if easing == "Preset" then
		local p = PRESET[settings:get("animations")]
		if not p then return function(a) return a end end
		style, dir = p[1], p[2]
	else
		style, dir = easing, settings:get("easingDirection")
	end
	local ts = Env.svc("TweenService")
	local es, ed = Enum.EasingStyle[style], Enum.EasingDirection[dir]
	return function(a)
		local ok, v = pcall(ts.GetValue, ts, a, es, ed)
		if ok and type(v) == "number" then return v end
		return a
	end
end

-- seconds a move takes (Off: none)
function Tween.length(settings)
	local anim = settings:get("animations")
	if anim == "Off" then return 0 end
	local len = settings:get("animationLength")
	if anim == "Snappy" and settings:get("easing") == "Preset" then len = len * 0.6 end
	return len
end

function Tween.new(E, life)
	local self = setmetatable({ E = E, list = {}, byInst = setmetatable({}, { __mode = "k" }), off = nil }, Tween)
	life:own(function() self:idle() end)
	return self
end

local function lerp(a, b, v)
	local ta = typeof(a)
	if ta == "number" then return a + (b - a) * v end
	if ta == "Color3" or ta == "UDim2" or ta == "Vector2" then return a:Lerp(b, v) end
	return (v >= 1) and b or a
end

-- moves inst's props to their goals; returns a handle (opts.length / opts.curve override the settings)
function Tween:play(inst, props, opts)
	opts = opts or {}
	local old = self.byInst[inst]
	if old then self:cancel(old) end
	local s = self.E.settings
	local len = opts.length or Tween.length(s)
	local h = { inst = inst, from = {}, to = props, t0 = os.clock(), len = len, curve = opts.curve or Tween.curve(s) }
	if len <= 0 then
		for k, v in pairs(props) do W.set(inst, k, v) end
		return h
	end
	for k in pairs(props) do h.from[k] = inst[k] end
	self.list[#self.list + 1] = h
	self.byInst[inst] = h
	if not self.off then self.off = self.E.pipe:add("PreRender", 200, "ui.tween", function() self:step() end, "ui") end
	return h
end

function Tween:cancel(h)
	local i = table.find(self.list, h)
	if i then table.remove(self.list, i) end
	if self.byInst[h.inst] == h then self.byInst[h.inst] = nil end
end

function Tween:running() return #self.list end

-- out of the pipeline (nothing runs)
function Tween:idle()
	if self.off then self.off(); self.off = nil end
end

local function finish(self, h)
	for k, v in pairs(h.to) do W.set(h.inst, k, v) end
	self:cancel(h)
end

function Tween:finishAll()
	for _, h in ipairs(table.clone(self.list)) do finish(self, h) end
end

function Tween:step()
	local list = self.list
	if #list == 0 then self:idle() return end
	local now = os.clock()
	for _, h in ipairs(table.clone(list)) do
		local a = (now - h.t0) / h.len
		if a >= 1 or not h.inst.Parent then
			finish(self, h)
		else
			local v = h.curve(a)
			for k, goal in pairs(h.to) do W.set(h.inst, k, lerp(h.from[k], goal, v)) end
		end
	end
end

return Tween
