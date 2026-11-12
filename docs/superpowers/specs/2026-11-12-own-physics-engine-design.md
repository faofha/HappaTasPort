# An own character physics engine for the speed hack: feasibility study

Date: 2026-11-12. Status: study only, nothing is built. No engine code exists.

## The short answer

- **Recommendation: do not build an own physics engine now.** Slow motion is already exact, because every
  step that runs is Roblox's own physics and the humanoid is frozen in between. An own engine could only
  copy Roblox, never beat it.
- When this study was written, two things were still inexact: **fast motion** (above 1x) and a **loose
  platform the character pushes or stands on** in slow motion. The second is fixed since (see "Update" below),
  so an own engine would now fix only fast motion. It would cost months and put every recorded run at the
  mercy of how exact the copy is.
- The much smaller "Targeted fixes" (section 5) were done first, as recommended.

**Update, 2026-11-12, after the targeted fixes.** With the humanoid frozen on the held frames, holding the
character and a loose platform together no longer breaks their contact. The rule that ran every step while
they touched is gone, so slow motion stays slow on loose platforms. Live, the kit's Pushing Platform at 0.25x
and 0.1x was pushed like at 1x (2.4 to 5.1 studs by 0.3 s in 12 runs, none stalled; at 1x 2.2 to 5.1 and 2
stalls in 8 runs); in half of the runs the push starts 0.03 to 0.07 s later. Diagnostics now counts the place's parts,
loose parts, constraints and collidable meshes, and Help says that fast motion is close, not exact.
- An own engine becomes worth it only if HappaTAS should become a different kind of tool: one that
  re-simulates a run from the keys alone, with savestates. That is a product decision, not a speed hack fix.

## 1. Where the speed hack stands today

The speed hack records in slow or fast motion and saves the run in normal time.

| Case | How it works today | How exact |
| --- | --- | --- |
| Slow motion, the character on fixed parts | Roblox's normal physics runs on some frames. Everything is held on the others, the humanoid frozen with it. | Exact. Live at 1x / 0.25x / 0.1x: jump 7.269 studs at all three, air time 0.527 / 0.529 / 0.525 s, landing lasts 0.050 / 0.046 / 0.050 s, a fall off a ledge within one frame. |
| Slow motion, kit objects (spinners, platforms, timers, beat blocks, bullets) | The kit's scripts run on the TAS clock. Physics-driven parts are held with everything else. | Exact for what the kit drives by its clock. |
| Slow motion, a loose platform you push or stand on | When the study was written: holding both broke their contact, so every step ran at full speed while you touched it. Since the update above: held with the character. | Was **not exact**. Now inside the spread of 1x; the push can start about 0.03 s later. |
| Fast motion (above 1x) | Roblox can't run more physics steps. Gravity, walking and jumping are scaled, and a model puts the humanoid's walking, turning, jumps and timers back on the game clock. | **Close, not exact.** One real step covers 2 to 4 steps of game time, so contacts are resolved more coarsely. |

Two facts from the live client set the limits:

- Roblox refuses extra physics steps while the game runs (`WorldRoot:StepPhysics`: "can only be used when
  game is paused or stopped"), and the call does nothing even after `RunService:Pause()`. So real physics
  can be held back, but never pushed ahead.
- A script can freeze the humanoid (`Humanoid.EvaluateStateMachine`). That is what made slow motion exact.

## 2. What "own engine" can mean

There are three sizes of this idea. They differ a lot in cost and in what they fix.

| | A. Full engine | B. Own humanoid only | C. Targeted fixes |
| --- | --- | --- | --- |
| What HappaTAS simulates itself | Everything about the character: its body, its collisions with the world, the humanoid. Loose parts and their constraints too. | Only the humanoid's controllers (walking, jumping, the floor spring, the state timers). Roblox still does every collision. | Nothing new. The two gaps are attacked directly. |
| Fixes fast motion | Yes, if the engine itself is exact. | Partly: the humanoid side. Collisions stay coarse. | No. Fast motion is labelled honestly instead. |
| Fixes loose platforms in slow motion | Yes, if it also simulates them and their constraints. | No. | Maybe: this is a research task. |
| Rough size | 25,000 to 40,000 lines, 40 to 70 sessions | 3,000 to 5,000 lines, 10 to 20 sessions | 2 to 5 sessions |
| Biggest risk | A copy that is almost right records runs that real Roblox would not allow. | A lot of work for the less important speed range. | The research may find no fix. |

A yardstick for size: Eternal Obbying, the game this idea comes from, has its physics written in Luau. Its
current engine is roughly 35,000 lines in about 40 modules, with about 6,000 more for the simulation loop,
levels and replays. It also keeps separate engines for older versions of Roblox's physics, because Roblox
changes its physics over time. Its engine belongs to its developers: nothing of it may be copied into
HappaTAS, so every line would have to be written and proven again.

## 3. What a full engine (A) would have to replicate

Each row is something Roblox does today that the engine would take over.

| Piece | What Roblox does | What is already known in HappaTAS |
| --- | --- | --- |
| Stepping | Fixed steps of 1/240 s. The velocity changes first, then the position moves. | Measured and used (`SH.Humanoid` in `src2/world/time/control.lua`). |
| Walking | Each step closes 62.5 % of the gap to the wanted speed, capped at 741.6 studs/s^2 on Plastic and 143 in the air. The cap depends on the floor's material. | Measured for Plastic. Other materials are learned while running. |
| Turning (AutoRotate) | A spring towards the move direction: each step the spin keeps 58.3 % and gains 10/3 of the angle left. | Measured. |
| Jumping | The Jumping state pushes the vertical speed to JumpPower x 1.06 at a step's start, then Freefall. | Measured: Running, Jumping at height 0, Jumping at 0.221 studs with 53 studs/s, Freefall. |
| State timers | Coyote time 0.13 s, 0.125 s before Running turns into Freefall, Landed for 0.05 s. | Measured. |
| Floor detection | Rays down from the body find the floor and its material. | **Not modelled.** Today Roblox does it. |
| Hip-height spring | A spring holds the body at its height above the floor (the 0.26-stud sink on landing). | **Not modelled.** |
| Balance | A torque keeps the character upright. | **Not modelled.** |
| Climbing | Rays find trusses and ladders; a climbing controller moves the character. | **Not modelled.** |
| Other states | Swimming, seats, falling down, getting up, platform stand. | **Not modelled.** |
| The body | The character is one rigid body. On R6 the Torso and Head collide, the limbs don't. Mass and inertia come from the parts. | **Not modelled.** |
| Collisions | Contact points between shapes (blocks, wedges, corner wedges, cylinders, balls, trusses, meshes, unions), then a solver that resolves them with friction and bounce. | **Not modelled.** This is the largest and hardest part. |
| Moving floors | The walking force is relative to the floor's velocity, and the floor gets the reaction. | Known in outline (it is why a platform you stand on can be pushed). |
| Loose parts and constraints | Pushboxes, pushing platforms, swings: hinges, sliders, ropes, springs, forces. | **Not modelled.** |

Roughly a third of the list is measured. The measured part is the humanoid on a flat fixed floor. The
unmeasured part, collisions above all, is where obby techniques live: wall hops, corner clips, ladder flicks
and wraparounds all depend on exactly how Roblox resolves a contact.

## 4. How a full engine would connect to the game

**Getting the world in.** The engine has no access to Roblox's own collision data, so it has to read the
workspace itself.

- Fixed parts are read once: shape, size, position, whether they collide, their collision group and
  material. In the EToH kit test place that is 115 collidable parts: 105 blocks, 5 cylinders, a ball, a
  wedge, a corner wedge, a truss, and terrain.
- Parts that move by script or by Roblox's physics (spinners, moving platforms) are read again every step
  as "moving but not pushable".
- Loose parts (14 in the test place) and their constraints (23 there: hinges, sliders, ropes, aligners,
  forces) either get simulated by the engine too, or stay Roblox's. If they stay Roblox's, the gap with
  loose platforms stays as well.
- **A hard limit:** a script cannot read the collision shape of a MeshPart or a Union. Roblox builds those
  shapes internally. The engine could only guess (a box, or a hull). The test place has none that collide,
  but real towers may.

**Writing the result out.** After each engine step the real character is put on the engine's position and
velocity. HappaTAS already does this in Test (`Character:sync`). Roblox's own humanoid would be frozen the
whole time, the way Frame Step freezes it on held frames.

**What still has to work.**

- Touched events (kill bricks, buttons, bounce pads) fire from the real parts. They work in Test today with
  the character moved this way, so they should keep working. This needs checking for every kit object.
- Kit scripts keep running on the TAS clock (Kit Clock). Nothing changes there.
- Client objects that Roblox's physics moves would need the engine's clock, or they would run at real speed
  while the character runs on the engine's.
- Things a kit script does to the character directly (a bounce pad setting its velocity, a launcher's
  force) would have to be picked up from the real character and fed into the engine.

## 5. What each choice adds and what it loses

### A. Full engine

Adds:

- Exact fast motion, if the engine is exact: it can run 2 to 4 steps in one frame.
- Exact loose platforms, if it simulates them and their constraints.
- More than speed: the whole state is plain data, so savestates, exact rewinding by re-simulating, and a
  TAS made of keys alone become possible. This is what Eternal Obbying's design really buys.

Loses:

- Today every simulated step is Roblox's own. With an own engine none is. A run is only as legitimate as the
  copy is exact, and a small error is enough to record a move real Roblox would not allow.
- Meshes and unions can only be guessed.
- Other players and anything the server owns stay outside the engine.
- Roblox changes its physics. Each change can break the copy, and nothing announces it.
- Speed: a solver in Luau at 240 steps a second costs real time every frame.

### B. Own humanoid only

Adds: in fast motion the walking, jumping and timers would be HappaTAS's own, in game time, instead of
Roblox's being corrected afterwards. That removes the correcting model's blind spots (slopes, moving floors,
landings at high speed).

Loses or keeps: collisions are still Roblox's at scaled speed, so fast motion still isn't exact. Slow motion
gains nothing: it is already exact. Floor detection, the hip spring, balance and climbing must all be
written and matched to Roblox first, which is most of the unmeasured list above.

### C. Targeted fixes

1. **Loose platforms in slow motion.** Find a way to hold a character and the loose part it touches
   without breaking their contact. Ideas to test live: freezing the humanoid while the pair runs; holding by
   restoring position and velocity instead of anchoring, now that the humanoid no longer fights it;
   Roblox's own throttle for everything but the character (it slows other parts by fixed ratios).
2. **Fast motion.** Say plainly in Help that fast motion is for getting through waits and is close, not
   exact, and recommend recording the parts that matter at 1x or below.
3. **A census tool.** One script that counts, in the tower being recorded, the things HappaTAS can't follow
   exactly: loose parts the character can reach, constraints, collidable meshes and unions. It tells you
   before recording whether any of this matters there.

## 6. How exactness would be measured

The offline mock is not Roblox, so it cannot prove an engine. The proof has to come from the live client.

1. **A reference library.** For a list of scripted moves, record what real Roblox does at 1x on every
   physics step: position, velocity, spin, humanoid state, floor material. The live harness
   (`tools/live/phys3.lua`) already drives moves this way: standing and walking jumps, walk and stop,
   turning, coyote time, drops. Obby techniques would have to be added: wall hops, corner clips, ladder
   flicks, slopes, moving and spinning floors, pushed boxes.
2. **Replay through the engine.** Feed the same world and the same inputs to the engine offline and compare
   step by step.
3. **Levels of "good enough".**

| Level | Meaning | Good for |
| --- | --- | --- |
| Bit-exact | Every number identical on every step. | A TAS made of keys alone. The only level where long runs can't drift. |
| Step-exact | Within 0.001 studs on every step for 10 seconds of every move in the library. | Recording positions, as HappaTAS does. The minimum for an engine that replaces Roblox while recording. |
| Looks the same | Same heights and times to the eye. | Not enough: obby techniques fail inside the difference. |

Today's Frame Step needs no such proof for slow motion. It was checked against 1x and matches to the frame,
because it is the same engine.

## 7. Phases, sizes and risks if a full engine were built

| Phase | Content | Sessions | Main risk |
| --- | --- | --- | --- |
| 0 | Reference library from the live client, world reader, census tool | 2 to 3 | None. Useful on its own. |
| 1 | Stepping, gravity, a block against fixed blocks: contact points and the solver | 5 to 8 | Matching Roblox's solver. Everything later rests on it. |
| 2 | The humanoid on flat floors: floor rays, hip spring, walking, jumping, states | 6 to 10 | The hip spring and balance are unmeasured. |
| 3 | The character's real shape against walls, wedges, cylinders, balls; friction | 8 to 15 | Obby techniques. Step-exact here is the hardest goal in the project. |
| 4 | Trusses and ladders; moving and spinning floors read from Roblox | 5 to 8 | Climbing is a controller of its own. |
| 5 | Loose parts and the kit's constraints | 10 to 20 | A general constraint solver. |
| 6 | Into HappaTAS: speed control, recording, Touched, client objects, Kit Clock | 5 to 8 | Kit objects that act on the character. |

Total: 40 to 70 sessions and 25,000 to 40,000 lines, if nothing has to be redone. Phases 1 and 3 are
research with no promised end: they are done when the numbers match, not when the code is written.

Smaller alternatives:

- **C, the targeted fixes** (2 to 5 sessions). Recommended first.
- **B, the own humanoid** (10 to 20 sessions). Only worth it if exact-feeling fast motion matters a lot.
- **Ask Eternal Obbying's developers** whether their engine may be used. With permission the work shrinks
  to the world reader and the connection to HappaTAS (6 to 12 sessions). The limits with meshes, other
  players and Roblox updates stay.

## 8. Recommendation and open questions

**Recommendation.**

1. Do the targeted fixes (C) next: the loose-platform research, the census tool, the honest label on fast
   motion.
2. Do not start B or A as a speed hack fix. Slow motion, the mode a TAS is made in, is already exact.
3. Come back to A only as its own product decision: a TAS made of keys with savestates. Then phase 0 is the
   first step, and its reference library is worth having either way.

**Questions to answer before anything is built.**

1. What is fast motion used for? Getting through waits, or recording moves that must be exactly right?
2. After the frozen Frame Step, what still looks wrong in slow motion? A concrete spot in a tower helps most.
3. Do the towers being recorded have meshes or unions the character touches? (The census tool would answer
   this.)
4. How often does a run push or ride a loose platform?
5. Is a TAS made of keys alone, with savestates, something HappaTAS should become?
6. R6 only, or R15 as well?
7. Would asking Eternal Obbying's developers for their engine be an option?

## Appendix: numbers behind this study

- EToH kit test place (counted live, 2026-11-12): 217 parts. Collidable: 105 blocks, 5 cylinders, 1 ball,
  1 wedge, 1 corner wedge, 1 truss, terrain. Loose and collidable: 14 blocks. Constraints and movers: 6
  ropes, 5 hinges, 3 sliders, 3 vector forces, 2 linear velocities, 2 position aligners, 1 orientation
  aligner, 1 ball socket. No collidable MeshPart or Union.
- Frame Step against 1x and the Roblox facts it rests on: the rewrite spec, section 13
  (`2026-10-18-happatas3-rewrite-design.md`).
- The humanoid model used for fast motion: `SH.Humanoid` in `src2/world/time/control.lua`.
