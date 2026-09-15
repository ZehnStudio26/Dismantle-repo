# Dismantle — Block Break & Debris Mechanic

**Plan only. No implementation until the decisions in §5 are signed off.**

**Goal:** hitting a Block should feel like striking real rock — the Block *pops*, two to three inner mesh chunks *break loose and fall*, and the Block visibly erodes until it is gone.

**Reference:** Flatten The Mountain.
**Date:** 2026-09-14 · **Status:** proposal

---

# 1. What we can and cannot claim about Flatten The Mountain

Worth stating up front, because it shapes the whole plan.

**Publicly confirmed** (fan wiki, gameplay material):

- Players "break nearby blocks for Cash"
- A **"three-voxel break"** is associated with an early Damage upgrade
- Skill Tree tracks exist for *Player Damage* and *Mine Speed*
- Buried chests sit inside the mountain and require mining through interior blocks

**Not publicly documented anywhere:** block dimensions, debris piece count, mesh choice, tween curves, timings, particle setup, or any break-animation detail. The fan wiki explicitly separates verified facts from observation and says its mechanics documentation is incomplete.

So "exactly that" can only mean **reproduce the observable behaviour**, not copy an implementation. That is the same rule our own two specs already set — Spec 1 §48 ("do not tell the developer FTM definitely uses X") and Doc 3 §31 ("the video proves the behavior, not the exact internal implementation").

The one hard number we have — **three voxels per break after a Damage upgrade** — corroborates the user's "around 3 to 2 falls from it". That is the anchor this plan builds on.

---

# 2. What exists today

```
Workspace.Dismantle.Kaiju
└── Block_0,0,0            Model, attribute BlockKey
    ├── Rock               Part 4×4×4, Enum.Material.Rock, 6 Texture faces
    └── … 16 chunks total (Block.Size = 4×2×2), 96 Textures
```

| | Current |
|---|---|
| Logical chunk | 4-stud Part, HP = material Hardness (Rock = 3) |
| Hit targeting | camera ray → Block; Block glows; glow ⇔ hit lands |
| Damage | `HitMode = "Block"` → nearest standing chunk takes `Power`, `Max` chunks (default **1**) |
| On hit | white Highlight flash · whole-Block sway · texture offset slip |
| On chunk destroyed | vanishes; 3 cube shards flung outward at 17 studs/s, fade 0.8 s |
| On Block emptied | `BlockBroken` → `+$1` popup → rebuild after 12 s |

**What's wrong with it, measured against the ask:**

1. Debris are **plain cubes**, not mesh chunks
2. They are **flung outward** (17 studs/s) — reads as an explosion, not as pieces *falling off*
3. Only **1 chunk** breaks per hit, so nothing like "2 to 3 fall from it"
4. There is **no pop** — the Block sways and glows but never scale-punches
5. Debris spawn is uncapped and uncached — fine for 16 chunks, wrong at kaiju scale

---

# 3. How the Roblox community solves this

| Technique | Source | Take for us |
|---|---|---|
| **Part caching / object pooling** — pre-create parts, reuse instead of `Instance.new`, kills the clone spike | VoxelDestruct 2.1 | Adopt at Phase 4. It is *the* answer to debris cost |
| **Client offloading** — run destruction visuals on clients, not the server | VoxelDestruct 2.1 | Already our pattern: shake, glow, debris are all client-side |
| **Debris count cap** (`debrisCount`) | VoxelDestruct 2.1 | Adopt. Hard ceiling on live pieces, oldest recycled first |
| **Greedy meshing** to cut part count | VoxelDestruct, VoxDestruct, VoxBreaker | *Not yet.* Our shell-only grid already avoids interior parts; revisit only if profiling demands |
| **Grid-split fracturing into 8 wedges**, shards inherit material/colour, velocity preserved | Part Fracturing System V3 | Good model for *how a piece inherits its parent's look*. We don't need runtime fracture — pre-made meshes are cheaper |
| **Tween to transparent / sink into ground** rather than vanishing | TweenService & Debris wrapper thread | Adopt for debris despawn |
| **Dust/smoke particles when parts unanchor** — adds scale, hides simple geometry | DevForum destruction threads | Adopt. Cheap, and it disguises low-poly debris |
| **Break indication**: crack progression, colour darkening, progress bar | "Block breaking indication?" | We already darken on damage. Crack decals are a Phase 5 option |
| **Squash/punch via TweenService**, ~0.1 s, Sine/Back easing; the recurring bug is **drift** — objects not returning to exact base size | "TweenService/stretch punch" | Adopt the curve, and design drift out (see §4.2) |

**Ladder note:** VoxBreaker / VoxelDestruct / VoxDestruct are full runtime-voxelisation engines. We do not need one — we already own an authoritative voxel grid. Pulling in a destruction module would duplicate it. We take their *performance techniques*, not their engines.

---

# 4. The proposed mechanic

## 4.1 Layer separation (unchanged principle)

```
LOGICAL  (server, authoritative)        VISUAL  (client, disposable)
VoxelGrid: chunk HP, block counts  →    chunk render · pop · debris · dust
```

The server keeps deciding *what* breaks. Everything in this plan is *presentation*, driven off events the server already sends. No new authority, no new trust.

## 4.2 One hit, four beats

Timeline for a single swing. Numbers are starting values, all in Config.

```
t=0ms     IMPACT       glow flash on (peak), hit SFX, dust puff at contact point
t=0ms     POP IN       Block scales 1.00 → 0.94        50ms   Quad Out
t=50ms    POP OUT      Block scales 0.94 → 1.05        90ms   Back Out   ← overshoot
t=140ms   SETTLE       Block scales 1.05 → 1.00       110ms   Quad Out
t=0ms     SWAY         whole-Block offset, decaying   300ms   (existing)
t=0ms     SLIP         texture offset jolt + settle   300ms   (existing)
t=40ms    SHED         2–3 chunks detach and fall      —      ← the new core
t=200ms   GLOW OFF     flash faded                     —
```

Total read: **~250 ms of punch**, debris living ~1.2 s after. The pop finishes well before the next swing at `Cooldown = 0.2 s`, so rapid hits chain without stacking.

**Pop implementation — and the drift trap.** Use the native `Model:ScaleTo()` on the Block Model. It tracks an *absolute* scale factor, so `ScaleTo(1.05)` → `ScaleTo(1.0)` returns to exact base with no accumulation — which is precisely the drift bug the DevForum punch thread works around manually. Two requirements:

- Set the Model's **`WorldPivot` explicitly to the Block centre at creation**. `GetPivot()` defaults to the bounding-box centre, which *moves as chunks are destroyed* — so an eroded Block would scale about the wrong point and appear to slide.
- Re-hit during a pop must **restart the timeline, not re-read the base**, same rule the sway already follows.

## 4.3 The shed — the piece that's actually new

On each hit, `Max` chunks break (see §5, decision D). Each broken chunk:

1. **Stops being a grid chunk** — server destroys the Part as it does today
2. **Becomes a falling mesh piece** on every client — a rock mesh at the chunk's exact CFrame, inheriting its colour and material
3. **Detaches rather than explodes** — small outward nudge (**6–8 studs/s**, down from today's 17), plus tumble; gravity does the rest
4. **Lands, rests briefly, fades** — tween to transparent over the tail of its lifetime, then recycled
5. **Puffs dust** at the detach point — one short-lived emitter, hides the low-poly silhouette

The difference from today is entirely in step 3. At 17 studs/s pieces rocket outward and read as an explosion. At 6–8 they *fall off the face of the block*, which is what "falls from it" describes and what the reference footage shows.

**Piece count per hit = chunks broken per hit.** One mesh per chunk, not three shards per chunk. So `Max = 3` gives exactly "3 to 2 falls from it", and it stays honest: what you see falling is what was actually removed. Optional 1–2 tiny chips can ride along for grit without implying extra removal.

## 4.4 Block completion

When the last chunk goes, the Block currently just empties. Proposed: a **final collapse** — the remaining shed is joined by a stronger dust burst, a lower-pitched break SFX, and the existing `+$` popup. Distinct beat from a normal hit, so completion reads as an event.

---

# 5. Decisions needed before any code

These change the build materially. My recommendation on each, but they are yours.

### A — What is a chunk *made of*?

| Option | Look | Cost | Notes |
|---|---|---|---|
| **A1. Cube chunks, mesh debris** (recommended) | Block stays a clean textured box; what falls out is rock meshes | Low — no change to the grid's render | Matches "inside the box there are chunks of meshes": the box is a box, the meshes come out of it |
| A2. Mesh chunks packed in a grid | Block surface is knobbly rock, chunks visibly individual | Medium — 16 MeshParts per Block | Contradicts GDD §6 ("angular cubes, Minecraft-like style") |
| A3. Solid outer shell + hidden inner meshes | Box outside, meshes revealed as it opens up | High — two render systems, shell must update per break | Most literal reading, most work |

**I recommend A1.** It gives the described effect at the lowest cost, and it is the only one that doesn't fight the GDD's stated cubic art direction.

### B — What do the falling meshes look like?

A Creator Store sweep for rock-shard packs turned up nothing clean — results were noisy and mostly unrelated. Three routes:

| Option | Notes |
|---|---|
| **B1. Angular faceted shards** (recommended) | Wedges/cubes at random rotation and irregular scale. No asset dependency, reads as broken rock, **stays inside the GDD's blocky art direction** |
| B2. Art supplies 4–6 rock chunk meshes | Best fidelity, blocks on art, needs `RenderFidelity = Performance` + `CollisionFidelity = Box` |
| B3. Library rocks (e.g. `6233861790`, `12530275269`, `14084159847`) | Fastest, but unvetted quality/licensing and organic shapes clash with cubic kaiju |

**I recommend B1 now, B2 later.** The mechanic can be built and tuned entirely with B1; swapping in real meshes afterwards is a one-line change in the debris spawner.

### C — Pop direction

"Pop in and pop out" reads two ways: **shrink→overshoot→settle** (block absorbs the blow) or **expand→settle** (block flinches outward). §4.2 specs the first, which is the standard impact punch and reads better on something heavy. Say if you meant the second.

### D — Chunks broken per hit

Currently `Max = 1`. The ask and the FTM datapoint both say 2–3. Recommend **`Config.Damage[1].Max = 3`** with `Power = 1`, so a 16-chunk Block clears in ~6 hits × 3 HP. This is the single number that most changes how the test bed feels — worth trying 2 and 3 back to back.

### E — Does the pop apply to the Block or the chunk?

Recommend **the whole Block**, consistent with the glow and sway you already chose. Per-chunk popping would reintroduce exactly the "reads as separate pieces" problem we just removed.

---

# 6. Architecture

Where each piece lands. **No change to server authority.**

```
SERVER                                    CLIENT
VoxelGrid       chunk HP, block counts    DismantleClient
MiningService   what breaks, when           ├── BlockFX      pop · sway · glow · texture slip
  └── fires BlockHit(blockKey, hitPos)      ├── DebrisFX     shed meshes · dust · pooling
  └── fires BlockBroken(blockKey)           └── popup / HUD
```

| Change | File | Size |
|---|---|---|
| Set `Model.WorldPivot` to Block centre on creation | `VoxelGrid` | 1 line |
| `Max` default 1 → 3 | `Config` | 1 line |
| Pop timeline (`ScaleTo`) folded into the existing hit reaction | `DismantleClient` | ~30 lines |
| Debris rewritten: mesh/shard pieces, fall not fling, dust, pooling, cap | `DismantleClient` → split to **`DebrisFX` ModuleScript** | ~90 lines |
| Completion collapse beat | `DismantleClient` | ~15 lines |

The client script is getting long enough that splitting the FX into their own modules is now worth it — that is the one structural change proposed.

**No new remotes.** Debris still keys off `Block Model.ChildRemoved`, which fires for any source, so drones and turrets inherit all of this for free when they arrive.

---

# 7. Performance budget

| | Test bed (1 Block, 16 chunks) | Kaiju (≈1,047 exposed chunks) |
|---|---|---|
| Pieces per hit | 3 | 3 |
| Live debris (cap) | 60 | 60 |
| Textures | 96 | **would be ~6,300 — do not texture kaiju chunks** |

Rules taken from the community research:

1. **Cap live debris** (`MaxLive = 60`), recycle oldest first — VoxelDestruct's `debrisCount`
2. **Pool, don't instantiate** — pre-create the cap, reuse forever. Avoids the clone spike on a 3-piece burst every 200 ms
3. Debris are `CanCollide/CanQuery/CanTouch = false` — they must never shove the player or **intercept the aim ray** (would make the glow flicker)
4. MeshPart debris (if B2) get `RenderFidelity = Performance`, `CollisionFidelity = Box`
5. Dust emitters: one per *hit*, not per piece; `Rate = 0`, `Emit(n)`, short lifetime

---

# 8. Config surface

Everything tunable, nothing hard-coded — consistent with the rest of the project.

```lua
Pop = {
    In = { Scale = 0.94, Time = 0.05, Style = "Quad", Dir = "Out" },
    Out= { Scale = 1.05, Time = 0.09, Style = "Back", Dir = "Out" },
    Settle = {            Time = 0.11, Style = "Quad", Dir = "Out" },
},

Debris = {
    PerChunk   = 1,     -- mesh pieces per broken chunk
    Chips      = 2,     -- extra grit, purely decorative
    Scale      = 0.7,   -- piece size as a fraction of a voxel
    Speed      = 7,     -- studs/s outward — LOW, so it falls rather than flies
    Spin       = 10,
    Lifetime   = 1.2,
    FadeAt     = 0.7,   -- fraction of lifetime before fade starts
    MaxLive    = 60,    -- hard cap, oldest recycled
    Meshes     = { },   -- empty = procedural angular shards (option B1)
},

Dust = { PerHit = 12, PerCompletion = 40, Lifetime = 0.6 },
```

---

# 9. Build order

Each phase is independently playable and independently revertible.

| Phase | Work | Done when |
|---|---|---|
| **1** | `WorldPivot` fix + pop timeline | Block visibly punches on hit, returns to exact base size after 50 hits (no drift) |
| **2** | Debris rewrite: fall not fling, one piece per chunk, `Max = 3` | 2–3 pieces visibly break loose and fall per hit |
| **3** | Dust puffs + completion collapse beat | A finished Block reads differently from a normal hit |
| **4** | Pooling + live cap | 200 hits in 30 s with no frame spike and no instance growth |
| **5** *(optional)* | Real rock meshes (B2), crack decals on damaged chunks | — |

---

# 10. Acceptance tests

1. **No drift.** 50 hits on one Block; every chunk's size and CFrame return to the exact spawn value.
2. **Piece count is honest.** Pieces that fall per hit == chunks actually removed per hit.
3. **It falls, not flies.** Debris lands within ~1 Block-width of its origin; no piece leaves the site.
4. **Cap holds.** Sustained mining never exceeds `MaxLive` debris instances; instance count returns to baseline within `Lifetime` of stopping.
5. **Aim is unaffected.** Glow never flickers while debris crosses the crosshair (proves `CanQuery = false`).
6. **Rebuild stays silent.** Block rebuild after completion sheds *no* debris and fires *no* dust.
7. **Chained hits.** Hits every 200 ms for 10 s — pop never stacks, never lands mid-scale, always settles to 1.0.
8. **Completion is distinct.** Final hit reads as a bigger event than the hit before it.

---

# 11. Risks

| Risk | Mitigation |
|---|---|
| `Model:ScaleTo` fights replication or chunk destruction mid-tween | Client-only; guard every frame on `Model.Parent` and per-part `Parent`; test 1 against it |
| Pivot drift as chunks are destroyed | Explicit `WorldPivot` at creation (§4.2) — the single most likely source of a "block slides while popping" bug |
| Organic rock meshes clash with the GDD's cubic direction | Default to angular shards (B1); meshes are opt-in |
| 3 chunks/hit makes the test bed clear too fast | `Hardness` scales it; try `Max` 2 vs 3 side by side |
| Debris parts intercept the aim ray → glow flicker | `CanQuery = false`, asserted by test 5 |
| FX modules drift from server truth | All FX read `ChildRemoved` / server events; none hold their own model of what exists |

---

# 12. Open question for the design side

`HitMode = "Block"` plus a 2–3 chunk break means the **spatial digging / cavity** behaviour from Doc 2 §83 and Doc 3 §13 is no longer reachable — you can't carve a tunnel where you aim, because the nearest-chunks rule decides for you.

That is a deliberate trade and it is currently the right one for feel. But eggs (GDD §4) depend on *exposing buried objects by removing surrounding material*, which wants directional digging. Worth deciding before Phase 3 of the main build whether eggs surface by proximity to any removal, or whether `HitMode = "Chunk"` returns for the kaiju while the test bed stays on `"Block"`.
