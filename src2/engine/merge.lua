-- ================================================================================================
--  MERGE  (HappaTAS 3 engine, plugin order 95): joins two runs (V2.38.16 p18_core: SetTAS with a merge,
--  the merge hitboxes, the Merge Stats button). The run before keeps its last frame as the start of a new
--  recording; the player records from there to the other run's first frame (red box = where the run
--  before ends, green box = where the run after starts). Close enough (16 x the mean of the two frame
--  times, in studs) completes the merge, else the click cancels it and the old run comes back.
--  begin(frames, where): frames = the other run (V2 frame tables); where = "after" (it comes after the
--  current run) or "before".
-- ================================================================================================
local Util = import("engine/util")

local round = Util.round
local Merge = { name = "merge", order = 95 }
Merge.__index = Merge

function Merge.new(E)
	local self = setmetatable({ E = E, before = nil, after = nil, old = nil, hitboxes = {}, reqDist = nil, goal = nil }, Merge)
	E.mergeCanComplete = false
	return self
end

-- keys held at the end of frames 1..upTo of a V2 frame list
local function heldAt(frames, upTo)
	local set = {}
	for i = 1, math.min(upTo, #frames) do
		local ev = frames[i].Input
		if ev then
			for k = 1, #ev do
				local e = ev[k]
				if e < 5000 then
					if e > 0 then set[e] = true else set[-e] = nil end
				end
			end
		end
	end
	return set
end

function Merge:destroyHitboxes()
	for _, h in ipairs(self.hitboxes) do pcall(function() h:Destroy() end) end
	self.hitboxes = {}
end

function Merge:createHitboxes()
	self:destroyHitboxes()
	local mb, ma = self.before, self.after
	for _, name in ipairs({ "startHitbox", "endHitbox" }) do
		local h = Instance.new("Part")
		h.Name = name
		local c = (name == "startHitbox") and mb[#mb].Cframe or ma[1].Cframe
		h.CFrame = CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
		h.Anchored = true
		h.Color = (name == "startHitbox") and Color3.fromRGB(205, 10, 0) or Color3.fromRGB(0, 185, 8)
		h.Transparency = 0.5
		h.CanCollide, h.CanQuery, h.CanTouch = false, false, false
		h.Size = Vector3.new(2.1, 2.1, 1.1)
		h.TopSurface = Enum.SurfaceType.Smooth
		h.Parent = workspace.CurrentCamera or workspace
		self.hitboxes[#self.hitboxes + 1] = self.E.life:own(h)
	end
end

function Merge:startMerge(frames, where)
	local E = self.E
	local current = E.tl:toV2All()
	self.old = current
	if where == "after" then self.before, self.after = current, frames
	else self.before, self.after = frames, current end
	local mb, ma = self.before, self.after
	if not mb or #mb == 0 or not ma or #ma == 0 then
		E.modes:status("Cannot merge: one of the TAS runs is empty", true)
		E.merge = false
		return false
	end
	if not mb[#mb].Cframe or not ma[1].Cframe then
		E.modes:status("Cannot merge: missing frame data", true)
		E.merge = false
		return false
	end
	E.tl:replaceFromV2({ mb[#mb] })
	E.plugins:call("onDataChanged")
	E.mergeBaseHeld = heldAt(mb, #mb - 1)
	E.merge = true
	E.modes:create()
	self:createHitboxes()
	local t1 = mb[#mb].FrameTime or 0.016
	local t2 = ma[1].FrameTime or 0.016
	self.reqDist = 16 * (t1 + t2) / 2
	self.goal = ma[1].Cframe
	return true
end

-- each Create frame (V2's merge stats): close enough to the other run's start?
function Merge:onCreateStats(tl, f)
	local E = self.E
	if not E.merge or not self.goal or f < 1 or f > tl:count() or not tl:isFilled(f) then return end
	local x, y, z = tl:get("Cframe", f, 1), tl:get("Cframe", f, 2), tl:get("Cframe", f, 3)
	local g = self.goal
	local dist = (Vector3.new(x, y, z) - Vector3.new(g[1], g[2], g[3])).Magnitude
	E.mergeCanComplete = dist < self.reqDist
	E.mergeDistance = dist
end

-- the merge button: completes when close enough, else cancels
function Merge:finishMerge()
	local E = self.E
	local tl = E.tl
	if E.mergeCanComplete then
		local mb, ma = self.before, self.after
		local recorded = tl:toV2All() -- (frame 1 = the run before's last frame, as the recording left it)
		E.merge = false
		E.modes:idle()
		self:destroyHitboxes()
		local newData = {}
		for i = 1, #mb - 1 do newData[i] = mb[i] end
		newData[#newData + 1] = recorded[1]
		for i = 2, #recorded do newData[#newData + 1] = recorded[i] end
		for i = 1, #ma do newData[#newData + 1] = ma[i] end
		for i = math.max(2, #mb), #newData do
			newData[i].TotalTime = round(newData[i].FrameTime + newData[i - 1].TotalTime, 1000000)
		end
		self.old, self.before, self.after, E.mergeBaseHeld = nil, nil, nil, nil
		tl:replaceFromV2(newData)
		E.plugins:call("onDataChanged")
		E.modes:status("Merge Complete")
	else
		E.merge = false
		E.modes:idle()
		self:destroyHitboxes()
		tl:replaceFromV2(self.old or {})
		E.plugins:call("onDataChanged")
		self.old, self.before, self.after, E.mergeBaseHeld = nil, nil, nil, nil
		E.modes:status("Merge Cancelled")
	end
	E.mergeCanComplete = false
	E.modes:publish()
end

function Merge:onUnload() self:destroyHitboxes() end

return Merge
