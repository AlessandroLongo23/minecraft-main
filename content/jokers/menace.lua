SMODS.Atlas {
    key = "menace",
    path = "menace.png",
    px = 71,
    py = 95
}

SMODS.Joker {
	key = "menace",
	loc_txt = {
		name = "Menace",
		text = {
			"Gains {C:mult}x0.25{} mult each time a",
			"{C:attention}High Card{} poker hand is played.",
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
	atlas = "menace",
	pos = { x = 0, y = 0 },
	
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
		if context.before and not context.blueprint and context.scoring_name == "High Card" then
			card.ability.extra.accumulated_mult = card.ability.extra.accumulated_mult + 0.25
			
			return {
				message = "+x0.25",
				colour = G.C.MULT,
				card = card
			}
		end
		
		if context.joker_main and card.ability.extra.accumulated_mult > 1 then
			return {
				mult = card.ability.extra.accumulated_mult
			}
		end
	end
}