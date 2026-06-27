-- Jumbo Food Pack. Mirrors content/boosters/resource_pack_jumbo.lua.
SMODS.Booster {
    key = 'food_pack_jumbo',
    atlas = 'bc_food_cards',
    pos = { x = 1, y = 1 },              -- cooked chicken cell
    config = { choose = 1, extra = 5 },
    cost = 6,
    weight = 0.5,
    loc_txt = {
        name = 'Jumbo Food Pack',
        group_name = 'Jumbo Food Pack',  -- open-pack title; without it the screen shows "ERROR"
        text = { 'Choose {C:attention}1{} of up to', '{C:attention}5{} foods.' },
    },
    create_card = function(self, card, i)
        return PB_UTIL.create_food_pack_card(card, i, self.config.extra)
    end,
}
