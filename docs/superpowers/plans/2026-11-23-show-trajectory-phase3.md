# Show Trajectory phase 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** the green / red lines follow moving parts (phase 3 of the spec), jump off trusses the three measured ways, and every
deferred trajectory bug from phases 1 and 2 is fixed.

**Architecture:** the predictor (`src2/world/trajectory/sim.lua`) passes the step's time to `world.ray` / `world.cast` and
takes a floor hit's `vel` as the floor's speed when the hit says `carry`. The plugin (`src2/world/trajectory.lua`) finds the
moving parts near the character (client objects from the CO registry, else loose parts nearby), measures how each moves
(physics: its assembly's velocity and spin; anchored: its CFrame change between updates; paused with CO data: the frame's
recorded velocity), and answers every query twice: the still world without the movers, then each mover at time t (the
query moved back into the mover's place at the update, one part, Include filter), the nearer hit wins.

**Tech Stack:** Luau, HappaTAS 3 (src2/), headless mock (tests/mock), luau CLI.

**Spec:** docs/superpowers/specs/2026-11-23-show-trajectory-design.md (phase 3 goal + "Phase 3 measured rules").

## Global Constraints

- Conservative Luau (no `+=`, `//`, backticks, `continue`, if-expressions); 200 locals per function.
- No rename of settings or files; no file-format change; Classic keeps its look.
- The lines never move the character, touch the world or change a recording.
- Cost: inside the existing 4 ms update budget, every 4th frame; bench gate passes.

## Review Focus

1. A mover that is removed / destroyed between updates: no error, no line through it.
2. A paused frame scrubbed to another one: the movers' motion comes from that frame, not the last live one.
3. Many movers nearby (a tower full of spinners): the mover count is capped, nearest first.
4. Sync Client Objects off: loose parts nearby still move the line; anchored tweened parts are then still.
5. The line on a platform that turns: carried around (point velocity), not along a straight line.

---

### Task 1: the three truss jumps (sim)

**Files:** Modify `src2/world/trajectory/sim.lua` (climb jump), Test `tests3/test_trajectory.lua`.

- [ ] Test "truss jump: still / climbing up / climbing down": a climbing start (`climb = { n = -Z, top = 40 }`) with vel.Y 0,
  11.2, -11.2 and `tap`; the first point's velocity (points every 1/240 s, (p2 - p1) x 240) is
  `unit((n + UP) x jp / sqrt 2 + UP x vy) x jp` within 0.5 (still: 35.36 out, 35.36 up; up: 30.24 / 39.82; down 41.29 /
  28.21 at jp 50, before gravity).
- [ ] Replace CLIMB_OUT / CLIMB_UP with that rule (the climb's current vy).

### Task 2: moving parts in the predictor (sim)

**Files:** Modify `src2/world/trajectory/sim.lua`; Test `tests3/test_trajectory.lua`.

- `world.ray(origin, dir, t)` / `world.cast(cf, size, dir, t)`: t = game time of the step's start (seconds from the start
  state). A hit may carry `vel` (the surface's speed there) and `carry` (true: it carries a character standing on it).
- Floor: a walkable hit with `carry` sets `floorVel = flat(hit.vel)` (a kit conveyor's effect still wins).
- [ ] Tests (fake world: a 6 x 1 x 6 platform whose top is at y 0 moving +X at 8): standing on it, carried 8 x time
  (within 0.3); walking off its back edge falls when the platform has moved on; a still floor beside it unchanged; a
  platform moving +Y at 4: the line rises 4 x time.

### Task 3: the plugin's movers

**Files:** Modify `src2/world/trajectory.lua`; Test `tests3/test_trajectory.lua` (plugin section).

- Movers = collidable parts that move: CO registry parts (`E.co.reg:eachPart`) when ready, plus unanchored parts within
  `R = 16 + 60 x Trajectory Time` studs (GetPartBoundsInRadius, unanchored only); nearest 24 kept.
- Motion { o = origin, v = velocity at o, w = spin, carry }: unanchored: AssemblyCenterOfMass, AssemblyLinearVelocity,
  AssemblyAngularVelocity, carry true; anchored: CFrame change since the last update over the game time between them
  (TimeControl:rate()), carry false (live: a CFrame-moved part carries nothing, velocity set or not); paused in Create with
  CO data: the shown frame's recorded velocity (player.cur state 36-41), carry by its Anchored.
  A mover still (|v| and |w| below 1e-3) is left in the still world.
- Pose at t: M(t) = translate(v t) * rotation(w t) about o; a query maps back with M(t)^-1 and is cast on that part alone
  (Include filter); hits map forward; `vel` = v + w x (hit - o - v t).
- [ ] Plugin tests: the mock's moving platform (unanchored, velocity +X 8): standing on it, the green line ends carried
  (8 x time); an anchored part moved by CFrame each frame: the line lands where it will be, not carried; a removed
  mover between updates: no error.

### Task 4: deferred trajectory bugs

**Files:** `sim.lua`, `trajectory.lua`, tests.

- [ ] A pending launch is dropped when a climb starts (test: launcher + truss).
- [ ] A launch lasts exactly LAUNCH_TIME (`launchLeft > 1e-9`; test counts the launched steps: 30).
- [ ] `trussAhead` excludes the camera (test: a TrussPart under the camera in front is not grabbed).
- [ ] Climbing up stops under a ceiling (test).
- [ ] The test's leftover `TR.launchersAt` lines go.
- [ ] The launcher box query runs again only after the body moved 0.25 studs (test counts queries).
- [ ] Head room and body box come from the character (R6 head top 2.2 above the root; R15 torso parts) (test: ceiling
  at root + 2.1 stops a jump at once).
- [ ] Jump held is not read from Space while typing (E.typing:active(nil)) (test).
- [ ] The paused key includes the timeline's version (test: a new run at the same frame redraws).
- [ ] Smooth Slow Motion: the line starts at the character's picture (TimeControl:picture()) (test).
- [ ] Floor at ledges: measured live first; the floor check uses the rule measured (center ray, else the body's
  footprint corners) (test: a ledge).

### Task 5: Help, update log, spec, review, gate, live, PR
