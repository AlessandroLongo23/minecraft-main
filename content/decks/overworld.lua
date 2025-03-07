SMODS.Atlas{
    key = 'overworldDeck',
    path = 'DepaDeck.png',
    px = 71,
    py = 95
}

SMODS.Back{
    name = 'Overworld',
    key = 'overworldDeck',
    atlas = 'overworldDeck',
    pos = {x = 0, y = 0},
    loc_txt = {
        name = 'Overworld Deck',
        text = {
            'Start with a',
            '{C:red}Depa Joker{}.'
        },
    },

    apply = function ()
        G.E_MANAGER:add_event(Event({
            func = function ()
                -- Add eternal Depa Joker
                joker_add('j_minecraft_depa')

                return true
            end
        }))
    end,
}