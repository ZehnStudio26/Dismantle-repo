# Dismantle — Voxel Mining Reverse Engineering & Implementation Specification

**Project:** Dismantle — Working Title  
**Platform:** Roblox  
**Players:** Up to 4 players  
**Reference:** Flatten The Mountain  
**Purpose:** Recreate the core voxel-dismantling feel while adapting it to the Dismantle game design.

---

# 1. Objective

Dismantle is a cooperative Roblox game where players progressively remove a gigantic kaiju corpse until it reaches 100% dismantled.

The core interaction is:

> Player aims at the kaiju → mining/cutting hit occurs → a localized group of voxels disappears → player receives progress/reward → the visible geometry updates.

Automation later performs the same underlying operation through drones and turrets.

The important architectural principle is:

> **Player, Drone, and Turret should all ultimately use the same mining/destruction system.**

They should not each have completely different destruction implementations.

The GDD specifically defines three dismantling methods:

1. Handheld cutter/chainsaw
2. Drone
3. Turret

The handheld tool directly removes material, while drones and turrets automate dismantling.

The GDD also requires the physical kaiju to visibly disappear as it is dismantled, with the progress eventually reaching 100%.

---

# 2. What We Know About Flatten The Mountain

Public gameplay information confirms that Flatten The Mountain uses a block/voxel-style mining interaction.

Its public description and gameplay material describe:

- mining blocks for cash;
- upgrading through a Skill Tree;
- buried chests;
- automated mining;
- drones;
- turrets;
- progressive flattening of the mountain.

Public guides describe the mountain as a voxel tower and describe the player breaking individual voxels/blocks.

Public observations also report that a Damage upgrade could cause multiple voxels to be removed from a single swing. One dated observation recorded three voxels being removed from a swing after an early Damage upgrade. This should be treated as a gameplay observation, **not as proof of the private implementation**.

The exact source code, voxel data structure, chunk size, remeshing algorithm, server architecture, and mining pattern of Flatten The Mountain are not publicly verified.

Therefore, the architecture below is a **reverse-engineered technical hypothesis** followed by a recommended implementation.

---

# 3. Important Distinction: Visual Block vs Internal Voxel

One of the most important concepts is that the large visible mountain/kaiju should not necessarily be treated as thousands of independent Roblox Parts.

A naive implementation would be:

```text
Kaiju
 ├── Part
 ├── Part
 ├── Part
 ├── Part
 ├── Part
 └── ...
```

and then:

```lua
part:Destroy()
```

when the player hits something.

This can work for a prototype but becomes inefficient and difficult to control at large scale.

A better architecture is:

```text
                VOXEL WORLD
                    │
             ┌──────┴──────┐
             │             │
          Chunk A        Chunk B
             │             │
       ┌─────┴─────┐      │
       │ voxel data │      │
       │ voxel data │      │
       │ voxel data │      │
       └────────────┘      │
```

The visible geometry is generated from internal voxel data.

Conceptually:

```text
Voxel Data
     ↓
Geometry / Mesh / Parts
     ↓
Roblox World
```

When a voxel is removed:

```text
Voxel Data changes
       ↓
Affected chunk identified
       ↓
Chunk geometry updated
       ↓
Player sees missing material
```

---

# 4. Reverse-Engineered Mining Pipeline

The likely interaction pipeline is:

```text
PLAYER SWING
     │
     ▼
Raycast
     │
     ▼
Hit Position
Hit Normal
Hit Instance
     │
     ▼
Identify Voxel World
     │
     ▼
Identify Chunk
     │
     ▼
Convert World Position → Chunk Local Position
     │
     ▼
Convert Local Position → Voxel Coordinate
     │
     ▼
Determine Mining Pattern
     │
     ▼
Determine Damage
     │
     ▼
Find Affected Voxels
     │
     ▼
Remove / Damage Voxels
     │
     ▼
Update Chunk Geometry
     │
     ▼
Update Dismantling Progress
     │
     ▼
Reward Player
     │
     ▼
Replicate Result
```

This is the core system that Dismantle should be built around.

---

# 5. Step 1 — Detect the Hit

The client controls the player's aiming/camera.

When the player attacks:

```lua
local origin = camera.CFrame.Position
local direction = camera.CFrame.LookVector * MAX_DISTANCE

local result = workspace:Raycast(
    origin,
    direction,
    raycastParams
)
```

The raycast gives us something similar to:

```lua
result.Instance
result.Position
result.Normal
result.Material
```

The most important value is:

```lua
result.Position
```

because this tells the mining system exactly where the player hit.

---

# 6. Why Hit Position Matters

Suppose the kaiju is made from a voxel grid:

```text
+---+---+---+---+
| A | B | C | D |
+---+---+---+---+
| E | F | G | H |
+---+---+---+---+
| I | J | K | L |
+---+---+---+---+
```

A hit on:

```text
F
```

should not randomly remove:

```text
A
B
K
L
```

Instead, the mining system converts the hit location into a voxel coordinate.

For example:

```text
World Position
      ↓
Chunk Local Position
      ↓
Voxel Coordinate
      ↓
(12, 7, 24)
```

That coordinate becomes the center of the mining operation.

---

# 7. World Space → Local Space

If a chunk is rotated or positioned in the world, directly using world coordinates can cause problems.

Instead:

```lua
local localPosition =
    chunk.CFrame:PointToObjectSpace(hitPosition)
```

Now the hit is expressed relative to the chunk.

Example:

```text
World:
X = 154
Y = 28
Z = -92

Chunk local:
X = 14
Y = 8
Z = 22
```

The local position can then be converted into voxel coordinates.

---

# 8. Local Position → Voxel Coordinate

Assume:

```lua
VOXEL_SIZE = 4
```

Then:

```lua
local voxelX = math.floor(localPosition.X / VOXEL_SIZE)
local voxelY = math.floor(localPosition.Y / VOXEL_SIZE)
local voxelZ = math.floor(localPosition.Z / VOXEL_SIZE)
```

Conceptually:

```text
Local Position
      ↓
divide by voxel size
      ↓
floor()
      ↓
Voxel X/Y/Z
```

For example:

```text
Local Position:

X = 14.3
Y = 8.7
Z = 22.1

Voxel Size = 4

X = floor(14.3 / 4) = 3
Y = floor(8.7  / 4) = 2
Z = floor(22.1 / 4) = 5

Voxel = (3,2,5)
```

The exact voxel size for Flatten The Mountain is **not publicly verified**.

For Dismantle, voxel size should be configurable.

---

# 9. Chunk System

Do not create one gigantic voxel array if the kaiju is extremely large.

Divide the kaiju into chunks.

Example:

```text
KAiju
│
├── Chunk_0_0_0
├── Chunk_0_0_1
├── Chunk_0_1_0
├── Chunk_0_1_1
├── Chunk_1_0_0
├── Chunk_1_0_1
└── ...
```

Each chunk owns a portion of the voxel grid.

Example:

```text
Chunk
Size:

16 × 16 × 16 voxels
```

or:

```text
32 × 32 × 32
```

The actual value should be benchmarked.

---

# 10. Why Chunks Are Important

Without chunks:

```text
Every hit
   ↓
rebuild entire kaiju
```

This would be extremely expensive.

With chunks:

```text
Player hits voxel
       ↓
Find affected chunk
       ↓
Modify chunk
       ↓
Rebuild only affected chunk
```

This greatly reduces work.

For example:

```text
KAJU
┌─────────┬─────────┐
│ Chunk A │ Chunk B │
├─────────┼─────────┤
│ Chunk C │ Chunk D │
└─────────┴─────────┘
```

Player hits Chunk D.

Only:

```text
Chunk D
```

and possibly neighboring boundary chunks need updating.

---

# 11. Voxel Data Structure

A simple implementation could use:

```lua
VoxelGrid[x][y][z]
```

However, nested Lua tables can become expensive.

A flattened index is often preferable:

```lua
index =
    x
    + y * SIZE_X
    + z * SIZE_X * SIZE_Y
```

Then:

```lua
voxels[index] = voxel
```

A voxel might contain:

```lua
{
    Occupied = true,
    Material = "Flesh",
    Health = 1,
    Value = 1
}
```

For Dismantle, a more useful structure might be:

```lua
{
    Occupied = true,
    Material = MaterialId,
    Health = 1,
    MaxHealth = 1,
    Reward = 1,
    EggId = nil
}
```

---

# 12. Do NOT Assume Every Voxel Needs Individual Health

There are two possible systems.

## System A — One-hit voxel

```text
Health = 1

Hit
↓
Voxel disappears
```

This is ideal for simple mining.

## System B — Damaged voxel

```text
Health = 10

Hit
↓
Health = 7

Hit
↓
Health = 4

Hit
↓
Health = 0

Voxel disappears
```

The public evidence does not establish which system Flatten The Mountain uses.

For Dismantle, the recommended approach is:

> Keep voxel health configurable.

This allows:

```lua
VoxelHealthMode = "OneHit"
```

or:

```lua
VoxelHealthMode = "Durability"
```

without rebuilding the entire mining architecture.

---

# 13. Mining Damage

Damage should be independent from the actual voxel system.

For example:

```lua
PlayerDamage = 1
```

could mean:

```text
1 hit → 1 voxel
```

while:

```lua
PlayerDamage = 3
```

could mean:

```text
1 hit → up to 3 voxels
```

This aligns with the observed gameplay concept where a damage upgrade was associated with multiple voxels being removed per swing.

But do not hardcode:

```lua
Damage = NumberOfVoxels
```

because a better system is to define a mining pattern.

---

# 14. Mining Pattern System

Create:

```text
MiningPattern
```

instead of putting voxel-selection logic directly inside the weapon.

Example:

```lua
MiningPattern.GetAffectedVoxels(
    centerVoxel,
    damage,
    hitNormal
)
```

Possible patterns:

### Pattern 1 — Single

```text
X
```

### Pattern 2 — Horizontal

```text
XXX
```

### Pattern 3 — Vertical

```text
 X
 X
 X
```

### Pattern 4 — Cross

```text
 X
XXX
 X
```

### Pattern 5 — 3D cluster

```text
XXX
XXX
XXX
```

The player's Damage upgrade can change the pattern.

---

# 15. Example Damage Progression

Instead of thinking:

```text
Damage = 1
Damage = 2
Damage = 3
```

think:

```text
Damage Level 1
    ↓
1 voxel

Damage Level 2
    ↓
3 voxels

Damage Level 3
    ↓
5 voxels

Damage Level 4
    ↓
3×3 area
```

This makes upgrades visually meaningful.

The Dismantle GDD specifically states that upgrades should visibly increase dismantling speed.

---

# 16. Hit Normal

The raycast also gives:

```lua
result.Normal
```

Example:

```text
Player
   ↓
   ↓
[ KAIJU ]
```

Hit normal:

```text
(0, 0, 1)
```

This tells the system which surface was hit.

It can be used to prevent a mining pattern from behaving strangely.

For example:

```text
Front face:

XXX
XXX
XXX
```

but if the player hits the top:

```text
XXX
XXX
XXX
```

the pattern should be oriented relative to the surface.

The exact role of hit normals in Flatten The Mountain is not publicly verified, so this should be considered an implementation recommendation rather than reverse-engineered fact.

---

# 17. Server Authority

The client should NOT be allowed to simply say:

```lua
DestroyVoxel(position)
```

because exploiters could call:

```lua
DestroyVoxel(
    Vector3.new(999999,999999,999999)
)
```

or:

```lua
GiveCash(100000000)
```

Instead:

```text
CLIENT
  │
  │ Attack request
  ▼
SERVER
  │
  ├── validate player
  ├── validate cooldown
  ├── validate distance
  ├── validate target
  ├── validate tool
  ├── calculate affected voxels
  ├── remove voxels
  ├── award cash
  └── replicate result
```

The server should own the authoritative voxel state.

---

# 18. Recommended Remote Event

Example:

```text
ReplicatedStorage
└── Remotes
    └── MineRequest
```

Client:

```lua
MineRequest:FireServer(
    hitPosition,
    hitNormal
)
```

The server should NOT blindly trust the supplied position.

It should verify that the position is reasonable relative to:

```lua
player.Character
```

and the target.

---

# 19. Mining Validation

Create:

```text
MiningValidator
```

Responsibilities:

```text
Validate:
- player alive
- tool equipped
- attack cooldown
- maximum range
- target belongs to voxel world
- target is a valid chunk
- hit position is plausible
- player has permission to mine
```

Example:

```lua
if distance > playerMineDistance then
    return false
end
```

Then:

```lua
if not voxelWorld:IsValidPosition(hitPosition) then
    return false
end
```

---

# 20. Mining Service

All mining should eventually pass through:

```lua
MiningService:Mine(...)
```

Recommended API:

```lua
MiningService:Mine(
    source,
    hitPosition,
    hitNormal,
    miningStats
)
```

Example:

```lua
MiningService:Mine(
    player,
    hitPosition,
    hitNormal,
    {
        Damage = 3,
        Range = 20,
        Pattern = "Player"
    }
)
```

Drone:

```lua
MiningService:Mine(
    drone,
    targetPosition,
    targetNormal,
    {
        Damage = droneDamage,
        Range = droneRange,
        Pattern = "Drone"
    }
)
```

Turret:

```lua
MiningService:Mine(
    turret,
    targetPosition,
    targetNormal,
    {
        Damage = turretDamage,
        Range = turretRange,
        Pattern = "Turret"
    }
)
```

This is one of the most important design decisions.

---

# 21. Drones

The Dismantle GDD describes drones as flying around the player or designated area and automatically carving. Their upgrades can affect speed, number, or range.

Recommended architecture:

```text
DroneService
│
├── DroneSpawner
├── DroneController
├── DroneTargetSelector
├── DroneMovement
├── DroneMining
└── DroneUpgradeStats
```

Drone loop:

```text
Find target
     ↓
Move toward target
     ↓
Reach mining position
     ↓
Mine
     ↓
Wait for rate cooldown
     ↓
Find next target
```

---

# 22. Drone Target Selection

Do not let each drone randomly select a voxel.

Use:

```lua
TargetSelector:GetBestTarget(drone)
```

Possible scoring:

```text
Target Score =
    Distance Score
  + Material Value
  + Visibility
  + Accessibility
  + Priority
```

For example:

```text
Nearby voxel      +10
High-value voxel  +20
Blocked voxel      -20
Already targeted   -50
```

This creates predictable automation.

---

# 23. Drone Mining

The drone should NOT implement its own destruction logic.

Instead:

```text
Drone
 ↓
Target
 ↓
MiningService
 ↓
VoxelWorld
```

This means player, drone and turret all remove material through the same system.

---

# 24. Turrets

The GDD describes turrets as placed devices that continuously carve around themselves, with potential upgrades to speed, range, and placement count.

Recommended structure:

```text
TurretService
│
├── TurretSpawner
├── TurretController
├── TurretTargetSelector
├── TurretAim
├── TurretMining
└── TurretUpgradeStats
```

Turret loop:

```text
Find target
    ↓
Aim
    ↓
Fire visual beam
    ↓
MiningService
    ↓
Cooldown
    ↓
Repeat
```

---

# 25. Visual Beam vs Actual Mining

Do not make the laser beam itself responsible for destruction.

Bad:

```text
Beam touches block
↓
Destroy block
```

Better:

```text
Turret chooses target
       ↓
MiningService validates target
       ↓
Voxel removed
       ↓
Beam VFX plays
```

The visual effect is therefore separate from gameplay logic.

This prevents VFX and gameplay from becoming tightly coupled.

---

# 26. Geometry Update

Once a voxel is removed:

```text
VoxelGrid
   ↓
Voxel removed
   ↓
Chunk marked dirty
   ↓
Geometry rebuild
```

Use:

```lua
chunk.Dirty = true
```

Then rebuild when appropriate.

Avoid rebuilding geometry several times during the same frame.

For example:

```text
Hit 1
Hit 2
Hit 3
Hit 4

instead of:

Rebuild
Rebuild
Rebuild
Rebuild
```

batch them:

```text
Hit 1
Hit 2
Hit 3
Hit 4
   ↓
ONE rebuild
```

---

# 27. Neighboring Chunks

If a voxel lies on a chunk boundary:

```text
Chunk A | Chunk B
        ↑
     boundary
```

removing a voxel from Chunk A may change the visible surface shared with Chunk B.

Therefore:

```lua
ChunkManager:MarkDirty(chunk)
```

and possibly:

```lua
ChunkManager:MarkDirty(neighborChunk)
```

when a boundary voxel changes.

---

# 28. Remeshing Options

There are several possible approaches.

## Option A — Individual Parts

Simplest.

```text
1 voxel = 1 Part
```

Good for:

- prototype
- small worlds
- debugging

Bad for:

- huge kaiju
- many players
- many voxels

---

## Option B — Part-based voxel chunks

Store voxels internally but create grouped Parts.

Better performance and easier to implement than a sophisticated mesh system.

---

## Option C — Greedy meshing

Combine adjacent voxel faces.

Example:

```text
Before:

████
████
████
████

After:

████████████████
```

This can dramatically reduce geometry.

---

## Option D — Custom voxel destruction module

A Roblox voxel destruction framework can handle parts of this problem.

For example, VoxBreaker is an open-source Roblox voxel destruction module, while Shatterbox is a newer Creator Store voxel-destruction system. These are useful references or potential prototype dependencies, but they should not be assumed to match Flatten The Mountain's implementation. 

---

# 29. Recommended Approach for Dismantle

For the first prototype:

```text
Internal voxel grid
+
chunk system
+
simple generated geometry
```

Do NOT immediately build an extremely sophisticated custom mesher.

First prove:

```text
Hit
↓
Correct voxel identified
↓
Voxel disappears
↓
Progress changes
↓
Cash awarded
```

Then optimize.

---

# 30. Dismantling Progress

The GDD requires a shared team dismantling percentage.

Maintain:

```lua
TotalVoxels
RemainingVoxels
```

Then:

```lua
local removed =
    TotalVoxels - RemainingVoxels

local progress =
    removed / TotalVoxels
```

Example:

```text
Total = 1,000,000

Remaining = 750,000

Removed = 250,000

Progress = 25%
```

Display:

```text
KAIJU DISMANTLED
██████░░░░░░░░░░
25%
```

---

# 31. Do Not Count Visual Parts

Do not calculate progress from:

```lua
#workspace.Kaiju:GetChildren()
```

because visual geometry can change independently from gameplay data.

Instead, the voxel world owns the authoritative count.

```text
VoxelWorld
 ├── TotalVoxelCount
 └── RemainingVoxelCount
```

---

# 32. Cash / Rewards

Each destroyed voxel can contain reward information.

Example:

```lua
{
    Material = "Flesh",
    Reward = 1
}
```

Special material:

```lua
{
    Material = "RareFlesh",
    Reward = 10
}
```

Then:

```text
Voxel removed
    ↓
RewardService
    ↓
CashService
```

The mining system should not directly manipulate leaderstats.

Instead:

```lua
RewardService:GrantMiningReward(player, voxel)
```

---

# 33. Eggs

The Dismantle GDD says eggs are buried inside the kaiju and are exposed as surrounding material is removed. Their contents can include money, items, baby kaiju, or aliens.

Do NOT make eggs part of the visual voxel geometry.

Instead:

```text
EggService
   │
   ├── EggPosition
   ├── EggState
   ├── EggContents
   └── EggExposure
```

Example:

```lua
Egg = {
    Position = Vector3,
    Radius = 2,
    State = "Buried",
    RewardType = "Random"
}
```

The egg becomes exposed when surrounding voxels are removed.

---

# 34. Egg Exposure

Possible system:

```text
Voxel removed
      ↓
Check nearby egg positions
      ↓
Is egg sufficiently exposed?
      ↓
YES
      ↓
Reveal Egg
```

Avoid checking every egg after every hit.

Use spatial partitioning:

```text
Egg → Chunk
```

Then only check eggs associated with affected chunks.

---

# 35. Gas System

The GDD says gas can be released from inside the kaiju and masks protect against it.

This should be independent from voxel destruction.

Possible event:

```lua
GasService:Release(position, radius)
```

The mining system can trigger:

```lua
GasService:CheckExposure(position)
```

but should not own mask logic.

---

# 36. Enemy System

The GDD describes:

- Baby Kaiju
- Parasitic mini-kaiju
- Alien
- UFO

and weapons including:

- cutter/chainsaw
- standard gun
- ray gun
- bazooka.

Keep combat separate:

```text
EnemyService
WeaponService
HealthService
ProjectileService
```

The cutter can be capable of damaging enemies, but that does not mean:

```text
MiningService = CombatService
```

Instead:

```text
Cutter
 ├── Mining attack
 └── Combat attack
```

---

# 37. Why This Separation Matters

A single tool can have multiple gameplay actions.

For example:

```text
Player Cutter
      │
      ├── Hit Kaiju
      │       ↓
      │   MiningService
      │
      └── Hit Enemy
              ↓
          CombatService
```

This keeps the architecture clean.

---

# 38. Recommended Folder Architecture

```text
ReplicatedStorage
│
├── Shared
│   ├── Config
│   │   ├── MiningConfig
│   │   ├── DroneConfig
│   │   ├── TurretConfig
│   │   ├── EggConfig
│   │   └── WeaponConfig
│   │
│   ├── Types
│   └── Utilities
│
├── Remotes
│   ├── MineRequest
│   ├── MiningResult
│   ├── DroneUpdate
│   ├── TurretUpdate
│   └── ProgressUpdate
│
└── Assets
    ├── VFX
    ├── SFX
    ├── Drones
    ├── Turrets
    ├── Eggs
    └── Weapons
```

Server:

```text
ServerScriptService
│
├── Services
│   ├── VoxelWorld
│   ├── ChunkService
│   ├── MiningService
│   ├── MiningValidator
│   ├── RewardService
│   ├── ProgressService
│   ├── DroneService
│   ├── TurretService
│   ├── EggService
│   ├── EnemyService
│   ├── GasService
│   └── UpgradeService
│
└── ServerBootstrap
```

Client:

```text
StarterPlayer
└── StarterPlayerScripts
    ├── MiningController
    ├── ToolController
    ├── VFXController
    ├── SFXController
    ├── DroneVFXController
    ├── TurretVFXController
    └── UIController
```

---

# 39. Core Dependency Graph

```text
                         VoxelWorld
                             │
                 ┌───────────┴───────────┐
                 │                       │
            MiningService           ProgressService
                 │                       │
        ┌────────┼────────┐              │
        │        │        │              │
      Player   Drone    Turret            │
        │        │        │              │
        └────────┼────────┘              │
                 │                       │
                 └───────────┬───────────┘
                             │
                       RewardService
                             │
                        CashService
```

Other systems listen to voxel events:

```text
VoxelWorld
    │
    ├── EggService
    ├── GasService
    ├── Audio/VFX
    └── ProgressService
```

---

# 40. Event-Driven Design

After a successful mining operation:

```lua
VoxelRemoved
```

can be emitted.

Payload:

```lua
{
    Position = position,
    VoxelCount = count,
    Source = source,
    Material = material
}
```

Listeners:

```text
RewardService
ProgressService
EggService
VFXService
AudioService
AnalyticsService
```

This prevents MiningService from becoming a giant script containing everything.

---

# 41. Complete Mining Flow

The intended final flow is:

```text
PLAYER PRESSES ATTACK
        ↓
MiningController
        ↓
Raycast
        ↓
MineRequest
        ↓
SERVER
        ↓
MiningValidator
        ↓
Find VoxelWorld
        ↓
World → Local
        ↓
Local → Voxel Coordinate
        ↓
MiningPattern
        ↓
Affected Voxels
        ↓
VoxelGrid.Remove()
        ↓
Mark Chunk Dirty
        ↓
Update Geometry
        ↓
Emit VoxelRemoved
        ↓
RewardService
        ↓
ProgressService
        ↓
EggService
        ↓
Replicate visual result
```

---

# 42. Example Pseudocode

```lua
function MiningService:Mine(source, hitPosition, hitNormal, stats)

    if not MiningValidator:CanMine(source, hitPosition, stats) then
        return false
    end

    local chunk =
        VoxelWorld:GetChunkAtWorldPosition(hitPosition)

    if not chunk then
        return false
    end

    local localPosition =
        chunk.CFrame:PointToObjectSpace(hitPosition)

    local voxelCoordinate =
        VoxelGrid:WorldToVoxel(localPosition)

    local affectedVoxels =
        MiningPattern:GetAffectedVoxels(
            voxelCoordinate,
            hitNormal,
            stats.Damage,
            stats.Pattern
        )

    local removed = {}

    for _, coordinate in affectedVoxels do

        local voxel =
            chunk.Voxels:Get(coordinate)

        if voxel and voxel.Occupied then

            local destroyed =
                VoxelGrid:Damage(voxel, stats.Damage)

            if destroyed then
                table.insert(removed, voxel)
            end
        end
    end

    if #removed == 0 then
        return false
    end

    ChunkService:MarkDirty(chunk)

    RewardService:ProcessMiningReward(
        source,
        removed
    )

    ProgressService:OnVoxelsRemoved(
        #removed
    )

    EggService:CheckExposure(
        removed
    )

    return true
end
```

---

# 43. Mining Stats

Create a standardized structure:

```lua
local MiningStats = {
    Damage = 1,
    Range = 20,
    Cooldown = 0.25,
    Pattern = "Single",
    MaxTargets = 1
}
```

Drone:

```lua
local DroneStats = {
    Damage = 1,
    Range = 30,
    Cooldown = 0.5,
    Pattern = "Single",
    Speed = 16
}
```

Turret:

```lua
local TurretStats = {
    Damage = 2,
    Range = 50,
    Cooldown = 0.4,
    Pattern = "Single"
}
```

---

# 44. Upgrade System

The GDD says income is used to upgrade drones, turrets, tools, masks and weapons.

Create:

```text
UpgradeService
```

rather than having each system manage its own purchases.

Example:

```lua
UpgradeService:Purchase(
    player,
    "DroneDamage",
    2
)
```

Then:

```text
UpgradeService
       ↓
PlayerData
       ↓
MiningStats
       ↓
DroneService
```

---

# 45. Performance Rules

The system should follow these rules.

### Never:

```text
Rebuild entire kaiju after every hit.
```

### Never:

```text
Create a new Part for every mining hit.
```

### Never:

```text
Let every drone scan every voxel.
```

### Never:

```text
Let every client own the authoritative voxel state.
```

### Prefer:

```text
Chunking
Caching
Spatial lookup
Dirty chunks
Batch updates
Server authority
Shared MiningService
```

---

# 46. Prototype Milestones

## Prototype 1 — Single Voxel

Goal:

```text
Click voxel
↓
voxel disappears
```

Nothing else.

---

## Prototype 2 — Localized Mining

Implement:

```text
Raycast
↓
Hit Position
↓
Voxel Coordinate
↓
Remove voxel
```

Verify that hitting different locations removes the correct voxel.

---

## Prototype 3 — Damage

Implement:

```text
Damage 1
Damage 3
Damage 5
```

and verify the affected area.

---

## Prototype 4 — Chunking

Create:

```text
multiple chunks
```

and ensure only affected chunks update.

---

## Prototype 5 — Progress

Add:

```text
Total Voxels
Remaining Voxels
Dismantled %
```

---

## Prototype 6 — Cash

Add:

```text
Voxel
↓
Reward
↓
Cash
```

---

## Prototype 7 — Drone

Drone should use:

```text
same MiningService
```

---

## Prototype 8 — Turret

Turret should use:

```text
same MiningService
```

---

## Prototype 9 — Eggs

Add:

```text
hidden egg
↓
voxels removed
↓
egg exposed
```

---

## Prototype 10 — Enemies / Gas

Only after the mining loop feels correct.

---

# 47. Acceptance Tests

The coding agent should not consider the system finished until these tests pass.

### Test 1

Player hits one voxel.

Expected:

```text
Exactly the intended voxel is removed.
```

### Test 2

Player hits different areas.

Expected:

```text
Different areas are removed according to hit position.
```

### Test 3

Increase Damage.

Expected:

```text
More material is removed per attack.
```

### Test 4

Hit chunk boundary.

Expected:

```text
Neighboring geometry remains correct.
```

### Test 5

Two players mine simultaneously.

Expected:

```text
No duplicated voxel rewards.
No corrupted voxel state.
```

### Test 6

Drone mines.

Expected:

```text
Drone removes material through MiningService.
```

### Test 7

Turret mines.

Expected:

```text
Turret removes material through MiningService.
```

### Test 8

Player + drone + turret attack same area.

Expected:

```text
No double destruction.
No duplicate rewards.
```

### Test 9

Egg is surrounded by material.

Expected:

```text
Egg remains hidden.
```

Remove surrounding voxels.

Expected:

```text
Egg becomes exposed.
```

### Test 10

Reach 100%.

Expected:

```text
Kaiju is fully dismantled.
Progress = 100%.
Completion event fires exactly once.
```

---

# 48. What NOT To Claim About Flatten The Mountain

Do not tell the developer:

> "Flatten The Mountain definitely uses X."

unless we have source-code evidence.

Instead say:

> "The observed behavior is consistent with a voxel/chunk-based mining architecture."

Known:

```text
Block/voxel-style mining
Multiple automated mining systems
Progressive destruction
Damage affecting mining output
```

Not confirmed:

```text
Exact voxel size
Exact chunk size
Exact remeshing algorithm
Exact data structure
Exact server architecture
Exact mining pattern
Exact raycast implementation
Exact source code
```

---

# 49. Recommended Dismantle Architecture

The final architecture should look like:

```text
                         ┌─────────────────────┐
                         │      GAME LOOP      │
                         └──────────┬──────────┘
                                    │
                         ┌──────────▼──────────┐
                         │     VoxelWorld      │
                         │                     │
                         │ Chunks              │
                         │ VoxelGrid            │
                         │ Materials            │
                         │ Geometry             │
                         └──────────┬──────────┘
                                    │
                         ┌──────────▼──────────┐
                         │    MiningService     │
                         └──────────┬──────────┘
                                    │
                 ┌──────────────────┼──────────────────┐
                 │                  │                  │
          ┌──────▼──────┐    ┌──────▼──────┐    ┌──────▼──────┐
          │   Player    │    │    Drone    │    │   Turret    │
          │   Mining    │    │   Mining    │    │   Mining    │
          └─────────────┘    └─────────────┘    └─────────────┘
                                    │
                                    ▼
                         ┌────────────────────┐
                         │   Voxel Removed    │
                         │       Event        │
                         └─────────┬──────────┘
                                   │
            ┌──────────────────────┼─────────────────────┐
            │                      │                     │
      ┌─────▼─────┐         ┌──────▼──────┐       ┌──────▼─────┐
      │   Cash    │         │   Progress  │       │    Eggs    │
      │  Service  │         │   Service   │       │   Service  │
      └───────────┘         └─────────────┘       └────────────┘
                                   │
                                   ▼
                           ┌──────────────┐
                           │  Completion  │
                           │    Event     │
                           └──────────────┘
```

---

# 50. MASTER IMPLEMENTATION PROMPT

Use the following prompt with Claude Code / Antigravity / another Roblox coding agent.

---

## Prompt

You are a senior Roblox/Luau gameplay engineer.

We are developing a Roblox game called **Dismantle**, inspired by the gameplay loop of **Flatten The Mountain**.

The goal is NOT to copy private source code from Flatten The Mountain.

Instead, implement a clean, original voxel-based destruction architecture that reproduces the observable gameplay behavior:

> Player attacks a large destructible structure → the hit position determines the local destruction area → voxels/material disappear → rewards are granted → total dismantling progress increases → drones and turrets can perform the same mining operation automatically.

The system must be modular, server-authoritative, performant, and easy to expand.

---

## PRIMARY REQUIREMENT

Build a reusable voxel destruction/mining framework.

The most important pipeline is:

```text
Raycast
→ Hit Position
→ Identify Voxel World
→ Identify Chunk
→ World Position → Local Position
→ Local Position → Voxel Coordinate
→ Determine Mining Pattern
→ Determine Affected Voxels
→ Damage/Remove Voxels
→ Mark Chunk Dirty
→ Update Geometry
→ Reward Player
→ Update Dismantling Progress
→ Trigger VoxelRemoved Event
```

Do not implement the system as:

```text
click → destroy Part
```

The game must have an internal voxel representation independent from its rendered geometry.

---

# ARCHITECTURE REQUIREMENTS

Create these major systems:

```text
VoxelWorld
ChunkService
VoxelGrid
VoxelGenerator
VoxelRemesher
MiningService
MiningValidator
MiningPattern
RewardService
ProgressService
DroneService
TurretService
EggService
UpgradeService
```

---

# VOXEL WORLD

Implement:

```lua
VoxelWorld:GetVoxelAtWorldPosition(position)
VoxelWorld:GetChunkAtWorldPosition(position)
VoxelWorld:RemoveVoxel(position)
VoxelWorld:DamageVoxel(position, damage)
VoxelWorld:GetRemainingVoxelCount()
VoxelWorld:GetTotalVoxelCount()
```

The world must be divided into chunks.

Do not rebuild the entire kaiju when a single voxel changes.

Only dirty/affected chunks should be updated.

---

# CHUNKS

Each chunk must contain:

```text
Voxel data
Chunk coordinates
World position
Size
Dirty state
Rendered geometry
```

Implement neighbor detection so that modifying a voxel on a chunk boundary can update neighboring geometry when required.

Chunk size must be configurable.

Voxel size must be configurable.

Do not hardcode these values throughout the project.

---

# VOXEL DATA

Each voxel should support at minimum:

```lua
{
    Occupied = true,
    Material = MaterialId,
    Health = 1,
    MaxHealth = 1,
    Reward = 1
}
```

Support both:

```text
one-hit voxel
```

and:

```text
multi-hit durability
```

through configuration.

---

# WORLD POSITION CONVERSION

Implement:

```text
World Position
↓
Chunk Local Position
↓
Voxel Coordinate
```

Use Roblox CFrame conversion rather than assuming the chunk is always at the world origin.

Conceptually:

```lua
local localPosition =
    chunk.CFrame:PointToObjectSpace(worldPosition)
```

Then calculate the voxel coordinate from the configurable voxel size.

---

# PLAYER MINING

The player should:

1. Aim at the kaiju.
2. Raycast.
3. Obtain hit position and hit normal.
4. Send a mining request to the server.
5. Server validates the request.
6. Server calculates the actual voxel(s) affected.
7. Server removes/damages the voxel(s).
8. Server awards the appropriate reward.
9. Server updates shared dismantling progress.
10. Clients receive the visual update.

Do not trust client-provided damage, reward, voxel coordinates, or cooldown.

---

# SERVER VALIDATION

Implement:

```text
MiningValidator
```

Validate:

```text
Player is alive
Tool is equipped
Attack cooldown
Maximum mining range
Valid target
Valid voxel world
Valid hit position
Valid mining source
```

The server owns the authoritative voxel state.

---

# MINING PATTERNS

Create:

```text
MiningPattern
```

with configurable patterns.

At minimum implement:

```text
Single
Horizontal
Vertical
Cross
Area
```

The pattern should be able to receive:

```text
center voxel
hit normal
damage
pattern configuration
```

and return affected voxel coordinates.

Example:

```lua
local affected =
    MiningPattern:GetAffectedVoxels(
        center,
        normal,
        damage,
        "Player"
    )
```

Do not hardcode "Damage 3 = these exact three voxels" inside the player weapon.

---

# DAMAGE

Damage must be configurable.

For example:

```text
Damage 1 → 1 voxel
Damage 2 → 3 voxels
Damage 3 → 5 voxels
```

This is only an example.

Make the actual progression configurable in:

```text
MiningConfig
```

---

# PLAYER / DRONE / TURRET SHARED SYSTEM

This is extremely important.

Player:

```lua
MiningService:Mine(...)
```

Drone:

```lua
MiningService:Mine(...)
```

Turret:

```lua
MiningService:Mine(...)
```

All three must use the same underlying destruction logic.

Do not create:

```text
PlayerMiningSystem
DroneMiningSystem
TurretMiningSystem
```

with three independent voxel implementations.

There should be ONE authoritative:

```text
MiningService
```

---

# DRONES

Implement a DroneService.

Drone responsibilities:

```text
Find target
Move to target
Orient toward target
Attack on cooldown
Call MiningService
Find next target
```

Drone stats:

```text
Damage
Rate
Speed
Range
```

All values must be configurable.

Drone target selection should avoid:

```text
destroyed voxels
unreachable targets
already-targeted voxels
```

Do not scan the entire voxel world every frame.

Use spatial/chunk lookup.

---

# TURRETS

Implement TurretService.

Turret responsibilities:

```text
Find target
Aim
Play firing VFX
Call MiningService
Wait cooldown
Repeat
```

Turret stats:

```text
Damage
Rate
Range
```

Again, turret destruction must go through MiningService.

The beam is visual feedback.

The beam itself must not be responsible for authoritative destruction.

---

# PROGRESS

Implement:

```lua
TotalVoxels
RemainingVoxels
RemovedVoxels
Progress
```

Formula:

```lua
Progress =
    RemovedVoxels / TotalVoxels
```

Clamp:

```text
0 → 100%
```

At 100%:

```text
Fire DismantleCompleted
```

exactly once.

Progress is team/shared progress.

---

# REWARDS

When voxels are successfully removed:

```text
VoxelRemoved
↓
RewardService
↓
CashService
```

Do not award rewards on the client.

Prevent double rewards when multiple players or machines attack the same voxel.

---

# EGGS

Implement EggService separately.

Eggs are hidden inside the kaiju.

They should not simply be normal visible voxels.

Each egg should have:

```text
Position
State
Reward Type
Exposure Threshold
```

When nearby material is removed:

```text
Check affected chunk
↓
Find nearby eggs
↓
Determine exposure
↓
Reveal egg
```

Possible outcomes:

```text
Money
Item
Baby Kaiju
Alien
```

Use configurable weighted random selection.

---

# EVENTS

Implement an event-driven system.

At minimum:

```text
VoxelRemoved
ChunkChanged
MiningPerformed
EggExposed
EggOpened
DismantleProgressChanged
DismantleCompleted
```

Other systems should listen to these events instead of creating hard dependencies.

---

# PERFORMANCE

Follow these rules:

1. Never rebuild the entire kaiju for one voxel.
2. Never scan every voxel every frame.
3. Never let every drone scan the entire world every frame.
4. Use chunks.
5. Use dirty flags.
6. Batch geometry updates where possible.
7. Cache spatial lookups.
8. Keep authoritative voxel data on the server.
9. Keep client VFX separate from gameplay state.
10. Profile before optimizing further.

---

# FOLDER STRUCTURE

Create:

```text
ReplicatedStorage
├── Shared
│   ├── Config
│   ├── Types
│   └── Utilities
├── Remotes
└── Assets

ServerScriptService
├── Services
│   ├── VoxelWorld
│   ├── ChunkService
│   ├── VoxelGrid
│   ├── VoxelGenerator
│   ├── VoxelRemesher
│   ├── MiningService
│   ├── MiningValidator
│   ├── MiningPattern
│   ├── RewardService
│   ├── ProgressService
│   ├── DroneService
│   ├── TurretService
│   ├── EggService
│   └── UpgradeService
└── ServerBootstrap

StarterPlayer
└── StarterPlayerScripts
    ├── MiningController
    ├── VFXController
    ├── SFXController
    └── UIController
```

Adapt the exact folder implementation to the existing project rather than destroying existing architecture.

---

# DEVELOPMENT PROCESS

Do NOT implement everything at once.

Work in stages.

## Stage 1

Inspect the existing Roblox project.

Identify:

```text
Existing scripts
Existing modules
Existing kaiju model
Existing tools
Existing remotes
Existing UI
Existing dependencies
```

Do not delete or rewrite unrelated systems.

---

## Stage 2

Build a tiny test voxel world.

It should look approximately:

```text
10 × 10 × 10
```

and allow:

```text
click voxel
→ voxel disappears
```

---

## Stage 3

Implement:

```text
Raycast
→ local coordinate
→ voxel coordinate
```

Verify that the correct voxel disappears based on the exact hit location.

---

## Stage 4

Add mining patterns.

---

## Stage 5

Add chunks and dirty updates.

---

## Stage 6

Add server validation.

---

## Stage 7

Add cash and dismantling progress.

---

## Stage 8

Add DroneService.

---

## Stage 9

Add TurretService.

---

## Stage 10

Add Eggs.

---

## Stage 11

Add enemies, gas, weapons, and other secondary systems.

Do not begin with secondary systems.

The mining loop is the foundation.

---

# DEBUG MODE

Create a development-only debug mode.

When enabled, show:

```text
Chunk boundaries
Voxel grid
Current hit voxel
Affected voxels
Mining range
Drone target
Turret target
Dismantling %
```

For example:

```text
Hit Voxel:
X: 12
Y: 8
Z: 24

Chunk:
3, 1, 4

Affected:
12,8,24
13,8,24
11,8,24
```

This will make reverse-engineering and debugging significantly easier.

---

# LOGGING

Add optional logs:

```text
[Mining]
Player hit voxel 12,8,24

[Mining]
Damage = 3

[Mining]
Affected = 3 voxels

[Voxel]
Chunk 3,1,4 marked dirty

[Reward]
Player earned $3

[Progress]
Dismantled = 12.5%
```

Disable verbose logging in production.

---

# ACCEPTANCE CRITERIA

The implementation is successful only if:

### A. Position accuracy

Hitting different positions produces destruction at the correct locations.

### B. Damage

Increasing damage visibly increases the amount of material removed.

### C. Chunking

Only affected chunks update.

### D. Multiplayer

Two or more players can mine simultaneously without corrupting voxel state.

### E. Shared mining

Player, drone and turret all use MiningService.

### F. Rewards

Every successfully removed voxel is rewarded exactly once.

### G. Progress

Team progress correctly reaches 100%.

### H. Eggs

Eggs remain hidden until sufficient surrounding material is removed.

### I. Security

Client cannot arbitrarily destroy distant voxels or award itself cash.

### J. Performance

The system remains usable with a large destructible kaiju and multiple automated miners.

---

# IMPORTANT ENGINEERING RULE

Do not prematurely optimize the system with a complicated custom voxel engine.

First prove:

```text
Correct hit
→ Correct voxel
→ Correct destruction
→ Correct reward
→ Correct progress
```

Then benchmark.

Only introduce:

```text
greedy meshing
object pooling
parallel processing
advanced spatial partitioning
custom mesh generation
```

when profiling shows they are necessary.

---

# FINAL EXPECTED RESULT

The final system should make this possible:

```text
             PLAYER
                │
             Attack
                │
             Raycast
                │
                ▼
          MiningService
                │
       ┌────────┼────────┐
       ▼        ▼        ▼
     Voxel    Reward   Progress
    Removal
       │
       ▼
   Chunk Update
       │
       ▼
   Visible Hole
```

Then:

```text
              AUTOMATION
                  │
          ┌───────┴────────┐
          ▼                ▼
        Drone            Turret
          │                │
          └───────┬────────┘
                  ▼
            MiningService
                  │
                  ▼
             VoxelWorld
```

The architecture must make the player, drone and turret feel like different gameplay systems while still sharing the same authoritative destruction engine.

---

# FINAL DESIGN PRINCIPLE

The most important abstraction is:

> **Mining is an operation, not a weapon.**

The cutter is one source of mining.

The drone is another source.

The turret is another source.

All of them ultimately perform:

```text
Mine(
    source,
    target,
    damage,
    pattern
)
```

The voxel world does not care whether the request came from:

```text
Player
Drone
Turret
```

It only validates the request and applies the appropriate voxel change.

That architecture will make Dismantle much easier to expand with:

```text
better cutters
larger drones
stronger turrets
special tools
rare materials
eggs
enemies
gas
power-ups
new kaiju
new mining patterns
```

without rewriting the core destruction system.