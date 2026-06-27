-- Per-biome start-decks: one SMODS.Back for each OVERWORLD biome. Each starts the run in that
-- exact biome and is locked until you've won PB_UTIL.BIOME_DECK_UNLOCK antes (boss blinds) in
-- that biome, cumulative across all runs (utilities/progression.lua; the count is incremented
-- by the Blind:defeat wrap in utilities/biomes.lua).
--
-- Data-driven from PB_UTIL.BIOMES so it stays in sync with the registry. The deck's center key
-- is the biome id (=> 'b_balacraft_<id>'), which is what try_unlock_biome_deck looks up.
-- Nether/End biomes are reached via their dimension decks instead (no per-biome decks there).

for _, b in ipairs(PB_UTIL.BIOMES or {}) do
    -- ritual_only biomes (Stronghold) are never a normal start-deck: they're only reached via the
    -- Eye-of-Ender trail, so skip them here (they also have no deck-splash cell).
    if b.dimension == 'overworld' and not b.ritual_only then
        local bid, bname, bx = b.id, b.name, b.pos.x
        SMODS.Back {
            name = bname,
            key = bid,
            atlas = 'bc_biome_decks',
            pos = { x = bx, y = 0 },
            loc_txt = {
                name = bname .. ' Deck',
                text = {
                    'Start the run in',
                    'the {C:attention}' .. bname .. '{} biome.',
                },
            },
            unlocked = (PB_UTIL.progression_unlocks_biome_deck and PB_UTIL.progression_unlocks_biome_deck(bid)) or false,
            discovered = true,
            apply = function(self)
                G.E_MANAGER:add_event(Event({
                    func = function()
                        if PB_UTIL.start_in_biome then PB_UTIL.start_in_biome(bid) end
                        -- DEV/testing convenience: the Plains deck starts with two Torches so the
                        -- shop-peek consumable can be exercised without crafting it each run.
                        if bid == 'plains' then
                            consumable_add('c_balacraft_torch')
                            consumable_add('c_balacraft_torch')
                        end
                        return true
                    end,
                }))
            end,
        }
    end
end
