-- ================================================================================================
--  MENU  (Controls, Settings, Saves, Help, More)
-- ================================================================================================
do
	local uis = UIS
	local ts = TweenService

	local Gui, menu, MobileUI, MergeMenu, JoinMessage
	local ControlsFrame, SettingsFrame, SavesFrame, HelpFrame, MoreFrame
	local WaitInputConnection, ChangingInput = nil, nil
	local SavingOrLoading = false
	local slotFrames = {}
	local slotNameOf = {}
	local pendingMerge = nil

	function Menu.IsModalOpen()
		return (menu ~= nil and menu.Visible) or (MergeMenu ~= nil and MergeMenu.Visible)
	end

	local function SetStatus(text, fade)
		task.spawn(C.SetStatus, text, fade)
	end
	Menu.SetStatus = SetStatus

	local function autoCanvas(scroller, container, extra)
		local ulog = container:FindFirstChild("3UpdateLog")
		local ulogLayout = ulog and ulog:FindFirstChildOfClass("UIListLayout")
		if ulog and ulogLayout then
			local function fitLog() ulog.Size = UDim2.new(1, 0, 0, ulogLayout.AbsoluteContentSize.Y + 10) end
			on(ulogLayout:GetPropertyChangedSignal("AbsoluteContentSize"), fitLog)
			fitLog()
		end
		local layout = container:FindFirstChildOfClass("UIListLayout")
		if not layout then return end
		local function fit()
			if container.Name == "List" or container.Name == "YourSlots" then
				container.Size = UDim2.new(container.Size.X.Scale, container.Size.X.Offset, 0, layout.AbsoluteContentSize.Y)
			end
			scroller.CanvasSize = UDim2.new(0, 0, 0, container.Position.Y.Offset + layout.AbsoluteContentSize.Y + (extra or 30))
		end
		on(layout:GetPropertyChangedSignal("AbsoluteContentSize"), fit)
		fit()
	end

	local function SetStatsSize(TextSize)
		for _, v in ipairs({ Gui.IdleStats, Gui.CreateStats, Gui.TestStats, Gui.MergeStats }) do
			local rows = 0
			for _, x in ipairs(v:GetChildren()) do
				if x:IsA("TextLabel") then
					rows = rows + 1
					x.Size = UDim2.new(1, 0, 0, 18 * TextSize / 11)
					x.TextSize = TextSize
				end
			end
			v.Size = UDim2.new(0, 240 * TextSize / 11, 0, rows * 18 * TextSize / 11)
			if v.Name == "MergeStats" then
				v.Position = UDim2.new(1, -10, 1, -180 * TextSize / 11 - 20)
			end
		end
	end

	local function progressText(verb)
		return function(i, n) task.spawn(C.SetStatus, verb .. " " .. i .. "/" .. n, true) end
	end

	local function sizeText(size)
		if not size then return "?" end
		if size >= 1048576 then return string.format("%.2f MB", size / 1048576) end
		return string.format("%.1f KB", size / 1024)
	end

	local function SaveSlot(name)
		if not name then return end
		if SavingOrLoading then SetStatus("You are already saving or loading.", true) return end
		local source = Core.GetTAS()
		if #source == 0 then SetStatus("There is nothing to save", true) return end
		SavingOrLoading = true
		local copy = table.move(source, 1, #source, 1, {})
		SetStatus("Saving...", true)
		local ok, res, size = Store.SaveSlot(name, copy, progressText("Saving"))
		SavingOrLoading = false
		if ok then
			SetStatus("Save Success! (" .. res .. " frames, " .. sizeText(size) .. ")", true)
		else
			SetStatus("Save Failed: " .. tostring(res), true)
		end
	end

	local function LoadSlot(name, mergeWhen)
		if not name then return end
		if SavingOrLoading then SetStatus("You are already saving or loading.", true) return end
		SavingOrLoading = true
		SetStatus("Loading...", true)
		local ok, result = Store.LoadSlot(name, progressText("Loading"))
		SavingOrLoading = false
		if ok then
			if #result == 0 then SetStatus("There is nothing to load", true) return end
			Core.SetTAS(result, mergeWhen)
			SetStatus(mergeWhen and "Move into the green hitbox to complete the merge" or "Load Success!", true)
		else
			SetStatus("Load Failed: " .. tostring(result), true)
		end
	end

	local function MergeSlot(name)
		if not name then return end
		if Core.GetTAS(true) == 0 then SetStatus("You must have a TAS to merge", true) return end
		if SavingOrLoading then SetStatus("You are already saving or loading.", true) return end
		SavingOrLoading = true
		SetStatus("Loading...", true)
		local ok, result = Store.LoadSlot(name, progressText("Loading"))
		SavingOrLoading = false
		if not ok or type(result) ~= "table" or #result == 0 then SetStatus("Load Failed: " .. tostring(result), true) return end
		local running = Enum.HumanoidStateType.Running.Value
		local canBefore = result[#result].State == running
		local canAfter = result[1].State == running
		pendingMerge = result
		SetStatus("")
		menu.Visible = false
		MergeMenu.Visible = true
		MergeMenu.Options.Before.Interactable = canBefore
		MergeMenu.Options.Before.BackgroundColor3 = canBefore and Color3.fromRGB(0, 52, 129) or Color3.fromRGB(50, 50, 50)
		MergeMenu.Options.After.Interactable = canAfter
		MergeMenu.Options.After.BackgroundColor3 = canAfter and Color3.fromRGB(0, 52, 129) or Color3.fromRGB(50, 50, 50)
	end

	local function updateSlotCount()
		local n = 0
		for _ in pairs(slotFrames) do n = n + 1 end
		SavesFrame.YourSlots.Top.Count.Text = n .. (n == 1 and " slot" or " slots")
	end

	local function reorderSlots(names)
		names = names or Store.ListSlots()
		for i, name in ipairs(names) do
			local f = slotFrames[name]
			if f then f.LayoutOrder = i; f.IDtext.Text = "#" .. i end
		end
	end

	local function createSlotFrame(name)
		local Slot = UI.Template("Slot")
		Slot.Name = "Slot_" .. name
		Slot.N.Text = name
		slotFrames[name] = Slot
		slotNameOf[Slot] = name
		Slot.Parent = SavesFrame.YourSlots

		on(Slot.N.FocusLost, function()
			local old = slotNameOf[Slot]
			if not old then return end
			local clean = Store.CleanName(Slot.N.Text)
			if not clean or clean == old then Slot.N.Text = old return end
			local ok, res = Store.RenameSlot(old, clean)
			if ok then
				slotFrames[old] = nil
				slotFrames[res] = Slot
				slotNameOf[Slot] = res
				Slot.Name = "Slot_" .. res
				Slot.N.Text = res
				reorderSlots()
			else
				Slot.N.Text = old
				SetStatus(tostring(res), true)
			end
		end)

		local confirmDelete = false
		on(Slot.MoreButtons.Delete.MouseButton1Click, function()
			local nm = slotNameOf[Slot]
			if not nm then return end
			if not confirmDelete then
				confirmDelete = true
				Slot.MoreButtons.Delete.Text = "Sure?"
				task.delay(3, function() confirmDelete = false; if Slot.Parent then Slot.MoreButtons.Delete.Text = "Delete" end end)
				return
			end
			local ok, err = Store.DeleteSlot(nm)
			if ok then
				slotFrames[nm] = nil
				slotNameOf[Slot] = nil
				Slot:Destroy()
				updateSlotCount()
				reorderSlots()
			else
				SetStatus("Delete failed: " .. tostring(err), true)
			end
		end)

		on(Slot.Buttons.Save.MouseButton1Click, function() SaveSlot(slotNameOf[Slot]) end)
		on(Slot.Buttons.Load.MouseButton1Click, function() LoadSlot(slotNameOf[Slot]) end)
		on(Slot.MoreButtons.Merge.MouseButton1Click, function() MergeSlot(slotNameOf[Slot]) end)
		on(Slot.Buttons.Expand.MouseButton1Click, function()
			Slot.Size = Slot.Size + UDim2.new(0, 0, 0, 30)
			Slot.Buttons.Expand.Visible = false
			Slot.Buttons.Close.Visible = true
		end)
		on(Slot.Buttons.Close.MouseButton1Click, function()
			Slot.Size = Slot.Size - UDim2.new(0, 0, 0, 30)
			Slot.Buttons.Expand.Visible = true
			Slot.Buttons.Close.Visible = false
		end)
		return Slot
	end

	local function rebuildSlots()
		for _, f in pairs(slotFrames) do f:Destroy() end
		slotFrames, slotNameOf = {}, {}
		local names = Store.ListSlots()
		for _, name in ipairs(names) do createSlotFrame(name) end
		reorderSlots(names)
		updateSlotCount()
	end

	local function refreshSlotsIfChanged()
		if not Store.Ready then return end
		local names = Store.ListSlots()
		local same, count = true, 0
		for _, name in ipairs(names) do
			count = count + 1
			if not slotFrames[name] then same = false break end
		end
		if same then
			local shown = 0
			for _ in pairs(slotFrames) do shown = shown + 1 end
			same = shown == count
		end
		if not same then rebuildSlots() end
	end

	-- --------------------------------------------------------------------------------------------- settings rows
	local function bindSettings()
		local SWITCH_ON = { Position = UDim2.new(1, 0, 0.5, 0), BackgroundColor3 = Color3.fromRGB(75, 75, 75) }
		local SWITCH_OFF = { Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = Color3.fromRGB(255, 255, 255) }
		for _, def in ipairs(SettingsTable) do
			local row = SettingsFrame.List:FindFirstChild(def.name)
			if row then
				local name = def.name
				if def.kind == "toggle" then
					local switch = row:FindFirstChild("Switch")
					local knob = switch and switch:FindFirstChild("Switcher")
					if switch and knob then
						local tOn = ts:Create(knob, TweenInfo.new(0.25), SWITCH_ON)
						local tOff = ts:Create(knob, TweenInfo.new(0.25), SWITCH_OFF)
						local function show(v, instant)
							local target = (v ~= 0) and SWITCH_ON or SWITCH_OFF
							if instant then
								knob.Position, knob.BackgroundColor3 = target.Position, target.BackgroundColor3
							elseif v ~= 0 then tOn:Play() else tOff:Play() end
						end
						show(Settings.Get(name), true)
						on(switch.MouseButton1Click, function()
							Settings.Set(name, Settings.On(name) and 0 or 1)
						end)
						Settings.Changed(name, function(v) show(v, false) end)
					end
				else
					local inp = row:FindFirstChild("Input")
					if inp then
						inp.Text = tostring(Settings.Get(name))
						on(inp.FocusLost, function()
							if not Settings.Set(name, inp.Text) then inp.Text = tostring(Settings.Get(name)) end
						end)
						Settings.Changed(name, function(v) inp.Text = tostring(v) end)
					end
				end
			end
		end
	end

	function Menu.Start(gui, onUnload)
		Gui = gui
		menu = gui.MainMenu
		MobileUI = gui.Mobile
		MergeMenu = gui.Merge
		JoinMessage = gui.JoinMessage
		ControlsFrame = menu.ControlsFrame
		SettingsFrame = menu.SettingsFrame
		SavesFrame = menu.SavesFrame
		HelpFrame = menu.HelpFrame
		MoreFrame = menu.MoreFrame
		if uis.TouchEnabled then
			MobileUI.MenuOpener.Visible = true
			MobileUI.More.Visible = true
			for i = 1, 3 do MobileUI.MobileModes["Mode" .. i .. "Mobile"].Visible = true end
			menu.ControlsFrame.Visible = false
			menu.ControlsToggle.Visible = false
			-- touch screens: the tabs without Controls, four in a row
			for x, t in pairs({ [0] = "Settings", [0.25] = "Saves", [0.5] = "Help", [0.75] = "More" }) do
				menu[t .. "Toggle"].Position = UDim2.new(x, 0, 0.108, 0)
				menu[t .. "Toggle"].Size = UDim2.new(0, 100, 0, 30)
			end
		end

		local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
		if viewport.Y < 420 then menu.Size = UDim2.new(0, 400, 0.95, 0) end

		local JoinTween = ts:Create(JoinMessage, TweenInfo.new(1, Enum.EasingStyle.Quad), { Position = UDim2.new(0, 10, 1, -10) })
		local ReverseJoinTween = ts:Create(JoinMessage, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(0, 10, 1, 150) })

		-- controls tab
		for i, cdef in ipairs(ControlsTable) do
			local cname = cdef[1]
			local ControlBlock = UI.Template("Control")
			ControlBlock.Name = cname
			ControlBlock.LayoutOrder = i
			ControlBlock.N.Text = cname
			ControlBlock.Key.Text = Controls.Get(cname)
			ControlBlock.Parent = ControlsFrame.List
			Controls.Changed(cname, function(v) ControlBlock.Key.Text = v end)
			on(ControlBlock.Key.MouseButton1Down, function()
				if ChangingInput then
					if WaitInputConnection then WaitInputConnection:Disconnect() end
					local old = ControlsFrame.List:FindFirstChild(ChangingInput)
					if old then old.Key.Text = Controls.Get(ChangingInput) end
				end
				ControlBlock.Key.Text = "Press Any Key"
				ChangingInput = cname
				Typing.rebinding = true
				RunService.RenderStepped:Wait()
				WaitInputConnection = uis.InputBegan:Connect(function(inp, proc)
					if proc and inp.UserInputType == Enum.UserInputType.Keyboard and not Settings.On("Ignore Game Processed") then return end
					local input
					if inp.UserInputType == Enum.UserInputType.Keyboard then input = inp.KeyCode
					elseif inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.MouseButton2 or inp.UserInputType == Enum.UserInputType.MouseButton3 then
						input = inp.UserInputType
					end
					if input and FromKey[input] then
						Controls.Set(ChangingInput, FromKey[input])
						ControlBlock.Key.Text = FromKey[input]
						if WaitInputConnection then WaitInputConnection:Disconnect() end
						ChangingInput = nil
						Typing.boundInput = inp
						Typing.rebinding = false
					end
				end)
				Janitor.add(WaitInputConnection)
			end)
		end

		bindSettings()
		SetStatsSize(Settings.Get("Stats Text Size"))
		Settings.Changed("Stats Text Size", function(v) SetStatsSize(v) end)

		if Store.Ready then
			rebuildSlots()
			on(SavesFrame.YourSlots.Top.AddSlot.MouseButton1Click, function()
				local ok, res = Store.CreateSlot(nil)
				if ok then createSlotFrame(res); reorderSlots(); updateSlotCount()
				else SetStatus("Could not add a slot: " .. tostring(res), true) end
			end)
		else
			SavesFrame.YourSlots.Top.Count.Text = "unavailable"
			SavesFrame.YourSlots.Top.AddSlot.Visible = false
		end

		on(MergeMenu.Cancel.MouseButton1Click, function() MergeMenu.Visible = false; pendingMerge = nil end)
		for _, when in ipairs({ "Before", "After" }) do
			on(MergeMenu.Options[when].MouseButton1Click, function()
				MergeMenu.Visible = false
				if pendingMerge then
					local tas = pendingMerge
					pendingMerge = nil
					Core.SetTAS(tas, when:lower())
					SetStatus("Move into the green hitbox to complete the merge", true)
				end
			end)
		end

		menu.Title.Text = "HappaTAS " .. VERSION
		JoinMessage.Title.Text = "HappaTAS " .. VERSION .. " Loaded"
		JoinMessage.M.Text = tostring(Controls.Get("Menu")) .. " - Main Menu"
		Controls.Changed("Menu", function(v) JoinMessage.M.Text = tostring(v) .. " - Main Menu" end)
		if not Store.Ready then
			JoinMessage.Size = UDim2.new(0, 280, 0, 110)
			JoinMessage.FailureMessage.Visible = true
		end
		JoinTween:Play()
		on(JoinMessage.Close.MouseButton1Down, function() ReverseJoinTween:Play() end)

		-- a Menu key on the keyboard works even when the game processed it (whatever Ignore Game Processed
		-- says); never while the player types (chat, a text box) or is in the Roblox menu
		on(uis.InputBegan, function(inp, proc)
			if not CheckInput(inp, "Menu") or Typing.Active(inp) then return end
			if inp.UserInputType ~= Enum.UserInputType.Keyboard then -- bound to a mouse button
				if InputSys.ClickOnOwnUI(inp) or (proc and not Settings.On("Ignore Game Processed")) then return end
			end
			menu.Visible = not menu.Visible
		end)

		local TABS = { "Controls", "Settings", "Saves", "Help", "More" }
		local function tab(TabName)
			for _, t in ipairs(TABS) do
				menu[t .. "Toggle"].BackgroundTransparency = 0.75
				menu[t .. "Frame"].Visible = false
			end
			menu[TabName .. "Toggle"].BackgroundTransparency = 0.5
			menu[TabName .. "Frame"].Visible = true
			if TabName == "Saves" then refreshSlotsIfChanged() end
		end
		for _, t in ipairs(TABS) do
			on(menu[t .. "Toggle"].MouseButton1Click, function() tab(t) end)
		end

		on(MoreFrame.List["1Model"].MouseButton1Click, function() if onUnload then onUnload() end end)
		if MoreFrame.List:FindFirstChild("ToggleMicroProfiler") then
			on(MoreFrame.List.ToggleMicroProfiler.MouseButton1Click, function()
				Settings.Set("Show MicroProfiler", Settings.On("Show MicroProfiler") and 0 or 1)
			end)
		end

		-- expandable help sections
		local hf = HelpFrame.List
		local SelectedHelp = "00"
		for _, v in ipairs(hf:GetChildren()) do
			if v:IsA("TextButton") then
				on(v.MouseButton1Click, function()
					if SelectedHelp ~= v.Name then
						if SelectedHelp ~= "00" then
							hf[SelectedHelp].Expansion.Visible = false
							hf[SelectedHelp].Expand.Text = "+"
							local oldSpacer = hf:FindFirstChild(SelectedHelp .. "Spacer")
							if oldSpacer then oldSpacer:Destroy() end
						end
						SelectedHelp = v.Name
						hf[SelectedHelp].Expansion.Visible = true
						hf[SelectedHelp].Expand.Text = "-"
						local spacer = hf.Spacer:Clone()
						spacer.Parent = hf
						spacer.Name = SelectedHelp .. "Spacer"
						spacer.Size = UDim2.new(0, 0, 0, hf[SelectedHelp].Expansion.Size.Y.Offset - 8)
					else
						hf[SelectedHelp].Expansion.Visible = false
						hf[SelectedHelp].Expand.Text = "+"
						local oldSpacer = hf:FindFirstChild(SelectedHelp .. "Spacer")
						if oldSpacer then oldSpacer:Destroy() end
						SelectedHelp = "00"
					end
				end)
			end
		end

		autoCanvas(ControlsFrame, ControlsFrame.List)
		autoCanvas(SettingsFrame, SettingsFrame.List)
		autoCanvas(HelpFrame, HelpFrame.List, 40)
		autoCanvas(MoreFrame, MoreFrame.List)
		autoCanvas(SavesFrame, SavesFrame.YourSlots, 60)

		on(MobileUI.MenuOpener.MouseButton1Click, function() menu.Visible = not menu.Visible end)
		on(MobileUI.More.MouseButton1Click, function()
			for _, b in ipairs(MobileUI.MobileOptions:GetChildren()) do b.Visible = not b.Visible end
		end)
		if MobileUI.MobileOptions:FindFirstChild("MicroProfiler") then
			on(MobileUI.MobileOptions.MicroProfiler.MouseButton1Click, function()
				Settings.Set("Show MicroProfiler", Settings.On("Show MicroProfiler") and 0 or 1)
			end)
		end
	end
end

