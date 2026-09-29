-- Text mission brief (B13 / MAP-09 / MAP-10). Replaces the opening movie for the MVP.
-- Narrated line by line on a player's first run; from the second run on, a skip is offered.
return {
	Title = "SITE BRIEF",
	Lines = {
		"A kaiju came down on the city last night. It is not getting up.",
		"You are the cleanup crew. Cut it down to nothing.",
		"Chainsaw for the body. Mask when the gas hits. Gun for whatever crawls out.",
		"Earn cash by cutting. Buy drones to cut with you.",
		"100% dismantled clears the site. Get to work.",
	},
	SecondsPerLine = 2.8,
	HoldSeconds = 2.0,      -- pause after the last line before the brief closes itself
	SkipKey = Enum.KeyCode.Space,
}
