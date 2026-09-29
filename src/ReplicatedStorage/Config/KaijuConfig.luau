-- Body-only config. Block HP keyed by the BlockMaterial attribute on each Part. All values provisional (Q05).
return {
	BlockSize = 6,  -- informational; Demolition reads the real size from Workspace.Kaiju.BlockSize (12-stud rebuild 2026-09-28, KJ-25; 0.9 scale; then 6-stud blocks 2026-09-29 so a player can jump onto one)
	-- Voxel Kaiju Plan: every block is a Model of Grid^3 chunks (2.67 studs at 3 on 8-stud blocks). Chunk HP = block HP / Grid^3.
	-- Only exposed chunks exist as Parts; hidden ones are revealed as neighbours go.
	Cells = { Grid = 3 },
	BlockHP = {
		-- 2026-09-29 (Shayan): Ridge 120 -> 80; Skin, Sucker, Event, Survivor 80 -> 60
		Light = 40, Skin = 60, Flesh = 60, Sucker = 60, Ridge = 80, Eye = 60,
		Event = 60, Organ = 100, Egg = 60, Survivor = 60,
		Default = 60,
	},
	-- Kaiju skin Phase 1 (R14 / Q27): built-in PBR materials per BlockMaterial, tinted by the block Color.
	-- Zero extra instances. Phase 2 swaps these for uploaded MaterialVariants assigned by name.
	Materials = {
		Skin = Enum.Material.Cobblestone,   -- scale plates
		Flesh = Enum.Material.Mud,          -- wet, organic
		Sucker = Enum.Material.Pebble,
		Ridge = Enum.Material.Slate,
		Eye = Enum.Material.Glass,
		Light = Enum.Material.Neon,         -- bioluminescent spots glow
		Event = Enum.Material.Neon,         -- buried event blocks glow when exposed (EVT-02 hint)
		Organ = Enum.Material.Neon,
		Egg = Enum.Material.Neon,
		Default = Enum.Material.SmoothPlastic,
	},
	-- D7: the drone never cuts these. "Event" is the seeded buried block whose outcome is rolled
	-- when it breaks (EVT-02). Egg / Organ remain for hand-placed blocks with a fixed outcome.
	EventMaterials = { Event = true, Organ = true, Egg = true },
}
