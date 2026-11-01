-- ================================================================================================
--  LIBRARY WINDOW  (HappaTAS 3 ui, spec 8.3): the place's runs. A folder sidebar (All runs and every
--  folder, New folder from the name field, Delete folder for empty ones), a search field and a sort menu,
--  the list (name, length, frames, saved; a run's attempts folded under it behind a chevron), an info line
--  for the selection, a name field and the buttons Save / New attempt / Rename and Load / Merge / Move to /
--  Delete. Save into a name that exists and Delete ask a second click within 3 s; Load / Save / New attempt
--  / Merge are dimmed while a save or load runs (E.busy). Results and refusals show as status toasts; the
--  list is read again when the window opens and after every save or load (bus "persist").
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local Util = import("engine/util")
local Files = import("platform/files")
local Button = import("ui/kit/button")
local Field = import("ui/kit/field")
local Dropdown = import("ui/kit/dropdown")
local Icon = import("ui/kit/icon")

local LibraryWin = {}

local PAD, SIDE, ROW_H, CONFIRM = 14, 160, 22, 3
local SORTS = {
	{ "Name A–Z", "name", false }, { "Name Z–A", "name", true }, { "Newest", "date", true },
	{ "Oldest", "date", false }, { "Longest", "length", true }, { "Shortest", "length", false },
}
local MOVE_LABEL, TOP_LEVEL = "Move to…", "Top level"
local BUSY_DIMS = { load = true, save = true, attempt = true, merge = true }

function LibraryWin.define(ui)
	ui.wm:define("library", { title = "Library", w = 660, h = 470, minW = 560, minH = 340,
		build = function(body, win) ui.libraryWin = LibraryWin.build(ui, body, win) end })
	ui:addDockButton("library")
end

local function lower(s) return string.lower(s) end

local function sizeText(n)
	n = n or 0
	if n < 1024 then return n .. " B" end
	if n < 1024 * 1024 then return string.format("%.1f KB", n / 1024) end
	return string.format("%.1f MB", n / 1024 / 1024)
end

local function dateText(t)
	if type(t) ~= "number" or t <= 0 then return "-" end
	return os.date("%Y-%m-%d %H:%M", t)
end

-- a clipped scrolling list in body; returns the frame and a ctx whose pointer rects are clipped to it
local function scrollList(lw, ctx, parent, name)
	local list = Instance.new("ScrollingFrame")
	list.Name = name
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.Parent = parent
	local lctx = {}
	for k, v in pairs(ctx) do lctx[k] = v end
	lctx.pointer = { add = function(r, z) r.clip = list; return ctx.pointer.add(r, z) end, remove = ctx.pointer.remove }
	local conn = list:GetPropertyChangedSignal("CanvasPosition"):Connect(function() W.bump() end)
	lw.offs[#lw.offs + 1] = function() conn:Disconnect() end
	return list, lctx
end

function LibraryWin.build(ui, body, win)
	local E, ctx, th = ui.E, win.ctx, ui.theme
	local lw = { ui = ui, E = E, ctx = ctx, win = win, offs = {}, rows = {}, visible = {}, folderRows = {},
		buttons = {}, expanded = {}, folder = nil, selected = nil, query = "", sortIndex = 1, confirm = nil }

	-- ---------------------------------------------------------------------------------------- sidebar
	local side = K.frame("Sidebar", body)
	side.Position = UDim2.new(0, 0, 0, 0)
	side.Size = UDim2.new(0, SIDE, 1, 0)
	local folders, fctx = scrollList(lw, ctx, side, "Folders")
	folders.Position = UDim2.new(0, 8, 0, 10)
	folders.Size = UDim2.new(1, -12, 1, -86)
	lw.folders, lw.fctx = folders, fctx
	lw.newFolder = Button.new(ctx, side, { text = "New folder", kind = "plain", w = SIDE - 24 })
	lw.newFolder.gui.Position = UDim2.new(0, 12, 1, -68)
	lw.deleteFolder = Button.new(ctx, side, { text = "Delete folder", kind = "plain", w = SIDE - 24 })
	lw.deleteFolder.gui.Position = UDim2.new(0, 12, 1, -38)

	-- ---------------------------------------------------------------------------------------- main
	local main = K.frame("Main", body)
	main.Position = UDim2.new(0, SIDE, 0, 0)
	main.Size = UDim2.new(1, -SIDE, 1, 0)
	lw.search = Field.new(ctx, main, { search = true, w = 260, placeholder = "Search" })
	lw.search.gui.Position = UDim2.new(0, PAD, 0, 8)
	local sortNames = {}
	for _, s in ipairs(SORTS) do sortNames[#sortNames + 1] = s[1] end
	lw.sort = Dropdown.new(ctx, main, { options = sortNames, w = 130 })
	lw.sort.gui.AnchorPoint = Vector2.new(1, 0)
	lw.sort.gui.Position = UDim2.new(1, -PAD, 0, 12)

	local header = K.frame("Header", main)
	header.Position = UDim2.new(0, PAD, 0, 48)
	header.Size = UDim2.new(1, -PAD * 2, 0, 16)
	-- a label in the theme's look (rows and folders are made again on a theme change; the header and the
	-- info line are restyled: lw.static)
	lw.static = {}
	local function paint(l, secondary, kind)
		W.set(l, "FontFace", th.font(kind or "text"))
		W.set(l, "TextSize", th.size(secondary and 10.5 or 12))
		W.set(l, "TextColor3", secondary and th.c.text2 or th.c.text)
	end
	local function column(parent, name, x, w, align, secondary, kind, static)
		local l = K.text("TextLabel", name, parent)
		l.Position = UDim2.new(x[1], x[2], 0, 0)
		l.Size = UDim2.new(w[1], w[2], 1, 0)
		l.TextXAlignment = align or Enum.TextXAlignment.Left
		l.TextTruncate = Enum.TextTruncate.AtEnd
		paint(l, secondary, kind)
		if static then lw.static[#lw.static + 1] = { l, secondary, kind } end
		return l
	end
	local COLS = {
		name = { { 0, 24 }, { 1, -320 } },
		length = { { 1, -290 }, { 0, 70 } },
		frames = { { 1, -212 }, { 0, 80 } },
		saved = { { 1, -126 }, { 0, 120 } },
	}
	lw.headers = {
		column(header, "Name", COLS.name[1], COLS.name[2], nil, true, nil, true),
		column(header, "Length", COLS.length[1], COLS.length[2], Enum.TextXAlignment.Right, true, nil, true),
		column(header, "Frames", COLS.frames[1], COLS.frames[2], Enum.TextXAlignment.Right, true, nil, true),
		column(header, "Saved", COLS.saved[1], COLS.saved[2], Enum.TextXAlignment.Right, true, nil, true),
	}
	lw.headers[1].Text, lw.headers[2].Text, lw.headers[3].Text, lw.headers[4].Text = "Name", "Length", "Frames", "Saved"

	local list, lctx = scrollList(lw, ctx, main, "List")
	list.Position = UDim2.new(0, PAD, 0, 66)
	list.Size = UDim2.new(1, -PAD * 2, 1, -66 - 110)
	lw.list, lw.lctx = list, lctx

	lw.info = column(main, "Info", { 0, PAD }, { 1, -PAD * 2 }, nil, true, nil, true)
	lw.info.Position = UDim2.new(0, PAD, 1, -104)
	lw.info.Size = UDim2.new(1, -PAD * 2, 0, 18)
	lw.info.Text = ""

	-- the name field and the buttons (two rows)
	lw.nameField = Field.new(ctx, main, { w = 200, placeholder = "Name" })
	lw.nameField.gui.Position = UDim2.new(0, PAD, 1, -78)
	local function button(key, text, parent, x, y, kind)
		local b = Button.new(ctx, parent, { text = text, kind = kind or "plain" })
		b.gui.Position = UDim2.new(0, x, 1, y)
		b.enabled = true
		b.text = text
		lw.buttons[key] = b
		return b
	end
	local x1 = PAD + 208
	button("save", "Save", main, x1, -78, "primary")
	button("attempt", "New attempt", main, x1 + 62, -78)
	button("rename", "Rename", main, x1 + 168, -78)
	button("load", "Load", main, PAD, -44, "primary")
	button("merge", "Merge", main, PAD + 62, -44)
	button("delete", "Delete", main, PAD + 134, -44)
	lw.moveDrop = Dropdown.new(ctx, main, { options = { MOVE_LABEL }, w = 150 })
	lw.moveDrop.gui.Position = UDim2.new(0, PAD + 214, 1, -44)

	-- ---------------------------------------------------------------------------------------- helpers
	local function status(text, isError) E.bus:emit("status", text, isError == true) end
	local function shownFolder() return lw.folder or "" end
	local function entryOf(path)
		for _, e in ipairs(lw.entries or {}) do
			if e.path == path then return e end
		end
		return nil
	end
	local function setButtonText(b, text)
		if b.label.Text ~= text then b:setText(text) end
	end
	local function setConfirm(name, key)
		lw.confirm = name and { name = name, key = key, left = CONFIRM } or nil
		setButtonText(lw.buttons.save, (name == "save") and "Overwrite?" or "Save")
		setButtonText(lw.buttons.delete, (name == "delete") and "Delete?" or "Delete")
	end
	local function asked(name, key)
		local c = lw.confirm
		return c ~= nil and c.name == name and c.key == key
	end

	-- dim / undim (Bar:setEnabled's look: a calmer pill, a faint label)
	local function setEnabled(b, on)
		if b.enabled == on then return end
		b.enabled = on
		W.set(b.gui, "BackgroundTransparency", on and (b.kind == "primary" and 0 or 0.88) or 0.95)
		W.set(b.label, "TextTransparency", on and 0 or 0.6)
	end
	local function updateButtons(force)
		local busy = E.busy ~= nil
		local sel = lw.selected ~= nil and entryOf(lw.selected) ~= nil
		local want = {
			load = sel and not busy, save = not busy, attempt = not busy,
			merge = sel and not busy and lw.onMerge ~= nil,
			rename = sel, delete = sel,
		}
		for key, on in pairs(want) do
			local b = lw.buttons[key]
			if force then b.enabled = nil end
			setEnabled(b, on)
		end
		local fb = lw.deleteFolder
		if force then fb.enabled = nil end
		setEnabled(fb, lw.folder ~= nil)
	end
	lw.updateButtons = updateButtons

	local function showInfo()
		local e = lw.selected and entryOf(lw.selected)
		if not e then
			W.set(lw.info, "Text", "")
			return
		end
		local parts = { sizeText(e.size), "v" .. tostring(e.version or "?") }
		if e.script then parts[#parts + 1] = "script " .. tostring(e.script) end
		if e.frames then parts[#parts + 1] = e.frames .. " frames" end
		if (e.kit or 0) > 0 then parts[#parts + 1] = "kit objects" end
		if (e.speedHack or 0) > 0 then parts[#parts + 1] = "speed hack" end
		if e.created then parts[#parts + 1] = "created " .. dateText(e.created) end
		W.set(lw.info, "Text", table.concat(parts, "  ·  "))
	end

	-- ---------------------------------------------------------------------------------------- folders
	local function folderLabel(f)
		if f == nil then return "All runs" end
		return f:match("([^/]+)$") or f
	end
	local function buildFolders()
		for _, fr in ipairs(lw.folderRows) do
			fctx.pointer.remove(fr.rect)
			fr.gui:Destroy()
		end
		lw.folderRows = {}
		local all = { false }
		for _, f in ipairs(E.library:folders()) do
			if f ~= "" then all[#all + 1] = f end
		end
		local y = 0
		local moveOptions = { MOVE_LABEL, TOP_LEVEL }
		for _, f in ipairs(all) do
			local folder = f or nil
			local depth = folder and select(2, folder:gsub("/", "")) + 1 or 0
			local gui = K.frame("Folder", folders, Color3.new(1, 1, 1))
			gui.BackgroundTransparency = (lw.folder == folder) and 0.84 or 1
			gui.Position = UDim2.new(0, 0, 0, y)
			gui.Size = UDim2.new(1, -4, 0, ROW_H)
			K.corner(gui, 8)
			local label = column(gui, "Label", { 0, 10 + math.max(0, depth - 1) * 12 }, { 1, -14 }, nil, false, folder and "text" or "bold")
			label.Text = folderLabel(folder)
			local fr = { folder = folder, gui = gui, label = label }
			fr.rect = fctx.pointer.add({ gui = gui, onRelease = function(_, clicked)
				if not clicked then return end
				lw.folder = folder
				lw.selected = nil
				setConfirm(nil)
				lw:refresh()
			end }, 1)
			lw.folderRows[#lw.folderRows + 1] = fr
			if folder then moveOptions[#moveOptions + 1] = folder end
			y = y + ROW_H + 2
		end
		W.set(folders, "CanvasSize", UDim2.new(0, 0, 0, y))
		lw.moveDrop.options = moveOptions
	end

	-- ---------------------------------------------------------------------------------------- the list
	local function selectRow(path)
		lw.selected = path
		local e = path and entryOf(path)
		if e then lw.nameField:set(e.name) end
		for _, r in ipairs(lw.rows) do
			W.set(r.gui, "BackgroundTransparency", (r.entry.path == path) and 0.84 or 1)
		end
		setConfirm(nil)
		showInfo()
		updateButtons()
	end
	lw.select = selectRow

	local function buildRows()
		for _, r in ipairs(lw.rows) do
			lctx.pointer.remove(r.rect)
			if r.chevronRect then lctx.pointer.remove(r.chevronRect) end
			if r.chevron then r.chevron:destroy() end
			r.gui:Destroy()
		end
		lw.rows = {}
		local y = 0
		for _, v in ipairs(lw.visible) do
			local e = v.entry
			local gui = K.frame("Row", list, Color3.new(1, 1, 1))
			gui.BackgroundTransparency = (e.path == lw.selected) and 0.84 or 1
			gui.Position = UDim2.new(0, 0, 0, y)
			gui.Size = UDim2.new(1, -6, 0, ROW_H)
			K.corner(gui, 8)
			local indent = v.depth * 16
			local name = column(gui, "Name", { 0, 24 + indent }, { 1, -320 - indent })
			name.Text = (lw.folder == nil and e.folder ~= "" and v.depth == 0) and (e.folder .. "/" .. e.name) or e.name
			column(gui, "Length", COLS.length[1], COLS.length[2], Enum.TextXAlignment.Right, true, "number").Text =
				Util.toTime(e.length or 0)
			column(gui, "Frames", COLS.frames[1], COLS.frames[2], Enum.TextXAlignment.Right, true, "number").Text =
				tostring(e.frames or "-")
			column(gui, "Saved", COLS.saved[1], COLS.saved[2], Enum.TextXAlignment.Right, true, "number").Text =
				dateText(e.saved)
			local r = { entry = e, depth = v.depth, gui = gui, label = name }
			r.rect = lctx.pointer.add({ gui = gui, onRelease = function(_, clicked) if clicked then selectRow(e.path) end end }, 1)
			if v.depth == 0 and v.group and #v.group.attempts > 0 then
				local chev = Icon.new(lctx, gui, "chevron", 9)
				chev.gui.AnchorPoint = Vector2.new(0.5, 0.5)
				chev.gui.Position = UDim2.new(0, 12, 0.5, 0)
				W.set(chev.gui, "Rotation", lw.expanded[e.path] and 0 or -90)
				r.chevron = chev
				r.chevronRect = lctx.pointer.add({ gui = chev.gui, onRelease = function(_, clicked)
					if not clicked then return end
					lw.expanded[e.path] = not lw.expanded[e.path] or nil
					lw:rebuild()
				end }, 2)
			end
			lw.rows[#lw.rows + 1] = r
			y = y + ROW_H
		end
		W.set(list, "CanvasSize", UDim2.new(0, 0, 0, y + 4))
	end

	-- the visible rows from the entries: the shown folder, the search, the sort, attempts folded
	function lw:rebuild()
		local lib = E.library
		local shown = {}
		for _, e in ipairs(self.entries or {}) do
			if self.folder == nil or e.folder == self.folder then shown[#shown + 1] = e end
		end
		local s = SORTS[self.sortIndex]
		local groups = lib:groups(lib:sorted(lib:search(shown, self.query), s[2], s[3]))
		local visible = {}
		for _, g in ipairs(groups) do
			visible[#visible + 1] = { entry = g.run, depth = 0, group = g }
			if self.expanded[g.run.path] then
				for _, a in ipairs(g.attempts) do visible[#visible + 1] = { entry = a, depth = 1 } end
			end
		end
		self.visible = visible
		if self.selected and not entryOf(self.selected) then self.selected = nil end
		buildRows()
		showInfo()
		updateButtons()
	end

	-- the runs read again (the window opens, a save or load ended, a file changed here)
	function lw:refresh()
		self.entries = E.library:list()
		buildFolders()
		self:rebuild()
	end

	-- ---------------------------------------------------------------------------------------- actions
	local function nameText() return lw.nameField.box.Text end
	lw.buttons.save.onClick = function()
		if not lw.buttons.save.enabled then return end
		local clean = Files.cleanName(nameText())
		if not clean then
			setConfirm(nil)
			status("Invalid name", true)
			return
		end
		local folder = shownFolder()
		local existing
		for _, e in ipairs(E.library:list()) do
			if e.folder == folder and lower(e.name) == lower(clean) and lower(e.ext) == ".tas" then existing = e end
		end
		if existing and not asked("save", lower(existing.path)) then
			setConfirm("save", lower(existing.path))
			return
		end
		setConfirm(nil)
		local ok, why = E.persist:save(existing and existing.name or clean, folder)
		if not ok then status(why, true) end
		updateButtons()
	end
	lw.buttons.attempt.onClick = function()
		if not lw.buttons.attempt.enabled then return end
		setConfirm(nil)
		local clean = Files.cleanName(nameText())
		if not clean then
			status("Invalid name", true)
			return
		end
		local ok, why = E.persist:save(clean, shownFolder(), true)
		if not ok then status(why, true) end
		updateButtons()
	end
	lw.buttons.load.onClick = function()
		if not lw.buttons.load.enabled or not lw.selected then return end
		setConfirm(nil)
		local ok, why = E.persist:load(lw.selected)
		if not ok then status(why, true) end
		updateButtons()
	end
	lw.buttons.merge.onClick = function()
		if not lw.buttons.merge.enabled or not lw.selected or not lw.onMerge then return end
		setConfirm(nil)
		lw.onMerge(lw.selected)
	end
	lw.buttons.rename.onClick = function()
		if not lw.buttons.rename.enabled or not lw.selected then return end
		setConfirm(nil)
		local ok, res = E.library:rename(lw.selected, nameText())
		if not ok then
			status(res, true)
			return
		end
		status("Renamed to " .. (res:match("([^/]+)%.[^%.]+$") or res))
		lw.selected = res
		lw:refresh()
	end
	lw.buttons.delete.onClick = function()
		if not lw.buttons.delete.enabled or not lw.selected then return end
		local path = lw.selected
		if not asked("delete", path) then
			setConfirm("delete", path)
			return
		end
		setConfirm(nil)
		local e = entryOf(path)
		local ok, why = E.library:delete(path)
		if not ok then
			status(why or "Could not delete the file", true)
			return
		end
		status("Deleted " .. (e and e.name or path))
		lw.selected = nil
		lw:refresh()
	end
	lw.moveDrop.onChange = function(v)
		lw.moveDrop:set(MOVE_LABEL)
		if v == MOVE_LABEL or not lw.selected then return end
		setConfirm(nil)
		local ok, res = E.library:move(lw.selected, v == TOP_LEVEL and "" or v)
		if not ok then
			status(res, true)
			return
		end
		status("Moved to " .. v)
		lw.selected = res
		lw:refresh()
	end
	lw.newFolder.onClick = function()
		setConfirm(nil)
		local clean = Files.cleanName(nameText())
		if not clean then
			status("Type the folder's name first", true)
			return
		end
		local f = shownFolder()
		local ok, res = E.library:createFolder(f == "" and clean or (f .. "/" .. clean))
		if not ok then
			status(res, true)
			return
		end
		status("Folder " .. res .. " made")
		lw:refresh()
	end
	lw.deleteFolder.onClick = function()
		if not lw.deleteFolder.enabled or not lw.folder then return end
		setConfirm(nil)
		local ok, why = E.library:deleteFolder(lw.folder)
		if not ok then
			status(why or "Could not delete the folder", true)
			return
		end
		status("Folder " .. lw.folder .. " deleted")
		lw.folder = nil
		lw:refresh()
	end
	lw.sort.onChange = function(v)
		for i, s in ipairs(SORTS) do
			if s[1] == v then lw.sortIndex = i end
		end
		lw:rebuild()
	end
	lw.search.onInput = function(text)
		lw.query = text or ""
		lw:rebuild()
	end

	-- ---------------------------------------------------------------------------------------- lifetime
	-- (while open: the 3-second questions run out, the buttons follow E.busy)
	local function follow()
		if win.open and not lw.off then
			lw.off = E.pipe:add("PreRender", 240, "ui.library", function(dt)
				local c = lw.confirm
				if c then
					c.left = c.left - (dt or 0)
					if c.left <= 0 then setConfirm(nil) end
				end
				if (E.busy ~= nil) ~= lw.wasBusy then
					lw.wasBusy = E.busy ~= nil
					updateButtons()
				end
			end, "ui")
		elseif not win.open and lw.off then
			lw.off()
			lw.off = nil
			setConfirm(nil)
		end
	end
	lw.offs[#lw.offs + 1] = ui.wm:changed(function(id, open)
		if id ~= "library" then return end
		follow()
		if open then lw:refresh() end
	end)
	lw.offs[#lw.offs + 1] = E.bus:on("persist", function(ev)
		if ev and (ev.op == "save" or ev.op == "load") and win.open then lw:refresh() end
	end)
	lw.offs[#lw.offs + 1] = th:changed(function()
		for _, s in ipairs(lw.static) do paint(s[1], s[2], s[3]) end
		updateButtons(true)
		if win.open then lw:refresh() end
	end)
	ui.life:own(function()
		if lw.off then lw.off() end
		for _, off in ipairs(lw.offs) do off() end
	end)
	follow()
	lw:refresh()
	return lw
end

return LibraryWin
