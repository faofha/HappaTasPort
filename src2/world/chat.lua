-- ================================================================================================
--  CHAT  (HappaTAS 3 world plugin, order 56, V3.1): what is typed into Roblox's chat bar while recording is
--  part of the run, and Test types it again. Column "Chat" (list): per frame the changes seen on it, in order:
--  { text } the bar's text changed (or the bar opened), { text, 1 } sent (Enter), { text, 2 } closed without
--  sending. The bar is the new chat's (TextChatService) input TextBox in CoreGui.ExperienceChat (live, EToH kit
--  test place 2026-11-22: CaptureFocus, Text and ReleaseFocus(true) from a script sent "/e dance2" and the
--  character danced). Games without it (the old chat): nothing is recorded or replayed.
-- ================================================================================================
local Env = import("platform/env")

local Chat = { name = "chat", order = 56 }
Chat.__index = Chat

local FIND_EVERY = 2 -- (seconds between looks for the chat bar while it is missing)

function Chat.new(E)
	local self = setmetatable({ E = E, core = Env.svc("CoreGui"), bar = nil, found = -math.huge, pending = {},
		conns = {}, played = 0, owns = false, queue = {}, lastText = nil }, Chat)
	E.tl:addColumn("Chat", "list", 1, { key = "Chat", keep = true })
	E.life:own(function() self:unhook() end)
	return self
end

function Chat:unhook()
	for _, c in ipairs(self.conns) do c:Disconnect() end
	self.conns = {}
end

function Chat:recording() return self.E.mode == 2 and not self.E.paused end

-- a change seen on the bar (kept only while recording); text changes in one frame collapse to the last
function Chat:note(text, kind)
	if self.owns or not self:recording() then return end
	local p = self.pending
	local last = p[#p]
	self.lastText = (kind == nil) and text or nil
	if kind == nil and last and last[2] == nil then last[1] = text return end
	p[#p + 1] = { text, kind }
end

function Chat:hook(b)
	self:unhook()
	local c = self.conns
	c[#c + 1] = b.Focused:Connect(function() self:note(b.Text, nil) end)
	c[#c + 1] = b:GetPropertyChangedSignal("Text"):Connect(function()
		if b:IsFocused() then self:note(b.Text, nil) end
	end)
	c[#c + 1] = b.FocusLost:Connect(function(enter)
		local text = b.Text
		if text == "" and self.lastText then text = self.lastText end -- (Roblox may empty the bar first)
		self:note(text, enter and 1 or 2)
	end)
end

-- the chat bar's TextBox (looked up again at most every FIND_EVERY s while missing)
function Chat:box()
	local b = self.bar
	if b and b.Parent then return b end
	local now = os.clock()
	if now - self.found < FIND_EVERY then return nil end
	self.found = now
	self.bar = nil
	local ok, found = pcall(function()
		local ec = self.core and self.core:FindFirstChild("ExperienceChat")
		local v2 = ec and ec:FindFirstChild("ChatInputBarV2", true)
		return v2 and v2:FindFirstChildWhichIsA("TextBox", true)
	end)
	if ok and found then
		self.bar = found
		self:hook(found)
	end
	return self.bar
end

-- recording: the changes since the last frame go onto frame i (a bar already open when recording starts too)
function Chat:fill(tl, i)
	local b = self:box()
	if not b then self.pending = {} return end
	if self.wasRecording ~= i - 1 and #self.pending == 0 and b:IsFocused() and not self.owns then
		self.pending[1] = { b.Text }
	end
	self.wasRecording = i
	if #self.pending > 0 then
		tl:setList("Chat", i, self.pending)
		self.pending = {}
	end
end

-- ------------------------------------------------------------------------------------------------ Test
-- one entry into the bar: open it (ours while open), set the text, send (1) or close (2)
function Chat:apply(e)
	local b = self:box()
	if not b then return end
	local text, kind = e[1], e[2]
	self.owns = true
	self.E.typing.chatReplay = true
	if not b:IsFocused() then b:CaptureFocus() end
	if b.Text ~= text then b.Text = text end
	if kind == 1 then
		b:ReleaseFocus(true)
		self:release(false)
	elseif kind == 2 then
		self:release(true)
	end
end

-- the bar handed back; close: a bar still open is emptied and closed without sending
function Chat:release(close)
	local b = self.bar
	if close and self.owns and b and b.Parent then
		b.Text = ""
		if b:IsFocused() then b:ReleaseFocus(false) end
	end
	self.owns = false
	self.E.typing.chatReplay = false
end

-- the entries of frames from .. to join the queue; drain applies them, stopping after one send a frame (all:
-- every one): Roblox's chat reads the bar's text after the script let go of it, so two sends in one frame could
-- merge (review, V3.1)
function Chat:playRange(tl, from, to)
	local q = self.queue
	for i = from, to do
		local l = tl:getList("Chat", i)
		if type(l) == "table" then
			for _, e in ipairs(l) do q[#q + 1] = e end
		end
	end
end

function Chat:drain(all)
	local q = self.queue
	while #q > 0 do
		local e = table.remove(q, 1)
		self:apply(e)
		if e[2] == 1 and not all then return end
	end
end

-- Test starts on frame f: the bar as it was just before f (open with its text if typing was going on)
function Chat:onPlaybackBegin(tl, f)
	self.active = self.E.settings:on("replayChat") and self:box() ~= nil
	if not self.active then return end
	self.played = f - 1
	self.queue = {}
	local last
	for i = 1, f - 1 do
		local l = tl:getList("Chat", i)
		if type(l) == "table" and #l > 0 then last = l[#l] end
	end
	if last and last[2] == nil then self:apply(last) end
end

-- every entry from the last frame played up to f, in order (frames skipped by speed or a long frame too)
function Chat:onPlayTo(tl, f)
	if not self.active then return end
	if f < self.played then
		self:release(true)
		self:onPlaybackBegin(tl, f + 1)
		return
	end
	if f > self.played then
		self:playRange(tl, self.played + 1, f)
		self.played = f
	end
	self:drain(false)
end

-- Test jumped to frame f (the timeline, TAS Timeline): the bar as it was there, nothing in between is sent
function Chat:onSeek(tl, f)
	if not self.active then return end
	self:release(true)
	self:onPlaybackBegin(tl, f + 1)
end

-- the end of Test: the last frames when it ran to the end, then the bar handed back (closed, unsent)
function Chat:onEndPlayback()
	if not self.active then return end
	local tl, E = self.E.tl, self.E
	local n = tl:count()
	if E.frame >= n - 1 and self.played < n then self:playRange(tl, self.played + 1, n) end
	self:drain(true)
	self.active = false
	self:release(true)
end

-- Test left another way (Idle, Create): the bar handed back, closed and unsent
function Chat:onRelease()
	if not self.active then return end
	self.queue = {}
	self.active = false
	self:release(true)
end

return Chat
