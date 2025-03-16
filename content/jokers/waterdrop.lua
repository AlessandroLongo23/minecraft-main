SMODS.Atlas {
    key = "waterdrop",
    path = "menace.png",
    px = 71,
    py = 95
}

SMODS.Joker {
	key = "waterdrop",
	loc_txt = {
		name = "Waterdrop",
		text = {
			"Gains {C:mult}x0.10{} mult for each small and big blind",
			"and {C:mult}x0.25{} mult for each boss blind beaten with one hand.",
			"{C:inactive}(Currently {C:mult}x#1#{C:inactive} Mult)"
		}
	},
	
	unlocked = true,
	discovered = true,

	blueprint_compat = true,
	brainstorm_compat = true,
	eternal_compat = true,
	perishable_compat = true,
	
	rarity = 1,
	atlas = "waterdrop",
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

	config = {
		extra = {
			accumulated_mult = 1
		}
	},
	
	loc_vars = function(self, info_queue, center)
        return {vars = {center.ability.extra.accumulated_mult}}
    end,


	calculate = function(self, card, context)
		if context.end_of_round and not context.other_card and G.GAME.current_round.hands_played == 1 then
            if not G.GAME.blind.boss then
                card.ability.extra.accumulated_mult = card.ability.extra.accumulated_mult + 0.10
                return {
                    message = "+x0.10",
                    colour = G.C.MULT,
                    card = card
                }
            else
                card.ability.extra.accumulated_mult = card.ability.extra.accumulated_mult + 0.25
                return {
                    message = "+x0.25",
                    colour = G.C.MULT,
                    card = card
                }
            end
		end
		
		if context.joker_main and card.ability.extra.accumulated_mult > 1 then
			return {
				mult = card.ability.extra.accumulated_mult
			}
		end
	end
}