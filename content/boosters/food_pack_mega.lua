-- Mega Food Pack. Mirrors content/boosters/resource_pack_mega.lua.
SMODS.Booster {
    key = 'food_pack_mega',
    atlas = 'bc_food_cards',
    pos = { x = 2, y = 1 },              -- cooked porkchop cell
    config = { choose = 2, extra = 5 },
    cost = 8,
    weight = 0.25,
    loc_txt = {
        name = 'Mega Food Pack',
        group_name = 'Mega Food Pack',  -- open-pack title; without it the screen shows "ERROR"
        text = { 'Choose {C:attention}2{} of up to', '{C:attention}5{} foods.' },
    },
    create_card = function(self, card, i)
        return PB_UTIL.create_food_pack_card(card, i, self.config.extra)
    end,
}
