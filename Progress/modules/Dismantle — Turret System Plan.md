# Dismantle — Turret System Plan

**Status:** plan only. Nothing implemented.
**Date:** 2026-09-15
**Builds on:** *Dismantle — Drone System Plan* and *Dismantle — Drone Laser & Auto-Helper Plan*.
Targeting, purchase, ownership-survives-the-body, reward attribution and the Beam laser are all
inherited; this document covers only what a turret does **differently**.

---

## 0. The model is a placeholder — needs your call

`Assets.Models.Turrets` inspected live:

```
Turrets (Model)  2 descendants
  Handle (Part)  2 x 0.2 x 2  Glass
    Mesh (SpecialMesh)  mesh=rbxassetid://2373177878  tex=rbxassetid://2597144836
```

That mesh and texture are **byte-identical to the Recon Drone's Handle** — it is a copy of the
same flat glass disc, not a turret. Three options in §18 A; my recommendation is the `ufo` Model
already sitting in `Assets.Models`, which is 22 parts with DiamondPlate/Neon panels **and a
SpotLight**, and reads far more like an orbiting weapon platform than a 0.2-stud disc.

---

## 1. Feature Overview

Turrets are the **side** counterpart to drones. A purchased turret takes a slot on a ring around
the kaiju, **orbits it continuously**, and holds a **yellow** laser fired **horizontally inward**
into the flank. Drones shave the crown; turrets shave the shoulders. Together the silhouette
comes down from every direction, which is what "flatten" means.

---

## 2. Reference Analysis — Flatten The Mountain

FTM's turrets read as fixed emplacements that sweep the mountain's sides with a held beam while
the player and drones work the top. Three things carry it:

1. **Motion is constant and indifferent.** A turret never reacts to the player. It circles at a
   steady rate whatever else is happening, which is exactly what makes it read as machinery
   rather than as another helper.
2. **The beam is horizontal.** It cuts *into* the flank, so the mountain narrows as well as
   shortens.
3. **They close in.** As the flank recedes the turret follows it inward, so the beam length stays
   roughly constant instead of stretching into a thin thread.

---

## 3. Research Findings

### 3.1 What the project's own specs mandate

> "Turret → Ray/beam target → Block → Hit Position → MiningService.
> **The turret's laser is only the visual representation.** Actual destruction is: MiningService."
> — Hierarchical spec §49

> "Turrets should: Find Block → Aim → Play beam → Call MiningService. The beam is visual. The
> MiningService is authoritative." — Hierarchical spec §22

So: no new destruction path, and the beam must never be load-bearing. Same conclusion the drone
work already landed on.

### 3.2 Movement — and why turrets must NOT copy the drones

This is the one real engineering decision, and the answer differs from drones on purpose.

Drones use `AlignPosition` because their motion is **reactive and unpredictable** — they chase a
target that moves, a player that runs, a slot that reshuffles. A spring constraint is the right
tool for chasing.

A turret's path is a **perfect circle, fully known in advance**. Three options:

| | Approach | Verdict |
|---|---|---|
| 1 | `AlignPosition` chasing a moving goal | **Wrong tool.** A spring always trails its goal, and on a circular path trailing means *cutting the corner* — the turret would sit permanently inside its own radius and lag the angle. Smooth, but not the path asked for. |
| 2 | **Anchored + server-set `CFrame` each Heartbeat from an angle** | **Recommended.** Exact path, no physics, server position is trivially authoritative for the range check, and Roblox interpolates anchored CFrame replication on clients. The orbit is slow (~41 studs/s at r=130, 20s per revolution), which is well inside what interpolation smooths. |
| 3 | Deterministic on both sides from `workspace:GetServerTimeNow()` | Perfectly smooth and zero replication, but needs a client-local visual separate from the server's authoritative virtual position — real extra machinery. Hold as the upgrade if 2 visibly stutters. |

Going with **2**, and stating the reason in the source, because a turret moving by a different
mechanism than a drone otherwise looks like inconsistency rather than a decision.

Anchored also means **no `SetNetworkOwner`**, no welding pass, no mass concerns — a whole class of
the drone's setup simply does not apply. `CanQuery = false` on every part still does.

### 3.3 Targeting — the raycast *is* the targeting

The drone scans `grid.blockAlive`, scores candidates and claims one. **A turret needs none of
that.** It sits outside the mountain and fires at the axis, so:

```
ray from turret position ──► (Origin.X, turretY, Origin.Z)
first KaijuVoxel hit = the flank at this angle and height
```

Whatever the ray hits first *is* the outermost standing material at that bearing, by definition.
No scan, no scoring, no claim registry — and no possibility of two turrets fighting over a target,
because they occupy different angles by construction.

That removes an entire subsystem relative to the drone. Worth stating plainly so it does not look
like an omission.

### 3.4 Closing in, and dropping down

Two adjustments keep a turret productive as the mountain erodes:

- **Radius follows the flank.** After each successful shot the turret keeps a fixed standoff from
  the surface it just hit. Without this the beam stretches from 130 studs out to a receding wall
  and `Reach` would have to be enormous.
- **Height drops a layer when a full revolution lands nothing.** That is the honest completion
  signal for a height band: if the turret has been all the way round and hit nothing, there is
  nothing left at that height.

### 3.5 Geometry (measured live)

```
Origin           = (0, 102, 2120)      VoxelSize = 6
Mountain radius  = 18 voxels = 108 studs
Mountain height  = 13 voxels = 78 studs     base y = 99, peak y = 180
Block layers     = 0..6, 12 studs each
Ground           = 512 x 512, top face y = 99
```

So an orbit radius of **130 studs** clears the widest point by 22 studs and sits comfortably
inside the 512-stud ground plate.

---

## 4. Reused, Not Rebuilt

| Existing | Reuse |
|---|---|
| `MiningService.mine(source, pos, normal, stats)` | Called verbatim; `sourceOrigin` already handles `Model`/`BasePart` |
| Per-source cooldown, `MiningService.forget()` | Free |
| `Events.Hit` → glow, sway, texture slip, **pop in / pop out** | Turret hits inherit the whole reaction with zero new code — the same win drones got |
| `Events.ChunkBroken` / `BlockBroken` | Income and `+$` popup |
| `Owner` ObjectValue → `RewardService.beneficiary` | Credits the turret's owner |
| Ownership-survives-the-body + top-up pass | Turrets last the session for the same reason drones do |
| `BuyDrone`-style purchase, price ladder, HUD reporting | Same shape, own Config block |
| `DroneFX` Beam construction | **Extract to a shared `LaserFX`** (§5) |
| `CollectionService` tagging | `DismantleTurret` |

---

## 5. Required New Systems

| File | Change |
|---|---|
| `ServerScriptService.Dismantle.TurretService` | Ring slots, orbit, inward raycast, radius/height tracking, mining |
| `ReplicatedStorage.Dismantle.Modules.LaserFX` | **Extracted from `DroneFX`** — beam + core + impact sparks + light, parameterised by colour/width |
| `ReplicatedStorage.Dismantle.Modules.DroneFX` | Refactored to call `LaserFX`; behaviour unchanged |
| `ReplicatedStorage.Dismantle.Modules.TurretFX` | Client visuals: yellow laser via `LaserFX`, slow body spin |
| `ReplicatedStorage.Dismantle.Remotes.BuyTurret` | Purchase |
| `Config` | `Turret` block |
| `KaijuServer` | `TurretService.init(grid, workspace.Dismantle)`; flush on rebuild |
| `DismantleClient` | Second buy button, bound to **`3`** |

**Why extract `LaserFX` now and not before.** One laser was not worth an abstraction. Two lasers
that differ only by colour and width is exactly the point at which copying it becomes the
expensive option — the ladder's "already in this codebase? reuse it" rung.

---

## 6. Gameplay Flow

```
buy ──► turret fades in on the ring at its slot angle
             │
             ▼
   ┌──── orbit at Turret.Speed, forever ────┐
   │                                        │
   │   ray inward toward the axis           │
   │        │                               │
   │        ├── hit  -> Firing = true, AimAt = surface, mine on cooldown,
   │        │          radius eases to keep Standoff from that surface
   │        │                               │
   │        └── miss -> Firing = false, count it                   │
   │                       │                                       │
   │              full revolution with no hits -> drop one layer ──┘
   └────────────────────────────────────────┘
```

---

## 7. Animation Flow

| Element | How |
|---|---|
| Orbit | Server `CFrame` each Heartbeat from angle; the whole motion |
| Facing | Always looks inward at the axis — a turret that is not aimed at what it is cutting looks broken |
| Body spin | Slow local Y spin on the visual, client-side, purely decorative |
| Bank | **None.** A turret is machinery on a rail, not an aircraft; leaning would make it read as a drone |

## 8. VFX Flow

| Beat | Effect |
|---|---|
| Deploy | Dust puff + 0.2s fade-in (existing `DebrisFX.dust`) |
| Laser hold | **Yellow** solid beam + white core, via `LaserFX` |
| Impact | Sparks + `PointLight` at `AimAt`, colour from `Materials.Turf.ParticleColor` |
| Chunk / Block breaks | **Nothing new** — `Events.Hit` and `BlockBroken` already cover it |
| Layer drop | Brief beam cut and a short descend; reads as the turret re-sighting |

## 9. SFX Flow

- Continuous yellow-laser hum, distinct pitch from the drone's so a swarm plus a ring is still
  legible by ear.
- Impact ticks reuse the existing positional hit audio — already source-agnostic.
- Orbit has no sound of its own; a constantly moving object that also hums constantly is noise.

---

## 10. Hit Detection

```
1  angle  := slotAngle + elapsed * Turret.Speed          (continuous, never resets)
2  centre := Vector3(Config.Origin.X, height, Config.Origin.Z)
3  pos    := centre + Vector3(cos(angle), 0, sin(angle)) * radius
4  ray    := pos ──► centre                              (horizontal, inward)
5  hit KaijuVoxel?
       yes -> AimAt = hit.Position; Firing = true
               mine(turret, hit.Position, hit.Normal, Config.Turret) on cooldown
               radius := lerp(radius, distance(centre, hit.Position) + Standoff, easing)
       no  -> Firing = false; misses += 1
6  misses over one full revolution == every sample -> height -= one Block layer, reset radius
```

`Reach` must cover `Standoff` plus slack. **Assert at load: `Turret.Reach > Standoff + VoxelSize`**
— the same assert the drone laser needed, for the same reason: without it every shot is silently
refused as `range`.

The ray filter excludes all turrets, all drones and all characters, exactly as the drone's does.

---

## 11. Client / Server Responsibilities

| Server | Client |
|---|---|
| Orbit angle, radius, height — the authoritative position | Beam, core, sparks, impact light |
| The inward raycast and `mine()` | Body spin |
| Publishes `Firing` (bool) and `AimAt` (Vector3), **on change only** | Laser hum |
| Ring slot assignment across all turrets in the world | — |

Identical split to drones, for the identical reason.

---

## 12. State Management

```
turrets[model] = {
    owner  = Player,
    base   = BasePart,
    slot   = n,          -- index into the GLOBAL ring, not per-player
    angle0 = radians,    -- slot's starting bearing
    radius = studs,      -- eases inward as the flank recedes
    layer  = n,          -- Block layer currently being cut
    firing = boolean,    -- mirrored to the attribute only on change
    aimAt  = Vector3?,
    sweepMisses = n,     -- consecutive misses; a full revolution of them drops a layer
    nextMine = clock,
}
```

**Slots are global, not per-player.** Turrets orbit the *kaiju*, which is shared — two players'
turrets at the same bearing would occupy the same air. Re-slotted whenever any turret is added or
removed, exactly as drone formation slots are.

---

## 13. Timing

| Beat | Value | Reasoning |
|---|---|---|
| `Turret.Speed` | 2π / 20 rad/s (**20s per revolution**) | ≈41 studs/s at r=130 — stately, and well inside what CFrame replication smooths |
| `Turret.Radius` (start) | 130 studs | clears the 108-stud footprint by 22 |
| `Turret.Standoff` | 20 studs off the flank | beam long enough to read, short enough to keep `Reach` sane |
| `Turret.Reach` | 30 | > Standoff + VoxelSize (26), asserted |
| `Turret.Cooldown` | 1.0s | slower than a drone's 0.8s; a turret is broad, not fast |
| `Turret.DamageLevel` | 3 | `Damage[3]` is Horizontal / Size 1 / Max 2 / Power 5 — a **horizontal** bite, which is exactly what a side-cutting beam should carve |
| Radius easing | ~2 studs/s | follows the flank without lurching |
| Layer drop | after one full revolution of misses | the honest "this band is clear" signal |
| `MaxPerPlayer` | 4 | 4 players x 4 = 16 on one ring is already dense |

### Pace

`Damage[3]` is Power 5, Max 2 → 2 chunks per shot, Turf hardness 3 → **2 chunks destroyed per
shot**. At 1.0s that is 2.0 chunks/s per turret — slightly faster than a drone's 1.25, which is
fair for a fixed emplacement that cannot reposition freely.

---

## 14. Economy

Same shape as drones, own ladder. A mountain is 11,345 Credits; the drone ladder is 2,500 (22%).
Proposed turret ladder **250 / 500 / 900 / 1400** = 3,050 (27%). Turrets cost more than the
equivalent drone because they cut faster and never need to travel. Both ladders together are 49%
of one mountain, which keeps a full loadout a two-mountain goal rather than a first-session one.

**Design numbers, not derived ones** — flagged, and one line to change.

---

## 15. Performance

| Concern | Budget | Mitigation |
|---|---|---|
| Update loop | **1** shared `Heartbeat` for all turrets | Same pattern as `DroneService` |
| Raycasts | 1 per turret per `Cooldown` = ~16/s at 16 turrets | Gated behind the cooldown, as the drone's is |
| Physics | **zero** | Anchored; no constraints, no ownership, no mass |
| Replication | one anchored CFrame per turret per frame | Roblox throttles and interpolates; orbit is slow |
| Attributes | 2 writes per chunk | On change only |
| Beams | 16 x (2 Beams + endpoint + emitter), **client-side** | Built once, reused; `LaserFX` shared with drones |

---

## 16. Edge Cases

| # | Case | Handling |
|---|---|---|
| 1 | Owner leaves | Destroy their turrets, re-slot the ring, `MiningService.forget` |
| 2 | Turret body destroyed | Ownership survives; top-up rebuilds it — same guarantee drones have |
| 3 | Mountain rebuilt | Reset every turret's radius and layer to start; clear `Firing` |
| 4 | Mountain fully cleared | Ray always misses, layer walks to 0, then turret idles with laser off |
| 5 | Layer drops below the base | Clamp at 0; idle rather than descending into the ground |
| 6 | Player standing in the beam path | Excluded from the ray filter — a teammate must never block a turret |
| 7 | Two turrets same bearing | Impossible — global ring slots |
| 8 | A drone flies through the beam | Excluded from the filter |
| 9 | Turret spawned before the grid is built | Deploy and orbit with the laser off; it starts cutting when there is something to hit |
| 10 | `Standoff` raised past `Reach` | Asserted at load |
| 11 | Radius would ease inside the mountain | Clamp to a minimum so a turret can never end up inside solid rock |
| 12 | Drill mode | `TurretServer` carries the `--[[DISMANTLE-GATE]]` line |

---

## 17. Implementation Steps

1. **Pick the model** (§18 A) and build the template into `Assets.Models`.
2. **Extract `LaserFX`** from `DroneFX`; prove drones still look identical before adding turrets.
3. **`Config.Turret`** block + the `Reach > Standoff + VoxelSize` assert.
4. **`TurretService` spawn/despawn** — anchored, `CanQuery = false`, ring slot, ownership.
5. **Orbit** — shared Heartbeat, angle from elapsed time, face inward. Test: ring is even, motion
   is steady, nothing stutters on a second client.
6. **Inward raycast + mine.** Test: it cuts the flank, and `Events.Hit` fires with a turret source
   so the pop reaction plays.
7. **Radius follow + layer drop.** Test: the beam length stays roughly constant as the flank
   recedes; a cleared band drops the turret a layer.
8. **Yellow laser via `LaserFX`** + impact FX.
9. **Purchase** — `BuyTurret`, key **`3`**, second HUD button, same failure reporting.
10. **Edge cases 1–12**, especially rebuild reset and ownership top-up.

---

## 18. Open Decisions

**A. Which model?** `Assets.Models.Turrets` is a copy of the Recon Drone Handle (§0).

| | Option | Trade-off |
|---|---|---|
| **A1 (recommended)** | Use the existing **`ufo`** Model — 22 parts, DiamondPlate + Neon, already has a SpotLight | Reads as a weapon platform; the SpotLight is a ready-made emitter; nothing new to source |
| A2 | Use `Turrets.Handle` as-is | A 0.2-stud glass disc at 130 studs' distance will be nearly invisible |
| A3 | You supply a turret rig | Best result, blocks the work until it lands |

**B. Working height.** Recommended: turrets track the **highest standing layer**, same as drones,
so the peak erodes from top and sides at once. Alternative: hold a fixed mid-height band and carve
a waist. Recommending the former; it matches "flatten".

**C. Prices** (§14) are chosen against the 11,345-Credit mountain, not tuned.

**D. `Damage[3]` (Horizontal, Max 2, Power 5)** for turrets, because a horizontal pattern is
literally what a side-cutting beam should remove. It is the first use of a non-`Single` pattern in
the project.

**E. Cap of 4 per player** — 16 turrets on one ring at 4 players.

---

## 19. Testing Checklist

- [ ] Ring slots even across ALL turrets, not per player
- [ ] Orbit is smooth on a second client (this is what decides option 2 vs 3 in §3.2)
- [ ] Beam is horizontal and lands on the flank, never on the top face
- [ ] Turret hits fire `Events.Hit` — glow, sway, texture slip and **pop in / pop out** all play
- [ ] Owner is credited for turret-completed Blocks
- [ ] Radius follows the flank inward; beam length stays roughly constant
- [ ] A cleared band drops the turret exactly one layer
- [ ] Layer clamps at 0; no turret descends into the ground
- [ ] Destroying a turret body rebuilds it; ownership never drops
- [ ] Rebuild resets radius/layer and clears every beam
- [ ] Turret never intercepts the player's aim ray
- [ ] 16 turrets + 20 drones: server frame time unchanged
- [ ] Drill mode: no turret code runs

## 20. Polish Checklist

- [ ] Orbit reads as machinery — constant, indifferent, no easing in or out
- [ ] Yellow is clearly distinct from the drones' green at distance
- [ ] Turret always visibly aims at what it is cutting
- [ ] Layer drop is a deliberate beat, not a teleport
- [ ] Ring of 4 lasers is not a wall of noise
- [ ] Repeated buy/leave/rejoin leaves zero orphaned Beams or emitters
