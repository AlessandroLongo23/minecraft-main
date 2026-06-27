SMODS.Blind {
    key = 'magmacube',
    loc_txt = {
        name = "The Magma Cube",
        text = {
            "After beating it, next",
            "ante's small blind",
            "requirement is X2"
        }
    },
    discovered = true,
    boss = {
        min = 2,
        max = 2
    },
    pos = {
        x = 0,
        y = 9
    },
    atlas = 'blinds',
    boss_colour = HEX('340800'),
    defeat = function()
        local ante = (G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or 1
        PB_UTIL.set_next_blind_mult({ ante = ante + 1, Small = 2 })
    end
}
