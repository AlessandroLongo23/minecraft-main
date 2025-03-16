SMODS.Atlas{
    key = 'overworldDeck',
    path = 'OverworldDeck.png',
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
            '{C:red}Waterdrop Joker{}.'
        },
    },

    apply = function ()
        G.E_MANAGER:add_event(Event({
            func = function ()
                joker_add('j_minecraft_0164')
                
                -- for _, card in ipairs(G.playing_cards) do
                --     card:set_seal('Purple', true, true)
                -- end

                return true
            end
        }))
    end,
}