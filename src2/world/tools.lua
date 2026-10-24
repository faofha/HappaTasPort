-- ================================================================================================
--  TOOLS  (HappaTAS 3 world plugin, order 50): equip / unequip / activate / deactivate (V2.38.16
--  p15_tools). Recording saves the events per frame (column Tools: { { Action, Name } }). Replay is
--  state based: the key and mouse replay usually reproduce tool actions by themselves, so HappaTAS only
--  steps in when the equipped tool still differs from the recording 4 frames later (no double toggles),
--  and only clicks a tool itself when mouse click replay is off.
-- ================================================================================================
local Env = import("platform/env")

local Tools = { name = "tools", order = 50 }
Tools.__index = Tools

local FIX_AFTER = 4
local MAX_PENDING = 64

function Tools.new(E)
	local self = setmetatable({ E = E, pending = {}, toolConns = {}, charLife = nil, desired = nil, mismatch = 0 }, Tools)
	E.tl:addColumn("Tools", "list", 1, { key = "Tools", keep = true })
	E.life:own(function()
		for _, list in pairs(self.toolConns) do for _, c in ipairs(list) do pcall(function() c:Disconnect() end) end end
		self.toolConns = {}
	end)
	return self
end

function Tools:push(action, name)
	if not self.E.settings:on("recordTools") then return end
	local p = self.pending
	p[#p + 1] = { Action = action, Name = name }
	if #p > MAX_PENDING then table.remove(p, 1) end
end

function Tools:hookTool(tool)
	if not tool:IsA("Tool") or self.toolConns[tool] then return end
	self.toolConns[tool] = {
		tool.Activated:Connect(function() self:push("Activate", tool.Name) end),
		tool.Deactivated:Connect(function() self:push("Deactivate", tool.Name) end),
		tool.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				local list = self.toolConns[tool]
				if list then for _, c in ipairs(list) do c:Disconnect() end end
				self.toolConns[tool] = nil
			end
		end),
	}
end

-- a new character: its tools and the backpack's are watched
function Tools:attach(char)
	if self.charLife then self.charLife:cleanup() end
	if not char then return end
	local life = self.E.life:scope("tools")
	self.charLife = life
	for _, ch in ipairs(char:GetChildren()) do if ch:IsA("Tool") then self:hookTool(ch) end end
	local bp = Env.svc("Players").LocalPlayer:FindFirstChildOfClass("Backpack")
	if bp then
		for _, ch in ipairs(bp:GetChildren()) do if ch:IsA("Tool") then self:hookTool(ch) end end
		life:connect(bp.ChildAdded, function(ch) if ch:IsA("Tool") then self:hookTool(ch) end end)
	end
	life:connect(char.ChildAdded, function(ch)
		if ch:IsA("Tool") then
			self:hookTool(ch)
			self:push("Equip", ch.Name)
		end
	end)
	life:connect(char.ChildRemoved, function(ch)
		if ch:IsA("Tool") then self:push("Unequip", ch.Name) end
	end)
end

function Tools:take()
	if #self.pending == 0 then return nil end
	local out = self.pending
	self.pending = {}
	return out
end
function Tools:clear() self.pending = {} end

function Tools:fill(tl, i) tl:setList("Tools", i, self:take()) end

local function equippedName(char)
	local tool = char and char:FindFirstChildOfClass("Tool")
	return tool and tool.Name or false
end

function Tools:replayBegin(tl, f, char)
	self.mismatch = 0
	self.desired = nil
	if not self.E.settings:on("recordTools") then return end
	local any = false
	local state = equippedName(char)
	for i = 1, math.min(f, tl:count()) do
		local list = tl:getList("Tools", i)
		if list then
			for _, e in ipairs(list) do
				any = true
				if e.Action == "Equip" then state = e.Name elseif e.Action == "Unequip" then state = false end
			end
		end
	end
	if any then self.desired = state end
end

function Tools:replayFrame(tl, i, char)
	local events = tl:getList("Tools", i)
	local s = self.E.settings
	if not events or not s:on("recordTools") then return end
	local clicksReplayed = self.E.inputs.available.clicks and s:on("replayMouseClicks")
	for _, e in ipairs(events) do
		if e.Action == "Equip" then
			self.desired = e.Name
		elseif e.Action == "Unequip" then
			self.desired = false
		elseif not clicksReplayed and char then
			local tool = char:FindFirstChild(e.Name)
			if tool and tool:IsA("Tool") then
				if e.Action == "Activate" then pcall(function() tool:Activate() end)
				else pcall(function() tool:Deactivate() end) end
			end
		end
	end
end

function Tools:step(char, humanoid)
	local desired = self.desired
	if desired == nil or not char or not humanoid then return end
	local cur = equippedName(char)
	if cur == desired then self.mismatch = 0 return end
	self.mismatch = self.mismatch + 1
	if self.mismatch < FIX_AFTER then return end
	self.mismatch = 0
	if desired == false then
		pcall(function() humanoid:UnequipTools() end)
	else
		local bp = Env.svc("Players").LocalPlayer:FindFirstChildOfClass("Backpack")
		local tool = (bp and bp:FindFirstChild(desired)) or char:FindFirstChild(desired)
		if tool and tool:IsA("Tool") then
			pcall(function() humanoid:EquipTool(tool) end)
		else
			self.desired = nil -- the tool isn't there any more: stop trying
			self.E.modes:status("Tool '" .. tostring(desired) .. "' missing, skipped")
		end
	end
end

function Tools:replayEnd()
	self.desired = nil
	self.mismatch = 0
end

return Tools
