-- Nether deck: starts the run directly in a random Nether biome. Locked until the Nether
-- Portal voucher has been bought PB_UTIL.PORTAL_UNLOCK times total across all runs
-- (utilities/progression.lua); the lifetime counter is the source of truth, re-read here at
-- registration, and unlock_card fires the in-run "Deck Unlocked" notification on the crossing.
SMODS.Atlas {
    key = 'netherDeck',
    path = 'NetherDeck.png',
    px = 71,
    py = 95,
}

SMODS.Back {
    name = 'Nether',
    key = 'nether',
    atlas = 'netherDeck',
    pos = { x = 0, y = 0 },
    loc_txt = {
        name = 'Nether Deck',
        text = {
            'Start the run in a',
            'random {C:attention}Nether{} biome.',
        },
    },
    -- Initial lock state from the persisted lifetime counter (guarded so it's simply locked
    -- if progression isn't loaded, e.g. biomes disabled).
    unlocked = (PB_UTIL.progression_unlocks_deck and PB_UTIL.progression_unlocks_deck('nether')) or false,
    discovered = true,
    apply = function(self)
        G.E_MANAGER:add_event(Event({
            func = function()
                if PB_UTIL.enter_dimension then PB_UTIL.enter_dimension('nether') end
                return true
            end,
        }))
    end,
}
