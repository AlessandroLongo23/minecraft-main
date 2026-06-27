-- End deck: starts the run directly in a random End biome. Locked until the End Portal
-- voucher has been bought PB_UTIL.PORTAL_UNLOCK times total across all runs
-- (utilities/progression.lua). Mirror of the Nether deck.
SMODS.Atlas {
    key = 'endDeck',
    path = 'EndDeck.png',
    px = 71,
    py = 95,
}

SMODS.Back {
    name = 'End',
    key = 'end',
    atlas = 'endDeck',
    pos = { x = 0, y = 0 },
    loc_txt = {
        name = 'End Deck',
        text = {
            'Start the run in a',
            'random {C:attention}End{} biome.',
        },
    },
    unlocked = (PB_UTIL.progression_unlocks_deck and PB_UTIL.progression_unlocks_deck('end')) or false,
    discovered = true,
    apply = function(self)
        G.E_MANAGER:add_event(Event({
            func = function()
                if PB_UTIL.enter_dimension then PB_UTIL.enter_dimension('end') end
                return true
            end,
        }))
    end,
}
