-- ================================================================================================
-- HappaTAS 3 UI suites (-- needs: ui): pointer and keyboard helpers. Positions are in the interface's own
-- space (GuiObject.AbsolutePosition: the top bar inset taken off); the mock's mouse is in
-- GetMouseLocation space, so the inset is added back here.
-- ================================================================================================
UIH = {}
function UIH.move(pos) M.moveMouse(pos.X, pos.Y + M.inset) end
function UIH.press(pos) UIH.move(pos); M.mouseDown(1, false) end
function UIH.release(pos) UIH.move(pos); M.mouseUp(1, false) end
function UIH.center(gui) return gui.AbsolutePosition + gui.AbsoluteSize / 2 end
local function at(x) if typeof(x) == "Vector2" then return x end return UIH.center(x) end
function UIH.click(guiOrPos)
	local p = at(guiOrPos)
	UIH.press(p)
	UIH.release(p)
end
function UIH.drag(from, to, steps)
	local a, b = at(from), at(to)
	steps = steps or 6
	UIH.press(a)
	for i = 1, steps do UIH.move(a:Lerp(b, i / steps)) end
	UIH.release(b)
end
function UIH.wheel(guiOrPos, z) UIH.move(at(guiOrPos)); M.wheel(z) end
-- types into a TextBox the way Roblox does: focus, Text set, focus lost (enter = true for Enter)
function UIH.typeInto(box, text, enter)
	box:CaptureFocus()
	box.Text = text
	if enter == nil then enter = true end
	M.focusedBox = nil
	box.FocusLost:Fire(enter, nil)
end
function UIH.key(kc) M.pressKey(kc); M.releaseKey(kc) end
-- every GuiObject under root whose Text is text (first one)
function UIH.find(root, text)
	for _, d in ipairs(root:GetDescendants()) do
		if (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) and d.Text == text then return d end
	end
	return nil
end
