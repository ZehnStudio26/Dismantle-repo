# Dismantle
## Hierarchical Block & Internal Chunk Destruction System

**Project:** Dismantle — Working Title  
**Platform:** Roblox  
**Reference Gameplay:** Flatten The Mountain  
**System:** Block Selection + Internal Chunk Damage + Progressive Destruction  
**Document Purpose:** Technical implementation specification for Roblox/Luau

---

# 1. Overview

The purpose of this system is to reproduce the specific mining behavior observed in **Flatten The Mountain** and adapt it to Dismantle.

The important behavior is:

1. The mountain/kaiju is composed of large visible **Blocks**.
2. The player raycasts against a Block.
3. The currently targeted Block receives a **white outline**.
4. The Block is not necessarily the smallest destruction unit.
5. Internally, one Block is divided into approximately **8 smaller chunks**.
6. The exact location where the raycast hits the Block determines an **internal hit offset**.
7. That offset determines which internal chunk(s) receive damage.
8. Repeated attacks progressively damage those internal chunks.
9. Eventually one internal chunk breaks/disappears.
10. Continued attacks can cause additional chunks to break.
11. A stronger attack can affect multiple nearby internal chunks.
12. The visible Block updates as its internal chunks disappear.
13. Eventually the entire Block is destroyed.
14. The same underlying system should be usable by the player, drones, and turrets.

The most important distinction is:

> **The raycast selects a large Block, but the hit offset determines where inside that Block the destruction occurs.**

---

# 2. Reference Behavior

Public information confirms that Flatten The Mountain's gameplay revolves around mining blocks/voxels for cash, with manual mining and automated systems such as drones and turrets.

Public gameplay documentation also reports that Player Damage can change the amount of voxel material removed per swing. One dated observation reported three voxels being removed after an early Damage upgrade. This is useful as a behavioral reference, but it should not be treated as proof of the private implementation.

For Dismantle, the target implementation should therefore reproduce the **observable behavior**, not attempt to copy private source code.

---

# 3. Core Concept

The system has three levels:

```text
KAIJU / MOUNTAIN
        │
        ▼
     BLOCKS
        │
        ▼
 INTERNAL CHUNKS
        │
        ▼
  INTERNAL DAMAGE
```

More explicitly:

```text
Kaiju
│
├── Block 0001
│   ├── Chunk 0
│   ├── Chunk 1
│   ├── Chunk 2
│   ├── Chunk 3
│   ├── Chunk 4
│   ├── Chunk 5
│   ├── Chunk 6
│   └── Chunk 7
│
├── Block 0002
│   ├── Chunk 0
│   ├── Chunk 1
│   └── ...
│
└── Block 0003
    └── ...
```

The **Block** is the primary gameplay target.

The **Chunk** is the internal destruction unit.

---

# 4. Why This Hierarchy Is Required

A simple implementation would be:

```text
Raycast
↓
Find Part
↓
Destroy Part
```

That cannot reproduce the observed behavior.

The required system is:

```text
Raycast
↓
Find Block
↓
Calculate exact hit position
↓
Convert hit position into Block-local offset
↓
Find internal chunk
↓
Apply damage
↓
Check chunk health
↓
Break chunk if necessary
↓
Update Block
```

This allows the player to hit different areas of the same visible Block.

---

# 5. Visual Representation

Consider one Block.

From outside, the player sees:

```text
┌──────────────────────┐
│                      │
│                      │
│        BLOCK         │
│                      │
│                      │
└──────────────────────┘
```

When targeted:

```text
╔══════════════════════╗
║                      ║
║        BLOCK         ║
║                      ║
╚══════════════════════╝
```

The white outline represents the **large Block**.

Internally, however:

```text
┌──────────────────────┐
│       │       │      │
│   C0  │   C1  │      │
│───────┼───────│      │
│   C2  │   C3  │      │
│───────┼───────│      │
│   C4  │   C5  │      │
│───────┼───────│      │
│   C6  │   C7  │      │
└──────────────────────┘
```

The exact visual subdivision does not need to be visible to the player.

It is internal data.

---

# 6. 8-Chunk Model

For the first implementation, use:

```lua
InternalGridSize = Vector3int16.new(2, 2, 2)
```

This produces:

```text
2 × 2 × 2 = 8 chunks
```

The chunks can be indexed:

```text
        Front

      0 ─── 1
      │     │
      2 ─── 3

      Back

      4 ─── 5
      │     │
      6 ─── 7
```

Internally:

```lua
Block.InternalGrid.Chunks[0]
Block.InternalGrid.Chunks[1]
...
Block.InternalGrid.Chunks[7]
```

Do not hardcode the number `8` throughout the code.

Use configuration.

---

# 7. Configuration

Create:

```text
ReplicatedStorage
└── Shared
    └── Config
        └── DestructionConfig
```

Example:

```lua
return {
    BlockSize = Vector3.new(8, 8, 8),

    InternalGridSize = Vector3int16.new(2, 2, 2),

    ChunkHealth = 10,

    DefaultMiningDamage = 1,

    HighlightEnabled = true,

    HighlightFillTransparency = 1,

    HighlightOutlineTransparency = 0,

    MaxMiningDistance = 20,
}
```

The actual BlockSize should eventually be determined by the Dismantle prototype.

---

# 8. Block Data

A Block should not simply be a Roblox Part.

It should have corresponding logical data.

Example:

```lua
local BlockData = {
    Id = 1001,

    Position = Vector3.zero,

    Size = Vector3.new(8, 8, 8),

    Material = "KaijuFlesh",

    InternalGrid = {
        SizeX = 2,
        SizeY = 2,
        SizeZ = 2,

        Chunks = {}
    },

    Destroyed = false,
}
```

---

# 9. Internal Chunk Data

Each internal chunk should contain its own state.

Example:

```lua
local ChunkData = {
    Id = 0,

    Coordinate = Vector3int16.new(0, 0, 0),

    Health = 10,

    MaxHealth = 10,

    Occupied = true,

    Destroyed = false,
}
```

The initial state is:

```text
Health = MaxHealth
Occupied = true
Destroyed = false
```

---

# 10. Block State

A Block can therefore contain:

```text
Block
│
├── Chunk 0
│   └── 10 / 10 HP
│
├── Chunk 1
│   └── 10 / 10 HP
│
├── Chunk 2
│   └── 10 / 10 HP
│
├── Chunk 3
│   └── 10 / 10 HP
│
├── Chunk 4
│   └── 10 / 10 HP
│
├── Chunk 5
│   └── 10 / 10 HP
│
├── Chunk 6
│   └── 10 / 10 HP
│
└── Chunk 7
    └── 10 / 10 HP
```

Initially:

```text
8/8 chunks alive
```

After one chunk breaks:

```text
7/8 chunks alive
```

After three chunks break:

```text
5/8 chunks alive
```

After all break:

```text
0/8 chunks alive
```

Then the Block itself is considered destroyed.

---

# 11. Raycast

The client performs the visual targeting raycast.

Example:

```lua
local result = workspace:Raycast(
    origin,
    direction,
    raycastParams
)
```

The result provides:

```lua
result.Instance
result.Position
result.Normal
```

The important values are:

```text
Target Block
Hit Position
Hit Normal
```

---

# 12. Finding the Block

The raycast may hit:

- Block geometry;
- generated geometry;
- collision geometry;
- a proxy Part.

Therefore the system should resolve the actual logical Block.

Create:

```text
BlockResolver
```

with:

```lua
BlockResolver:GetBlockFromInstance(instance)
```

Example:

```lua
local block =
    BlockResolver:GetBlockFromInstance(
        result.Instance
    )
```

The resolver should never assume that the directly hit Roblox Instance is always the logical Block.

---

# 13. White Outline

Once the raycast identifies the Block:

```text
Raycast
↓
BlockResolver
↓
Block
↓
Highlight
```

Create a Roblox `Highlight` associated with the selected Block.

Example:

```lua
highlight.Adornee = block.RenderInstance
```

Configure:

```text
FillTransparency = 1
OutlineTransparency = 0
OutlineColor = white
```

The outline should represent:

> **The entire Block that the player is currently targeting.**

It should NOT move to individual internal chunks.

---

# 14. Targeting Example

Player aims here:

```text
┌───────────────────────┐
│                       │
│                  X    │
│                       │
│                       │
└───────────────────────┘
```

The entire Block becomes outlined:

```text
╔═══════════════════════╗
║                       ║
║                  X    ║
║                       ║
║                       ║
╚═══════════════════════╝
```

The internal destruction target is then determined from `X`.

---

# 15. Hit Offset

This is the most important calculation.

Given:

```lua
hitPosition
```

and:

```lua
block.CFrame
```

calculate:

```lua
local hitOffset =
    block.CFrame:PointToObjectSpace(
        hitPosition
    )
```

Now the position is expressed relative to the Block.

For example:

```text
World Position:

X = 124
Y = 20
Z = -52
```

could become:

```text
Block Local Position:

X = 2.3
Y = -1.1
Z = 3.4
```

This is the **Hit Offset**.

---

# 16. Why Hit Offset Is Important

Suppose the player attacks:

```text
Left side
```

The offset might be:

```text
X = -3
```

Attack the center:

```text
X = 0
```

Attack the right:

```text
X = +3
```

These should resolve to different internal chunks.

Therefore:

```text
Same Block
+
Different Hit Position
=
Different Internal Destruction Location
```

This is the mechanic that must be preserved.

---

# 17. Normalized Offset

For easier calculations, normalize the local position.

Assume:

```text
Block Size = 8
```

Convert:

```text
-4 → 0
+4 → 1
```

Conceptually:

```lua
local normalizedX =
    (localPosition.X / blockSize.X) + 0.5
```

Do this for:

```text
X
Y
Z
```

Result:

```text
normalizedPosition =
(
    0 → 1,
    0 → 1,
    0 → 1
)
```

This makes it easy to map the hit to the internal grid.

---

# 18. Internal Chunk Coordinate

If:

```text
InternalGrid = 2 × 2 × 2
```

then:

```lua
local chunkX =
    math.floor(normalizedX * 2)

local chunkY =
    math.floor(normalizedY * 2)

local chunkZ =
    math.floor(normalizedZ * 2)
```

Clamp:

```lua
chunkX = math.clamp(chunkX, 0, 1)
chunkY = math.clamp(chunkY, 0, 1)
chunkZ = math.clamp(chunkZ, 0, 1)
```

Now:

```text
Hit Offset
    ↓
Internal Chunk Coordinate
```

---

# 19. Chunk Index

Convert:

```text
X,Y,Z
```

into a single index.

For a 2×2×2 grid:

```lua
local index =
    chunkX
    + chunkY * 2
    + chunkZ * 4
```

This gives:

```text
(0,0,0) → 0
(1,0,0) → 1
(0,1,0) → 2
(1,1,0) → 3
(0,0,1) → 4
(1,0,1) → 5
(0,1,1) → 6
(1,1,1) → 7
```

This gives us the internal destruction target.

---

# 20. Mining Operation

The final mining operation should look like:

```text
Player Attack
     ↓
Raycast
     ↓
Block Resolver
     ↓
Target Block
     ↓
Hit Offset
     ↓
Chunk Resolver
     ↓
Internal Chunk
     ↓
Damage
```

The player does NOT directly destroy the chunk.

The server performs the authoritative operation.

---

# 21. Client/Server Architecture

Client:

```text
Raycast
↓
Determine visual target
↓
Show white outline
↓
Send mining request
```

Server:

```text
Receive request
↓
Validate request
↓
Resolve Block
↓
Resolve actual hit offset
↓
Resolve internal chunks
↓
Apply damage
↓
Break chunks
↓
Update block
↓
Award reward
↓
Update progress
```

---

# 22. Do Not Trust Client Chunk Coordinates

The client should NOT send:

```lua
chunkIndex = 7
```

and expect the server to destroy chunk 7.

An exploiter could simply send:

```lua
chunkIndex = 7
```

for every request.

Instead, the server should receive enough information to validate the hit and calculate the internal target itself.

Prefer:

```lua
MineRequest:FireServer(
    targetBlockId,
    hitPosition,
    hitNormal
)
```

Then:

```text
SERVER
↓
validate
↓
recalculate
↓
resolve chunk
```

---

# 23. Server Validation

Create:

```text
MiningValidator
```

Validate:

### Player state

```text
Player exists
Character exists
Character alive
Tool equipped
```

### Distance

```text
Player → hit position
```

must be within the player's mining range.

### Target

The target must belong to:

```text
Dismantle's BlockWorld
```

### Cooldown

Prevent:

```text
10,000 mining requests / second
```

### Position

The reported hit position must be close enough to a legitimate raycast result.

---

# 24. Server Raycast Verification

For stronger security, the server can perform its own raycast.

Conceptually:

```text
Client:
"I hit Block A here."

Server:
"Let me verify that the player could actually hit Block A."
```

Server:

```lua
local serverResult =
    workspace:Raycast(
        serverOrigin,
        serverDirection,
        params
    )
```

Then compare:

```text
Client target
vs
Server target
```

The exact amount of verification can be adjusted for performance.

---

# 25. Damage Model

Each internal chunk has:

```text
Health
MaxHealth
```

Example:

```text
10 HP
```

Player Damage:

```text
1
```

Then:

```text
Hit 1 → 9 HP
Hit 2 → 8 HP
Hit 3 → 7 HP
...
Hit 10 → 0 HP
```

At:

```text
Health <= 0
```

the chunk breaks.

---

# 26. Important: Damage and Number of Chunks Are Separate

Do not confuse:

```text
Damage
```

with:

```text
Number of chunks affected
```

They are two separate concepts.

For example:

```text
Damage = 3
Affected Chunks = 1
```

means:

> One chunk receives 3 damage.

But:

```text
Damage = 3
Affected Chunks = 3
```

means:

> Three chunks each receive damage.

This separation is extremely useful for upgrades.

---

# 27. Mining Pattern

Create:

```text
MiningPatternService
```

Input:

```text
Center Chunk
Hit Normal
Damage
Mining Level
```

Output:

```text
Affected Chunk List
```

Example:

```lua
{
    Chunk0,
    Chunk1,
    Chunk2
}
```

---

# 28. Example Patterns

### Level 1

```text
X
```

One chunk.

### Level 2

```text
XX
```

Two chunks.

### Level 3

```text
XXX
```

Three chunks.

### Level 4

```text
XXX
XXX
```

Six chunks.

### Level 5

```text
XXX
XXX
XXX
```

Nine chunks.

However, these are examples only.

The exact Dismantle progression should be tuned during gameplay testing.

---

# 29. Hit Normal and Pattern Direction

The hit normal can determine which direction the mining pattern expands.

For example:

```text
Player
  ↓
Block surface
```

The pattern should expand along the surface rather than randomly through the Block.

Conceptually:

```text
Hit Normal
     ↓
Determine surface plane
     ↓
Orient mining pattern
     ↓
Select neighboring chunks
```

This allows the destruction to feel physically connected to the player's hit.

---

# 30. Example

Player hits:

```text
Front surface
```

The target chunk is:

```text
C3
```

A 3-chunk horizontal pattern could become:

```text
C2 C3 C4
```

rather than:

```text
C0 C3 C7
```

The exact selection should depend on the block's internal grid and available neighboring chunks.

---

# 31. Prevent Destroying Empty Chunks

Suppose:

```text
C3 = destroyed
```

and the player attacks near C3 again.

Do not apply damage to C3.

Instead:

```text
Target C3
↓
C3 already destroyed
↓
Find valid neighboring chunk
```

The system should optionally redirect the mining pattern to remaining material.

---

# 32. Progressive Block Damage

Example:

Initial:

```text
████████
████████
████████
████████
```

Internally:

```text
8 chunks alive
```

After several hits:

```text
████████
████████
███░████
████████
```

Internal state:

```text
7 chunks alive
```

After more hits:

```text
████████
██░░████
██░░████
████████
```

Internal state:

```text
5 chunks alive
```

Eventually:

```text
████████
██░░░░██
██░░░░██
████████
```

Then additional chunks disappear until:

```text
░░░░░░░░
░░░░░░░░
░░░░░░░░
░░░░░░░░
```

The Block is now destroyed.

---

# 33. Block Break Condition

A Block is broken when:

```lua
remainingChunks == 0
```

or:

```lua
remainingMaterial <= 0
```

Then:

```lua
BlockBreakService:Break(block)
```

fires.

---

# 34. Block Break Event

Create:

```text
BlockBroken
```

Payload:

```lua
{
    BlockId = block.Id,

    Position = block.Position,

    Material = block.Material,

    Source = source,

    Reward = reward
}
```

Listeners can include:

```text
RewardService
ProgressService
EggService
AudioService
VFXService
```

---

# 35. Chunk Break Event

Also create:

```text
ChunkBroken
```

Payload:

```lua
{
    BlockId = block.Id,

    ChunkIndex = chunkIndex,

    Position = chunkWorldPosition,

    Source = source
}
```

This allows VFX to happen at the exact destroyed internal area.

---

# 36. Visual Destruction

The logical system and rendering system should remain separate.

Logical:

```text
Chunk.Destroyed = true
```

Rendering:

```text
BlockRenderer
↓
Update visible geometry
```

Do not let VFX determine whether a chunk actually exists.

---

# 37. Block Renderer

Create:

```text
BlockRenderer
```

Responsibilities:

```text
Read block state
↓
Determine which chunks remain
↓
Generate/update visible geometry
```

It should never own:

```text
Damage
Rewards
Progress
```

---

# 38. Simple Prototype Renderer

For the first prototype, each internal chunk can temporarily be represented by a Part.

Example:

```text
Block
├── ChunkPart0
├── ChunkPart1
├── ChunkPart2
├── ChunkPart3
├── ChunkPart4
├── ChunkPart5
├── ChunkPart6
└── ChunkPart7
```

When:

```text
Chunk.Destroyed = true
```

temporarily:

```lua
chunkPart.Transparency = 1
chunkPart.CanCollide = false
```

This is for proving the mechanic.

Do not assume this is the final production renderer.

---

# 39. Production Renderer

Once the gameplay is proven, replace the prototype renderer with a more efficient solution.

Possible approaches:

```text
Chunk meshes
Greedy meshing
Combined geometry
Voxel destruction module
Custom mesh generation
```

The gameplay API should remain unchanged.

That means:

```text
MiningService
```

should not care how the geometry is rendered.

---

# 40. Collision

Collision should correspond to the logical state.

When a chunk is destroyed:

```text
Chunk exists = false
```

then its collision should disappear.

Prototype:

```lua
chunkPart.CanCollide = false
```

Production:

```text
Update collision geometry
```

Do not leave invisible collision inside holes.

---

# 41. Block Outline After Damage

The white outline should continue to target the **logical Block**, not each remaining chunk.

If:

```text
Chunk 3
```

breaks:

```text
Block remains targetable.
```

Therefore:

```text
Highlight.Adornee = BlockRender
```

not:

```text
Highlight.Adornee = ChunkRender
```

---

# 42. Outline When Block Is Destroyed

When:

```text
remainingChunks == 0
```

the Block disappears.

At that point:

```text
Remove Highlight
```

and select another valid Block if the player is still aiming at the mountain.

---

# 43. Target Switching

Player moves the cursor:

```text
Block A
```

to:

```text
Block B
```

The system should:

```text
Remove outline from A
Add outline to B
```

Do not create a new Highlight every frame.

Use one reusable Highlight:

```text
TargetHighlight
```

and change:

```lua
TargetHighlight.Adornee
```

---

# 44. Mining Cooldown

The player should have a configurable mining cooldown.

Example:

```lua
MiningCooldown = 0.2
```

Flow:

```text
Attack
↓
Mine
↓
Cooldown
↓
Attack
```

The server should enforce the cooldown.

The client may predict the swing animation, but the server determines whether the mining operation actually succeeds.

---

# 45. Player Damage Upgrade

Player Damage should affect the mining operation.

Example:

```text
Level 1
Damage = 1

Level 2
Damage = 2

Level 3
Damage = 4

Level 4
Damage = 6
```

But remember:

```text
Damage ≠ number of chunks
```

A Damage upgrade could either:

1. remove chunks faster;
2. affect more chunks;
3. or both.

Keep these as separate configurable stats.

---

# 46. Recommended Mining Stats

```lua
MiningStats = {
    Damage = 1,

    Cooldown = 0.25,

    MaxRange = 20,

    ChunkRadius = 0,

    MaxAffectedChunks = 1,

    Pattern = "Single",
}
```

Later:

```lua
MiningStats = {
    Damage = 4,

    Cooldown = 0.15,

    MaxRange = 25,

    ChunkRadius = 1,

    MaxAffectedChunks = 3,

    Pattern = "SurfaceCluster",
}
```

---

# 47. Drones

The Dismantle GDD requires drones to automatically carve around the player/designated area.

The drone should use the same system:

```text
Drone
 ↓
Select Block
 ↓
Select Hit Position
 ↓
MiningService
 ↓
Hit Offset
 ↓
Internal Chunk
 ↓
Damage
```

The drone does not need a different destruction engine.

---

# 48. Drone Target Position

The drone can choose:

```text
Block center
```

for simple behavior.

But for more natural destruction:

```text
Block
 ↓
Find exposed surface
 ↓
Choose target position
 ↓
MiningService
```

This allows drones to carve different parts of the kaiju.

---

# 49. Turrets

Turrets similarly:

```text
Turret
 ↓
Ray/beam target
 ↓
Block
 ↓
Hit Position
 ↓
MiningService
```

The turret's laser is only the visual representation.

Actual destruction is:

```text
MiningService
```

---

# 50. Shared Mining Architecture

The final system should therefore be:

```text
                   MiningService
                         │
            ┌────────────┼────────────┐
            │            │            │
         Player        Drone        Turret
            │            │            │
            └────────────┼────────────┘
                         │
                         ▼
                    BlockResolver
                         │
                         ▼
                   HitOffsetResolver
                         │
                         ▼
                   ChunkResolver
                         │
                         ▼
                 MiningPatternService
                         │
                         ▼
                  ChunkDamageService
                         │
                 ┌───────┴────────┐
                 ▼                ▼
            ChunkBroken       BlockBroken
                 │                │
                 └───────┬────────┘
                         ▼
                    Event System
```

---

# 51. Complete Module Architecture

Recommended:

```text
ServerScriptService
│
├── Services
│   │
│   ├── BlockWorldService
│   │
│   ├── BlockResolver
│   │
│   ├── HitOffsetResolver
│   │
│   ├── ChunkResolver
│   │
│   ├── ChunkDamageService
│   │
│   ├── MiningPatternService
│   │
│   ├── MiningService
│   │
│   ├── MiningValidator
│   │
│   ├── BlockBreakService
│   │
│   ├── BlockRenderService
│   │
│   ├── ProgressService
│   │
│   ├── RewardService
│   │
│   ├── DroneService
│   │
│   └── TurretService
```

---

# 52. Responsibilities

## BlockWorldService

Owns:

```text
All blocks
Block lookup
Block registration
Block removal
Spatial lookup
```

---

## BlockResolver

Converts:

```text
Roblox Instance
↓
Logical Block
```

---

## HitOffsetResolver

Converts:

```text
World hit position
↓
Block-local position
↓
Normalized offset
```

---

## ChunkResolver

Converts:

```text
Block-local offset
↓
Internal chunk coordinate
↓
Chunk
```

---

## ChunkDamageService

Handles:

```text
Damage
Health
Destruction
```

---

## MiningPatternService

Determines:

```text
Which chunk(s) are affected
```

---

## MiningService

Coordinates the entire mining operation.

---

## MiningValidator

Prevents invalid/exploitative mining.

---

## BlockBreakService

Handles:

```text
Block destroyed
Rewards
Completion
Cleanup
```

---

## BlockRenderService

Updates:

```text
Visible geometry
Collision
Visual effects
```

---

# 53. MiningService Pseudocode

```lua
function MiningService:Mine(
    source,
    block,
    hitPosition,
    hitNormal,
    stats
)

    if not MiningValidator:Validate(
        source,
        block,
        hitPosition,
        stats
    ) then
        return false
    end

    local offset =
        HitOffsetResolver:GetBlockOffset(
            block,
            hitPosition
        )

    local centerChunk =
        ChunkResolver:GetChunkAtOffset(
            block,
            offset
        )

    if not centerChunk then
        return false
    end

    local affectedChunks =
        MiningPatternService:GetAffectedChunks(
            block,
            centerChunk,
            hitNormal,
            stats
        )

    local brokenChunks = {}

    for _, chunk in affectedChunks do

        if not chunk.Destroyed then

            local destroyed =
                ChunkDamageService:Damage(
                    chunk,
                    stats.Damage
                )

            if destroyed then
                table.insert(
                    brokenChunks,
                    chunk
                )
            end
        end
    end

    if #brokenChunks == 0 then
        return false
    end

    BlockRenderService:UpdateBlock(
        block,
        brokenChunks
    )

    EventService:Fire(
        "ChunkBroken",
        brokenChunks
    )

    if block:GetRemainingChunkCount() == 0 then

        BlockBreakService:Break(
            block,
            source
        )

    end

    return true
end
```

---

# 54. HitOffsetResolver

Example:

```lua
function HitOffsetResolver:GetBlockOffset(
    block,
    worldPosition
)

    local localPosition =
        block.CFrame:PointToObjectSpace(
            worldPosition
        )

    local size = block.Size

    local normalized = Vector3.new(
        (localPosition.X / size.X) + 0.5,
        (localPosition.Y / size.Y) + 0.5,
        (localPosition.Z / size.Z) + 0.5
    )

    return Vector3.new(
        math.clamp(normalized.X, 0, 1),
        math.clamp(normalized.Y, 0, 1),
        math.clamp(normalized.Z, 0, 1)
    )
end
```

---

# 55. ChunkResolver

Example:

```lua
function ChunkResolver:GetChunkAtOffset(
    block,
    offset
)

    local grid = block.InternalGrid

    local x =
        math.clamp(
            math.floor(
                offset.X * grid.SizeX
            ),
            0,
            grid.SizeX - 1
        )

    local y =
        math.clamp(
            math.floor(
                offset.Y * grid.SizeY
            ),
            0,
            grid.SizeY - 1
        )

    local z =
        math.clamp(
            math.floor(
                offset.Z * grid.SizeZ
            ),
            0,
            grid.SizeZ - 1
        )

    return grid:GetChunk(x, y, z)
end
```

---

# 56. Chunk Damage

```lua
function ChunkDamageService:Damage(
    chunk,
    amount
)

    if chunk.Destroyed then
        return false
    end

    chunk.Health -= amount

    if chunk.Health <= 0 then

        chunk.Health = 0
        chunk.Destroyed = true
        chunk.Occupied = false

        return true
    end

    return false
end
```

---

# 57. Multiple Chunk Destruction

The system should support:

```text
1 chunk
```

and:

```text
2 chunks
```

and:

```text
3 chunks
```

from one mining operation.

Example:

```text
Player Damage Level 1
→ 1 affected chunk

Player Damage Level 2
→ 1–2 affected chunks

Player Damage Level 3
→ 2–3 affected chunks
```

The exact balance should be configurable.

---

# 58. Do Not Randomly Choose Chunks

Bad implementation:

```lua
chunk = randomChunk()
```

This would make the system feel disconnected from the player's aim.

Instead:

```text
Hit Position
↓
Hit Offset
↓
Center Chunk
↓
Neighbor Selection
```

The destruction must remain spatially connected to the hit.

---

# 59. Neighbor Selection

Given:

```text
Center = Chunk 3
```

find:

```text
left
right
up
down
front
back
```

depending on the mining pattern.

Example:

```text
    C2
     │
C1 ─ C3 ─ C4
     │
    C5
```

Then choose from these neighbors according to:

```text
Damage
Pattern
Hit Normal
Remaining chunks
```

---

# 60. Boundary Handling

If the player hits a chunk on the edge:

```text
┌───┬───┐
│   │ X │
├───┼───┤
│   │   │
└───┴───┘
```

the mining pattern must not attempt to access nonexistent chunks.

Use:

```lua
if chunk then
    -- valid
end
```

before applying damage.

---

# 61. Neighboring Blocks

A Block's internal chunks may border another Block.

Example:

```text
BLOCK A | BLOCK B
```

If an internal chunk near the edge breaks, the renderer must correctly preserve the boundary between the two Blocks.

Do not accidentally:

```text
destroy neighboring Block geometry
```

just because an internal chunk is missing.

---

# 62. Block-to-Block Mining

The raycast can switch from:

```text
Block A
```

to:

```text
Block B
```

The outline should switch immediately.

The mining system should then calculate the offset relative to **Block B**, not the previous Block.

---

# 63. Targeting Flow

Every render frame:

```text
Camera
 ↓
Raycast
 ↓
Resolve Block
 ↓
Compare Current Target
```

If target changed:

```text
Update Highlight
```

Do NOT perform destruction every frame.

Mining only occurs when the attack action occurs.

---

# 64. Targeting and Mining Are Separate

This distinction is important.

### Targeting:

```text
Raycast
↓
Highlight Block
```

### Mining:

```text
Attack
↓
Validate
↓
Calculate offset
↓
Damage chunks
```

The player can look at a Block without damaging it.

---

# 65. Visual Feedback

When a chunk is damaged but not destroyed:

```text
Hit VFX
Hit SFX
Small impact
```

When a chunk breaks:

```text
Break VFX
Debris
Chunk disappearance
Stronger SFX
```

When a Block completely breaks:

```text
Large break effect
Cash popup
Progress update
```

---

# 66. Dismantle Adaptation

Instead of a mountain:

```text
Kaiju
```

contains:

```text
Block grid
```

Each Block can have materials:

```text
KaijuFlesh
Bone
Armor
RareFlesh
EggShell
```

The internal chunks inherit the material unless special behavior is required.

---

# 67. Kaiju Shape

The large kaiju should not need to be a perfect cube.

You can have:

```text
          HEAD
       █████████
      ███████████
   ███████████████
      █████████
        █████
```

Internally:

```text
Block
Block
Block
Block
```

Each large Block maintains its own internal chunk grid.

---

# 68. Irregular Blocks

If the kaiju silhouette is irregular:

```text
Block A
Block B
Block C
```

some internal chunks may initially be:

```text
Occupied = false
```

Example:

```text
Chunk 0 = occupied
Chunk 1 = occupied
Chunk 2 = occupied
Chunk 3 = empty
```

This allows the Block to have an irregular shape.

---

# 69. Empty Internal Chunks

An empty chunk should:

```text
Occupied = false
Destroyed = true
```

or use a separate state:

```text
State = "Empty"
```

Do not allow mining to reward empty chunks.

---

# 70. Eggs

The GDD states that eggs are buried inside the kaiju and become exposed as players/drones/turrets remove surrounding material.

This hierarchical chunk system makes egg placement easier.

An egg can belong to:

```text
Block 512
```

and:

```text
Chunk 5
```

Example:

```lua
Egg = {
    BlockId = 512,
    ChunkIndex = 5,
    LocalOffset = Vector3.new(...)
}
```

When that chunk becomes destroyed/exposed:

```text
EggService
↓
Check Egg
↓
Reveal Egg
```

---

# 71. Progress Calculation

For Dismantle, track:

```text
Total Chunks
Destroyed Chunks
```

but the final progress can also account for partially damaged chunks if desired.

Simple version:

```text
Progress =
DestroyedChunks / TotalChunks
```

Better version:

```text
Progress =
DestroyedMaterial / TotalMaterial
```

The GDD requires shared dismantling progress reaching 100%.

For the first prototype, use:

```text
Destroyed internal material / total internal material
```

because it allows partially damaged Blocks to contribute to progress.

---

# 72. Recommended Progress Model

Each chunk:

```lua
MaxHealth = 10
Health = 6
```

Remaining material:

```text
6 / 10
```

Destroyed percentage:

```text
4 / 10 = 40%
```

This allows:

```text
Progress
```

to increase with every hit instead of only when a chunk finally disappears.

---

# 73. Example

8 chunks:

```text
10 HP each
```

Total:

```text
80 HP
```

Player damages one chunk:

```text
10 → 9
```

Global destruction:

```text
1 / 80 = 1.25%
```

After 10 hits:

```text
Chunk destroyed
```

Progress:

```text
10 / 80 = 12.5%
```

This provides smooth global dismantling progress.

---

# 74. Reward Model

Do not necessarily wait until a whole Block breaks to give money.

Possible:

```text
Damage material
↓
Reward proportional to material removed
```

Example:

```text
1 damage = $1
```

Then:

```text
10 damage
=
$10
```

But the exact economy should be configured separately.

---

# 75. Block Metadata

Recommended:

```lua
BlockData = {
    Id = 1001,

    Material = "Flesh",

    RewardPerHealth = 1,

    InternalGrid = {
        SizeX = 2,
        SizeY = 2,
        SizeZ = 2
    },

    TotalHealth = 80,

    RemainingHealth = 80
}
```

---

# 76. Performance Strategy

The system should NOT create:

```text
8 Roblox Parts
```

for every Block in the final production version if the kaiju contains thousands of Blocks.

That could become expensive.

Instead:

```text
Logical Block
+
Internal chunk data
+
combined/rendered geometry
```

The 8-chunk representation can remain logical.

---

# 77. Prototype vs Production

## Prototype

Use:

```text
1 Block Part
+
8 internal Chunk Parts
```

This makes debugging extremely easy.

## Production

Use:

```text
1 rendered Block/mesh region
+
internal chunk state
```

or:

```text
chunk-based generated geometry
```

depending on performance.

The gameplay code should not change.

---

# 78. Debug Visualization

Create a debug toggle:

```lua
DebugDestruction = true
```

When enabled, show internal chunks:

```text
┌────┬────┐
│ C0 │ C1 │
├────┼────┤
│ C2 │ C3 │
├────┼────┤
│ C4 │ C5 │
├────┼────┤
│ C6 │ C7 │
└────┴────┘
```

Also display:

```text
Target Block: 103
Hit Offset: 0.72, 0.34, 0.91
Target Chunk: 5
Chunk HP: 7/10
Affected Chunks: 5,6
```

This is extremely valuable when matching the reference behavior.

---

# 79. Debug UI

Example:

```text
--------------------------------
 DESTRUCTION DEBUG
--------------------------------

Block: 103

Hit Offset:
X: 0.72
Y: 0.34
Z: 0.91

Chunk:
X: 1
Y: 0
Z: 1

Chunk Index:
5

Health:
7 / 10

Affected:
5

Destroyed:
3 / 8

Block Remaining:
47 / 80 HP
--------------------------------
```

---

# 80. Testing Procedure

The first test should use exactly:

```text
1 Block
2×2×2 internal chunks
10 HP per chunk
1 damage per hit
```

Then:

### Test A

Hit center.

Expected:

```text
Center internal chunk receives damage.
```

### Test B

Hit left.

Expected:

```text
Left internal chunk receives damage.
```

### Test C

Hit right.

Expected:

```text
Right internal chunk receives damage.
```

### Test D

Hit the same location repeatedly.

Expected:

```text
Same chunk continues receiving damage.
```

### Test E

Destroy one chunk.

Expected:

```text
Only that chunk disappears.
```

### Test F

Hit another location.

Expected:

```text
Different chunk begins taking damage.
```

---

# 81. Critical Test

This is the most important test for matching your observation.

Start:

```text
8 chunks
```

Then hit:

```text
Location A
```

until one chunk breaks.

Verify:

```text
1 chunk disappeared.
```

Then hit:

```text
Location B
```

until another chunk breaks.

Verify:

```text
Second chunk disappears.
```

Then increase Damage.

Verify that:

```text
2–3 nearby chunks
```

can be affected by a single attack when the upgrade/pattern calls for it.

---

# 82. No Random Destruction

The system must NOT behave like:

```text
Player hits Block
↓
Random chunk breaks
```

Instead:

```text
Player hits Block
↓
Exact hit offset
↓
Exact chunk
↓
Damage
```

This is essential.

---

# 83. Same Location = Same Internal Region

If the player repeatedly attacks exactly the same position:

```text
X = 2
Y = 4
Z = 3
```

the system should repeatedly target the same internal region until it breaks.

This gives the player a sense that they are physically carving into the Block.

---

# 84. Slightly Different Location = Different Offset

If the player moves their aim:

```text
X = 2.0
```

to:

```text
X = 2.8
```

the calculated internal offset changes.

If the new position crosses the internal chunk boundary, the target chunk changes.

This creates the feeling of:

> "I'm cutting this side of the block now."

---

# 85. Internal Chunk Boundary

For a 2×2×2 Block:

```text
Normalized X = 0.49
```

might target:

```text
X chunk = 0
```

while:

```text
Normalized X = 0.51
```

targets:

```text
X chunk = 1
```

This boundary must be deterministic.

---

# 86. Hit Offset Must Be Based on the Actual Hit

Do not calculate:

```lua
offset = camera.LookVector
```

alone.

Use:

```lua
hitPosition
```

because the player can hit different locations on the same surface.

The camera direction determines the ray.

The raycast intersection determines the actual mining location.

---

# 87. Surface Depth

If the ray enters the visible surface:

```text
Block front
      ↓
████████
```

the hit position is on the surface.

For a more advanced implementation, the system can calculate:

```text
Surface Hit
+
Normal
+
Depth
```

to create a deeper carving effect.

This can later evolve into:

```text
surface damage
→ internal material removal
```

without changing the high-level architecture.

---

# 88. Future Advanced Version

If you eventually want more detailed destruction:

```text
Block
 ↓
Internal chunks
 ↓
Microvoxels
```

Example:

```text
Block
  ↓
8 Chunks
  ↓
Each Chunk = 4×4×4 Microvoxels
```

Then the architecture becomes:

```text
Block
 ├── Chunk
 │    ├── MicroVoxel
 │    ├── MicroVoxel
 │    └── ...
 └── ...
```

But do NOT implement this initially.

Start with:

```text
Block
 ↓
8 chunks
```

and prove the gameplay.

---

# 89. Recommended Final Hierarchy

For Dismantle:

```text
KAIJU
│
├── Block
│   │
│   ├── Internal Chunk 0
│   ├── Internal Chunk 1
│   ├── Internal Chunk 2
│   ├── Internal Chunk 3
│   ├── Internal Chunk 4
│   ├── Internal Chunk 5
│   ├── Internal Chunk 6
│   └── Internal Chunk 7
│
├── Block
│   └── ...
│
└── Block
    └── ...
```

Gameplay:

```text
Raycast
↓
Block
↓
White Outline
↓
Hit Position
↓
Block Local Offset
↓
Internal Chunk
↓
Mining Pattern
↓
Damage
↓
Chunk Break
↓
Block Update
↓
Progress
↓
Reward
```

---

# 90. Master Implementation Prompt

Give the following to Claude Code / Antigravity after the project has been inspected.

---

## MASTER PROMPT

You are a senior Roblox/Luau gameplay engineer.

We are implementing the core destruction/mining system for a Roblox game called **Dismantle**.

The game is inspired by the observable mining behavior of **Flatten The Mountain**, but you must implement an original system and must NOT claim or reproduce private source code.

The target behavior is a hierarchical destruction system.

The critical mechanic is:

```text
A large visible Block is the player's target.
The Block receives a white outline when raycast-selected.
The Block contains an internal grid of approximately 8 smaller chunks.
The exact raycast hit position inside the Block determines an internal hit offset.
That offset determines which internal chunk receives damage.
Repeated hits damage the same internal region.
When a chunk's health reaches zero, that chunk breaks/disappears.
Later attacks can break additional chunks.
Stronger mining can affect multiple nearby chunks.
When all internal chunks are destroyed, the parent Block breaks.
```

Do NOT implement:

```text
Raycast → Destroy Part
```

Implement:

```text
Raycast
→ Large Block
→ Hit Position
→ Block Local Offset
→ Internal Chunk
→ Mining Pattern
→ Chunk Damage
→ Chunk Break
→ Block Update
→ Reward
→ Progress
```

---

## 1. INSPECT THE EXISTING PROJECT FIRST

Before changing anything:

- inspect the existing Roblox hierarchy;
- inspect existing scripts;
- inspect existing modules;
- inspect existing remotes;
- inspect existing kaiju/mountain geometry;
- inspect existing tools;
- inspect existing UI;
- inspect existing dependencies.

Do not delete unrelated systems.

Do not rewrite the entire project unnecessarily.

Explain the existing architecture before implementing the new system.

---

## 2. BUILD A MINIMAL TEST FIRST

Create exactly one test Block.

Configuration:

```lua
BlockSize = Vector3.new(8,8,8)

InternalGridSize =
    Vector3int16.new(2,2,2)

ChunkHealth = 10

MiningDamage = 1
```

Therefore:

```text
1 Block
=
2 × 2 × 2
=
8 internal chunks
```

Make the internal chunks visible in debug mode.

---

## 3. RAYCAST TARGETING

Implement client-side raycasting.

The raycast must resolve:

```text
Hit Instance
Hit Position
Hit Normal
Logical Block
```

The player should see a white outline around the entire Block.

Use one reusable Highlight object.

Do not create a new Highlight every frame.

---

## 4. BLOCK RESOLUTION

Create:

```text
BlockResolver
```

Implement:

```lua
BlockResolver:GetBlockFromInstance(instance)
```

The raycast may hit:

- Block geometry;
- generated geometry;
- proxy collision geometry.

Resolve the logical Block correctly.

---

## 5. HIT OFFSET

This is a critical requirement.

Given:

```lua
block
hitPosition
```

calculate:

```lua
local localPosition =
    block.CFrame:PointToObjectSpace(
        hitPosition
    )
```

Then normalize the local position relative to the Block size.

The result should be:

```text
0 → 1
```

for:

```text
X
Y
Z
```

This normalized position is the internal hit offset.

---

## 6. INTERNAL CHUNK RESOLUTION

With:

```text
InternalGridSize = 2×2×2
```

convert:

```text
Hit Offset
↓
Chunk X/Y/Z
```

using floor and clamp.

Example:

```lua
local x =
    math.clamp(
        math.floor(offset.X * 2),
        0,
        1
    )
```

Repeat for Y/Z.

Resolve the exact internal chunk.

---

## 7. IMPORTANT BEHAVIOR

If the player repeatedly hits the same location:

```text
same Block
+
same hit region
```

the same internal chunk should continue receiving damage.

Do not randomly select another chunk.

If the player changes the hit location enough to cross into another internal region, the target chunk should change.

---

## 8. CHUNK DAMAGE

Every chunk has:

```text
Health
MaxHealth
Destroyed
Occupied
```

Example:

```lua
Health = 10
MaxHealth = 10
```

When:

```text
Damage = 1
```

the sequence is:

```text
10
9
8
7
6
5
4
3
2
1
0
```

At zero:

```text
Destroyed = true
Occupied = false
```

and the chunk visually disappears.

---

## 9. DAMAGE IS NOT CHUNK COUNT

Keep these separate:

```text
Damage
```

and:

```text
Affected Chunk Count
```

For example:

```text
Damage = 3
AffectedChunks = 1
```

means:

> One chunk takes 3 damage.

While:

```text
Damage = 3
AffectedChunks = 3
```

means:

> Three chunks each receive 3 damage.

Both systems must be configurable.

---

## 10. MINING PATTERN

Create:

```text
MiningPatternService
```

Implement:

```lua
GetAffectedChunks(
    block,
    centerChunk,
    hitNormal,
    miningStats
)
```

The result should be an ordered list of valid chunks.

Start with:

```text
Single
```

Then implement:

```text
SurfaceCluster
```

which can affect neighboring chunks based on:

- hit normal;
- center chunk;
- damage level;
- max affected chunks.

---

## 11. SPATIAL CONSISTENCY

Do NOT randomly choose chunks.

The affected chunks must be spatially close to the hit location.

For example:

```text
    A
B   C   D
    E
```

If C is the center, an area attack can select:

```text
C
```

or:

```text
B,C,D
```

depending on the mining level.

---

## 12. CHUNK BOUNDARIES

If the target is at the edge of the internal grid:

```text
┌────┬────┐
│ C0 │ C1 │
├────┼────┤
│ C2 │ C3 │
└────┴────┘
```

and the mining pattern requests a nonexistent neighbor:

```text
C4
```

ignore it.

Never create invalid chunk references.

---

## 13. BLOCK BREAK

When:

```text
remainingChunks == 0
```

the parent Block is destroyed.

Call:

```lua
BlockBreakService:Break(block)
```

This should:

- remove block collision;
- remove block rendering;
- remove target highlight;
- award final Block reward;
- update dismantling progress;
- emit BlockBroken.

---

## 14. EVENTS

Create:

```text
ChunkDamaged
ChunkBroken
BlockDamaged
BlockBroken
MiningPerformed
DismantleProgressChanged
```

Example:

```lua
EventService:Fire(
    "ChunkBroken",
    {
        BlockId = block.Id,
        ChunkIndex = chunk.Index,
        Source = source
    }
)
```

---

## 15. RENDERING

Keep rendering separate from logical destruction.

Logical:

```text
chunk.Destroyed = true
```

Rendering:

```text
BlockRenderService
```

updates the geometry.

For the first prototype, individual chunk Parts are acceptable.

Do not optimize prematurely.

---

## 16. WHITE OUTLINE

The white outline must remain associated with the parent Block.

It must NOT outline individual internal chunks.

Example:

```text
Logical:
Block
 ├── Chunk 0
 ├── Chunk 1
 └── ...

Target:
Block

Highlight:
Block
```

not:

```text
Highlight:
Chunk 0
```

---

## 17. PLAYER MINING

Player flow:

```text
Player presses attack
↓
Client raycast
↓
Target Block identified
↓
Client displays/updates white outline
↓
Client sends MineRequest
↓
Server validates
↓
Server resolves Block
↓
Server calculates hit offset
↓
Server resolves internal chunk(s)
↓
Server applies damage
↓
Server updates geometry
↓
Server gives reward
↓
Server updates progress
```

---

## 18. SECURITY

Never trust:

```text
Client damage
Client reward
Client chunk index
Client block health
Client progress
```

The client can provide:

```text
hitPosition
hitNormal
target identifier
```

but the server must validate and calculate the actual result.

---

## 19. SERVER VALIDATION

Implement:

```text
MiningValidator
```

Check:

```text
Player exists
Character exists
Character alive
Tool equipped
Target valid
Target belongs to BlockWorld
Distance valid
Cooldown valid
Hit position plausible
```

Reject invalid requests.

---

## 20. PLAYER / DRONE / TURRET

All mining sources MUST call:

```text
MiningService
```

Player:

```text
MiningService:Mine(...)
```

Drone:

```text
MiningService:Mine(...)
```

Turret:

```text
MiningService:Mine(...)
```

Do not build three separate destruction engines.

---

## 21. DRONES

Drones should:

```text
Find Block
↓
Find exposed/valid target
↓
Generate target position
↓
Call MiningService
```

Drone stats:

```text
Damage
Rate
Speed
Range
MaxAffectedChunks
Pattern
```

---

## 22. TURRETS

Turrets should:

```text
Find Block
↓
Aim
↓
Play beam
↓
Call MiningService
```

The beam is visual.

The MiningService is authoritative.

---

## 23. PROGRESS

Track:

```text
TotalMaterial
RemainingMaterial
DestroyedMaterial
```

Recommended:

```lua
Progress =
    DestroyedMaterial / TotalMaterial
```

This allows partially damaged chunks to contribute to overall Dismantle progress.

---

## 24. REWARDS

Rewards must be based on actual server-authorized destruction.

Do not award cash for:

```text
hit animation
client request
VFX
```

Award only when:

```text
server confirms actual material damage/removal
```

---

## 25. DEBUG MODE

Implement:

```lua
DebugDestruction = true
```

When enabled, display:

```text
Target Block
Hit Offset
Chunk Coordinate
Chunk Index
Chunk Health
Affected Chunks
Remaining Block Health
Global Progress
```

Also visually show internal chunk boundaries.

---

## 26. TEST SCENARIO

Create a test Block with:

```text
2×2×2 chunks
10 HP each
```

Test:

### Test 1

Hit center repeatedly.

Expected:

```text
Same internal chunk receives damage.
```

### Test 2

Move aim to another section.

Expected:

```text
Different internal chunk receives damage.
```

### Test 3

Destroy first chunk.

Expected:

```text
Only first chunk disappears.
Block remains.
```

### Test 4

Destroy second and third chunks.

Expected:

```text
Multiple holes appear inside same Block.
```

### Test 5

Destroy all 8 chunks.

Expected:

```text
Parent Block disappears.
```

### Test 6

Increase mining damage.

Expected:

```text
Chunks break faster.
```

### Test 7

Increase max affected chunks.

Expected:

```text
2–3 spatially adjacent chunks can be damaged by one attack.
```

---

## 27. PERFORMANCE

Do not:

```text
rebuild entire kaiju every hit
scan every block every frame
scan every chunk every frame
create new Highlight every frame
create thousands of temporary Parts per hit
let clients own destruction state
```

Prefer:

```text
Block lookup cache
Chunk lookup
Dirty blocks
Dirty geometry
Reusable Highlight
Server-authoritative state
Event-driven updates
```

---

## 28. FINAL ARCHITECTURE

Implement:

```text
                         PLAYER
                           │
                         Raycast
                           │
                           ▼
                    ┌──────────────┐
                    │ BlockResolver│
                    └──────┬───────┘
                           │
                           ▼
                     TARGET BLOCK
                           │
                     White Outline
                           │
                           ▼
                    Hit Position
                           │
                           ▼
                  HitOffsetResolver
                           │
                           ▼
                   Internal Offset
                           │
                           ▼
                    ChunkResolver
                           │
                           ▼
                    Center Chunk
                           │
                           ▼
                MiningPatternService
                           │
                           ▼
                 Affected Chunk(s)
                           │
                           ▼
                ChunkDamageService
                           │
                  ┌────────┴────────┐
                  ▼                 ▼
            Chunk Broken       Chunk Damaged
                  │                 │
                  └────────┬────────┘
                           ▼
                    BlockRenderService
                           │
                           ▼
                    ProgressService
                           │
                           ▼
                     RewardService
```

---

# 29. FINAL PRINCIPLE

The implementation should preserve this exact mental model:

```text
        WHAT PLAYER SEES
              │
              ▼
       ┌─────────────┐
       │    BLOCK    │ ← White outline
       └─────────────┘
              │
              │ hidden internal structure
              ▼
       ┌────┬────┐
       │ C0 │ C1 │
       ├────┼────┤
       │ C2 │ C3 │
       ├────┼────┤
       │ C4 │ C5 │
       ├────┼────┤
       │ C6 │ C7 │
       └────┴────┘
              │
              ▼
       Hit Offset selects
       internal region
              │
              ▼
       Damage accumulates
              │
              ▼
       Chunk breaks
              │
              ▼
       Block progressively
       disappears
```

The key implementation formula is:

```text
RAYCAST HIT
     ↓
TARGET BLOCK
     ↓
BLOCK-LOCAL HIT OFFSET
     ↓
INTERNAL CHUNK
     ↓
MINING PATTERN
     ↓
DAMAGE
     ↓
CHUNK BREAK
     ↓
BLOCK UPDATE
```

**Do not replace this with `Raycast → Destroy Part`.**

The internal offset is the core of the mechanic.