SMODS.Atlas {
    key = "depa",
    path = "Depa.png",
    px = 71,
    py = 95
}

SMODS.Joker {
	key = "depa",
	loc_txt = {
		name = "Depa",
		text = {
			"A simple Joker with no special abilities."
		}
	},
	
	unlocked = true,
	discovered = true,

	blueprint_compat = false,
	brainstorm_compat = false,
	eternal_compat = true,
	perishable_compat = true,
	
	rarity = 1,
	atlas = "depa",
	pos = { x = 0, y = 0 },
	cost = 4,
	value = 8,
	
	pools = {
		Common = true,
		Shop = true,
		Event = true,
		Rare = false,
		Legendary = false,
		Buffoon = false
	},


	calculate = function(self, card, context)
		-- This joker has no special abilities
	end
}