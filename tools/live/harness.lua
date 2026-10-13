-- HappaTAS live test helpers, for testing in a real Roblox client through an executor (development only).
-- Copy this file and a test build (bash tools/live_build.sh, which exports the modules as
-- getgenv().__HappaTAS_T) to <executor workspace>/HappaTasTest/, load the build, then in a test script:
--     local H = loadfile("HappaTasTest/harness.lua")()
-- Real input only reaches Roblox while its window is focused; keypress / mouse1press go to the foreground
-- window, so don't run input tests while someone else is using the computer.
local H = {}
local RS = game:GetService("RunService")
H.T = rawget(getgenv(), "__HappaTAS_T")
H.C = H.T and H.T.C
H.VK = {
	["1"] = 0x31, ["2"] = 0x32, ["3"] = 0x33, W = 0x57, A = 0x41, S = 0x53, D = 0x44, SPACE = 0x20, E = 0x45,
	Q = 0x51, T = 0x54, G = 0x47, F = 0x46, V = 0x56, R = 0x52, L = 0x4C, M = 0x4D, QUOTE = 0xDE, RBRACKET = 0xDD,
	BACKSPACE = 0x08, SHIFT = 0x10, LSHIFT = 0xA0, CTRL = 0x11, P = 0x50, F6 = 0x75, SLASH = 0xBF, ENTER = 0x0D,
	ESC = 0x1B, I = 0x49, O = 0x4F,
}
function H.frames(n) for _ = 1, n do RS.Heartbeat:Wait() end end
function H.tap(k, holdFrames)
	keypress(H.VK[k]); H.frames(holdFrames or 2); keyrelease(H.VK[k]); H.frames(2)
end
function H.down(k) keypress(H.VK[k]) end
function H.up(k) keyrelease(H.VK[k]) end
function H.hold(k, secs) keypress(H.VK[k]); task.wait(secs); keyrelease(H.VK[k]) end
function H.pos(fr) return Vector3.new(fr.Cframe[1], fr.Cframe[2], fr.Cframe[3]) end
function H.v(p) return string.format("(%.2f, %.2f, %.2f)", p.X, p.Y, p.Z) end
-- the recorded root position at playback time t
function H.wantAt(data, f, t)
	local f1, f2 = data[f], data[f + 1]
	if not (f1 and f2 and f1.Cframe and f2.Cframe) then return nil end
	local t1, t2 = f1.TotalTime, f2.TotalTime
	local w = (t2 > t1) and math.clamp((t - t1) / (t2 - t1), 0, 1) or 0
	return H.pos(f1):Lerp(H.pos(f2), w)
end
-- console errors / warnings from HappaTAS since a console seq (read through LogService)
local LogService = game:GetService("LogService")
H.logs = {}
H.logConn = LogService.MessageOut:Connect(function(msg, typ)
	if typ ~= Enum.MessageType.MessageOutput and typ ~= Enum.MessageType.MessageInfo then
		H.logs[#H.logs + 1] = tostring(typ.Name) .. ": " .. msg
	end
end)
function H.done()
	if H.logConn then H.logConn:Disconnect() end
	return H.logs
end
-- real mouse click on the middle of a GUI object (client-area coordinates for mousemoveabs)
function H.screenPoint(gui)
	local inset = game:GetService("GuiService"):GetGuiInset()
	local p = gui.AbsolutePosition + gui.AbsoluteSize / 2
	-- AbsolutePosition is measured from below the top bar, also in IgnoreGuiInset ScreenGuis
	local y = p.Y + inset.Y
	return math.floor(p.X + 0.5), math.floor(y + 0.5)
end
-- Real's injected mouse moves reach Roblox one event late: a tiny relative move afterwards makes Roblox
-- see the target position (checked with UserInputService:GetMouseLocation)
local UIS = game:GetService("UserInputService")
function H.moveTo(x, y)
	for _ = 1, 3 do
		mousemoveabs(x, y); task.wait(0.03)
		mousemoverel(1, 0); task.wait(0.03)
		mousemoverel(-1, 0); task.wait(0.03)
		local m = UIS:GetMouseLocation()
		if math.abs(m.X - x) <= 8 and math.abs(m.Y - y) <= 8 then return true end
	end
	return false
end
function H.click(gui, right)
	local x, y = H.screenPoint(gui)
	H.moveTo(x, y)
	if right then mouse2press() else mouse1press() end
	H.frames(2)
	if right then mouse2release() else mouse1release() end
	H.frames(3)
end
function H.clickAt(x, y, right)
	H.moveTo(x, y)
	if right then mouse2press() else mouse1press() end
	H.frames(2)
	if right then mouse2release() else mouse1release() end
	H.frames(3)
end
function H.gui(path) -- "MainMenu.SettingsToggle" under the HappaTAS ScreenGui
	local g = H.T.Gui
	for part in string.gmatch(path, "[^%.]+") do g = g and g:FindFirstChild(part) end
	return g
end
-- idle + empty TAS
function H.reset()
	local C = H.C
	if C.mode ~= 1 then H.tap("1"); H.frames(3) end
	H.T.Core.SetTAS({})
	H.frames(3)
end
return H
