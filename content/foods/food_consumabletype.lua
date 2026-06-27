-- Food consumable type + the six food cards. Unlike resources, foods DO appear in the shop
-- (shop_rate > 0) and in the collection, and are generated into the food booster packs.

SMODS.ConsumableType {
    key = 'balacraft_food',
    primary_colour = HEX('c0392b'),
    secondary_colour = HEX('e67e22'),
    collection_rows = { 3, 3 },
    shop_rate = 2,                       -- appears in the shop (tunable; ~half a Tarot's rate)
    default = 'c_balacraft_food_carrot',
    loc_txt = { name = 'Food', collection = 'Food' },
}

for _, f in ipairs(PB_UTIL.FOODS) do
    local food = f
    SMODS.Consumable {
        key = 'food_' .. food.id,
        set = 'balacraft_food',
        atlas = 'bc_food_cards',
        pos = food.pos,
        cost = food.cost,
        discovered = true,
        loc_txt = {
            name = food.name,
            text = {
                'Restores {C:attention}' .. food.hunger .. '{} hunger',
                '{C:inactive}(keeps you fed; well-fed heals)',
            },
        },
        -- Can't eat at full hunger (Minecraft-style); avoids wasting a card for nothing.
        can_use = function(self, card)
            return PB_UTIL.get_hunger() < PB_UTIL.get_max_hunger()
        end,
        use = function(self, card, area, copier)
            PB_UTIL.add_hunger(food.hunger)
        end,
    }
end
