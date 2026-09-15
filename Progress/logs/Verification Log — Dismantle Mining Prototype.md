# Verification Log — Dismantle Mining Prototype

**Project:** Dismantle (Working Title) — Roblox
**Place:** `drill` working copy, placeId 71108578328239 (fork; live game untouched)
**Log date:** 2026-09-14
**Scope:** Phase 0 (isolate), Phase 1 (kaiju + cutter), chainsaw animation set, spec-driven `MiningService` refactor, hierarchical Block additions, doc-3 reward/completion additions.
**Status:** all items below verified in Studio playtests unless marked ⚠️.

Every claim in this log was observed in a running playtest via `eval_server_runtime` / `eval_client_runtime`, the server log buffer, or a real 2-client `StudioTestService` session. Where a check could not be made, it says so.

---

## 1. Environment & switches

| Item | Value |
|---|---|
| Game mode switch | `ReplicatedStorage.GameMode` ModuleScript, attribute `Mode` = `"Drill"` \| `"Dismantle"` (Properties panel, no code edit) |
| Gates | 20 lines tagged `--[[DISMANTLE-GATE]]` — 14 Drill-only entry points + 6 surgical gates inside `Joining.DataStoreHandler` |
| Avatar | **R6** (set in Game Settings → Avatar). Chainsaw animations are R6 and do not play on R15 |
| DataStore | Dismantle uses ProfileStore `"DismantleProto1"`; Drill keeps `"PublicStore1"`. Studio API access is **off**, so no writes occur in Studio |
| Debug | `Config.Debug = true` — server prints `[Mining] <player> hit <key> (block <bk>) -> removed n, damaged n (Material hp n left) | BLOCK COMPLETE xN` and refusals other than `cooldown` / `not-exposed` |
| Current `Mode` | `Dismantle` |

---

## 2. Module inventory

### Shared — `ReplicatedStorage.Dismantle`

| Instance | Type | Responsibility | Source doc |
|---|---|---|---|
| `Config` | ModuleScript | All tuning: `VoxelSize`, `Block`, `Player` stats, `Damage` table, `Reward`, `Kaiju` radii, `Origin`, `RebuildDelay`, `Debug` | Spec 1 §43, Doc 2 §7 |
| `Materials` | ModuleScript | Hide / Fat / Muscle / Bone by depth; `Hardness` = HP and progress weight; particle fields mirror the old `Ores` shape | GDD 6 |
| `Animations` | ModuleScript | Chainsaw ids (Idle / Equip / Slash×2) and `GripOffset` matching the R6 rig | anims.md |
| `MineRequest` | RemoteEvent | client → server `(hitPosition, hitNormal)` | Spec 1 §18 |
| `BlockBroken` | RemoteEvent | server → all clients `(position, amount)` for the `+$` popup | Doc 3 §19 |
| `Carved`, `Total` | IntValue | team progress in **material units** (Σ hardness) | Doc 2 §71 |
| `Chainsaw` | Tool | moved out of `StarterPack`; free-model scripts stripped; contains `CutterClient` | — |
| `Sounds/Break`, `Sounds/Hit` | Sound | copied from Drill / chainsaw handle; break and damage cues | — |

### Server — `ServerScriptService.Dismantle`

| Instance | Type | Responsibility |
|---|---|---|
| `VoxelGrid` | ModuleScript | Authoritative voxel data. Shape function (half-ellipsoid), shell-only Parts, `carved`/`hp` sets, `totalHP`/`removedHP`, per-Block alive counts, `hit()` / `carve()` / `reset()` |
| `MiningPattern` | ModuleScript | `(centre, normal, spec) → ordered coords`. Shapes: Single, Horizontal, Vertical, Cross, Area, Cube; face-oriented basis; nearest-first; optional `Max` truncation |
| `MiningService` | ModuleScript | **The one mining operation**: `mine(source, hitPos, hitNormal, stats)`. Validation (args, finite, cooldown, alive, tool, range, exposed), world→voxel, pattern, damage, material progress, `BlockBroken`, once-only completion |
| `KaijuServer` | Script (gated) | Builds the kaiju, adapts the player remote onto `MiningService`, chips/sounds, `+$` relay, cutter hand-out, Motor6D re-joint for animations, rebuild on completion |
| `RewardService` | Script (gated) | `Events.BlockBroken` → `leaderstats.Credits += Config.Reward.PerBlock` for Player sources |
| `Events/BlockBroken` | BindableEvent | server-side destruction event bus (payload `{BlockKey, Position, Source}`) |

### Client

| Instance | Type | Responsibility |
|---|---|---|
| `ReplicatedStorage.Dismantle.Chainsaw.CutterClient` | LocalScript | Camera-ray targeting every frame (Block outline via proxy Part + one `Highlight`), hold-to-mine pacing, animation tracks, saw sounds, stuck-button guard |
| `StarterPlayerScripts.DismantleClient` | LocalScript (gated) | Team progress bar (built in code), `+$` popup billboard |

### World — `Workspace.Dismantle`

`SiteSpawn` (SpawnLocation), `Ground`, `Kaiju` (voxel Parts), `Effects` (transient chips/sound hosts).

---

## 3. Change log (chronological)

| # | Session | Change | Verification summary |
|---|---|---|---|
| 1 | Phase 0 — isolate | `GameMode` switch; 14 blanket gates; 6 surgical gates in `DataStoreHandler` (incl. the `WaitForChild("Plot")` hard block and the un-pcall'd `Plot.Value.Miners:Destroy()` on leave); separate ProfileStore per mode; `SiteSpawn` | Both modes booted. Drill: plot assigned, spawn at plot, Credits 50. Dismantle: no plot, Credits 50, spawn at site, 0 plots claimed |
| 2 | Phase 1 — kaiju + cutter | `VoxelGrid` shell-only (5,111 solids / 1,047 Parts), `Carve` remote, cutter tool, HUD, chips + break sound | Reach reject, carve, neighbour spawn, rate limit (5 → 1), Hide→Fat→Muscle order, Muscle 2-hit, HUD live, Drill regression clean |
| 3 | Chainsaw animations | `Animations` config; `StarterPack.Chainsaw` → RS; Motor6D `Handle` re-joint (R6 `Right Arm` / R15 `RightHand`); `GripOffset` = 180° yaw + 1.08 studs; `CutterClient` Equip/Idle/Slash/sounds | On R15: tracks load with Length 0 (root cause: R6 keyframes). After R6: Equip 1.17 s, Idle 0.52 s, Motor6D driven, clean unequip/re-equip, carve still works |
| 4 | Spec 1 refactor | `MiningService`, `MiningPattern`, `MineRequest(pos, normal)`, HP moved into grid data, alive/tool validation, exposed-only rule | Spec §47 tests 1, 2, 3, 5, 10 + security + timing (see §4) |
| 5 | Validation pass | **Bug fixed:** completion lived in the player handler — a machine source reaching 100% never rebuilt. Moved into `MiningService` with once-guard + `rebuilt()`. **Bug fixed:** NaN hit position passed range check (`NaN > x` is false) → `finite()` guard. Added `Config.Debug` refusal log | 100% → rebuild at 12.2 s → second 100%; completion logged exactly twice for two cycles; 2 real clients, 3 voxels → `Carved` 3 |
| 6 | Doc 2 additions | Block outline (proxy + Highlight), material-based progress, per-hit feedback (`Hit` sound + chip), Hardness 3/2/5/8 | Material +1/+2/+3 per Hide; cube accounting 13 = 13; proxy at exact Block centre; real click → 13 s log stream of `hp 2 → hp 1 → removed` per voxel |
| 7 | Doc 3 additions | `Max` cap; per-Block alive tracking; `Events.BlockBroken`; `RewardService`; `+$` popup; §27 tool table in `Config.Damage` | Doc §33 A–E all exact; real player path: Credits 51 → 52, one popup at exact Block centre |

---

## 4. Verification matrix

Legend: ✅ observed · ⚠️ by inspection only / not reproducible in harness

### 4.1 VoxelGrid

| Check | Method | Expected | Observed | |
|---|---|---|---|---|
| Build counts | server eval | shape-exposed = Parts | 5,111 solids · 1,047 exposed · 1,047 Parts | ✅ |
| Builder misses nothing | brute-force recount vs Parts | every solid with an air neighbour has a Part unless carved | missing = 164 = `Carved` exactly | ✅ |
| Neighbour exposure on carve | client eval | voxel behind a carved face spawns | `0,0,-19` appeared after `0,0,-20` carved | ✅ |
| Underside sealed | build | `y<0` never counted as air | no floor Parts (1,047 total) | ✅ |
| Material bands | tunnel test | Hide → Fat → Muscle inward | order observed; Muscle first at `z=-10` | ✅ |
| Hardness / HP in data | service | Muscle: damaged then destroyed | HP 2 → 1 → removed (later 3-band Hide: 2 → 1 → removed) | ✅ |
| Material totals | build | Σ hardness | 15,850 for 14×8×20 mound | ✅ |
| Material accounting | service | +power on damage, +remaining on carve, no over-count | +1, +2, +3 per Hide; cube 13 vs computed 13; overkill counted 1 not 2 | ✅ |
| Per-Block alive → completion | service | fires once when last voxel goes | `BlockBroken` ×1 for Block `0,0,-10` (5 solids) | ✅ |
| `reset()` | completion test | totals and Parts restored | 51 / 0 / 37 restored, second cycle ran | ✅ |

### 4.2 MiningPattern

| Check | Observed | |
|---|---|---|
| Single | exact key | ✅ |
| Horizontal on front wall (−Z) runs along X | `1,0,-19 2,0,-19 3,0,-19` | ✅ |
| Horizontal on +X wall runs along Z | `13,1,-1 13,1,0 13,1,1` | ✅ |
| Vertical on +X wall runs along Y | `13,0,3 13,1,3 13,2,3` | ✅ |
| Horizontal on top face runs along X | `1,7,4 2,7,4 3,7,4` | ✅ |
| Cross on top face: X and Z arms | `-2,7,-4 -3,7,-3 -3,7,-4 -3,7,-5 -4,7,-4` | ✅ |
| Cross below-ground arm dropped | 4 cells at `y=0` | ✅ |
| Cube bites inward, nearest-first exposure | 16 removed (18 minus 2 already gone) | ✅ |
| Diagonal normal snaps | `(0.2,0.9,0.3)` → top face | ✅ |
| `Max = 2` | centre + one neighbour, exactly 2 | ✅ |

### 4.3 MiningService

| Check | Observed | |
|---|---|---|
| Position accuracy (nose, top, walls) | exact keys | ✅ |
| Interior position | `not-exposed` | ✅ |
| Out of range | `range` | ✅ |
| Cooldown | second immediate request refused | ✅ |
| Same face by two sources | second `not-exposed`; no double count | ✅ |
| NaN / inf position | `bad-args` (after fix) | ✅ |
| Garbage args from client | refused, no server error | ✅ |
| Unequipped player | `no-tool` — request refused | ✅ |
| Dead player | ⚠️ path present, not exercised | ⚠️ |
| Depth via real raycast re-aim | `6,0,-18 → -17 → -16` | ✅ |
| Completion from machine source | rebuild fired (after fix) | ✅ |
| Completion once per cycle | 2 log lines for 2 cycles | ✅ |
| Throughput | 30 mines → 30 removed, 0 wrong keys, 0.16 ms/mine (150-mine run: 0.09 ms) | ✅ |
| `BlockBroken` payload | `BlockKey 0,0,-10`, `Position (2,103,2042)` = centre, `Source` carried | ✅ |

### 4.4 Player path (real remote / real input)

| Check | Observed | |
|---|---|---|
| Equipped request mines | `Carved` +1, voxel gone | ✅ |
| Held click through the tool (virtual input) | 13 s stream: `hp 2 → hp 1 → removed` per voxel, aim advancing; stopped cleanly | ✅ |
| Block outline | proxy + Highlight under camera; enabled when cursor ray hit `0,0,-19`; proxy at `(2,103,2042)`; size 8×8×8; off on unequip | ✅ |
| Outline seen in screenshot | ⚠️ character stood between scripted camera and mound | ⚠️ |
| Reward on Block completion | Credits 51 → 52 | ✅ |
| `+$` popup | 1 popup, amount 1, at `(58,103,2122)` = Block `7,0,0` centre | ✅ |
| HUD | tracks material live; `CLEAR` at 100%; back to 0% after rebuild | ✅ |

### 4.5 Chainsaw

| Check | Observed | |
|---|---|---|
| Re-joint | `Right Arm` has only `Handle[Motor6D]`, `RightGrip` gone | ✅ |
| `GripOffset` | Handle relative to arm = `GripOffset` to 4 dp | ✅ |
| Tracks (R6) | Equip 1.17 s @Action2, Idle 0.52 s @Action, both Slash 1.17 s | ✅ |
| Motor6D driven by animation | Transform ≠ identity | ✅ |
| Unequip / re-equip | joint removed, 0 tracks; recreated | ✅ |
| Slash alternation visible | ⚠️ `Activated` cannot be raised programmatically; logic trivial | ⚠️ |
| Idle poses whole body | 32 keyframes incl. legs; at `Action` overrides walk — tune to `Movement` if it slides | note |

### 4.6 Multiplayer & regression

| Check | Observed | |
|---|---|---|
| 2 real clients, different voxels | 3 voxels → `Carved` 3, both HUDs agree | ✅ |
| 2 clients, same voxel same instant | ⚠️ second client's eval started late (voxel already gone → `bad-args`); covered by server back-to-back test + single-threaded remote handling | ⚠️ |
| Drill mode after every structural change | plot assigned, spawn at plot, Credits 50, no kaiju, no HUD, no chainsaw, `StarterPack` empty | ✅ (last run: after refactor; not re-run after change #7 — only a gated Script was added) |
| Server/client errors from Dismantle scripts | none across all runs (pre-existing Drill noise only: Studio API access, `timeban:16`, `DailyHandler:11`, `HeadLook:14`) | ✅ |

---

## 5. Known gaps / not verified

1. **Same-instant same-voxel race with two real clients** — not reproduced; guarded by `carved[k]` + sequential remote handling.
2. **Dead-player refusal** — code path exists, not exercised.
3. **Outline visually** — data exact; screenshot obstructed.
4. **Slash animation alternation** — cannot trigger `Tool.Activated` from evals.
5. **Save/load across rejoin** — Studio API access is off; `DismantleProto1` store is correct by construction, unwritten.
6. **Drone/turret sources** — `MiningService` accepts `BasePart`/`Model` sources (verified with a Part); reward for non-Player sources deliberately not implemented (`ponytail:` note in `RewardService`).

---

## 6. Harness pitfalls (for whoever tests next)

- **Teleport-then-fire from a client eval is refused for `range`** until the CFrame replicates (0.6–1.2 s+). Real players stream position; this only bites synthetic tests. Wait, or fire from the server with the player as source.
- **Lua multi-return truncation**: `f(g())` passes all of `g`'s returns only if `g()` is the *last* argument. A helper returning `(pos, normal)` in the middle of an argument list produced `bad-args` across a whole run.
- **`Carved` resets on every boot.** Baselines taken before a restart produced a phantom "150 ok vs +81" mismatch.
- **Virtual mouse "click"** releases before the next frame, so the stuck-button guard clears `holding`; use `mouseDown` or read the debug log — the click *did* mine, the HUD was sampled too early.
- **Second client evals start late**; a "same voxel" test must target a voxel that still exists when the second request fires.
- The scripted camera for screenshots ends up behind the character; move the character out of the line first.

---

## 7. Tuning snapshot (placeholders per GDD 9.3)

```
VoxelSize        4
Block            2 voxels/edge  (8×8×8 stud outline)
Player           DamageLevel 1 · Reach 14 · Cooldown 0.2 s
Damage           [1] Single P1 · [2] Single P3 · [3] Horizontal Max2 P5 · [4] Cross Max3 P10 · [5] Cube P10
Hardness         Hide 3 · Fat 2 · Muscle 5 · Bone 8
Reward           1 credit per completed Block
Kaiju            14 × 8 × 20 voxels → 5,111 solids · 15,850 material
RebuildDelay     12 s
Debug            true
```

Session length at these numbers: solo ≈ 15,850 material / (5 hits/s) ≈ 53 min at Power 1 — far too long; it is the knob to set alongside radii once feel is judged.

---

## 8. Live play verification — `digging.md` (hand-played, 2026-09-14 15:43:59 → 15:44:33)

Source: 48 `[Mining]` lines from the Output window during a real hand-held session (player `Shayankhankhan7`, Chainsaw, `DamageLevel 1`). Every line is `KaijuServer:116`, i.e. the debug print after a **successful** `MiningService.mine()`. No refusal lines other than the suppressed `cooldown` / `not-exposed` classes; no errors.

### 8.1 What the log proves

| Behaviour | Evidence in `digging.md` | Spec |
|---|---|---|
| Same location → same voxel keeps taking damage until it breaks | every voxel appears as `hp 2 left` → `hp 1 left` → `removed`, consecutive (e.g. lines 2–4, 5–7, 8–10) | Doc 2 §83, Doc 3 §10 |
| Damage persists in data while the aim is elsewhere | `-4,0,-19`: hp 2 at line 1 (15:43:59), hp 1 at line 16 (15:44:24), removed at line 21 — 26 s apart with 15 other hits in between. Same for `-3,0,-18` (lines 25 → 38 → 39) | Doc 2 §36 (data ≠ geometry) |
| Depth: digging continues into the cavity | `-4,1,-19 → -4,1,-18` (lines 4→5), `-5,1,-18 → -5,1,-17` (10→11), `-4,1,-17 → -4,1,-16` (17→18), `-3,1,-19 → -18 → -17 → -16` (28→37) | Doc 3 §13 |
| Hit position selects the cell, not random | all transitions are to face- or depth-adjacent keys; no jumps | Doc 3 §5, §12 |
| Pacing enforced | median gap between lines ≈ 0.21 s; minimum 0.199 s (Cooldown 0.2 s, client-paced, server-enforced). Long gaps (19 s at 1→2, 1.8 s at 11→12) are the player aiming, not the system | Spec 1 §44 |
| Block labelling | `-4,1,-19` → block `-2,0,-10`; `-4,1,-18` → `-2,0,-9`; `-4,1,-16` → `-2,0,-8`; `-5,1,-18` → `-3,0,-9` — all equal `floor(coord / 2)` | Doc 2 §18–19 |
| Material accounting | 48 hits at Power 1 = 48 material; 16 voxels removed × Hide hardness 3 = 48. The two numbers agree exactly | Doc 2 §71–73 |

### 8.2 Block completion, checked against the shape

Block **`-2,0,-10`** spans x∈{−4,−3}, y∈{0,1}, z∈{−20,−19}. By the half-ellipsoid, the z=−20 layer is air for x≠0, so the Block holds exactly **4** solids: `-4,0,-19`, `-3,0,-19`, `-4,1,-19` (r² = 0.9997 — barely inside), `-3,1,-19`.
Log removals for that Block: line 4 (`-4,1,-19`), 21 (`-4,0,-19`), 24 (`-3,0,-19`), **28 (`-3,1,-19`) → `BLOCK COMPLETE x1`**. Fired on the 4th and last solid, not before. ✅

Block **`-2,0,-9`** spans z∈{−18,−17}; all **8** cells are solid.
Log removals: lines 7, 17, 31, 34, 39, 42, 45, **48 → `BLOCK COMPLETE x1`**. Fired on the 8th. ✅

Block **`-3,0,-9`** (x∈{−6,−5}) lost `-5,1,-18` and `-5,1,-17` only → **no** completion logged. ✅ (no false positive)

No voxel key is removed twice. ✅

### 8.3 What the log cannot show

- Credits and the `+$` popup — not in the server print; verified separately in §4.4 (Credits 51 → 52, popup at exact Block centre).
- Outline placement during this session — client-side, not logged.
- Refusals: `cooldown` and `not-exposed` are intentionally suppressed, so the log is a record of successful hits only.

**Verdict:** the hand-played session matches the implemented model line for line — per-cell HP with persistence, spatial selection, depth carving, exact Block bookkeeping, and completion firing precisely on the last solid of each Block.

---

## 9. Reproduction procedure

1. `GameMode.Mode = "Dismantle"`, press Play (R6).
2. Server: `require(SSS.Dismantle.MiningService).mine(part, hitPos, normal, {DamageLevel=n, Reach=14, Cooldown=0})` with a transparent anchored `Part` as source placed 6 studs off the face; `hitPos = VoxelGrid.coordToWorld(x,y,z) + normal*2`.
3. Expect `result.Removed` / `Damaged` / `BlocksBroken` keys as in §4; `Carved.Value` moves by material.
4. Completion loop: set `Config.Kaiju = {3,2,3}` (51 solids), mine all Parts, wait `RebuildDelay`, observe `Total 51 / Carved 0 / Parts 37`; restore `{14,8,20}`.
5. Two clients: `multiplayer_playtest` with 2 players; fire `MineRequest` from each at different faces after ≥1 s settle.
6. Flip `Mode = "Drill"`, press Play: plot assigned, no kaiju Parts, no HUD, no Chainsaw. Flip back.
