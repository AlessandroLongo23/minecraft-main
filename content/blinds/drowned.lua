SMODS.Blind {
    key = 'drowned',
    loc_txt = {
        name = "The Drowned",
        text = { 
            "After discard,",
            "discard an additional",
            "random card"
        }
    },
    discovered = true,
    boss = {
        min = 1,
        max = 1
    },
    pos = {
        x = 0,
        y = 6
    },
    atlas = 'blinds',
    boss_colour = HEX('4D9280')

    -- effect in lovely.toml because it couldn't be done here due to lack of "press_discard" blind event
}