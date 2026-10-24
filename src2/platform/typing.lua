-- ================================================================================================
--  TYPING  (HappaTAS 3 platform): HappaTAS keys do nothing while the player types (chat, any text box)
--  or has the Roblox menu open. GetFocusedTextBox() doesn't see text boxes inside CoreGui, like the new
--  chat bar (TextChatService) or HappaTAS's own boxes (under gethui()), so those are checked directly:
--  ChatInputBarConfiguration.IsFocused and the Focused / FocusLost events of our own boxes.
--  rebinding: a control waits for its new key. boundInput: the press that gave it the new key (Roblox
--  doesn't promise the order of InputBegan handlers; live, the press also ran the old control).
-- ================================================================================================
local Env = import("platform/env")

local Typing = {}
Typing.__index = Typing

function Typing.new(life)
	return setmetatable({ life = life, own = nil, bar = nil, rebinding = false, boundInput = nil,
		uis = Env.svc("UserInputService"), gui = Env.svc("GuiService"), chat = Env.svc("TextChatService") }, Typing)
end

-- every TextBox under root, also ones added later, counts as one of ours
function Typing:watch(root)
	local function add(d)
		if not d:IsA("TextBox") then return end
		self.life:connect(d.Focused, function() self.own = d end)
		self.life:connect(d.FocusLost, function() if self.own == d then self.own = nil end end)
	end
	for _, d in ipairs(root:GetDescendants()) do add(d) end
	self.life:connect(root.DescendantAdded, add)
end

function Typing:chatFocused()
	local bar = self.bar
	if not (bar and bar.Parent) then
		bar = self.chat and self.chat:FindFirstChildOfClass("ChatInputBarConfiguration")
		self.bar = bar
	end
	return bar ~= nil and bar.IsFocused == true
end

function Typing:active(inp)
	if self.rebinding or (inp ~= nil and inp == self.boundInput) then return true end
	if self.uis:GetFocusedTextBox() ~= nil then return true end -- game text boxes, the old chat
	local own = self.own
	if own and own.Parent and own:IsFocused() then return true end
	if self.gui and self.gui.MenuIsOpen then return true end
	local ok, chat = pcall(self.chatFocused, self)
	return ok and chat == true
end

return Typing
