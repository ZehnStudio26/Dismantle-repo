-- Lobby shop (R-4 / KJ-70, Shayan 2026-09-29): "Buy in lobby, bring into the run, use to heal. Only item in
-- MVP". Shared by the lobby (Shop: buying) and the gameplay place (using). Paid with the one saved
-- currency, Cash (R-3). Each item is a saved player attribute (Profile).
return {
	Order = { "Medkit" }, -- display order in the shop
	Items = {
		Medkit = {
			Label = "MEDKIT",
			Icon = "💊",
			Price = 40,
			Heal = 50,            -- HP per use, capped at MaxHealth
			Max = 3,              -- carried at once
			Attribute = "Medkits",
			UseKey = Enum.KeyCode.H,
			Desc = "+50 HP when you need it. Use it in a run with H.",
		},
	},
}
