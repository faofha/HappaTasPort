# Show Trajectory (HappaTAS 3) - design

Approved direction: dzr, 2026-11-23 ("Then let's build it!" after approach A). This document is for dzr to approve
before any code is written.

## Intent

Like the Show Trajectory mods of Geometry Dash: while you play or make a TAS, lines show where your character will
be over the next moment, so you can see whether a jump lands before you do it.

- **Green line:** what happens with the keys you hold now (walking, holding a direction, holding jump).
- **Red line:** what happens if you jump now. While jump is held, the jump is what will happen, so that line is the
  green one (only green shows). In the air, where a jump can't start, only green shows; inside coyote time a jump
  can still start, so red shows there too.
- Works in Idle and in Create (paused and recording), chosen like Speed Hack In.

## Why it has to be a prediction

Roblox does not let a script run its physics ahead (`WorldRoot:StepPhysics` refuses in a live game, measured
2026-11-12). Eternal Obbying can replay from inputs alone because their game runs on their own deterministic
engine; Roblox's engine is closed and not deterministic run to run. So HappaTAS runs its own copy of the character's
movement for the next few seconds, starting again from the character's real position and speed at every update. It
only has to be right for the next moment: each update corrects any drift.

## Goals

- Settings (one store, shown in the New, Tasability and Classic settings, section "Trajectory"):
  - **Show Trajectory** (on / off, default off).
  - **Trajectory Time** (seconds ahead, default 1, 0.1 - 5).
  - **Show Trajectory In** (Idle and / or Create, default both; a multi row like Speed Hack In).
- Two lines drawn in the world, client only, never seen by game scripts as parts.
- Phase 1 (this build): the character on the world as it is now, measured against Roblox:
  walking (62.5 % of the speed gap per 1/240 s step, at most 741.6 stud/s^2 on the floor, 143 in the air), jumping
  (the jump speed held at each step's start until a step starts there), gravity (workspace.Gravity), coyote time
  (jump until 0.13 s off the floor, Freefall after 0.125 s), landing, walls, slopes (walk up below
  Humanoid.MaxSlopeAngle, slide on steeper ones), rotated parts, wedges, cylinders, balls, meshes and unions.
- Phase 2: trusses (start a climb, climb speed, jumping off), bounce pads and jump launchers (the EToH kit's own
  config values), conveyors.
- Phase 3: moving client objects: a platform you stand on carries the line; moving parts are guessed from their
  current speed and spin.

## Non-goals

- A full copy of Roblox's physics (pushing loose parts, constraints, other players).
- Being exact over long times: the line is a prediction; a longer Trajectory Time drifts more.
- Changing anything the TAS records or plays: the lines are only drawn.

## Anti-goals

- The lines must never move the character, touch the world, or change a recording.
- No measurable lag: the work per frame stays small (below).

## How (decided)

- **Collisions come from Roblox, not from HappaTAS's own shapes:** each step of the simulated character asks
  Roblox with `workspace:Blockcast` / `Raycast` (the character's collision box and its floor ray), so rotation,
  wedges, cylinders, meshes and unions are Roblox's own exact shapes. The character and HappaTAS's own parts are
  excluded.
- **Movement rules:** the ones measured in the client for the speed hack (listed in Goals), stepped at Roblox's
  1/240 s. Floor: a ray down from the root (Humanoid.HipHeight, like Roblox's humanoid); the floor's normal gives
  slopes. Walls: the box cast along the move; the move slides along the wall's surface.
- **Input:** the keys held now (W A S D or the game's MoveDirection), relative to the camera as the game's control
  script does, and the jump key. While paused in Create: the keys held now, from the paused frame's position and
  speed.
- **Start state:** the real root position, velocity, humanoid state, and the coyote timer HappaTAS already keeps.
- **Drawing:** a pool of thin line adornments (`LineHandleAdornment` on Terrain, under HappaTAS's hidden interface
  root), about one segment per 1/30 s of predicted time. Green 0, 255, 0; red 255, 60, 60 (builder may tune).
- **Cost:** the prediction runs at most every 3rd frame while moving, and once when something changes while
  paused; a budget of about 1 ms per update (the line is cut short rather than going over it). Bench gate as usual.
- Settings in `src2/engine/settings.lua`, the feature in a new world module (e.g. `src2/world/trajectory.lua`),
  Help topic text, update log line.

## Testing

- Headless: the mock's measured Roblox controller (tests/mock `M.robloxController`) is the reference: record what the
  mock character really does for the predicted time and compare with the line (walking, a jump, a fall off an edge,
  coyote jump, landing, a wall). Red / green rules: holding jump, in the air, coyote time.
- Live (Real MCP, EToH kit test place): compare the predicted line with the real path for walk, jump, a ledge, a
  wedge, a cylinder; the per-update cost.

## Left to the builder

- Exact segment count and line thickness; how the camera-relative input is read (the PlayerModule's control module or
  the keys plus the camera's look, whichever matches the game live).
- Whether Classic shows the rows (`classicToo`, like Replay Chat): yes unless it breaks Classic's layout.

## Phase 2 measured rules (live, 2026-11-23, EToH kit test place, R6, WalkSpeed 16, JumpPower 50, 60 FPS)

- **Truss (TrussPart):** walking into a truss face starts a climb about 0.1 s after the body touches it (root 0.6 - 0.9
  studs from the face; the root then holds its distance). Climbing speed = 0.7 x WalkSpeed (11.2) times how much
  the move points at the truss: toward it = up, away = down, none = hang (still Climbing, speed 0). At the top the
  climb goes on until the root is 2.4 studs above the truss top, then the character steps over it (Landed on the
  top, walking on). At the bottom, climbing down onto the floor lets go. A jump while climbing: on the first frame
  the velocity is about 34 studs/s away from the truss (along -LookVector, flat: 0.68 x JumpPower) and 42 up
  (0.84 x JumpPower), then gravity and the air steering (143 stud/s^2) as usual; walking toward the truss again grabs
  it again.
- **Conveyor (`ConveyorConfiguration`, Speed 10):** the belt's AssemblyLinearVelocity is LookVector x Speed. On it,
  walking aims at belt velocity + move x WalkSpeed (standing: carried at the belt speed from the second frame; walking
  against a 10 belt: 6). In the air the target is the move alone: the belt speed fades at the air steering rate.
- **Bounce pad (`BouncePadConfiguration`):** the test place's pad has RelativeForce true (Power 100): its RightVector
  points down, so -RightVector x 100 is straight up. A fall onto it left at about 100 up the next frame (93.5 one
  frame of gravity later). Matches the kit's rule.
- **Jump launcher (`LauncherConfiguration`, Force 60):** hitbox `JumpLauncherHitbox` 4 x 4 x 4 around the 3 x 3 x 3
  launcher. A jump inside it: 60 up from the next frame, held for 0.125 s, then gravity (top 17.9 studs above the
  start); no normal jump on top of it. Matches the kit's rule.

## Phase 3 measured rules (live, 2026-11-23, EToH kit test place, R6, WalkSpeed 16, JumpPower 50, 60 FPS)

- **Jumps off a truss (three kinds):** measured again on a lone truss (2026-11-23, "(SPOOKY) Practice.", 1510 trusses): the
  jump's velocity is the jump speed (1.0757 x JumpPower, as for a normal jump) at 45 degrees out (the face's normal) and up,
  with half the climbing speed moved from out to up: hanging still 38.03 / 38.03, climbing up (+11.2) 32.43 out / 43.63 up,
  climbing down (-11.2) 43.63 / 32.43 (each within 0.03, the frame's gravity steps taken off). The first measure in the
  EToH test place (35.4 / 35.4) was on a wall of five trusses: the neighbours deflected the jump (a sideways 4.7).
- **Climbing near the top:** the root climbs on to 2.4 studs above the truss, so the truss is looked for from the root
  down to the feet. **Ceilings:** a block over the body's width (not over the root's centre) stops a jump: the head check
  uses the body's footprint when the ray from the root misses.
- **Moving floors:** a physics part (the kit's MovingPlatform: unanchored, AlignPosition) carries a character standing on it,
  the character's speed following the floor's like a conveyor's. An anchored part moved by setting its CFrame carries
  nothing, with or without a velocity set on it (it slides away under the character).
- **Ledges:** the character keeps standing until its root is about 0.45 studs past the edge facing it (half the body's
  depth less 0.05).
- **Head:** R6's Head collides as its part box (2 x 1 x 1 at +1.5): the head's top is 2.0 above the root.
- The test place's moving parts: MovingPlatform (physics, about 9 stud/s, slowing near its ends), the Spinning Kill Brick
  and the KeyGroup key (not collidable), the Conveyor (anchored, velocity only).
- **Phase 3 live results (2026-11-23):** truss jumps (still / up / down) about 1 stud off after 0.4 s; walking off a ledge
  1.7 studs after the fall (the line used to leave the edge ~0.1 s early); on the kit's MovingPlatform the line is right
  while the platform keeps its speed (0.17 studs at 0.23 s against 2.3 without phase 3) and drifts when it stops or turns
  back (it waits at its ends): a speed-based guess can't see that. A 1 s line costs 1.3 - 1.8 ms with two moving parts
  near (0.6 without); standing still away from moving parts costs nothing. The sliding platform reported a 0.00009 rad/s
  spin (physics jitter): spins under 0.01 rad/s count as none.
- **More live rules (2026-11-23, "(SPOOKY) Practice."):**
  - Climbing: any move climbs up at the full 0.7 x WalkSpeed, also sideways or up to 0.2 away from the truss; more than 0.2
    away climbs down at full speed; no move hangs. There is no sideways movement while climbing.
  - A head hitting a ceiling bounces: the vertical speed comes back at the average of the two surfaces' elasticity (the body is
    Plastic 0.5: Plastic ceiling about half, Ice about a third), and friction takes sideways speed (Plastic: 16 -> 4, Ice:
    16 -> 12 - 14; 0.73 x friction x (1 + elasticity) x the vertical speed).
  - Against a wall the root rests 0.39 - 0.48 from the face (the box's half depth is 0.5): walls are checked with the box
    0.15 smaller across. A wall check starts 0.05 behind the body (a check that starts inside a part ignores it).
  - The body lands on an edge the same way it stands on one (the footprint); after a climb it keeps facing the truss.
  - A plain part's edge being climbed counts as a climb (its face and top), and a truss under a block on its top is still
    grabbed (rays at the body's middle and legs).
  - The lines are worked out on every frame the character or its keys change: about 1.1 ms for both 1 s lines, more near
    walls and moving parts (budget 3 ms).
