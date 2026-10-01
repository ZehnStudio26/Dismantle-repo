-- Run-level rules. Every number is provisional (GDD 仮) until ch.15 KPIs settle it.
return {
	-- Shayan 2026-09-28: the kaiju is cut one layer at a time, like the reference's flattening. Only the
	-- highest layer that still has blocks (buried ones included) can be cut by the drones; clearing it
	-- unlocks the next one down. Ayesh 2026-10-01: the player cuts anywhere, only drones follow the layers.
	-- Blocks adopted by the Studio sandbox are exempt.
	OneLayerAtATime = true,
	MaxPartySize = 4,        -- D2
	PlayerMaxHP = 100,       -- D4, no passive regen. Back to a 100 pool on 2026-09-25 (H-1's "four
	                         -- hits" was tried and reverted the same day); hazard damage in
	                         -- EventConfig is on this scale, 10 per gas tick or larva bite.
	TargetRunMinutes = 15,   -- KJ-25 (2026-09-28): measured for a FULL party of MaxPartySize, not solo. On the 12-stud
	                         -- kaiju (10,720 blocks) each player's share is about 2,700 blocks; a solo run takes about 45 min,
	                         -- inside the reference's 33-51. Server.Balance prints both.
	-- A16 balance guard: pure cutting time (total block HP / (cutter + drone DPS)) should leave
	-- this share of the target for movement, climbing and events. Balance logs a warning otherwise.
	OverheadShare = 0.35,
	-- Provisional economy (Q04 decides the real one): cash credited to the finishing actor per completed block,
	-- drones credit their owner, as in the reference. Shown as "+$N" and on the HUD.
	-- the VIEW button's top-down map camera: studs right / up / back of its focus point in the heading you had
	-- when you switched, eased at Sharpness. It does not follow you: PanStep studs per wheel notch, DragSpeed studs
	-- per pixel of right-drag, the focus kept within Margin studs of the kaiju. V / VIEW returns to first person.
	TopView = { Right = 18, Height = 72, Back = 26, Sharpness = 10, PanStep = 16, DragSpeed = 0.35, Margin = 60 },
	ToTopCooldown = 20, -- seconds between TO TOP button uses; the button only works off the open layer
	ClimbWalkSpeed = 40, -- walk speed held while on a ladder (climb = 70% of it, ~28 studs/s: the tower in ~6 s)
	CashPerBlock = { Player = 3, Drone = 1 }, -- $ per block by who broke it (2026-09-29: chainsaw 1 -> 3)
	-- H-2 clear screen (Server.RunEnd, 2026-09-29): a flat reward to everyone when the kaiju is cleared (R-3's
	-- "clear reward"; provisional, about a fifth of what a 4-player run pays each player by cutting), how long
	-- the results show before everyone returns, and the lobby for players who joined the gameplay place
	-- directly (0 = none; players who came through the lobby return to it by their join data).
	ClearReward = 500,
	ResultsSeconds = 20,
	LobbyPlaceId = 100673839351076, -- "[Lobby] - Cleaner the Kaiju", the experience's start place
}
