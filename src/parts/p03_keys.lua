-- ================================================================================================
--  KEY NAMES  (text shown in the Controls tab  <->  Roblox enum)
-- ================================================================================================
local ToKey, FromKey = {}, {}
do
	local function add(name, item)
		if item ~= nil then
			ToKey[name] = item
			if FromKey[item] == nil then FromKey[item] = name end
		end
	end
	local function kc(n)
		local ok, item = pcall(function() return Enum.KeyCode[n] end)
		return ok and item or nil
	end
	local letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	for i = 1, #letters do
		local ch = letters:sub(i, i)
		add(ch, kc(ch))
	end
	local digits = { "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
	for n = 0, 9 do add(tostring(n), kc(digits[n + 1])) end
	for n = 1, 12 do add("F" .. n, kc("F" .. n)) end
	local other = {
		{ "Return", "Return" }, { "Backspace", "Backspace" }, { "Delete", "Delete" }, { "Tab", "Tab" },
		{ "-", "Minus" }, { "=", "Equals" }, { "'", "Quote" }, { "/", "Slash" }, { "\\", "BackSlash" },
		{ ";", "Semicolon" }, { ",", "Comma" }, { ".", "Period" }, { "[", "LeftBracket" }, { "]", "RightBracket" },
		{ "`", "Backquote" }, { "LeftControl", "LeftControl" }, { "RightControl", "RightControl" },
		{ "LeftShift", "LeftShift" }, { "RightShift", "RightShift" }, { "LeftAlt", "LeftAlt" }, { "RightAlt", "RightAlt" },
		{ "Space", "Space" }, { "CapsLock", "CapsLock" }, { "Up", "Up" }, { "Down", "Down" }, { "Left", "Left" },
		{ "Right", "Right" }, { "Insert", "Insert" }, { "Home", "Home" }, { "End", "End" },
		{ "PageUp", "PageUp" }, { "PageDown", "PageDown" },
	}
	for _, o in ipairs(other) do add(o[1], kc(o[2])) end
	for n = 0, 9 do add("Num" .. n, kc("Keypad" .. digits[n + 1])) end
	add("Left Click", Enum.UserInputType.MouseButton1)
	add("Right Click", Enum.UserInputType.MouseButton2)
	add("Scroll Click", Enum.UserInputType.MouseButton3)
end

local function isValidKeyName(s) return type(s) == "string" and ToKey[s] ~= nil end

-- true when the input matches the key bound to a control
local function CheckInput(inp, control)
	local item = ToKey[Controls.Get(control) or ""]
	if item == nil then return false end
	return inp.KeyCode == item or inp.UserInputType == item
end

