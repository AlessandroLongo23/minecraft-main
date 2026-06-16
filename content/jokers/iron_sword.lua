SMODS.Joker {
    key = 'iron_sword',
    loc_txt = {
        name = 'Iron Sword',
        text = { '{X:mult,C:white}X2{} Mult while fighting', 'a {C:attention}Boss Blind{}.' },
    },
    unlocked = true, discovered = true,
    blueprint_compat = true, eternal_compat = true,
    rarity = 2,
    atlas = 'mc_resource_cards', pos = { x = 0, y = 1 }, -- placeholder (iron cell)
    cost = 6,
    calculate = function(self, card, context)
        if context.joker_main and G.GAME.blind and G.GAME.blind.boss then
            return { x_mult = 2 }
        end
    end,
}
