# Dismantle — Locked-Voxel Laser: Analysis & Plan

**Status:** Phase 1 (analysis) + Phase 2 (plan). **No code changed.**
**Date:** 2026-09-16
**Brief:** `Progress/modules/Drone_Turret.md`

---

## Phase 1 — Analysis

### 1.1 The headline finding

> **Nothing in the system currently locks onto a voxel at all.**

The brief describes the current behaviour as "the Drone locks its laser onto a voxel… once that
voxel is destroyed the laser redirects". The real implementation never had a voxel lock. The unit
of targeting is a **Block** — a 4×2×2 group of 16 voxels — and the laser endpoint is a **raycast
hit that slides continuously**. So the "initial voxel-locking logic" the brief calls correct does
not exist yet and has to be built.

That matters because it changes the size of the job: this is not "delete the retarget line", it is
"introduce a lock that was never there, then end the attack on its death".

### 1.2 Relevant scripts

| Script | Role |
|---|---|
| `ServerScriptService.Dismantle.DroneService` | Drone targeting, movement, firing |
| `ServerScriptService.Dismantle.TurretService` | Turret orbit, targeting, firing |
| `ServerScriptService.Dismantle.MiningService` | **The** damage operation — shared by player, drone, turret |
| `ReplicatedStorage.Dismantle.Modules.LaserFX` | Draws the beam. Shared by both FX modules |
| `ReplicatedStorage.Dismantle.Modules.DroneFX` / `TurretFX` | Per-unit visuals; call `LaserFX` |
| `ServerScriptService.Dismantle.VoxelGrid` | Voxel data, `isExposed`, `blockVoxels`, `blockAlive` |

### 1.3 Current drone flow

```
findTarget()            claims a BLOCK (nearest unclaimed, highest layer, within owner leash)
      ↓                 called only when rec.target == nil, gated by rec.nextThink
aimFor(bk)              returns the CENTROID of that Block's standing chunks
      ↓                 called EVERY FRAME from updateDrone
hover goal              aimPos + (lateral offset, Laser.Height, offset)  → drone flies above it
      ↓
tryMine()               cooldown-gated; raycast drone → aimPos
      ↓
setFiring(true, hit.Position)      ← beam endpoint = the RAYCAST HIT
      ↓
MiningService.mine(drone, hit.Position, hit.Normal, rec.stats)
```

### 1.4 Where the laser origin and endpoint come from

- **Origin — already correct.** `LaserFX:53` sets `Beam.Attachment0 = emitter`, an Attachment on
  the drone itself. The beam start therefore follows the drone for free, with no per-frame code.
  Nothing needs to change here.
- **Endpoint — the problem.** `LaserFX:108` does `rig.endPart.Position = aimAt`, where `AimAt` is
  the attribute the server publishes, and the server publishes `hit.Position` — the raycast
  result. Because the ray direction is `drone → Block centroid`, moving the drone moves the ray,
  which moves the hit, which moves the endpoint. The beam slides along the surface instead of
  staying pinned to one voxel.

### 1.5 Exact sources of automatic retargeting — there are four, not one

| # | Location | What it does |
|---|---|---|
| **A** | `DroneService:245-259` (`aimFor`) | Recomputes the centroid whenever `grid.blockAlive[bk]` changes — i.e. **every time any chunk in the Block dies**. The aim silently moves to the centre of what is left. This is a redirect with no "find target" call anywhere near it, and it is the one most likely to be missed. |
| **B** | `DroneService:347-355` | When the Block empties, `releaseClaim` clears `rec.target`; the next think calls `findTarget` and a new Block is claimed. The Block-level retarget chain. |
| **C** | `DroneService:295-303` (`tryMine`) | A blocked ray increments `rec.failures`; at `MaxFailures` it releases the claim and blacklists the Block → retarget. |
| **D** | `TurretService:314-346` | Same as A+B, plus the turret **re-picks the nearest Block on any probe** where `rec.aimBlock` was cleared — and it is cleared whenever the Block dies *or* the orbit carries it out of reach. |

### 1.6 Shared code — can this break anything else?

The brief asks this explicitly. Checked:

- **`LaserFX` is shared** by drones and turrets, but contains **no targeting logic**. It reads
  `Firing` and `AimAt` and draws. Changing what the server puts in `AimAt` cannot break it — it
  will draw whatever endpoint it is handed. Safe.
- **`MiningService` is shared by the player too.** It must not change. The plan below does not
  touch it.
- **`Config.HitMode`** is global and affects all three sources. Not changed.
- No other weapon or ability uses either service. The chainsaw goes through `MiningService`
  directly and never touches drone/turret targeting.

### 1.7 A consequence worth a decision, not an assumption

`MiningService` in `HitMode = "Block"` damages the **`spec.Max` nearest standing chunks** to the
hit point, not strictly the one that was hit:

| Source | `DamageLevel` | `Max` | Chunks damaged per shot |
|---|---|---|---|
| Drone | 2 | none → 1 | **exactly the locked voxel** ✅ |
| Turret | 3 | **2** | the locked voxel **+ one neighbour** ⚠️ |

So "only damage the locked voxel" is already true for drones and will **not** be true for turrets
without a config change. That is a damage-pattern decision, not retargeting — see §3 Decision B.

---

## Phase 2 — Plan

### 2.1 The model

Three concepts, kept separate, exactly as the brief frames it:

```
ASSIGNMENT  = the claimed Block   (which area this unit owns — unchanged, prevents two units colliding)
TARGET      = the locked VOXEL    (new — fixed for the life of one attack)
ORIGIN      = the unit's position (already follows the unit via Attachment0)
```

An **attack** is the new unit of behaviour:

```
begin attack → lock voxel → beam on → damage that voxel → voxel dies → ATTACK ENDS → beam off
                                                                             ↓
                                                              (no automatic retarget)
                                                                             ↓
                                                        next attack begins on the next cycle
```

### 2.2 Minimal change

Add two fields per unit record and one gate. No new module, no duplicate targeting system.

| Field | Meaning |
|---|---|
| `rec.lockKey` | voxel key (`"x,y,z"`) locked for this attack, or `nil` between attacks |
| `rec.lockPos` | that voxel's world centre — **this becomes `AimAt`**, and it never moves |
| `rec.nextAttack` | clock gate; a new attack may only begin after this |

**Drone changes**

1. `aimFor` **stops returning a centroid**. When `rec.lockKey` is set it returns `rec.lockPos`
   unchanged — this alone removes retarget source **A**.
2. Locking: when no lock is held and `now >= rec.nextAttack`, choose one voxel from the claimed
   Block (highest first, nearest among equals — the existing rule) and store key + world centre.
3. `tryMine` rays `drone → rec.lockPos`. `setFiring(true, rec.lockPos)` — **the fixed voxel**, not
   `hit.Position`. Damage still goes through `MiningService` with the ray's hit/normal, so
   validation is unchanged.
4. Attack end — set `rec.lockKey = nil`, `setFiring(false)`, `rec.nextAttack = now + Attack.Rest`,
   on any of: voxel no longer `isExposed`; out of `FIRE_RANGE`; ray blocked; Block released.
   **Source B is now gated behind `nextAttack` instead of firing on the same tick.**
5. Hover goal moves from "above the centroid" to "above `lockPos`", so the drone positions itself
   over the voxel it is actually cutting.

**Turret changes** — identical, applied after the drone is verified, per the brief's §5. The
turret keeps orbiting; a lock additionally ends when the orbit carries the voxel out of reach,
which is the turret moving on rather than the laser redirecting.

### 2.3 What is deliberately NOT changed

- The **Block claim** stays. It is the work assignment that stops two drones on the same Block and
  drives top-down layer order. The brief does not ask for its removal, and removing it would
  reintroduce two units fighting over one area.
- `MiningService`, `LaserFX`, `Config.HitMode`, the player's swing — all untouched.
- Movement, orbit, upgrade stats, purchase flow — untouched.

---

## 3. Decisions needed before implementation

**A. When does the next attack begin?** The brief says a new target is selected only when "a new
attack/target-selection cycle explicitly begins" but does not define the cycle. Proposed:
`Config.Drone.Attack.Rest` / `Config.Turret.Attack.Rest`, **0.35s**, giving a visible beat —
cut, beam off, reposition, cut again. Set it to `0` and behaviour is effectively continuous
attacks with a one-frame gap; set it higher for a more deliberate rhythm.

**B. Turret splash.** `Damage[3]` has `Max = 2`, so a turret damages the locked voxel plus one
neighbour. Either accept it (the lock governs *aim*, not blast radius) or give turrets a
`Max = 1` damage level so "damages only the locked voxel" is literally true. I lean to accepting
it and documenting it — narrowing it weakens turrets by half.

**C. Does an attack end when the drone is still travelling?** A drone hovering into position is
out of `FIRE_RANGE` for a second or two. Proposed: **locking happens on arrival**, not on Block
claim — so travel does not consume and discard attacks.

---

## 4. Test plan (from the brief §8)

| Test | Expected |
|---|---|
| 1 — Normal attack | Drone locks voxel A, beam on, A takes damage |
| 2 — Drone movement | Move the drone; beam **origin** moves, **endpoint stays on A**, no switch to B |
| 3 — Target destruction | A destroyed → beam **off**, no immediate retarget |
| 4 — Multiple voxels | A destroyed with B and C adjacent and valid → **no** B targeting within the same attack |
| 5 — Turret | Repeat 1–4 |

Test 2 is the decisive one and is measurable: sample `AimAt` while the drone moves — it must be
**constant**, where today it slides.
