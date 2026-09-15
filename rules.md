# Roblox Development Rules

## 1. Research Before Implementation

Before implementing any requested feature, mechanic, effect, system, or interaction:

- Analyze how similar systems are commonly built in the Roblox community.
- Study established Roblox development patterns, best practices, and commonly used approaches.
- Look at comparable games, mechanics, effects, and systems to understand how they achieve a polished result.
- Identify the important technical components required to recreate the desired behavior.
- Do not blindly copy an implementation. Understand the underlying logic and recreate the same type of experience appropriately for our game.

The goal is to produce a result that feels **native to a polished Roblox game**, not a quick prototype.

---

## 2. Planning Must Come Before Coding

**Do NOT immediately start implementing the requested feature.**

Before writing or modifying code:

1. Fully understand the requested mechanic/effect.
2. Research how similar Roblox systems are commonly implemented.
3. Break the feature into its individual systems and components.
4. Determine how those components should communicate with each other.
5. Identify edge cases and possible failure points.
6. Decide what should happen during every important state of the mechanic.
7. Create a complete implementation plan.
8. Review the plan for missing details or conflicts with the existing game.
9. Only after the plan is complete should implementation begin.

---

## 3. Create a Complete Mechanic Specification

Every significant mechanic should have a clear specification before implementation.

The specification should explain:

### Gameplay Behavior
- What the player does to activate the mechanic.
- What happens after activation.
- What the player sees and experiences.
- What happens when the mechanic succeeds.
- What happens when the mechanic fails.
- What happens when the mechanic is interrupted.

### Timing
Define important timing such as:

- Startup
- Active period
- Hit/detection window
- Recovery
- Cooldown
- Animation timing
- VFX timing
- SFX timing

Timing between **animation, VFX, hitboxes, sounds, and gameplay logic** should be intentionally synchronized.

### Player Interaction
Specify:

- Whether the player can move during the mechanic.
- Whether controls are blocked.
- Whether the mechanic follows the player.
- Whether it targets another character/object.
- Whether it can be interrupted.
- Whether it can be cancelled.
- What happens if the player dies, moves away, or loses the target.

### Multiplayer Behavior
Determine:

- Which logic runs on the server.
- Which logic runs on the client.
- What information must be replicated.
- How hit detection is validated.
- How to prevent clients from creating invalid gameplay results.
- How the mechanic behaves under latency.

---

## 4. Study Existing Game Architecture First

Before adding a new system:

- Inspect the existing project structure.
- Understand existing modules and systems.
- Identify reusable components.
- Check existing naming conventions.
- Check existing remote events/functions.
- Check existing animation, VFX, SFX, combat, and state systems.
- Reuse existing systems when appropriate instead of unnecessarily creating duplicates.

**Do not introduce a completely separate architecture when an existing system can support the feature cleanly.**

---

## 5. Do Not Use Quick or Temporary Implementations

Avoid implementations that are only intended to "make it work."

Do not:

- Hardcode unnecessary values everywhere.
- Duplicate large amounts of existing code.
- Create temporary systems without a migration plan.
- Use placeholder logic as the final implementation.
- Ignore edge cases.
- Hide problems instead of fixing their underlying cause.

The target is a **complete, maintainable, polished mechanic**, not merely a working prototype.

---

## 6. Match the Reference Behavior

If a reference video, game, animation, effect, or mechanic is provided:

- Analyze it carefully before implementation.
- Break down what happens frame-by-frame when necessary.
- Identify player input, movement, animation, VFX, SFX, hit detection, camera behavior, and timing.
- Recreate the **behavior and experience**, not merely the visual appearance.
- Pay particular attention to timing and transitions.

If something in the reference is ambiguous, determine the most reasonable implementation based on established Roblox development patterns rather than immediately guessing.

---

## 7. Polish Requirements

A feature should not be considered complete simply because the basic functionality works.

Before considering it finished, verify:

- Animations feel natural.
- VFX timing matches gameplay events.
- SFX occur at the correct moments.
- Hitboxes/detection match the intended visual action.
- Movement feels responsive.
- Transitions are smooth.
- Effects clean themselves up correctly.
- The mechanic works repeatedly without accumulating objects/connections.
- Multiplayer behavior is reliable.
- Performance is reasonable.
- Edge cases are handled.
- The feature fits the existing game's style and architecture.

---

## 8. Implementation Workflow

Use this workflow for significant features:

### Phase 1 — Understand
Understand exactly what needs to be created.

### Phase 2 — Research
Analyze similar Roblox mechanics and established community approaches.

### Phase 3 — Inspect
Inspect the existing game's architecture and identify reusable systems.

### Phase 4 — Plan
Create a complete technical and gameplay plan before coding.

### Phase 5 — Review
Check the plan for:

- Missing systems
- Incorrect assumptions
- Timing problems
- Multiplayer problems
- Performance concerns
- Edge cases
- Conflicts with existing systems

### Phase 6 — Implement
Only after the plan is complete, begin implementation.

### Phase 7 — Test
Test the mechanic under normal and abnormal conditions.

### Phase 8 — Polish
Improve timing, responsiveness, visuals, audio, transitions, and overall feel.

### Phase 9 — Final Review
Confirm that the finished mechanic matches the intended reference and follows the project's architecture.

---

## 9. Planning Output Requirement

Before implementing a major feature, provide a clear plan containing:

1. **Feature Overview**
2. **Reference Analysis**
3. **Research Findings**
4. **Existing Systems That Can Be Reused**
5. **Required New Systems**
6. **Gameplay Flow**
7. **Animation Flow**
8. **VFX Flow**
9. **SFX Flow**
10. **Hit Detection / Interaction Logic**
11. **Client/Server Responsibilities**
12. **State Management**
13. **Timing Specification**
14. **Edge Cases**
15. **Performance Considerations**
16. **Implementation Steps**
17. **Testing Checklist**
18. **Polish Checklist**

Do not begin implementation until this plan is sufficiently complete.

---

## 10. Quality Standard

Always aim for:

> **"If this mechanic were shipped in a polished Roblox game, would it feel intentional, responsive, reliable, and complete?"**

If the answer is no, continue improving it.

The objective is not simply to make the requested feature function.

The objective is to create a **complete, polished, production-ready Roblox mechanic** that follows proven Roblox development practices and integrates cleanly with the existing game.