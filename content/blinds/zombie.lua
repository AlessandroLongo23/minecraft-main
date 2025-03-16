SMODS.Blind {
    key = 'zombie',
    loc_txt = {
        name = "The Zombie",
        text = { 
            "After beating it,",
            "makes the leftmost joker",
            "perishable"
        }
    },
    discovered = true,
    boss = {
        min = 1,
        max = 1
    },
    pos = {
        x = 0,
        y = 1
    },
    atlas = 'blinds',
    boss_colour = HEX('4E7D3D'),
    defeat = function()
        G.jokers.cards[1].ability.perishable = true
        G.jokers.cards[1].ability.perish_tally = G.GAME.perishable_rounds
        G.jokers.cards[1]:juice_up(0.8, 0.8)
    end
}