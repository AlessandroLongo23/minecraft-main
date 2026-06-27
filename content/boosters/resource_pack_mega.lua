-- "Mega Loot Chest" booster: show 5 ores, pick 2.
-- Placeholder art: Diamond cell from the resource card atlas (cosmetic, swap later).
SMODS.Booster {
    key = 'resource_pack_mega',
    atlas = 'bc_resource_cards',
    pos = { x = 2, y = 1 }, -- diamond cell (placeholder pack art)
    config = { choose = 2, extra = 5 },
    cost = 8,
    weight = 0.25,
    loc_txt = {
        name = 'Mega Loot Chest',
        group_name = 'Mega Loot Chest',  -- open-pack title; without it the screen shows "ERROR"
        text = { 'Choose {C:attention}2{} of up to', '{C:attention}5{} Minecraft resources.' },
    },
    create_card = function(self, card, i)
        return PB_UTIL.create_resource_pack_card(card, i, self.config.extra)
    end,
}
