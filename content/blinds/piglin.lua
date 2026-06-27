-- Placeholder art: no atlas/pos -> SMODS falls back to the base-game blind chip sprite.
SMODS.Blind {
    key = 'piglin',
    loc_txt = {
        name = "The Piglin",
        text = {
            "After scoring, played cards",
            "become 2s if your deck has",
            "fewer than 2 Gold cards"
        }
    },
    discovered = true,
    boss = {
        min = 2,
        max = 8
    },
    boss_colour = HEX('D2A24C'),
    -- context.after fires after the hand is scored, so the poker hand is already locked in.
    -- But the chip-tally animation events are queued earlier in evaluate_play, so we must
    -- *queue* the conversion (not run it inline) for it to land after that animation finishes.
    calculate = function(self, blind, context)
        if blind.disabled or not context.after then return end

        local gold = 0
        for _, c in ipairs(G.playing_cards) do
            if c.config and c.config.center == G.P_CENTERS.m_gold then gold = gold + 1 end
        end
        if gold >= 2 then return end

        -- Snapshot the played cards now; G.play.cards is emptied to the discard pile
        -- before the deferred event below runs.
        local played = {}
        for _, c in ipairs(context.full_hand or {}) do played[#played + 1] = c end
        if #played == 0 then return end

        G.E_MANAGER:add_event(Event({
            trigger = 'after',
            delay = 0.3,
            func = function()
                local changed = false
                for _, c in ipairs(played) do
                    if c.base.value ~= '2' then
                        SMODS.change_base(c, nil, '2') -- keep suit, set rank to 2
                        c:juice_up(0.3, 0.3)
                        changed = true
                    end
                end
                if changed then
                    blind:wiggle()
                    play_sound('tarot1', 1, 0.4)
                end
                return true
            end
        }))
    end
}
