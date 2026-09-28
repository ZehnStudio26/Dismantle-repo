# Dismantle — Chainsaw Cutting Plan

**Date:** 2026-09-28. **Asked by:** Shayan. **Place:** Kaiju (placeId 96604275292994).
**Goal:** replace laser cutting with a chainsaw that has everything the free mining pack
(`Workspace["FREE Mining System - Ungroup"]`, by skaterstudios) gives a pickaxe, but pointed at the
kaiju's blocks instead of rocks. Model: `Workspace.TestArea.Models.Chainsaw` ("Worn Chainsaw"
MeshPart, 1.44 × 1.33 × 4.98 studs). Animations: the pack's Idle / Walk / Mine 1 / Mine 2.

## 1. What the pack is, in our terms

| Pack piece | What it does | Kaiju equivalent |
|---|---|---|
| `PickaxeService` (server) | Gives every character a handle-less Tool and welds the model to the RightHand with a Motor6D | A normal Tool with a Handle in `StarterPack` (our Inventory, slots and grip editor already work that way) |
| `MiningController` (client) | Hold = swing Mine 1 then Mine 2; the hit fires at a fixed frame of the swing; input buffer, combo gap and window, finish cooldown, hitstop | `StarterPack.Chainsaw.Client` |
| `FindTarget` | Melee box 5×6×5 studs, 3 studs in front of the root; nearest rock hitbox inside | Same box, but the candidates are the kaiju blocks under it (grid lookup, not 8,000 hitboxes) |
| `MiningService` (server) | Validates tool, reach 10, hit interval 0.35; rolls 20–30 damage, 15 % crit ×2; writes `MiningHealth`; respawns rocks | `Server.Chainsaw`: validates, then `Demolition.Damage` (chunks, percent, cash, D7 / D9). Nothing respawns |
| `RockEffectsController` | Squash/lean spring, white flash, chips cloned from the rock, dust, CRITICAL! text, two hit sounds, camera kick, vignette flash | Our `BlockFX` already pops the whole block, puffs dust and throws pooled shards; add flash, crit text, sounds, camera kick, vignette |
| `PickaxeAnimationController` | Idle / Walk loops while held, walk speed follows ground speed | Same, in the tool client |
| `GripController` | Shifts the weld during each swing | Tween `Tool.Grip` |
| `MovementController` | Walk 16 / 11 held / 5 while swinging | Same numbers, held only |
| `CameraController` | FOV 62 held, head follow, sway, shake, dip | Port the hit shake and dip; FOV must respect the gas mask FOV tiers |
| `ShiftLockController`, `FacingController` | Custom shift lock and face-the-camera | Skip for now: clashes with the View toggle (V) |
| `VignetteController` | Grey edge while held, white flash on hit | Port as a screen flash |
| `WindController` | Wind trails while running | Later, cosmetic |
| `RockHealthController` | Health bar above a rock | Block HP bar above the block being cut (one bar, moves with the target) |
| `RockClearanceController` | Pushes a player out of a respawning rock | Not needed: blocks never come back |

Rules carried over: `Demolition.CanDamage` still decides D7 / D9; damage per hit comes from
`UpgradeConfig` Player.Damage; the Speed tier now shortens the combo cooldowns instead of a timer;
Player.Range is ignored by the chainsaw (melee) until the ladder is retuned (Q24).

## 2. Constraints

- **License:** free to use and modify, not to resell or redistribute. Every pack file carries a
  watermark header that must stay if the file is reused. Plan: write our own modules in our
  architecture; nothing from the pack is copied into our scripts except numbers.
- **Packages:** the pack bundles Vide, Maid, Signal, SwiftPacket, Observers, PerfectSequencer and a
  Log library. New packages need Jawad or Bee. Not needed: our remotes and attributes cover it.
- **Animations:** the four IDs are published by skaterstudios and will not play in our game unless
  republished by the place owner (user 9618593716). The KeyframeSequences are in
  `Workspace["FREE Mining System - Ungroup"].Workspace["Pickaxe Animations"].AnimSaves`. Step 1's
  playtest tells us whether they load; if not, Shayan publishes them from the Animation Editor and
  pastes the IDs into `StarterPack.Chainsaw.Animations`.
- **Hit timing:** the pack fires at frame 29 of each swing. The saved sequences are 0.633 s (Mine 1)
  and 1.167 s (Mine 2) long, so the frame unit is 60 fps: the hit lands at 0.483 s into either swing.
  Mine 2 also carries a `Hit` marker at 0.433 s. Timing lives in `ToolConfig.Chainsaw.HitTime`.
- **Two cutters during development:** LaserCutter stays in slot 1; the chainsaw takes slot 4 until
  Shayan decides it replaces the laser.

## 3. Build order (one playtest per step, run by Shayan)

1. **Tool + animations.** `StarterPack.Chainsaw` with the mesh as Handle, the four animations, a
   client that plays Idle / Walk while held and the Mine 1 → Mine 2 combo while the mouse is held.
   The hit only prints. Check: tool in hand at the right angle, animations load, log shows swings and
   hit times.
2. **Hit → server → block.** Client finds the block in the melee box at the hit time and reports it.
   `Server.Chainsaw` validates (tool held, alive, reach, hit interval, `CanDamage`) and calls
   `Demolition.Damage` with the Player.Damage tier. `CutState` attribute as before. Check: blocks
   crack and break, percent and Cash move, drone and gun untouched.
3. **Feel on the block.** Hitstop, block flash, crit roll with CRITICAL! text, hit sounds, chips and
   dust from the impact point, camera kick, screen flash. Check: every hit reads.
4. **Body feel.** Walk speeds, FOV while held, grip shift during swings, head follow and sway.
5. **Block HP bar** above the block being cut.
6. **Enemies.** Chainsaw damages larvae like the laser does (`EnemyDPS`).
7. **Retire the laser** (or keep both), retune `Player.Range` and update the sheet, board and `src/`.

## 4. Log

- 2026-09-28: pack analysed (no backdoors; two startup scripts error because it is still grouped
  under Workspace). Step 1 built.
- 2026-09-28: the pack folder parked in `ServerStorage.Reference` (scripts disabled). Shayan republished
  the four animations under the place owner; IDs now on `StarterPack.Chainsaw.Animations`:
  Idle 99840311133211, Walk 107915644329835, Mine1 123877552384621, Mine2 98903146548842.
- 2026-09-28: tool rebuilt the way the Gun was: invisible `Handle` (0.4 × 0.6 × 0.6) at the rear
  D-handle, the mesh welded to it as `Body` (legacy Weld, C0 = 0, 0.1, -2.05), `Grip` identity so the
  blade leaves the fist along -Z, attachments `BladeTip` (z -2.4) and `BladeMid` (z -1.3) on Body for
  effects. Creator Store sounds on the Handle: EquipSound 135729718983904, IdleSound (loop)
  129562586053031, SwingSound 129972325154662, HitSound 133850299035625. The client plays them.
- 2026-09-28: step 2 built. `Remotes.ChainsawHit` (client -> server: part, blade position, swing;
  server -> client: ok, reason, crit, damage). `Server.Chainsaw` validates (NoTool / Dead / NoBlock /
  OutOfReach / TooSoon / Refused) and calls `Demolition.Damage` with DamagePerHit 30 x Player.Damage,
  15 % x2 crit, chunk cap from `Cutter.CellsPerHitByLevel`; CutState and Cutting attributes as the
  laser. Client finds the nearest kaiju part in a 6 x 6 x 6 box 3.5 studs ahead of the root at the hit
  time and outlines that block while held. Animations still blocked on the access grant (Shayan).
- 2026-09-28: step 2 verified by Shayan (client + server logs: every swing landed, one 9-chunk face per
  hit, Skin blocks in 3 hits). Server log now reports intact / cracked / BROKEN from `Demolition.BlockAt`
  (the first hit turned the Part into a Model, which read as "BROKEN"). Step 3 built: `StarterGui.ChainsawFX`
  (HitFlash frame + CritText billboard template, authored as instances), `FXConfig.Chainsaw`, and the client
  plays outline flash (red on crit), white screen flash, camera dip spring + rotation shake, CRITICAL! text
  at the blade point, all from the server's reply so only real hits feel. Crit text is local to the hitter
  (the pack broadcasts it); widen through BlockFX if wanted.
- 2026-09-28: step 3 verified by Shayan (animations now load; flash, screen flash, kick and one CRIT
  with text). Crit fix: the chunk cap (9) swallowed the doubled damage, so a crit now doubles the cap
  too (two faces). Step 4 built: walk 16 -> 11 held -> 5 mid-swing (eased), FOV 70 -> 62 while held,
  head-follow on Humanoid.CameraOffset (shares the dip), Tool.Grip slides 0.5 / 0.8 studs forward
  during Mine1 / Mine2 and blends back. Pickaxe sway skipped (tiny; add if the camera feels static).
  Custom shift lock and facing stay skipped (View toggle).
- 2026-09-28: Shayan: remove the ladders from the blocks. `Server.Scaffold` is no longer loaded by
  Main (line commented, module kept), the mission brief no longer mentions scaffolds, and leftover
  trusses were cleared from `Workspace.Scaffolds`. This answers Q25 (drop the scaffolds).
- 2026-09-28: playtest on R15 showed no animation (R6 clips cannot play on R15). Shayan switched the
  game's avatar type to **R6** in Game Settings; next playtest: equip, idle, both slashes, mount and
  hits all fine ("Everything is fine"). Steps 1-4 verified on the rig animations.
- 2026-09-28: Bee's action items arrived (`feedback.md`, 10 items). Analysis and order in chat; the
  chainsaw-related ones (replace the laser, click-per-swing with auto-cut as an upgrade, cutting area
  in blocks, no cut radius) fold into steps 6-7 of this plan.
- 2026-09-28 (Bee item 1): laser replaced. `StarterPack.LaserCutter` parked in `ServerStorage.Reference`
  (client script disabled), `Server.Cutter` no longer loaded, `ToolConfig.Slots` = Chainsaw / Gun /
  GasMask / reserved. Player ladders now describe the chainsaw: Damage (x1 / 1.4 / 1.9, unchanged),
  Speed = swing speed x1 / 1.25 / 1.5 (multiplies playback, divides ComboGap / FinishCooldown /
  MinHitInterval), Range = reach 2 / 3 / 4 BLOCKS (Bee: two blocks to start; the melee box is that
  deep and the server accepts a block centre within blocks x 8 + ReachSlack 4 + half-diagonal). The
  laser's cursor outline and 90-130 stud radius are gone with it. Balance estimates chainsaw
  throughput (two crit-weighted hits per combo cycle) instead of laser DPS. Brief says chainsaw.
- 2026-09-28 research (Shayan: damage too high, one block around the player). Public sources on the
  reference (flatten-themountain.wiki, flattenthemountains.wiki, Roblox page): Damage I = "three
  voxels per swing" and $1 (dated 09-02); Mine Distance I = 18 studs; mining is click / tap, Auto
  Mine "reduced repeated clicking"; a run = 534 m, 89 six-metre layers, ~9,400 blocks, flattened as
  walkable rings from the top; no public source describes the voxels per block, the base reach or
  the View button. Retune: DamagePerHit 30 -> 10, chunk cap per hit 9 -> 3 / 4 / 5 by Damage tier
  (crit doubles both), reach 2 / 3 / 4 -> 1 / 2 / 3 blocks. Skin block: 3 hits -> 9 hits at tier 1.
- 2026-09-28 playtest after the retune: 10 damage, 3 chunks per hit (6 on a crit), a Skin block in
  6 hits with three crits. Shayan: select the block with the mouse like the reference. The repo's FTM
  reverse-engineering spec records the reference as raycast from the camera -> logical block -> white
  outline -> dig at the ray's hit point; the wiki controls page says "tap the block" on mobile.
  Built: the chainsaw client now selects the block under the cursor (the laser's aim code, with its
  grid walk through cracked-block holes), outlines it white, and at the hit time sends that block and
  the ray's hit point. Reach is a cube of Range blocks around the player's body cell (1 = the ring
  around you, the floor and the step above); the server runs the same test plus 0.5 block of slack.
  The melee box and ReachSlack are gone. Live sources verified byte-equal to src/ after the push.
- 2026-09-28 playtest: cursor selection verified (every hit named the block under the cursor, hit
  points on the face pointed at, 3 chunks per hit, 6 on a crit). Out-of-reach whiff not yet exercised.
- 2026-09-28 (Bee item 2): one click per swing. Each Activated queues exactly one swing (a click
  during a swing queues the next); holding keeps swinging only with the new `Player.AutoCut` upgrade
  (Values 0 / 1, Names OFF / ON, cost $100, provisional; the reference sells Auto Mine the same way).
  `InputBuffer` removed. The tree got an authored hex `Node_Player_AutoCut_2` at axial cell (1, 0)
  (a copy of Node_Player_Speed_2 with Stat / Level / Q / Rr / Title / Icon set), and UpgradesUI's
  `fmt` reads an optional `ladder.Names` so the tooltip says OFF > ON; the PLAYER line tooltip now
  counts its stats. Server.Upgrades needed no change (it validates against UpgradeConfig.Stats).
- 2026-09-28 playtest: item 2 verified (swings "by click" until Auto Cut was bought for $100, then
  "by hold (auto cut)"; out-of-reach swings logged "no block under the cursor within 1 block").
- 2026-09-28 (Bee item 3): drone digs top-down. `Server.Drone.findTarget` now ranks candidates by
  layer first (highest grid BY wins) and distance second; it also drives the next-block chain and the
  on-the-way-home check, so all three follow layer order. New log line per target: "[Drone] X's drone
  #n -> Block_..., top layer in reach (y ..)". The drone still searches within SearchRadius (120) of
  itself and returns to its owner between jobs. Drone is not mirrored in src/ (the src copy predates
  the 09-24/25 rewrite; live Studio is the source of truth for it).
- 2026-09-28 playtest: item 3 verified at the pick ("drone #1 -> Block_2_23_-203, top layer in
  reach (y 168)"). Only one pick in a minute because the drone cuts at 2 DPS (09-25 tuning, ~40 s per
  Skin block). Added a log line for the next-block chain so layer progression shows in the log.
- Item 4 (spawn on top): already true. SpawnLocation (-4, 168.5, -397) stands on the top face of
  layer BY 23 (y 168), at the top layer's front edge, 77 studs from the body's centre. Left as is.
- 2026-09-28 (Shayan: "the drone works like a turret"). Reference, from the wiki's overview of a
  good run ("drones above clusters, turrets on the sides"; "Drones: parked on payday clusters") and the
  repo's earlier study (Drone Laser & Auto-Helper Plan section 2: "hover above the work, and hold a
  continuous beam down"): drones beam DOWN from above, turrets beam from the sides. Ours had been
  switched to side-beaming on 09-25. Server.Drone.pickSide now returns the top face whenever the cell
  above the block is empty (top-down targeting makes that the norm), falling back to an open side
  under an overhang; the drone holds Standoff (12) above the chunk and sinks with the dig; the beam
  leaves from the drone's underside. Target and chain log lines say "from above" / "from the side".
- 2026-09-28 playtest: drone from above "working fine" (Shayan). Next asks: the pack's health bar for
  blocks (player and drone hits), and cutting one layer at a time.
- Health bar: Demolition.CellHit now carries the block's health after each hit (fraction, hp, max);
  Server.BlockFX relays it in the "Hit" event. New `StarterGui.BlockHealth` BillboardGui (authored:
  HEALTH + "hp / max" labels, track with the pack's green gradient fill, red trail, 4 segment lines,
  white flash layer, inside a CanvasGroup for the fade) and `StarterPlayerScripts.BlockHealth`, which
  clones it over any block hit by anyone, fills in 0.25 s, drains the trail over 0.9 s, flashes, and
  fades 3.5 s after the last hit (0.6 s after a break). Max 12 bars. Numbers: FXConfig.BlockHealth.
- One layer at a time (`RunConfig.OneLayerAtATime = true`): Demolition counts live blocks per layer
  (buried included, sandbox-adopted blocks excluded, tagged `Adopted`), publishes RunState.ActiveLayer
  / ActiveLayerLeft, and CanDamage refuses Player and Drone hits below the open layer; clearing it
  prints "[Demolition] layer N cleared; layer M is now open". The chainsaw outlines a locked block
  red and does not report the swing. The drone's search already filters by CanDamage.

### 2026-09-28: solid kaiju and the KJ-25 balance
- Hollow found: not a sealed pocket (a 3D flood fill finds none) but a cave under the mantle, open to
  the ground: 1,544 empty cells, BY 3 to 12, up to 8 blocks tall, over BX -18..20 / BZ -231..-172.
  Filled (one undo waypoint "Fill kaiju cave"): 375 Skin blocks on the new underside surface in
  Workspace.Kaiju, 1,169 Flesh blocks inside in ServerStorage.KaijuHidden, 432 old cave-lining blocks
  that are now sealed in moved to KaijuHidden (408 of them Skin / Light relined as Flesh). Same rule as
  the generator: a block is visible when any face touches air, and the ground counts as air.
  The arms' one-block gap to the ground (563 cells) was left alone: that is their shape, not a hollow.
- Now 36,678 blocks (8,201 visible, 28,477 hidden), 2,527,740 HP, Kaiju.TotalBlocks updated.
- Server.Balance is now a whole-run simulator (cash per block, cheapest-upgrade-first buying, chainsaw
  with crits and area, drones with hits per block and flight). Before the retune: a 4-player run was
  about 558 min and a solo run did not finish inside 10 hours; fully upgraded, one player broke 0.45 blocks/s.
- Root-cause fix in Demolition.Damage: a hit's leftover damage now carries into the chunks it reveals.
  Before, a hit could only take chunks already showing, so a block open on top took 3 hits whatever the cap.
- Retune (all four KJ-25 levers):
  - Target: RunConfig.TargetRunMinutes 15 -> 30, measured for a full party of 4. Each player's share
    (about 9,000 blocks) is the reference's whole mountain, 33-51 min solo there.
  - Area damage per cutter level: ToolConfig.Chainsaw.AreaByTier { 1, 5, 9 } by Player.Damage tier
    (the aimed block; plus its 4 side neighbours; the 3x3), same layer, each passing CanDamage. Tier 1
    is unchanged, so the first swings still feel like one block.
  - Automation carries the bulk: DroneConfig.DPS 2 -> 92, ChunksPerHitByTier { 9, 18, 27 }, Drone.Damage
    { 1, 1.5, 3 } = 3 / 2 / 1 hits a block (the old 1.65 / 2.7 made tier 3 a trap: 2 hits like tier 2),
    Drone.Count { 2, 4, 6 }, six hover slots.
  - Costs spread over the run: cutting stats 150 / 600, drones 250 / 1000, drone damage 200 / 800, reach 100 / 300.
- Simulated: 4 players 31.1 min, solo 83.1 min. Fully upgraded, a player breaks 1.95 blocks/s with the
  saw and 11.6 with drones; the tree is complete at about 14 min of a 4-player run.
- Watch in the playtest: 4 players at full upgrades break about 54 blocks/s, each cracking into chunk
  Parts with FX. Server and client frame time are the risk to check. A 15-minute 4-player run at this
  feel needs about a third of the blocks (about 12,000, for example re-voxelising at 12-stud blocks).

### 2026-09-28: streamline (12-stud kaiju, dead paths, chunk pop)
- Kaiju rebuilt at 12-stud blocks by resampling the solid 8-stud body (27 samples per new cell,
  majority keeps it; a surface cell keeps the commonest surface material among its samples, inside
  cells take the plain majority). 10,720 blocks: 3,554 visible, 7,166 hidden, 14 layers (BY 1..14,
  ground still at y 0, origin -8, -6, 1222). Every region keeps 95-106% of its volume; extent matches
  within 10 studs. The 8-stud kaiju is parked, not deleted: ServerStorage.Reference.Kaiju_8stud and
  KaijuHidden_8stud. Undo waypoint "Rebuild kaiju at 12-stud blocks".
- Block-size follow-ups: KaijuConfig.BlockSize 12 (informational), DroneConfig.NextBlockRadius 14 -> 20.
- Balance for 10,720 blocks: RunConfig.TargetRunMinutes 15 for a 4-player party; Drone.Count back to
  { 1, 2, 4 } (four hover slots); costs 30 / 120 (cutting stats, drone speed), 50 / 160 (drones),
  40 / 140 (drone damage), 30 / 100 (reach). Simulated: 4 players 14.9 min, solo 43.6 min (the
  reference's solo runs are 33-51). Fully upgraded party peak: about 29 blocks/s (was 54).
- Retired (moved to ServerStorage.Reference.Retired, nothing deleted): Server.Cutter, Server.Scaffold,
  Remotes.CutterAim, the Workspace.Scaffolds folder. Removed from code: ToolConfig.Cutter, the drone's
  legacy HoverShoot mode (DroneConfig.Mode / Range), the disabled N4 share cap (MaxShare /
  EnforceShareCap), Main's commented requires. The TestArea sandbox stays until ship day (Bee: 09-30).
- Chunk pop-out / pop-in (the mining pack's rock feel, our own code in StarterPlayerScripts.BlockFX,
  numbers in FXConfig.PopSpring): a removed chunk leaves a pooled ghost that swells to about 1.17 and
  springs to nothing in about 0.25 s; a chunk or block the server reveals springs up from 0.2 to an
  overshoot of 1.2 and settles. Demolition stamps revealed parts with a RevealedAt server time so only
  those pop in (StreamingEnabled parts arriving late do not). The whole-block punch now scales from each
  part's recorded base size, so a punch mid pop-in cannot leave a chunk small. Server.BlockFX relays the
  chunk material for the ghost. Log: "[BlockFX] last 5 s: N block punch(es), N chunk pop-out(s), N pop-in(s)".

### 2026-09-28: drones patrol the layer, UFO visits
- Drone beam fixed to the drone (straight down from the gimbal, Cfg.MuzzleOffset); only the drone moves.
  Beam ON in APPROACH and CUT including every hop, OFF only in PATROL, when the open layer holds nothing
  a drone may cut (only event blocks, or everything claimed). Damage lands at the beam foot once on station.
- Drones no longer follow their owner (Follow / Return / onPathHome / HoverOffsets removed). With nothing
  to cut they circle the open layer (OrbitSpeed 30 x Drone.Speed, OrbitMargin 12 outside the widest block,
  Standoff above the top; recomputed when a layer opens), searching the whole layer every 1.5 s.
- Flight: one top speed (ApproachSpeed 90 x Drone.Speed) with an ease-out (ArriveEase 8, MinSpeed 6), heading
  held for the last 2 studs. Research (FTM wiki, Mine a Planet, PS99, Idle Obelisk Miner): travel speed and
  cutting speed are separate stats everywhere; FTM also has a Rate stat we do not.
- UFO visits (FTM's eagle: periodic, "EAGLE INCOMING!", red path, one pass, dodge, no reward; the grab is
  unsourced and left out): one UFO per server, first 45 s into a run, then every 60-90 s after the last one
  left. It descends over a random briefed player on the open layer while the HUD flashes "EVENT: UFO
  INCOMING!", attacks twice (the existing sweep or larva drop), then leaves. EventConfig.UFO.Visit. Sweep
  line resized for 12-stud blocks (72 x 12 x 12). EventRoll now counts on from RunState.EventCount so both
  writers keep the HUD flash firing.
- UFO tweaks (Shayan): a visit is ONE kind, sweep or larva drop (Weights), never both, so a larva visit has
  no red line; a drop visit hovers straight over its player and lands 3-4 larvae (Visit.DropMin/Max). A
  visiting UFO's sweep crosses the WHOLE open layer edge to edge through the player (attribute FullWidth,
  Sweep.EdgeMargin 12), faster (FlySpeed 120, PassSpeed 90), tints the row of blocks it lies on, and leaves
  from the far end. Saucers spin client-side (StarterPlayerScripts.UFOSpin turns the root Motor6D's
  Transform, SpinSpeed attribute, 90 deg/s); the sandbox saucer spins too.
- Two saucers by tag (Shayan's models in Workspace.TestArea.Models): "DamageUFO" (Damage-UFO: the red line
  sweep only) and "LarvaUFO" (Larva-UFO: beams larvae down only), bound in Server.UFO with a fixed kind; the
  plain "UFO" tag still means random. Visits clone ServerStorage.Templates["Damage-UFO" / "Larva-UFO"]
  (tag-free copies) and tag them by kind. A larva visit's hover puts the bottom of the Larva-UFO's
  Kaiju-Skin-Identify part on the kaiju skin (24.1 studs under the root); that part is now welded to the
  Beam with collisions off (it was loose and CanCollide, so it would have fallen off and been a platform).
