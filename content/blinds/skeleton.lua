SMODS.Blind {
    key = 'skeleton',
    loc_txt = {
        name = "The Skeleton",
        text = { 
            "Destroy a random card",
            "in hand after scoring"
        }
    },
    discovered = true,
    boss = {
        min = 1,
        max = 1
    },
    pos = {
        x = 0,
        y = 0
    },
    atlas = 'blinds',
    boss_colour = HEX('494949'),
    press_play = function()
        G.E_MANAGER:add_event(Event({
            trigger = 'after',
            delay = 0.1,
            func = function ()
                local dCard = pseudorandom_element(G.hand.cards, pseudoseed('gluttony'))
                dCard:start_dissolve()
                return true
            end
        }))
    end
}