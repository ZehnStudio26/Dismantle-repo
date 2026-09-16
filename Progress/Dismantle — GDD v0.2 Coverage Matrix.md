# Dismantle — GDD v0.2 Coverage Matrix

**Date:** 2026-09-15
**Source:** `gdd/Dismantle_Working_Title_GDD_v0.2_English.pdf`, matched against the live `drill` place.
**Method:** every GDD section read in full; each claim below verified against the place, not assumed.

Legend: ✅ done · ⚠️ partial · ❌ not started

---

## 1. Core loop (GDD §1.1–1.3)

> "Carve → Earn → Upgrade equipment → Discover hazards / eggs → Clear at 100%"

| Loop stage | Status | Reality |
|---|---|---|
| Carve | ✅ | Voxel grid, chainsaw, Block/chunk destruction, pop + debris + dust |
| Earn | ✅ | `PerChunk = 1`, `PerBlock = 10`; a mountain is 11,345 Credits |
| **Upgrade equipment** | ⚠️ | You can **buy** drones and turrets. You cannot **level** anything — see §2 |
| Discover hazards / eggs | ❌ | No eggs, no gas, no enemies |
| Clear at 100% | ⚠️ | The kaiju rebuilds after 12s. There is no clear state, no celebration, no session end |

**Three of five loop stages are incomplete.** The loop currently runs Carve → Earn → Buy → (nothing) → Respawn.

---

## 2. Growth of dismantling methods (GDD §2)

> "**The main progression axis is leveling up drones and turrets.**"

| Method | Exists | "How it grows" (GDD's own column) | Status |
|---|---|---|---|
| Handheld tools | ✅ Chainsaw | Upgrade to stronger tools (plasma cutter) | ❌ `Player.DamageLevel` is hard-fixed at 1 |
| Drone | ✅ | Speed, **number**, range | ⚠️ number only (ladder 100/200/400/700/1100) |
| Turret | ✅ | Speed, range, **number** of placements | ⚠️ number only (ladder 250/500/900/1400) |

**The single largest gap in the whole project.** All three dismantling methods are built, and none of them can grow except by buying more units. `Config.Damage` already defines **5 levels** and `MiningService` already accepts `DamageLevel` per source — the data model is there, nothing spends money on it.

GDD §2.2 also asks that upgrades produce "an obvious **visual** increase in speed" — so this is not purely a numbers change.

**§2.3 [Unconfirmed] — needs a decision:** are drones/turrets individually owned or team-shared? I built them **individually owned** (each player buys their own; turrets share one global ring for spacing). The GDD flags this as directly affecting progress rate and income distribution. This should be ratified rather than inherited from my implementation.

---

## 3. Gas, masks, audio (GDD §3)

| Item | Status |
|---|---|
| Gas release from the kaiju | ❌ |
| Basic mask / advanced mask, visibility tiers | ❌ |
| Gas + enemies simultaneously (§3.2) | ❌ |

### Audio (§3.1) — ⚠️ partial

| Situation GDD asks for | Have |
|---|---|
| Carving by hand — blade entry, blocks crumbling, ASMR layering | ⚠️ `Hit`, `Break`, chainsaw `Idle`/`Equip`/`Swoosh` (+ unused `Charge`, `Crush`, `Crush2`, `Crush3`) |
| Drones / turrets carving — many small sounds, density rising with level | ❌ |
| Income / level-up — coin sounds, success cues | ❌ |
| Gas — deflating / bubbling / "pssh" | ❌ |
| Egg found / opened — crack, then positive or alarm | ❌ |
| Enemy — baby-kaiju cries, alien/UFO electronics | ❌ |

Four unused chainsaw sounds are already in the place — the carving layer is closer than it looks.

---

## 4. Eggs (GDD §4) — ❌ none

Required: eggs buried in the body, exposed by carving (by hand, drone **or** turret), openable, with four outcome categories — Money, Item, Baby kaiju, Alien — that are **visually indistinguishable**.

⚠️ **Blocked by an open design question.** The Block Break plan §12 flagged it and it is still unresolved: `HitMode = "Block"` means a hit damages the nearest chunks in the targeted Block rather than digging directionally. Eggs are *buried inside* and must be *exposed by carving into* the body. Egg placement and exposure depend on which digging model wins.

---

## 5. Enemies and weapons (GDD §5) — ❌ none

Required: Baby kaiju, Parasitic mini-kaiju, Alien, UFO. Weapons: standard gun, ray gun, bazooka. Plus §5.3 — the **starter cutter must still damage enemies**, so nobody is locked out of contributing.

Nothing exists: no enemy, no weapon, no health, no combat.

---

## 6. Kaiju and visual direction (GDD §6)

| Target | GDD direction | Status |
|---|---|---|
| Kaiju | Angular cubes, Minecraft-like, **visible steps** on contours and cut faces | ✅ exactly what the voxel heightmap produces |
| Kaiju **form** | An original kaiju — octopus / squid / hermit crab candidates | ⚠️ currently a generic **mountain**. `Shape = "Kaiju"` (half-ellipsoid) exists but is orphaned |
| Avatar | **Always BOX-type** Roblox-style, box torso/arms/legs | ❌ no `StarterCharacter` in the place; players use their own avatar |
| Drones / turrets | **Same cubic visual vocabulary** as the kaiju | ❌ drone is a smooth mesh quadcopter; turret is a 2×0.2×2 glass disc |
| Eggs | Rounded form from stacked cubes | ❌ |
| World | Bright, simple, "brainrot-style" | ⚠️ inherited Drill environment |

The destruction *reads* correct. The **cast** (avatar, drones, turrets) does not match the stated art direction.

---

## 7. Co-op and interface (GDD §7)

| Requirement | Status |
|---|---|
| Team shares one dismantling rate to 100% | ✅ by construction — one grid, one `Carved`/`Total` |
| No fixed classes, switch equipment by situation | ⚠️ only one piece of equipment exists |
| **Actually running with 2–4 players** | ❌ **never tested** |

### §7.1 — what the screen must communicate

| Must show | Status |
|---|---|
| Team-wide dismantling rate | ✅ progress bar |
| Money | ✅ `CreditsDisplay.Money` |
| Purchase access | ✅ Shop → Drone & Torrets |
| Ownership/switching of tools, masks, weapons | ❌ |
| Drone/turret **levels and operating status** | ⚠️ count only (`0/5`, `0/4`) |
| Notifications for gas, enemies, eggs | ❌ |

### §7.2 — a control constraint that affects architecture

> "The player must be able to use weapons **while a gas mask remains equipped**. If the three categories are treated as simple mutually exclusive equipment slots, combat during gas events will not work."

**This conflicts with the current model.** The chainsaw is a Roblox `Tool` in the Backpack, and Tools *are* mutually exclusive by nature. Masks cannot be a Tool. This needs settling **before** masks or weapons are built, not after.

---

## 8. GDD §8.2 in-scope feature list — the official scorecard

| # | Feature | Status |
|---|---|---|
| 1 | Co-op party up to 4, shared rate | ⚠️ built for it, never tested |
| 2 | Handheld dismantling + rate display | ✅ |
| 3 | Buying **and leveling** drones / turrets | ⚠️ buying only |
| 4 | Eggs (random rewards / enemies) | ❌ |
| 5 | Enemies + weapons | ❌ |
| 6 | Starter-tool enemy damage | ❌ |
| 7 | Gas + gas masks | ❌ |
| 8 | Audio direction | ⚠️ carving only |
| 9 | Clear at 100% | ⚠️ rebuilds, no clear state |

**Roughly 2.5 of 9 complete.** Everything finished so far sits in features 1–3 — the dismantling core. Features 4–7, which the GDD describes as the key differentiators from "flatten the mountain", have not been started.

---

## 9. Prototype validation (GDD §9.3) — what we can actually answer

| Question the prototype must answer | Answerable today? |
|---|---|
| 1. Does hand carving feel satisfying, kaiju visibly disappearing? | ✅ **yes** |
| 2. Do drone/turret **level-ups** clearly feel faster, without dead waiting? | ❌ no levels exist |
| 3. Does egg motivation survive several bad results? | ❌ no eggs |
| 4. Can a starter-cutter player still fight enemies? | ❌ no enemies |
| 5. Can multiple players carve together and return after events? | ❌ never run multiplayer |

**One of five.** This is the sharpest measure of where the project is.

---

## 10. Recommended order

1. **`UpgradeService`** — GDD's stated main progression axis, unblocks validation Q2, and cheapest to build: `Config.Damage` levels and per-source `DamageLevel` already exist. Include the "obvious visual increase in speed" §2.2 asks for.
2. **Multiplayer smoke test** — everything is written for N players and verified with 1. Cheap to run, and it de-risks Q5 before more systems are layered on.
3. **`EggService`** — Q3 and the replay motivator. **Settle the Block Break §12 digging question first.**
4. **`EnemyService` + weapons** — Q4, the largest build. **Settle the §7.2 equipment-slot question first.**
5. **`GasService`** — smallest event system; depends on the same equipment decision.

Cross-cutting, and cheap to do alongside: session-clear state at 100%, level-up and coin audio, persistence of owned units (`ProfileStore` already holds Credits), and the art-direction gap in §6 (box avatar, cubic drones/turrets).

---

## 11. Decisions blocking work — need a human

| # | Question | GDD ref | Blocks |
|---|---|---|---|
| A | Are drones/turrets individually owned or team-shared? | §2.3 [Unconfirmed] | income distribution, upgrade design |
| B | Directional digging vs Block-aimed hits | Block Break plan §12 | eggs |
| C | How do tool / mask / weapon slots coexist? | §7.2 | masks, weapons, all combat |
| D | Which kaiju form is first, and its scale/cube size? | §6.1 [Unconfirmed] | art direction, level design |
| E | Do turrets shoot enemies, or only carve? | §2.4, §5.4 | weapon value, turret scope |
| F | Drone/turret level count, prices, speed/range per level | §2.4 [Unconfirmed] | `UpgradeService` |
