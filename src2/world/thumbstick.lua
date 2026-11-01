-- ================================================================================================
--  THUMBSTICK  (HappaTAS 3 world plugin, order 55; spec 2 "thumbstick replay"): Roblox's touch controls
--  recorded per frame and put back while testing, on touch devices only (V2.38.17 p18_core.lua ReadMobile /
--  ReplayMobile). PlayerGui.TouchGui.TouchControlFrame: the jump button's look (pressed or not), the static
--  thumbstick's stick, and the dynamic thumbstick's start, end and middle images (position, transparency,
--  size). Column "Mobile" (V2's key: a V2 run's data loads into it; Run.registerCarry no longer keeps it as
--  "v2Mobile"), V2's table shape { Jumping, JoystickX, JoystickY, Dynamic = { Start, End, Middles } }.
-- ================================================================================================
local Env = import("platform/env")
local Util = import("engine/util")

local Thumbstick = { name = "thumbstick", order = 55 }
Thumbstick.__index = Thumbstick

local FIND_EVERY = 2 -- (seconds between looks for the touch controls, as V2's touchFrame)
local r = Util.round

function Thumbstick.new(E)
	local self = setmetatable({ E = E, uis = Env.svc("UserInputService"), players = Env.svc("Players"), tcf = nil, found = -math.huge }, Thumbstick)
	self.mobile = self:touch()
	E.tl:addColumn("Mobile", "list", 1, { key = "Mobile", keep = true })
	return self
end

-- the touch controls' frame (looked up again at most every FIND_EVERY s)
function Thumbstick:frame()
	local now = os.clock()
	if self.tcf and self.tcf.Parent and now - self.found < FIND_EVERY then return self.tcf end
	self.found = now
	local lp = self.players and self.players.LocalPlayer
	local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
	local tg = pg and pg:FindFirstChild("TouchGui")
	self.tcf = tg and tg:FindFirstChild("TouchControlFrame")
	return self.tcf
end

function Thumbstick:touch() return self.uis ~= nil and self.uis.TouchEnabled == true end

-- this frame's controls (V2's ReadMobile)
function Thumbstick:read()
	local ok, res = pcall(function()
		local tcf = self:frame()
		if not tcf then return nil end
		local jb = tcf:FindFirstChild("JumpButton")
		local m = { Jumping = (jb and jb.ImageRectOffset.X == 146) and 1 or 0 }
		local tf = tcf:FindFirstChild("ThumbstickFrame")
		local stick = tf and tf.Visible and tf:FindFirstChild("StickImage")
		if stick then
			m.JoystickX = r(stick.Position.X.Offset, 1)
			m.JoystickY = r(stick.Position.Y.Offset, 1)
		end
		local dtf = tcf:FindFirstChild("DynamicThumbstickFrame")
		if dtf and dtf.Visible then
			local sImg, eImg = dtf:FindFirstChild("ThumbstickStart"), dtf:FindFirstChild("ThumbstickEnd")
			if sImg and eImg and sImg.Visible then
				local mids = {}
				for _, ch in ipairs(dtf:GetChildren()) do
					if ch.Name == "ThumbstickMiddle" and ch:IsA("ImageLabel") and ch.Visible then
						local szX = ch.Size.X.Offset > 0 and ch.Size.X.Offset or ch.AbsoluteSize.X
						local szY = ch.Size.Y.Offset > 0 and ch.Size.Y.Offset or ch.AbsoluteSize.Y
						mids[#mids + 1] = { r(ch.Position.X.Offset, 1), r(ch.Position.Y.Offset, 1), r(ch.ImageTransparency, 100), r(szX, 1), r(szY, 1) }
					end
				end
				m.Dynamic = {
					Start = { r(sImg.Position.X.Offset, 1), r(sImg.Position.Y.Offset, 1), r(sImg.ImageTransparency, 100) },
					End = { r(eImg.Position.X.Offset, 1), r(eImg.Position.Y.Offset, 1), r(eImg.ImageTransparency, 100) },
					Middles = mids,
				}
			end
		end
		return m
	end)
	if ok and res then return res end
	return nil
end

-- the controls as recorded (V2's ReplayMobile)
function Thumbstick:replay(mob)
	pcall(function()
		local tcf = self:frame()
		if not tcf then return end
		local jb = tcf:FindFirstChild("JumpButton")
		if jb then jb.ImageRectOffset = Vector2.new((mob.Jumping or 0) * 145 + 1, 146) end
		if mob.JoystickX and mob.JoystickY then
			local tf = tcf:FindFirstChild("ThumbstickFrame")
			local stick = tf and tf:FindFirstChild("StickImage")
			if stick then stick.Position = UDim2.new(0, mob.JoystickX, 0, mob.JoystickY) end
		end
		local dtf = tcf:FindFirstChild("DynamicThumbstickFrame")
		if not dtf then return end
		local dyn = mob.Dynamic
		local sImg, eImg = dtf:FindFirstChild("ThumbstickStart"), dtf:FindFirstChild("ThumbstickEnd")
		local mids = {}
		for _, ch in ipairs(dtf:GetChildren()) do
			if ch.Name == "ThumbstickMiddle" and ch:IsA("ImageLabel") then mids[#mids + 1] = ch end
		end
		if dyn and dyn.Start and sImg and eImg then
			sImg.Position = UDim2.new(0, dyn.Start[1], 0, dyn.Start[2])
			sImg.ImageTransparency = dyn.Start[3]
			sImg.Visible = true
			eImg.Position = UDim2.new(0, dyn.End[1], 0, dyn.End[2])
			eImg.ImageTransparency = dyn.End[3]
			eImg.Visible = true
			local list = dyn.Middles or {}
			for i, m in ipairs(list) do
				local img = mids[i]
				if img then
					img.Position = UDim2.new(0, m[1], 0, m[2])
					img.ImageTransparency = m[3]
					if m[4] and m[5] and m[4] > 0 and m[5] > 0 then img.Size = UDim2.new(0, m[4], 0, m[5]) end
					img.Visible = true
				end
			end
			for i = #list + 1, #mids do mids[i].Visible = false end
		else
			if sImg then sImg.Visible = false end
			if eImg then eImg.Visible = false end
			for _, img in ipairs(mids) do img.Visible = false end
		end
	end)
end

-- recording (touch devices only: decided once when the script starts, as V2's C.IsMobile)
function Thumbstick:fill(tl, i)
	if not self.mobile then return end
	local m = self:read()
	if m then tl:setList("Mobile", i, m) end
end

-- Test (touch devices only; TouchEnabled is read only for a frame with thumbstick data, as V2 did)
function Thumbstick:onPlayTo(tl, f)
	if f < 1 or f > tl:count() then return end
	local mob = tl:getList("Mobile", f)
	if type(mob) == "table" and self:touch() then self:replay(mob) end
end

return Thumbstick
