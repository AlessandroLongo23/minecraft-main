-- Placeholder art: no atlas/pos -> SMODS falls back to the base-game blind chip sprite.
SMODS.Blind {
    key = 'witch',
    loc_txt = {
        name = "The Witch",
        text = {
            "At the start of the round,",
            "shuffles your hands",
            "and discards"
        }
    },
    discovered = true,
    boss = {
        min = 2,
        max = 2
    },
    boss_colour = HEX('3A2E4A'),
    set_blind = function(self)
        local hands = G.GAME.current_round.hands_left
        local discards = G.GAME.current_round.discards_left
        local total = hands + discards
        if total < 1 then return end

        -- random split of the same total, always leaving at least 1 hand
        local new_hands = 1 + math.floor(pseudorandom(pseudoseed('witch')) * total)
        local new_discards = total - new_hands

        self.witch_dh = new_hands - hands
        self.witch_dd = new_discards - discards
        if self.witch_dh ~= 0 then ease_hands_played(self.witch_dh) end
        if self.witch_dd ~= 0 then ease_discard(self.witch_dd) end
    end,
    disable = function(self)
        if self.witch_dh and self.witch_dh ~= 0 then ease_hands_played(-self.witch_dh) end
        if self.witch_dd and self.witch_dd ~= 0 then ease_discard(-self.witch_dd) end
        self.witch_dh, self.witch_dd = nil, nil
    end
}
