SMODS.Atlas {
    key = "elytra",
    path = "menace.png",
    px = 71,
    py = 95
}

SMODS.Joker {
	key = "elytra",
	loc_txt = {
		name = "Elytra",
		text = {
			"Sell instantly to beat the current blind"
		}
	},
	
	unlocked = true,
	discovered = true,

	blueprint_compat = false,
	brainstorm_compat = false,
	eternal_compat = true,
	perishable_compat = true,
	
	rarity = 3,
	atlas = "elytra",
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
		if context.selling_self and not context.retrigger_joker and not context.blueprint_card then
            if G.STATE == G.STATES.SELECTING_HAND then
				G.GAME.chips = G.GAME.blind.chips
				G.STATE = G.STATES.HAND_PLAYED
				G.STATE_COMPLETE = true
				end_round()
			end
		end
	end
}