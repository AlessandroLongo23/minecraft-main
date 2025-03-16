SMODS.Atlas {
    key = "itshome",
    path = "menace.png",
    px = 71,
    py = 95
}

SMODS.Joker {
	key = "itshome",
	loc_txt = {
		name = "It's Home",
		text = {
			"{C:mult}X1.5{} Mult if played hand contains",
			"{C:attention}2 or fewer{} cards.",
		}
	},
	
	unlocked = true,
	discovered = true,

	blueprint_compat = true,
	brainstorm_compat = true,
	eternal_compat = true,
	perishable_compat = true,
	
	rarity = 1,
	atlas = "itshome",
	pos = { x = 0, y = 0 },
	
	pools = {
		Common = true,
		Shop = true,
		Event = true,
		Rare = false,
		Legendary = false,
		Buffoon = false
	},

	calculate = function(self, card, context)
		local hand = next(G.play.cards) and G.play.cards or G.hand.highlighted
        if context.joker_main and hand and #hand <= 2 then
            return {
                mult = 1.5
            }
        end
	end
}