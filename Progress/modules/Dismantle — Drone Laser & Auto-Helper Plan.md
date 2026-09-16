# Dismantle — Drone Laser & Auto-Helper Plan

**Status:** plan only. Nothing implemented.
**Date:** 2026-09-15
**Supersedes:** §7, §8, §10, §13 and §17 step 2–3 of *Dismantle — Drone System Plan*. Targeting,
claims, reward attribution, purchase and lifecycle from that plan stand unchanged.

---

## 0. Test result — why the purchase failed

Run against the live playtest. **Root cause found, and it was not affordability.**

`Assets.Models` contained **two children named `Drone`**:

```
Models child: ufo    (Folder)
Models child: Drone  (Model)   <- the real rig: Base MeshPart + 6 Propellers on Motor6Ds + 6 Trails
Models child: Drone  (Part)    <- the legacy Recon-Drone-mesh template, now obsolete
```

`D.Assets.Models.Drone` dot-indexes to the **first** match — the Model — which has no `Owner`
child, so `spawn()` threw at `DroneService:292`. That throw escaped `BuyDrone.OnServerEvent`,
which aborts the handler: no drone, no charge, **and no reply**, so even the new failure
reporting never ran. A silent failure with a reported cause.

Already hardened: the template is resolved explicitly (prefer Model, fall back to BasePart) and
a missing one returns `"bad-template"` instead of erroring.

**Still to do — your call:** `Assets.Models` still holds both. The obsolete `Drone` **Part** (the
one I built from the Recon Drone mesh) should be removed, but I am not deleting it without your
say-so. Until it goes, the resolver picks the Model, which is the correct one.

---

## 1. Feature Overview

A purchased drone is an **auto-helper**: it deploys at the **summit of the mountain**, then works
autonomously, cutting with a **laser beam** rather than by proximity. The laser is both the visual
and the contract — if a beam is touching rock, that rock is taking damage.

---

## 2. Reference Analysis — Flatten The Mountain

FTM's drones read as: deploy high, hover *above* the work, and hold a continuous beam down onto
the surface. Three things carry the fantasy:

1. **The beam is persistent, not a pulse.** It stays on while the drone is working. Damage still
   ticks on a cooldown underneath, but the player reads a continuous cut.
2. **The drone hovers off and above, not next to.** The laser gives it reach, so the drone never
   has to nose up against the rock. This is the main behavioural difference from the plan I
   already built, where the drone flies to an 8-stud standoff on the *face*.
3. **The impact point is the loud part** — sparks and a glow at the surface, not at the emitter.

---

## 3. Research Findings

### 3.1 The rig you added (inspected live)

```
Drone (Model)
  Base (MeshPart, PrimaryPart)  3.34 x 1.07 x 2.98   mesh 972315091 / tex 972315530
  6 x Propeller (MeshPart)      each on a Motor6D:  Part0 = Propeller, Part1 = Base
  6 x Trail  (12 TrailAttachments)
  CameraAttachment on Base, local (0.017, -0.064, -0.553)   <- front-underside
```

Three consequences:

- **It is a Model, not a Part.** `AlignPosition`/`AlignOrientation` must be built on
  `PrimaryPart` (`Base`), every other part welded to it, and the whole assembly made massless
  and non-colliding. `SetNetworkOwner(nil)` is called on `Base`.
- **`CameraAttachment` is the laser emitter**, already positioned front-underside. No new
  attachment needed, and its name is the only thing tying it to a camera — nothing uses it.
- **The propellers are real parts on Motor6Ds.** The `MeshId`-swapping rotor code currently in
  `DroneFX` is for the *old* Recon Drone mesh and does nothing here — the rig has no
  `SpecialMesh`. Spin is a joint rotation instead (§7).

### 3.2 Laser: `Beam`, per the official docs

> "A **Beam** object connects two Attachments by drawing a texture between them… To display, a
> beam must be a descendant of the Workspace with its Attachment0 and Attachment1 properties set
> to Attachments also descending from the Workspace."

Also from the docs: beams are a **cubic Bézier** over four control points, and `CurveSize0` /
`CurveSize1` bend it. **For a laser both must be 0** — otherwise the beam bows, because P1/P2 are
offset along the attachments' X axes.

Properties that make a Beam read as a laser rather than a ribbon:

| Property | Value | Why |
|---|---|---|
| `CurveSize0` / `CurveSize1` | `0` | dead straight; the default curve reads as a rope |
| `FaceCamera` | `true` | a flat beam disappears edge-on as the drone banks |
| `LightEmission` | `1` | glows rather than being shaded |
| `LightInfluence` | `0` | unaffected by world lighting, so it stays hot at night |
| `Width0` / `Width1` | wide at emitter → narrow at impact | gives the beam direction |
| `TextureSpeed` + `TextureLength` | scrolling | energy flow; the difference between "laser" and "stick" |
| `Transparency` | `NumberSequence` soft at both ends | hides the hard endpoint caps |

**The alternative the community also uses** — a stretched Neon `Part` between two points — is
cheaper but does not face the camera, aliases badly at distance, and cannot scroll a texture. The
Beam is the documented answer and is what this plan uses.

### 3.3 Where the beam should live: client, not server

A Beam needs its endpoint attachment in the Workspace, and the endpoint *moves*. Creating it
server-side means an anchored endpoint part whose CFrame is rewritten every frame — per-frame
replication for something purely cosmetic, times 20 drones.

Instead: the server publishes **two attributes** on the drone —

```
drone:SetAttribute("Firing", true/false)
drone:SetAttribute("AimAt", Vector3)     -- surface point the laser lands on
```

Attributes replicate on change only, and `AimAt` changes when the *target chunk* changes (roughly
once per chunk destroyed), not per frame. Each client builds its own Beam and endpoint. Server
cost: two attribute writes per chunk. This is the same "server authoritative, client cosmetic"
split the whole project already uses for glow, sway, pop, debris and dust.

### 3.4 Propeller spin on a Motor6D

With no `Animator` driving the joints, the community approach is to write the joint directly each
frame. Two options:

- `motor.C0 = motor.C0 * CFrame.Angles(0, w * dt, 0)` — accumulates float drift over a long
  session and permanently corrupts the rig's rest pose.
- **`motor.Transform = CFrame.Angles(0, angle, 0)`** where `angle` is recomputed from elapsed
  time — the same "compute from elapsed time, never accumulate" rule already used for the Block
  pop and the hit sway. **This is the one to use.** `Transform` is the field animations write, it
  is composed on top of `C0`/`C1` rather than replacing them, and the rest pose is never touched.

Client-side, one loop for every propeller of every drone.

### 3.5 Summit spawn

`VoxelGrid:summitPosition()` already exists — it is what places the player's `SummitSpawn`. The
drone deploy reuses it directly, no new geometry maths.

---

## 4. Existing Systems Reused

Unchanged from the first plan and still the reason this is small: `MiningService.mine()`,
per-source cooldown, `MiningService.forget()`, `Events.ChunkBroken` / `BlockBroken`, the claim
registry, reward attribution via the `Owner` ObjectValue, `BlockHit`/`BlockBroken` client effects,
`CollectionService` tag `DismantleDrone`, and the whole purchase path.

Newly reused: `VoxelGrid:summitPosition()`, and the rig's own `CameraAttachment` and `Trail`s.

---

## 5. Required Changes

| File | Change |
|---|---|
| `DroneService` | Model-aware spawn (weld, `PrimaryPart` constraints, massless, `CanQuery=false` on **every** part); hover-above targeting; publish `Firing` / `AimAt` |
| `DroneFX` | **Replace** the MeshId rotor code with Motor6D spin; add Beam construction, impact sparks, impact light |
| `Config` | `Drone.Laser` block; `Standoff` → hover geometry; `DeployAt = "Summit"` |
| `KaijuServer` | Pass the summit to `DroneService` (it already computes it for `SummitSpawn`) |

No new remotes. No change to `MiningService`, `RewardService`, or the purchase flow.

---

## 6. Gameplay Flow

```
buy ──► drone fades in AT THE SUMMIT ──► flies to its work ──► HOVER above target
                                                                    │
                                        ┌───── laser ON ◄───────────┘
                                        │      (Firing = true, AimAt = surface point)
                                        │
                              damage ticks every Cooldown while the beam holds
                                        │
                          target Block done ──► laser OFF ──► retarget
                                                                │
                                          nothing in leash ──► orbit owner, laser OFF
```

---

## 7. Animation Flow

| Element | How | Note |
|---|---|---|
| Propellers | `Motor6D.Transform = CFrame.Angles(0, angle, 0)`, angle from elapsed time | Client. Replaces the dead MeshId code. Spin rate scales with speed so hovering ≠ sprinting |
| Trails | already on the rig; enable while `Travel`, disable when hovering | Free motion cue |
| Body lean | `AlignOrientation` goal tilts from actual velocity | Already built |
| Firing pose | nose pitches down toward `AimAt` while `Firing` | Sells "aiming" |

---

## 8. VFX Flow

| Beat | Effect |
|---|---|
| Deploy | Dust puff at the summit + 0.2s fade-in (already built) |
| Laser on | Beam fades in over ~0.08s — instant snap-on reads as a bug |
| Laser hold | Scrolling texture, slight width pulse |
| **Impact** | `ParticleEmitter` at `AimAt` + a small `PointLight`, colour from `Materials.Turf.ParticleColor` |
| Chunk breaks | **Nothing new** — `BlockHit`/`BlockBroken` already fire for drone sources |
| Laser off | Fade out over ~0.12s, particles stop emitting but live out their lifetime |

## 9. SFX Flow

- Looping laser hum on the drone, started/stopped with `Firing`, pitch-jittered per drone so five
  do not phase into one tone.
- Rotor hum (from the first plan), volume scaled by speed.
- Impact ticks reuse the existing positional hit audio — already source-agnostic, already working.

---

## 10. Hit Detection

Same raycast, **different geometry**. The drone no longer flies to the face; it hovers above and
beams down:

```
1..5  target Block selection, claims, blacklist      UNCHANGED from the first plan
6     aim chunk := standing chunk nearest the drone  UNCHANGED
7     hover goal := aimChunk + Vector3(0, Laser.Height, 0) + small orbit jitter
8     raycast  drone emitter ──► aim chunk centre
9     ray hits a KaijuVoxel?
          yes -> AimAt = hit.Position;  Firing = true;  mine() on cooldown
          no  -> Firing = false; failures += 1; blacklist at MaxFailures
```

`Config.Drone.Reach` must cover `Laser.Height` plus slack, or `MiningService` refuses every shot
for `range`. **Constraint to assert at build time: `Laser.Height + VoxelSize < Reach`.**

The raycast still sits behind the mining cooldown, so it stays ~25 rays/s, not per-frame.

---

## 11. Client / Server Responsibilities

| Server | Client |
|---|---|
| Drone existence, position goal, targeting, claims | Beam instance and its endpoint attachment |
| `mine()` — all validation | Propeller spin, trails, impact particles, light |
| Publishes `Firing` (bool) and `AimAt` (Vector3) | Reads those two attributes; draws accordingly |
| `SetNetworkOwner(nil)` on `Base` | Laser hum |

The client never tells the server where the beam landed. A client that forges `Firing` only lies
to itself.

---

## 12. State Management

Adds to the existing per-drone record:

```
firing   = boolean      -- mirrored to the attribute only on CHANGE, never per frame
aimAt    = Vector3?     -- ditto
```

Invariant: `Firing == true` implies a live claim and a successful ray within `Reach`. A drone that
loses its target must clear `Firing` **in the same frame**, or a beam hangs in the air pointing at
destroyed rock.

---

## 13. Timing

| Beat | Value | Reasoning |
|---|---|---|
| `Laser.Height` | 14 studs above the aim chunk | high enough to read as "beaming down", inside Reach |
| `Laser.FadeIn` / `FadeOut` | 0.08s / 0.12s | snap-on reads as a bug; slow fade reads as mush |
| `Laser.TextureSpeed` | 3 | visible flow without strobing |
| `Laser.WidthNear/Far` | 0.55 → 0.18 | taper gives direction |
| Damage tick | `Drone.Cooldown` = 0.8s (unchanged) | the beam is continuous, the damage is not |
| Impact particles | ~18/s while firing | enough to read, cheap at 20 drones |
| Propeller | ~25 rad/s hover, ~45 travel | scales with speed |
| Deploy → first work | summit fade-in 0.2s, then fly | |

**`Reach` must rise from 20 → 24** to satisfy §10's constraint (`14 + 6 = 20`, needs slack).

---

## 14. Economy

Unchanged. `PerChunk = 1`, `PerBlock = 10`, mountain = 11,345 Credits, ladder
`100/200/400/700/1100`. The laser changes how a drone looks, not what it earns.

---

## 15. Performance

| Concern | Budget | Mitigation |
|---|---|---|
| Beam instances | 20 drones x (1 Beam + 1 endpoint Part + 1 Attachment) = 60, **client-side** | Created once per drone, reused; never per shot |
| Attribute replication | 2 writes per chunk destroyed, not per frame | Only mirror on change |
| Propeller joints | 20 drones x 6 = 120 `Transform` writes/frame, client | Trivial; one loop |
| Impact particles | 20 emitters x ~18/s | `Rate` set to 0 rather than destroying the emitter |
| Raycasts | ~25/s | Already gated behind the mine cooldown |
| Server cost of the laser | **zero** | It is entirely client-side |

---

## 16. Edge Cases

Everything in the first plan's §16 still applies. New:

| # | Case | Handling |
|---|---|---|
| 16 | Target destroyed mid-beam | `Firing = false` the same frame the claim releases |
| 17 | Drone despawned while firing | Beam and endpoint destroyed with it; client listens on tag removal |
| 18 | Owner leaves mid-beam | as 17 |
| 19 | Client joins while a drone is already firing | Attributes replicate on join, so the beam builds correctly for late joiners |
| 20 | `AimAt` set but ray now blocked | `Firing` cleared; beam fades rather than cutting out |
| 21 | Mountain rebuilds mid-beam | `flushClaims()` already clears targets; must also clear `Firing` |
| 22 | Summit dug away before a drone deploys | `summitPosition()` is the peak of the *shape*, not what stands — drone deploys in mid-air and flies down. Acceptable; noted |
| 23 | Drone spawns before the grid is built | Deploy at the owner instead of the summit, then normal behaviour |
| 24 | `Laser.Height` raised past `Reach` | Assert at load; `mine()` would otherwise refuse everything as `range` |

---

## 17. Implementation Steps

1. **Remove the obsolete `Drone` Part** *(needs your OK)*, so only the Model remains.
2. **Model-aware spawn** — weld all parts to `Base`, constraints on `Base`, massless,
   `CanQuery = false` on every descendant, `SetNetworkOwner(nil)` on `Base`. Test: a drone
   deploys and hovers without being shoved or catching the aim ray.
3. **Summit deploy** — pass the summit through, fade in there. Test: buying puts a drone on the peak.
4. **Hover-above targeting** — replace face-standoff with `aimChunk + Height`. Test: drones sit
   above the rock, not against it.
5. **`Firing` / `AimAt` publishing** — on change only. Test: attribute writes per second is ~1, not 60.
6. **Beam on the client** — build, fade, texture scroll. Test: beam is straight (`CurveSize = 0`),
   faces the camera, endpoints land exactly on the surface.
7. **Impact FX** — particles + light at `AimAt`.
8. **Propeller spin via Motor6D** — and **delete the dead MeshId rotor code**.
9. **Trails + laser hum**, gated on state.
10. **Edge cases 16–24**, especially clearing `Firing` on rebuild and despawn.

---

## 18. Open Decisions

**A. Where does a drone work from?** Deploying at the summit is settled. After that:

| | Behaviour | Trade-off |
|---|---|---|
| **A1 (recommended)** | Deploy at summit, then leash to the **owner** and work Blocks near them | Matches FTM and the GDD's "around the player"; the swarm follows you down the hole |
| A2 | Stay near the summit and dig straight down | Simpler, but drones drift away from the player and stop feeling like *your* helpers |

**B. `Reach` 20 → 24** to fit the 14-stud hover. Mechanical, but it is a server validation bound,
so calling it out.

**C. Laser damage model.** The beam is continuous but damage ticks every 0.8s. The alternative —
continuous damage-per-second — would need `MiningService` to accept fractional damage, which it
does not. Recommending the tick, since it keeps drones on the exact code path players use.

**D. Deleting the obsolete `Drone` Part** (§0 / step 1).

---

## 19. Testing Checklist

- [ ] Buying deploys a drone at the summit, not at the player
- [ ] Beam is straight, faces camera, and lands exactly on the surface
- [ ] Beam appears on a second client, and on a client that joins mid-fire
- [ ] `Firing` attribute writes ≈ 1/chunk, not 60/s
- [ ] Beam clears the same frame a target dies — never left pointing at nothing
- [ ] Rebuild mid-beam: all beams clear, drones retarget
- [ ] 6 propellers spin on all 5 drones; rest pose uncorrupted after 10 minutes
- [ ] Drone never intercepts the player's aim ray (every descendant `CanQuery = false`)
- [ ] `Laser.Height + VoxelSize < Reach` — no shot refused for `range`
- [ ] 20 drones firing: server frame time unchanged (laser is client-only)

## 20. Polish Checklist

- [ ] Beam fades, never snaps
- [ ] Impact reads at the rock, not at the emitter
- [ ] Five lasers do not become one wall of noise
- [ ] Propeller rate visibly differs hovering vs travelling
- [ ] Drone pitches toward what it is cutting
- [ ] Repeated buy/leave/rejoin leaves zero orphaned Beams, endpoints or emitters
