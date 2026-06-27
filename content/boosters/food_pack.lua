-- Normal Food Pack. Mirrors content/boosters/resource_pack.lua.
SMODS.Booster {
    key = 'food_pack',
    atlas = 'bc_food_cards',
    pos = { x = 0, y = 0 },              -- carrot cell (placeholder pack art)
    config = { choose = 1, extra = 3 },
    cost = 4,
    weight = 1,
    loc_txt = {
        name = 'Food Pack',
        group_name = 'Food Pack',  -- open-pack title; without it the screen shows "ERROR"
        text = { 'Choose {C:attention}1{} of up to', '{C:attention}3{} foods.' },
    },
    create_card = function(self, card, i)
        return PB_UTIL.create_food_pack_card(card, i, self.config.extra)
    end,
}
