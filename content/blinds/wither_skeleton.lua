-- Placeholder art: no atlas/pos -> SMODS falls back to the base-game blind chip sprite.
SMODS.Blind {
    key = 'wither_skeleton',
    loc_txt = {
        name = "The Wither Skeleton",
        text = {
            "After scoring,",
            "destroy a random",
            "consumable"
        }
    },
    discovered = true,
    boss = {
        min = 2,
        max = 2
    },
    boss_colour = HEX('2B2B2B'),
    press_play = function(self)
        G.E_MANAGER:add_event(Event({
            trigger = 'after',
            delay = 0.3,
            func = function()
                if G.consumeables and #G.consumeables.cards > 0 then
                    local c = pseudorandom_element(G.consumeables.cards, pseudoseed('wither_skeleton'))
                    if c then
                        c:start_dissolve()
                        G.GAME.blind:wiggle()
                    end
                end
                return true
            end
        }))
    end
}
