-- ================================================================================================
--  TOOLS  (equip / unequip / activate / deactivate)
--  Recording saves the events per frame. Replay is state based: the key and mouse replay usually
--  reproduce tool actions by themselves, so HappaTAS only steps in when the equipped tool still
--  differs from the recording a few frames later (no double toggles), and only clicks a tool itself
--  when mouse click replay is off.
-- ================================================================================================
do
	local T = ToolSync
	local pending = {}
	local toolConns = {}
	local charConns = {}
	local desired = nil   -- name of the tool that should be equipped, false = none, nil = not replaying
	local mismatch = 0
	local FIX_AFTER = 4

	local function push(action, name)
		if not Settings.On("Record Tool Actions") then return end
		pending[#pending + 1] = { Action = action, Name = name }
		if #pending > 64 then table.remove(pending, 1) end
	end

	local function hookTool(tool)
		if not tool:IsA("Tool") or toolConns[tool] then return end
		toolConns[tool] = {
			tool.Activated:Connect(function() push("Activate", tool.Name) end),
			tool.Deactivated:Connect(function() push("Deactivate", tool.Name) end),
			tool.AncestryChanged:Connect(function(_, parent)
				if parent == nil then
					local list = toolConns[tool]
					if list then for _, c in ipairs(list) do c:Disconnect() end end
					toolConns[tool] = nil
				end
			end),
		}
	end

	local function clearChar()
		for _, c in ipairs(charConns) do pcall(function() c:Disconnect() end) end
		charConns = {}
	end

	function T.AttachCharacter(char)
		clearChar()
		if not char then return end
		for _, ch in ipairs(char:GetChildren()) do if ch:IsA("Tool") then hookTool(ch) end end
		local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
		if bp then
			for _, ch in ipairs(bp:GetChildren()) do if ch:IsA("Tool") then hookTool(ch) end end
			charConns[#charConns + 1] = bp.ChildAdded:Connect(function(ch) if ch:IsA("Tool") then hookTool(ch) end end)
		end
		charConns[#charConns + 1] = char.ChildAdded:Connect(function(ch)
			if ch:IsA("Tool") then
				hookTool(ch)
				push("Equip", ch.Name)
			end
		end)
		charConns[#charConns + 1] = char.ChildRemoved:Connect(function(ch)
			if ch:IsA("Tool") then push("Unequip", ch.Name) end
		end)
	end

	function T.Take()
		if #pending == 0 then return nil end
		local out = pending
		pending = {}
		return out
	end
	function T.Clear() pending = {} end

	local function equippedName(char)
		local tool = char and char:FindFirstChildOfClass("Tool")
		return tool and tool.Name or false
	end

	function T.ReplayBegin(data, f, char)
		mismatch = 0
		desired = nil
		if not Settings.On("Record Tool Actions") then return end
		local any = false
		local state = equippedName(char)
		for i = 1, math.min(f, #data) do
			local list = data[i].Tools
			if list then
				for _, e in ipairs(list) do
					any = true
					if e.Action == "Equip" then state = e.Name elseif e.Action == "Unequip" then state = false end
				end
			end
		end
		if any then desired = state end
	end

	function T.ReplayFrame(events, char)
		if not events or not Settings.On("Record Tool Actions") then return end
		local clicksReplayed = InputSys.Available.Clicks and Settings.On("Replay Mouse Clicks")
		for _, e in ipairs(events) do
			if e.Action == "Equip" then
				desired = e.Name
			elseif e.Action == "Unequip" then
				desired = false
			elseif not clicksReplayed and char then
				local tool = char:FindFirstChild(e.Name)
				if tool and tool:IsA("Tool") then
					if e.Action == "Activate" then pcall(function() tool:Activate() end)
					else pcall(function() tool:Deactivate() end) end
				end
			end
		end
	end

	function T.Step(char, humanoid)
		if desired == nil or not char or not humanoid then return end
		local cur = equippedName(char)
		if cur == desired then mismatch = 0 return end
		mismatch = mismatch + 1
		if mismatch < FIX_AFTER then return end
		mismatch = 0
		if desired == false then
			pcall(function() humanoid:UnequipTools() end)
		else
			local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
			local tool = (bp and bp:FindFirstChild(desired)) or char:FindFirstChild(desired)
			if tool and tool:IsA("Tool") then
				pcall(function() humanoid:EquipTool(tool) end)
			else
				local missing = desired
				desired = nil -- the tool isn't there any more: stop trying
				if Core.SetStatus then task.spawn(Core.SetStatus, "Tool '" .. tostring(missing) .. "' missing, skipped") end
			end
		end
	end

	function T.ReplayEnd()
		desired = nil
		mismatch = 0
	end

	Janitor.add(function()
		clearChar()
		for _, list in pairs(toolConns) do for _, c in ipairs(list) do pcall(function() c:Disconnect() end) end end
		toolConns = {}
	end)
end

