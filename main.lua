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
    -- Unified inventory capacity model (slot math); load right after resources so add_resource's
    -- capacity-aware path and the crafting gates can reach it.
    SMODS.load_file("utilities/inventory_model.lua")()
    -- Minecraft consumable area (G.bc_mc_consumeables) + classification + acquire routing. Loads
    -- before resource_ui so the toggle/driver can flip between the vanilla and MC areas.
    SMODS.load_file("utilities/mc_consumables.lua")()
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
    -- The Composter (organics -> Bone Meal). Loads after furnace.lua: it reuses open_base + the
    -- station_built/build_station plumbing and its Back returns to the unified Base modal.
    SMODS.load_file("utilities/composter.lua")()
    SMODS.load_file("utilities/torch.lua")()
    -- Tool registry FIRST: defines PB_UTIL.TOOLS, which content/resources/recipes.lua reads
    -- to build the 18 tool recipes.
    PB_UTIL.register_items({ 'registry' }, "tools")
    PB_UTIL.register_items(PB_UTIL.ENABLED_RESOURCES, "resources")
    -- Tool consumable cards + the Torch AFTER resources: they use the bc_resource_cards atlas
    -- registered in content/resources/registry.lua.
    PB_UTIL.register_items({ 'tool_consumabletype', 'torch', 'arrow', 'bone_meal', 'tnt', 'firework',
        'flint_and_steel', 'ender_eye' }, "tools")
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
    -- Structure blinds (re-theme Night/Cave per ante) + the Ruined Portal -> Nether entry. Loads
    -- after biomes (reads current_dimension/biome) and is self-guarded on blinds_enabled.
    SMODS.load_file("utilities/structures.lua")()
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

-- Potions: a Minecraft brewing consumable category (drink / throw). Loads after health
-- (Healing/Instant Health call PB_UTIL.heal/damage), biomes (Swiftness opens the biome select),
-- xp, and the resources block (potions route through the MC consumable area, and the Brewing
-- Stand is a crafting station). potions.lua holds the effect helpers; the registry registers the
-- ConsumableType + the 8 centers. The Brewing Stand station + booster pack are loaded here as
-- their files are added (Waves 2 & 4).
if PB_UTIL.config.potions_enabled then
    SMODS.load_file("utilities/potions.lua")()
    PB_UTIL.register_items(PB_UTIL.ENABLED_POTIONS, "potions")
    -- Active-effects HUD row below the consumable area (reads the potion effect state seeded in
    -- potions.lua; uses the bc_effect_icons atlas registered by the registry above).
    SMODS.load_file("utilities/effects_ui.lua")()
    -- The Brewing Stand: fuel + brew recipes + dimension drops (brewing.lua), then its in-frame station
    -- content (brewing_ui.lua), which renders inside the unified Inventory modal's Workbench picker once
    -- the station is crafted. Guarded so potions still load if the resources block is disabled.
    if PB_UTIL.config.resources_enabled then
        SMODS.load_file("utilities/brewing.lua")()
        SMODS.load_file("utilities/brewing_ui.lua")()
    end
    -- Potion booster pack (secondary source; brewing is primary). Registered after the centers
    -- above so its create_card can spawn them.
    PB_UTIL.register_items(PB_UTIL.ENABLED_POTION_PACKS, "boosters")
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
    SMODS.load_file("utilities/enchanting_table_ui.lua")()
    -- Enchanting booster pack (gated with enchanting, like the food packs are with food).
    -- Sampler lives in utilities/functions.lua (loaded first); the books were registered above.
    PB_UTIL.register_items({ 'enchant_pack' }, "boosters")
end

if PB_UTIL.config.jokers_enabled then
    PB_UTIL.register_items(PB_UTIL.ENABLED_JOKERS, "jokers")
end

-- Card enhancements ("block-cards"): the Lapis card (Sheet-applied) + Ore Blocks
-- (spawn naturally). Loads AFTER resources (needs PB_UTIL.random_ore_of_tier + the
-- bc_resource_cards atlas), xp, and food so the per-block effects can grant XP / hunger / ore.
if PB_UTIL.config.card_enhancements_enabled then
    PB_UTIL.register_items(PB_UTIL.ENABLED_CARD_ENHANCEMENTS, "card_enhancements")
    SMODS.load_file("utilities/card_enhancements.lua")()
end

-- Sheets: a craftable consumable (Anvil "Forge Sheets" tab: 2 ore -> 1 sheet; the Glass sheet is the
-- Crafting Table exception) APPLIED to a playing card as an enhancement (the same UX as a Tarot).
-- Loads after card_enhancements (the Lapis sheet reuses m_balacraft_lapis) and after resources/xp
-- (the Emerald sheet pays $). The Steel->Iron display rename lives in the sheets registry; the Anvil
-- "Forge Sheets" tab + sand->glass smelt + the glass-sheet recipe are wired in the resources block
-- above (utilities/furnace.lua + content/resources/recipes.lua), all runtime-guarded on PB_UTIL.SHEETS.
if PB_UTIL.config.sheets_enabled then
    -- the four new enhancement centers (Diamond/Emerald/Redstone/Coal) the metal sheets apply.
    PB_UTIL.register_items({ 'sheet_enhancements' }, "card_enhancements")
    PB_UTIL.register_items(PB_UTIL.ENABLED_SHEETS, "sheets")
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