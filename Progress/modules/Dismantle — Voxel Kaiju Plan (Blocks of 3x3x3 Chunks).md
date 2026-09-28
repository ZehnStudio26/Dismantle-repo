# Dismantle — Voxel Kaiju Plan (Blocks of 3×3×3 Chunks)

**Date:** 2026-09-23 · **Status:** approved by Shayan in chat ("1 block should have inner chunks like 3x3 ... setup the model according to Block and voxel"), built and tested same day. Sources in `src/`.

**Correction after building.** The source model had been rescaled to **8-stud blocks** (body 280 × 56 × 264 studs) before the build, so the numbers in §1 (measured on the 40-stud model) are topology-only: the real chunk is **2.67 studs** and 11,226 chunks are exposed at start. The generator reads the block size from the source Parts. The old model is kept in `ServerStorage.Assets.Kaiju_Blocks_v1`. Open follow-ups: Q24 (tool ranges were tuned for the 40-stud body) and Q25 (scaffolds may be redundant now that chunk terraces are walkable).
**Supersedes:** the lazy 2×2×2 cell split in "Cutting Polish Plan". The hit feel (pop, dust, shards) is kept; the unit of material changes from a runtime cell to a modelled chunk.

## 1. What the research says

| Source | Finding |
|---|---|
| Repo "Flatten The Mountain — Digging" spec (video) | The visible target is a **large logical block**; the material inside is **cells** that go one hit at a time; the outline is on the block, cavities appear inside it. |
| Repo "Voxel Mining" spec §3, §9, §28 | Do not make every voxel a live Part. Keep an **internal voxel grid**, render only what can be seen, rebuild only the affected chunk. Options: individual Parts (prototype), grouped Parts, greedy meshing, destruction modules. |
| Repo "Hierarchical Block & Chunk" doc §5–8 | Block = data (Id, Material, InternalGrid, Chunks[], Destroyed) with a Part per visible chunk; grid size is config, "do not hardcode 8". |
| Pirate-place prototype (Work Log, 19 Sept) | 16,251 cells, only ~29% spawned as Parts via **lazy reveal**: breaking a block spawns its hidden neighbours. That is the proven pattern for this team. |
| DevForum (VoxDestruct, "Greedy Meshing Voxels", octree threads) | Community voxel games keep part counts down with **exposed-only rendering, greedy meshing and pooling**. Greedy meshing is the next step if exposed-only is still too heavy. |
| Public info on FTM's build | None. The mountain reads as a heightmap of player-scale voxels; nothing says how it is stored. We reproduce the look and the behaviour, not an imagined implementation. |

Measured on the current model (`Workspace.Kaiju`, 1,350 blocks of 40 studs):

| Grid per block | Chunks total | Visible at start | Chunk size |
|---|---|---|---|
| 2×2×2 | 10,800 | 7,444 (69%) | 20 studs |
| **3×3×3** | **36,450** | **18,464 (51%)** | **13.3 studs** |
| 4×4×4 | 86,400 | 34,458 (40%) | 10 studs |

No block is fully buried (the body is 7 layers deep with thin arms), so "exposed only" still means about half of all chunks.

## 2. Decisions

- **A. Block = Model, chunk = Part.** `Workspace.Kaiju.Block_NNNN` is a Model carrying the block attributes (BlockMaterial, Region, BlockId, Demolishable, GX/GY/GZ) and a WorldPivot at the block centre. Its children are the chunk Parts that exist right now, named `C_x_y_z`.
- **B. 3×3×3, configurable.** `KaijuConfig.Cells.Grid = 3`. Chunk = 13.33 studs. The generator and Demolition read the grid from config; nothing hardcodes 27.
- **C. Exposed-only rendering with lazy reveal.** A chunk is a Part only while at least one of its six neighbours is empty. Hidden chunks live in a server-side occupancy grid keyed by chunk coordinate. Removing a chunk reveals its hidden neighbours, across block boundaries too. Start: 18,464 Parts. The old model stays in `ServerStorage.Assets.Kaiju_Blocks_v1` so the voxel kaiju can be regenerated with a different grid.
- **D. Voxel look.** A deterministic per-chunk colour jitter (±6% around the block colour) makes the chunks read as individual voxels, the same trick FTM's coloured rocks and Minecraft noise use. No texture asset needed. A 3×3 grid texture can be added per face later if wanted.
- **E. Damage carries over, DPS stays exact.** One hit spends `DPS × HitInterval` damage on the exposed chunks nearest the hit point, killing them in order until the budget or the per-hit cap (`CellsPerHitByLevel`, 9 at Lv1 = one face) runs out. Chunk HP = block HP / 27. So the Balance estimate (total HP / DPS) still holds, and "chunks per hit" emerges from material toughness: a Skin block loses ~7 chunks per hit, Ridge ~5, Light a full face.
- **F. Only exposed chunks take damage.** You cannot hit what you cannot see; hidden chunks become targets when revealed.
- **G. Everything above the material layer is unchanged.** BlockBroken still fires with the block's CFrame and 40-stud size, so scaffolds, the event roll, telemetry and the drone's rules do not change. The FX relay sends one Hit per swing (block + hit point + removed chunk frames) and the client pops the block's surviving chunks and drops shards from the removed ones.

## 2b. Large Voxel Kaiju (same day, Shayan: "make the kaiju large, do not scale it")

More blocks of the same 8-stud size, not bigger blocks. The octopus was **resampled at 3× resolution**: the 1,350-block source volume is treated as a density field, sampled trilinearly on a 3× finer grid and thresholded at 0.5, so the silhouette rounds off instead of stair-stepping; material and colour come from the nearest source block. Result: **35,134 blocks**, body 840 × 168 × 792 studs, 21 layers, generated in 1.9 s.

That is ~950k chunks, so rendering exposed chunks everywhere is impossible. Rendering became **two-level, the way the reference reads**:

| State | Rendered as | Where |
|---|---|---|
| Intact, exposed | one 8-stud voxel Part with per-block tint | `Workspace.Kaiju` (8,258 at start) |
| Intact, hidden | a parked Part, never replicated | `ServerStorage.KaijuHidden` (26,876 at start) |
| Cracked (has been hit) | a Model of its exposed chunk Parts | `Workspace.Kaiju` |

A block cracks on its first hit. Removing a chunk reveals hidden neighbour chunks and un-parks hidden neighbour blocks (reparent, no recreation). `BlockAt` is an exact grid lookup from the Kaiju `Origin` attribute. Clients load 8,258 Parts at join instead of 11k–18k, and the body is 3× bigger.

**Balance consequence (Q26).** 35k blocks is 27× the material: the Balance line now reads 238.6 min of pure cutting against a 9.8 min budget. The per-hit feel is unchanged; the run-length target, area damage per hit, or the automation share has to change. That is a design decision, not a tuning knob.

## 3. Part budget and fallbacks

18,464 anchored Parts at start plus reveals as the body opens. That is 4× the pirate prototype and inside what Roblox renders comfortably on PC; mobile and join-replication are the risk. In order, if it is too heavy: enable StreamingEnabled (parts replicate by distance), then greedy-mesh intact block faces into slabs and split a block into chunks on its first hit (the data model does not change), then drop to 2×2×2 (7,444 Parts) as the last resort. Measure first (K-metrics + Studio memory) before doing any of them.

## 4. Build order

1. Generator (edit mode, undoable): back up the old model, build `Kaiju` of Block Models with exposed chunk Parts, attributes, pivot, colour jitter. Verify counts and bounding box.
2. `Demolition` rewrite: occupancy grid, exposed set, block registry from GX/GY/GZ, carry-over damage, lazy reveal, percent per chunk. Same public API.
3. Touch-ups: `Cutter` and `Drone` use block pivot and size; `Balance` and `EventBlocks` iterate Models; `LaserCutter.Client` outlines the block Model; client `BlockFX` pops any BasePart child and caps shards per hit.
4. Tests: chunk under the cursor dies first; hidden neighbours appear when it does; a corner hit on a Skin block removes ~7 chunks and leaves a cavity; block completes on its last chunk with one BlockBroken; D7 / D9 hold on chunks; full clear reaches 100.00%; Balance line unchanged; part count at start ≈ 18,464 + 1,350 Models.
5. Mirror everything into `src/`, then Shayan saves.
