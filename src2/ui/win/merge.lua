-- ================================================================================================
--  MERGE WINDOW  (HappaTAS 3 ui, spec 8.3; V2.38.16's merge dialog and Merge Stats): opened by the Library's
--  Merge with a saved run. It needs a run in use ("You must have a TAS to merge"), reads the file
--  (Persist:readFrames: the run in use stays as it is), then offers Before / After: the file's run can go
--  before the current one only if its last frame is Running, after it only if its first frame is (V2's
--  rule). After a choice E.mergeRun:startMerge records from the end of the run before to the start of the run
--  after; the window shows the current and the required distance and one button, "Complete merge" (green,
--  close enough) or "Cancel merge" (red). You play while merging, so the window doesn't free the mouse
--  (modal false) and sits in the top-left corner; closing it during a merge cancels the merge.
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local Button = import("ui/kit/button")
local Persist = import("persist/persist")

local MergeWin = {}

local PAD = 16
local GREEN, RED = Color3.fromRGB(0, 140, 40), Color3.fromRGB(170, 30, 30)
local NO_RUN = "You must have a TAS to merge"

function MergeWin.define(ui)
	ui.wm:define("merge", { title = "Merge", w = 340, h = 190, minW = 300, minH = 170, modal = false, corner = "topLeft", remember = false,
		build = function(body, win) ui.mergeWin = MergeWin.build(ui, body, win) end })
	-- (the Library's Merge: open the window and read the run at path)
	ui.startMerge = function(path)
		ui.wm:open("merge")
		if ui.mergeWin then ui.mergeWin:start(path) end
	end
end

local function baseName(path)
	return (tostring(path):match("([^/]+)$") or tostring(path)):gsub("%.[^%.]+$", "")
end

function MergeWin.build(ui, body, win)
	local E, ctx, th = ui.E, win.ctx, ui.theme
	local mw = { E = E, ui = ui, win = win, buttons = {}, offs = {}, state = "idle", frames = nil, path = nil }
	local function label(name, y, h)
		local l = K.text("TextLabel", name, body)
		l.Position = UDim2.new(0, PAD, 0, y)
		l.Size = UDim2.new(1, -PAD * 2, 0, h)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextYAlignment = Enum.TextYAlignment.Top
		l.TextWrapped = true
		l.Text = ""
		return l
	end
	mw.message = label("Message", 12, 40)
	mw.detail = label("Detail", 54, 40)
	local function paint()
		W.set(mw.message, "FontFace", th.font("text"))
		W.set(mw.message, "TextSize", th.size(12.5))
		W.set(mw.message, "TextColor3", th.c.text)
		W.set(mw.detail, "FontFace", th.font("number"))
		W.set(mw.detail, "TextSize", th.size(11.5))
		W.set(mw.detail, "TextColor3", th.c.text2)
	end
	paint()
	local function button(key, text, x, kind)
		local b = Button.new(ctx, body, { text = text, kind = kind or "plain" })
		b.gui.Position = UDim2.new(0, x, 1, -40)
		b.enabled = true
		mw.buttons[key] = b
		return b
	end
	button("before", "Before", PAD, "primary")
	button("after", "After", PAD + 72, "primary")
	button("cancel", "Cancel", PAD + 136)
	button("finish", "Cancel merge", PAD)

	local function status(text, isError) E.bus:emit("status", text, isError == true) end
	local function setEnabled(b, on)
		if b.enabled == on then return end
		b.enabled = on
		W.set(b.gui, "BackgroundTransparency", on and (b.kind == "primary" and 0 or 0.88) or 0.95)
		W.set(b.label, "TextTransparency", on and 0 or 0.6)
	end
	-- what shows in each state: message (a line), reading, choose (Before / After / Cancel), merging (the
	-- distances and the finish button)
	local function show()
		local s = mw.state
		W.set(mw.buttons.before.gui, "Visible", s == "choose")
		W.set(mw.buttons.after.gui, "Visible", s == "choose")
		W.set(mw.buttons.cancel.gui, "Visible", s == "choose" or s == "reading" or s == "message")
		W.set(mw.buttons.finish.gui, "Visible", s == "merging")
		if s ~= "merging" then W.set(mw.detail, "Text", "") end
	end
	local function running(fr)
		return fr ~= nil and fr.State == Enum.HumanoidStateType.Running.Value
	end
	local function updateChoice()
		local f = mw.frames
		local busy = E.busy ~= nil
		setEnabled(mw.buttons.before, f ~= nil and running(f[#f]) and not busy)
		setEnabled(mw.buttons.after, f ~= nil and running(f[1]) and not busy)
	end
	local function setState(s, message)
		mw.state = s
		if message then W.set(mw.message, "Text", message) end
		show()
		if s == "choose" then updateChoice() end
	end

	-- reads the run at path (the window is open)
	function mw:start(path)
		if E.merge then
			setState("merging")
			return
		end
		self.frames, self.path = nil, path
		if E.tl:count() == 0 then
			setState("message", NO_RUN)
			status(NO_RUN, true)
			return
		end
		local ok, why = E.persist:readFrames(path)
		if not ok then
			setState("message", why)
			status(why, true)
			return
		end
		setState("reading", "Reading " .. baseName(path) .. "…")
	end

	local function begin(where)
		if not mw.frames then return end
		-- (the mode may have changed while Before / After were offered: a merge takes the run over)
		if not Persist.canMerge(E) then
			status(Persist.NOT_NOW_MERGE, true)
			return
		end
		if E.mergeRun:startMerge(mw.frames, where) then
			mw.frames = nil
			-- (you play now: the Library frees the mouse, so it closes)
			if ui.wm:isOpen("library") then ui.wm:close("library") end
			setState("merging", "Record to the green box, then finish here.")
		else
			setState("message", "The merge could not start.")
		end
	end
	mw.buttons.before.onClick = function() if mw.buttons.before.enabled then begin("before") end end
	mw.buttons.after.onClick = function() if mw.buttons.after.enabled then begin("after") end end
	mw.buttons.cancel.onClick = function() ui.wm:close("merge") end
	mw.buttons.finish.onClick = function()
		if not E.merge then return end
		E.mergeRun:finishMerge()
		setState("idle", "")
		ui.wm:close("merge")
	end

	-- (while merging: the distances and the finish button follow the recording; while choosing: E.busy)
	local function step()
		if mw.state == "merging" then
			if not E.merge then
				setState("idle", "")
				return
			end
			local d, req = E.mergeDistance, E.mergeRun.reqDist
			W.set(mw.detail, "Text", string.format("Current distance: %s\nDistance required: %s",
				d and string.format("%.3f", d) or "-", req and string.format("%.3f", req) or "-"))
			local can = E.mergeCanComplete == true
			local b = mw.buttons.finish
			if b.label.Text ~= (can and "Complete merge" or "Cancel merge") then
				b:setText(can and "Complete merge" or "Cancel merge")
			end
			W.set(b.gui, "BackgroundColor3", can and GREEN or RED)
			W.set(b.gui, "BackgroundTransparency", 0)
		elseif mw.state == "choose" then
			updateChoice()
		end
	end
	local function follow()
		if win.open and not mw.off then
			mw.off = E.pipe:add("PreRender", 245, "ui.merge", step, "ui")
		elseif not win.open and mw.off then
			mw.off()
			mw.off = nil
		end
	end
	mw.offs[#mw.offs + 1] = ui.wm:changed(function(id, open)
		if id ~= "merge" then return end
		follow()
		if not open then
			-- (closing during a merge cancels it: the old run comes back)
			if E.merge then
				E.mergeCanComplete = false
				E.mergeRun:finishMerge()
			end
			mw.frames, mw.path = nil, nil
			setState("idle", "")
		end
	end)
	mw.offs[#mw.offs + 1] = E.bus:on("persist", function(ev)
		if not ev or ev.op ~= "frames" or mw.state ~= "reading" or ev.path ~= mw.path then return end
		if not ev.ok then
			setState("message", ev.message)
			return
		end
		mw.frames = ev.frames
		setState("choose", "Put " .. baseName(ev.path) .. " before or after the run in use?")
	end)
	mw.offs[#mw.offs + 1] = th:changed(function()
		paint()
		for _, b in pairs(mw.buttons) do
			local on = b.enabled
			b.enabled = nil
			setEnabled(b, on ~= false)
		end
	end)
	ui.life:own(function()
		if mw.off then mw.off() end
		for _, off in ipairs(mw.offs) do off() end
	end)
	follow()
	setState("idle", "")
	return mw
end

return MergeWin
