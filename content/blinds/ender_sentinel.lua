-- Central-End-exclusive boss blind (End). Same additive in_pool mechanic as the other biome
-- bosses: eligible only while the current biome is Central End. PLACEHOLDER ART: reuses the
-- Enderman sprite cell (atlas 'blinds', y = 3).
SMODS.Blind {
    key = 'ender_sentinel',
    loc_txt = {
        name = "The Ender Sentinel",
        text = {
            "Guards only the",
            "{C:attention}Central End{}."
        }
    },
    discovered = true,
    boss = {
        min = 2,
        max = 10
    },
    pos = {
        x = 0,
        y = 3
    },
    atlas = 'blinds',
    boss_colour = HEX('7A28B0'),
    in_pool = function(self)
        return (PB_UTIL.biome_blind_in_pool and PB_UTIL.biome_blind_in_pool('central_end')) or false
    end
}
