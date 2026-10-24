-- ================================================================================================
--  KEYS  (HappaTAS 3 engine): key names shown to the player <-> Roblox enums (V2.38.16 p03_keys).
--  toKey["2"] = Enum.KeyCode.Two, fromKey[Enum.KeyCode.Two] = "2"; mouse buttons are UserInputTypes.
-- ================================================================================================
local Keys = { toKey = {}, fromKey = {} }

local function add(name, item)
	if item ~= nil then
		Keys.toKey[name] = item
		if Keys.fromKey[item] == nil then Keys.fromKey[item] = name end
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

function Keys.isValid(name) return type(name) == "string" and Keys.toKey[name] ~= nil end

return Keys
