# Drone & Turret Laser Shooting — Mechanics Correction

We are now going to work on the **laser shooting mechanics for both the Drone and Turret**.

## Current Behavior

Analyze the existing Drone laser implementation first.

Currently, the system works approximately like this:

1. The Drone locks its laser onto a voxel.
2. The laser damages that voxel.
3. Once that voxel is destroyed, the laser automatically redirects to another voxel.
4. The Drone then continues attacking the newly selected voxel.

The **initial voxel-locking logic is correct**, but the **automatic target redirection is NOT correct**.

We need to change this behavior.

---

# 1. Drone Laser — Required Behavior

Before making any changes, **analyze the existing Drone laser code and understand how targeting, laser positioning, damage, voxel detection, and movement currently work.**

Do not immediately rewrite the system.

First identify:

* Where the Drone selects/locks onto a voxel.
* How the laser origin is calculated.
* How the laser direction/endpoint is calculated.
* How the laser follows the target.
* How voxel damage is applied.
* What happens when the targeted voxel is destroyed.
* What code currently causes the laser to redirect to another voxel.
* Whether any existing systems already support the behavior we need.

Then propose the smallest clean change required.

---

## Correct Drone Mechanic

The Drone should still **lock onto a voxel**, but after locking, the laser should **NOT automatically search for or redirect to another voxel**.

### Important rule:

> **The laser target is fixed once the Drone locks onto it.**

If the targeted voxel is destroyed:

* Do **NOT** select another voxel.
* Do **NOT** redirect the laser.
* Do **NOT** retarget automatically.
* Do **NOT** perform another target search as part of the same laser attack.

The laser should remain committed to its original target.

---

# 2. Laser Movement Behavior

The important part of this mechanic is that the **laser itself should remain straight and connected to the Drone**.

The Drone is allowed to move.

For example:

```text
Drone
   |
   |
   |
   | LASER
   |
   X  ← Locked voxel
```

If the Drone moves:

```text
        Drone
          |
          |
          |
          |
          X  ← SAME locked voxel
```

The laser should move **with the Drone**, while still remaining connected to the **same locked voxel**.

### In other words:

* The Drone moves.
* The laser follows the Drone's movement.
* The laser remains connected to the Drone.
* The laser does NOT independently redirect to another voxel.
* The original locked voxel remains the target.
* The laser should continue damaging that locked voxel while the Drone is positioned appropriately over/at that voxel.

The laser should behave like a **physical beam attached to the Drone**, not like an AI targeting system that continuously searches for new voxels.

---

# 3. Voxel Damage Behavior

The Drone should only damage the voxel it has locked onto.

When the Drone reaches/positions itself over the locked voxel:

```text
       DRONE
         |
         |
         |
         ↓
      [VOXEL]
```

The laser damages that voxel.

Once that voxel is destroyed:

```text
       DRONE
         |
         |
         |
         ↓

      destroyed
```

The current laser attack should end/stop.

### It must NOT do this:

```text
Voxel A destroyed
       ↓
Find Voxel B
       ↓
Redirect laser
       ↓
Damage Voxel B
       ↓
Find Voxel C
       ↓
Redirect laser
```

That automatic chain-targeting behavior must be removed.

---

# 4. Drone Movement vs. Laser Target

The target and the Drone's position are separate concepts.

The Drone can move while the target remains fixed.

Think of it as:

```text
TARGET = Locked Voxel
DRONE = Moving object
LASER = Beam connecting Drone → Locked Voxel
```

The Drone's movement should update the **laser origin**, but should NOT change the target.

So:

```text
Laser Origin = Drone's current position
Laser Target = Originally locked voxel
```

The target should only change when a **new attack/target-selection cycle explicitly begins**, not simply because the previous voxel was destroyed.

---

# 5. Turret Laser

After the Drone implementation is corrected and verified, apply the **same targeting principle to the Turret**.

The Turret should follow the same fundamental rules:

### Turret:

* Lock onto one voxel.
* Keep that voxel as the fixed target.
* Laser does not automatically redirect.
* Laser does not automatically search for another voxel.
* If the target voxel is destroyed, the current attack ends/stops.
* A new target should only be selected when a new attack/target-selection cycle begins.

The main difference is that the Turret itself may not move like the Drone.

---

# 6. Important: Do Not Break Existing Systems

Before modifying anything:

1. Analyze the existing implementation.
2. Trace the complete Drone laser flow.
3. Identify the exact source of automatic retargeting.
4. Determine whether Drone and Turret share laser/targeting modules.
5. Check whether changing shared code could unintentionally affect other weapons or abilities.
6. Reuse existing systems where possible.
7. Avoid creating duplicate targeting/laser systems.

Do not rewrite working systems unnecessarily.

---

# 7. Implementation Requirements

### Phase 1 — Analysis

First analyze the existing code and report:

* Relevant scripts/modules.
* Current targeting flow.
* Current laser flow.
* Current voxel damage flow.
* Current Drone movement interaction.
* Current Turret implementation.
* Exact location where automatic retargeting happens.
* Recommended minimal architectural change.

### Phase 2 — Plan

Before implementation, create a concise implementation plan.

The plan should clearly explain:

```text
Drone
  ↓
Select voxel
  ↓
Lock voxel
  ↓
Create laser
  ↓
Drone moves
  ↓
Laser follows Drone
  ↓
Laser remains locked to SAME voxel
  ↓
Voxel takes damage
  ↓
Voxel destroyed
  ↓
Laser attack ends
  ↓
NO automatic retarget
```

And:

```text
Turret
  ↓
Select voxel
  ↓
Lock voxel
  ↓
Create laser
  ↓
Laser remains locked to SAME voxel
  ↓
Voxel takes damage
  ↓
Voxel destroyed
  ↓
Laser attack ends
  ↓
NO automatic retarget
```

### Phase 3 — Implementation

Only after the analysis and plan are complete, implement the change.

Keep the implementation:

* Modular.
* Easy to maintain.
* Compatible with the existing architecture.
* Server-authoritative for damage/target state where applicable.
* Free of unnecessary duplicate logic.

---

# 8. Verification / Testing

After implementation, test at minimum:

### Test 1 — Normal attack

* Drone locks onto Voxel A.
* Laser attacks Voxel A.
* Voxel A receives damage.

### Test 2 — Drone movement

* Drone locks onto Voxel A.
* Move the Drone.
* Verify the laser follows the Drone.
* Verify the laser remains connected to Voxel A.
* Verify it does NOT switch to Voxel B.

### Test 3 — Target destruction

* Drone locks onto Voxel A.
* Destroy Voxel A.
* Verify the laser stops/attack ends.
* Verify the Drone does NOT automatically target Voxel B.

### Test 4 — Multiple voxels

Place multiple valid voxels around the Drone.

Verify:

```text
Lock Voxel A
    ↓
Voxel A destroyed
    ↓
NO Voxel B targeting
```

### Test 5 — Turret

Repeat the same tests for the Turret.

---

# Critical Requirement

**Do not interpret this mechanic as "find the nearest voxel every frame."**

That is NOT what we want.

The correct behavior is:

> **Select and lock one voxel. Keep that voxel as the target. The Drone can move, and the laser follows the Drone while remaining connected to that same locked voxel. When the locked voxel is destroyed, stop the current laser attack instead of automatically redirecting to another voxel.**

Apply the same targeting rule to the Turret.

**First analyze the existing implementation and explain the current behavior and the exact code responsible for automatic retargeting. Do not start modifying code until the analysis and implementation plan are clear.**
