-- "Jumbo Loot Chest" booster: show 5 ores, pick 1.
-- Placeholder art: Gold cell from the resource card atlas (cosmetic, swap later).
SMODS.Booster {
    key = 'resource_pack_jumbo',
    atlas = 'bc_resource_cards',
    pos = { x = 1, y = 1 }, -- gold cell (placeholder pack art)
    config = { choose = 1, extra = 5 },
    cost = 6,
    weight = 0.5,
    loc_txt = {
        name = 'Jumbo Loot Chest',
        text = { 'Choose {C:attention}1{} of up to', '{C:attention}5{} Minecraft resources.' },
    },
    create_card = function(self, card, i)
        return PB_UTIL.create_resource_pack_card(card, i, self.config.extra)
    end,
}
