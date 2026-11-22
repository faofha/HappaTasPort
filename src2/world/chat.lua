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
		conns = {}, played = 0, owns = false }, Chat)
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
		local p = self.pending
		local text = b.Text
		if text == "" and p[#p] and p[#p][2] == nil then text = p[#p][1] end -- (Roblox may empty it first)
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

return Chat
