-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1: chat replay. What is typed into Roblox's chat bar while recording is saved per frame
-- (column Chat: { text } a change, { text, 1 } sent, { text, 2 } closed without sending) and typed and sent
-- again through the same bar in Test (headless mock: M.chatBox, M.chatSent)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local tl = E.tl
local box = M.chatBox
local function req(a) E.modes:request(a); M.steps(2) end
local function entries(from, to)
	local out = {}
	for i = from or 1, to or tl:count() do
		local l = tl:getList("Chat", i)
		if type(l) == "table" then
			for _, e in ipairs(l) do out[#out + 1] = { i = i, text = e[1], kind = e[2] } end
		end
	end
	return out
end
local function typeOn(text) box.Text = text; M.steps(1) end

section("recording")
req("create")
req("unpause")
M.steps(3)
local f0 = tl:count()
box:CaptureFocus(); M.steps(1)
typeOn("/")
typeOn("/e")
typeOn("/e dance2")
box:ReleaseFocus(true); M.steps(1)
local e = entries(f0)
local texts = {}
for _, x in ipairs(e) do texts[#texts + 1] = tostring(x.text) .. (x.kind and ("#" .. x.kind) or "") end
local got = table.concat(texts, "|")
check(got == "|/|/e|/e dance2|/e dance2#1" or got == "/|/e|/e dance2|/e dance2#1", "opened, typed, sent in order (" .. got .. ")")
eq(M.chatSent[#M.chatSent], "/e dance2", "Roblox sent it")
local sentFrame = e[#e].i
check(sentFrame > e[1].i, "over several frames")

section("closed without sending")
box:CaptureFocus(); M.steps(1)
typeOn("hi")
box:ReleaseFocus(false); M.steps(1)
e = entries(sentFrame + 1)
check(#e >= 2 and e[#e].text == "hi" and e[#e].kind == 2, "the last entry is { hi, 2 }")

section("paused: nothing recorded")
req("pause")
local before = #entries()
box:CaptureFocus(); M.steps(1)
typeOn("paused text")
box:ReleaseFocus(false); M.steps(2)
req("unpause") -- (and nothing of it lands on the frames recorded next)
M.steps(3)
req("pause")
eq(#entries(), before, "no new entries")

section("cut: recording over drops later chat")
local n = tl:count()
E.modes:seek(f0 - 2); M.steps(2)
req("unpause")
M.steps(3)
req("pause")
eq(#entries(f0 + 2, n), 0, "the chat after the new end is gone (" .. tl:count() .. " frames)")

-- ------------------------------------------------------------------------------------------------ Test
local function waitIdle()
	local g = 0
	while E.busy and g < 2000 do M.step(1 / 60); g = g + 1 end
	return not E.busy
end
E.modes:seek(tl:count()); M.steps(2)
req("unpause")
M.steps(3)
local fOpen = tl:count() + 1
box:CaptureFocus(); M.steps(1)
typeOn("/e")
typeOn("/e dance2")
box:ReleaseFocus(true); M.steps(1)
local fSend = tl:count()
M.steps(40) -- (the send well before the end: at Playback Speed 10 its frame is skipped, not caught up at the end)
req("pause")
req("idle")
check(fSend > fOpen + 1, "a run with chat (" .. fOpen .. " .. " .. fSend .. ")")

local caretOff = 0 -- (frames where the text cursor wasn't after the last letter while Test typed)
-- plays Test to the end (or until stopAt(frame) is true); returns sends, texts seen, frame of the send
local function playTest(stopAt)
	local s0 = #M.chatSent
	local seen, sentAt = {}, nil
	req("test")
	for _ = 1, tl:count() * 4 + 60 do
		if E.mode ~= 3 then break end
		if box.Text ~= "" then
			seen[box.Text] = true
			if box.CursorPosition ~= #box.Text + 1 then caretOff = caretOff + 1 end
		end
		if not sentAt and #M.chatSent > s0 then sentAt = E.frame end
		if stopAt and stopAt() then break end
		M.step(1 / 60)
	end
	if not sentAt and #M.chatSent > s0 then sentAt = E.frame end
	return #M.chatSent - s0, seen, sentAt
end

section("Test types and sends")
local sends, seen, at = playTest()
eq(sends, 1, "sent once")
eq(M.chatSent[#M.chatSent], "/e dance2", "the recorded text")
check(seen["/e"] and seen["/e dance2"], "the text grew in the bar")
check(at and math.abs(at - fSend) <= 1, "on the send frame (" .. tostring(at) .. " vs " .. fSend .. ")")
check(not box:IsFocused() and box.Text == "", "the bar is closed and empty after")
eq(caretOff, 0, "the text cursor follows the typing (after the last letter)")

section("skipped frames: Playback Speed 10")
E.settings:set("playbackSpeed", 10)
sends = playTest()
eq(sends, 1, "still sent once")
eq(M.chatSent[#M.chatSent], "/e dance2", "the whole text")
E.settings:set("playbackSpeed", 1)

section("start mid-typing")
E.settings:set("restartWhenTesting", 0)
req("create")
E.modes:seek(fOpen + 2); M.steps(2)
local s0 = #M.chatSent
E.modes:request("test")
check(box:IsFocused() and box.Text == "/e", "the bar opens at once with the text typed so far (" .. box.Text .. ")")
for _ = 1, tl:count() * 4 + 60 do if E.mode ~= 3 then break end M.step(1 / 60) end
eq(E.mode, 1, "Test ran to the end")
eq(#M.chatSent - s0, 1, "then sends it")
E.settings:set("restartWhenTesting", 1)

section("stop mid-typing, keys still work")
M.focusedChatBarSeen = true -- (live: GetFocusedTextBox reports the chat bar the replay focused)
local active
sends = playTest(function()
	if box:IsFocused() and box.Text == "/e" then active = E.typing:active(); return true end
	return false
end)
eq(active, false, "while the replay types, HappaTAS's keys still work")
M.focusedChatBarSeen = false
req("idle")
eq(sends, 0, "nothing sent")
check(not box:IsFocused() and box.Text == "", "the bar is closed and empty")

section("Replay Chat off")
E.settings:set("replayChat", 0)
local focused = false
local fc = box.Focused:Connect(function() focused = true end)
sends = playTest()
fc:Disconnect()
eq(sends, 0, "nothing sent")
eq(focused, false, "the bar never opened")
E.settings:set("replayChat", 1)

section("save / load")
check((E.persist:save("chat run", "")), "save started")
check(waitIdle(), "saved")
for i = 1, tl:count() do tl:setList("Chat", i, nil) end
sends = playTest()
eq(sends, 0, "a run without chat sends nothing")
check((E.persist:load("chat run.tas")), "load started")
check(waitIdle(), "loaded")
M.steps(2)
sends = playTest()
eq(sends, 1, "the loaded run sends it again")

section("review: a seek in Test sends nothing it jumps over")
local sk0 = #M.chatSent
local sought = false
playTest(function()
	if E.frame >= 3 and E.frame < fOpen then E.modes:seek(fSend + 10); sought = true; return true end
	return false
end)
for _ = 1, tl:count() * 4 do if E.mode ~= 3 then break end M.step(1 / 60) end
check(sought, "sought past the send during Test")
eq(#M.chatSent - sk0, 0, "the seek past the send sent nothing")

section("review: one send per frame, in order (two sends a frame apart, Playback Speed 10)")
req("create")
E.modes:seek(tl:count()); M.steps(2)
req("unpause")
M.steps(2)
box:CaptureFocus(); M.steps(1)
typeOn("first")
box:ReleaseFocus(true); M.steps(1)
box:CaptureFocus(); M.steps(1)
typeOn("second")
box:ReleaseFocus(true); M.steps(1)
M.steps(40)
req("pause")
req("idle")
E.settings:set("playbackSpeed", 10)
local perStep, worst, order = 0, 0, {}
local s1 = #M.chatSent
req("test")
for _ = 1, tl:count() * 4 do
	if E.mode ~= 3 then break end
	local before2 = #M.chatSent
	M.step(1 / 60)
	perStep = #M.chatSent - before2
	if perStep > worst then worst = perStep end
end
E.settings:set("playbackSpeed", 1)
for i = s1 + 1, #M.chatSent do order[#order + 1] = M.chatSent[i] end
local got2 = table.concat(order, ",")
check(got2:sub(-12) == "first,second", "both sent, in order (" .. got2 .. ")")
eq(worst, 1, "never two sends in one frame")

section("review: Roblox empties the bar before FocusLost: the send keeps its text")
M.chatClearFirst = true
req("create")
E.modes:seek(tl:count()); M.steps(2)
req("unpause")
M.steps(2)
local fA = tl:count() + 1
box:CaptureFocus(); M.steps(1)
typeOn("/e wave")
M.steps(2)
box:ReleaseFocus(true); M.steps(1)
req("pause")
M.chatClearFirst = false
local lastE
for _, x in ipairs(entries(fA)) do lastE = x end
check(lastE and lastE.kind == 1 and lastE.text == "/e wave", "recorded as { /e wave, 1 } (" .. tostring(lastE and lastE.text) .. ")")
req("idle")

section("Help and the update log")
do
	local inputs
	for _, t in ipairs(__T3("ui/win/helptext").topics(E)) do if t.id == "inputs" then inputs = t.body end end
	check(inputs and inputs:find("Replay Chat", 1, true) ~= nil and inputs:find("/e dance2", 1, true) ~= nil,
		"the Keyboard and Mouse Inputs topic explains chat replay")
	local v31 = table.concat(__T3("ui/updatelog").ENTRIES[1].bullets, " ")
	check(v31:find("chat", 1, true) ~= nil, "V3.1's log has it")
end

section("no chat bar: no errors, nothing recorded")
local errors = 0
local conn = game:GetService("LogService").MessageOut:Connect(function(m, t)
	if t == Enum.MessageType.MessageError or tostring(m):find("chat", 1, true) then errors = errors + 1 end
end)
game:GetService("CoreGui").ExperienceChat:Destroy()
local had = #entries()
req("create")
req("unpause")
for _ = 1, 200 do M.step(1 / 60) end -- (past the 2 s look-up again)
req("pause")
eq(#entries(), had, "nothing new")
eq(errors, 0, "no errors")
conn:Disconnect()
req("idle")
finish()
