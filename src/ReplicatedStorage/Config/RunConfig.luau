-- Run-level rules. Every number is provisional (GDD 仮) until ch.15 KPIs settle it.
return {
	MaxPartySize = 4,        -- D2
	PlayerMaxHP = 100,       -- D4, no passive regen
	TargetRunMinutes = 15,   -- N1 / O-C provisional, measured as a SOLO run (D2: difficulty does not scale)
	-- A16 balance guard: pure cutting time (total block HP / (cutter + drone DPS)) should leave
	-- this share of the target for movement, climbing and events. Balance logs a warning otherwise.
	OverheadShare = 0.35,
	-- Provisional economy (Q04 decides the real one): cash credited to the finishing actor per completed block,
	-- drones credit their owner, as in the reference. Shown as "+$N" and on the HUD.
	CashPerBlock = 1,
}
