# Dismantle — Automation Progression Polish Plan

**Status:** IMPLEMENTED — steps 1–9 complete and measured. See §21 for results.
**Date:** 2026-09-16
**Reference:** Flatten The Mountain (Roblox 78724109436030)
**GDD:** §2.1, §2.2, §2.4, §3.1, §6, §7.1, §7.2, §9.3 Q2
**Supersedes the ladder in:** `Dismantle — Upgrade System Plan.md` §4

---

## 1. Feature Overview

Three connected pieces of work, planned together because changing any one alone leaves the
other two wrong:

| # | Part | Why it is in scope |
|---|---|---|
| **A** | **Retune the drone and turret ladders** so value-per-credit falls monotonically | The current curve has a trap level; research says this is the one measurable defect |
| **B** | **Make a level visible** — scaled visuals, a level-up cue, and a shop that states what a level buys | GDD §2.2 wants an *obvious visual* increase, not a number. Steps 8–9 of the Upgrade plan, never done |
| **C** | **Turret parity + beam duty cycle** | The drone now attacks a whole Block; the turret still attacks one voxel. FTM's single loudest player complaint is turret beam-on-air |

**Not in scope:** persistence of levels (GDD §2.4 [Unconfirmed]), new damage patterns, egg/enemy
interaction, the Tool track's own retune.

---

## 2. Reference Analysis — Flatten The Mountain

Only two fan wikis carry mechanics and **both label their own numbers as dated and unverified.**
Nothing official exists. Treated as weak evidence throughout; the *shape* is used, never the
numbers.

| Observation | Source confidence | What we take from it |
|---|---|---|
| Three skill tracks: Player / Drones / Turrets | Medium | Confirms our Tool / Drone / Turret split is idiomatic |
| Drone I ≈ $5, Turret I ≈ $23 | Low (dated 2 Sep 2026) | Direction only: first automation is CHEAP and bought within a minute |
| Buy order 1st drone (S) → 1st turret (A) → 2nd drone (S) → efficiency nodes → extra turrets (B) | Medium | Drone should out-rank turret; extra turrets explicitly diminishing |
| "First drone is the biggest jump besides mining speed" | Medium | **Conflicts with our new Lv1 drone at 15% of a player.** Flagged in §20, not silently reversed |
| "Efficiency nodes multiply drone speed" | Medium | Multiplicative, not additive, steps |
| Layer cuts are the fastest method | Medium | Our top-down rule already matches; no change |
| "If the beam is not hitting a voxel, you bought a flashlight" | Medium | Beam-on-air is what makes players rate turrets weak. Drives part C |

**No DPS, rate, cooldown or scaling number is published anywhere.** They cannot be copied.

---

## 3. Research Findings — idle/incremental math

The rigorous body of knowledge is idle-game design, not Roblox-specific.

```
cost_next        = cost_base * growth^owned          growth = 1.07 .. 1.15 in shipped games
production_total = production_base * owned * multipliers
```

- Costs grow **exponentially**, production grows **polynomially**, so affordability seesaws:
  many purchases early, lengthening waits later. This is the pacing engine.
- AdVenture Capitalist's first business: base cost 4, base production 1.67/s, growth 1.07.
- The satisfying-progression argument on the DevForum is **noticeable impact per upgrade**,
  not speed of acquisition. Reducing "6 hits to 4" is the cited example.
- Both DevForum economy threads end at "iterate and test" — no ready ratios. The testable
  invariant below is ours, derived from the AdVenture Capitalist shape.

### The invariant this plan enforces

> **Value-per-credit must fall monotonically across a track.**
> `(rate[n+1] - rate[n]) / price[n+1]` strictly decreasing.

If it ever rises, that level is a *trap* — a player who does the arithmetic skips it, and a
player who does not is punished for buying in order.

### Our current drone ladder fails it

| Buy | rate gain | price | gain per credit |
|---|---|---|---|
| →Lv2 | +0.17/s | 500 | 0.000340 |
| →Lv3 | +0.27/s | 1,200 | 0.000225 |
| →Lv4 | **+1.45/s** | 2,500 | **0.000580** |
| →Lv5 | +1.11/s | 5,000 | 0.000222 |

Lv4 is 2.6× better value than Lv3, because that is where the discrete `Damage[3]` jump lands.
Lv3 and Lv5 are traps.

---

## 4. Existing Systems That Can Be Reused

| Existing | Reused for |
|---|---|
| `Config.Upgrades` | Entire ladder retune is data-only. No code change for part A |
| `Config.Damage` 5 levels | chunks-per-hit comes from `Pattern`/`Max`/`Power` vs hardness. Untouched |
| `UpgradeService.statsFor / sync / cap / buy` | Already pure and version-gated. No change needed |
| `UpgradeService.publish` → `player:SetAttribute("<Track>Level")` | The replication channel for part B. Already exists |
| `LaserFX.update` reads `rig.spec` **every frame** | Level-scaled beam needs no new module — only a per-rig spec |
| `DroneFX` propeller rate already velocity-scaled | Add a level term to the same expression |
| `DebrisFX.dust` | The level-up puff |
| `DismantleUpgrades` label-matched options + `flashUntil` feedback | Extend the existing refresh, do not rewrite |
| `Config` load-time asserts | Extend with the monotonicity check (§16) |
| `MiningService.mine(source, pos, normal, stats)` | Untouched. Rates change only via `stats.Cooldown` |

**Nothing here needs a new service.** Part A is data. Parts B and C are additive.

---

## 5. Required New Systems

Deliberately small:

1. **`Config.RateOf(track, level)`** — one pure helper returning chunks/s from `Damage` +
   `Cooldown`. Used by the assert, the shop and every test, so all three agree by construction.
2. **`Config.Upgrades` monotonicity assert** — a load-time check that the invariant in §3 holds.
3. **Drone/Turret `Level` attribute** — the server publishes the owner's level on the *unit*, so
   a client can scale one unit's visuals without resolving Owner → Player → attribute, and so
   two players at different levels look different.
4. **Per-rig laser spec** — `DroneFX.SPEC` is currently a module-level table **shared by every
   drone's rig**. Mutating it for one drone would change all of them, including other players'.
   Each rig gets its own copy.
5. **`LevelUpFX`** — the purchase beat (flash + puff + sound). One small module shared by all
   three tracks, so the cue is identical wherever it fires.

---

## 6. Gameplay Flow

```
carve -> credits -> Shop -> BuyUpgrade("Drone")
                               |
            server: valid track? not max? affordable?
                               |
                level += 1, charge, version += 1, publish attributes
                               |
        +----------------------+------------------------+
        |                                               |
  every deployed drone picks up new stats          client sees DroneLevel change
  on its NEXT TICK (sync, no respawn)                    |
        |                                          LevelUpFX on each owned unit
  cooldown drops -> chunks pop faster              beam widens, propellers spin up
        |                                          shop row shows "Lv 3/5   0.91/s"
        +----------------------+------------------------+
                               |
                    player SEES and HEARS it speed up
```

The un-upgraded state is deliberately feeble (0.33 chunks/s, ~15% of a player) so the first
purchase is felt. Every step after is ~+65%.

---

## 7. Animation Flow

Drones and turrets have no skeletal animation; their "animation" is procedural and already
exists. Level scales it:

| Element | Lv1 | Lv5 | Mechanism |
|---|---|---|---|
| Propeller spin | `Hover 25 → Travel 45` rad/s by velocity | same band ×1.35 | Existing `DroneFX` expression, add a level term |
| Drone body lean | capped 15° by speed / `DR.Speed` | unchanged | Movement is not a level stat |
| Turret spin | `Spin 0.6` | ×1.35 | `TurretFX` |
| Level-up | — | one 0.25s scale punch on the unit | `LevelUpFX`, reuses the Block pop easing |

**Movement speed is explicitly NOT level-scaled.** It was just tuned to slow/smooth/steady;
letting a level undo that would re-open the complaint.

---

## 8. VFX Flow

| Event | Effect | Timing |
|---|---|---|
| Level bought | Flash + `DebrisFX.dust` puff on every unit the player owns | 0.0s, one frame, 0.25s decay |
| Beam, per level | `WidthNear/WidthFar/CoreWidth` × `1 + 0.09*(level-1)` → +36% at Lv5; `Sparks` 18 → 30 | continuous |
| Impact | existing pop + debris + dust per chunk, unchanged | on `ChunkBroken` |
| Beam colour | **unchanged per level** — colour is the unit-TYPE identity (green drone / yellow turret); tying it to level would make two players' drones read as different machines | — |

Width and spark density carry level, not hue. This is GDD §6's "larger and flashier" without
breaking the type read.

---

## 9. SFX Flow

GDD §3.1 asks for income/level-up cues and drone/turret carving sound. Currently **none exist**.

| Event | Sound | Asset status |
|---|---|---|
| Level bought | rising confirm | **No asset. Needs sourcing — do not invent an ID** |
| Beam active | low continuous hum, pitch × `1 + 0.05*(level-1)` | **No asset** |
| Chunk popped by a unit | quiet tick, volume by distance | 4 unused chainsaw sounds exist (`Charge`, `Crush`, `Crush2`, `Crush3`) — `Crush*` is a plausible fit |
| Income | coin | **No asset** |

**Audio is planned but gated on assets.** Implementation step 7 wires the hooks and leaves the
SoundIds blank rather than shipping placeholder IDs, so adding a sound later is a one-line edit
and never a code change. Silence is honest; a wrong sound is not.

---

## 10. Hit Detection / Interaction Logic

**Unchanged.** Every source still calls `MiningService.mine(source, hitPosition, hitNormal, stats)`
and every existing validation (cooldown, range, exposed-only) applies identically. The ladder
changes exactly two fields inside `stats`:

- `Cooldown` — how often a bite lands. **This is the rate knob.**
- `DamageLevel` — how many chunks a bite takes.

### The finding that makes this correct

`Damage[1]` (Power 1, Max 3) and `Damage[2]` (Power 3, Max 1) **both amortise to one chunk per
hit** against Turf hardness 3: three Power-1 hits kill all three cells at once. Lowering the
damage level changes whether chunks pop in bursts or singly — it does **not** change throughput.

Chunks per hit, as used by every rate in this document:

| DamageLevel | Pattern / Max / Power | chunks per hit |
|---|---|---|
| 1 | Single, Max 3, Power 1 | 1 (amortised, bursty) |
| 2 | Single, Power 3 | 1 |
| 3 | Horizontal, Max 2, Power 5 | 2 |
| 4 | Cross, Max 3, Power 10 | 3 |
| 5 | Cube, Power 10 | up to 27 |

---

## 11. Client / Server Responsibilities

| Concern | Side | Note |
|---|---|---|
| Level state, price, charge | **Server** | `UpgradeService` + `UpgradeServer`. Unchanged |
| Track-name validation | **Server** | Allowlist before any table index. Unchanged |
| `stats.Cooldown` / `DamageLevel` in effect | **Server** | Clients cannot affect mining rate |
| `<Track>Level` on the Player | Server writes, client reads | Existing attribute |
| **`Level` on each unit** | Server writes on change only | NEW. One write per purchase per unit, never per frame |
| Beam width, propeller rate, level-up flash | **Client** | Cosmetic. Server never reads it |
| Shop row text and affordability colour | **Client** | Hint only; the server still decides |

**Latency:** a purchase changes stats on the server's next tick regardless of client state. The
client's visual change arrives with the attribute replication. Worst case the beam widens a
fraction of a second after the chunks start popping faster — gameplay leads the cosmetic, which
is the correct order.

**Exploit surface:** unchanged. The one remote that carries an argument is `BuyUpgrade`, already
allowlisted and rate-limited at 0.25s.

---

## 12. State Management

Per unit record, additions only:

| Field | Owner | Lifetime |
|---|---|---|
| `rec.statsVersion` | server | exists; gates the sync copy |
| `rec.visualLevel` | server | NEW — last `Level` written to the attribute; prevents per-frame writes |
| `rig.spec` | client | NEW per-rig copy, replaces the shared `DroneFX.SPEC` |
| `rig.level` | client | NEW — last level rendered; gates the width recompute |

Invariant to protect, extending the existing claims invariant:

```
unit:GetAttribute("Level") == UpgradeService.level(owner, track)     for every live unit
```

Broken only if a unit is deployed between a purchase and the next tick; the top-up pass and
`sync` both run every tick, so the window is one frame.

---

## 13. Timing Specification

| Phase | Drone | Turret | Source |
|---|---|---|---|
| Target acquired | `ThinkInterval` 0.25s | `ProbeInterval` 0.1s | existing |
| Beam on → first chunk | `Attack.Windup` 0.25s | 0.25s (NEW, parity) | Config |
| Bite cadence | `Cooldown` 3.00s → 0.80s by level | 2.20s → 0.90s | §14 |
| Attack ends | whole Block gone | whole Block gone (NEW, parity) | part C |
| Rest between attacks | `Attack.Rest` 0.35s | 0.35s | existing |
| Beam fade | in 0.08s, out 0.12s | same | `Laser.FadeIn/FadeOut` |
| Level-up flash | 0.25s | 0.25s | `LevelUpFX` |
| Shop feedback flash | 1.6s then refresh | same | existing `flashUntil` |

Windup exists so a chunk never pops before the beam visually arrives. It is a **fixed** value,
never one cooldown — at Lv1's 3.0s a cooldown-long windup would be three dead seconds.

---

## 14. The ladders

### 14.1 Drone — satisfies the §3 invariant

| Lv | DamageLevel | Cooldown | chunks/hit | chunks/s | step | Price | cumulative |
|---|---|---|---|---|---|---|---|
| 1 | 2 | 3.00 | 1 | 0.333 | — | — | — |
| 2 | 2 | 1.80 | 1 | 0.556 | ×1.67 | 500 | 500 |
| 3 | 2 | 1.10 | 1 | 0.909 | ×1.64 | 1,100 | 1,600 |
| 4 | 3 | 1.30 | 2 | 1.538 | ×1.69 | 2,400 | 4,000 |
| 5 | 3 | 0.80 | 2 | 2.500 | ×1.63 | 5,300 | 9,300 |

Value per credit: 0.000446 → 0.000321 → 0.000262 → 0.000182. **Monotonic.**
Price ratio: 2.20, 2.18, 2.21. Lv1 → Lv5 is **7.5×**.

Lv4's cooldown *rises* (1.10 → 1.30) while its rate climbs, because `Damage[3]` takes two chunks
per hit. Leash and Cap keep their existing progression (120→200, 5→8).

### 14.2 Turret — same discipline, currently absent

Today the turret starts at `DamageLevel 3` / 1.00s = **2.0 chunks/s**, which is 6× the retuned
drone's Lv1. Left alone it makes the drone change invisible in practice.

| Lv | DamageLevel | Cooldown | chunks/hit | chunks/s | step | Reach | Cap | Price |
|---|---|---|---|---|---|---|---|---|
| 1 | 2 | 2.20 | 1 | 0.455 | — | 30 | 4 | — |
| 2 | 2 | 1.35 | 1 | 0.741 | ×1.63 | 34 | 4 | 700 |
| 3 | 3 | 1.65 | 2 | 1.212 | ×1.64 | 38 | 5 | 1,550 |
| 4 | 3 | 1.00 | 2 | 2.000 | ×1.65 | 42 | 6 | 3,400 |
| 5 | 4 | 0.90 | 3 | 3.333 | ×1.67 | 46 | 6 | 7,500 |

Turret Lv1 sits slightly above drone Lv1 (0.455 vs 0.333) because it costs 250 not 100 and is
pinned to an orbit — matching FTM's "drone S-tier, turret A-tier" ordering.
Reach stays above `Standoff 16 + VoxelSize 6` at every level, as the existing assert requires.

### 14.3 Economy check

- Mountain = 6,265 chunks / 508 Blocks = **11,345 Credits**. Player at Tool Lv1 = 2.22 chunks/s.
- First purchases land at ~45s (drone 100), ~90s, ~180s, ~315s — the early cadence idle games aim for.
- Full ladder spend: drones 9,300 + turrets 13,150 + units 5,550 + tool 6,400 = **~34,400**, about **3 mountains**.
- **Flag (GDD §2.4):** maxed automation is 8 drones × 2.5 + 6 turrets × 3.33 = **40 chunks/s**,
  ~18× a Lv1 player, clearing a mountain in ~157s. GDD §2.4 warns players will "simply wait".
  The named counterweight is eggs and enemies, which do not exist yet. **Lever if it bites:
  unit caps, not rates** — lowering caps preserves the curve shape.

---

## 15. Edge Cases

| # | Case | Handling |
|---|---|---|
| 1 | Level bought mid-attack | Applies on next tick. `Cooldown` shortens the *next* bite; the current attack is not interrupted |
| 2 | Cooldown shortened below the windup | Windup is fixed and independent; the first bite is still gated by it |
| 3 | Two players, different levels, adjacent drones | Per-unit `Level` attribute + per-rig spec means the beams visibly differ |
| 4 | `DroneFX.SPEC` shared table mutated | Eliminated by the per-rig copy. Would otherwise scale every drone on the server |
| 5 | Level raises Cap | Cap rises; the player still buys the extra unit. No free spawns |
| 6 | Cap lowered by a Config edit below units owned | Existing units keep working; no new ones until under cap |
| 7 | Already at max level | Refused and reported; shop shows MAX |
| 8 | Forged / unknown track string | Rejected before any table index. Unchanged |
| 9 | Remote spam | Existing 0.25s guard |
| 10 | Player leaves | `UpgradeService.forget`; units despawned. Session-only, unchanged |
| 11 | Kaiju rebuild mid-attack | `flushClaims` already clears lock, target and Firing on every unit |
| 12 | Unit body destroyed and re-deployed | Top-up pass re-deploys; `sync` on first tick gives it the current level, `Level` written before the client attaches |
| 13 | Buy succeeds but charge fails | Charge only after the level is committed, mirroring spawn-then-charge |
| 14 | Shop opened before `leaderstats` replicates | Existing `WaitForChild` with timeout; affordability colour is a hint only |
| 15 | Level-up fires while the unit is mid-travel | Flash is positional on the unit; no gameplay state touched |
| 16 | A trap level reintroduced by a future Config edit | **Caught at load by the new monotonicity assert** rather than in playtest |

---

## 16. Performance Considerations

| Concern | Budget | Mitigation |
|---|---|---|
| `Level` attribute writes | 1 per purchase per owned unit (max 8) | Gated on `rec.visualLevel` change; never per frame |
| Per-rig spec tables | 1 table per live unit (max 14 per player) | Allocated once at attach, not per frame |
| Beam width recompute | Only when `rig.level` changes | Gated; `LaserFX.update` per-frame cost unchanged |
| Level-up puff | 1 `DebrisFX.dust` per owned unit, on purchase only | Existing pooled emitter path |
| Ladder retune | **Zero runtime cost** — data only | — |
| Shop refresh | On attribute change + credits change, as today | Unchanged |
| Faster cooldowns at Lv5 | 8 drones at 0.80s + 6 turrets at 0.90s ≈ 17 mine calls/s | Inside the existing raycast budget (~25/s at the old rates) |

The one thing to watch is **chunk destruction rate at max level** (40 chunks/s), which drives
pop/debris/dust on every client. Existing `DebrisFX` pooling is the relevant limit — measure it,
do not assume.

---

## 17. Implementation Steps

Ordered so each step is verifiable alone and nothing later depends on an unproven earlier step.

1. **`Config.RateOf(track, level)`** — pure helper returning chunks/s from `Damage` + `Cooldown`.
2. **Drone ladder (§14.1)** — data only. Verify measured rate at Lv1 and Lv5 matches the table.
3. **Monotonicity assert** — extend the existing load-time asserts. Deliberately added *after*
   the new numbers so it is proven to pass on good data, not written to fit.
4. **Turret ladder (§14.2)** — data only. Same verification.
5. **Turret Block-attack parity (part C)** — port the drone's "attack = one Block" model and its
   keep-the-beam-lit-while-repositioning branch to `TurretService`.
6. **`Level` attribute + per-rig spec** — plumbing for part B. No visible change yet; verify two
   players at different levels get different attribute values.
7. **Level-scaled visuals + `LevelUpFX` + SFX hooks** (blank SoundIds, per §9).
8. **Shop row shows the effect** — `Lv 3/5` plus the rate the next level buys (§7.1).
9. **Edge cases 1–16**, then the full testing checklist.

Step 5 is the risky one and is deliberately isolated: it changes turret targeting semantics, and
must be measured before visuals are layered on top.

---

## 18. Testing Checklist

- [ ] Drone measured rate at Lv1 = 0.33 ± 0.05 chunks/s; at Lv5 = 2.50 ± 0.2
- [ ] Turret measured rate at Lv1 = 0.46 ± 0.05; at Lv5 = 3.33 ± 0.3
- [ ] Every step is a felt speed-up side by side (§9.3 Q2 is a *feel* question)
- [ ] Monotonicity assert fails loudly on a deliberately bad Config edit
- [ ] Two players at different levels mine at different rates **simultaneously**
- [ ] Two players' drones visibly differ in beam width at different levels
- [ ] A level bought mid-session changes deployed units without respawning them
- [ ] Cap increase permits one more purchase and grants nothing free
- [ ] Forged track string rejected; max level refused and reported
- [ ] **Turret beam duty cycle measured** — % of firing samples whose endpoint is a live voxel.
      Target ≥ the drone's 92%. This is the FTM "flashlight" test
- [ ] Turret holds one Block to completion; `AimAt` never leaves the claimed Block mid-attack
- [ ] Levels survive a kaiju rebuild; units re-acquire without a hung beam
- [ ] No attribute write storm: `Level` writes == purchases × units owned, not per frame
- [ ] 40 chunks/s at max automation does not drop client frame rate
- [ ] Levels gone after rejoin (expected until §2.4 carry-over is decided)

---

## 19. Polish Checklist

- [ ] Beam width change at level-up is visible but does not break the type read (green/yellow)
- [ ] Level-up flash fires on **every** owned unit, not just the nearest
- [ ] Propeller spin-up reads as the drone working harder, not as a different drone
- [ ] Movement stays slow, smooth and steady at **every** level — speed is not level-scaled
- [ ] Beam never lit while pointing at destroyed rock or empty air (the FTM failure)
- [ ] Shop states what the next level buys, not only its price
- [ ] Effects clean up: no orphan beams, dust emitters or `LaserEnd` parts after despawn
- [ ] Repeated buy / rebuild cycles accumulate no instances or connections

---

## 20. Open decisions — need a human

**A. Does the first drone stay feeble?** You asked for very low base damage; FTM's design makes
the first drone the single biggest jump in the game and prices it at ~$5. These are opposite
trades. This plan implements **your** direction (Lv1 = 0.33 chunks/s, ~15% of a player) and
flags the conflict rather than quietly reverting it.

**B. Turret retune (§14.2) — in or out?** You asked only for the drone. But the turret currently
starts 6× stronger than the retuned drone, which makes the drone change invisible in practice.
Recommend in.

**C. Five discrete levels, or many cheap nodes?** FTM sells lots of small efficiency nodes; we
sell four expensive steps. Many-cheap matches idle convention and gives a far better purchase
cadence, but it is a bigger change to the Shop UI. Not planned here — raise it if the cadence
still feels sparse after A and B.

**D. Max-automation ceiling (§14.3).** 40 chunks/s clears a mountain in ~157s. Acceptable now, or
lower the unit caps?

**E. Audio assets (§9).** Four sounds are needed and none exist. Source them, or ship the hooks
silent?

---

## 21. Implementation results (measured, 2026-09-16)

### Rates — predicted vs measured in a live playtest

| Unit | Level | Predicted | Measured | % of ceiling |
|---|---|---|---|---|
| Drone | 1 | 0.333/s | **0.351/s** | 105% |
| Drone | 5 | 2.500/s | **2.447/s** | 98% |
| Turret | 1 | 0.455/s | **0.338/s** | 74% |
| Turret | 5 | 3.333/s | **2.703/s** | 81% |

Measured climb: drone **7.0×** Lv1→Lv5, turret **8.0×**.

The turret's 74–81% is its orbit genuinely carrying Blocks out of reach — not beam-on-air.
`Config.RateOf` is documented as a ceiling so nobody later "fixes" the gap by inflating it.

### Part C — the turret duty cycle

| | before step 5 | after step 5 |
|---|---|---|
| Lv1 rate | 0.217/s (48% of ceiling) | **0.338/s (74%)** |
| Beam lit | — | 74% of samples |
| **Beam on LIVE rock** | — | **96% of firing** (drone: 99%) |

The FTM "flashlight" failure does not occur: when the beam is lit it is on real rock 96–99% of
the time. The Block-attack port was worth **+56% turret throughput** on its own.

### Verified

- Monotonicity check errors on Drone/Turret, warns on Tool — and caught two real bugs on its
  first run (below)
- `Level` attribute: published at spawn, updated on purchase, **0 writes** in 43s with no
  purchase — no write storm
- §12 invariant `unit.Level == owner's level` holds, including across a rebuild
- Beam scales: drone Width0 0.70 → 0.94 at Lv5 (×1.34), sparks 18 → 30
- Max level refused; forged tracks `"Weapons"`, `"__index"`, `""`, `42` all rejected
- Cap rises 5 → 8 at Lv5 and grants nothing free
- No hung beams after a rebuild (0 firing on the flush frame, 0 pointing at dead rock after)
- Zero orphan `LaserEnd` parts, Beams or ImpactLights after despawn

### NEW FINDING — the Tool track has two real bugs

Writing `RateOf` exposed them; they pre-date this work and are **not fixed**, because the Tool
track was explicitly out of scope and its fix is a design decision:

```
Config.Upgrades.Tool: level 2 is not faster than level 1 (2.222 -> 2.222 chunks/s)
Config.Upgrades.Tool: level 5 is not faster than level 4 (6.667 -> 2.222 chunks/s)
```

- **Lv2 costs 300 Credits and changes nothing.** `Damage[1]` (Power 1, Max 3) and `Damage[2]`
  (Power 3, Max 1) both amortise to one chunk per hit.
- **Lv5 costs 3,500 Credits and makes the player 3× WORSE.** `Damage[5]` is "Cube" with no
  `Max`, and under `HitMode = "Block"` a missing `Max` means ONE cell.

The shop now displays this to the player as `Cutter  Lv 1/5  2.22>2.22/s  $300`.

**The fix is a decision, not a patch.** The Tool track has no cooldown of its own — a swing is
paced by `Player.SwingTime` — so its five levels must come from five distinct `Damage` entries,
and Block mode does not provide five usable ones. Either give `Damage[2]` and `Damage[5]` real
`Max` values (which changes drone and turret output too, since the table is shared), or give the
Tool track its own per-level swing time.
