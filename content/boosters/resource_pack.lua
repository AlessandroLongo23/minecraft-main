-- "Loot Chest" booster (Normal): show 3 ores, pick 1.
-- Placeholder art: Coal cell from the resource card atlas (cosmetic, swap later).
SMODS.Booster {
    key = 'resource_pack',
    atlas = 'bc_resource_cards',
    pos = { x = 2, y = 0 }, -- coal cell (placeholder pack art)
    config = { choose = 1, extra = 3 },
    cost = 4,
    weight = 1,
    loc_txt = {
        name = 'Loot Chest',
        text = { 'Choose {C:attention}1{} of up to', '{C:attention}3{} Minecraft resources.' },
    },
    create_card = function(self, card, i)
        return PB_UTIL.create_resource_pack_card(card, i, self.config.extra)
    end,
}
