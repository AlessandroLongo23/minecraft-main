SMODS.Atlas {
    key = "crackedknuckles",
    path = "menace.png",
    px = 71,
    py = 95
}

SMODS.Joker {
	key = "crackedknuckles",
	loc_txt = {
		name = "Cracked Knuckles",
		text = {
			"Gains {C:chips}+50{} Chips and {C:mult}+5{} Mult",
            "when beating a small blind",
			"{C:inactive}(Currently {C:chips}+#1#{} Chips and {C:mult}+#2#{} Mult{C:inactive})"
		}
	},
	
	unlocked = true,
	discovered = true,

	blueprint_compat = true,
	brainstorm_compat = true,
	eternal_compat = true,
	perishable_compat = true,
	
	rarity = 1,
	atlas = "crackedknuckles",
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
			accumulated_mult = 0,
			accumulated_chips = 0
		}
	},
	
	loc_vars = function(self, info_queue, center)
        return {
            vars = {
                center.ability.extra.accumulated_chips,
                center.ability.extra.accumulated_mult
            }
        }
    end,

	calculate = function(self, card, context)
		if context.end_of_round and not context.other_card and G.GAME.blind.name == 'Small Blind' and not context.blueprint then
			card.ability.extra.accumulated_chips = card.ability.extra.accumulated_chips + 50
			card.ability.extra.accumulated_mult = card.ability.extra.accumulated_mult + 5

			return {
				message = "+50",
				colour = G.C.CHIPS,
				card = card
			}
		end
		
		if context.joker_main and card.ability.extra.accumulated_chips > 0 and card.ability.extra.accumulated_mult > 0 then
			return {
                chips = card.ability.extra.accumulated_chips,
				mult = card.ability.extra.accumulated_mult
			}
		end
	end
}