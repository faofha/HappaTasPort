# Show Trajectory, Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The trajectory lines also follow bounce pads, jump launchers, conveyors and trusses (climbing and jumping off).

**Architecture:** The predictor (`world/trajectory/sim`) gets "effects" from its `world`: the part a floor ray or a wall cast hits can be a bounce pad, a conveyor or a truss, and a query tells whether the body is inside a jump launcher's hitbox. The plugin (`world/trajectory`) builds these from the EToH kit's own config instances (attributes, with the kit's defaults) and Roblox's TrussPart. Truss and conveyor rules are measured live first (task 1); bounce pads and launchers follow the kit's scripts (v6.1.3, read in `claude/reference/etoh_kit_v6.1.3_scripts.zip`).

**Tech Stack:** Luau (conservative syntax), headless mock `tests/mock`, suite `tests3/test_trajectory.lua`.

**Spec:** `docs/superpowers/specs/2026-11-23-show-trajectory-design.md` (phase 2 goals)

## Global Constraints

- Kit rules (scripts, v6.1.3):
  - **BouncePad** (config `BouncePadConfiguration`, defaults Power 100, RelativeForce false): on touch, the root's velocity becomes (vx, Power, vz); with RelativeForce, `-pad.CFrame.RightVector * Power`; the humanoid goes to Freefall (a jump in progress ends).
  - **JumpLauncher** (config `LauncherConfiguration`, defaults Force 60, SizeReduction (1, 1, 1)): the kit makes a non-colliding hitbox `JumpLauncherHitbox` at the part's original size; while the body is inside it and jump is pressed, a LinearVelocity forces `UpVector * Force` for 0.125 s (only Y when the launcher is upright: |Up.X|, |Up.Z| < 0.1; all axes otherwise).
  - **Conveyor** (config name read live in task 1, default Speed 10): the anchored part's AssemblyLinearVelocity is `LookVector * Speed`.
- Speed hack: HappaTAS scales the kit's Power while slowed (KIT_CONFIG); the predictor runs in game time and uses the unscaled value (HappaTAS keeps the base).
- Phase 1's constraints stand (budget, no world changes, conservative Luau, CRLF kept, no wow1, commit format, PR text never quotes dzr).

## Review Focus

1. A bounce pad touched from the side or from below (a wall cast hit, a ceiling ray hit): it bounces as the kit does on any touch (task 2 test "pad from the side").
2. A launcher entered mid-air with jump held: launches when the body enters (task 3 test "held jump into a launcher").
3. Leaving a truss at its top: the climb ends, the walk goes on over the top (task 4 test "truss top").
4. A conveyor under a jump: the line keeps the conveyor's speed in the air (task 2 test "conveyor jump").
5. A pad / launcher / truss config without attributes: the kit's defaults are used (task 5 test "defaults").

---

### Task 1: Live measurements (no product code)

**Files:** Modify `docs/superpowers/specs/2026-11-23-show-trajectory-design.md` (a "Phase 2 measured rules" section).

- [ ] Real MCP, EToH kit test place (back up HappaTasPort first; temporary parts in a folder that is deleted after; restore byte-identical; HappaTasTest deleted; FPS cap kept). Measure and write down:
  - **Truss:** when a climb starts (distance from the truss face, facing / move direction into it), the climb speed (studs/s vs WalkSpeed), what happens at the top (the root's path over the edge), the velocity right after a jump off it (away from the truss and up, vs JumpPower).
  - **Conveyor:** the config instance name; how fast a standing character reaches the belt speed and how walking adds to it (the target velocity on a moving floor); the speed kept after jumping off.
  - **Bounce pad / launcher:** check the kit rules above against the real path (height reached), note any frame delay.
- [ ] Commit `Show Trajectory: phase 2 measured rules`.

### Task 2: Bounce pads and conveyors in the predictor

**Files:** Modify `src2/world/trajectory/sim.lua`; Test `tests3/test_trajectory.lua`.

**Interfaces:**
- Produces: `world.ray` / `world.cast` results gain `part`; `world.effect(part) -> effect?` with effect `{ kind = "bounce", power = number, relative = Vector3? }` (relative: the push vector for RelativeForce) or `{ kind = "conveyor", vel = Vector3 }`.
- Sim: a step whose floor ray or wall cast hits a part with a bounce effect sets the velocity as the kit does and ends a jump in progress; standing on a conveyor makes the walking target `conveyor.vel + move * walkSpeed` (the rule measured in task 1), kept in the air as the start velocity.

- [ ] Failing tests (pure, fake world with effects): "pad from above" (lands, then rises to the height Power gives: Power^2 / 2g within 0.3 studs), "pad from the side" (a wall hit bounces), "relative pad" (velocity = -Right * Power), "conveyor standing" (carried at the belt speed after the measured ramp), "conveyor walking" (adds), "conveyor jump" (keeps the belt speed in the air).
- [ ] Implement; run trajectory - PASS; mutation-check each rule.
- [ ] Commit `HappaTAS 3: trajectory follows bounce pads and conveyors`.

### Task 3: Jump launchers in the predictor

**Files:** Modify `src2/world/trajectory/sim.lua`; Test `tests3/test_trajectory.lua`.

**Interfaces:**
- Produces: `world.launcher(pos: Vector3, box: Vector3, rot: CFrame) -> { up: Vector3, force: number }?` (the launcher hitbox the body is in).
- Sim: a step that starts with jump wanted (held, or the tap on step 1) inside a launcher: for the next 0.125 s the velocity is forced to `up * force` (only Y when upright); no normal jump at the same time.

- [ ] Failing tests: "jump in a launcher" (rises at 60 for 0.125 s, then falls), "tap outside a launcher" (a normal jump), "held jump into a launcher" (launches when the body enters), "tilted launcher" (all axes).
- [ ] Implement; run - PASS; mutation-check.
- [ ] Commit `HappaTAS 3: trajectory follows jump launchers`.

### Task 4: Trusses in the predictor

**Files:** Modify `src2/world/trajectory/sim.lua`; Test `tests3/test_trajectory.lua`.

**Interfaces:**
- Produces: `world.effect(part)` also returns `{ kind = "truss" }`; the sim's climb state: started by the rule measured in task 1, moves up at the measured climb speed while moving into the truss, ends at the top (walks over) or on a jump (the measured jump-off velocity) or when the input leaves the truss.
- Red line on a truss = jump off now; green = keep climbing (or what the keys do).

- [ ] Failing tests with the measured numbers: "climb", "truss top", "jump off", "let go" (no input: hangs / slides as measured).
- [ ] Implement; run - PASS; mutation-check.
- [ ] Commit `HappaTAS 3: trajectory climbs trusses`.

### Task 5: The plugin builds the effects

**Files:** Modify `src2/world/trajectory.lua`; Test `tests3/test_trajectory.lua`; mock additions if needed (attributes, TrussPart class).

**Interfaces:**
- Consumes: tasks 2-4's `world.effect`, `world.launcher`.
- `effect(part)`: `BouncePadConfiguration` child (attributes Power, RelativeForce; kit defaults; Power the unscaled one while the speed hack slows it), the conveyor config (task 1's name, Speed; or a moving anchored part's AssemblyLinearVelocity), `part:IsA("TrussPart")`; cached per part per update.
- `launcher(...)`: the `JumpLauncherHitbox` parts (CollectionService tag or the kit's model layout, found once per second), a box overlap test.

- [ ] Failing tests: kit-like parts in the mock (a pad with BouncePadConfiguration, a launcher with LauncherConfiguration + hitbox, a conveyor, a TrussPart): the green / red lines bounce, launch, ride, climb; "defaults" (configs without attributes).
- [ ] Implement; run trajectory + gate `timeout 590 bash tools/test_all3.sh` - ALL PASSED.
- [ ] Commit `HappaTAS 3: Show Trajectory knows the kit`.

### Task 6: Help, live check, PR

- [ ] Help (Speed Hack topic paragraph: what the lines now follow), update log line (max 60 characters).
- [ ] Live (as task 1's setup): predicted vs real for a bounce pad, a launcher, a conveyor, climbing and jumping off a truss; the cost per update.
- [ ] Gate, rebuild `wow` (restore wow1), push, PR to main for dzr to merge.
