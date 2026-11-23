-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1: Show Trajectory (like Geometry Dash's mods): green = what the held keys do, red = what a jump
-- now does, predicted ahead by HappaTAS's copy of the measured movement rules (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local s = E.settings
local Settings = __T3("engine/settings")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end

section("settings")
do
	local st, tt, si = Settings.byKey.showTrajectory, Settings.byKey.trajectoryTime, Settings.byKey.showTrajectoryIn
	check(st ~= nil and st.default == 0, "Show Trajectory, off by default")
	check(tt ~= nil and tt.default == 1 and tt.min == 0.1 and tt.max == 5, "Trajectory Time: 1 s, 0.1 - 5")
	check(si ~= nil and si.kind == "multi" and si.default == "Idle,Create", "Show Trajectory In: Idle and Create")
	eq(st and st.section, "Trajectory", "in a Trajectory section")
	ui.wm:open("settings")
	M.steps(2)
	local rows = ui.settingsWin.rows
	check(rows.showTrajectory ~= nil and rows.trajectoryTime ~= nil and rows.showTrajectoryIn ~= nil, "New's Settings window has the three rows")
	ui.wm:close("settings")
	s:set("interface", "Classic")
	M.steps(2)
	local cr = ui.classic.settingsRows
	check(cr.showTrajectory ~= nil and cr.trajectoryTime ~= nil, "Classic has Show Trajectory and Trajectory Time")
	check(cr["showTrajectoryIn:Idle"] ~= nil and cr["showTrajectoryIn:Create"] ~= nil, "and a switch per mode")
	s:set("interface", "New")
	M.steps(2)
end

finish()
