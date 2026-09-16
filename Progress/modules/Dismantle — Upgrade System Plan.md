# Dismantle — Upgrade System Plan

**Status:** plan only. Nothing implemented.
**Date:** 2026-09-15
**GDD:** §2.1 "How it grows", §2.2 income and upgrades, §2.4 [Unconfirmed], §6 visual direction, §9.3 Q2.

---

## 1. Feature Overview

Credits buy **levels** in three tracks — Tool, Drone, Turret — that make every unit of that type
cut faster and reach further. This is the GDD's stated **main progression axis**, and the thing
that makes validation question §9.3 Q2 ("do level-ups clearly feel faster?") answerable at all.

Buying **more units** already exists and is unchanged. Levels are a second, orthogonal axis.

---

## 2. What the GDD actually asks for

| GDD | Requirement |
|---|---|
| §2.1 | Tool: "upgrade to stronger tools". Drone: "speed, number, range". Turret: "speed, range, number of placements" |
| §2.2 | "Drone and turret upgrades should create an **obvious visual increase in speed**" — not just numbers |
| §2.4 | "If automated dismantling becomes too strong, players will simply wait" — upgrades must not remove the reason to carve |
| §6 | "Higher levels may make them **larger and flashier**" |
| §7.1 | The HUD must show "drone/turret **levels** and operating status" |
| §7.2 | Levelling "should be accessible **without stopping the main work flow**" |

Note §2.1's "number" axis is **already served** by the existing purchase ladder. Levels therefore
cover **speed, range and damage**, and may also raise the cap.

---

## 3. Research — what exists to reuse

| Existing | Reuse |
|---|---|
| `Config.Damage` — **5 levels already defined** (Power, Pattern, Max) | The Tool track maps 1:1 onto these. No new damage model |
| `MiningService.mine(source, …, stats)` takes `stats.DamageLevel` per call | Per-player stats need no change to the mining core |
| `TurretService` `rec.stats` — a per-turret stats table already built at spawn | The pattern to copy for drones |
| Purchase flow: remote → validate → `spawn` → charge → reply, with every refusal reported | Copy wholesale for `BuyUpgrade` |
| `DismantleShop` — options matched by label, price/count from Config | Extend rather than replace |
| Replicated Player attributes (`Drones`, `Turrets`) drive the HUD with no remote round-trip | Same for `ToolLevel` / `DroneLevel` / `TurretLevel` |
| `DroneFX` propeller rate, `LaserFX` beam width | The "obvious visual increase" §2.2 demands |

### The one real refactor

`DroneService` passes the **shared** `Config.Drone` table straight into `mine()`. With per-player
levels that is wrong — two players with different levels would share one stats table.
`TurretService` already builds a per-record `rec.stats`; drones must do the same.

### Persistence: deliberately NOT in v1

`DataStoreHandler` keeps `Profiles` as a **file-local table** with no accessor, so nothing outside
it can read or write profile data. Exposing that is a change to inherited Drill code.

More importantly GDD §2.4 lists *"whether equipment or money carries over into the next play
session"* as **[Unconfirmed]** — so persisting levels would be inventing an answer to an open
design question. Levels are **session-only**, exactly like drones and turrets already are.
Revisit when the carry-over decision is made.

---

## 4. Proposed level tables — §2.4 marks these [Unconfirmed], so they need your call

Five levels per track, mirroring `Config.Damage`'s existing five.

### Tool (the player's chainsaw)

| Lv | Price | DamageLevel | Effect | Chunks/swing |
|---|---|---|---|---|
| 1 | — | 1 | Single, Power 1, Max 3 | start |
| 2 | 300 | 2 | Single, Power 3 | breaks a chunk per hit |
| 3 | 800 | 3 | Horizontal, Power 5, Max 2 | 2 chunks |
| 4 | 1,800 | 4 | Cross, Power 10, Max 3 | 3 chunks |
| 5 | 3,500 | 5 | Cube, Power 10 | 3×3×3 bite |

### Drone

| Lv | Price | DamageLevel | Cooldown | Leash | Cap |
|---|---|---|---|---|---|
| 1 | — | 2 | 0.80s | 120 | 5 |
| 2 | 500 | 2 | 0.65s | 140 | 5 |
| 3 | 1,200 | 3 | 0.55s | 160 | 6 |
| 4 | 2,500 | 3 | 0.45s | 180 | 7 |
| 5 | 5,000 | 4 | 0.40s | 200 | 8 |

### Turret

| Lv | Price | DamageLevel | Cooldown | Reach | Cap |
|---|---|---|---|---|---|
| 1 | — | 3 | 1.00s | 30 | 4 |
| 2 | 700 | 3 | 0.85s | 34 | 4 |
| 3 | 1,600 | 4 | 0.70s | 38 | 5 |
| 4 | 3,200 | 4 | 0.60s | 42 | 6 |
| 5 | 6,000 | 5 | 0.50s | 46 | 6 |

**Pacing check against §2.4** ("if automation is too strong, players will simply wait"):
at level 5 with a full swarm, automation is roughly 6× the player's own rate. That is a lot —
but the GDD explicitly wants automation to "contribute a large share". The counter-pressure it
names is eggs and enemies pulling players back in by hand, neither of which exists yet, so
**these numbers should be re-tuned once eggs land**.

Full ladder cost: Tool 6,400 + Drone 9,200 + Turret 11,500 = **27,100**, against ~11,345 per
mountain — so roughly 2.5 mountains to max everything, on top of unit purchases.

---

## 5. Architecture

| File | Role |
|---|---|
| `Config.Upgrades` | The three level tables above. One place to tune |
| `ServerScriptService.Dismantle.UpgradeService` (Module) | Per-player levels, `statsFor(track, level)`, purchase validation, attribute publishing |
| `ServerScriptService.Dismantle.UpgradeServer` (Script, gated) | `BuyUpgrade` remote + player lifecycle |
| `Remotes.BuyUpgrade` | Purchase request — **carries a track name** |
| `DroneService` / `TurretService` | Read per-owner stats instead of shared Config |
| `KaijuServer` | Player's mine uses their Tool level |
| `DroneFX` / `TurretFX` | Level-scaled visuals |
| `DismantleShop` | Upgrade rows in the existing Shop panel |

### `BuyUpgrade` is the first remote in this project that takes an argument

Every other remote carries nothing, which makes them trivially safe. This one takes a track
name, so it must be validated as **one of exactly three known strings** before use — never
indexed into a table directly, or a crafted value becomes a lookup into arbitrary Config.

---

## 6. Gameplay flow

```
carve -> credits -> Shop -> BuyUpgrade("Drone")
                               |
            server: valid track? not max? affordable?
                               |
                    level += 1, charge, publish attribute
                               |
          every EXISTING drone picks up the new stats on its next tick
          (no respawn, no interruption — §7.2 "without stopping the work flow")
```

---

## 7. Visuals (§2.2 / §6) — the part that is not numbers

| Level rises | Drone | Turret |
|---|---|---|
| Speed | Propeller spin rate up (already velocity-scaled — add a level term) | Orbit rate up |
| Presence | `ScaleTo` slightly larger per level | Slightly larger |
| Power | Laser wider + brighter core | Beam wider, hotter |
| Moment of purchase | Flash + level-up sound (GDD §3.1 "clearly mark progression milestones") | same |

---

## 8. Edge cases

| # | Case | Handling |
|---|---|---|
| 1 | Level bought while units are deployed | Applied on next tick from the owner's stats — never respawn a unit |
| 2 | Level raises the cap | Cap rises; the player still **buys** the extra unit. No free spawns |
| 3 | Cap lowered by a Config edit below units owned | Existing units keep working; no new ones until under cap |
| 4 | Already at max level | Refused and reported, like the unit cap |
| 5 | Forged / unknown track string | Rejected before any table lookup |
| 6 | Remote spam | Same 0.25s guard the buy remotes use |
| 7 | Player leaves | Levels dropped with them (session-only, §3) |
| 8 | Two players, different levels | Per-owner stats tables — the bug the drone refactor exists to prevent |
| 9 | Kaiju rebuild | Levels untouched; they are a player property, not a site property |
| 10 | Buy succeeds but charge fails | Charge only after the level is committed, mirroring spawn-then-charge |

---

## 9. Implementation steps

1. `Config.Upgrades` tables.
2. `UpgradeService` — levels, `statsFor`, attributes. No callers yet.
3. **Drone per-owner stats refactor** — prove drones still mine identically at level 1 before any level exists.
4. Turret per-owner stats (smaller — `rec.stats` already exists).
5. Player Tool level into `KaijuServer`'s mine call.
6. `BuyUpgrade` remote + `UpgradeServer`, with track validation.
7. Shop UI rows + level display (§7.1).
8. Level-scaled visuals (§2.2) and the level-up cue (§3.1).
9. Edge cases 1–10.

Step 3 is the risky one and lands first, deliberately: it changes how every existing drone gets
its stats, and must be verified as a no-op before levels are stacked on top.

---

## 10. Testing checklist

- [ ] Level 1 behaviour byte-identical to today (step 3 is a no-op)
- [ ] Two players at different levels mine at different rates **simultaneously**
- [ ] A level bought mid-session changes deployed units without respawning them
- [ ] Cap increase permits one more purchase, grants nothing free
- [ ] Forged track string rejected
- [ ] Max level refused and reported
- [ ] Visual speed increase is obvious side-by-side at Lv1 vs Lv5 (§2.2 is a *feel* requirement)
- [ ] HUD shows levels (§7.1)
- [ ] Levels survive a kaiju rebuild
- [ ] Levels gone after rejoin (expected until carry-over is decided)

---

## 11. Open decisions

**A. The level tables in §4** — GDD §2.4 explicitly marks level count, prices, speed and range as
[Unconfirmed]. Mine are a starting point, not a design.

**B. Does levelling raise the unit cap?** I have it doing so (Drone 5→8, Turret 4→6). The
alternative is that count and level stay fully separate. §2.1 lists "number" as a growth axis,
which is why I included it.

**C. Session-only levels** — recommended, per §3. Confirm you are happy that testers lose
progression on rejoin until §2.4's carry-over question is settled.

**D. Re-tune after eggs.** §2.4 warns automation can make players wait. The named counterweight
is eggs and enemies, which do not exist yet, so level-5 pacing cannot be judged honestly today.
