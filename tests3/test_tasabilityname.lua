-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1: the third interface is called Tasability (it shipped as "Compact": a saved "Compact" loads as
-- Tasability) (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local Settings = __T3("engine/settings")
local Env = __T3("platform/env")
local Files = __T3("platform/files")
local Controls = __T3("engine/controls")
local SettingsFile = __T3("persist/settingsfile")
local Lifecycle = __T3("kernel/lifecycle")
local Errors = __T3("kernel/errors")
local HelpText = __T3("ui/win/helptext")
local UpdateLog = __T3("ui/updatelog")
local HttpService = game:GetService("HttpService")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end

section("the name")
eq(table.concat(Settings.byKey.interface.options, ","), "New,Classic,Tasability", "New, Classic, Tasability")
E.settings:set("interface", "Tasability")
M.steps(2)
eq(ui:isCompact(), true, "Tasability is the third interface")
check(ui.compact ~= nil and ui.compact.gui.Visible, "its window shows")
E.settings:set("interface", "New")
M.steps(2)

section("a saved Compact loads as Tasability")
local files = Files.new(Env)
local V3_PATH = "HappaTasPort/Settings3.json"
local saved = files:read(V3_PATH)
files:write(V3_PATH, HttpService:JSONEncode({ format = "HappaTAS3 settings", version = 1, settings = { interface = "Compact" }, controls = {} }))
local st = Settings.new(Errors.new(function() end))
SettingsFile.new(files, st, Controls.new(), Lifecycle.new("name test")):load()
eq(st:get("interface"), "Tasability", "Compact -> Tasability")
if saved then files:write(V3_PATH, saved) end

section("no Compact left where players read")
local bad = {}
for _, t in ipairs(HelpText.topics(E)) do
	if t.title:find("Compact", 1, true) or t.body:find("Compact", 1, true) then bad[#bad + 1] = t.id end
end
eq(#bad, 0, "Help (" .. table.concat(bad, ", ") .. ")")
for _, b in ipairs(UpdateLog.ENTRIES[1].bullets) do check(not b:find("Compact", 1, true), "V3.1 log: " .. b) end
check(not Settings.byKey.interface.desc:find("Compact", 1, true), "the setting's description")
finish()
