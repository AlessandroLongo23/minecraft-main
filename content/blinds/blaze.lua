SMODS.Blind {
    key = 'blaze',
    loc_txt = {
        name = "The Blaze",
        text = { 
            "After scoring,",
            "1 in 5 chance to",
            "destroy each card",
            "in played hand"
        }
    },
    discovered = true,
    boss = {
        min = 1,
        max = 1
    },
    pos = {
        x = 0,
        y = 5
    },
    atlas = 'blinds',
    boss_colour = HEX('FFC427'),
    press_play = function()
        G.E_MANAGER:add_event(Event({
            trigger = 'after',
            delay = 0.1,
            func = function ()
                for i = 1, #G.hand.cards do
                    local rand = pseudorandom('blaze')
                    if rand < 0.2 then
                        local dCard = G.hand.cards[i]
                        dCard:start_dissolve()
                    end
                end
                return true
            end
        }))
    end
}

-- 71VQ33YA
