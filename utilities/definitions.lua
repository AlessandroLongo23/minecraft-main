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
    'enchant_shader', -- registers the balacraft_enchant glint shader (MUST load before the editions below)
    'enchant_glint',  -- e_balacraft_enchant_glint      (inert carrier: routes enchanted TOOLS through the shader)
    'sharpness',      -- e_balacraft_sharpness_{1,2,3}  (Sharpness book -> card)
    'unbreaking',     -- e_balacraft_unbreaking         (Durability book -> card, flat)
    'lucky',          -- e_balacraft_lucky_{1,2,3}      (Fortune book -> card)
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
    -- Wave 1 (Archery) craftable jokers (output of recipes in content/resources/recipes.lua).
    'bow',
    'fishing_rod',
    'crossbow',
    -- 'disappointment',
    -- stone_pickaxe / iron_sword / iron_shovel are now crafted TOOL CONSUMABLES
    -- (content/tools/, ENABLED_TOOLS below). The joker files are left inert on disk.
}

PB_UTIL.ENABLED_TAGS = {
    'tags',
}

-- NOTE: the Nether/End Portal vouchers were removed -- dimensions are now reached via the
-- Ruined Portal blind (Flint & Steel + Obsidian) and the Eye-of-Ender trail (utilities/structures.lua,
-- utilities/biomes.lua). Only the enchanting pair remains.
PB_UTIL.ENABLED_VOUCHERS = {
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
    'arrow',   -- Wave 1 (Archery) one-shot consumable; loaded with torch (post-resources block)
    'bone_meal',  -- Bone mob-drop sink: select cards -> +Chips + buff that poker hand
    'tnt',        -- Gunpowder sink (explosives): destroy a card + its two neighbours
    'firework',   -- Gunpowder sink (explosives): load a card with Chips, scales with Gunpowder held
    'flint_and_steel', -- Nether key: light a Ruined Portal blind (spends 1 Obsidian) -> warp to the Nether
    'ender_eye',       -- End trail: use one per ante for 3 consecutive antes, following the marked biome
}

-- Loaded from content/foods/ (registry before consumabletype, which the packs depend on).
PB_UTIL.ENABLED_FOODS = {
    'registry',
    'food_consumabletype',
}

-- Loaded from content/sheets/ (registry before consumabletype). Sheets are crafted at the Anvil
-- (2 ore -> 1 sheet) and applied to a playing card as an enhancement. See main.lua's sheets block.
PB_UTIL.ENABLED_SHEETS = {
    'registry',
    'sheet_consumabletype',
}

-- Loaded from content/boosters/ (gated with the rest of the food system).
PB_UTIL.ENABLED_FOOD_PACKS = {
    'food_pack',
    'food_pack_jumbo',
    'food_pack_mega',
}

-- Tool booster packs (Toolbox trio). Gated with the tools system (the resources_enabled block in
-- main.lua), since they hand out tool consumables. The enchant roll inside is independently
-- runtime-guarded on PB_UTIL.ENCHANTS.
PB_UTIL.ENABLED_TOOL_PACKS = {
    'tool_pack',
    'tool_pack_jumbo',
    'tool_pack_mega',
}

-- Potions (brewed at the Brewing Stand; drink/throw consumables). 'registry' (POTIONS data +
-- the bc_potion_cards atlas) loads before 'potion_consumabletype' (the ConsumableType + the
-- 8 potion centers). Brewing logic/UI + the effect helpers (utilities/potions.lua, brewing.lua,
-- brewing_ui.lua) are loaded explicitly in main.lua's potions block.
PB_UTIL.ENABLED_POTIONS = {
    'registry',
    'potion_consumabletype',
}

-- Potion booster packs (gated with the potions system in main.lua, like the food/tool packs).
PB_UTIL.ENABLED_POTION_PACKS = {
    'potion_pack',
}