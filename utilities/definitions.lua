PB_UTIL.ENABLED_BLINDS = {
    'skeleton',
    'zombie',
    'creeper',
    'enderman',
    'spider',
    'blaze',
    'drowned',
    'ghast',
    'zombiepigman',
    'magmacube',
    'slime',
    'silverfish',
    'wither_skeleton',
    'husk',
    'phantom',
    'piglin',
    'hoglin',
    'guardian',
    'shulker',
    'stray',
    'witch',
    'four_horsemen',
    'forest_guardian',  -- biome-exclusive (Forest); gated by in_pool, see content/biomes/
    'magma_lord',       -- biome-exclusive (Nether / Basalt Deltas); gated by in_pool
    'ender_sentinel',   -- biome-exclusive (End / Central End); gated by in_pool

    -- 'ender_dragon',
    -- 'wither',
    -- 'elder_guardian',
    -- 'warden',
    -- 'raid',     -- deferred: multi-phase mechanic needs its own design
    -- 'mansion',
}

PB_UTIL.ENABLED_BOOSTERS = {
    'resource_pack',
    'resource_pack_jumbo',
    'resource_pack_mega',
}

PB_UTIL.ENABLED_DECKS = {
    'test',     -- DEV sandbox deck (replaces overworld); remove before public release
    'nether',
    'end',
    'biome_decks',  -- one start-deck per Overworld biome (looped; unlock = 10 antes won there)
    -- 'aether',
}

-- Enchanting books. 'registry' (ENCHANTS data + math helpers) loads BEFORE
-- 'enchant_consumabletype' (the 9 book cards). The enchanting logic + Enchant button UI
-- (utilities/enchanting.lua, enchanting_ui.lua) are loaded explicitly in main.lua.
PB_UTIL.ENABLED_ENHANCEMENTS = {
    'registry',
    'enchant_consumabletype',
}

-- Card editions applied through the Enchant flow (loaded with the enhancements block).
-- Sharpness is the card side of the dual-target Sharpness book (tool ×Mult / card +Mult).
PB_UTIL.ENABLED_EDITIONS = {
    'sharpness',    -- e_balacraft_sharpness_{1,2,3}  (Sharpness book -> card)
    'unbreaking',   -- e_balacraft_unbreaking         (Durability book -> card, flat)
    'lucky',        -- e_balacraft_lucky_{1,2,3}      (Fortune book -> card)
}

-- Balatro card enhancements ("block-cards") — DISTINCT from the Enchanting books above.
-- 'blocks' = the SMODS.Enhancement centers (Obsidian/Hay Bale/Lapis + 7 ore blocks);
-- 'tarots' = the Tarot consumables that apply the first three. Ore blocks spawn naturally
-- (utilities/card_enhancements.lua), so they have no applier.
PB_UTIL.ENABLED_CARD_ENHANCEMENTS = {
    'blocks',
    'tarots',
}

-- BalaCraft seals (Ore / Soul / Cooked) + the Spectral cards that apply them.
PB_UTIL.ENABLED_SEALS = {
    'seals',
    'spectrals',
}

PB_UTIL.ENABLED_JOKERS = {
    'menace',
    'waterdrop',
    'elytra',
    'itshome',
    'crackedknuckles',
    '0164',
    -- 'disappointment',
    -- stone_pickaxe / iron_sword / iron_shovel are now crafted TOOL CONSUMABLES
    -- (content/tools/, ENABLED_TOOLS below). The joker files are left inert on disk.
}

PB_UTIL.ENABLED_TAGS = {
    'tags',
}

PB_UTIL.ENABLED_VOUCHERS = {
    'nether_portal',
    'end_portal',         -- sequential: requires nether_portal (loads after it)
    'enchanting_table',   -- enchanting pair (gated on enhancements_enabled via in_pool)
    'sorcerers_tome',     -- sequential: requires enchanting_table (loads after it)
}

-- Loaded from content/biomes/ (data registry; logic is in utilities/biomes.lua).
PB_UTIL.ENABLED_BIOMES = {
    'registry',
}

PB_UTIL.ENABLED_RESOURCES = {
    'registry',
    'resource_consumabletype',
    'recipes',
    'resource_tile',
}

-- Loaded from content/tools/. Load order is SPECIAL (handled explicitly in main.lua):
-- 'registry' must load BEFORE content/resources/recipes.lua (recipes read PB_UTIL.TOOLS),
-- while 'tool_consumabletype' loads AFTER resources (it uses the bc_resource_cards atlas).
PB_UTIL.ENABLED_TOOLS = {
    'registry',
    'tool_consumabletype',
    'torch',
}

-- Loaded from content/foods/ (registry before consumabletype, which the packs depend on).
PB_UTIL.ENABLED_FOODS = {
    'registry',
    'food_consumabletype',
}

-- Loaded from content/boosters/ (gated with the rest of the food system).
PB_UTIL.ENABLED_FOOD_PACKS = {
    'food_pack',
    'food_pack_jumbo',
    'food_pack_mega',
}