-- Placeholder art: no atlas/pos -> SMODS falls back to the base-game blind chip sprite.
SMODS.Blind {
    key = 'guardian',
    loc_txt = {
        name = "The Guardian",
        text = {
            "Destroys cards that",
            "stayed in hand for",
            "2 played hands"
        }
    },
    discovered = true,
    boss = {
        min = 2,
        max = 2
    },
    boss_colour = HEX('5A8E8B'),
    set_blind = function(self)
        -- reset the per-card "hands survived" counters
        for _, c in ipairs(G.playing_cards or {}) do
            if c.ability then c.ability.guardian_age = nil end
        end
    end,
    press_play = function(self)
        -- Played cards are still in G.hand at press_play; the ones staying in hand
        -- are G.hand.cards minus the highlighted (played) cards.
        local played = {}
        for _, c in ipairs(G.hand.highlighted) do played[c] = true end

        local to_destroy = {}
        for _, c in ipairs(G.hand.cards) do
            if not played[c] then
                c.ability.guardian_age = (c.ability.guardian_age or 0) + 1
                if c.ability.guardian_age >= 2 then
                    to_destroy[#to_destroy + 1] = c
                end
            end
        end

        if #to_destroy > 0 then
            G.E_MANAGER:add_event(Event({
                trigger = 'after',
                delay = 0.3,
                func = function()
                    for _, c in ipairs(to_destroy) do c:start_dissolve() end
                    G.GAME.blind:wiggle()
                    return true
                end
            }))
        end
    end
}
