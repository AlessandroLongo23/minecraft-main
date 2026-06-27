PB_UTIL = {}
PB_UTIL.config = SMODS.current_mod.config

SMODS.load_file("utilities/definitions.lua")()
SMODS.load_file("utilities/functions.lua")()
SMODS.load_file("utilities/ui.lua")()

if PB_UTIL.config.blinds_enabled then
    PB_UTIL.load_blinds(PB_UTIL.ENABLED_BLINDS)
end

if PB_UTIL.config.resources_enabled then
    SMODS.load_file("utilities/resources.lua")()
    SMODS.load_file("utilities/resource_ui.lua")()
    SMODS.load_file("utilities/cashout_ui.lua")()
    SMODS.load_file("utilities/crafting.lua")()
    SMODS.load_file("utilities/crafting_match.lua")()
    SMODS.load_file("utilities/crafting_grid.lua")()
    SMODS.load_file("utilities/crafting_ui.lua")()
    -- Recipe reference panel on craftable cards' hover popup (a static 3x3 grid beside the
    -- description, like the base game's Gold Card box). Lazy: reads PB_UTIL.RECIPES at hover time,
    -- so it composes with the tool/joker centers registered later in this file.
    SMODS.load_file("utilities/recipe_tooltip.lua")()
    -- The Furnace (smelt raw->refined) + the "Your Base" launcher. Loads after crafting_ui so its
    -- Base slot can call open_crafting_table / the Back-to-Base helper can credit craft_cells.
    SMODS.load_file("utilities/furnace.lua")()
    SMODS.load_file("utilities/torch.lua")()
    -- Tool registry FIRST: defines PB_UTIL.TOOLS, which content/resources/recipes.lua reads
    -- to build the 18 tool recipes.
    PB_UTIL.register_items({ 'registry' }, "tools")
    PB_UTIL.register_items(PB_UTIL.ENABLED_RESOURCES, "resources")
    -- Tool consumable cards + the Torch AFTER resources: they use the bc_resource_cards atlas
    -- registered in content/resources/registry.lua.
    PB_UTIL.register_items({ 'tool_consumabletype', 'torch', 'arrow', 'bone_meal', 'tnt', 'firework' }, "tools")
    -- Tool booster packs (Toolbox trio). Logic helpers + the three boosters. sample_pack_tools
    -- reads PB_UTIL.TOOLS (registered just above) at pack-open time; the enchant roll is runtime-
    -- guarded on PB_UTIL.ENCHANTS, so it composes regardless of the enhancements load order below.
    SMODS.load_file("utilities/tool_packs.lua")()
    PB_UTIL.register_items(PB_UTIL.ENABLED_TOOL_PACKS, "boosters")
    -- Villager Trading: spend emeralds on resource bundles + plain tools (persistent shop
    -- section). Loads last in this block: needs PB_UTIL.RESOURCES/TOOLS, the bc_resource_icons
    -- atlas, the tool consumable centers, and consumable_add (all set up above).
    if PB_UTIL.config.villager_enabled then
        SMODS.load_file("content/villager/professions.lua")()   -- profession data; villager.lua reads it
        SMODS.load_file("content/villager/trades.lua")()
        SMODS.load_file("utilities/villager.lua")()
        SMODS.load_file("utilities/villager_ui.lua")()
    end
end

-- Minecraft Inventory & Loadout. Loads AFTER the resources block so its bench-aware
-- has_joker_room / has_consumable_room overrides land on top of crafting.lua's, and so the
-- "Open Crafting" button + resource row can reach open_crafting_table / the resource atlas
-- (both guarded, so this still works when resources are off).
if PB_UTIL.config.inventory_enabled then
    SMODS.load_file("utilities/inventory.lua")()
    SMODS.load_file("utilities/inventory_ui.lua")()
end

if PB_UTIL.config.health_enabled then
    SMODS.load_file("utilities/health.lua")()
    SMODS.load_file("utilities/health_ui.lua")()
end

-- Biomes & Dimensions. Registry (data) first, then the core logic + selection UI. The
-- resource-drop bias (resources.lua) and any biome-aware joker checks look up biome state
-- at call-time, so this is inert unless biomes_enabled and composes with any load order.
if PB_UTIL.config.biomes_enabled then
    -- progression first: it loads the persisted lifetime counters so the dimension decks'
    -- `unlocked` field reads the right value when they register in the decks block below.
    SMODS.load_file("utilities/progression.lua")()
    PB_UTIL.register_items(PB_UTIL.ENABLED_BIOMES, "biomes")
    SMODS.load_file("utilities/biomes.lua")()
    SMODS.load_file("utilities/biomes_ui.lua")()
end

-- XP loads after the resources block so xp.lua's PB_UTIL.craft wrap sees the real
-- function (crafting.lua loads above when resources_enabled).
if PB_UTIL.config.xp_enabled then
    SMODS.load_file("utilities/xp.lua")()
    SMODS.load_file("utilities/xp_ui.lua")()
end

-- Food + hunger. Loads after health so hunger's regen/starvation can call PB_UTIL.heal/damage
-- (guarded if health is off). Registers the food consumables before the food packs that spawn them.
if PB_UTIL.config.food_enabled then
    SMODS.load_file("utilities/hunger.lua")()
    SMODS.load_file("utilities/hunger_ui.lua")()
    PB_UTIL.register_items(PB_UTIL.ENABLED_FOODS, "foods")
    PB_UTIL.register_items(PB_UTIL.ENABLED_FOOD_PACKS, "boosters")
end

if PB_UTIL.config.boosters_enabled then
    PB_UTIL.register_items(PB_UTIL.ENABLED_BOOSTERS, "boosters")
end

if PB_UTIL.config.decks_enabled then
    PB_UTIL.register_items(PB_UTIL.ENABLED_DECKS, "decks")
end

-- Enchanting: books (content/enhancements/) + the apply logic and Enchant button UI.
-- Loads after the resources block (needs PB_UTIL.TOOL_BY_ID + get_view_mode) and the XP
-- block (applying an enchant spends levels via PB_UTIL.spend_level).
if PB_UTIL.config.enhancements_enabled then
    -- registry (ENCHANTS data + math) before the book consumable type.
    PB_UTIL.register_items(PB_UTIL.ENABLED_ENHANCEMENTS, "enhancements")
    -- Card editions (Sharpness) applied via the dual-target Enchant flow.
    PB_UTIL.register_items(PB_UTIL.ENABLED_EDITIONS, "editions")
    SMODS.load_file("utilities/enchanting.lua")()
    SMODS.load_file("utilities/enchanting_ui.lua")()
    -- Enchanting booster pack (gated with enchanting, like the food packs are with food).
    -- Sampler lives in utilities/functions.lua (loaded first); the books were registered above.
    PB_UTIL.register_items({ 'enchant_pack' }, "boosters")
end

if PB_UTIL.config.jokers_enabled then
    PB_UTIL.register_items(PB_UTIL.ENABLED_JOKERS, "jokers")
end

-- Card enhancements ("block-cards"): Obsidian/Hay Bale/Lapis (tarot-applied) + Ore Blocks
-- (spawn naturally). Loads AFTER resources (needs PB_UTIL.random_ore_of_tier + the
-- bc_resource_cards atlas), xp, and food so the per-block effects can grant XP / hunger / ore.
if PB_UTIL.config.card_enhancements_enabled then
    PB_UTIL.register_items(PB_UTIL.ENABLED_CARD_ENHANCEMENTS, "card_enhancements")
    SMODS.load_file("utilities/card_enhancements.lua")()
end

-- Seals: Ore (discard->resource), Soul (play->XP), Cooked (held->Food, seal stays on the card).
-- Loads after resources/xp/food so the seal effects can grant ore / XP / food; spectrals apply them.
if PB_UTIL.config.seals_enabled then
    PB_UTIL.register_items(PB_UTIL.ENABLED_SEALS, "seals")
end

if PB_UTIL.config.tags_enabled then
    PB_UTIL.register_items(PB_UTIL.ENABLED_TAGS, "tags")
end

if PB_UTIL.config.vouchers_enabled then
    PB_UTIL.register_items(PB_UTIL.ENABLED_VOUCHERS, "vouchers")
end