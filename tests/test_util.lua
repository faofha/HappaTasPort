-- ================================================================================================
-- test helpers
-- ================================================================================================
T = { pass = 0, fail = 0, failures = {} }
function check(cond, name)
	if cond then
		T.pass = T.pass + 1
	else
		T.fail = T.fail + 1
		T.failures[#T.failures + 1] = name
		M.realPrint("  FAIL: " .. tostring(name))
	end
	return cond
end
function eq(a, b, name)
	local ok = a == b
	if not ok then name = tostring(name) .. "  (got " .. tostring(a) .. ", expected " .. tostring(b) .. ")" end
	return check(ok, name)
end
function near(a, b, eps, name)
	local ok = type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (eps or 1e-6)
	if not ok then name = tostring(name) .. "  (got " .. tostring(a) .. ", expected " .. tostring(b) .. ")" end
	return check(ok, name)
end
function section(s) M.realPrint("-- " .. s) end

-- boots the script inside a coroutine (task.wait needs one), then runs a few frames
function boot(frames)
	M.scriptThread = coroutine.create(function()
		local ok, err = pcall(__SCRIPT__)
		if not ok then M.bootError = err end
		M.booted = true
	end)
	M.resume(M.scriptThread)
	local guard = 0
	while not M.booted and guard < 600 do
		M.step(1 / 60)
		guard = guard + 1
	end
	if M.bootError then M.realPrint("BOOT ERROR: " .. tostring(M.bootError)) end
	M.steps(frames or 5)
	return M.booted and not M.bootError
end

function errorsInLogs()
	local out = {}
	for _, l in ipairs(M.logs) do
		if l:find("ERROR") or l:find("PreRender:") or l:find("PreSimulation:") or l:find("Heartbeat:") or l:find("render step:")
			or l:find("attempt to") or l:find("is not a valid member") then
			out[#out + 1] = l
		end
	end
	return out
end

function finish()
	local errs = errorsInLogs()
	for _, e in ipairs(errs) do M.realPrint("  LOG: " .. e) end
	check(#errs == 0, "no runtime errors in logs (" .. #errs .. ")")
	M.realPrint(string.format("RESULT %d passed, %d failed", T.pass, T.fail))
	if T.fail > 0 then error("tests failed: " .. T.fail, 0) end
end

-- find a descendant by name path "A.B.C" from an instance
function path(root, p)
	local cur = root
	for part in p:gmatch("[^%.]+") do
		if not cur then return nil end
		cur = cur:FindFirstChild(part)
	end
	return cur
end
