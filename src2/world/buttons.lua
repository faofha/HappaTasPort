-- ================================================================================================
--  BUTTONS  (HappaTAS 3 world plugin, order 55, "Sync Button Timers"): the EToH kit v6.1.3's timed buttons
--  on the TAS clock (V2.38.17 p14_buttons.lua 12-1811, function by function; only the frame access is new).
--  How the kit works (Repository/Interactables/Button): every button gets a BoolValue "Pressed" and a
--  NumberValue "TimerStart" next to its "ButtonPart". Pressing sets Pressed = true and TimerStart =
--  os.clock(); a Heartbeat loop releases the button when Timer - (os.clock() - TimerStart) <= 0.
--  HappaTAS saves every press / release with the frame it happened on (column v2BT: { { id, 1 / 0, time
--  already run } }), and while a TAS is active it writes TimerStart so the kit's timer follows the TAS
--  clock: frozen while paused, exact when scrubbing, on the TAS clock while testing. It also keeps the kit's
--  own timer labels and the button's look right meanwhile. Ids are saved with their workspace paths
--  (tl.meta.v2buttons) and translated on load.
-- ================================================================================================
local Env = import("platform/env")
local Players = Env.svc("Players")
local engine = nil -- (the engine, set by Buttons.new: the run a pause flushes into)

local B = {}
local reg = { byId = {}, byKey = {}, nextId = 1 }
local enabled = false
local descConn
local conns = setmetatable({}, { __mode = "k" }) -- BoolValue -> connection (destroyed values drop out)
local timerStartConns = setmetatable({}, { __mode = "k" })
local pending = {}
local recording = false
local pressAt = {}          -- id -> TAS time the current press started
local control = "none"      -- none | record | paused | test
local suppress = {}         -- id -> value HappaTAS just wrote (not a player action)
local suppressTimerStart = {}
local sharedRealTemplate = nil
local cachedContainers = nil
local lastContainerScan = 0
local cachedAdorneeGuis = nil
local lastAdorneeScan = 0
local lastCanTouchState = nil
local dirtyButtons = {}
local idx, idxData, idxVer, idxCount = nil, nil, -1, -1
local dataVersion = 0
local applied = 0           -- last frame applied during playback
local tNowCache = 0

local keyOfFn = nil -- (the client objects' path keys, set by Buttons.new)
local function keyOf(inst)
	return keyOfFn and keyOfFn(inst) or inst:GetFullName()
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

local function findConfig(inst)
	if not inst then return nil end
	return inst:FindFirstChild("ButtonConfiguration")
		or inst:FindFirstChild("Configurations")
		or inst:FindFirstChild("Configuration")
		or inst:FindFirstChildWhichIsA("Configuration")
		or inst:FindFirstChildWhichIsA("ModuleScript")
end
local function isGroupContainer(inst)
	if not inst or inst == workspace then return true end
	local n = inst.Name:lower()
	if n == "buttons" or n == "clientobjects" or n == "clientparts" or n == "mechanics" or n == "obstacles" then
		return true
	end
	if inst:IsA("Folder") then
		if inst:FindFirstChild("ButtonPart") or inst:FindFirstChild("ButtonConfiguration") or inst:FindFirstChild("Configuration") or inst:FindFirstChild("Pressed") then
			return false
		end
		return true
	end
	return false
end
local function getButtonInfo(v)
	if not (v and v:IsA("BoolValue") and v.Name == "Pressed") then return nil end
	local p = v.Parent
	if not p then return nil end
	if p:IsA("BasePart") then
		local m = (p.Parent and not isGroupContainer(p.Parent)) and p.Parent or p
		return m, p, findConfig(p) or (m ~= p and findConfig(m)) or nil
	end
	local bp = p:FindFirstChild("ButtonPart") or p:FindFirstChild("Button") or p:FindFirstChildWhichIsA("BasePart")
	if bp and bp:IsA("BasePart") then
		return p, bp, findConfig(p) or findConfig(bp)
	end
	local pp = p.Parent
	if pp and not isGroupContainer(pp) then
		bp = pp:FindFirstChild("ButtonPart") or pp:FindFirstChild("Button") or pp:FindFirstChildWhichIsA("BasePart")
		if bp and bp:IsA("BasePart") then
			return pp, bp, p
		end
		local bpNested = pp:FindFirstChild("ButtonPart", true) or pp:FindFirstChild("Button", true)
		if bpNested and bpNested:IsA("BasePart") then
			return pp, bpNested, p
		end
	end
	return nil
end

local function isButtonValue(v)
	local model, bp = getButtonInfo(v)
	return model ~= nil and bp ~= nil
end
local function hookTimerStart(b, ts)
	if not ts or timerStartConns[ts] then return end
	timerStartConns[ts] = ts:GetPropertyChangedSignal("Value"):Connect(function()
		if suppressTimerStart[b.id] then return end
		if control ~= "none" and pressAt[b.id] ~= nil and b.currentPressed then
			local rawEl = tNowCache - pressAt[b.id]
			if rawEl >= -0.001 then
				local want = os.clock() - math.max(0, rawEl)
				if math.abs(ts.Value - want) > 0.005 then
					suppressTimerStart[b.id] = true
					pcall(function() ts.Value = want end)
					suppressTimerStart[b.id] = nil
				end
			end
		end
	end)
end
local function setTimerStartValue(b, timerStart, val)
	if not timerStart then return end
	if math.abs(timerStart.Value - val) <= 0.001 then return end
	suppressTimerStart[b.id] = true
	pcall(function() timerStart.Value = val end)
	suppressTimerStart[b.id] = nil
end
local function getTimerValues(b)
	if b.timerValuesChecked and not b.needTimerStartRecheck then
		local ts = b.timerStart
		local dv = b.durationVal
		if (not ts or ts.Parent) and (not dv or dv.Parent) then
			return ts, dv, b.config
		end
	end
	b.timerValuesChecked = true
	b.needTimerStartRecheck = false
	local model = b.model or b.parent
	local config = b.config or findConfig(model)
	b.config = config
	local timerStart = b.timerStart
	if not (timerStart and timerStart.Parent) then
		timerStart = (config and config:FindFirstChild("TimerStart"))
			or (model and model:FindFirstChild("TimerStart"))
			or (b.parent and b.parent:FindFirstChild("TimerStart"))
			or (b.bp and b.bp:FindFirstChild("TimerStart"))
		if timerStart and timerStart:IsA("NumberValue") then
			b.timerStart = timerStart
			hookTimerStart(b, timerStart)
		else
			b.timerStart = nil
			timerStart = nil
		end
	end
	local durationVal = b.durationVal
	if not (durationVal and durationVal.Parent) then
		durationVal = (config and (config:FindFirstChild("Timer") or config:FindFirstChild("Duration") or config:FindFirstChild("Time")))
			or (model and (model:FindFirstChild("Timer") or model:FindFirstChild("Duration") or model:FindFirstChild("Time")))
			or (b.parent and (b.parent:FindFirstChild("Timer") or b.parent:FindFirstChild("Duration") or b.parent:FindFirstChild("Time")))
		if durationVal and (durationVal:IsA("NumberValue") or durationVal:IsA("IntValue")) then
			b.durationVal = durationVal
		else
			b.durationVal = nil
			durationVal = nil
		end
	end
	return timerStart, durationVal, config
end
local function isHideGUI(b)
	if b.hideGUI ~= nil then return b.hideGUI end
	local _, _, config = getTimerValues(b)
	local model = b.model or b.parent
	local h = (config and config:GetAttribute("HideGUI"))
		or (model and model:GetAttribute("HideGUI"))
		or (b.bp and b.bp:GetAttribute("HideGUI"))
	if h == true then
		b.hideGUI = true
		return true
	end
	local hv = (config and config:FindFirstChild("HideGUI")) or (model and model:FindFirstChild("HideGUI"))
	if hv and hv:IsA("BoolValue") and hv.Value == true then
		b.hideGUI = true
		return true
	end
	b.hideGUI = false
	return false
end
local function getButtonDuration(b)
	if b.cachedDuration ~= nil then return b.cachedDuration end
	local _, durationVal, config = getTimerValues(b)
	if durationVal and durationVal.Value > 0 then
		b.cachedDuration = durationVal.Value
		return durationVal.Value
	end
	local model = b.model or b.parent
	local attr = (config and (config:GetAttribute("Timer") or config:GetAttribute("Duration") or config:GetAttribute("Time")))
		or (model and (model:GetAttribute("Timer") or model:GetAttribute("Duration") or model:GetAttribute("Time")))
		or (b.parent and (b.parent:GetAttribute("Timer") or b.parent:GetAttribute("Duration") or b.parent:GetAttribute("Time")))
		or (b.bp and (b.bp:GetAttribute("Timer") or b.bp:GetAttribute("Duration") or b.bp:GetAttribute("Time")))
	if type(attr) == "number" and attr > 0 then
		b.cachedDuration = attr
		return attr
	end
	local mod = (config and config:IsA("ModuleScript") and config)
		or (model and model:FindFirstChildWhichIsA("ModuleScript"))
	if mod then
		local ok, res = pcall(require, mod)
		if ok and type(res) == "table" then
			local tm = res.Timer or res.Duration or res.Time
			if type(tm) == "number" and tm > 0 then
				b.cachedDuration = tm
				return tm
			end
		end
	end
	local tl = (config and config:FindFirstChildWhichIsA("TextLabel", true))
		or (model and model:FindFirstChildWhichIsA("TextLabel", true))
	if tl and tl.Text ~= "" then
		local num = tonumber(tl.Text:match("%d+%.?%d*"))
		if num and num > 0 and num <= 300 then
			b.cachedDuration = num
			return num
		end
	end
	b.cachedDuration = 0
	return 0
end
local CollectionService = Env.svc("CollectionService")
local function parseDigitKV(k, v)
	local nk = tostring(k):lower():gsub("[%s_%-]", "")
	if nk == "needdigits" or nk == "needsdigits" or nk == "needdigit" or nk == "threedigits" or nk == "3digits" then
		if v == true or v == 1 or tostring(v):lower() == "true" then return 3 end
		return tonumber(v)
	elseif nk == "twodigits" or nk == "2digits" or nk == "hundredths" or nk == "showhundredths" then
		if v == true or v == 1 or tostring(v):lower() == "true" then return 2 end
		return tonumber(v)
	elseif nk == "onedigit" or nk == "1digit" or nk == "tenths" then
		if v == true or v == 1 or tostring(v):lower() == "true" then return 1 end
		return tonumber(v)
	elseif nk == "nodecimals" or nk == "nodigits" or nk == "wholenumbers" or nk == "integer" then
		if v == true or v == 1 or tostring(v):lower() == "true" then return 0 end
	elseif nk:find("digit") or nk:find("decimal") or nk == "precision" or nk == "places" or nk == "rounding" then
		if v == true or tostring(v):lower() == "true" then return 2 end
		if type(v) == "number" then return v end
		if type(v) == "string" then
			local fmtD = v:match("%%%.(%d+)f")
			if fmtD then return tonumber(fmtD) end
			local dotD = v:match("^%d*%.(%d+)$")
			if dotD then return #dotD end
			return tonumber(v)
		end
	end
	return nil
end
local function learnFormatFromGameText(b, txt)
	if type(txt) ~= "string" or txt == "" then return false end
	local intStr, decStr = txt:match("(%d+)%.(%d+)")
	if not decStr then return false end
	local nDec = #decStr
	if nDec < 1 or nDec > 4 then return false end
	local intVal = tonumber(intStr) or 0
	local changed = false
	if intVal == 0 then
		if b.subSecDecimals ~= nDec then
			b.subSecDecimals = nDec
			changed = true
		end
	else
		if b.aboveSecDecimals ~= nDec then
			b.aboveSecDecimals = nDec
			changed = true
		end
	end
	if b.liveDecimals ~= nDec then
		b.liveDecimals = nDec
		changed = true
	end
	if changed then
		b.lastRemQ = nil
		b.lastFormatted = nil
	end
	return changed
end
local function getDigitsProperty(b)
	if b.configDecimals ~= nil then return b.configDecimals ~= false and b.configDecimals or nil end
	local bp, model = b.bp, b.model or b.parent
	local config = b.config or findConfig(model)
	local function checkInstance(inst, deep)
		if not inst then return nil end
		local decAttr = inst:GetAttribute("TimerDecimalPlaces") or inst:GetAttribute("DecimalPlaces") or inst:GetAttribute("Digits") or inst:GetAttribute("Decimals")
		if type(decAttr) == "number" then return decAttr end
		local okAttr, attrs = pcall(inst.GetAttributes, inst)
		if okAttr and type(attrs) == "table" then
			for k, v in pairs(attrs) do
				local d = parseDigitKV(k, v)
				if d ~= nil then return d end
			end
		end
		local list = deep and inst:GetDescendants() or inst:GetChildren()
		for _, ch in ipairs(list) do
			if ch:IsA("ValueBase") then
				local d = parseDigitKV(ch.Name, ch.Value)
				if d ~= nil then return d end
			end
		end
		if CollectionService then
			for _, tag in ipairs({ "NeedDigits", "NeedsDigits", "3Digits", "ThreeDigits", "Digits" }) do
				local ok, has = pcall(CollectionService.HasTag, CollectionService, inst, tag)
				if ok and has then return 3 end
			end
			for _, tag in ipairs({ "2Digits", "TwoDigits", "Hundredths" }) do
				local ok, has = pcall(CollectionService.HasTag, CollectionService, inst, tag)
				if ok and has then return 2 end
			end
		end
		return nil
	end
	local d = checkInstance(b.pressed, false)
		or checkInstance(config, true)
		or checkInstance(bp, true)
		or (model and not isGroupContainer(model) and checkInstance(model, true))
	if d == nil and b.parent and b.parent ~= model and b.parent ~= config and not isGroupContainer(b.parent) then
		d = checkInstance(b.parent, true)
	end
	if d == nil and model and model.Parent and model.Parent ~= workspace then
		d = checkInstance(model.Parent, false)
	end
	if d ~= nil then
		b.configDecimals = d
		return d
	end
	local mod = (config and config:IsA("ModuleScript") and config) or (model and not isGroupContainer(model) and model:FindFirstChildWhichIsA("ModuleScript", true))
	if mod then
		local ok, res = pcall(require, mod)
		if ok and type(res) == "table" then
			for k, v in pairs(res) do
				local dv = parseDigitKV(k, v)
				if dv ~= nil then
					b.configDecimals = dv
					return dv
				end
			end
		end
	end
	local dur = getButtonDuration(b)
	if dur and dur > 0 then
		local s = string.format("%.4f", dur):gsub("0+$", ""):gsub("%.$", "")
		local frac = s:match("%.(%d+)")
		if frac and #frac >= 2 then
			b.configDecimals = #frac
			return #frac
		end
	end
	local bestTlDec = nil
	local function scanLabelsForDec(root)
		if not root or isGroupContainer(root) then return end
		for _, dInst in ipairs(root:GetDescendants()) do
			if dInst:IsA("TextLabel") and dInst.Text ~= "" then
				local decs = dInst.Text:match("%d+%.(%d+)")
				if decs and #decs >= 2 and #decs <= 4 then
					if not bestTlDec or #decs > bestTlDec then bestTlDec = #decs end
				end
			end
		end
	end
	scanLabelsForDec(config)
	scanLabelsForDec(bp)
	if model ~= bp then scanLabelsForDec(model) end
	if bestTlDec then
		b.configDecimals = bestTlDec
		return bestTlDec
	end
	b.configDecimals = false
	return nil
end
local function getEffectiveDecimals(b, remaining)
	if remaining ~= nil then
		if remaining < 1 and b.subSecDecimals ~= nil then return b.subSecDecimals end
		if remaining >= 1 and b.aboveSecDecimals ~= nil then return b.aboveSecDecimals end
	end
	if b.liveDecimals ~= nil then return b.liveDecimals end
	local cfgD = getDigitsProperty(b)
	if cfgD ~= nil then return math.max(0, math.floor(cfgD)) end
	if remaining ~= nil and remaining < 1 and b.subSecDecimals ~= nil then return b.subSecDecimals end
	return 1
end
local function formatTimer(b, remaining, forceDec)
	local dec = forceDec or getEffectiveDecimals(b, remaining)
	local strVal = b.timerText
	if strVal == nil then
		local model = b.model or b.parent
		local config = b.config or findConfig(model)
		local attr = (config and config:GetAttribute("TimerText"))
			or (model and model:GetAttribute("TimerText"))
			or (b.bp and b.bp:GetAttribute("TimerText"))
		if type(attr) == "string" then
			strVal = attr
		else
			local tv = (config and config:FindFirstChild("TimerText")) or (model and model:FindFirstChild("TimerText"))
			if tv and tv:IsA("StringValue") then
				strVal = tv.Value
			else
				local mod = (config and config:IsA("ModuleScript") and config) or (model and model:FindFirstChildWhichIsA("ModuleScript"))
				if mod then
					local ok, res = pcall(require, mod)
					if ok and type(res) == "table" and type(res.TimerText) == "string" then
						strVal = res.TimerText
					end
				end
			end
		end
		strVal = strVal or "{T}"
		b.timerText = strVal
	end
	local rem = math.max(0, remaining)
	local displayTime = (dec == 0) and tostring(math.ceil(rem)) or string.format("%." .. tostring(dec) .. "f", rem)
	if strVal == "" or strVal == "{T}" then
		return displayTime
	end
	local flooredSeconds = math.floor(rem)
	local mins = math.floor(flooredSeconds / 60)
	local secs = flooredSeconds % 60
	local ms = math.floor(rem * 100) % 100
	local lp = Players.LocalPlayer
	local pName = lp and lp.Name or ""
	local pDisp = lp and lp.DisplayName or pName
	local pUid = lp and tostring(lp.UserId) or "0"
	local res = strVal:gsub("{T}", displayTime)
		:gsub("{M}", tostring(mins))
		:gsub("{SM}", (tostring(mins) == "1") and "" or "s")
		:gsub("{S}", string.format("%02i", secs))
		:gsub("{MS}", string.format("%02i", ms))
		:gsub("{SS}", (displayTime == "1") and "" or "s")
		:gsub("{pn}", pName:lower())
		:gsub("{Pn}", pName)
		:gsub("{PN}", pName:upper())
		:gsub("{dn}", pDisp:lower())
		:gsub("{Dn}", pDisp)
		:gsub("{DN}", pDisp:upper())
		:gsub("{UID}", pUid)
	return res
end
local function colorClose(c1, c2, tol)
	if not c1 or not c2 then return false end
	local t = tol or 0.08
	return math.abs(c1.R - c2.R) < t and math.abs(c1.G - c2.G) < t and math.abs(c1.B - c2.B) < t
end
local function applyRealButtonColors(lbl, bpColor, isAlreadyStyledForButton)
	if not (lbl and bpColor) or isAlreadyStyledForButton then return end
	local okTag, special = pcall(function() return lbl:HasTag("UseSpecialColor") end)
	if okTag and special then return end
	local invColor = Color3.new(1 - bpColor.R, 1 - bpColor.G, 1 - bpColor.B)
	local oldColor = lbl.TextColor3
	local oldInv = oldColor and Color3.new(1 - oldColor.R, 1 - oldColor.G, 1 - oldColor.B)
	lbl.TextColor3 = bpColor
	lbl.TextStrokeColor3 = invColor
	local stroke = lbl:FindFirstChildWhichIsA("UIStroke")
	if stroke then
		if oldInv and colorClose(stroke.Color, oldInv, 0.08) then
			stroke.Color = invColor
		elseif oldColor and colorClose(stroke.Color, oldColor, 0.08) then
			stroke.Color = bpColor
		end
	end
end
local function stripScripts(inst)
	if not inst then return end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then pcall(function() d:Destroy() end) end
	end
end
local function cacheTemplateFromLabel(b, lbl, isLiveForThisButton)
	if not (lbl and lbl:IsA("TextLabel")) then return end
	if lbl:GetAttribute("HappaTASFake") then return end
	if b.realTemplate and (b.realTemplateFromLive or not isLiveForThisButton) then return end
	pcall(function()
		local cl = lbl:Clone()
		stripScripts(cl)
		cl:SetAttribute("HappaTASButton", nil)
		cl:SetAttribute("HappaTASFake", nil)
		b.realTemplate = cl
		b.realTemplateFromLive = isLiveForThisButton and true or false
		if not sharedRealTemplate then
			local scl = cl:Clone()
			sharedRealTemplate = scl
		end
	end)
end
local function getAllTimerContainers()
	if cachedContainers and #cachedContainers > 0 then
		local allValid = true
		for i = 1, #cachedContainers do
			if not cachedContainers[i].Parent then
				allValid = false
				break
			end
		end
		if allValid then return cachedContainers end
	end
	local now = os.clock()
	if cachedContainers and now - lastContainerScan < 0.5 then
		return cachedContainers
	end
	lastContainerScan = now
	local containers = {}
	local lp = Players.LocalPlayer
	local pg = lp and lp:FindFirstChild("PlayerGui")
	if not pg then
		cachedContainers = containers
		return containers
	end
	local function addContainer(c)
		if not (c and c:IsA("GuiObject")) then return end
		for i = 1, #containers do
			if containers[i] == c then return end
		end
		containers[#containers + 1] = c
	end
	local function checkGuiDirect(gui)
		if not (gui and gui.Parent) then return end
		addContainer(gui:FindFirstChild("TimerList"))
		addContainer(gui:FindFirstChild("Timers"))
		addContainer(gui:FindFirstChild("TimerContainer"))
		addContainer(gui:FindFirstChild("TimerFrame"))
	end
	for _, name in ipairs({ "EffectGUI", "EffectGui", "EffectsGui", "EffectsGUI" }) do
		local eg = pg:FindFirstChild(name)
		if eg then checkGuiDirect(eg) end
	end
	if #containers == 0 then
		for _, ch in ipairs(pg:GetChildren()) do
			if ch:IsA("ScreenGui") and ch.Name ~= "TASUserInterface" and ch.Name ~= "HappaProfiler" and ch.Name ~= "HappaCursor" then
				checkGuiDirect(ch)
				if #containers == 0 then
					local tl = ch:FindFirstChild("TimerList", true) or ch:FindFirstChild("Timers", true)
					if tl then addContainer(tl) end
				end
			end
		end
	end
	cachedContainers = containers
	return containers
end
local function getTimerList(createIfMissing)
	local containers = getAllTimerContainers()
	if #containers > 0 then return containers[1] end
	if not createIfMissing then return nil end
	local lp = Players.LocalPlayer
	local pg = lp and lp:FindFirstChild("PlayerGui")
	if not pg then return nil end
	local eg = pg:FindFirstChild("EffectGUI") or pg:FindFirstChild("EffectGui") or pg:FindFirstChild("EffectsGui")
	if eg then
		local newTl = eg:FindFirstChild("TimerList")
		if not newTl then
			newTl = Instance.new("Frame")
			newTl.Name = "TimerList"
			newTl.BackgroundTransparency = 1
			newTl.Size = UDim2.new(0, 300, 0, 80)
			newTl.Position = UDim2.new(0.5, -150, 0, 15)
			newTl.Parent = eg
		end
		cachedContainers = { newTl }
		return newTl
	end
	return nil
end
local function findTemplateForButton(b)
	if b.realTemplate then return b.realTemplate, b.realTemplateFromLive end
	local model = b.model or b.parent
	local config = b.config or findConfig(model)
	local tl = (config and config:FindFirstChildWhichIsA("TextLabel", true))
		or (model and model:FindFirstChildWhichIsA("TextLabel", true))
	if tl then
		cacheTemplateFromLabel(b, tl, false)
		return b.realTemplate or tl, false
	end
	local bp = b.bp
	if bp and bp.Parent then
		for _, ch in ipairs(bp:GetChildren()) do
			if ch:IsA("SurfaceGui") or ch:IsA("BillboardGui") then
				local gtl = ch:FindFirstChildWhichIsA("TextLabel")
				if gtl and not gtl:GetAttribute("HappaTASFake") then
					cacheTemplateFromLabel(b, gtl, true)
					return b.realTemplate or gtl, true
				end
			end
		end
	end
	if sharedRealTemplate then return sharedRealTemplate, false end
	for _, otherB in pairs(reg.byId) do
		if otherB.realTemplate then
			sharedRealTemplate = otherB.realTemplate
			return otherB.realTemplate, false
		end
		local oc = otherB.config or findConfig(otherB.model or otherB.parent)
		local otl = oc and oc:FindFirstChildWhichIsA("TextLabel", true)
		if otl then
			cacheTemplateFromLabel(otherB, otl, false)
			return otherB.realTemplate or otl, false
		end
	end
	return nil, false
end
local function matchesOtherActiveButton(b, lblColor, candidateLbl)
	if not lblColor then return false end
	for otherId, _ in pairs(pressAt) do
		if otherId ~= b.id then
			local otherB = reg.byId[otherId]
			if otherB and (otherB.currentPressed or (otherB.pressed and otherB.pressed.Value)) then
				local oc = otherB.unpressedColor or (otherB.bp and otherB.bp.Color)
				if oc and colorClose(lblColor, oc, 0.08) then
					local oLbl = otherB.screenLabel
					if not (oLbl and oLbl.Parent and oLbl ~= candidateLbl and not oLbl:GetAttribute("HappaTASFake")) then
						return true
					end
				end
			end
		end
	end
	return false
end
local function getScreenLabel(b, createIfMissing)
	if isHideGUI(b) then return nil end
	if control == "none" then
		createIfMissing = false
	end
	local now = os.clock()
	local cur = b.screenLabel
	local recentRealPress = b.realPressClock and (now - b.realPressClock) < 0.35
	if cur and cur.Parent then
		local interval = (cur == b.ourScreenLabel) and (recentRealPress and 0.08 or 0.25) or 0.2
		if b.lastScreenScan and (now - b.lastScreenScan) < interval then
			return cur
		end
	elseif b.lastScreenScan and (now - b.lastScreenScan) < (recentRealPress and 0.05 or 0.2) then
		return nil
	end
	b.lastScreenScan = now
	local bp = b.bp
	local bpColor = b.unpressedColor or (bp and bp.Color)
	local curBpColor = bp and bp.Color
	local invColor = bpColor and Color3.new(1 - bpColor.R, 1 - bpColor.G, 1 - bpColor.B)
	local containers = getAllTimerContainers()
	local bestReal = nil
	local bestRealScore = 0
	local realMatches = {}
	local fakeDuplicates = {}
	local otherTimerInList = nil
	local function scoreLabel(lbl, containerEntry)
		if not (lbl and lbl:IsA("TextLabel") and lbl.Parent) then return end
		local isFake = lbl:GetAttribute("HappaTASFake") == true
		local attrId = lbl:GetAttribute("HappaTASButton") or (containerEntry and containerEntry:GetAttribute("HappaTASButton"))
		if attrId ~= nil and attrId ~= b.id then
			if not isFake then otherTimerInList = otherTimerInList or lbl end
			return
		end
		if isFake then
			if attrId == b.id or lbl == b.ourScreenLabel then
				fakeDuplicates[#fakeDuplicates + 1] = lbl
			end
			return
		end
		otherTimerInList = otherTimerInList or lbl
		local colorMatched = false
		local score = 0
		if bpColor then
			if colorClose(lbl.TextColor3, bpColor, 0.08) or (curBpColor and colorClose(lbl.TextColor3, curBpColor, 0.08)) then
				colorMatched = true
				score = score + 300
				if invColor and colorClose(lbl.TextStrokeColor3, invColor, 0.08) then
					score = score + 100
				end
			elseif invColor and colorClose(lbl.TextStrokeColor3, invColor, 0.08) then
				colorMatched = true
				score = score + 200
			elseif not matchesOtherActiveButton(b, lbl.TextColor3, lbl) then
				score = score + 80
			end
		else
			colorMatched = true
			score = score + 100
		end
		local ownedByB = (attrId == b.id) or (attrId == nil and colorMatched and not matchesOtherActiveButton(b, lbl.TextColor3, lbl))
		if ownedByB then
			realMatches[#realMatches + 1] = { lbl = lbl, entry = containerEntry }
			score = score + 1000 + #realMatches * 10
			if lbl.TextTransparency < 0.5 then
				score = score + 500
			end
		elseif lbl == b.screenLabel then
			score = score + 600
		end
		if score >= bestRealScore and score > 0 then
			bestRealScore = score
			bestReal = lbl
		end
	end
	for _, container in ipairs(containers) do
		for _, ch in ipairs(container:GetChildren()) do
			if ch:IsA("TextLabel") then
				scoreLabel(ch, ch)
			elseif ch:IsA("GuiObject") then
				local nested = ch:FindFirstChildWhichIsA("TextLabel")
				if nested then scoreLabel(nested, ch) end
			end
		end
	end
	if bestReal then
		for _, m in ipairs(realMatches) do
			if m.lbl ~= bestReal and m.lbl.Parent then
				pcall(function()
					if m.entry and m.entry ~= m.lbl and m.entry.Parent and m.entry.Name ~= "TimerList" and m.entry.Name ~= "Timers" then
						m.entry:Destroy()
					else
						m.lbl:Destroy()
					end
				end)
			end
		end
		for _, fk in ipairs(fakeDuplicates) do
			if fk.Parent then pcall(function() fk:Destroy() end) end
		end
		if b.ourScreenLabel and b.ourScreenLabel.Parent then
			pcall(function() b.ourScreenLabel:Destroy() end)
		end
		b.ourScreenLabel = nil
		cacheTemplateFromLabel(b, bestReal, true)
		if (b.currentPressed or (b.pressed and b.pressed.Value)) and bestReal.Text ~= "" and bestReal.Text ~= b.lastFormatted then
			learnFormatFromGameText(b, bestReal.Text)
		end
		if bestReal:GetAttribute("HappaTASButton") ~= b.id then
			pcall(function()
				bestReal:SetAttribute("HappaTASButton", b.id)
				if bestReal.Parent and bestReal.Parent:IsA("GuiObject") and bestReal.Parent.Name ~= "TimerList" and bestReal.Parent.Name ~= "Timers" then
					bestReal.Parent:SetAttribute("HappaTASButton", b.id)
				end
			end)
		end
		b.screenLabel = bestReal
		return bestReal
	end
	if b.ourScreenLabel and b.ourScreenLabel.Parent then
		for _, fk in ipairs(fakeDuplicates) do
			if fk ~= b.ourScreenLabel and fk.Parent then
				pcall(function() fk:Destroy() end)
			end
		end
		b.screenLabel = b.ourScreenLabel
		return b.ourScreenLabel
	end
	b.ourScreenLabel = nil
	b.screenLabel = nil
	if not createIfMissing or control == "none" then
		return nil
	end
	if b.reasserting or (b.pressed and b.pressed.Value and b.realPressClock and (now - b.realPressClock) < 0.2) then
		return nil
	end
	local tList = getTimerList(true)
	if not tList then return nil end
	local template, isLiveForThisButton = findTemplateForButton(b)
	if not template and otherTimerInList then
		template = otherTimerInList
		isLiveForThisButton = false
	end
	local newLabel
	if template then
		newLabel = template:Clone()
		newLabel.Visible = true
		applyRealButtonColors(newLabel, bpColor, isLiveForThisButton)
	else
		newLabel = Instance.new("TextLabel")
		newLabel.Name = "TimerLabel"
		newLabel.BackgroundTransparency = 1
		newLabel.Size = UDim2.new(1, 0, 0.2, 0)
		pcall(function()
			newLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal)
		end)
		newLabel.TextScaled = true
		newLabel.TextSize = 42
		newLabel.TextStrokeTransparency = 0
		applyRealButtonColors(newLabel, bpColor, false)
	end
	newLabel:SetAttribute("HappaTASButton", b.id)
	newLabel:SetAttribute("HappaTASFake", true)
	newLabel.Parent = tList
	b.screenLabel = newLabel
	b.ourScreenLabel = newLabel
	return newLabel
end
local labelTextConns = setmetatable({}, { __mode = "k" })
local suppressLabelText = setmetatable({}, { __mode = "k" })
local function syncPartLabelVisual(lbl, formatted)
	if not (lbl and lbl.Parent) then return end
	if lbl.Text ~= formatted then
		suppressLabelText[lbl] = true
		pcall(function() lbl.Text = formatted end)
		suppressLabelText[lbl] = nil
	end
	if not lbl.Visible then pcall(function() lbl.Visible = true end) end
	if lbl.TextTransparency > 0.5 then pcall(function() lbl.TextTransparency = 0 end) end
	local gui = lbl:FindFirstAncestorWhichIsA("LayerCollector")
	if gui and (gui:IsA("SurfaceGui") or gui:IsA("BillboardGui")) and not gui.Enabled then
		pcall(function() gui.Enabled = true end)
	end
end
local function hookLabelText(b, lbl)
	if not lbl or labelTextConns[lbl] then return end
	if not lbl:GetAttribute("HappaTASFake") and (b.currentPressed or (b.pressed and b.pressed.Value)) and lbl.Text ~= "" and lbl.Text ~= b.lastFormatted then
		learnFormatFromGameText(b, lbl.Text)
	end
	labelTextConns[lbl] = lbl:GetPropertyChangedSignal("Text"):Connect(function()
		if suppressLabelText[lbl] then return end
		local gameTxt = lbl.Text
		if not lbl:GetAttribute("HappaTASFake") and (b.currentPressed or (b.pressed and b.pressed.Value) or control == "none") then
			if learnFormatFromGameText(b, gameTxt) and control ~= "none" and b.currentPressed and pressAt[b.id] ~= nil then
				local dur = getButtonDuration(b)
				if dur > 0 then
					local rem = math.max(0, dur - math.max(0, tNowCache - pressAt[b.id]))
					local dec = getEffectiveDecimals(b, rem)
					b.lastUsedDec = dec
					b.lastRemQ = math.floor(rem * (10 ^ dec) + 0.5)
					b.lastFormatted = formatTimer(b, rem, dec)
					local sLbl = b.screenLabel
					if sLbl and sLbl.Parent and sLbl ~= lbl then
						suppressLabelText[sLbl] = true
						pcall(function() sLbl.Text = b.lastFormatted end)
						suppressLabelText[sLbl] = nil
					end
					local pLbls = b.partLabels
					if pLbls then
						for i = 1, #pLbls do
							if pLbls[i] ~= lbl then syncPartLabelVisual(pLbls[i], b.lastFormatted) end
						end
					end
				end
			end
		end
		if control ~= "none" then
			if b.currentPressed and b.lastFormatted then
				if lbl.Text ~= b.lastFormatted then
					suppressLabelText[lbl] = true
					pcall(function() lbl.Text = b.lastFormatted end)
					suppressLabelText[lbl] = nil
				end
				if not lbl.Visible then pcall(function() lbl.Visible = true end) end
			elseif not b.currentPressed and lbl ~= b.screenLabel then
				if lbl.Visible then pcall(function() lbl.Visible = false end) end
			end
		end
	end)
end
local function getAdorneeGuis()
	local now = os.clock()
	if cachedAdorneeGuis and (now - lastAdorneeScan) < 0.5 then
		return cachedAdorneeGuis
	end
	lastAdorneeScan = now
	local list = {}
	local lp = Players.LocalPlayer
	local pg = lp and lp:FindFirstChild("PlayerGui")
	if pg then
		for _, d in ipairs(pg:GetDescendants()) do
			if (d:IsA("SurfaceGui") or d:IsA("BillboardGui")) and d.Adornee ~= nil then
				list[#list + 1] = d
			end
		end
	end
	cachedAdorneeGuis = list
	return list
end
local function getPartLabels(b, createIfMissing)
	local now = os.clock()
	local cached = b.partLabels
	local recentP = b.realPressClock and (now - b.realPressClock) < 0.35
	if cached and #cached > 0 then
		local allValid = true
		for i = 1, #cached do
			if not cached[i].Parent then
				allValid = false
				break
			end
		end
		if allValid then
			local interval = b.ourPartGui and (recentP and 0.08 or 0.25) or 0.25
			if b.lastPartScan and (now - b.lastPartScan) < interval then
				return cached
			end
		end
	elseif cached and #cached == 0 and b.lastPartScan and (now - b.lastPartScan) < (recentP and 0.05 or 0.25) then
		return cached
	end
	b.lastPartScan = now
	local list = {}
	local seen = {}
	local realGuis = {}
	local seenGuis = {}
	local bp = b.bp
	local model = b.model or b.parent
	local config = b.config
	local function isConfigTemplate(inst)
		if not inst or not config or config == bp or config == model then return false end
		return inst:IsDescendantOf(config)
	end
	local function addLabel(lbl)
		if lbl and lbl:IsA("TextLabel") and not seen[lbl] and lbl.Parent then
			if lbl:GetAttribute("HappaTASFake") or isConfigTemplate(lbl) then return end
			seen[lbl] = true
			list[#list + 1] = lbl
			hookLabelText(b, lbl)
			cacheTemplateFromLabel(b, lbl, true)
		end
	end
	local function addGui(gui)
		if not (gui and (gui:IsA("SurfaceGui") or gui:IsA("BillboardGui")) and gui.Parent) then return end
		if gui:GetAttribute("HappaTASFake") or seenGuis[gui] or isConfigTemplate(gui) then return end
		seenGuis[gui] = true
		realGuis[#realGuis + 1] = gui
		if not b.realPartGuiTemplate then
			pcall(function()
				local cl = gui:Clone()
				stripScripts(cl)
				b.realPartGuiTemplate = cl
			end)
		end
		for _, d in ipairs(gui:GetDescendants()) do
			if d:IsA("TextLabel") then addLabel(d) end
		end
	end
	local function scanRoot(root)
		if not (root and root.Parent) or isGroupContainer(root) then return end
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
				addGui(d)
			elseif d:IsA("TextLabel") then
				addLabel(d)
			end
		end
	end
	scanRoot(bp)
	if model and model ~= bp and not isGroupContainer(model) then scanRoot(model) end
	if b.parent and b.parent ~= model and b.parent ~= bp and b.parent ~= config and not isGroupContainer(b.parent) then
		scanRoot(b.parent)
	end
	if bp or (model and not isGroupContainer(model)) then
		for _, gui in ipairs(getAdorneeGuis()) do
			if gui.Parent then
				local ad = gui.Adornee
				if ad and (ad == bp or ad == model or (model and not isGroupContainer(model) and ad:IsDescendantOf(model))) then
					addGui(gui)
				end
			end
		end
	end
	if #list > 0 then
		if b.ourPartGui and b.ourPartGui.Parent then
			pcall(function() b.ourPartGui:Destroy() end)
		end
		b.ourPartGui = nil
		b.partLabels = list
		return list
	end
	if b.ourPartGui and b.ourPartGui.Parent then
		local fakeLabels = {}
		for _, d in ipairs(b.ourPartGui:GetDescendants()) do
			if d:IsA("TextLabel") then
				hookLabelText(b, d)
				fakeLabels[#fakeLabels + 1] = d
			end
		end
		if #fakeLabels > 0 then
			b.partLabels = fakeLabels
			return b.partLabels
		end
	end
	b.ourPartGui = nil
	if not b.realPartGuiTemplate and config and config ~= bp then
		local cfgGui = config:FindFirstChildWhichIsA("SurfaceGui", true) or config:FindFirstChildWhichIsA("BillboardGui", true)
		if cfgGui then
			pcall(function()
				local cl = cfgGui:Clone()
				stripScripts(cl)
				b.realPartGuiTemplate = cl
			end)
		end
	end
	if createIfMissing and control ~= "none" and bp and bp.Parent and b.realPartGuiTemplate then
		if not (b.reasserting or (b.pressed and b.pressed.Value and b.realPressClock and (now - b.realPressClock) < 0.2)) then
			local sgui = b.realPartGuiTemplate:Clone()
			stripScripts(sgui)
			sgui.Enabled = true
			sgui:SetAttribute("HappaTASFake", true)
			sgui:SetAttribute("HappaTASButton", b.id)
			local fakeLabels = {}
			for _, d in ipairs(sgui:GetDescendants()) do
				if d:IsA("TextLabel") then
					d.Visible = true
					d:SetAttribute("HappaTASFake", true)
					d:SetAttribute("HappaTASButton", b.id)
					hookLabelText(b, d)
					fakeLabels[#fakeLabels + 1] = d
				end
			end
			sgui.Parent = bp
			b.ourPartGui = sgui
			b.partLabels = fakeLabels
			return b.partLabels
		end
	end
	b.partLabels = list
	return list
end
local function updateTimerUI(b, remaining, allowCreate)
	if control == "none" then return end
	local canCreate = allowCreate == true and control ~= "none"
	local sLabel = (not isHideGUI(b)) and getScreenLabel(b, canCreate) or nil
	if sLabel and sLabel.Parent then hookLabelText(b, sLabel) end
	local pLabels = getPartLabels(b, canCreate)
	local dec = getEffectiveDecimals(b, remaining)
	local scale = 10 ^ dec
	local remQ = math.floor(math.max(0, remaining) * scale + 0.5)
	local formatted = b.lastFormatted
	if remQ ~= b.lastRemQ or dec ~= b.lastUsedDec or not formatted then
		b.lastRemQ = remQ
		b.lastUsedDec = dec
		formatted = formatTimer(b, remaining, dec)
		b.lastFormatted = formatted
	end
	if sLabel and sLabel.Parent then
		if sLabel.Text ~= formatted then
			suppressLabelText[sLabel] = true
			pcall(function() sLabel.Text = formatted end)
			suppressLabelText[sLabel] = nil
		end
		if not sLabel.Visible then pcall(function() sLabel.Visible = true end) end
	end
	for i = 1, #pLabels do
		syncPartLabelVisual(pLabels[i], formatted)
	end
end
local function hideTimerUI(b)
	if b.ourScreenLabel and b.ourScreenLabel.Parent then
		pcall(function() b.ourScreenLabel:Destroy() end)
	end
	b.ourScreenLabel = nil
	if b.ourPartGui and b.ourPartGui.Parent then
		pcall(function() b.ourPartGui:Destroy() end)
	end
	b.ourPartGui = nil
	local bp = b.bp
	local bpColor = b.unpressedColor or (bp and bp.Color)
	local containers = getAllTimerContainers()
	for _, c in ipairs(containers) do
		for _, ch in ipairs(c:GetChildren()) do
			if ch:GetAttribute("HappaTASFake") and (ch:GetAttribute("HappaTASButton") == b.id or (bpColor and colorClose(ch.TextColor3, bpColor, 0.08))) then
				pcall(function() ch:Destroy() end)
			elseif ch:GetAttribute("HappaTASButton") == b.id or ch == b.screenLabel or (ch:IsA("TextLabel") and bpColor and colorClose(ch.TextColor3, bpColor, 0.08) and not matchesOtherActiveButton(b, ch.TextColor3)) then
				if ch.Visible then pcall(function() ch.Visible = false end) end
			elseif ch:IsA("GuiObject") then
				local lbl = ch:FindFirstChildWhichIsA("TextLabel")
				if lbl and (lbl:GetAttribute("HappaTASButton") == b.id or (bpColor and colorClose(lbl.TextColor3, bpColor, 0.08) and not matchesOtherActiveButton(b, lbl.TextColor3))) then
					if lbl:GetAttribute("HappaTASFake") then
						pcall(function() ch:Destroy() end)
					elseif lbl.Visible then
						pcall(function() lbl.Visible = false end)
					end
				end
			end
		end
	end
	b.screenLabel = nil
	local pLabels = b.partLabels
	if pLabels then
		for i = 1, #pLabels do
			local lbl = pLabels[i]
			if lbl and lbl.Parent then
				if lbl.Visible then pcall(function() lbl.Visible = false end) end
			end
		end
	end
	if bp and bp.Parent then
		for _, ch in ipairs(bp:GetChildren()) do
			if ch:IsA("SurfaceGui") or ch:IsA("BillboardGui") then
				if ch:GetAttribute("HappaTASFake") then
					pcall(function() ch:Destroy() end)
				else
					for _, gch in ipairs(ch:GetChildren()) do
						if gch:IsA("TextLabel") and gch.Visible then
							pcall(function() gch.Visible = false end)
						end
					end
				end
			end
		end
	end
	b.partLabels = nil
end
local function getPressedMaterial(b)
	if b.pressedMaterial then return b.pressedMaterial end
	local config = b.config
	local pm = config and config:GetAttribute("PressedMaterial")
	if typeof(pm) == "EnumItem" and pm.EnumType == Enum.Material then
		b.pressedMaterial = pm
		return pm
	elseif type(pm) == "string" then
		local ok, mat = pcall(function() return Enum.Material[pm] end)
		if ok and mat then
			b.pressedMaterial = mat
			return mat
		end
	end
	b.pressedMaterial = Enum.Material.Neon
	return Enum.Material.Neon
end
local function restoreButtonVisual(b, isPressed)
	local bp = b.bp
	if bp and bp.Parent then
		if isPressed then
			local wantMat = getPressedMaterial(b)
			if wantMat and bp.Material ~= wantMat then
				pcall(function() bp.Material = wantMat end)
			end
			if b.pressedCF and not (b.pressed and b.pressed.Value) then
				if (bp.Position - b.pressedCF.Position).Magnitude > 0.01 then
					pcall(function() bp.CFrame = b.pressedCF end)
				end
			end
		else
			local wantMat = b.unpressedMaterial or Enum.Material.SmoothPlastic
			if bp.Material ~= wantMat then
				pcall(function() bp.Material = wantMat end)
			end
			local cf = b.unpressedCF
			if cf and (bp.Position - cf.Position).Magnitude > 0.01 then
				pcall(function() bp.CFrame = cf end)
			end
		end
	end
	if not isPressed then
		hideTimerUI(b)
	end
end
local function setPressed(b, value, silent)
	local v = b.pressed
	if not v or not v.Parent then return end
	if v.Value == value then return end
	if value then
		local now = os.clock()
		b.realPressClock = now
		if not silent then b.pressClock = now end
	end
	local snd = silent and b.bp and b.bp:FindFirstChild("Press")
	local oldVol
	if snd and snd:IsA("Sound") then
		oldVol = snd.Volume
		pcall(function() snd.Volume = 0 end)
	end
	suppress[b.id] = value
	pcall(function() v.Value = value end)
	if snd and oldVol ~= nil then
		task.defer(function()
			pcall(function()
				snd:Stop()
				snd.Volume = oldVol
			end)
		end)
	end
end
local function setAllCanTouch(canTouch)
	if lastCanTouchState == canTouch then return end
	lastCanTouchState = canTouch
	for _, b in pairs(reg.byId) do
		local bp = b.bp
		if bp and bp.Parent and bp.CanTouch ~= canTouch then
			pcall(function() bp.CanTouch = canTouch end)
		end
	end
end
local function reassertPressed(b)
	if b.reasserting then return end
	b.reasserting = true
	b.realPressClock = os.clock()
	local dur0 = getButtonDuration(b)
	local rawEl0 = pressAt[b.id] and (tNowCache - pressAt[b.id]) or 0
	if rawEl0 >= -0.001 and (dur0 == 0 or rawEl0 < dur0) then
		local el0 = math.max(0, rawEl0)
		if b.pressed and b.pressed.Parent and not b.pressed.Value then
			setPressed(b, true, true)
			local ts0 = getTimerValues(b)
			if ts0 then setTimerStartValue(b, ts0, os.clock() - el0) end
		end
	end
	restoreButtonVisual(b, true)
	task.defer(function()
		b.reasserting = false
		if control ~= "none" and b.currentPressed and pressAt[b.id] ~= nil then
			local dur = getButtonDuration(b)
			local rawEl = tNowCache - pressAt[b.id]
			if rawEl >= -0.001 and (dur == 0 or rawEl < dur) then
				local elapsedTAS = math.max(0, rawEl)
				if b.pressed and b.pressed.Parent and not b.pressed.Value then
					setPressed(b, true, true)
					local timerStart = getTimerValues(b)
					if timerStart then
						setTimerStartValue(b, timerStart, os.clock() - elapsedTAS)
					end
				end
				restoreButtonVisual(b, true)
				if dur > 0 then
					updateTimerUI(b, math.max(0, dur - elapsedTAS), true)
					task.defer(function()
						if control ~= "none" and b.currentPressed and pressAt[b.id] ~= nil then
							local curEl = math.max(0, tNowCache - pressAt[b.id])
							updateTimerUI(b, math.max(0, dur - curEl), true)
						end
					end)
				end
			end
		end
	end)
end
local function reassertUnpressed(b)
	if b.reassertingUnpress then return end
	b.reassertingUnpress = true
	local timerStart = getTimerValues(b)
	setPressed(b, false, true)
	setTimerStartValue(b, timerStart, 0)
	restoreButtonVisual(b, false)
	task.defer(function()
		b.reassertingUnpress = false
		if control ~= "none" and not b.currentPressed then
			if b.pressed and b.pressed.Parent and b.pressed.Value then
				setPressed(b, false, true)
			end
			setTimerStartValue(b, timerStart, 0)
			restoreButtonVisual(b, false)
		end
	end)
end
local function clearOurLabels(b)
	if b.ourScreenLabel and b.ourScreenLabel.Parent then pcall(function() b.ourScreenLabel:Destroy() end) end
	if b.ourPartGui and b.ourPartGui.Parent then pcall(function() b.ourPartGui:Destroy() end) end
	b.ourScreenLabel, b.ourPartGui, b.screenLabel, b.partLabels = nil, nil, nil, nil
	b.lastRemQ, b.lastFormatted = nil, nil
end
local function getLiveElapsed(b, clock)
	local timerStart = getTimerValues(b)
	local dur = getButtonDuration(b)
	if b.pausedElapsed ~= nil then
		return b.pausedElapsed, dur
	end
	local el = (timerStart and timerStart.Value > 0 and math.max(0, clock - timerStart.Value))
		or (b.pressClock and math.max(0, clock - b.pressClock)) or 0
	return el, dur
end
local function applyPressedState(b, id, t0, el, silent, clock)
	local dur = getButtonDuration(b)
	if dur > 0 and el >= dur then return false end
	b.currentPressed, b.pressedInIdle, b.pausedElapsed = true, nil, el
	dirtyButtons[id] = true
	pressAt[id] = t0
	local nowClock = clock or os.clock()
	b.pressClock = nowClock - el
	setPressed(b, true, silent)
	local timerStart = getTimerValues(b)
	setTimerStartValue(b, timerStart, nowClock - el)
	if dur > 0 then
		updateTimerUI(b, math.max(0, dur - el), control ~= "none")
		task.defer(function()
			if b.currentPressed and pressAt[id] then
				local curEl = math.max(0, tNowCache - pressAt[id])
				setTimerStartValue(b, timerStart, os.clock() - curEl)
				updateTimerUI(b, math.max(0, dur - curEl), control ~= "none")
			end
		end)
	end
	restoreButtonVisual(b, true)
	return true
end

local function onPressedChanged(b)
	local v = b.pressed
	if not v or not v.Parent then return end
	local now = v.Value
	if now then
		b.realPressClock = os.clock()
		b.needTimerStartRecheck = true
		if b.bp and b.bp.Parent and b.bp.Material ~= b.unpressedMaterial then b.pressedMaterial = b.bp.Material end
	end
	local s = suppress[b.id]
	if s ~= nil then
		suppress[b.id] = nil
		if s == now then return end
	end
	if control ~= "none" then
		if not now and b.currentPressed and pressAt[b.id] ~= nil then
			local dur = getButtonDuration(b)
			local rawEl = tNowCache - pressAt[b.id]
			local tol = (control == "record") and 0.05 or 0
			if rawEl >= -0.001 and ((dur == 0 and control ~= "record") or (dur > 0 and rawEl < dur - tol)) then
				reassertPressed(b)
				return
			end
		elseif now and not b.currentPressed and control == "paused" then
			reassertUnpressed(b)
			return
		elseif now and b.currentPressed and pressAt[b.id] ~= nil then
			local dur = getButtonDuration(b)
			local rawEl = tNowCache - pressAt[b.id]
			if rawEl >= -0.001 and (dur == 0 or rawEl < dur) then
				local elapsedTAS = math.max(0, rawEl)
				local timerStart = getTimerValues(b)
				if timerStart then setTimerStartValue(b, timerStart, os.clock() - elapsedTAS) end
				if dur > 0 then updateTimerUI(b, math.max(0, dur - elapsedTAS), true) end
				return
			end
		end
		if control == "paused" then return end
	end
	if recording then pending[#pending + 1] = { b.id, now and 1 or 0 } end
	if now then
		b.pressClock = os.clock()
		b.currentPressed = true
		dirtyButtons[b.id] = true
		b.pausedElapsed = nil
		clearOurLabels(b)
		pressAt[b.id] = tNowCache
		b.pressedInIdle = (control == "none")
		local function hookLiveLabels()
			if not b.currentPressed then return end
			local sLbl = getScreenLabel(b, false)
			if sLbl then hookLabelText(b, sLbl) end
			getPartLabels(b, false)
		end
		task.defer(hookLiveLabels)
		task.delay(0.05, hookLiveLabels)
	else
		b.currentPressed, b.pressedInIdle, b.pausedElapsed, pressAt[b.id] = false, nil, nil, nil
		hideTimerUI(b)
	end
end

local function bind(v)
	if conns[v] then return end
	local model, bp, config = getButtonInfo(v)
	if not (model and bp) then return end
	local parent = v.Parent
	local key = keyOf(parent) or keyOf(model)
	if not key then return end
	local id = idForKey(key)
	local b = reg.byId[id]
	b.model, b.bp, b.config, b.parent, b.pressed = model, bp, config, parent, v
	b.timerStart, b.durationVal, b.cachedDuration = nil, nil, nil
	b.timerValuesChecked, b.needTimerStartRecheck, b.hideGUI = false, false, nil
	b.partLabels, b.screenLabel, b.ourScreenLabel, b.ourPartGui = nil, nil, nil, nil
	b.timerText, b.decimalPlaces, b.configDecimals, b.liveDecimals, b.subSecDecimals, b.aboveSecDecimals = nil, nil, nil, nil, nil, nil
	b.decScale, b.lastUsedDec, b.lastRemQ, b.lastFormatted = nil, nil, nil, nil
	b.currentPressed = v.Value
	b.pressClock = v.Value and os.clock() or nil
	b.realPressClock = b.pressClock
	if not v.Value or not b.unpressedColor then b.unpressedColor = bp.Color end
	local pm = getPressedMaterial(b)
	if not v.Value and bp.Material ~= pm then
		b.unpressedMaterial = bp.Material
	elseif not b.unpressedMaterial then
		b.unpressedMaterial = (bp.Material == pm) and Enum.Material.SmoothPlastic or bp.Material
	end
	local pressOffset = config and config:GetAttribute("PressOffset")
	if typeof(pressOffset) == "Vector3" then pressOffset = CFrame.new(pressOffset)
	elseif typeof(pressOffset) ~= "CFrame" then pressOffset = CFrame.new(0, 0.75, 0) end
	if not v.Value then
		b.unpressedCF, b.pressedCF = bp.CFrame, bp.CFrame * pressOffset
	else
		b.pressedCF, b.unpressedCF = bp.CFrame, bp.CFrame * pressOffset:Inverse()
		dirtyButtons[id] = true
		if pressAt[id] == nil then pressAt[id] = tNowCache; b.pressedInIdle = (control == "none") end
	end
	getPartLabels(b, false)
	if control == "paused" and bp.CanTouch then pcall(function() bp.CanTouch = false end) end
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
		if inst.Name == "Pressed" and inst:IsA("BoolValue") then
			task.defer(function()
				if enabled and inst.Parent and inst.Name == "Pressed" and isButtonValue(inst) then bind(inst) end
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
	for _, b in pairs(reg.byId) do clearOurLabels(b) end
	for ts, cn in pairs(timerStartConns) do pcall(function() cn:Disconnect() end); timerStartConns[ts] = nil end
	for v in pairs(conns) do unbind(v) end
	pressAt, pending, suppress, suppressTimerStart, dirtyButtons = {}, {}, {}, {}, {}
	cachedContainers, cachedAdorneeGuis, lastCanTouchState = nil, nil, nil
	control, recording = "none", false
	idx = nil
end

function B.IsEnabled() return enabled end
function B.Count()
	local n = 0
	for _ in pairs(conns) do n = n + 1 end
	return n
end


-- keeps the kit's timer on the TAS clock (called every frame while a TAS is active)
function B.Step(tNow)
	if not enabled or control == "none" then return end
	tNowCache = tNow or tNowCache
	if next(pressAt) == nil then return end
	local clock = os.clock()
	for id, t0 in pairs(pressAt) do
		local b = reg.byId[id]
		local v = b and b.pressed
		if v and v.Parent and (v.Value or control ~= "none" or b.currentPressed) then
			local timerStart = getTimerValues(b)
			local dur = getButtonDuration(b)
			local rawEl = tNowCache - t0
			if rawEl < -0.001 or (dur > 0 and rawEl >= dur) then
				if recording and b.currentPressed then
					pending[#pending + 1] = { id, 0 }
				end
				b.currentPressed, b.pausedElapsed, pressAt[id] = false, nil, nil
				reassertUnpressed(b)
			else
				local elapsedTAS = math.max(0, rawEl)
				b.currentPressed = true
				dirtyButtons[id] = true
				if not v.Value and (control ~= "record" or dur > 0) then reassertPressed(b) end
				if timerStart then setTimerStartValue(b, timerStart, clock - elapsedTAS) end
				if dur > 0 then updateTimerUI(b, math.max(0, dur - elapsedTAS), true) end
				restoreButtonVisual(b, true)
			end
		else
			pressAt[id] = nil
		end
	end
end

-- events of the frame that is being recorded. first = the TAS starts here (snapshot)
function B.RenderStep()
	if not enabled or control == "none" or next(pressAt) == nil then return end
	local clock = os.clock()
	for id, t0 in pairs(pressAt) do
		local b = reg.byId[id]
		if b and b.currentPressed then
			local dur = getButtonDuration(b)
			local rawEl = tNowCache - t0
			if rawEl >= -0.001 and (dur == 0 or rawEl < dur) then
				local elapsedTAS = math.max(0, rawEl)
				local ts = b.timerStart
				if ts and ts.Parent then setTimerStartValue(b, ts, clock - elapsedTAS) end
				if dur > 0 then
					local formatted = b.lastFormatted or formatTimer(b, math.max(0, dur - elapsedTAS))
					local sLabel = b.screenLabel or (not isHideGUI(b) and getScreenLabel(b, false)) or nil
					if sLabel and sLabel.Parent then
						if sLabel.Text ~= formatted then
							suppressLabelText[sLabel] = true
							pcall(function() sLabel.Text = formatted end)
							suppressLabelText[sLabel] = nil
						end
						if not sLabel.Visible then pcall(function() sLabel.Visible = true end) end
					end
					local pLabels = b.partLabels or getPartLabels(b, false)
					if pLabels then
						for i = 1, #pLabels do
							syncPartLabelVisual(pLabels[i], formatted)
						end
					end
				end
			end
		end
	end
end
function B.RecordFrame(tNow, first)
	if not enabled or not recording then
		if #pending > 0 then table.clear(pending) end
		return nil
	end
	tNowCache = tNow or tNowCache
	local out
	if first then
		local clock = os.clock()
		for v in pairs(conns) do
			if v.Parent and v.Value then
				local model = getButtonInfo(v)
				local key = keyOf(v.Parent) or (model and keyOf(model))
				local id = key and reg.byKey[key] and reg.byKey[key].id
				if id then
					local b = reg.byId[id]
					local el, dur = getLiveElapsed(b, clock)
					if dur == 0 or el < dur then
						out = out or {}
						out[#out + 1] = { id, 1, el }
						b.currentPressed, b.pressedInIdle = true, nil
						pressAt[id] = tNow - el
					end
				end
			end
		end
		if out then dataVersion = dataVersion + 1; idx = nil end
	end
	if #pending > 0 then
		out = out or {}
		local seen = {}
		for i = #pending, 1, -1 do -- the last change of a button in this frame wins
			local e = pending[i]
			if not seen[e[1]] then
				seen[e[1]] = true
				out[#out + 1] = { e[1], e[2], 0 }
				if e[2] == 1 then pressAt[e[1]] = tNow else pressAt[e[1]] = nil end
			end
		end
		table.clear(pending)
		dataVersion = dataVersion + 1
		idx = nil
	end
	return out
end

function B.Invalidate()
	dataVersion = dataVersion + 1
	idx = nil
end

local function totalAt(tl, f)
	if f >= 1 and f <= tl:count() then return tl:get("TotalTime", f, 1) end
	return nil
end
local function buildIndex(data)
	local n = data:count()
	if idx and idxData == data and idxVer == dataVersion and idxCount == n then return idx end
	idx = { byId = {} }
	for f = 1, n do
		local bt = data:getList("v2BT", f)
		if bt then
			for _, e in ipairs(bt) do
				if e[1] ~= 0 then
					local list = idx.byId[e[1]]
					if not list then list = {}; idx.byId[e[1]] = list end
					list[#list + 1] = { f, e[2], e[3] or 0 }
				end
			end
		end
	end
	idxData, idxVer, idxCount = data, dataVersion, n
	return idx
end
local seekCandidates = {}

-- state of every button at frame f, applied to the game
local function seekTo(data, f)
	if not enabled then return end
	local ix = buildIndex(data)
	local tF = totalAt(data, f) or 0
	tNowCache = tF
	local clock = os.clock()
	table.clear(seekCandidates)
	for id in pairs(ix.byId) do seekCandidates[id] = true end
	for id in pairs(pressAt) do seekCandidates[id] = true end
	for id in pairs(dirtyButtons) do seekCandidates[id] = true end
	for id in pairs(seekCandidates) do
		local b = reg.byId[id]
		if b and b.pressed and b.pressed.Parent then
			local list = ix.byId[id]
			local pressed, el = false, 0
			if list then
				-- last event at or before f (binary search)
				local lo, hi, best = 1, #list, nil
				while lo <= hi do
					local mid = math.floor((lo + hi) / 2)
					if list[mid][1] <= f then best = mid; lo = mid + 1 else hi = mid - 1 end
				end
				if best and list[best][2] == 1 then
					local e = list[best]
					pressed = true
					el = e[3] + (tF - (totalAt(data, e[1]) or tF))
				end
			end
			if pressed and not applyPressedState(b, id, tF - el, el, control == "paused" or control == "record", clock) then
				pressed = false
			end
			if not pressed then
				if b.currentPressed or b.pressed.Value or pressAt[id] ~= nil or b.screenLabel ~= nil or b.ourScreenLabel ~= nil or b.ourPartGui ~= nil then
					b.currentPressed, b.pressedInIdle, b.pausedElapsed, pressAt[id] = false, nil, nil, nil
					reassertUnpressed(b)
				elseif list == nil then
					dirtyButtons[id] = nil
				end
			end
		end
	end
end
local function flushPending(data, tNow)
	if #pending > 0 and data and data:count() > 0 then
		local idxFrame = data:count()
		while idxFrame > 1 and not data:isFilled(idxFrame) do idxFrame = idxFrame - 1 end
		if idxFrame >= 1 then
			local fTime = totalAt(data, idxFrame) or tNow or tNowCache
			local out, seen = data:getList("v2BT", idxFrame) or {}, {}
			for i = #pending, 1, -1 do
				local e = pending[i]
				if not seen[e[1]] then
					seen[e[1]] = true
					out[#out + 1] = { e[1], e[2], 0 }
					if e[2] == 1 then pressAt[e[1]] = fTime else pressAt[e[1]] = nil end
				end
			end
			data:setList("v2BT", idxFrame, out)
		end
		table.clear(pending)
		dataVersion = dataVersion + 1
		idx = nil
	end
end

-- paused in Create mode on frame f
function B.ShowFrame(data, f)
	if not enabled then return end
	flushPending(data, totalAt(data, f) or tNowCache)
	recording, control = false, "paused"
	setAllCanTouch(false)
	seekTo(data, f)
end

-- recording continues from frame f (unpause)
function B.Resume(data, f)
	if not enabled then return end
	control, recording = "record", true
	if f and f > 0 and f <= data:count() then
		seekTo(data, f)
	else
		tNowCache = 0
		local clock = os.clock()
		for id, b in pairs(reg.byId) do
			if b.currentPressed and pressAt[id] ~= nil then
				local el = b.pausedElapsed or math.max(0, -pressAt[id])
				applyPressedState(b, id, -el, el, true, clock)
			end
		end
	end
	for _, b in pairs(reg.byId) do
		if b.bp and b.bp.Parent then pcall(function() b.bp.CanTouch = true end) end
		if not b.currentPressed then clearOurLabels(b) end
	end
	table.clear(pending)
	dataVersion = dataVersion + 1
	idx = nil
end

function B.Pause(tNow)
	if not enabled then return end
	recording, control = false, "paused"
	tNowCache = tNow or tNowCache
	local data = engine and engine.tl
	if data and data:count() > 0 then flushPending(data, tNowCache) end
	dataVersion = dataVersion + 1
	idx = nil
	setAllCanTouch(false)
	if not data or data:count() == 0 then
		local clock = os.clock()
		for id, b in pairs(reg.byId) do
			if b.pressed and b.pressed.Parent and b.pressed.Value and (pressAt[id] == nil or b.pressedInIdle) then
				local el, dur = getLiveElapsed(b, clock)
				if dur == 0 or el < dur then
					b.currentPressed, b.pressedInIdle, b.pausedElapsed = true, nil, el
					pressAt[id] = tNowCache - el
				end
			elseif b.currentPressed and pressAt[id] ~= nil then
				b.pausedElapsed = math.max(0, tNowCache - pressAt[id])
			end
		end
	else
		for id, t0 in pairs(pressAt) do
			local b = reg.byId[id]
			if b and b.currentPressed then
				b.pausedElapsed = math.max(0, tNowCache - t0)
			end
		end
	end
	B.Step(tNowCache)
end

function B.PlaybackBegin(data, f)
	if not enabled then return end
	recording, control, applied = false, "test", f
	table.clear(pending)
	setAllCanTouch(true)
	seekTo(data, f)
end

-- apply recorded events of frames (applied, f]
function B.PlaybackTo(data, f, t)
	if not enabled or control ~= "test" then return end
	tNowCache = t or tNowCache
	if f < applied or f - applied > 600 then
		seekTo(data, f)
	else
		local clock = os.clock()
		for i = applied + 1, f do
			local bt = data:getList("v2BT", i)
			if bt then
				local tI = totalAt(data, i) or 0
				for _, e in ipairs(bt) do
					local b = e[1] ~= 0 and reg.byId[e[1]]
					if b then
						if e[2] == 1 then
							applyPressedState(b, e[1], tI - (e[3] or 0), e[3] or 0, false, clock)
						else
							b.currentPressed, pressAt[e[1]] = false, nil
							reassertUnpressed(b)
						end
					end
				end
			end
		end
	end
	applied = f
	B.Step(t)
end
function B.Reset()
	for id, b in pairs(reg.byId) do
		b.currentPressed, b.pressedInIdle, pressAt[id] = false, nil, nil
		if b.pressed and b.pressed.Parent and b.pressed.Value then setPressed(b, false, true) end
		local timerStart = getTimerValues(b)
		setTimerStartValue(b, timerStart, 0)
		restoreButtonVisual(b, false)
	end
	table.clear(pending)
	table.clear(pressAt)
	dataVersion = dataVersion + 1
	idx = nil
end

-- back to normal play: the kit's timers continue in real time from where they are
function B.Release()
	setAllCanTouch(true)
	for _, b in pairs(reg.byId) do
		clearOurLabels(b)
		b.pressedInIdle = nil
	end
	control, recording = "none", false
	table.clear(pending)
	table.clear(pressAt)
	idx = nil
end

function B.ExportKeys(tl)
	local set = {}
	for i = 1, tl:count() do
		local bt = tl:getList("v2BT", i)
		if bt then
			for _, e in ipairs(bt) do
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

function B.ImportKeys(tl, list)
	local map, changed = {}, false
	for _, o in ipairs(list) do
		if type(o) == "table" and type(o.key) == "string" and type(o.id) == "number" then
			local sid = idForKey(o.key)
			map[o.id] = sid
			if sid ~= o.id then changed = true end
		end
	end
	if changed then
		for i = 1, tl:count() do
			local bt = tl:getList("v2BT", i)
			if bt then
				for _, e in ipairs(bt) do
					if e[1] ~= 0 then e[1] = map[e[1]] or e[1] end
				end
			end
		end
	end
	B.Invalidate()
end

-- ------------------------------------------------------------------------------------------------ the plugin
local Buttons = { name = "buttons", order = 55 }
Buttons.__index = Buttons

function Buttons.new(E)
	engine = E
	keyOfFn = function(inst) return E.co:keyOf(inst) end
	local self = setmetatable({ E = E }, Buttons)
	E.tl:addColumn("v2BT", "list", 1, { key = "BT", keep = true })
	E.life:own(function() B.Disable() end)
	E.life:own(E.settings:changed("syncButtonTimers", function(v)
		if v ~= 0 then B.Enable() else B.Disable() end
	end))
	if E.settings:on("syncButtonTimers") then B.Enable() end
	return self
end

function Buttons:fill(tl, n) tl:setList("v2BT", n, B.RecordFrame(tl:get("TotalTime", n, 1), n == 1)) end
function Buttons:onStep(t) B.Step(t) end
function Buttons:lateRender() B.RenderStep() end
function Buttons:onShowFrame(tl, i) B.ShowFrame(tl, i) end
function Buttons:onBeginRecording(tl, n) B.Resume(tl, n) end
function Buttons:onPause(t) B.Pause(t) end
function Buttons:onPlaybackBeginAlways(tl, f) B.PlaybackBegin(tl, f) end
-- (Test: the playback clock; frame by frame playback: the frame's own time, like V2)
function Buttons:onPlayTo(tl, f, t) B.PlaybackTo(tl, f, t or totalAt(tl, f) or 0) end
function Buttons:onReset() B.Reset() end
function Buttons:onRelease() B.Release() end
function Buttons:onDataChanged() B.Invalidate() end
function Buttons:onSave(tl)
	tl.meta = tl.meta or {}
	tl.meta.v2buttons = B.ExportKeys(tl)
end
-- (a run being loaded, before the engine takes it: persist/persist.lua)
function Buttons:onLoading(tl)
	local list = tl.meta and tl.meta.v2buttons
	if type(list) == "table" then B.ImportKeys(tl, list) end
end
function Buttons:count() return B.Count() end
function Buttons:isEnabled() return B.IsEnabled() end

return Buttons
