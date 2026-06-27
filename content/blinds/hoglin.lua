-- Placeholder art: no atlas/pos -> SMODS falls back to the base-game blind chip sprite.
SMODS.Blind {
    key = 'hoglin',
    loc_txt = {
        name = "The Hoglin",
        text = {
            "At the start of the round,",
            "removes 3 from your hands",
            "and discards at random"
        }
    },
    discovered = true,
    boss = {
        min = 2,
        max = 2
    },
    boss_colour = HEX('B06A52'),
    set_blind = function(self)
        local dh, dd = 0, 0 -- amounts to remove from hands / discards
        for _ = 1, 3 do
            local hands_proj = G.GAME.current_round.hands_left - dh
            local discards_proj = G.GAME.current_round.discards_left - dd
            local can_hand = hands_proj > 1 -- always keep at least 1 hand
            local can_discard = discards_proj > 0
            if not can_hand and not can_discard then break end

            local take_hand
            if can_hand and can_discard then
                take_hand = pseudorandom(pseudoseed('hoglin')) < 0.5
            else
                take_hand = can_hand
            end
            if take_hand then dh = dh + 1 else dd = dd + 1 end
        end

        self.hoglin_dh, self.hoglin_dd = dh, dd
        if dh > 0 then ease_hands_played(-dh) end
        if dd > 0 then ease_discard(-dd) end
    end,
    disable = function(self)
        if self.hoglin_dh and self.hoglin_dh > 0 then ease_hands_played(self.hoglin_dh) end
        if self.hoglin_dd and self.hoglin_dd > 0 then ease_discard(self.hoglin_dd) end
        self.hoglin_dh, self.hoglin_dd = nil, nil
    end
}
