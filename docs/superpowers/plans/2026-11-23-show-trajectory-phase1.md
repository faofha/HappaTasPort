# Show Trajectory, Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Green / red trajectory lines for the character on the world as it is now (walk, jump, gravity, coyote, landing, walls, slopes, any part shape), in Idle and / or Create.

**Architecture:** A pure predictor (`world/trajectory/sim`) steps a copy of the character at 1/240 s with the movement rules measured for the speed hack, asking a `world` object (Roblox's Raycast / Blockcast in the game, the same in the mock) for floors and walls. A world plugin (`world/trajectory`) decides when to run, reads the start state and the input, runs the predictor for the green and the red line, and draws both with a pool of `LineHandleAdornment`s (`world/trajectory/draw`). Phases 2 (trusses, bounce pads, launchers, conveyors) and 3 (moving client objects) get their own plans.

**Tech Stack:** Luau (conservative syntax), headless mock `tests/mock`, suites `tests3/test_*.lua`.

**Spec:** `docs/superpowers/specs/2026-11-23-show-trajectory-design.md`

## Global Constraints

- Settings: `showTrajectory` (toggle, default 0), `trajectoryTime` (number, default 1, min 0.1, max 5), `showTrajectoryIn` (multi, options Idle, Create, default "Idle,Create"); section "Trajectory"; no V2 name; `classicToo = true`; labels "Show Trajectory", "Trajectory Time", "Show Trajectory In" (Classic per-mode labels "Show Trajectory in Idle" / "... in Create").
- Movement constants (measured, V2.38.17): step 1/240 s; walking closes 62.5 % of the speed gap per step, at most 741.6 stud/s^2 on the floor, 143 in the air; a jump: Jumping pushes the vertical speed to the jump speed at each step's start until a step starts at it; jump speed = JumpPower x JUMP_SCALE (JUMP_SCALE = 1.06, live; the mock's controller uses 1, tests set `Sim.JUMP_SCALE = 1`), or sqrt(2 g JumpHeight) when not UseJumpPower; coyote: jump until 0.13 s off the floor; gravity = workspace.Gravity clamped to 1000.
- The lines never move the character, touch the world or change the timeline; they exclude the character and HappaTAS's parts from every cast.
- Cost: at most one prediction every 3rd frame while the character moves, once per change while paused; budget 1 ms per update (stop the line where the budget ends). The bench gate (`tools/bench3.sh` in test_all3) must stay OK with the setting off (default).
- Conservative Luau; 200 locals per function; never commit wow1; commits as Claude with the Co-Authored-By line; PR text never quotes dzr.

## Review Focus

1. Character respawn / death while lines are shown: no error, lines go away until the new character loads (Task 3 test "respawn").
2. Switching the setting or the interface off while lines are drawn: every adornment hidden at once (Task 3 test "off hides").
3. Test mode (E.mode 3): never drawn (Task 3 test "not in Test").
4. A start inside a part (spawned overlapping): the predictor neither errors nor shoots the line away (Task 2 test "start overlapping").
5. Very long Trajectory Time (5 s) with a slow budget: the line is cut, the frame isn't (Task 3 test "budget").

---

### Task 1: Settings

**Files:**
- Modify: `src2/engine/settings.lua` (rows after the Glide rows; labels in the V3 names table), `src2/ui/classic/settingsrows.lua` (SECTIONS gets `Trajectory = "Trajectory"` if needed)
- Test: `tests3/test_trajectory.lua` (new; `-- needs: ui`)

**Interfaces:**
- Produces: `E.settings:on("showTrajectory")`, `E.settings:get("trajectoryTime")`, `E.settings:has("showTrajectoryIn", "Idle" | "Create")`.

- [ ] **Step 1: Failing test** section "settings": `Settings.byKey.showTrajectory.default == 0`, `trajectoryTime` default 1 with min 0.1 / max 5, `showTrajectoryIn` kind "multi" default "Idle,Create"; New's Settings window has a row for each; Classic (`settingsRows`) has `showTrajectory` and `trajectoryTime` and the two per-mode switches.
- [ ] **Step 2: Run** `bash <scratchpad>/suites.sh trajectory` - Expected: FAIL.
- [ ] **Step 3: Rows** as in Global Constraints (descriptions in V2's friendly style).
- [ ] **Step 4: Run** trajectory, settings, classicrows, classiclook (row count +4 with the per-mode switches: update its literal with a comment), settingswin, tsettings - Expected: PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: Show Trajectory settings`.

### Task 2: The predictor

**Files:**
- Create: `src2/world/trajectory/sim.lua`
- Modify: `src2/modules.txt` (before `world/trajectory`, after `world/glide`), `tests/mock/svc.lua` (Raycast against parts like Blockcast; both return the entry face's Normal)
- Test: `tests3/test_trajectory.lua`

**Interfaces:**
- Produces: `Sim.run(start, input, world, opts) -> points, info`
  - `start = { pos: Vector3, vel: Vector3, onFloor: bool, offTime: number, jumping: bool, ground: number (root height above the floor), box: Vector3 (collision box), walkSpeed, jumpSpeed, maxSlope (degrees), gravity }`
  - `input = { move: Vector3 (unit or zero, horizontal), jump: bool (held the whole time) }`
  - `world = { ray(origin: Vector3, dir: Vector3) -> { pos, normal }?, cast(cf: CFrame, size: Vector3, dir: Vector3) -> { pos, normal, dist }? }`
  - `opts = { time: number, every: number (seconds between points, 1/30), deadline: number? (os.clock() limit) }`
  - returns `points` (Vector3 list starting at start.pos) and `info = { jumped: bool (a jump started), cut: bool }`
- Produces: `Sim.canJump(start) -> bool` (on the floor, or offTime <= 0.13 and not jumping), `Sim.JUMP_SCALE = 1.06`, `Sim.STEP = 1/240`.

Approach (each step): floor = `world.ray(pos, -up * (ground + 0.1))`; on the floor when it hits, vertical speed <= 0 and the normal's angle from up < maxSlope (then the root snaps to hit.y + ground, vertical speed 0, offTime 0); otherwise offTime += step. Walking as in Global Constraints toward `input.move * walkSpeed`. Jump: when `input.jump` and `Sim.canJump` → jumping; while jumping, a step that starts below jumpSpeed sets it, one that starts at it ends the jump; gravity otherwise when not on the floor. Horizontal move: `world.cast` of `box` lifted by 0.5 along the move; on a hit the move stops at the contact and the velocity loses its part along the normal (slides along walls). A rising root hits a ceiling with `world.ray` up (vertical speed 0). Points every `opts.every`.

- [ ] **Step 1: Failing tests** (section per case) comparing `Sim.run` with the mock's measured controller (`M.humanoidPhysics = true; M.robloxController = true; Sim.JUMP_SCALE = 1`, a floor part whose top is at `M.floorY` and whose edge matches `M.floorEdgeX`), each prediction from the live state, then the mock run for the same time with the same input; every predicted point within 0.05 studs of where the mock root was at that time:
  - "standing": no input, 1 s → all points at the start.
  - "walking": move +X, 1 s.
  - "jump from standing": jump held 0.5 s then the comparison only up to landing (the mock re-jumps while held: also compare 1.5 s with jump held → bunny hops match).
  - "edge": walking off `M.floorEdgeX`, falling.
  - "coyote": `Sim.canJump` true 0.1 s after the edge, false 0.14 s after.
  - "wall": a wall part across +X (the mock character has no walls: expect every point's x <= wall face - box.X/2 + 0.01 and the line continues along the wall when moving diagonally).
  - "slope rule" (pure, a fake world whose floor normal is 30 then 60 degrees from up, maxSlope 89 then 45): 30 degrees walkable, 60 degrees with maxSlope 45 not (falls).
  - "start overlapping": start inside a part → returns points, no error, none further than walkSpeed x time from the start.
- [ ] **Step 2: Run** - Expected: FAIL (`world/trajectory/sim` missing).
- [ ] **Step 3: Implement** `Sim` (one module, no engine imports).
- [ ] **Step 4: Run** trajectory + speedhack (mock change) + kit (Blockcast users) - Expected: PASS.
- [ ] **Step 5: Commit** `HappaTAS 3: trajectory predictor`.

### Task 3: The plugin: when, what, drawing

**Files:**
- Create: `src2/world/trajectory/draw.lua`, `src2/world/trajectory.lua`
- Modify: `src2/modules.txt`, `src2/main.lua` (`E.trajectory = guard(E.plugins:add(Trajectory.new(E)), "trajectory")` after glide), `tests/mock/inst.lua` (class `LineHandleAdornment`: Adornee, CFrame, Length, Thickness, Color3, Transparency, AlwaysOnTop, Visible, ZIndex)
- Test: `tests3/test_trajectory.lua`, `tests3/test_merge.lua` (hook guard list if the plugin uses fill / begin)

**Interfaces:**
- Consumes: `Sim.run`, `Sim.canJump`, the settings of Task 1.
- Produces: `Draw.new(parent) -> d`; `d:line(id: "green" | "red", points, color)`; `d:hide(id?)`; `d:destroy()`. Segments are `LineHandleAdornment`s (Adornee `workspace.Terrain`, AlwaysOnTop true, Thickness 3, pooled, reused).
- Produces: `Trajectory.new(E)` plugin `{ name = "trajectory", order = 70 }` with `onFrameEnd(dt)`; `E.trajectory.lines = { green = points?, red = points? }` (what is drawn, for tests); `Trajectory:wanted() -> bool`.
- Green = `Sim.run(start, { move, jump = held })`; red = `Sim.run(start, { move, jump = true })` only when jump isn't held and `Sim.canJump(start)`; drawn green 0,255,0 and red 255,60,60. `held` = `UserInputService:IsKeyDown(Space)` or `hum.Jump`; `move` = `hum.MoveDirection` (horizontal). Start: the root's position and velocity (Idle, recording) or the paused frame's (`Cframe`, `Lin` columns) while paused; `onFloor` from `hum.FloorMaterial ~= Air`; `offTime` from the coyote timer HappaTAS keeps (`E.time`) else 0 on the floor / 1 in the air; `ground` = HipHeight + root.Size.Y/2 (R15) or 2 + root.Size.Y/2 (R6); `box` = (2, 3, 1) for R6, from the character's extents for R15 (builder's call, checked live). The world excludes the character and HappaTAS's root via `RaycastParams` (Exclude).
- Wanted: setting on, character loaded and alive, `E.mode == 1` with `has("showTrajectoryIn", "Idle")` or `E.mode == 2` with `has(..., "Create")`; never in Test. Rate: every 3rd frame while the root moves; while paused only when the frame, the move or the jump input changed.

- [ ] **Step 1: Failing tests:** "drawn in Idle" (green has points, red too on the floor), "holding jump: only green", "in the air past coyote: only green", "Create paused uses the frame" (green starts at the paused frame's root), "not in Test", "off hides" (setting off → no visible adornment), "Show Trajectory In = Create: nothing in Idle", "respawn" (character removed then added: no error report, lines back after), "budget" (Trajectory Time 5 with `opts.deadline` forced past: `info.cut` and the frame goes on).
- [ ] **Step 2: Run** - Expected: FAIL.
- [ ] **Step 3: Implement** `draw.lua`, `trajectory.lua`, wiring.
- [ ] **Step 4: Run** trajectory, merge, modes, smoke - Expected: PASS. Then `timeout 590 bash tools/test_all3.sh` - Expected: ALL PASSED (bench OK: off by default).
- [ ] **Step 5: Commit** `HappaTAS 3: Show Trajectory lines`.

### Task 4: Help, update log, live check

**Files:**
- Modify: `src2/ui/win/helptext.lua` (a V2-style paragraph in the speed hack's neighbourhood or a new topic "Show Trajectory": the two colours, holding jump, coyote, settings, it's a prediction), `src2/ui/updatelog.lua` (V3.1 bullet, 60 characters max)
- Test: `tests3/test_trajectory.lua` section "help"

- [ ] **Step 1: Failing check** (topic text mentions "Show Trajectory" and "red"; the log has "trajectory"), then the text; help, pages (330-character lines, at most 20 topics: add to an existing topic if 20 are used), updatelog - PASS.
- [ ] **Step 2: Gate** `timeout 590 bash tools/test_all3.sh` - ALL PASSED.
- [ ] **Step 3: Live** (Real MCP, EToH kit test place; back up HappaTasPort, restore byte-identical, delete HappaTasTest, keep the FPS cap): calibrate `JUMP_SCALE`, `ground` and `box` against the real character; compare predicted vs real for a walk, a jump, a ledge fall, a wedge, a cylinder (error at 1 s); measure the cost per update. Ledger every constant changed.
- [ ] **Step 4: Commit**, rebuild `wow` (restore wow1), push, PR to main for dzr to merge.
