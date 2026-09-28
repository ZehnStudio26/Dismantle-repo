# Dismantle — Cutting Polish Plan (Cells + Hit Feel)

**Date:** 2026-09-22 · **Status:** approved by Shayan in chat ("polish the cutting mechanics ... pops in and pops out"), implemented same day in kaiju.rbxl, all 8 acceptance tests passed 2026-09-23. Sources: `src/`.

**Two corrections found in testing.** (1) Decision C is reversed: the pop applies to the hit block's *surviving* cells, not the dying cell. At Lv1 one hit removes one cell, so a pop on the dying cell is never visible; the block flinching is what the eye reads (the Sep 14 plan's decision E was right). (2) Signals in this place are deferred, so a handler that reads `cell.Parent` after `CellHit` sees a destroyed cell. Demolition now passes the block explicitly, and EventRoll ignores hits after Cleared / Failed.
**Supersedes for the kaiju place:** the test-bed numbers in "Block Break & Debris Mechanic Plan" (2026-09-14). Its design reasoning and community research still stand and are reused here.

---

## 1. What the research says

| Source | Finding | Confidence |
|---|---|---|
| Repo spec "Flatten The Mountain — Digging" (from gameplay video) | One visible block is a **large logical block with internal cells**. Hits are **discrete**, land **where you aim**, remove **1–3 cells** per hit, and leave **cavities**. **+$ only on block completion.** A **white outline** marks the aimed logical block. | High (observed) |
| flatten-themountain.wiki | "Damage I ($1)" recorded a **three-voxel break**. Skill tracks: Damage, Mine Speed, Mine Distance (18 studs at I), Auto Mine. | Medium (dated snapshot) |
| Repo "Block Break & Debris" plan + DevForum / VoxelDestruct threads | Hit feel = **pop** (scale punch ~250 ms), pieces **fall rather than fly** (6–8 studs/s), **debris pooled and capped**, all FX **client-side**, squash tween drift avoided by tweening from an **absolute base size**. | Community practice |
| Public web (this pass) | No source-level info: no devlog, no Discord notes, no DevForum posts by DomBlox. Clip titles carry nothing. | — |

Conclusion: reproduce the **behaviour**, not an imagined implementation. Internal data structure of FTM is unknown; a 2×2×2 cell grid is the cheapest thing that produces the same picture, and the grid size stays configurable (spec §31).

## 1b. Deep research pass (2026-09-23): the hit, the break, the payout

What could still be learned about Flatten The Mountain after a second sweep (wiki pages incl. updates and calculator, Reddit, YouTube pages, DevForum, developer channels):

| Question | Answer | Evidence |
|---|---|---|
| What reacts when you hit? | **The whole targeted block punches** (squash in, overshoot out, settle). The block itself never moves; internal cells disappear where you aimed. | Shayan's observation; repo spec §2–§15 ("do not physically move the whole large block", cells vanish, cavities) |
| Hit cadence | Swings on a cooldown (about 0.2–0.25 s in the repo's estimate); click or hold, server enforces the cooldown. | Hierarchical doc §44 |
| How much comes off per hit | Damage I ≈ a three-voxel break; damage upgrades remove more or faster; damage and chunk count are separate stats. | wiki (dated Sep 1–2), Hierarchical doc §45–§46 |
| What the break looks like | Last cell goes → block disappears → **+$ popup** → outline jumps to the next block under the cursor. Reward on completion only, never per hit. | repo spec §19–§21, §32 |
| Who gets the cash | Drones and turrets earn Cash the same way the player does; the wiki tracks a per-player Cash balance. | flatten-themountain.wiki (Cash & Gems, Drones vs Turrets) |
| Debris, particles, sound, exact curve | **Not documented anywhere public.** No DomBlox devlog, Discord notes or DevForum posts exist; YouTube pages expose no text; the wiki's own Updates page says no patch details are known. | this pass |

Community technique for the punch (DevForum "object shake effect", "squash and stretch"): tween or step from a **saved base transform**, never compound offsets, restore the exact base at the end; TweenService with Back / Bounce easing for the overshoot.

**Decisions from this pass**
- **Pop the whole block**, about its pivot, on every hit: snapshot every chunk Part of the block (Size and CFrame), scale them together around the block centre, restore the snapshot exactly. Chunks revealed mid-pop are left alone (they are not in the snapshot), so there is no drift and no fight with the server. `Model:ScaleTo` was rejected because Parts added while the model is mid-scale get mis-scaled on reset.
- The pop fits inside the 0.15 s hit cadence (in 40 ms, out 60 ms, settle 50 ms) so a held laser reads as a shudder, not a smear.
- **Hit flash**: the aimed block's outline fills briefly on the local player's own hits.
- **Completion**: `+$N` billboard rises and fades at the block; the finishing actor is credited `CashPerBlock` on a provisional per-player `Cash` attribute (Q04 decides the real economy; drones credit their owner, as in the reference). HUD shows the balance.
- Cooldown stays the cutter's HitInterval; the laser is our pickaxe.

## 2. What we have vs. what we want

| | Today (kaiju.rbxl) | Target |
|---|---|---|
| Unit of damage | whole 40-stud block, one HP pool | logical block of **8 cells** (20 studs), each with HP |
| Where damage lands | anywhere, block fades | **the cell under the cursor**, cavity opens |
| Hit cadence | continuous DPS every frame | **discrete hits** every 0.15 s, same DPS |
| Cells per hit | — | 1 at Lv1, 2 at Lv2, 3 from Lv3 (the "three-voxel break") |
| Hit feedback | transparency fade | **pop in → pop out → settle**, dust puff |
| Cell removal feedback | — | 2 shards **fall** from the cavity, fade, recycled |
| Block completion | scaffold + percent + event roll | same, plus a bigger dust burst |
| Percent bar | per block | per **cell**, moves on every removal |
| Outline | aimed part | aimed **logical block** |

## 3. Design decisions (locked)

- **A. Cells are cubes, debris are shards.** Block stays a clean box (GDD §6 cubic direction). Shards are angular cubes with the block's colour. Real meshes later, one-line swap.
- **B. Pop direction = in then out** (shrink 0.90 → overshoot 1.05 → settle 1.00), per Shayan.
- **C. Pop applies to the hit cell**, not the whole block. With cells visible, the hit cell is what the eye tracks.
- **D. Cells per hit is a cutter level stat**, `CellsPerHitByLevel = {1, 2, 3, 3, 3}`. Extra cells are the **nearest live cells to the hit point** (spatially connected, spec §12).
- **E. Cell HP = block HP / 8**, so the time to clear a block is unchanged and the Balance estimate still holds.
- **F. Server owns everything that matters** (cells, HP, percent, events). **Clients own every visual** (pop, dust, shards). One remote, `BlockFX`, server → clients.
- **G. Subdivide lazily**: a block splits into cells on its first hit. Untouched blocks stay one Part, so part count only grows where people are working.
- **H. The whole-block rules survive untouched**: D7 / D9 in `CanDamage` (a cell resolves to its block), event roll on completion, scaffold on completion, drone peel-around, telemetry on `BlockBroken`.

## 4. Architecture

```
SERVER                                              CLIENT
Demolition   blocks, cells, HP, percent, events     BlockFX (StarterPlayerScripts)
  CellHit(cell, hitPos, frac)  ─┐                     pop tween on the cell (absolute base size)
  CellBroken(cf, size, color) ──┼─ Server.BlockFX ─►  dust puff at hit point
  BlockBroken(cf, size, ...)  ─┘   RemoteEvent        2 shards per broken cell, pooled (cap 60)
Cutter       discrete hits every HitInterval          bigger dust on block completion
Drone        discrete hits, hit point = drone body   LaserCutter.Client
                                                      raycast → (part, hitPos); outline = logical block
```

Cell resolution: cells are `Part` children of their block `Part`. The block Part goes invisible / non-collide / non-query when it splits, so raycasts hit cells. `Demolition` keeps `cellToBlock` and `blocks[part] = { cells, cellHP, unitsLeft }`. Percent = removed units / (blocks × 8).

## 5. Config surface

```lua
KaijuConfig.Cells = { Grid = 2 }                    -- 2x2x2; spec §31 keeps it configurable
ToolConfig.Cutter.HitInterval = 0.15                -- discrete hits; DPS unchanged
ToolConfig.Cutter.CellsPerHitByLevel = {1,2,3,3,3}
DroneConfig.HitInterval = 0.25
FXConfig.Pop    = { In = {0.90, 0.05}, Out = {1.05, 0.09}, Settle = {1.00, 0.11} }
FXConfig.Debris = { PerCell = 2, Scale = 0.35, Speed = 7, Spin = 8, Lifetime = 1.2, FadeAt = 0.7, MaxLive = 60 }
FXConfig.Dust   = { PerHit = 10, PerBlock = 40 }
```

## 6. Build order

1. `Demolition` cell model (subdivide, resolve, nearest cells, unit percent). Existing rules kept.
2. `Cutter` and `Drone` on discrete hits with a hit point. Client sends the hit position; outline moves to the logical block.
3. `Server.BlockFX` relay + client `BlockFX` (pop, dust, pooled shards, completion burst).
4. Tests (below). Balance line re-checked.

## 7. Acceptance tests

1. Hitting a fresh block splits it into 8 cells; the cell under the cursor takes the damage; a cavity appears where aimed.
2. A cell dies after `ceil(cellHP / hitDamage)` hits; pieces that fall == cells removed.
3. 50 hits on one cell: its Size returns to the exact base size (no drift).
4. Debris never exceeds `MaxLive`; instance count returns to baseline after `Lifetime`. Debris has `CanQuery = false`; the outline never flickers.
5. Last cell of a block → `BlockBroken` fires once, scaffold appears, event roll fires for Event blocks, percent hits the block's full share.
6. Gun on a cell: refused (D9). Drone on a cell of an Event block: refused (D7). Drone peels ordinary cells around an Event block and leaves it standing.
7. Breaking every block reaches exactly 100.00% and fires `Cleared`.
8. Balance line at run start is unchanged (same total HP, same DPS).

## 8. Risks

| Risk | Mitigation |
|---|---|
| Highlight on a transparent parent Part | Adornee is the block Part; Highlight renders its cell children, so the silhouette is the remaining block |
| Pop tween fights a server destroy mid-tween | Client guards `cell.Parent` every step; tweens are cancelled on destroy |
| Part count spike | Lazy split; a block only becomes 8 Parts while it is being cut; completion destroys parent and cells |
| Remote spam at 6.7 hits/s/player | One small event per hit; fine for 4 players. Restrict to nearby clients if it ever shows in the profiler |
| Egg exposure now needs cell-level digging | This is the desired behaviour (GDD 4.1): buried cells appear as neighbours are carved |

## 9. Deferred (not in this pass)

Real shard meshes, crack decals, hit SFX (no audio assets yet), hit-normal-directed patterns (spec §25/§29), Auto Mine node, greedy meshing.

## 10. Built and verified (2026-09-23)

Everything in §1b is in the place and mirrored under `src/`:

| Piece | Where | Verified in play mode |
|---|---|---|
| Whole-block pop from a snapshot, scaled about the block centre | `StarterPlayerScripts.BlockFX` (`popBlock`, `scaleAt`, `restore`) | Skin block: chunk scale ran 0.900 → 1.054 → 1.000 over 32 frames, one active pop, exact restore |
| Dust puff per hit, pooled shards capped per hit | same, `FXConfig.Dust / Debris` | 20 live shards, pool 40 of 60 after a 6-hit block |
| `+$N` popup on completion | same, `popup()` | 1 popup per broken block, mine in `MineColor` |
| Provisional Cash credited to the finishing actor (drone → owner) | `Demolition.Break`, `RunConfig.CashPerBlock` | player Cash 2 → 3 on the player's block; drone's blocks credited the owner too |
| HUD `$ N` line | `HUD.client` | reads the `Cash` attribute |
| Hit flash on the aimed outline | `LaserCutter.Client` (`FXConfig.Flash`) | logic in place; needs a real mouse aim to fire, so not covered by the harness |
| `CutState` debug attribute on the player | `Server.Cutter` | `NoTool / NoBlock / AimStale / Dead / OutOfReach / Refused / OK` |

Two bugs found on the way, both in `Demolition`:

1. **`WorldPivot` on an empty Model is discarded.** Cracked blocks got their pivot before any chunk Part existed, so `GetPivot()` on a cracked block was wrong and the cutter and drone lost the block after the first hit. The pivot is now set after the chunk Parts exist, and `Demolition.CenterOf(inst)` gives the grid centre for any block holder.
2. **`Workspace.Kaiju` had been moved 90 studs (+Z) since generation** while the 26,876 hidden Parts in `ServerStorage.KaijuHidden` stayed put, so the saved `Origin` attribute was stale and every computed block centre was 90 studs off (`CutState` read `OutOfReach` for 36 of 37 ticks). `Init` now derives the origin from an exposed Part and warns; hidden Parts snap to the grid when they are exposed. The hidden Parts and the attribute were also realigned in the edit place (undo waypoint "Realign hidden blocks to moved Kaiju").

Reminder: the place is still unsaved on disk. Save (Ctrl+S) before closing Studio.
