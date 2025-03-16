SMODS.Atlas {
    key = "0164",
    path = "menace.png",
    px = 71,
    py = 95
}

SMODS.Joker {
	key = "0164",
	loc_txt = {
		name = "0.164%",
		text = {
			"Probability of finding this is 0.164%",
		}
	},

    ability = {
        extra_value = 64
    },
	
	unlocked = true,
	discovered = true,

	blueprint_compat = false,
	brainstorm_compat = false,
	eternal_compat = true,
	perishable_compat = true,
	
	rarity = 3,
	atlas = "0164",
	pos = { x = 0, y = 0 },
	
	pools = {
		Common = true,
		Shop = true,
		Event = true,
		Rare = false,
		Legendary = false,
		Buffoon = false
	},

    add_to_deck = function(self, card, from_debuff)
		card.ability.extra_value = 63
		card:set_cost()
    end,
}