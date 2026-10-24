-- Trace adapter for HappaTAS 3: the scenario's view of the script (filled in by phase 2 Task 4).
A = {}
function A.boot() return boot(30) end
function A.mode() return 1 end
function A.frame() return 0 end
function A.paused() return true end
function A.count() return 0 end
function A.frameV2(i) return {} end
function A.frames() return {} end
function A.setSetting(name, v) end
function A.char()
	local ch = M.player.Character
	return ch and ch:FindFirstChild("HumanoidRootPart"), ch and ch:FindFirstChildOfClass("Humanoid")
end
function A.optimizeTwice() end
function A.merge(frames, where) end
function A.mergeClick() end
