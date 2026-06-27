-- Resource registry + atlases.

-- `drop_class` (gathered only) splits the loot economy: 'ore' = the mined minerals that flow
-- through random_ore_of_tier (blind drops, resource packs, Ore-Block cards, villager bundles);
-- 'mob' = mob/creature materials (string, feather, flint, …) that DON'T dilute the ore pools --
-- they arrive via themed blinds (PB_UTIL.BLIND_MOB_DROPS) + an additive loot roll + Fishing Rod.
-- 'refined' = furnace/craft outputs only (iron/gold/glass); 'special' = granted ONLY by bespoke
-- code, never by any pool (Obsidian/Ender Pearl/Blaze Powder -- the Nether/End progression items).
-- Every pool loop filters on drop_class=='ore' or =='mob', so 'special'/'refined' are excluded from
-- all of them. Missing drop_class is treated as 'ore'.
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
    { id = 'redstone',    name = 'Redstone',    kind = 'gathered', tier = 3, drop_class = 'ore', pos = { x = 1, y = 6 } },
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
    -- Glass chain: Sand is a gathered tier-1 ore (mine/drop/pack), smelted in the Furnace into Glass
    -- (drop_class='refined' -> furnace-output only, like iron/gold). Glass crafts the Glass Sheet at
    -- the Crafting Table (content/resources/recipes.lua). See PB_UTIL.SMELTS in utilities/furnace.lua.
    -- Sand stays a tier-1 ore (drops/packs/villager/seals/tags) for the glass chain, but `no_oreblock`
    -- keeps it OUT of the minable Ore-Block cards (PB_UTIL.is_oreblock_resource) -- it is not a block you mine.
    { id = 'sand',         name = 'Sand',         kind = 'gathered', tier = 1, drop_class = 'ore', no_oreblock = true, pos = { x = 2, y = 6 } },
    { id = 'glass',        name = 'Glass',        kind = 'gathered', tier = 1, drop_class = 'refined', pos = { x = 0, y = 7 } },
    -- Nether/End progression items (drop_class='special' -> never in any pool; granted only by code).
    -- obsidian   : stays drop_class='special' (NEVER in the drop/pack/villager/seal/tag pools), but
    --              `oreblock = true` opts it into the minable Ore-Block cards -- so the main way to get
    --              it is to mine an Obsidian block, gated to a DIAMOND pickaxe (ORE_MINING_LEVEL below,
    --              tier=3 spawn depth). Bespoke grants remain: Cave blinds (rare) + a Ruined Portal beaten
    --              WITHOUT lighting it. Spent (1) to light a Ruined Portal with Flint & Steel (structures.lua).
    -- ender_pearl: drops from the Enderman blind + while in the End (utilities/resources.lua).
    -- blaze_powder: drops from the Blaze blind + while in the Nether. Pearl+Powder craft the Eye of Ender.
    { id = 'obsidian',     name = 'Obsidian',     kind = 'gathered', tier = 3, drop_class = 'special', oreblock = true, pos = { x = 1, y = 7 } },
    { id = 'ender_pearl',  name = 'Ender Pearl',  kind = 'gathered', drop_class = 'special', pos = { x = 2, y = 7 } },
    { id = 'blaze_powder', name = 'Blaze Powder', kind = 'gathered', drop_class = 'special', pos = { x = 0, y = 8 } },
    -- ── Brewing ingredients (potions feature) ──────────────────────────────────
    -- Raw drops: dimension-themed, drop_class='special' so they stay out of the ore/mob pools and are
    -- granted only by code (PB_UTIL.grant_brewing_drop, a Blind:defeat wrap in utilities/brewing.lua,
    -- keyed by the active dimension -- Overworld farm items vs Nether/End items).
    { id = 'nether_wart',    name = 'Nether Wart',    kind = 'gathered', tier = 2, drop_class = 'special', pos = { x = 1, y = 8 } },
    { id = 'sugar_cane',     name = 'Sugar Cane',     kind = 'gathered', tier = 1, drop_class = 'special', pos = { x = 2, y = 8 } },
    { id = 'melon_slice',    name = 'Melon Slice',    kind = 'gathered', tier = 1, drop_class = 'special', pos = { x = 0, y = 9 } },
    { id = 'carrot',         name = 'Carrot',         kind = 'gathered', tier = 1, drop_class = 'special', pos = { x = 1, y = 9 } },
    { id = 'brown_mushroom', name = 'Brown Mushroom', kind = 'gathered', tier = 1, drop_class = 'special', pos = { x = 2, y = 9 } },
    { id = 'ghast_tear',     name = 'Ghast Tear',     kind = 'gathered', tier = 3, drop_class = 'special', pos = { x = 0, y = 10 } },
    { id = 'blaze_rod',      name = 'Blaze Rod',      kind = 'gathered', tier = 3, drop_class = 'special', pos = { x = 1, y = 10 } },
    { id = 'glowstone_dust', name = 'Glowstone Dust', kind = 'gathered', tier = 2, drop_class = 'special', pos = { x = 2, y = 10 } },
    { id = 'dragon_breath',  name = "Dragon's Breath", kind = 'gathered', tier = 4, drop_class = 'special', pos = { x = 0, y = 11 } },
    -- Crafted intermediates (kind='crafted'): craft-only, excluded from every drop/pack pool (icon cell only).
    { id = 'glass_bottle',         name = 'Glass Bottle',         kind = 'crafted', pos = { x = 1, y = 11 } },
    { id = 'water_bottle',         name = 'Water Bottle',         kind = 'crafted', pos = { x = 2, y = 11 } },
    { id = 'sugar',                name = 'Sugar',                kind = 'crafted', pos = { x = 0, y = 12 } },
    { id = 'glistering_melon',     name = 'Glistering Melon',     kind = 'crafted', pos = { x = 1, y = 12 } },
    { id = 'golden_carrot',        name = 'Golden Carrot',        kind = 'crafted', pos = { x = 2, y = 12 } },
    { id = 'fermented_spider_eye', name = 'Fermented Spider Eye', kind = 'crafted', pos = { x = 0, y = 13 } },
    { id = 'awkward_potion',       name = 'Awkward Potion',       kind = 'crafted', pos = { x = 1, y = 13 } },
    -- ── Enchanting book chain (enchanting-table feature) ────────────────────────
    -- Leather: a surface (Night) mob drop -- drop_class='mob'+location='surface' auto-pools it via
    -- PB_UTIL.random_mob_drop (no extra wiring). Paper + Book are craft-only intermediates: Book is
    -- consumed at the Enchanting Table to generate enchant books. MC chain: Sugar Cane -> Paper;
    -- 3 Paper + Leather -> Book.
    { id = 'leather', name = 'Leather', kind = 'gathered', tier = 1, drop_class = 'mob', location = 'surface', pos = { x = 2, y = 13 } },
    { id = 'paper',   name = 'Paper',   kind = 'crafted', pos = { x = 0, y = 14 } },
    { id = 'book',    name = 'Book',    kind = 'crafted', pos = { x = 1, y = 14 } },
}

-- Lookup by id (used by drops/UI).
PB_UTIL.RESOURCE_BY_ID = {}
for _, r in ipairs(PB_UTIL.RESOURCES) do PB_UTIL.RESOURCE_BY_ID[r.id] = r end

-- ── Mining levels (Minecraft-faithful) ──────────────────────────────────────
-- Each ore-block requires a pickaxe (or axe) of at least this MINING LEVEL to extract (see
-- utilities/mining.lua). Tool material -> mining level lives on the tool registry (content/tools/
-- registry.lua MATERIALS): wood=0, cobblestone/stone=1, iron=2, gold=0 (the MC golden-pickaxe
-- quirk), diamond=3, netherite=4. The `tier` field (spawn budget) is deliberately DECOUPLED from
-- the gate -- e.g. lapis is tier-3 depth but stone-mineable (lvl 1); raw_gold is tier-2 but iron-
-- gated (lvl 2) -- matching the real game. Wood is absent: it is harvested by the Axe / bare hand,
-- never the pickaxe. An ore not listed defaults to level 0 (any tool can mine it).
PB_UTIL.ORE_MINING_LEVEL = {
    cobblestone = 0, coal = 0, sand = 0,
    raw_iron = 1, lapis = 1,
    raw_gold = 2, redstone = 2, diamond = 2, emerald = 2,
    netherite = 3,
    obsidian = 3,   -- DIAMOND pickaxe (lvl 3) or better -- MC-faithful (obsidian needs a diamond pick).
}

-- True if a tool of `tool_level` can mine `ore_id`. Wood is never pickaxe-mineable.
function PB_UTIL.can_mine(tool_level, ore_id)
    if ore_id == 'wood' then return false end
    local req = PB_UTIL.ORE_MINING_LEVEL[ore_id] or 0
    return (tonumber(tool_level) or 0) >= req
end

-- True if resource `r` should appear as a minable Ore-Block card. Drives both the center
-- registration (content/card_enhancements/blocks.lua) and the spawn roll
-- (PB_UTIL.random_oreblock_of_tier, utilities/resources.lua), so the two never disagree.
-- Eligible = a gathered ore (drop_class='ore') NOT flagged `no_oreblock` (Sand), PLUS any resource
-- explicitly opted in with `oreblock = true` (Obsidian, which is otherwise drop_class='special').
function PB_UTIL.is_oreblock_resource(r)
    if not (r and r.kind == 'gathered') then return false end
    if r.no_oreblock then return false end
    return r.drop_class == 'ore' or r.oreblock == true
end

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
