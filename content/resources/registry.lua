-- Resource registry + atlases.

-- `drop_class` (gathered only) splits the loot economy: 'ore' = the mined minerals that flow
-- through random_ore_of_tier (blind drops, resource packs, Ore-Block cards, villager bundles);
-- 'mob' = mob/creature materials (string, feather, flint, …) that DON'T dilute the ore pools --
-- they arrive via themed blinds (PB_UTIL.BLIND_MOB_DROPS) + an additive loot roll + Fishing Rod.
-- The ore-only loops filter `drop_class ~= 'mob'`. Missing drop_class is treated as 'ore'.
--
-- `location` (mob drops only) gates which environment blind can drop a mob material:
--   'both'    -> droppable from Night (surface) AND Cave (underground)
--   'surface' -> Night only        'cave' -> Cave only
-- The Night/Cave blinds are the reskinned vanilla Small/Big (see utilities/functions.lua).
-- Missing location is treated as 'both' (so the Wave-1 archery drops need no edit).
PB_UTIL.RESOURCES = {
    { id = 'wood',        name = 'Wood',        kind = 'gathered', tier = 1, drop_class = 'ore', pos = { x = 0, y = 0 } },
    { id = 'cobblestone', name = 'Cobblestone', kind = 'gathered', tier = 1, drop_class = 'ore', pos = { x = 1, y = 0 } },
    { id = 'coal',        name = 'Coal',        kind = 'gathered', tier = 1, drop_class = 'ore', pos = { x = 2, y = 0 } },
    -- iron + gold are SMELT-ONLY (drop_class='refined'): they no longer drop/mine/pack/trade -- you
    -- get the raw_* form (below) and smelt it in the Furnace. The ore-only loops filter drop_class=='ore'.
    { id = 'iron',        name = 'Iron',        kind = 'gathered', tier = 2, drop_class = 'refined', pos = { x = 0, y = 1 } },
    { id = 'gold',        name = 'Gold',        kind = 'gathered', tier = 2, drop_class = 'refined', pos = { x = 1, y = 1 } },
    { id = 'diamond',     name = 'Diamond',     kind = 'gathered', tier = 3, drop_class = 'ore', pos = { x = 2, y = 1 } },
    { id = 'emerald',     name = 'Emerald',     kind = 'gathered', tier = 2, drop_class = 'ore', pos = { x = 1, y = 2 } },
    { id = 'netherite',   name = 'Netherite',   kind = 'gathered', tier = 4, drop_class = 'ore', pos = { x = 2, y = 2 } },
    { id = 'sticks',      name = 'Sticks',      kind = 'crafted',                                pos = { x = 0, y = 2 } },
    { id = 'lapis',       name = 'Lapis Lazuli', kind = 'gathered', tier = 3, drop_class = 'ore', pos = { x = 0, y = 3 } },
    -- Wave 1 (Archery) mob drops: gathered loot, but drop_class='mob' keeps them out of the ore
    -- pools. Each is justified by an end-item: string -> Bow/Fishing Rod/Crossbow, feather+flint -> Arrow.
    { id = 'string',      name = 'String',      kind = 'gathered', tier = 1, drop_class = 'mob', location = 'both', pos = { x = 1, y = 3 } },
    { id = 'feather',     name = 'Feather',     kind = 'gathered', tier = 1, drop_class = 'mob', location = 'both', pos = { x = 2, y = 3 } },
    { id = 'flint',       name = 'Flint',       kind = 'gathered', tier = 1, drop_class = 'mob', location = 'both', pos = { x = 0, y = 4 } },
    -- Wave 2 (Night/Cave) mob drops. gunpowder/bone drop in both environments; spider_eye (Cave
    -- Spider) and glow_ink_sac (Glow Squid) are CAVE-EXCLUSIVE. Purposes: gunpowder->TNT/Firework,
    -- bone->Bone Meal (queued), spider_eye->brewing (queued); all four also gate tier-2/3 tool
    -- enchants (utilities/enchanting.lua). glow_ink_sac additionally crafts the Torch (its MC
    -- "light in the dark" identity -> the Cave's reveal item; recipes.lua key 'glow_torch').
    { id = 'gunpowder',    name = 'Gunpowder',    kind = 'gathered', tier = 1, drop_class = 'mob', location = 'both', pos = { x = 1, y = 4 } },
    { id = 'bone',         name = 'Bone',         kind = 'gathered', tier = 1, drop_class = 'mob', location = 'both', pos = { x = 2, y = 4 } },
    { id = 'spider_eye',   name = 'Spider Eye',   kind = 'gathered', tier = 1, drop_class = 'mob', location = 'cave', pos = { x = 0, y = 5 } },
    { id = 'glow_ink_sac', name = 'Glow Ink Sac', kind = 'gathered', tier = 1, drop_class = 'mob', location = 'cave', pos = { x = 1, y = 5 } },
    -- Raw ores (MC-faithful smelt set): mined/dropped as raw, smelted in the Furnace into iron/gold.
    -- drop_class='ore' so they flow through every ore pool (drops/packs/Ore-Blocks/villager) at tier 2.
    { id = 'raw_iron',     name = 'Raw Iron',     kind = 'gathered', tier = 2, drop_class = 'ore', pos = { x = 2, y = 5 } },
    { id = 'raw_gold',     name = 'Raw Gold',     kind = 'gathered', tier = 2, drop_class = 'ore', pos = { x = 0, y = 6 } },
}

-- Lookup by id (used by drops/UI).
PB_UTIL.RESOURCE_BY_ID = {}
for _, r in ipairs(PB_UTIL.RESOURCES) do PB_UTIL.RESOURCE_BY_ID[r.id] = r end

-- Card sheet (71x95, 3x3 grid) for the booster pack; icon sheet (34x34, 3x3 grid) for the panel.
PB_UTIL.card_atlas = SMODS.Atlas {
    key = 'bc_resource_cards', path = 'resource_cards.png', px = 71, py = 95,
}
PB_UTIL.icon_atlas = SMODS.Atlas {
    key = 'bc_resource_icons', path = 'resource_icons.png', px = 34, py = 34,
}
-- Ore-Block CARD faces (71x95). Dedicated atlas so the booster resource cards (bc_resource_cards,
-- centered item on a dark face) are untouched. Each cell is the genuine MC block texture tiled to
-- fill the card, clipped to the rounded card mask (so it never overflows), leaving the rank/suit/
-- pips readable on top. Built by assets/gen_ore_blocks.py; used by content/card_enhancements/blocks.lua.
PB_UTIL.ore_block_atlas = SMODS.Atlas {
    key = 'bc_ore_blocks', path = 'ore_blocks.png', px = 71, py = 95,
}
-- Bare, frameless emerald (16x16) used by the villager UI's emerald counter + prices.
PB_UTIL.emerald_atlas = SMODS.Atlas {
    key = 'bc_emerald', path = 'emerald_plain.png', px = 16, py = 16,
}
-- Bare, frameless lapis (16x16) used by the enchant bar's cost line (same style as the emerald).
PB_UTIL.lapis_atlas = SMODS.Atlas {
    key = 'bc_lapis', path = 'lapis_plain.png', px = 16, py = 16,
}
