# Dismantle — source mirror of kaiju.rbxl

Every script in the Studio place, one file per Instance, mirrored so that a lost or reverted place is a
re-send, not a rewrite. Paths mirror the DataModel:

```
ReplicatedStorage/Config/*.luau              ModuleScripts (tunable numbers)
ServerScriptService/Server/*.luau            ModuleScripts; Main.server.luau is the one Script
StarterPlayer/StarterPlayerScripts/*.client.luau   LocalScripts
StarterPlayer/StarterCharacterScripts/Health.server.luau
StarterPack/<Tool>/Client.client.luau        LocalScript inside each Tool
Setup.luau                                   run once in the Studio command bar: creates every non-script
                                             Instance (folders, remotes, RunState, tools, handles)
```

Restore procedure
1. Open kaiju.rbxl. Run `Setup.luau` in the command bar (it is idempotent).
2. Paste each file into the matching Instance (or send them through the MCP `set_script_source`).
   Do not use `\n` escapes inside Luau strings through MCP; the transport turns them into real newlines.
3. Play. The server prints `[Balance]`, `[KPI] RunStart`, `[Brief]` lines when everything loaded.
4. Save (Ctrl+S). Nothing in this pipeline saves the place for you.

Kaiju model (Large Voxel Kaiju, 2026-09-23): Workspace.Kaiju is a Model of exposed 8-stud block Parts named
Block_x_y_z with attributes BlockMaterial, Region, BlockId, Demolishable, Color, BX/BY/BZ; hidden blocks are
Parts in ServerStorage.KaijuHidden (server only). Kaiju attributes: BlockSize, Grid, Origin, Scale, TotalBlocks.
Blocks crack into 3x3x3 chunks at runtime. Regenerate from ServerStorage.Assets.Kaiju_Blocks_v1 (the 1,350-block
8-stud octopus) with the generator recorded in the Voxel Kaiju Plan (scale S = 3 gives 35,134 blocks).
