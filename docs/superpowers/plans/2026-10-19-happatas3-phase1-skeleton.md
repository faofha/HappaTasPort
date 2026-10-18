# HappaTAS 3 Phase 1 (Skeleton) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A HappaTAS 3 script that builds from `src2/` modules into one file, loads in the headless mock and in an executor, runs an (empty) frame pipeline, and unloads leaving nothing behind.

**Architecture:** Each `src2/` file is one module; `tools/build3.sh` wraps every module in its own function inside one file with a tiny `import` loader (so no function nears Luau's 200-locals limit). Layers built here: platform (executor lookup, services, game calls) and kernel (lifecycle, error reporting, state store, event bus, frame pipeline), plus `main` that starts and unloads them.

**Tech Stack:** Luau (Roblox client, executor), bash + python3 build scripts (existing `tools/strip.py`), the existing headless mock (`tests/mock/`) and test helpers (`tests/test_util.lua`), `luau` CLI.

**Spec:** `docs/superpowers/specs/2026-10-18-happatas3-rewrite-design.md` (sections 3, 4, 10, 11, 12 phase 1).

## Global Constraints

- Conservative Luau syntax only: no `+=`, `//`, backtick strings, `continue`, if-expressions (project convention, the existing code follows it).
- No network code anywhere (no HttpGet / request / loadstring).
- Executor functions: sUNC names first, each looked up with fallbacks; a missing function switches the feature off, never errors. Docs only from docs.projectreal.gg, docs.potassium.pro, sunc.su.
- Game code (camera module, kit functions) is only ever called on its own thread (`gameCall`).
- Debug output only when `CONFIG.Debug = true`.
- Version string for this phase: `"3.0.0-dev"`.
- Never commit `CLAUDE.md` or `claude/`; commit messages describe the change (no quotes of requests), end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; author `-c user.name="Claude" -c user.email="noreply@anthropic.com"` (no git identity on the PC).
- Branch: `v3-rewrite`. `src/parts/`, `wow`, `wow1` (V2.38.16) are not touched.
- Tools on this PC: luau / python3 wrappers are in a Claude scratchpad `bin/` (put it on PATH); bash is Git Bash.

## Review Focus

1. Re-running the script while an older copy runs (V2.38.16's `getgenv().__HappaTAS` or a HappaTAS 3 `getgenv().__HappaTAS3`): the old one must unload first and nothing doubles. Test in Task 6.
2. One handler that errors every frame: the frame goes on for every other handler, the error is printed once, and after 5 failing frames in a row the handler is switched off with a `moduleDisabled` event. Test in Task 5.
3. A handler that yields (calls `task.wait`) inside the pipeline: reported as an error, other handlers in the same stage still run that frame. Test in Task 5.
4. Unload called from inside a frame handler: the rest of that frame's handlers are skipped, no errors. Test in Task 6.
5. Executor without `getgenv` / `cloneref` / `hookfunction`: the script still loads (fallbacks), the missing feature is reported as off. Test in Task 2.

---

## File Structure

| File | Responsibility |
|---|---|
| `src2/modules.txt` | Module names in build order (one per line, path without `.lua`) |
| `src2/config.lua` | `CONFIG` table: `VERSION`, `Debug` |
| `src2/platform/env.lua` | `genv`, executor function lookup with fallbacks, `svc(name)` through cloneref, feature flags |
| `src2/platform/gamecall.lua` | `gameCall(f, ...)` and `gameGet(f, ...)`: run game code on its own thread |
| `src2/kernel/lifecycle.lua` | Ownership of connections / instances / cleanup functions / property changes; `cleanup()` in reverse order |
| `src2/kernel/errors.lua` | Error reporting: once per distinct message, max 25 messages, per-source failure counts |
| `src2/kernel/state.lua` | State store with per-key change watchers |
| `src2/kernel/bus.lua` | Named events between modules |
| `src2/kernel/pipeline.lua` | The frame pipeline: stages, ordered handlers, protection, yield detection, auto-disable |
| `src2/main.lua` | Start: unload older copies, build the kernel, publish the handle; Unload |
| `tools/build3.sh` | Bundles `src2/` into `src2/HappaTAS3.lua`; `--release OUT` also writes the stripped release |
| `tools/build_test3.sh` | Builds `tests3/run_NAME.lua` from mock + bundle + test helpers + `tests3/test_NAME.lua` |
| `tools/test_all3.sh` | Runs every `tests3` suite (and the release smoke) |
| `tests3/test_bundle.lua`, `test_platform.lua`, `test_lifecycle.lua`, `test_state.lua`, `test_pipeline.lua`, `test_main.lua` | One suite per task |

`src2/HappaTAS3.lua` and `tests3/run_*.lua` are build outputs: add them to `.gitignore`.

---

### Task 1: Bundler and module loader

**Files:**
- Create: `src2/modules.txt`, `src2/config.lua`, `src2/main.lua` (stub), `tools/build3.sh`, `tools/build_test3.sh`, `tests3/test_bundle.lua`
- Modify: `.gitignore` (add `src2/HappaTAS3.lua`, `tests3/run_*.lua`, `wow3`)

**Interfaces:**
- Produces: built file layout:
  ```lua
  local __mods, __cache, __loading = {}, {}, {}
  local function import(name) ... end   -- loads once, caches, errors "HappaTAS3: no module <name>" / "HappaTAS3: import cycle: <a> -> <b>"
  __mods["config"] = function(import) <src2/config.lua> end
  ...                                    -- one entry per line of modules.txt, in that order
  local __main = import("main")
  __main.Start()
  ```
  A module file is a chunk that `return`s its table; it may call `import("other")` at its top.
- Produces: `CONFIG = import("config")` → `{ VERSION = "3.0.0-dev", Debug = false }`.
- Produces: `tools/build_test3.sh NAME [BUILD]` writes `tests3/run_NAME.lua` = `tests/mock/{dt,json_lz4,inst,svc}.lua` + `local os = setmetatable({ clock = function() return M.clock() end }, { __index = os })` + `local function __SCRIPT__() <bundle with Debug = true> __T3 = import end` + `tests/test_util.lua` + `$PRE` + `tests3/test_NAME.lua` (same shape as `tools/build_test.sh`). `boot()` from `test_util.lua` runs `__SCRIPT__`.
- Produces: `main.lua` stub returns `{ Start = function() end, Unload = function() end }` (Task 6 fills it).

- [ ] **Step 1: Write the failing test** `tests3/test_bundle.lua`:
  ```lua
  check(boot(3), "boots")
  eq(__T3("config").VERSION, "3.0.0-dev", "config module loads")
  check(__T3("config") == __T3("config"), "a module is loaded once")
  local ok, err = pcall(__T3, "nope")
  check(not ok and tostring(err):find("HappaTAS3: no module nope", 1, true), "unknown module errors clearly")
  finish()
  ```
  Cycle check (outside the mock): create `tests3/fixtures/cycle/` with `modules.txt` (`a`, `b`, `main`), `a.lua` = `local b = import("b") return {}`, `b.lua` = `local a = import("a") return {}`, `main.lua` = `import("a") return { Start = function() end }`. `bash tools/build3.sh --src tests3/fixtures/cycle --check` must exit 1 and print `import cycle: a -> b -> a`.
- [ ] **Step 2: Run it to see it fail**: `bash tools/build_test3.sh bundle && cd tests3 && luau run_bundle.lua` → fails (no build tool yet).
- [ ] **Step 3: Implement** `tools/build3.sh [--src DIR] [--check] [--release OUT]` (default src `src2`, output `DIR/HappaTAS3.lua`): reads `modules.txt`, emits the layout above, each module body indented by one tab inside its function; `--check` loads the bundle in `luau` with a stub `game`/`task` and runs `import` on every module to surface cycles (cycle detection: `__loading[name]` set while a module runs; importing a name that is loading errors with the chain). `--release OUT` runs `python3 tools/strip.py` with header lines `HappaTAS 3.0.0-dev - records and replays TAS runs on the client (executor script).` / `Release build: comments and blank lines removed. The commented source is src2/ (HappaTasPort repository).` `tools/build_test3.sh` as in Interfaces (sed `Debug = false` → `Debug = true` like `build_test.sh`). `src2/config.lua`, `src2/main.lua` stub, `modules.txt` with `config` and `main`.
- [ ] **Step 4: Run it to see it pass**: same command → `RESULT 5 passed, 0 failed` (4 checks + `finish()`'s no-runtime-errors check); `bash tools/build3.sh --src tests3/fixtures/cycle --check` exits 1 with `import cycle: a -> b -> a`.
- [ ] **Step 5: Commit**: `git add src2 tools/build3.sh tools/build_test3.sh tests3 .gitignore && git commit` ("HappaTAS 3: module bundler and loader").

### Task 2: Platform (executor lookup, services, game calls)

**Files:**
- Create: `src2/platform/env.lua`, `src2/platform/gamecall.lua`, `tests3/test_platform.lua`
- Modify: `src2/modules.txt` (add `platform/env`, `platform/gamecall` after `config`)

**Interfaces:**
- Produces `Env = import("platform/env")`:
  - `Env.genv` (table: `getgenv()` or `_G`)
  - `Env.fn(...) -> function?`: first argument that is a function
  - executor functions as fields, looked up with these fallbacks (nil when missing): `writefile`, `readfile`, `isfile`, `isfolder`, `makefolder`, `listfiles`, `delfile`, `appendfile`, `lz4compress`, `lz4decompress`, `gethui`, `cloneref`, `getgc`, `filtergc`, `getconnections` (`getconnections`, `getsignals`, `get_signal_cons`), `hookfunction` (`hookfunction`, `replaceclosure`), `restorefunction`, `iscclosure`, `getloadedmodules`, `setreadonly`, `isreadonly`, `isactive` (`isrbxactive`, `isgameactive`, `iswindowactive`), `keypress`/`keyrelease`, `mouse1press`/`mouse1release`/`mouse2press`/`mouse2release`, `mousemoveabs`, `mousemoverel`, `mousescroll`, `getcustomasset`, `identifyexecutor`
  - `Env.svc(name) -> Instance?`: `game:GetService(name)` through `cloneref` when available
  - `Env.has(feature) -> boolean` for `"files"` (writefile+readfile+isfile+isfolder+makefolder), `"lz4"`, `"hooks"` (hookfunction+restorefunction), `"connections"`, `"filtergc"`, `"hui"`
  - `Env.executor -> string` (`identifyexecutor()` name or `"unknown"`)
- Produces `GameCall = import("platform/gamecall")`:
  - `GameCall.call(f, ...) -> (ran: boolean)`: runs `f(...)` in `task.spawn(pcall, ...)`; returns whether it finished without yielding
  - `GameCall.get(f, ...) -> (ok: boolean, value: any)`: same, returning `f`'s first result when it finished

- [ ] **Step 1: Write the failing test** `tests3/test_platform.lua` with `PRE` lines that simulate executors. Checks:
  - `eq(Env.fn(nil, 5, print), print, "fn picks the first function")`
  - `check(Env.svc("RunService") ~= nil, "svc finds a service")`; with `PRE='cloneref = function(x) return setmetatable({}, {__index = x}) end'` in a second build, `svc` returns a different reference than `game:GetService` (cloneref used)
  - `eq(Env.getconnections, getconnections, "getconnections found")`; with `PRE='getsignals = getconnections; getconnections = nil'`, `Env.getconnections` is `getsignals`
  - with `PRE='getgenv = nil; cloneref = nil; hookfunction = nil'`: boots, `Env.genv == _G`, `Env.has("hooks") == false`
  - `GameCall.call` runs the function on a different coroutine than the caller (`coroutine.running()` captured inside differs) and returns true; a function that calls `task.wait()` returns false; `GameCall.get(function() return 7 end)` returns `true, 7`; an erroring function returns `false`.
- [ ] **Step 2: Run to fail**: `bash tools/build_test3.sh platform && cd tests3 && luau run_platform.lua` → FAIL (`no module platform/env`).
- [ ] **Step 3: Implement** both modules (lookup table built once at load; `has` reads it).
- [ ] **Step 4: Run to pass** (all variants: the default build and the `PRE` builds listed in Step 1; `tools/test_all3.sh` in Task 6 runs them all).
- [ ] **Step 5: Commit** ("HappaTAS 3: platform layer").

### Task 3: Lifecycle and error reporting

**Files:**
- Create: `src2/kernel/lifecycle.lua`, `src2/kernel/errors.lua`, `tests3/test_lifecycle.lua`
- Modify: `src2/modules.txt`

**Interfaces:**
- Produces `Lifecycle = import("kernel/lifecycle")`, `local life = Lifecycle.new()`:
  - `life:own(x) -> x`: x is an RBXScriptConnection (disconnected on cleanup), an Instance (destroyed), or a function (called)
  - `life:connect(signal, fn) -> RBXScriptConnection` (owned)
  - `life:setProp(inst, prop, value)`: remembers the value before HappaTAS's first write per `(inst, prop)`; on cleanup puts it back only if the property still holds the last value HappaTAS wrote
  - `life:cleanup()`: undoes everything in reverse order, each step protected; sets `life.unloading = true` first; safe to call twice
- Produces `Errors = import("kernel/errors")`, `local errs = Errors.new(printFn)` (`printFn` defaults to `warn`):
  - `errs:report(source: string, err: any)`: prints `"[HappaTAS3] <source>: <err>"` once per distinct `source .. err`; stops printing after 25 distinct messages (counts still kept)
  - `errs:count(source) -> number` (total reports for that source)

- [ ] **Step 1: Write the failing test** `tests3/test_lifecycle.lua`:
  - three owned functions run in reverse order on cleanup (`eq(table.concat(order, ","), "3,2,1", ...)`)
  - an owned connection is disconnected (`check(not c.Connected, ...)`); an owned Instance has `Parent == nil`
  - `setProp(part, "Transparency", 0.5)` then cleanup → back to the original `0`; if the game wrote `0.8` after HappaTAS, cleanup leaves `0.8`
  - an erroring cleanup step doesn't stop the others; `cleanup()` twice is harmless
  - `errs:report("Pipeline", "boom")` twice prints once (capture with a `printFn` that appends to a table); 30 distinct messages print 25; `errs:count("Pipeline") == 31` after those 31 reports.
- [ ] **Step 2: Run to fail.**
- [ ] **Step 3: Implement both modules.**
- [ ] **Step 4: Run to pass.**
- [ ] **Step 5: Commit** ("HappaTAS 3: lifecycle and error reporting").

### Task 4: State store and event bus

**Files:**
- Create: `src2/kernel/state.lua`, `src2/kernel/bus.lua`, `tests3/test_state.lua`
- Modify: `src2/modules.txt`

**Interfaces:**
- Produces `State = import("kernel/state")`, `local st = State.new(initial: table?, errs)`:
  - `st:get(key) -> any`
  - `st:set(key, value)`: stores; if the value changed (`~=`), calls the key's watchers with `(value, old)` in registration order, each protected (errors go to `errs:report("state:" .. key, err)`)
  - `st:watch(key, fn) -> unwatch()`
  - `st:snapshot() -> table` (shallow copy)
- Produces `Bus = import("kernel/bus")`, `local bus = Bus.new(errs)`:
  - `bus:on(name, fn) -> off()`; `bus:emit(name, ...)`: calls listeners in registration order, protected; a listener removed during an emit is not called later in that emit

- [ ] **Step 1: Write the failing test** `tests3/test_state.lua`:
  - `set("mode", "Idle")` then `set("mode", "Idle")` calls a watcher once; `set("mode", "Paused")` passes `("Paused", "Idle")`
  - `unwatch()` stops calls; a watcher that errors doesn't stop the next watcher and is reported once
  - `snapshot()` changes don't affect the store
  - bus: two listeners in order; `off()` inside the first listener stops the second only if it is the second's own `off`; emit with no listeners is fine; extra args are passed through.
- [ ] **Step 2: Run to fail.**
- [ ] **Step 3: Implement both.**
- [ ] **Step 4: Run to pass.**
- [ ] **Step 5: Commit** ("HappaTAS 3: state store and event bus").

### Task 5: Frame pipeline

**Files:**
- Create: `src2/kernel/pipeline.lua`, `tests3/test_pipeline.lua`
- Modify: `src2/modules.txt`

**Interfaces:**
- Consumes: `Lifecycle` (Task 3), `Errors` (Task 3), `Bus` (Task 4), `Env.svc` (Task 2).
- Produces `Pipeline = import("kernel/pipeline")`, `local pipe = Pipeline.new(life, errs, bus)`:
  - stages, in frame order: `"PreRender"` (RunService.PreRender), `"PreSimulation"` (RunService.PreSimulation), `"PostSimulation"` (RunService.PostSimulation), `"LateRender"` (`BindToRenderStep("HappaTAS3Late", Enum.RenderPriority.Last.Value + 1, ...)`); a frame without a physics step has no PreSimulation / PostSimulation calls (Roblox behaviour), handlers simply aren't called
  - `pipe:add(stage, order: number, name: string, fn(dt)) -> remove()`: handlers run by ascending `order`, ties in the order they were added
  - `pipe:start()`: connects the four stages through `life` (so cleanup disconnects and unbinds)
  - each handler runs in its own coroutine per call: an error is reported via `errs:report(name, err)`; a handler that yields is reported as `"<name>: yielded (handlers must not yield)"` and its coroutine is closed; either way the next handler runs
  - a handler whose last 5 calls all failed is removed and `bus:emit("moduleDisabled", name, lastError)` fires
  - `pipe:stop()`: no more handlers run (used by Unload; also checked between handlers so an Unload inside a handler skips the rest of that frame)
  - `pipe.frame` (number of PreRender calls so far)

- [ ] **Step 1: Write the failing test** `tests3/test_pipeline.lua` (uses the mock's `M.step(dt)`; `M.simDt` returning 0 for a frame models a frame without physics):
  - order: handlers added as (PreRender, 20, "b"), (PreRender, 10, "a"), (PreSimulation, 10, "c"), (PostSimulation, 10, "d"), (LateRender, 10, "e"), (PreRender, 10, "a2") → one `M.step(1/60)` logs `a,a2,b,` then `c,d` and `e` (the mock runs binds after PreRender: assert per-stage order, and that PreRender handlers ran before PreSimulation ones)
  - `M.simDt = function() return 0 end` for one frame → `c` and `d` not called that frame
  - a handler that errors every frame: other handlers keep running; the error is printed once; after 5 frames the handler is gone and `moduleDisabled` fired with its name
  - a handler that fails twice then succeeds is not removed (the count resets)
  - a handler calling `task.wait()` is reported as yielded and the handler after it still runs in that frame
  - `remove()` removes a handler; `pipe:stop()` from inside handler "a" → "b" doesn't run that frame
  - after `life:cleanup()`: `M.services.RunService.PreRender:Count()` back to the count before `start()`, and the `HappaTAS3Late` bind is gone.
- [ ] **Step 2: Run to fail.**
- [ ] **Step 3: Implement.** Handler list per stage kept sorted on `add`; the per-call coroutine: `local co = coroutine.create(fn); local ok, err = coroutine.resume(co, dt); if ok and coroutine.status(co) == "suspended" then coroutine.close(co); report yielded end`.
- [ ] **Step 4: Run to pass.**
- [ ] **Step 5: Commit** ("HappaTAS 3: frame pipeline").

### Task 6: Main, unload, release build, test runner

**Files:**
- Modify: `src2/main.lua`, `src2/modules.txt` (`main` last)
- Create: `tests3/test_main.lua`, `tools/test_all3.sh`

**Interfaces:**
- Consumes: everything above.
- Produces `Main = import("main")`:
  - `Main.Start()`: (1) unloads older copies: if `Env.genv.__HappaTAS` (V2.38.x) or `Env.genv.__HappaTAS3` has an `Unload` function, calls it in `task.spawn(pcall, old.Unload)` (V2 note: its Unload could take its thread's CoreGui access); (2) creates `errs`, `life`, `state` (initial `{ mode = "Idle", frame = 0, paused = true }`), `bus`, `pipe`; (3) `pipe:start()`; (4) publishes `Env.genv.__HappaTAS3 = { Version = CONFIG.VERSION, Unload = Main.Unload }` and, only when `CONFIG.Debug`, `Env.genv.__HappaTAS3_T = { errs, life, state, bus, pipe, Env }`; (5) prints `[HappaTAS3] loaded 3.0.0-dev` only when `CONFIG.Debug`
  - `Main.Unload()`: `pipe:stop()`, `life:cleanup()`, removes both genv entries if they are ours; safe twice
- Produces `tools/test_all3.sh`: builds, runs every `tests3/test_*.lua` suite (and the `PRE` variants of `test_platform`), then `bash tools/build3.sh --release wow3` and runs `test_main` against `wow3`; prints `ALL PASSED` or exits 1.

- [ ] **Step 1: Write the failing test** `tests3/test_main.lua`:
  - boots; `getgenv().__HappaTAS3.Version == "3.0.0-dev"`; `__HappaTAS3_T` present (test builds have Debug on)
  - a handler added through `__HappaTAS3_T.pipe` runs each frame
  - re-run: `PRE` sets `getgenv().__HappaTAS = { Unload = function() oldUnloaded = true end }` before boot → `oldUnloaded` after boot; calling `__SCRIPT__()` a second time unloads the first HappaTAS 3 copy (its pipeline handler stops running; exactly one PreRender connection from HappaTAS 3)
  - Unload: RunService PreRender / PreSimulation / PostSimulation `:Count()` back to the pre-boot values, no `HappaTAS3Late` bind, both genv entries gone, `Unload()` twice is fine
  - Unload from inside a PreRender handler: the next handler in that frame doesn't run, no errors in logs
  - the release build: `bash tools/build_test3.sh main wow3` passes the same checks.
- [ ] **Step 2: Run to fail.**
- [ ] **Step 3: Implement `main.lua` and `tools/test_all3.sh`.**
- [ ] **Step 4: Run** `bash tools/test_all3.sh` → every suite `0 failed`, `ALL PASSED`.
- [ ] **Step 5: Commit** ("HappaTAS 3: main, unload and test runner").
- [ ] **Step 6: Live check (only if dzr says the Real MCP is connected):** copy `wow3` to `C:\Users\User\AppData\Local\Real\workspace\HappaTasTest\h3p1.lua`, load it in a job with `loadfile("HappaTasTest/h3p1.lua", "=HappaTAS3")()` in the EToH kit test place while V2.38.16 is loaded too; expect V2.38.16 unloaded, `getgenv().__HappaTAS3.Version == "3.0.0-dev"`, no console errors; then `Unload()` and check `getconnections(RunService.PreRender)` holds no HappaTAS 3 function. Back up and restore Settings.json and the place's `.tas` files first; delete HappaTasTest after.
