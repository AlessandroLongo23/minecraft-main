-- "Loot Chest" booster: spawns the 6 ores so the player picks one.
-- Uses the card atlas's diamond cell as a placeholder pack image (cosmetic, swap later).

SMODS.Booster {
    key = 'resource_pack',
    atlas = 'bc_resource_cards',
    pos = { x = 2, y = 1 }, -- diamond cell as placeholder pack art
    config = { choose = 1, extra = 6 },
    cost = 4,
    weight = 1,
    loc_txt = {
        name = 'Loot Chest',
        text = { 'Choose {C:attention}1{} of up to', '{C:attention}6{} Minecraft resources.' },
    },
    create_card = function(self, card, i)
        local ore = PB_UTIL.RESOURCES[i] or PB_UTIL.RESOURCES[1]
        return create_card('balacraft_resource', G.pack_cards, nil, nil, true, true,
            'c_balacraft_res_' .. ore.id, 'bc_respack')
    end,
}
