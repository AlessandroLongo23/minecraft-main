-- Placeholder art: no atlas/pos -> SMODS falls back to the base-game blind chip sprite.
SMODS.Blind {
    key = 'shulker',
    loc_txt = {
        name = "The Shulker",
        text = {
            "Before your second hand,",
            "lose {C:money}$ {}equal to the total",
            "rank of the first hand"
        }
    },
    discovered = true,
    boss = {
        min = 2,
        max = 2
    },
    boss_colour = HEX('8A5A8A'),
    set_blind = function(self)
        self.shulker_first_total = nil
    end,
    press_play = function(self)
        local hands_played = G.GAME.current_round.hands_played
        if hands_played == 0 then
            -- first hand of the round: record the total rank played
            local total = 0
            for _, c in ipairs(G.hand.highlighted) do
                total = total + (c.base.nominal or 0)
            end
            self.shulker_first_total = total
        elseif hands_played == 1 then
            -- second hand: pay the tax before it scores
            if self.shulker_first_total and self.shulker_first_total > 0 then
                ease_dollars(-self.shulker_first_total)
                G.GAME.blind:wiggle()
            end
        end
    end
}
