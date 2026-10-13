-- ================================================================================================
--  BUTTONS  (EToH kit v6.1.3 buttons, "Sync Button Timers")
--
--  How the kit works (Repository/Interactables/Button): every button gets a BoolValue "Pressed" and
--  a NumberValue "TimerStart" next to its "ButtonPart". Pressing sets Pressed = true and
--  TimerStart = os.clock(); a Heartbeat loop releases the button when
--      Timer - (os.clock() - TimerStart) <= 0.
--  HappaTAS saves every press / release with the frame it happened on (plus how long the timer had
--  already run), and while a TAS is active it writes TimerStart so the kit's timer follows the TAS
--  clock: frozen while paused, exact when scrubbing, on the TAS clock while testing.
-- ================================================================================================
do
	local B = Buttons
	local reg = { byId = {}, byKey = {}, nextId = 1 }
	local enabled = false
	local descConn
	local conns = setmetatable({}, { __mode = "k" }) -- BoolValue -> connection (destroyed values drop out)
	local pending = {}
	local recording = false
	local pressAt = {}          -- id -> TAS time the current press started
	local control = "none"      -- none | record | paused | test
	local suppress = {}         -- id -> value HappaTAS just wrote (not a player action)
	local idx, idxData, idxVer = nil, nil, -1
	local dataVersion = 0
	local applied = 0           -- last frame applied during playback
	local tNowCache = 0

	local function keyOf(inst)
		return ClientObjects.KeyOf and ClientObjects.KeyOf(inst) or inst:GetFullName()
	end

	local function idForKey(key)
		local b = reg.byKey[key]
		if b then return b.id end
		local id = reg.nextId
		reg.nextId = id + 1
		b = { id = id, key = key }
		reg.byKey[key], reg.byId[id] = b, b
		return id
	end

	local function timerOf(b)
		local t = b.timer
		if t and t.Parent == b.parent then return t end
		t = b.parent and b.parent:FindFirstChild("TimerStart")
		if t and t:IsA("NumberValue") then b.timer = t return t end
		return nil
	end

	local function isButtonValue(v)
		if not v:IsA("BoolValue") or v.Name ~= "Pressed" then return false end
		local p = v.Parent
		local bp = p and p:FindFirstChild("ButtonPart")
		return bp ~= nil and bp:IsA("BasePart")
	end

	local function onPressedChanged(b)
		local v = b.pressed
		if not v or not v.Parent then return end
		local now = v.Value
		local s = suppress[b.id]
		if s ~= nil then
			suppress[b.id] = nil
			if s == now then return end
		end
		if recording then
			pending[#pending + 1] = { b.id, now and 1 or 0 }
		end
		if not now then pressAt[b.id] = nil end
	end

	local function bind(v)
		if conns[v] then return end
		local parent = v.Parent
		local key = keyOf(parent)
		if not key then return end
		local id = idForKey(key)
		local b = reg.byId[id]
		b.parent, b.pressed, b.timer = parent, v, nil
		conns[v] = v:GetPropertyChangedSignal("Value"):Connect(function() onPressedChanged(b) end)
	end

	local function unbind(v)
		local cn = conns[v]
		if cn then cn:Disconnect(); conns[v] = nil end
	end

	function B.Enable()
		if enabled then return end
		enabled = true
		descConn = workspace.DescendantAdded:Connect(function(inst)
			if inst.Name == "Pressed" then
				task.defer(function()
					if enabled and inst.Parent and isButtonValue(inst) then bind(inst) end
				end)
			end
		end)
		task.spawn(function()
			local list = workspace:GetDescendants()
			for i = 1, #list do
				if not enabled then return end
				local inst = list[i]
				if inst.Name == "Pressed" and isButtonValue(inst) then bind(inst) end
				if i % 2000 == 0 then task.wait() end
			end
		end)
	end

	function B.Disable()
		if not enabled then return end
		enabled = false
		if descConn then descConn:Disconnect(); descConn = nil end
		for v in pairs(conns) do unbind(v) end
		pressAt, pending, suppress = {}, {}, {}
		control, recording = "none", false
	end

	function B.IsEnabled() return enabled end
	function B.Count()
		local n = 0
		for _ in pairs(conns) do n = n + 1 end
		return n
	end

	local function setPressed(b, value)
		local v = b.pressed
		if not v or not v.Parent or v.Value == value then return end
		suppress[b.id] = value
		pcall(function() v.Value = value end)
	end

	-- keeps the kit's timer on the TAS clock (called every frame while a TAS is active)
	function B.Step(tNow)
		if not enabled or control == "none" then return end
		tNowCache = tNow or tNowCache
		local clock = os.clock()
		for id, t0 in pairs(pressAt) do
			local b = reg.byId[id]
			local v = b and b.pressed
			if v and v.Parent and v.Value then
				local timer = timerOf(b)
				if timer then
					local want = clock - (tNowCache - t0)
					if math.abs(timer.Value - want) > 0.0005 then
						pcall(function() timer.Value = want end)
					end
				end
			else
				pressAt[id] = nil
			end
		end
	end

	-- events of the frame that is being recorded. first = the TAS starts here (snapshot)
	function B.RecordFrame(tNow, first)
		if not enabled or not recording then
			pending = {}
			return nil
		end
		local out, seen = nil, nil
		if first then
			out = { { 0, 0, 0 } } -- id 0 = "button sync was on": buttons without events start released
			local clock = os.clock()
			for v, _ in pairs(conns) do
				if v.Parent and v.Value then
					local key = keyOf(v.Parent)
					local id = key and reg.byKey[key] and reg.byKey[key].id
					if id then
						local b = reg.byId[id]
						local timer = timerOf(b)
						local el = 0
						if timer and timer.Value > 0 then el = math.max(0, clock - timer.Value) end
						out[#out + 1] = { id, 1, el }
						pressAt[id] = tNow - el
					end
				end
			end
		end
		if #pending > 0 then
			out = out or {}
			seen = {}
			for i = #pending, 1, -1 do -- the last change of a button in this frame wins
				local e = pending[i]
				if not seen[e[1]] then
					seen[e[1]] = true
					out[#out + 1] = { e[1], e[2], 0 }
					if e[2] == 1 then pressAt[e[1]] = tNow else pressAt[e[1]] = nil end
				end
			end
			pending = {}
		end
		return out
	end

	function B.Invalidate() dataVersion = dataVersion + 1 end

	local function buildIndex(data)
		if idx and idxData == data and idxVer == dataVersion then return idx end
		idx = { snapshot = false, byId = {} }
		for f = 1, #data do
			local bt = data[f].BT
			if bt then
				for _, e in ipairs(bt) do
					if e[1] == 0 then
						idx.snapshot = true
					else
						local list = idx.byId[e[1]]
						if not list then list = {}; idx.byId[e[1]] = list end
						list[#list + 1] = { f, e[2], e[3] or 0 }
					end
				end
			end
		end
		idxData, idxVer = data, dataVersion
		return idx
	end

	-- state of every button at frame f, applied to the game
	local function seekTo(data, f)
		if not enabled then return end
		local ix = buildIndex(data)
		if not ix.snapshot and next(ix.byId) == nil then return end
		local tF = data[f] and data[f].TotalTime or 0
		for id, b in pairs(reg.byId) do
			if b.pressed and b.pressed.Parent then
				local list = ix.byId[id]
				local pressed, el = false, 0
				if list then
					-- last event at or before f (binary search)
					local lo, hi, best = 1, #list, nil
					while lo <= hi do
						local mid = math.floor((lo + hi) / 2)
						if list[mid][1] <= f then best = mid; lo = mid + 1 else hi = mid - 1 end
					end
					if best then
						local e = list[best]
						if e[2] == 1 then
							pressed = true
							el = e[3] + (tF - (data[e[1]] and data[e[1]].TotalTime or tF))
						end
					end
				elseif not ix.snapshot then
					pressed = nil -- unknown: this TAS has no button data for it
				end
				if pressed == true then
					setPressed(b, true)
					pressAt[id] = tF - el
				elseif pressed == false then
					setPressed(b, false)
					pressAt[id] = nil
				end
			end
		end
		tNowCache = tF
	end

	-- paused in Create mode on frame f
	function B.ShowFrame(data, f)
		if not enabled then return end
		recording = false
		pending = {}
		control = "paused"
		seekTo(data, f)
	end

	-- recording continues from frame f (unpause)
	function B.Resume(data, f)
		if not enabled then return end
		if f and f > 0 and data[f] then seekTo(data, f) end
		pending = {}
		recording = true
		control = "record"
	end

	function B.Pause(tNow)
		if not enabled then return end
		recording = false
		pending = {}
		control = "paused"
		tNowCache = tNow or tNowCache
	end

	function B.PlaybackBegin(data, f)
		if not enabled then return end
		recording = false
		pending = {}
		control = "test"
		applied = f
		seekTo(data, f)
	end

	-- apply recorded events of frames (applied, f]
	function B.PlaybackTo(data, f, t)
		if not enabled or control ~= "test" then return end
		if f < applied or f - applied > 600 then
			seekTo(data, f)
		else
			for i = applied + 1, f do
				local bt = data[i] and data[i].BT
				if bt then
					local tI = data[i].TotalTime or 0
					for _, e in ipairs(bt) do
						local b = e[1] ~= 0 and reg.byId[e[1]]
						if b then
							if e[2] == 1 then
								setPressed(b, true)
								pressAt[e[1]] = tI - (e[3] or 0)
							else
								setPressed(b, false)
								pressAt[e[1]] = nil
							end
						end
					end
				end
			end
		end
		applied = f
		B.Step(t)
	end

	-- back to normal play: the kit's timers continue in real time from where they are
	function B.Release()
		control, recording = "none", false
		pending, pressAt = {}, {}
	end

	function B.ExportKeys(frames)
		local set = {}
		for _, f in ipairs(frames) do
			if f.BT then
				for _, e in ipairs(f.BT) do
					if e[1] ~= 0 then set[e[1]] = true end
				end
			end
		end
		local list = {}
		for id in pairs(set) do
			local b = reg.byId[id]
			if b then list[#list + 1] = { id = id, key = b.key } end
		end
		table.sort(list, function(a, b2) return a.id < b2.id end)
		return list
	end

	function B.ImportKeys(frames, list)
		local map, changed = {}, false
		for _, o in ipairs(list) do
			local sid = idForKey(o.key)
			map[o.id] = sid
			if sid ~= o.id then changed = true end
		end
		if changed then
			for _, f in ipairs(frames) do
				if f.BT then
					for _, e in ipairs(f.BT) do
						if e[1] ~= 0 then e[1] = map[e[1]] or e[1] end
					end
				end
			end
		end
		B.Invalidate()
	end

	function B.Start()
		if Settings.On("Sync Button Timers") then B.Enable() end
		Settings.Changed("Sync Button Timers", function(v)
			if v ~= 0 then B.Enable() else B.Disable() end
		end)
		Janitor.add(function() B.Disable() end)
	end
end

