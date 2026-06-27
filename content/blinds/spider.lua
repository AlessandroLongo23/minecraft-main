SMODS.Blind {
    key = 'spider',
    loc_txt = {
        name = "The Spider",
        text = {
            "Debuff all cards",
            "with an enhancement"
        }
    },
    discovered = true,
    boss = {
        min = 2,
        max = 2
    },
    pos = {
        x = 0,
        y = 4
    },
    atlas = 'blinds',
    boss_colour = HEX('342D27'),
    -- No clean hook neutralizes only the enhancement, so any enhanced card is fully debuffed.
    recalc_debuff = function(self, card, from_blind)
        return card.playing_card
            and card.config and card.config.center
            and card.config.center ~= G.P_CENTERS.c_base
            and true or false
    end
}
