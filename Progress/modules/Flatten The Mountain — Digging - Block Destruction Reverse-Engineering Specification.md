# Flatten The Mountain — Digging / Block Destruction Reverse-Engineering Specification

## 1. Purpose

This document describes the digging/destruction behavior observed in the supplied gameplay video.

The goal is to reproduce the **behavior** in Roblox, not copy private source code.

The system should produce the same gameplay result:

**Aim → Target Large Block → Dig at Hit Location → Remove Internal Material → Create Cavity → Continue Digging → Completely Remove Block → Reward → Select Next Block**

---

# 2. Most Important Observation

The visible white rectangle is a **large logical mining block**.

The game does NOT simply do:

```text
Player hits block
        ↓
Delete entire block
```

Instead, it behaves approximately like:

```text
                 LARGE TARGET BLOCK
             ┌────────────────────────┐
             │                        │
             │   Internal material    │
             │   / voxel sections     │
             │                        │
             │       ↓                │
             │    DIG HERE            │
             │       ↓                │
             │    ███████             │
             │    █  HOLE             │
             │    ███████             │
             │                        │
             └────────────────────────┘
```

The outer target remains while internal material is progressively removed.

This is why the player can see:

- vertical walls
- deeper layers
- remaining pieces
- holes
- separated blocks of material
- different depths inside the same outlined region

---

# 3. White Outline Behavior

The white outline appears to represent the **logical mining block**, not an individual tiny piece.

This is extremely important.

The system should therefore have:

```text
MiningBlock
 ├── TargetBounds
 ├── MaterialData
 ├── InternalVoxelData
 ├── Health
 └── SelectionOutline
```

The outline should remain around the logical block while its internal material is being destroyed.

### Do NOT implement the outline as:

```text
Outline the individual chunk being damaged
```

Instead:

```text
Raycast
   ↓
Find MiningBlock
   ↓
Highlight MiningBlock
```

---

# 4. The Block Has Internal Material

The video strongly suggests that a large target is internally subdivided.

Conceptually:

```text
Large Block
│
├── Internal Cell
├── Internal Cell
├── Internal Cell
├── Internal Cell
├── Internal Cell
├── Internal Cell
├── Internal Cell
└── Internal Cell
```

An **8-cell / 2×2×2 representation is a good implementation starting point**, but the video alone cannot prove that the original game literally stores exactly eight objects.

Therefore:

### Implementation requirement

Make the internal resolution configurable:

```lua
GridSize = Vector3int16.new(2, 2, 2)
```

Do not hard-code the architecture around exactly eight Parts.

This lets us change it later if further footage reveals a finer voxel resolution.

---

# 5. Digging Is Spatial

This is one of the most important behaviors.

The location where the player hits matters.

The system should NOT randomly choose a chunk.

Bad:

```lua
local chunk = RandomChunk()
Destroy(chunk)
```

Correct:

```text
Raycast
   ↓
Hit Position
   ↓
Convert Hit Position into Block Local Space
   ↓
Determine Internal Cell
   ↓
Damage That Area
```

For example:

```text
          LARGE BLOCK
      ┌─────────────────┐
      │  A  │  B        │
      │─────┼─────      │
      │  C  │  D        │
      │     │           │
      └─────────────────┘
```

If the player aims at A:

```text
A receives damage
```

If they move the cursor to D:

```text
D receives damage
```

This creates spatially meaningful digging.

---

# 6. Hit Position Calculation

Roblox raycasting gives us:

```lua
RaycastResult.Position
```

This is the exact world-space location where the tool hit.

Convert it into the mining block's local coordinate system:

```lua
local localHit =
    block.CFrame:PointToObjectSpace(hitPosition)
```

Now the hit is relative to the block.

This is much better than using world coordinates because the block may be rotated.

---

# 7. Convert Hit Position to Internal Cell

Assume the logical block has:

```text
Size.X
Size.Y
Size.Z
```

and:

```text
Grid = 2 × 2 × 2
```

Normalize the hit position:

```lua
local normalizedX =
    (localHit.X / block.Size.X) + 0.5

local normalizedY =
    (localHit.Y / block.Size.Y) + 0.5

local normalizedZ =
    (localHit.Z / block.Size.Z) + 0.5
```

Clamp:

```lua
normalizedX = math.clamp(normalizedX, 0, 0.999999)
normalizedY = math.clamp(normalizedY, 0, 0.999999)
normalizedZ = math.clamp(normalizedZ, 0, 0.999999)
```

Then:

```lua
local x = math.floor(normalizedX * 2)
local y = math.floor(normalizedY * 2)
local z = math.floor(normalizedZ * 2)
```

Now we know which internal region was hit.

---

# 8. Why This Matters for the Video

The video shows that the excavation does not always progress as one uniform rectangle.

Instead, you can see remaining pieces at different positions.

For example, conceptually:

```text
BEFORE

████████
████████
████████
████████


AFTER DIGGING

████████
██  ████
██  ████
████████
```

Later:

```text
████████
██    ██
██ ██ ██
████████
```

And eventually:

```text
████████
██      █
██      █
████████
```

The result is a **spatial cavity**, rather than a simple health bar attached to the entire block.

---

# 9. Important: Digging Appears Discrete

The geometry changes in noticeable discrete steps.

It is not:

```text
Block smoothly shrinks
```

It is closer to:

```text
Hit
 ↓
Material section changes
 ↓
Another hit
 ↓
Another section changes
 ↓
Section disappears
 ↓
Hole becomes larger/deeper
```

Therefore the implementation should use **discrete destruction events**.

Example:

```lua
MiningService:ApplyHit(block, hitPosition, damage)
```

Then:

```text
Determine affected cells
        ↓
Apply damage
        ↓
Check cell health
        ↓
Remove destroyed cells
        ↓
Update visible geometry
        ↓
Update progress
```

---

# 10. Damage and Destruction Are Different

Do not immediately destroy a cell on every hit.

Each internal cell should have health.

Example:

```lua
ChunkState = {
    Health = 10,
    MaxHealth = 10,
    Destroyed = false,
}
```

A hit:

```text
Health = 10
      ↓
Damage 3
      ↓
Health = 7
```

Next:

```text
7
↓
3 damage
↓
4
```

Next:

```text
4
↓
3
↓
1
```

Next:

```text
1
↓
3
↓
0
↓
DESTROYED
```

The exact numbers should be configurable.

---

# 11. A Hit Can Affect Multiple Internal Cells

The video also shows situations where the resulting excavation is larger than a single tiny cube.

Therefore the architecture should support:

```lua
AffectedChunks = 1
```

but also:

```lua
AffectedChunks = 2
```

or:

```lua
AffectedChunks = 3
```

This should be controlled by the player's/tool's damage configuration.

For example:

```lua
ToolStats = {
    Damage = 3,
    MaxAffectedChunks = 1,
}
```

An upgraded tool:

```lua
ToolStats = {
    Damage = 6,
    MaxAffectedChunks = 2,
}
```

---

# 12. Damage Should Be Spatially Connected

If multiple cells are affected, they should generally be selected near the hit cell.

Example:

```text
        Z
        ↑

    [ ][ ][ ]
    [ ][X][ ]
    [ ][ ][ ]

         X
       HIT CELL
```

Possible affected cells:

```text
[X][X]
[X][ ]
```

rather than:

```text
[X][ ][ ]
[ ][ ][ ]
[ ][ ][X]
```

Random distant destruction would not reproduce the observed digging behavior.

---

# 13. Depth Is Important

One of the strongest visual characteristics in the video is that digging produces **depth**.

The player doesn't just remove a flat square from the surface.

Instead:

```text
SURFACE
████████████

      ↓ DIG

████████████
██      ████
██      ████
████████████

      ↓ MORE DIGGING

████████████
██          █
██          █
██          █
████████████
```

Therefore the internal representation needs a **depth axis**.

This is another reason to use:

```text
X × Y × Z
```

rather than a simple 2D grid.

---

# 14. Layer-Based Interpretation

A practical way to reproduce the observed behavior is to think of each block as containing several material layers.

Conceptually:

```text
Layer 0 — Surface
Layer 1 — Shallow
Layer 2 — Middle
Layer 3 — Deep
```

The player first removes material from the surface.

Once the surface material is gone, deeper material becomes visible.

This produces the stair-step / cavity appearance seen in the footage.

---

# 15. Do Not Physically Move the Whole Large Block

The parent mining block should remain logically stationary.

Instead:

```text
MiningBlock
     │
     ├── Cell 1
     ├── Cell 2
     ├── Cell 3
     ├── Cell 4
     └── ...
```

Individual internal material sections disappear.

This produces the illusion that the player is carving into a solid block.

---

# 16. Recommended Logical Data Structure

Use something like:

```lua
MiningBlock = {
    Id = "Block_001",

    CFrame = ...,
    Size = ...,

    GridSize = Vector3int16.new(2, 2, 2),

    Cells = {},

    TotalHealth = 80,
    RemainingHealth = 80,

    Destroyed = false,
}
```

Each cell:

```lua
Cell = {
    Coordinate = Vector3int16.new(x, y, z),

    MaxHealth = 10,
    Health = 10,

    Destroyed = false,

    Visible = true,
}
```

---

# 17. Cell Index

For a 2×2×2 grid:

```text
X = 0/1
Y = 0/1
Z = 0/1
```

A deterministic index can be:

```lua
local index =
    x
    + y * gridX
    + z * gridX * gridY
```

For 2×2×2:

```text
0–7
```

This gives every internal cell a stable identity.

---

# 18. The Mining Pipeline

The final architecture should be:

```text
PLAYER
  │
  │ Click / Mine
  ▼
RAYCAST
  │
  ├── Hit Instance
  ├── Hit Position
  └── Hit Normal
  │
  ▼
BLOCK RESOLVER
  │
  ▼
MINING BLOCK
  │
  ▼
HIT POSITION RESOLVER
  │
  ▼
INTERNAL CELL
  │
  ▼
MINING PATTERN
  │
  ▼
AFFECTED CELLS
  │
  ▼
DAMAGE
  │
  ▼
CELL HEALTH
  │
  ├── Still alive
  │
  └── Destroyed
          │
          ▼
     REMOVE VISUAL
          │
          ▼
     UPDATE PROGRESS
          │
          ▼
   CHECK BLOCK COMPLETE
          │
          ▼
        REWARD
          │
          ▼
    NEXT TARGET BLOCK
```

---

# 19. Block Completion

The video shows a clear transition after enough material is removed.

The player receives a small reward indicator:

```text
+$1
```

and the mining target changes.

Therefore:

```lua
if remainingMaterial <= 0 then
    CompleteBlock(block)
end
```

Block completion should:

1. Destroy remaining visual material.
2. Mark block as completed.
3. Award money.
4. Update global progress.
5. Find/select the next available block.

---

# 20. Reward Should NOT Happen on Every Hit

The observed `+$1` appears associated with completion of a mining section/block rather than every individual damage event.

Therefore separate:

```text
Damage Event
```

from:

```text
Block Completion Event
```

Example:

```lua
MiningService:ApplyDamage(...)
```

versus:

```lua
BlockBreakService:CompleteBlock(...)
RewardService:GiveReward(...)
```

---

# 21. Target Selection

After a block is completed:

```text
Current Block
      ↓
Destroyed
      ↓
Find next mineable block
      ↓
New white outline
```

The white outline should therefore be dynamically assigned.

```lua
TargetService:SetTarget(player, newBlock)
```

---

# 22. Recommended Server Architecture

For Roblox, the server should be authoritative.

### Client

Responsible for:

- mouse position
- visual raycast
- tool animation
- hit VFX
- target outline preview

### Server

Responsible for:

- validating target
- validating distance
- validating cooldown
- calculating actual hit
- resolving internal cell
- applying damage
- destroying cells
- awarding money
- updating progress

Architecture:

```text
CLIENT
   │
   │ Mine Request
   ▼
SERVER
   │
   ├── Validate player
   ├── Validate distance
   ├── Validate cooldown
   ├── Validate target
   ├── Resolve hit
   ├── Resolve cell
   ├── Apply damage
   ├── Destroy cell
   └── Award progress/reward
```

Never trust:

```lua
RemoteEvent:FireServer(block, damage, chunk)
```

without server validation.

---

# 23. Rendering Strategy

For the first prototype, the easiest implementation is:

```text
1 logical block
      ↓
8 visible internal Parts
```

Each internal Part represents one cell.

When damaged enough:

```lua
cellPart:Destroy()
```

This allows us to test the gameplay very quickly.

However, this should be treated as a **prototype renderer**, not necessarily the final production solution.

---

# 24. Production Architecture

Eventually separate:

```text
LOGICAL DESTRUCTION
```

from:

```text
VISUAL GEOMETRY
```

For example:

```text
MiningBlock
     │
     ├── CellState
     │
     ├── Health
     │
     └── DestructionState
             │
             ▼
       RenderService
             │
             ▼
      Visible Geometry
```

This allows us to change the visual implementation without rewriting the mining logic.

---

# 25. Hit Normal Should Also Be Stored

The raycast provides:

```lua
hitNormal
```

Keep this information.

It tells us which surface the player hit.

For example:

```text
Top surface
    ↓
Y-

Front surface
    ↓
Z+

Side surface
    ↓
X+
```

This can be used to determine how the excavation progresses.

For example, if the player hits the top:

```text
remove top-facing material first
```

If they hit a side:

```text
remove side-facing material first
```

This should be tested against additional footage before making it mandatory.

---

# 26. Recommended Mining Pattern Algorithm

Do not simply destroy the hit cell.

Instead:

```lua
local centerCell =
    ResolveHitCell(block, hitPosition)

local affectedCells =
    MiningPatternService:GetAffectedCells(
        block,
        centerCell,
        hitNormal,
        toolStats
    )
```

Then:

```lua
for _, cell in affectedCells do
    ChunkDamageService:Damage(
        cell,
        toolStats.Damage
    )
end
```

This provides a clean upgrade path.

---

# 27. Tool Upgrades

The same destruction system can support:

### Weak tool

```text
Damage: 1
Affected Cells: 1
```

### Medium tool

```text
Damage: 3
Affected Cells: 1
```

### Strong tool

```text
Damage: 5
Affected Cells: 2
```

### Advanced tool

```text
Damage: 10
Affected Cells: 3
```

The mining algorithm remains the same.

Only the tool statistics change.

---

# 28. Drone and Turret Compatibility

This architecture is particularly useful for your Dismantle game.

Your GDD specifies three dismantling methods: the player's handheld tool, drones that automatically carve, and turrets that continuously carve.

Therefore they should all call the **same MiningService**.

```text
PLAYER
   │
   └────────┐
            │
DRONE ──────┼──→ MiningService
            │
TURRET ─────┘
```

Do NOT create:

```text
PlayerMiningSystem
DroneMiningSystem
TurretMiningSystem
```

with three different destruction implementations.

Instead:

```text
Player/Drone/Turret
       ↓
MiningService
       ↓
Same block/chunk destruction logic
```

---

# 29. Global Progress

Your GDD requires the dismantling process to ultimately reach 100%, with physical disappearance of the kaiju being an important part of the experience.

Therefore progress should be calculated from material.

Recommended:

```text
Total Material
      -
Destroyed Material
      =
Remaining Material
```

Then:

```lua
progress =
    1 - (remainingHealth / totalHealth)
```

This is better than:

```text
Number of Blocks Destroyed / Number of Blocks
```

because partially damaged material should contribute toward the overall progress.

---

# 30. Eggs / Hidden Objects

Your GDD also says eggs are buried inside the kaiju and become exposed as material is removed.

This means the destruction system should expose interior objects naturally.

Conceptually:

```text
MiningBlock
   │
   ├── Material Cells
   │
   └── Egg
```

When the cells covering the egg are destroyed:

```text
Egg becomes exposed
        ↓
Egg interaction becomes available
```

This is another reason the system should track **3D internal material**, rather than simply deleting a whole surface block.

---

# 31. Important Correction to the Original 8-Chunk Idea

After analyzing the video, I would NOT lock the final implementation to:

```text
1 large block = exactly 8 chunks
```

as a permanent assumption.

Instead:

```text
1 large block = configurable 3D voxel/cell volume
```

with:

```lua
GridSize = Vector3int16.new(2, 2, 2)
```

as the first implementation.

Why?

Because the video demonstrates **internal spatial destruction**, but video footage cannot prove the original developer's exact internal data structure.

The game could internally use:

```text
2×2×2
```

or:

```text
4×4×4
```

or:

```text
voxel grid + depth layers
```

while producing the same visible result.

We should reproduce the behavior rather than assume the original code structure.

---

# 32. Exact Behavior We Should Target

The final Roblox implementation should feel like:

```text
PLAYER AIMS
     ↓
WHITE OUTLINE APPEARS
     ↓
PLAYER HITS BLOCK
     ↓
HIT POSITION IS RECORDED
     ↓
CORRESPONDING INTERNAL MATERIAL IS DAMAGED
     ↓
SMALL SECTION DISAPPEARS
     ↓
CAVITY BECOMES VISIBLE
     ↓
PLAYER CAN CONTINUE DIGGING INSIDE CAVITY
     ↓
DEEPER MATERIAL IS REVEALED
     ↓
MORE MATERIAL DISAPPEARS
     ↓
BLOCK COMPLETES
     ↓
+$REWARD
     ↓
NEXT BLOCK BECOMES TARGET
```

---

# 33. Critical Prototype Test

Before implementing the entire mountain/kaiju, create only:

```text
1 Large Block
```

Use:

```text
Grid = 2×2×2
Cell HP = 10
Damage = 3
Affected Cells = 1
```

Then perform this exact test.

### Test A — Same location

Hit the same location repeatedly.

Expected:

```text
Hit 1 → same cell HP 7
Hit 2 → same cell HP 4
Hit 3 → same cell HP 1
Hit 4 → cell destroyed
```

Only that area should disappear.

---

### Test B — Different location

Move the cursor to another part of the block.

Expected:

```text
Different hit position
        ↓
Different internal cell
        ↓
Different area receives damage
```

---

### Test C — Multiple cells

Set:

```text
AffectedCells = 2
```

Expected:

```text
Hit
 ↓
Center cell + neighboring cell
 ↓
Both receive damage
```

---

### Test D — Depth

Continue mining the same location.

Expected:

```text
Surface
 ↓
Shallow cavity
 ↓
Deeper cavity
 ↓
Deep cavity
```

The result should look like the footage.

---

### Test E — Completion

Destroy every internal material cell.

Expected:

```text
Last cell destroyed
        ↓
Block disappears
        ↓
Reward
        ↓
Next target
```

---

# 34. Recommended Module Structure

```text
ReplicatedStorage
└── Mining
    ├── MiningConfig
    ├── MiningTypes
    └── MiningRemotes

ServerScriptService
└── Mining
    ├── MiningService
    ├── MiningValidator
    ├── BlockResolver
    ├── HitPositionResolver
    ├── ChunkResolver
    ├── MiningPatternService
    ├── ChunkDamageService
    ├── BlockBreakService
    ├── ProgressService
    └── RewardService

StarterPlayer
└── StarterPlayerScripts
    └── MiningController
        ├── ClientRaycast
        ├── TargetOutline
        ├── ToolAnimation
        └── MiningInput
```

---

# 35. Debug Mode

The prototype should include a debug mode.

When enabled, display:

```text
Target Block: Block_001

Hit Position:
X: 0.32
Y: 0.71
Z: 0.44

Resolved Cell:
X: 0
Y: 1
Z: 0

Cell HP:
7 / 10

Affected Cells:
1

Remaining Block Health:
47 / 80

Global Progress:
41.25%
```

Also optionally render the internal cell boundaries.

This will make it much easier to compare our implementation against the reference footage.

---

# 36. Final Implementation Principle

The most important rule is:

> **The player is not mining the visual Part. The player is mining logical material inside a target Block.**

The visual geometry is simply the representation of the logical material state.

Therefore:

```text
RAYCAST
   ↓
LOGICAL BLOCK
   ↓
HIT POSITION
   ↓
INTERNAL CELL
   ↓
DAMAGE
   ↓
CELL STATE
   ↓
VISUAL UPDATE
```

This architecture gives us the same type of digging behavior seen in the video while remaining flexible enough to support:

- better tools
- stronger damage
- larger mining areas
- drones
- turrets
- hidden eggs
- global dismantling progress
- multiplayer
- different voxel resolutions
- different kaiju sizes
- different materials
- future weapons

---

# 37. Bottom Line

Based on the supplied footage, I would implement the system as a **3D logical voxel/cell destruction system contained inside larger selectable mining blocks**.

The initial prototype should use:

```text
Large Block
     ↓
2×2×2 internal cells
     ↓
Hit-position-based selection
     ↓
Per-cell health
     ↓
Spatially connected multi-cell damage
     ↓
Discrete cell removal
     ↓
Cavity/depth formation
     ↓
Block completion
     ↓
Reward
     ↓
Next block
```

But the **2×2×2 resolution should remain configurable**, because the video proves the behavior, not the exact internal implementation used by Flatten The Mountain.