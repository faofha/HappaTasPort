-- ================================================================================================
--  CLASSIC SAVES  (HappaTAS 3 ui, spec 8.5): V2.38.17's Saves tab, merge dialog and Merge Stats on HappaTAS 3's
--  engine. A slot is a run at the top of the place folder (runs in folders show only in the new Library).
--  "Add Slot" adds a row ("Slot N") that becomes a file on its first Save; Save over a slot that holds a run
--  and Delete ask "Sure?" for 3 s (V2's delete question); a name typed in a slot renames its file
--  (Files.cleanName; refused: the old name back and the Library's message). Saving, loading and reading for a
--  merge go through E.persist (its refusals: never an empty run, not while busy, merges only in Idle or
--  paused in Create). The merge: V2's dialog (Before / After by the Running rule), then Merge Stats
--  (Current Distance / Distance Required, green "complete" or red "cancel"), updated each frame only while
--  a merge runs.
-- ================================================================================================
local Files = import("platform/files")
local Util = import("engine/util")
local Persist = import("persist/persist")
local ClassicTree = import("ui/classic/tree")
local ClassicBuild = import("ui/classic/build")

local Saves = {}

local CONFIRM = 3
local GAP = 5
local u = UDim2.new
local GREEN, RED = Color3.fromRGB(0, 80, 0), Color3.fromRGB(100, 0, 0)
local ON, OFF = Color3.fromRGB(0, 52, 129), Color3.fromRGB(50, 50, 50)

local function lower(s) return string.lower(s) end

function Saves.build(classic)
	local E, ui = classic.E, classic.ui
	local life, b = ui.life, classic.byPath
	local list = b["MainMenu.SavesFrame.YourSlots"]
	local sv = { slots = {}, count = b["MainMenu.SavesFrame.YourSlots.Top.Count"], addSlot = b["MainMenu.SavesFrame.YourSlots.Top.AddSlot"],
		pendingMerge = nil, frames = nil }
	local function status(t) E.bus:emit("status", t, true) end

	-- the place's top-level runs, by name
	local function entries()
		local top = {}
		for _, e in ipairs(E.library:list()) do if e.folder == "" then top[#top + 1] = e end end
		return E.library:sorted(top, "name", false)
	end
	local function layout()
		local h = 30
		for i, s in ipairs(sv.slots) do
			s.frame.LayoutOrder = i + 1
			s.frame.IDtext.Text = "#" .. i
			h = h + GAP + s.frame.Size.Y.Offset
		end
		local n = #sv.slots
		sv.count.Text = n .. (n == 1 and " slot" or " slots")
		list.Size = u(0, 360, 0, h)
		b["MainMenu.SavesFrame"].CanvasSize = u(0, 0, 0, h + 60)
	end
	-- a button asks "Sure?" once; true when this click is the second within CONFIRM s
	local function confirmed(s, button, word)
		if s.asking == button then
			s.asking = nil
			button.Text = word
			return true
		end
		s.asking = button
		button.Text = "Sure?"
		local token = {}
		s.token = token
		task.delay(CONFIRM, function()
			if s.token == token and s.asking == button then
				s.asking = nil
				if button.Parent then button.Text = word end
			end
		end)
		return false
	end

	local function removeSlot(s)
		local i = table.find(sv.slots, s)
		if i then table.remove(sv.slots, i) end
		pcall(function() s.frame:Destroy() end)
		layout()
	end

	local function newSlot(name, path)
		local f = ClassicBuild.node(ClassicTree.TEMPLATES.Slot, ClassicTree.STYLES)
		f.Name = "Slot_" .. name
		f.N.Text = name
		f.Parent = list
		local s = { frame = f, name = f.N, save = f.Buttons.Save, load = f.Buttons.Load, merge = f.MoreButtons.Merge,
			delete = f.MoreButtons.Delete, slotName = name, path = path }
		sv.slots[#sv.slots + 1] = s
		if classic.look then classic.look:adoptAll(f) end
		life:connect(f.N.FocusLost, function()
			local old = s.slotName
			local clean = Files.cleanName(f.N.Text)
			if not clean or clean == old then
				f.N.Text = old
				return
			end
			if s.path then
				local ok, res = E.library:rename(s.path, clean)
				if not ok then
					f.N.Text = old
					status(tostring(res))
					return
				end
				s.path = res
			end
			s.slotName = clean
			f.N.Text = clean
			f.Name = "Slot_" .. clean
		end)
		life:connect(s.save.MouseButton1Click, function()
			if s.path and not confirmed(s, s.save, "Save") then return end
			local ok, why = E.persist:save(s.slotName, "")
			if not ok then status(why) return end
			sv.saving = s
		end)
		life:connect(s.load.MouseButton1Click, function()
			if not s.path then status("This slot has nothing saved yet") return end
			local ok, why = E.persist:load(s.path)
			if not ok then status(why) end
		end)
		life:connect(s.merge.MouseButton1Click, function()
			if not s.path then status("This slot has nothing saved yet") return end
			if E.tl:count() == 0 then status("You must have a TAS to merge") return end
			local ok, why = E.persist:readFrames(s.path)
			if not ok then status(why) return end
			sv.pendingMerge = s.path
		end)
		life:connect(s.delete.MouseButton1Click, function()
			if not confirmed(s, s.delete, "Delete") then return end
			if s.path then
				local ok, err = E.library:delete(s.path)
				if not ok then status("Delete failed: " .. tostring(err)) return end
			end
			removeSlot(s)
		end)
		life:connect(f.Buttons.Expand.MouseButton1Click, function()
			f.Size = f.Size + u(0, 0, 0, 30)
			f.Buttons.Expand.Visible, f.Buttons.Close.Visible = false, true
			layout()
		end)
		life:connect(f.Buttons.Close.MouseButton1Click, function()
			f.Size = f.Size - u(0, 0, 0, 30)
			f.Buttons.Expand.Visible, f.Buttons.Close.Visible = true, false
			layout()
		end)
		return s
	end

	-- the rows made again only when the place's runs differ from them (V2's refreshSlotsIfChanged); rows not
	-- saved yet stay
	function sv.refresh()
		local list2 = entries()
		local have = {}
		for _, s in ipairs(sv.slots) do if s.path then have[lower(s.path)] = true end end
		local same = true
		local n = 0
		for _, e in ipairs(list2) do
			n = n + 1
			if not have[lower(e.path)] then same = false end
		end
		local saved = 0
		for _, s in ipairs(sv.slots) do if s.path then saved = saved + 1 end end
		if same and saved == n then layout() return end
		local keep = {}
		for _, s in ipairs(sv.slots) do
			if s.path then pcall(function() s.frame:Destroy() end) else keep[#keep + 1] = s end
		end
		sv.slots = {}
		for _, e in ipairs(list2) do newSlot(e.name, e.path) end
		for _, s in ipairs(keep) do sv.slots[#sv.slots + 1] = s end
		layout()
	end

	life:connect(sv.addSlot.MouseButton1Click, function()
		local used = {}
		for _, s in ipairs(sv.slots) do used[lower(s.slotName)] = true end
		for _, e in ipairs(E.library:list()) do if e.folder == "" then used[lower(e.name)] = true end end
		local i = 1
		while used[lower("Slot " .. i)] do i = i + 1 end
		newSlot("Slot " .. i, nil)
		layout()
	end)

	-- ---------------------------------------------------------------------------------------- the merge
	local merge = b.Merge
	local stats = b.MergeStats
	local running = Enum.HumanoidStateType.Running.Value
	local function setOption(btn, on)
		btn.Interactable = on
		btn.BackgroundColor3 = on and ON or OFF
	end
	local function follow()
		if E.merge and ui.live == "Classic" and not sv.off then
			sv.off = E.pipe:add("PreRender", 250, "ui.classic.merge", function() sv.step() end, "ui")
		elseif (not E.merge or ui.live ~= "Classic") and sv.off then
			sv.off()
			sv.off = nil
		end
	end
	function sv.step()
		if not E.merge then
			stats.Visible = false
			follow()
			return
		end
		local d, req = E.mergeDistance, E.mergeRun.reqDist
		b["MergeStats.1"].Text = " Current Distance: " .. (d and tostring(Util.round(d, 1000)) or "-")
		b["MergeStats.2"].Text = " Distance Required: " .. (req and tostring(Util.round(req, 1000)) or "-")
		local can = E.mergeCanComplete == true
		b["MergeStats.3"].Text = can and " Click here to complete merge" or " Click here to cancel merge"
		stats.BackgroundColor3 = can and GREEN or RED
	end
	for _, when in ipairs({ "Before", "After" }) do
		local btn = b["Merge.Options." .. when]
		life:connect(btn.MouseButton1Click, function()
			if not btn.Interactable or not sv.frames then return end
			if not Persist.canMerge(E) then status(Persist.NOT_NOW_MERGE) return end
			local frames = sv.frames
			sv.frames = nil
			merge.Visible = false
			ui:updateModal()
			if E.mergeRun:startMerge(frames, when:lower()) then
				status("Move into the green hitbox to complete the merge")
				stats.Visible = true
				follow()
				sv.step()
			end
		end)
	end
	life:connect(b["Merge.Cancel"].MouseButton1Click, function()
		merge.Visible = false
		sv.frames = nil
		ui:updateModal()
	end)
	life:connect(stats.MouseButton1Click, function()
		if not E.merge then return end
		E.mergeRun:finishMerge()
		stats.Visible = false
		follow()
	end)
	classic.offs[#classic.offs + 1] = E.bus:on("persist", function(ev)
		if not ev then return end
		if ev.op == "frames" and ev.path == sv.pendingMerge then
			sv.pendingMerge = nil
			if not ev.ok then return end
			local f = ev.frames
			sv.frames = f
			classic.menu.Visible = false
			merge.Visible = true
			setOption(b["Merge.Options.Before"], f[#f] ~= nil and f[#f].State == running)
			setOption(b["Merge.Options.After"], f[1] ~= nil and f[1].State == running)
			ui:updateModal()
		elseif ev.op == "save" and ev.ok and sv.saving then
			sv.saving.path = ev.path
			sv.saving = nil
			sv.refresh()
		elseif ev.op == "save" or ev.op == "load" then
			sv.saving = nil
			if ui.live == "Classic" then sv.refresh() end
		end
	end)
	classic.offs[#classic.offs + 1] = E.bus:on("uiShown", function() follow() end)
	classic.offs[#classic.offs + 1] = function() if sv.off then sv.off(); sv.off = nil end end
	sv.refresh()
	return sv
end

return Saves
