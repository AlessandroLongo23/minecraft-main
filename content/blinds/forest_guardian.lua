-- Forest-exclusive boss blind. Proves the ADDITIVE biome boss-pool mechanic: it declares
-- `in_pool`, so get_new_boss (functions/common_events.lua) only makes it eligible while the
-- current biome is Forest. The shared base blinds declare no in_pool, so they stay
-- always-eligible -- this boss is *added* to the pool in Forest, never replacing it.
--
-- PLACEHOLDER ART: reuses the Spider sprite cell (atlas 'blinds', y = 4). A dedicated frame
-- is a Phase 4 art task (see docs/biomes-and-dimensions.md). Mechanic is fully wired.
SMODS.Blind {
    key = 'forest_guardian',
    loc_txt = {
        name = "The Overgrowth",
        text = {
            "Only stirs in the",
            "{C:attention}Forest{}."
        }
    },
    discovered = true,
    -- Broad ante range; biome gating is done by in_pool, not the ante window.
    boss = {
        min = 2,
        max = 10
    },
    pos = {
        x = 0,
        y = 4
    },
    atlas = 'blinds',
    boss_colour = HEX('2E5E27'),
    in_pool = function(self)
        -- Guarded: if biomes are disabled the helper is absent, so this boss simply
        -- never enters the pool (rather than erroring in get_new_boss).
        return (PB_UTIL.biome_blind_in_pool and PB_UTIL.biome_blind_in_pool('forest')) or false
    end
}
