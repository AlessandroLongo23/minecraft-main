SMODS.Blind {
    key = 'slime',
    loc_txt = {
        name = "The Slime",
        text = {
            "After beating it, next",
            "ante's small and big blind",
            "are X1.5 and X1.25"
        }
    },
    discovered = true,
    boss = {
        min = 2,
        max = 2
    },
    pos = {
        x = 0,
        y = 13
    },
    atlas = 'blinds',
    boss_colour = HEX('5AA244'),
    defeat = function()
        local ante = (G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or 1
        PB_UTIL.set_next_blind_mult({ ante = ante + 1, Small = 1.5, Big = 1.25 })
    end
}
