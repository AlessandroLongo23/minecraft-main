-- Hidden ConsumableType used ONLY to populate the resource booster pack.
-- These never appear in the collection, shop, or normal pools.

SMODS.ConsumableType {
    key = 'balacraft_resource',
    primary_colour = HEX('6b5840'),
    secondary_colour = HEX('8b7765'),
    collection_rows = { 3, 3 },
    shop_rate = 0,
    no_collection = true,
    default = 'c_balacraft_res_wood',
    loc_txt = { name = 'Resource', collection = 'Resources' },
}

-- Display metadata for each ore (name shown on the pack card's tooltip).
local ORE_LOC = {
    wood        = 'Wood',
    cobblestone = 'Cobblestone',
    coal        = 'Coal',
    iron        = 'Iron',
    gold        = 'Gold',
    diamond     = 'Diamond',
}

for _, r in ipairs(PB_UTIL.RESOURCES) do
    if r.kind == 'gathered' then
        local id = r.id
        SMODS.Consumable {
            key = 'res_' .. id,
            set = 'balacraft_resource',
            atlas = 'bc_resource_cards',
            pos = r.pos,
            cost = 0,
            discovered = true,
            no_collection = true,
            loc_txt = {
                name = ORE_LOC[id],
                text = { 'Adds {C:attention}1{} ' .. ORE_LOC[id], 'to your resources.' },
            },
            can_use = function(self, card) return true end,
            use = function(self, card, area, copier)
                PB_UTIL.add_resource(id, 1)
            end,
            in_pool = function(self, args) return false end,
        }
    end
end
