-- Placeholder art: no atlas/pos -> SMODS falls back to the base-game blind chip sprite.
SMODS.Blind {
    key = 'four_horsemen',
    loc_txt = {
        name = "The Four Horsemen",
        text = {
            "Debuff 6 random cards,",
            "{C:attention}-1{} hand, {C:attention}-1{} discard,",
            "destroy all consumables"
        }
    },
    discovered = true,
    boss = {
        min = 2,
        max = 2
    },
    boss_colour = HEX('6E1414'),
    set_blind = function(self)
        -- mark 6 random deck cards to be debuffed (recalc_debuff picks them up,
        -- and the base set_blind runs debuff_card on every card right after this).
        local pool = {}
        for _, c in ipairs(G.playing_cards) do pool[#pool + 1] = c end
        for _ = 1, math.min(6, #pool) do
            local c, k = pseudorandom_element(pool, pseudoseed('four_horsemen'))
            if not c then break end
            c.ability.four_horsemen = true
            table.remove(pool, k)
        end

        -- one fewer hand and discard
        ease_hands_played(-1)
        ease_discard(-1)

        -- destroy every consumable
        G.E_MANAGER:add_event(Event({
            trigger = 'after',
            delay = 0.2,
            func = function()
                if G.consumeables then
                    for i = #G.consumeables.cards, 1, -1 do
                        G.consumeables.cards[i]:start_dissolve()
                    end
                end
                return true
            end
        }))
    end,
    recalc_debuff = function(self, card, from_blind)
        return card.ability and card.ability.four_horsemen and true or false
    end,
    disable = function(self)
        for _, c in ipairs(G.playing_cards or {}) do
            if c.ability and c.ability.four_horsemen then c.ability.four_horsemen = nil end
        end
        ease_hands_played(1)
        ease_discard(1)
    end
}
