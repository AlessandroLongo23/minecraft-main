-- Potion Pack. Mirrors content/boosters/food_pack.lua: reuses the bc_potion_cards atlas for the
-- pack art (placeholder cell) and hands out plain (un-modified) potions to choose from. Brewing
-- is the primary source; this pack is the secondary one (the user opted to keep both).
SMODS.Booster {
    key = 'potion_pack',
    atlas = 'bc_potion_cards',
    pos = { x = 0, y = 1 },              -- healing cell (placeholder pack art)
    config = { choose = 1, extra = 3 },
    cost = 4,
    weight = 1,
    loc_txt = {
        name = 'Potion Pack',
        group_name = 'Potion Pack',      -- open-pack title; without it the screen shows "ERROR"
        text = { 'Choose {C:attention}1{} of up to', '{C:attention}3{} potions.' },
    },
    create_card = function(self, card, i)
        return PB_UTIL.create_potion_pack_card(card, i, self.config.extra)
    end,
}
