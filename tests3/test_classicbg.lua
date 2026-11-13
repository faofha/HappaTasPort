-- needs: ui
-- ================================================================================================
-- HappaTAS 3: Classic Look's background: a picture link (downloaded once into HappaTasPort/Backgrounds, then
-- loaded with getcustomasset), a Roblox image id, or a Roblox video id, behind Classic's main menu. Video files
-- from links are refused (Roblox didn't play any, measured live). (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local ui = E.ui
local s = E.settings
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
M.http, M.httpLog = M.http or {}, M.httpLog or {}
-- (review: set before Classic is built: a part Classic's code paints keeps that code's colour)
s:set("classicSectionTitle", "#FFFFFF")
s:set("classicText", "#FFFF00")
s:set("interface", "Classic")
M.steps(1)
local c = ui.classic
do
	local t = c.byPath["MainMenu.SettingsFrame.List"]:FindFirstChild("Section_Classic Look")
	eq(t and t.TextColor3, Color3.fromRGB(255, 255, 255), "a section title is built in Section Title, not Text")
	s:set("classicSectionTitle", "Auto")
	s:set("classicText", "Auto")
	M.steps(1)
end
local bg = c.background
local menu = c.menu
local statuses = {}
local realStatus = c.status
c.status = function(self, text) statuses[#statuses + 1] = text; return realStatus(self, text) end
local function lastStatus() return statuses[#statuses] or "" end
local function wait(n) for _ = 1, n or 3 do M.step(1 / 60) end end
local function files()
	local n = 0
	for p in pairs(M.fs) do if p:find("^HappaTasPort/Backgrounds/") then n = n + 1 end end
	return n
end
local function near(a, b) return math.abs(a - b) < 1e-6 end

section("nothing set")
check(bg ~= nil, "Classic has a background")
eq(bg.kind, nil, "no background")
check(near(menu.BackgroundTransparency, 0.2), "V2's menu transparency")

section("a picture link")
local URL = "https://example.com/pics/sky.png?size=large"
M.http[URL] = "\137PNG\r\n\26\n" .. string.rep("x", 64)
s:set("classicBackground", URL)
wait()
eq(#M.httpLog, 1, "downloaded once")
eq(files(), 1, "saved in HappaTasPort/Backgrounds")
eq(bg.kind, "image", "shown as a picture")
local path
for p in pairs(M.fs) do if p:find("^HappaTasPort/Backgrounds/") then path = p end end
check(path ~= nil and path:match("^HappaTasPort/Backgrounds/%x%x%x%x%x%x%x%x%.png$") ~= nil, "named by the link's hash, .png (" .. tostring(path) .. ")")
eq(bg.view and bg.view.Image, "rbxasset://custom/" .. tostring(path), "loaded with getcustomasset")
eq(bg.view and bg.view.Name, "HappaTASBackground", "its name")
check(bg.view and bg.view.ZIndex < menu.ZIndex, "behind the menu")
check(near(menu.BackgroundTransparency, 0.6), "the window colour over it at 40 %")
s:set("classicBackground", "")
wait()
eq(bg.kind, nil, "empty: none")
eq(bg.view, nil, "(nothing shown)")
check(near(menu.BackgroundTransparency, 0.2), "V2's transparency again")
s:set("classicBackground", URL)
wait()
eq(#M.httpLog, 1, "set again: the saved file, no second download")
eq(bg.kind, "image", "(shown)")

section("fit and transparency")
s:set("classicBackgroundFit", "Stretch")
eq(bg.view.ScaleType, Enum.ScaleType.Stretch, "Stretch")
s:set("classicBackgroundFit", "Fit")
eq(bg.view.ScaleType, Enum.ScaleType.Fit, "Fit")
s:set("classicBackgroundFit", "Crop")
eq(bg.view.ScaleType, Enum.ScaleType.Crop, "Crop")
s:set("classicBackgroundTransparency", 75)
check(near(menu.BackgroundTransparency, 0.25), "75 %: the window colour shows a lot")
s:set("classicBackgroundTransparency", 40)

section("follows the menu")
menu.Position = UDim2.new(0, 123, 0, 45)
eq(bg.view.Position, menu.Position, "moved with the menu")
menu.Visible = false
eq(bg.view.Visible, false, "hidden with the menu")
menu.Visible = true
eq(bg.view.Visible, true, "shown with it")

section("Roblox ids")
local before = #M.httpLog
s:set("classicBackground", "123")
wait()
eq(bg.kind, "image", "a number: a Roblox image")
eq(bg.view.Image, "rbxassetid://123", "its id")
s:set("classicBackground", "rbxassetid://124")
wait()
eq(bg.view.Image, "rbxassetid://124", "rbxassetid://")
s:set("classicBackground", "video:456")
wait()
eq(bg.kind, "video", "video: a Roblox video")
eq(bg.view.ClassName, "VideoFrame", "a VideoFrame")
eq(bg.view.Video, "rbxassetid://456", "its id")
eq(bg.view.Looped, true, "looped")
eq(bg.view.Volume, 0, "muted")
s:set("classicBackground", "video:rbxassetid://457")
wait()
eq(bg.view.Video, "rbxassetid://457", "video:rbxassetid://")
eq(#M.httpLog, before, "ids download nothing")

section("a video that never loads")
M.videoFails = true
statuses = {}
s:set("classicBackground", "video:999")
wait(60 * 5)
eq(bg.kind, "video", "still waiting after 5 s")
wait(60 * 6)
M.videoFails = nil
eq(bg.kind, nil, "given up after 10 s")
check(lastStatus():find("didn't load", 1, true) ~= nil, "says so (" .. lastStatus() .. ")")
check(near(menu.BackgroundTransparency, 0.2), "V2's window again")

section("bad links (Review Focus)")
local function bad(url, body, want, tag)
	M.http[url] = body
	local n = files()
	statuses = {}
	s:set("classicBackground", url)
	wait()
	eq(bg.kind, nil, tag .. ": nothing shown")
	eq(files(), n, tag .. ": nothing saved")
	check(near(menu.BackgroundTransparency, 0.2), tag .. ": V2's window")
	check(lastStatus():find(want, 1, true) ~= nil, tag .. ": says why (" .. lastStatus() .. ")")
end
bad("https://example.com/page", "<!DOCTYPE html><html>nope</html>", "didn't give a picture", "an HTML page")
bad("https://example.com/empty", "", "didn't give a picture", "an empty body")
bad("https://example.com/missing.png", "<html><body>404 Not Found</body></html>", "didn't give a picture", "a .png link giving an error page")
bad("https://example.com/pic.png", "404: Not Found - the file you asked for is gone", "didn't give a picture", "a .png link giving a text error (review)")
bad("https://example.com/json.jpg", '{"error":"not found","code":404}', "didn't give a picture", "a .jpg link giving JSON (review)")
bad("https://example.com/gone.png", { error = "HTTP 404 (Not Found)" }, "download", "a failed download")
local n0 = #M.httpLog
bad("https://example.com/clip.mp4", "whatever", "video id", "a video link")
eq(#M.httpLog, n0, "a video link isn't even downloaded")
bad("https://example.com/clip", "\0\0\0\24ftypisom" .. string.rep("x", 32), "video id", "an MP4 body")
bad("https://example.com/clip2", "\26\69\223\163" .. string.rep("x", 32), "video id", "a WebM body")
statuses = {}
s:set("classicBackground", "hello there")
wait()
eq(bg.kind, nil, "not a link or an id: nothing")
check(lastStatus():find("not a link or an id", 1, true) ~= nil, "says so")

section("the box clears it (review)")
s:set("classicBackground", "123")
wait()
eq(bg.kind, "image", "(an id shown)")
local row = c.settingsRows.classicBackground
row.input.Text = ""
row.input.FocusLost:Fire(true, nil)
wait()
eq(s:get("classicBackground"), "", "an empty box clears the Background")
eq(bg.kind, nil, "and removes it")

section("a picture that never loads: its saved file goes (review)")
local NEVER = "https://example.com/never.png"
M.http[NEVER] = "\137PNG\r\n\26\n" .. string.rep("z", 64)
M.imagesFail = true
local nFiles = files()
statuses = {}
s:set("classicBackground", NEVER)
wait(60 * 11)
M.imagesFail = nil
eq(bg.kind, nil, "given up")
eq(files(), nFiles, "its saved file is deleted (the next try downloads again)")

section("hidden: the wait for loading pauses, a video doesn't play (review)")
M.videoFails = true
menu.Visible = false
s:set("classicBackground", "video:555")
wait(60 * 12)
eq(bg.kind, "video", "the menu closed: still waiting after 12 s")
eq(bg.view.Playing, false, "and not playing while hidden")
menu.Visible = true
wait(2)
eq(bg.view.Playing, true, "playing once the menu shows")
wait(60 * 11)
eq(bg.kind, nil, "shown for 10 s without loading: given up")
M.videoFails = nil
s:set("classicBackground", "video:556")
wait()
s:set("interface", "New")
M.steps(2)
eq(bg.view.Playing, false, "the New interface: paused")
s:set("interface", "Classic")
M.steps(2)
eq(bg.view.Playing, true, "Classic again: playing")
s:set("classicBackground", "")
wait()

section("a newer value wins over an older download")
local SLOW = "https://example.com/slow.png"
M.http[SLOW] = "\137PNG\r\n\26\n" .. string.rep("y", 64)
M.httpDelay = 5
s:set("classicBackground", SLOW)
s:set("classicBackground", "789")
wait(10)
M.httpDelay = nil
eq(bg.view and bg.view.Image, "rbxassetid://789", "the id set last stays")

section("without HttpGet")
M.noHttpGet = true
statuses = {}
s:set("classicBackground", "https://example.com/other.png")
wait()
eq(bg.kind, nil, "no picture")
check(lastStatus() ~= "", "says why (" .. lastStatus() .. ")")
s:set("classicBackground", "321")
wait()
eq(bg.view and bg.view.Image, "rbxassetid://321", "an id still works")
M.noHttpGet = nil

section("New and Unload (Review Focus)")
s:set("interface", "New")
M.steps(1)
eq(c.gui.Enabled, false, "hidden with Classic")
s:set("interface", "Classic")
M.steps(1)
eq(bg.view and bg.view.Image, "rbxassetid://321", "back with it")
getgenv().__HappaTAS3.Unload()
M.steps(3)
local left = 0
for _, d in ipairs(game:GetDescendants()) do if d.Name == "HappaTASBackground" then left = left + 1 end end
eq(left, 0, "Unload leaves no background")

finish()
