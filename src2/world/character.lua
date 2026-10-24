-- ================================================================================================
--  CHARACTER  (HappaTAS 3 world plugin, order 10): the root part's pose, velocities and humanoid state,
--  death and respawn (V2.38.16 p18_core: SyncCharacter, anchor, CharLoad, fillFrame).
--  Columns: Cframe (12), Lin (3), Ang (3) as V2 Velocity.Linear / Angular, State (u8), Died (list).
--  Velocities are taken when a frame starts (PreRender), the pose and state when it is filled (before
--  the physics step).
-- ================================================================================================
local Env = import("platform/env")
local Util = import("engine/util")

local round = Util.round
local Character = { name = "character", order = 10 }
Character.__index = Character

function Character.new(E)
	local self = setmetatable({ E = E, hum = nil, hrp = nil, model = nil, torso = nil, rootJoint = nil, charLife = nil }, Character)
	local tl = E.tl
	tl:addColumn("Cframe", "f64", 12, { key = "Cframe" })
	tl:addColumn("Lin", "f64", 3, { key = "Velocity", sub = "Linear" })
	tl:addColumn("Ang", "f64", 3, { key = "Velocity", sub = "Angular" })
	tl:addColumn("State", "u8", 1, { key = "State" })
	tl:addColumn("Died", "list", 1, { key = "Died", keep = true })
	return self
end

-- ------------------------------------------------------------------------------------------------ frames
function Character:cframeAt(tl, i)
	local x, y, z, a, b, c, d, e, f, g, h, k = tl:getN("Cframe", i)
	return CFrame.new(x, y, z, a, b, c, d, e, f, g, h, k)
end
function Character:linAt(tl, i) return Vector3.new(tl:getN("Lin", i)) end
function Character:angAt(tl, i) return Vector3.new(tl:getN("Ang", i)) end

function Character:begin(tl, i)
	local hrp = self.hrp
	local lin, ang = hrp.AssemblyLinearVelocity, hrp.AssemblyAngularVelocity
	local k = self.E.recScale
	if k ~= 1 then lin, ang = lin / k, ang / k end
	tl:setN("Lin", i, round(lin.X, 1000), round(lin.Y, 1000), round(lin.Z, 1000))
	tl:setN("Ang", i, round(ang.X, 1000), round(ang.Y, 1000), round(ang.Z, 1000))
end

function Character:fill(tl, i)
	local hrp, hum = self.hrp, self.hum
	local state = hum:GetState()
	local x, y, z, a, b, c, d, e, f, g, h, k = hrp.CFrame:GetComponents()
	tl:setN("Cframe", i, round(x, 1000), round(y, 1000), round(z, 1000), round(a, 1000), round(b, 1000), round(c, 1000),
		round(d, 1000), round(e, 1000), round(f, 1000), round(g, 1000), round(h, 1000), round(k, 1000))
	tl:set("State", i, 1, state.Value)
end

-- (after every other plugin filled the frame, like V2's fillFrame)
function Character:fillDeath(tl, i)
	local hum = self.hum
	if hum:GetState() == Enum.HumanoidStateType.Dead or hum.Health <= 0 then tl:setList("Died", i, true) end
end

-- ------------------------------------------------------------------------------------------------ the character
function Character:loaded()
	local h = self.hrp
	return self.model ~= nil and h ~= nil and h.Parent ~= nil and self.hum ~= nil
end

function Character:notDead()
	if self.E.settings:on("recordDeath") then return true end
	return self.hum ~= nil and self.hum:GetState() ~= Enum.HumanoidStateType.Dead
end

function Character:changeState(st)
	local hum = self.hum
	if hum then pcall(hum.ChangeState, hum, st) end
end

-- moves the whole character: the root moves the assembly, the torso is aligned through the root joint
-- so the limbs never trail a frame behind
function Character:sync(cf, lin, ang)
	local hrp = self.hrp
	if not hrp then return end
	hrp.CFrame = cf
	hrp.AssemblyLinearVelocity = lin
	hrp.AssemblyAngularVelocity = ang
	local torso, rj = self.torso, self.rootJoint
	if torso and torso.Parent and rj and rj.Parent then
		torso.CFrame = cf * rj.C0 * rj.Transform * rj.C1:Inverse()
	end
end

function Character:syncFrame(tl, i)
	self:sync(self:cframeAt(tl, i), self:linAt(tl, i), self:angAt(tl, i))
end

-- anchored = held still (paused); AutoRotate only while recording / idle and not anchored
function Character:anchor(value)
	if self.hrp then self.hrp.Anchored = value end
	local allowAutoRotate = (not value) and (self.E.mode ~= 3)
	if self.hum then
		local hum = self.hum
		pcall(function() hum.AutoRotate = allowAutoRotate end)
	end
	self.E.cs:shiftlockRotation(allowAutoRotate)
end

-- a jump from Running needs two Running frames before it (coyote jump)
function Character:canCoyoteJump()
	local E = self.E
	local tl, f = E.tl, E.frame
	local running = Enum.HumanoidStateType.Running.Value
	return self.hum:GetState() == Enum.HumanoidStateType.Running and f >= 2 and f <= tl:count()
		and tl:get("State", f, 1) == running and tl:get("State", f - 1, 1) == running
end

function Character:jumpedOffLadder()
	local E = self.E
	local tl, f = E.tl, E.frame
	return f >= 2 and f <= tl:count() and tl:get("State", f, 1) == Enum.HumanoidStateType.Jumping.Value
		and tl:get("State", f - 1, 1) == Enum.HumanoidStateType.Climbing.Value
end

-- ------------------------------------------------------------------------------------------------ load / respawn
function Character:load(model)
	local hum = model:WaitForChild("Humanoid", 30)
	local root = model:WaitForChild("HumanoidRootPart", 30)
	local E = self.E
	if not hum or not root or E.life.unloading then return end
	if self.charLife then self.charLife:cleanup() end
	self.charLife = E.life:scope("character")
	self.hum, self.hrp, self.model = hum, root, model
	self.torso = model:FindFirstChild("Torso")
	self.rootJoint = root:FindFirstChild("RootJoint")
	self.charLife:connect(hum.Died, function()
		if E.settings:on("recordDeath") then return end -- the recording / replay keeps going
		if E.mode == 2 and not E.paused and E.tl:count() > 0 then E.tl:removeLast() end
		if E.mode ~= 1 then E.modes:idle() end
	end)
end

function Character:start()
	local E = self.E
	local players = Env.svc("Players")
	local lp = players.LocalPlayer
	pcall(function() E.life:setProp(lp, "AutoJumpEnabled", false) end)
	local function onCharacter(model)
		task.spawn(function()
			local ok, err = pcall(self.load, self, model)
			if not ok then E.errs:report("character", err) end
		end)
		E.plugins:call("attach", model)
	end
	E.life:connect(lp.CharacterAdded, onCharacter)
	if lp.Character then onCharacter(lp.Character) end
end

return Character
