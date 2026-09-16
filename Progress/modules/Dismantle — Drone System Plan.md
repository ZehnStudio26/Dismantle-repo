# Dismantle — Drone System Plan

**Status:** plan only. Nothing implemented.
**Date:** 2026-09-15
**Rules:** written to `rules.md` §9 (18-point planning output), §1 (research first), §4 (reuse existing architecture).

---

## 1. Feature Overview

Money earned by cutting the kaiju/mountain with the chainsaw buys **up to 5 autonomous drones**
per player. Each drone flies near its owner, picks a Block, flies to an exposed face, and calls
the *same* mining operation the player's chainsaw calls. Drones supplement the player; they never
replace them.

**Drones are not Tools and never enter the Backpack.** They are autonomous helpers owned by the
Player and living in the world. The `Recon Drone` Tool asset contributes its **mesh only**; its
scripts are not used and the Tool itself is left untouched.

Prototype scope: **no shop building, no plot, no placement UI** — buying a drone spawns it.

---

## 2. Reference Analysis — Flatten The Mountain

FTM's automation reads as: drones orbit the player while idle, break formation to fly at a nearby
block, hover at a short standoff, fire repeatedly on a fixed cadence, and drift back. They are
visibly *slower* than the player's own tool — the fantasy is "my swarm keeps working", not "my
swarm does it for me". Drones never dig somewhere the player is not.

Three behaviours worth copying exactly:

1. **Leashed to the owner.** Drones work in the player's area. They never wander the map.
2. **Visible standoff + travel time.** The flight is the feedback that a drone is working.
3. **Round-robin spread.** Two drones never chew the same block; the swarm fans out.

---

## 3. Research Findings

### 3.1 The supplied asset is not reusable as logic

`ReplicatedStorage.Dismantle.Assets.Tools["Recon Drone"]` is a free model
(credited "NO2ONE and XenoSynthesis"). It is a **player-piloted camera drone**, not an autonomous
helper. Read in full; the problems are structural, not cosmetic:

| Issue | Where | Consequence |
|---|---|---|
| `toggle`, `bG`, `bV`, `cycle`, `mesh`, `gui`, `direction` are **globals** (no `local`) | `Server` | With 5 drones every clone shares `bG`/`bV`; the last spawned wins and the rest go dead. Fatal for our use. |
| `BodyGyro` / `BodyVelocity` | `Server` 34-39 | Deprecated by Roblox in favour of mover constraints. |
| `cycle()` is `while wait(.05)` with **no exit** | `Server` 71-86 | One orphaned thread per spawn, forever. `d:WaitForChild("Mesh")` on a destroyed part yields forever. |
| Remote fired **every frame** while held | `Client` 27-32 | Classic remote-spam anti-pattern. |
| `:connect`, `wait()` | both | Deprecated forms. |
| No `SetNetworkOwner` | `Server` | Physics ownership falls to the client → position is exploitable. |
| Mouse-driven (`player:GetMouse()`, `mouse.Hit`) | `Client` | Directly conflicts with our camera-locked aiming (`MouseBehavior.LockCenter`, `MouseIconEnabled = false`). |

**Verdict: keep the art, discard the scripts.** Reusable: `Handle` (2 × 0.2 × 2, Glass) and its
`Mesh`, plus the 4-frame propeller cycle the script reveals —
`2373177878 → 2373179100 → 2373186965 → 2373356432`. That spin is a nice touch and is kept, moved
to the client (see §8).

### 3.2 Prior art already in this codebase — `ServerScriptService.Miners`

The Drill fork ships an NPC-helper system. What to take and what to avoid:

| Take | Avoid |
|---|---|
| `hrp:SetNetworkOwner(nil)` (`MinerWalkPlaceHandler:67`) — server keeps authority | **One `task.spawn` + `while` loop per NPC.** At 4 players × 5 drones that is 20 loops. One shared loop instead (§15). |
| Per-type stats from a config module, not literals | `PathfindingService` + `Humanoid:MoveTo` — drones fly; pathfinding is cost with no benefit |
| Stuck-recovery fallback (`PivotTo` teleport when the path fails) | `MoveToFinished:Wait()` inside the loop — one stuck NPC stalls its own cycle indefinitely |
| Clear state beats: home → find work → travel → act → home | Reaching across into `plot.Value.Grid` — tight coupling to another system's instances |

### 3.3 Roblox community pattern for flying followers

The settled approach for pets/drones is **not** `Humanoid`, and **not** anchored CFrame writes
from the server (anchored CFrame replication is throttled and stutters on remote clients). It is:

- unanchored part, `Massless = true`, `CanCollide = false`
- **`AlignPosition`** (`Mode = OneAttachment`, goal written to `.Position`) + **`AlignOrientation`**
- **`SetNetworkOwner(nil)`** so the server, not the nearest client, owns the physics

The official `AlignPosition` page describes exactly this: force applied to move one attachment to
a goal position, with `Responsiveness` / `MaxVelocity` shaping the approach. The physics engine
then interpolates smoothly on every client for free, which is the whole reason to prefer it over
scripted CFrame.

- **Formation slotting:** each follower takes slot *i* of *n* and orbits at
  `angle = (i/n) * 2π + t * orbitSpeed`. Standard pet-system maths; stops 5 drones stacking.
- **Claim registry:** one shared `blockKey → drone` table so two drones never target one block.
  This is the spec's "Already targeted −50" expressed as a hard exclusion instead of a weight.

### 3.4 What the project's own specs already mandate

Both supplied specs are unambiguous and agree with each other:

> "The drone should NOT implement its own destruction logic." — Voxel spec §23
> "Do not build three separate destruction engines." — Hierarchical spec §20
> "Do not let each drone randomly select a voxel." — Voxel spec §22
> "Block → find exposed surface → choose target position → MiningService" — Hierarchical spec §48

---

## 4. Existing Systems That Can Be Reused

This is the part that makes the feature small. **`MiningService` was built for this.**

| Existing | Reuse | Evidence |
|---|---|---|
| `MiningService.mine(source, pos, normal, stats)` | Called verbatim by drones | Header line 2: "Player, drone and turret all call `MiningService.mine()`" |
| `sourceOrigin()` accepts `BasePart` and `Model` | Drone passes itself as `source`; range check works unmodified | `MiningService:70-74` |
| Per-source cooldown keyed by instance | Each drone gets its own rate for free | `lastMine[source]`, `:88` |
| `MiningService.forget(source)` | Called on drone despawn so `lastMine` cannot grow | `:56-58` |
| `Events.BlockBroken` carries `Source` | Reward attribution hook already exists | `:147` |
| `grid.blockAlive` (blockKey → standing count) | Candidate list for targeting | `VoxelGrid` |
| `grid:blockVoxels(bk)` (standing coords in a Block) | Pick an aim voxel | `VoxelGrid` |
| `VoxelGrid.blockCentre(bk)` | Distance scoring | `VoxelGrid` |
| Client `BlockHit` / `BlockBroken` remotes | Glow, sway, pop, debris, dust fire for drone hits with **zero new code** | Block Break plan §192: "fires for any source, so drones inherit all of this for free" |
| `CollectionService` tag convention (`KaijuVoxel`) | Tag drones `DismantleDrone` for client FX | existing pattern |
| `Config` single-knob style | `Config.Drone` block | existing |

**Net new destruction code: zero.** A drone is a targeting-and-movement problem only.

---

## 5. Required New Systems

The Voxel spec proposes six modules (`DroneSpawner`, `DroneController`, `DroneTargetSelector`,
`DroneMovement`, `DroneMining`, `DroneUpgradeStats`). I am deliberately collapsing that to **two
files plus one client module**:

| File | Class | Job |
|---|---|---|
| `ServerScriptService.Dismantle.DroneService` | ModuleScript | Registry, claim table, spawn/despawn, one shared update loop, targeting, movement, mining |
| `ServerScriptService.Dismantle.DroneServer` | Script (gated) | Purchase remote, price/cap validation, player lifecycle, wiring. **No Tool hand-out** — contrast `KaijuServer.giveCutter`, which must re-grant the Chainsaw on every `CharacterAdded`; drones need no equivalent because they are not Tools |
| `ReplicatedStorage.Dismantle.Modules.DroneFX` | ModuleScript | Client propeller spin, deploy/recall puff |
| `ReplicatedStorage.Dismantle.Remotes.BuyDrone` | RemoteEvent | Purchase request |

**Why not six modules.** Target selection, movement and the mine call are ~30 lines each and have
exactly one caller. Six files would be six `require`s and six places to look for one loop. The
split point is real but not here yet: **when turrets arrive they share target selection**, and that
is when `DroneTargetSelector` earns its own file. Noted, not pre-built.

Also required: `RewardService` gains owner attribution (§11) — a ~4 line change to a file whose
`ponytail:` comment already predicts it.

---

## 6. Gameplay Flow

```
Player cuts blocks ──► Block completes ──► RewardService ──► leaderstats.Credits +1
                                                                    │
                                              HUD "Buy Drone $25 (0/5)" ◄┘
                                                                    │
                                                     click ──► BuyDrone remote
                                                                    │
                            server: Credits >= price? count < 5? ───┤
                                                                    ▼
                              deduct ─ spawn drone in world ─ tag ─ register ─ starts working
                              (no Tool, no Backpack, no equip step — buying IS deploying)
                                                                    │
                                                                    ▼
    ┌──────────────────────────── drone update loop ────────────────────────────┐
    │  IDLE ──(work available in leash)──► TRAVEL ──(within reach)──► MINING     │
    │    ▲                                    │                          │       │
    │    │                                    │ target gone / blocked    │       │
    │    └────────────────────────────────────┴──────────────────────────┘       │
    │  orbit owner                                          block done → release │
    └───────────────────────────────────────────────────────────────────────────┘
```

**States: `Idle` → `Travel` → `Mining`.** Three, not more. Every transition below is listed in §13.

---

## 7. Animation Flow

Drones have no skeleton. "Animation" is three things:

1. **Propeller spin** — cycle the `Mesh.MeshId` through the 4 frames at ~0.05s.
   **Client-side, one loop for all drones**, driven off the `DismantleDrone` tag. The free model
   did this on the server with a leaking per-drone thread; that is the bug being designed out.
2. **Bank into travel** — `AlignOrientation` goal tilts toward the velocity vector, so a drone
   leans as it flies and levels out when hovering. Free banking, no keyframes.
3. **Recoil bob** — on each mine, a small client-side position kick away from the face, reusing
   the same "compute from elapsed time, restore exact base" technique as the Block pop, so repeated
   hits cannot accumulate drift.

---

## 8. VFX Flow

| Beat | Effect | Where |
|---|---|---|
| Deploy | Dust puff + drone fades in over ~0.2s | Client, `DebrisFX.dust` reused |
| Travel | Faint thruster trail | Client |
| Mine impact | **Nothing new.** `BlockHit` already fires for any source → glow, sway, texture slip, pop, debris | Already built |
| Block done | **Nothing new.** `BlockBroken` fires → dust, collapse, `+$` popup | Already built |
| Recall / owner leaves | Puff + fade out | Client |

A cutting beam from drone to face is *optional polish*, listed in §18, not in the build order.

---

## 9. SFX Flow

- Continuous rotor hum, looping `Sound` on the drone `Handle`, `RollOffMaxDistance` tuned so 5
  drones do not wall of noise. Volume scales slightly with speed.
- Mine impact reuses the existing `Assets.Sounds.Hit` at reduced volume — the server already plays
  positional hit/break audio in `KaijuServer`, and that path is source-agnostic, so **drone hits
  are already audible with no new code**. Only the rotor is new.

---

## 10. Hit Detection / Interaction Logic

Per Hierarchical spec §48 — "find exposed surface", not "aim at block centre":

```
1. candidate Blocks := keys of grid.blockAlive
2. reject: claimed by another drone
3. reject: blockCentre beyond Config.Drone.Leash from OWNER
4. score := distance from drone to blockCentre        (nearest wins)
5. claim the winner
6. aim voxel := nearest standing coord from grid:blockVoxels(bk)
7. standoff := hover Config.Drone.Standoff studs off that voxel
8. raycast drone ──► aim voxel centre
9. ray hit tagged "KaijuVoxel"?  → mine(drone, result.Position, result.Normal, Config.Drone)
                    otherwise    → blocked; release claim, retarget
```

**Why a raycast rather than computed geometry.** It is the same thing the player's
`acquireTarget()` does, so drones and players are validated identically. It yields a true surface
`Position` and `Normal`, which is exactly what `MiningService` wants. And it self-solves the
spec's "Blocked voxel −20": if the ray cannot reach, the drone genuinely cannot mine there. The
`RaycastParams` must exclude the drone itself, other drones and characters.

**Drones must be `CanQuery = false`.** A drone drifting across the player's crosshair would
otherwise intercept the aim ray and make the target glow flicker — the same trap `DebrisFX` already
documents for debris.

---

## 11. Client / Server Responsibilities

| Server (authoritative) | Client (cosmetic only) |
|---|---|
| Owns drone existence, position goal, targeting, claims | Propeller spin |
| Calls `MiningService.mine` — every existing validation applies | Thruster trail, deploy/recall puffs |
| Validates purchase: price, credit balance, 5-drone cap | Recoil bob |
| `SetNetworkOwner(nil)` on every drone | Buy button + count display |
| Credits the owner on Block completion | Rotor audio |

The client **never** tells the server where a drone is or what it hit. `BuyDrone` carries no
arguments — a client that fires it 100 times gets one drone and 99 rejections.

### Reward attribution — the one change to an existing file

`RewardService:23-29` currently credits only `Player` sources; its own comment says
*"Drones/turrets will carry an Owner to credit."* Plan: each drone holds an `Owner` `ObjectValue`
(or `:SetAttribute` is not usable — attributes cannot hold Instances, so `ObjectValue`). Resolve:

```
source is Player          → credit source
source has Owner ObjectValue → credit Owner.Value
otherwise                 → no credit
```

---

## 12. State Management

**One registry, one loop.**

```lua
drones[drone] = {
    owner      = Player,
    slot       = 1..5,          -- formation index
    state      = "Idle" | "Travel" | "Mining",
    target     = blockKey?,     -- nil unless claimed
    aimPos     = Vector3?,
    failures   = 0,             -- consecutive blocked rays; N -> blacklist briefly
    nextThink  = 0,             -- os.clock gate for retarget
}
claims[blockKey] = drone        -- inverse index; exactly one drone per Block
byOwner[Player]  = { drone, ... }
```

Invariant to hold: `claims[k] == d` **iff** `drones[d].target == k`. Every release path
(mined out, blocked, owner left, rebuild, despawn) must clear **both** sides. This is the single
most likely source of a leak in this feature.

---

## 13. Timing Specification

| Beat | Value | Reasoning |
|---|---|---|
| Movement update | every `Heartbeat` | constraint goal write, one loop for all drones |
| Retarget think | ≥ 0.25s per drone, and only when `Idle` or target invalid | 508 Blocks scanned per think; cheap, but not every frame |
| `Config.Drone.Cooldown` | **0.8s** | slower than the player's 0.45s swing — a supplement, not a replacement |
| Arrival threshold | within `Reach × 0.8` of aim point | hysteresis so it does not flip Travel/Mining each frame |
| `Config.Drone.Standoff` | 8 studs off the face | visible gap; reads as "working at" not "inside" |
| `Config.Drone.Leash` | 120 studs from owner | ≈ the mountain's radius; drones stay in the player's area |
| `Config.Drone.Speed` | 45 studs/s (`AlignPosition.MaxVelocity`) | faster than a walking player so they keep up |
| Orbit period (idle) | 4s | slow, readable |
| Propeller frame | 0.05s | as authored in the source asset |
| Deploy fade | 0.2s | matches existing FX timing |

### Damage and the resulting pace

Proposed `Config.Drone.DamageLevel = 2` — existing `Damage[2]` is `Single / Power 3 / no Max`, so
one chunk per hit, and Turf hardness is 3, so **one chunk destroyed per drone hit**.

```
player : 3 chunks damaged per 0.45s swing, 3 HP each  ≈ 1 chunk / 0.45s  = 2.22 chunk/s
drone  : 1 chunk per 0.80s                            = 1.25 chunk/s   (≈ 56% of a player)
5 drones + player                                     ≈ 8.5 chunk/s    (≈ 3.8× solo)
```

Mountain is **6,265 chunks**. Solo ≈ 47 min → **with 5 drones ≈ 12 min.** That is a session length
worth having, and it is the argument for these specific numbers.

---

## 14. Economy

**Hard number:** the mountain contains **508 Blocks**, and `Config.Reward.PerBlock = 1`, so one
fully-flattened mountain pays **508 Credits**. Every price below is measured against that ceiling.

| Drone | Price | Cumulative | % of one mountain |
|---|---|---|---|
| 1 | 15 | 15 | 3% |
| 2 | 30 | 45 | 9% |
| 3 | 60 | 105 | 21% |
| 4 | 100 | 205 | 40% |
| 5 | 150 | 355 | 70% |

Rationale: the first drone must land early enough to teach the mechanic (3% of a mountain ≈ 40s of
cutting); the fifth is a genuine goal but reachable inside a single mountain, so a prototype tester
can see the full swarm without a grind. Escalating cost keeps each purchase a decision.

**These are design numbers, not derived ones** — flagged for confirmation, easy to change
(`Config.Drone.Prices`).

---

## 15. Performance Considerations

| Concern | Budget | Mitigation |
|---|---|---|
| Update loops | **1** total | One `Heartbeat` for all drones. Explicitly *not* the Drill Miners' loop-per-NPC. |
| Instances | 20 drones × (1 part + 2 attachments + 2 constraints + 1 sound) = **120** | Flat, no growth |
| Raycasts | ~20 drones / 0.8s = **25 rays/s** | Negligible |
| Target scan | 508 Blocks × 20 drones, but only on think (≥0.25s apart, and only when idle) | `ponytail:` linear scan; if profiling complains, bucket Blocks by region |
| Physics | 20 unanchored massless parts, no collision | Trivial; this is what pet systems run at scale |
| `lastMine` table growth | unbounded if ignored | `MiningService.forget(drone)` on every despawn — **mandatory** |
| Propeller MeshId writes | server would replicate 20 × 20/s | Client-only, one loop, zero replication |
| Rotor audio | 20 looping sounds | `RollOffMaxDistance` capped; consider per-owner cap if it muddies |

---

## 16. Edge Cases

| # | Case | Handling |
|---|---|---|
| 1 | Owner leaves | Destroy their drones, release claims, `MiningService.forget` each |
| 2 | Owner dies / respawns | Re-home to the new character; drones persist |
| 3 | Owner walks out of leash while drone is mining | Finish current mine, then return to formation |
| 4 | Target Block destroyed by the *player* mid-flight | `blockAlive[bk]` gone → release claim, retarget |
| 5 | Mountain hits 100% and rebuilds (`grid:reset()`) | **All `blockModels` are destroyed.** Every claim must be flushed on `MiningService.rebuilt()` / `onComplete`, or drones hold keys to dead Blocks forever |
| 6 | Drone spawned before the grid finishes building | Spawn Idle; targeting no-ops until `blockAlive` is populated |
| 7 | Ray blocked (another Block in the way) | `failures += 1`; after 3, release and blacklist that Block for 5s |
| 8 | Two drones pick the same Block | Impossible by construction — claim registry |
| 9 | Player buys a 6th drone | Server rejects; cap is server-side, the button is only a hint |
| 10 | Player buys with insufficient Credits | Server rejects; client never deducts |
| 11 | `BuyDrone` spammed | Rate-limited server-side; purchase is idempotent per validation |
| 12 | Drone falls behind / desyncs | If distance to owner > 2× Leash, teleport to formation slot (the Miners' stuck-recovery idea) |
| 13 | Game mode is Drill | `DroneServer` carries the `--[[DISMANTLE-GATE]]` line like every other Dismantle script |
| 14 | Drone gets shoved by a player | `CanCollide = false`, `Massless = true`, server network ownership |
| 15 | Drone intercepts the player's aim ray | `CanQuery = false` |

---

## 17. Implementation Steps

Ordered so each step is independently testable.

1. **`Config.Drone` block** — stats, prices, leash, standoff, cap. No behaviour yet.
2. **Build the drone template** — clone the `Recon Drone` `Handle` + `Mesh` into the (currently
   empty) `Assets.Models.Drone` folder as a standalone Part. The Tool itself is **not touched and
   not used**; nothing is deleted.
3. **`DroneService.spawn/despawn`** — build the part + attachments + constraints,
   `SetNetworkOwner(nil)`, tag `DismantleDrone`, register. Test: a drone appears and hovers.
4. **Formation + movement loop** — one `Heartbeat`, slot orbit around the owner. Test: 5 drones
   orbit without stacking, and keep up when the player runs.
5. **Targeting + claims** — scan, score, claim, release. Test: log-free assertion that
   `claims` and `drones[d].target` never disagree.
6. **Mining** — raycast, call `MiningService.mine`. Test: blocks break; existing glow/pop/debris
   fire with no new client code.
7. **Reward attribution** — `Owner` ObjectValue + `RewardService` resolve. Test: drone kills pay
   the owner.
8. **Purchase** — `BuyDrone` remote, server validation, HUD button + count. Test: cap and price
   enforced with the client lying.
9. **Client FX** — propeller, trail, bob, rotor audio.
10. **Rebuild + lifecycle** — claim flush on rebuild, cleanup on leave/respawn.

Steps 1-6 are the feature. 7-10 are what make it shippable.

---

## 18. Open Decisions — need your call

**A. Backpack semantics — SETTLED 2026-09-15: no Tool.** Drones are autonomous helpers. The
`Recon Drone` Tool is not used at all; only its **mesh** is taken, as the drone's visual.
(Superseded options A1 "Tool as token" and A2 "active only while equipped" are dropped.)

This removes work rather than adding it:

- No equip / unequip lifecycle, no `Tool.Activated` desync guard.
- **No respawn re-granting.** Tools are cleared from the Character on death — a Backpack token
  would have needed the same `giveCutter`-style re-hand-out on every `CharacterAdded`. Drones
  live in the world, owned by the *Player*, so a respawn does not touch them; they simply re-home
  to the new character (§16 case 2).
- No Backpack slot competing with the Chainsaw.
- Purchase deploys directly. Buying *is* spawning.

**B. Deleting the free-model scripts — MOOT.** Since the Tool is not used, nothing needs deleting.
`Assets.Tools["Recon Drone"]` is **left exactly as it is, untouched**, and its `Client` / `Server`
/ `Communications` scripts never run (they only run from a Backpack or Character). The drone
template is built separately from the mesh into `Assets.Models.Drone`, which is currently an empty
folder and is the natural home for it.

**C. Prices in §14** are chosen against the 508-Credit mountain, not derived from a tuning pass.

**D. Drone rate (0.8s) and damage level (2)** give ≈12 min for a 5-drone mountain. Faster drones
trivialise the chainsaw; slower ones make the purchase feel dead.

**E. Deferred deliberately:** drone upgrades (speed/count/range tiers from the GDD), turrets,
`ProfileStore` persistence of owned drones (prototype = session-only), and the drone→turret shared
target selector.

---

## 19. Testing Checklist

- [ ] 5 drones orbit without overlapping; formation holds while the owner sprints
- [ ] No two drones ever hold the same `blockKey` (assert on the claim invariant)
- [ ] Drone hits produce identical client FX to player hits
- [ ] Owner is credited for drone-completed Blocks; a second player is not
- [ ] Buying with insufficient Credits fails server-side even with a forged remote call
- [ ] 6th purchase rejected
- [ ] Player leaves → drones gone, `lastMine` and `claims` empty
- [ ] Mountain rebuild → all claims flushed, drones resume on the new mountain
- [ ] Drone never makes the player's target glow flicker (`CanQuery = false`)
- [ ] 20 drones (4 players × 5): server frame time unchanged within noise
- [ ] Drill mode: no drone code runs at all

## 20. Polish Checklist (rules.md §7)

- [ ] Travel reads as purposeful, not jittery — banking matches velocity
- [ ] Rotor audio does not stack into noise at 5 drones
- [ ] Recoil bob does not accumulate drift over hundreds of hits
- [ ] Deploy/recall have a visible beat, not a pop-in
- [ ] Drones visibly slower than the player — the fantasy is a swarm assisting
- [ ] Repeated buy/leave/rejoin leaves zero orphaned instances or connections
