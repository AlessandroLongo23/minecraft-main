-- Basalt-Deltas-exclusive boss blind (Nether). Same additive in_pool mechanic as
-- forest_guardian: eligible only while the current biome is Basalt Deltas; base blinds stay
-- always-eligible. PLACEHOLDER ART: reuses the Blaze sprite cell (atlas 'blinds', y = 5).
SMODS.Blind {
    key = 'magma_lord',
    loc_txt = {
        name = "The Magma Lord",
        text = {
            "Erupts only in the",
            "{C:attention}Basalt Deltas{}."
        }
    },
    discovered = true,
    boss = {
        min = 2,
        max = 10
    },
    pos = {
        x = 0,
        y = 5
    },
    atlas = 'blinds',
    boss_colour = HEX('C0501A'),
    in_pool = function(self)
        return (PB_UTIL.biome_blind_in_pool and PB_UTIL.biome_blind_in_pool('basalt_deltas')) or false
    end
}
