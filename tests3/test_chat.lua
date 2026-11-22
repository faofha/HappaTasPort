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

section("no chat bar: no errors, nothing recorded")
local errors = 0
local conn = game:GetService("LogService").MessageOut:Connect(function(m, t)
	if t == Enum.MessageType.MessageError or tostring(m):find("chat", 1, true) then errors = errors + 1 end
end)
game:GetService("CoreGui").ExperienceChat:Destroy()
local had = #entries()
req("unpause")
for _ = 1, 200 do M.step(1 / 60) end -- (past the 2 s look-up again)
req("pause")
eq(#entries(), had, "nothing new")
eq(errors, 0, "no errors")
conn:Disconnect()
req("idle")
finish()
