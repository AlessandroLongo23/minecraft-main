SMODS.Blind {
    key = 'stray',
    loc_txt = {
        name = "The Stray",
        text = {
            "Mult is capped at the",
            "Mult of your previous",
            "played hand"
        }
    },
    discovered = true,
    boss = {
        min = 2,
        max = 2
    },
    pos = {
        x = 0,
        y = 7
    },
    atlas = 'blinds',
    boss_colour = HEX('4B6C6D'),
    set_blind = function(self)
        self.stray_prev_mult = nil -- no cap on the first hand
    end,
    modify_hand = function(self, cards, poker_hands, text, mult, hand_chips)
        local capped = mult
        local triggered = false
        if self.stray_prev_mult and mult > self.stray_prev_mult then
            capped = self.stray_prev_mult
            triggered = true
        end
        self.stray_prev_mult = capped -- this hand's applied Mult becomes the cap for the next
        return capped, hand_chips, triggered
    end
}
