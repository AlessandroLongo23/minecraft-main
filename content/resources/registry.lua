-- Resource registry + atlases.

PB_UTIL.RESOURCES = {
    { id = 'wood',        kind = 'gathered', tier = 1, pos = { x = 0, y = 0 } },
    { id = 'cobblestone', kind = 'gathered', tier = 1, pos = { x = 1, y = 0 } },
    { id = 'coal',        kind = 'gathered', tier = 1, pos = { x = 2, y = 0 } },
    { id = 'iron',        kind = 'gathered', tier = 2, pos = { x = 0, y = 1 } },
    { id = 'gold',        kind = 'gathered', tier = 2, pos = { x = 1, y = 1 } },
    { id = 'diamond',     kind = 'gathered', tier = 3, pos = { x = 2, y = 1 } },
    { id = 'sticks',      kind = 'crafted',            pos = { x = 0, y = 2 } },
}

-- Lookup by id (used by drops/UI).
PB_UTIL.RESOURCE_BY_ID = {}
for _, r in ipairs(PB_UTIL.RESOURCES) do PB_UTIL.RESOURCE_BY_ID[r.id] = r end

-- Card sheet (71x95) for the booster pack; icon sheet (34x34) for the panel.
PB_UTIL.card_atlas = SMODS.Atlas {
    key = 'bc_resource_cards', path = 'resource_cards.png', px = 71, py = 95,
}
PB_UTIL.icon_atlas = SMODS.Atlas {
    key = 'bc_resource_icons', path = 'resource_icons.png', px = 34, py = 34,
}
