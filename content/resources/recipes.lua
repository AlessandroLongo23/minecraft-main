-- Crafting recipes (data-driven). Empty grid cells are `false` (NOT nil — nil makes
-- Lua array holes). Each recipe: 3x3 pattern of resource ids + an output.

PB_UTIL.RECIPES = {
    {
        key = 'sticks',
        name = 'Sticks',
        output = { type = 'resource', id = 'sticks', amount = 2 },
        pattern = {
            { false, 'wood',  false },
            { false, 'wood',  false },
            { false, false,   false },
        },
    },
}

-- Tool recipes: 4 tools x 6 materials = 24, derived from PB_UTIL.TOOLS (content/tools/registry.lua,
-- which loads first -- see main.lua). Each outputs a consumable. The shaped matcher
-- (crafting_match.lua) compares cell IDS, so e.g. Wooden Sword (wood/wood/stick) and Iron Sword
-- (iron/iron/stick) are distinct recipes despite sharing a shape. Minecraft tool shapes:
--   sword   = 2 material stacked + 1 stick below
--   pickaxe = 3 material top row + 2 sticks (handle)
--   shovel  = 1 material + 2 sticks (handle)
--   axe     = 2 material + 1 material side + 2 sticks (the L-head + handle)
local function tool_pattern(tool, M)
    if tool == 'sword' then
        return {
            { false, M,        false },
            { false, M,        false },
            { false, 'sticks', false },
        }
    elseif tool == 'pickaxe' then
        return {
            { M,     M,        M     },
            { false, 'sticks', false },
            { false, 'sticks', false },
        }
    elseif tool == 'axe' then
        return {
            { M,     M,        false },
            { M,     'sticks', false },
            { false, 'sticks', false },
        }
    else -- shovel
        return {
            { false, M,        false },
            { false, 'sticks', false },
            { false, 'sticks', false },
        }
    end
end

for _, t in ipairs(PB_UTIL.TOOLS or {}) do
    PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
        key = 'tool_' .. t.id,
        name = t.name,
        output = { type = 'consumable', id = 'c_balacraft_tool_' .. t.id, amount = 1 },
        pattern = tool_pattern(t.tool, t.material),
    }
end

-- Torch: Minecraft recipe = coal directly above a stick. Normalizes to a 1x2 column
-- [coal, sticks], distinct from every tool/sticks shape (different cell ids). Outputs the
-- shop-peek consumable (logic in utilities/torch.lua).
PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
    key = 'torch',
    name = 'Torch',
    output = { type = 'consumable', id = 'c_balacraft_torch', amount = 1 },
    pattern = {
        { false, 'coal',   false },
        { false, 'sticks', false },
        { false, false,    false },
    },
}

-- Glow Torch: the same Torch crafted from a Glow Ink Sac instead of coal (MC torches craft from
-- coal OR charcoal -- multiple light sources, same torch). This is glow_ink_sac's THEMATIC home:
-- in Minecraft glow ink only makes things visible in the dark (glow signs / glow item frames), and
-- the Torch is BalaCraft's "reveal in the dark" item -- so the cave Glow Squid drop lights the cave.
-- Glow ink is concentrated cave-light, so this yields 2 Torches (coal yields 1) -> a worthwhile,
-- non-redundant use of a rare cave-exclusive drop. Same [head, sticks] 1x2 shape as the coal Torch
-- but distinct cell ids, so the matcher keeps them separate.
PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
    key = 'glow_torch',
    name = 'Torch',
    output = { type = 'consumable', id = 'c_balacraft_torch', amount = 2 },
    pattern = {
        { false, 'glow_ink_sac', false },
        { false, 'sticks',       false },
        { false, false,          false },
    },
}

-- ── Wave 1: Archery cluster ────────────────────────────────────────────────
-- Mob drops (string/feather/flint) + sticks/iron into ranged-weapon ends. Shapes mirror the
-- Minecraft recipes; the matcher compares cell IDs, so each is distinct from the others and from
-- the tool/sticks/torch shapes. Joker/consumable centers register later (jokers + tools blocks in
-- main.lua); can_craft gates on G.P_CENTERS at craft time, so the forward reference is fine.

-- Bow: 3 sticks (the bent frame) + 3 string (the drawn string). Output: persistent joker.
PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
    key = 'bow',
    name = 'Bow',
    output = { type = 'joker', id = 'j_balacraft_bow', amount = 1 },
    pattern = {
        { false,    'sticks', 'string' },
        { 'sticks', false,    'string' },
        { false,    'sticks', 'string' },
    },
}

-- Fishing Rod: 3 sticks (the pole) + 2 string (the line). Output: persistent joker.
PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
    key = 'fishing_rod',
    name = 'Fishing Rod',
    output = { type = 'joker', id = 'j_balacraft_fishing_rod', amount = 1 },
    pattern = {
        { false,    false,    'sticks' },
        { false,    'sticks', 'string' },
        { 'sticks', false,    'string' },
    },
}

-- Crossbow: 3 string + 2 sticks + 1 iron (tripwire hook simplified out). Output: joker.
-- can_craft ALSO requires owning a Bow this run (Cube->Big Cube prerequisite; see crafting.lua).
PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
    key = 'crossbow',
    name = 'Crossbow',
    output = { type = 'joker', id = 'j_balacraft_crossbow', amount = 1 },
    pattern = {
        { 'string', 'iron',   'string' },
        { 'sticks', false,    'sticks' },
        { false,    'string', false    },
    },
}

-- Arrow: flint tip + stick shaft + feather fletching. Output: a one-shot consumable.
PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
    key = 'arrow',
    name = 'Arrow',
    output = { type = 'consumable', id = 'c_balacraft_arrow', amount = 1 },
    pattern = {
        { false, 'flint',   false },
        { false, 'sticks',  false },
        { false, 'feather', false },
    },
}

-- Bone Meal: 1 Bone -> a Bone Meal consumable. Gives the Bone mob drop a crafting sink (no-orphan
-- rule). Single-cell shape (just Bone), distinct from every other recipe -- they are all multi-cell,
-- so this never collides. MC's recipe is 1 bone -> 3 bone meal; here it yields one consumable card.
PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
    key = 'bone_meal',
    name = 'Bone Meal',
    output = { type = 'consumable', id = 'c_balacraft_bone_meal', amount = 1 },
    pattern = {
        { false, false,  false },
        { false, 'bone', false },
        { false, false,  false },
    },
}

-- ── Explosives cluster (Gunpowder sinks) ────────────────────────────────────
-- TNT: 4 Gunpowder in the corners + a Cobblestone core (MC's gunpowder/sand checkerboard,
-- simplified). Output: the TNT consumable (destroy a card + its two neighbours).
PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
    key = 'tnt',
    name = 'TNT',
    output = { type = 'consumable', id = 'c_balacraft_tnt', amount = 1 },
    pattern = {
        { 'gunpowder', false,         'gunpowder' },
        { false,       'cobblestone', false       },
        { 'gunpowder', false,         'gunpowder' },
    },
}

-- Firework Rocket: 1 Gunpowder over 1 Stick (MC's gunpowder + paper, stick as the body). Output:
-- the Firework consumable (load a card with Chips, scaling with the Gunpowder you hold).
PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
    key = 'firework',
    name = 'Firework Rocket',
    output = { type = 'consumable', id = 'c_balacraft_firework', amount = 1 },
    pattern = {
        { false, 'gunpowder', false },
        { false, 'sticks',    false },
        { false, false,       false },
    },
}

-- ── Nether / End progression items ──────────────────────────────────────────
-- Eye of Ender: the genuine MC shapeless recipe, 1 Ender Pearl + 1 Blaze Powder. Same 1x2-column
-- shape as the Torch but distinct cell ids, so the matcher keeps them separate. Used (one per ante,
-- three consecutive antes) to follow the Eye-of-Ender trail to The End (utilities/biomes.lua).
PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
    key = 'ender_eye',
    name = 'Eye of Ender',
    output = { type = 'consumable', id = 'c_balacraft_ender_eye', amount = 1 },
    pattern = {
        { false, 'ender_pearl',  false },
        { false, 'blaze_powder', false },
        { false, false,          false },
    },
}

-- Flint and Steel: MC recipe = 1 Iron Ingot + 1 Flint (diagonal). Iron is smelt-only
-- (drop_class='refined'), so this is naturally gated behind a Furnace. A single-use consumable:
-- used in a Ruined Portal blind (with 1 Obsidian) to light it -> warp to the Nether
-- (use logic in content/tools/flint_and_steel.lua + utilities/structures.lua).
PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
    key = 'flint_and_steel',
    name = 'Flint and Steel',
    output = { type = 'consumable', id = 'c_balacraft_flint_and_steel', amount = 1 },
    pattern = {
        { 'iron', false,    false },
        { false,  'flint',  false },
        { false,  false,    false },
    },
}

-- Glass Sheet: the one sheet crafted at the Crafting Table (the metal/mineral sheets are forged at
-- the Anvil's "Forge Sheets" tab instead). MC's glass-pane row: 3 Glass across the middle, which
-- normalizes to a unique 1x3 'glass' shape. Glass is furnace-only (smelt Sand, see furnace.lua), so
-- this is naturally gated behind a Furnace. Guarded on sheets_enabled (the sheet consumable must
-- exist; can_craft also gates on G.P_CENTERS at craft time).
if PB_UTIL.config and PB_UTIL.config.sheets_enabled then
    PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
        key = 'glass_sheet',
        name = 'Glass Sheet',
        output = { type = 'consumable', id = 'c_balacraft_sheet_glass', amount = 1 },
        pattern = {
            { false,   false,   false   },
            { 'glass', 'glass', 'glass' },
            { false,   false,   false   },
        },
    }
end

-- ── Potions: brewing-ingredient sub-crafts (Crafting Table) ─────────────────
-- The MC sub-crafts that feed the Brewing Stand (Water Bottles + the base ingredients). The brews
-- themselves happen at the Brewing Stand's sequential transition engine (utilities/brewing.lua);
-- these are the Crafting-Table intermediates. Gated on potions_enabled (the output resources must
-- exist; can_craft re-checks at craft time). Single-cell shapes (Sugar, Blaze Powder) by cell id.
if PB_UTIL.config and PB_UTIL.config.potions_enabled then
    -- Water Bottle: MC's V of 3 Glass -> 3 bottles, already filled with water (we skip the empty
    -- Glass Bottle + separate fill step; the Brewing Stand wants Water Bottles). Glass is furnace-only.
    PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
        key = 'water_bottle', name = 'Water Bottle',
        output = { type = 'resource', id = 'water_bottle', amount = 3 },
        pattern = { { 'glass', false, 'glass' }, { false, 'glass', false }, { false, false, false } },
    }
    -- Sugar: 1 Sugar Cane -> 1 Sugar.
    PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
        key = 'sugar', name = 'Sugar',
        output = { type = 'resource', id = 'sugar', amount = 1 },
        pattern = { { false, false, false }, { false, 'sugar_cane', false }, { false, false, false } },
    }
    -- Blaze Powder: 1 Blaze Rod -> 2 Blaze Powder (the MC craft; blaze_powder also drops in the Nether).
    PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
        key = 'blaze_powder', name = 'Blaze Powder',
        output = { type = 'resource', id = 'blaze_powder', amount = 2 },
        pattern = { { false, false, false }, { false, 'blaze_rod', false }, { false, false, false } },
    }
    -- Glistering Melon: Melon Slice + Gold (MC's gold-nugget ring, simplified to 1 Gold above).
    PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
        key = 'glistering_melon', name = 'Glistering Melon',
        output = { type = 'resource', id = 'glistering_melon', amount = 1 },
        pattern = { { false, 'gold', false }, { false, 'melon_slice', false }, { false, false, false } },
    }
    -- Golden Carrot: Carrot + Gold (same simplification as the melon).
    PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
        key = 'golden_carrot', name = 'Golden Carrot',
        output = { type = 'resource', id = 'golden_carrot', amount = 1 },
        pattern = { { false, 'gold', false }, { false, 'carrot', false }, { false, false, false } },
    }
    -- Fermented Spider Eye: Spider Eye + Sugar + Brown Mushroom (shapeless -> a 1x3 row).
    PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
        key = 'fermented_spider_eye', name = 'Fermented Spider Eye',
        output = { type = 'resource', id = 'fermented_spider_eye', amount = 1 },
        pattern = { { false, false, false }, { 'spider_eye', 'sugar', 'brown_mushroom' }, { false, false, false } },
    }
    -- Brewing Stand station: MC's 1 Blaze Rod over 3 Cobblestone. Unlocks the Brewing Stand in the Base.
    PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
        key = 'brewing_stand', name = 'Brewing Stand',
        output = { type = 'station', id = 'brewing_stand', amount = 1 },
        pattern = { { false, 'blaze_rod', false }, { 'cobblestone', 'cobblestone', 'cobblestone' }, { false, false, false } },
    }
end

-- ── The Base: crafted stations ──────────────────────────────────────────────
-- output.type='station' is a one-time unlock (utilities/crafting.lua): crafting it flips the
-- station on in "Your Base" (PB_UTIL.build_station). The Furnace is the MC ring of 8 Cobblestone.
-- Tuned to be affordable by early-mid ante 2 so smelting (raw iron/gold -> ingots) comes online.
PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
    key = 'furnace',
    name = 'Furnace',
    output = { type = 'station', id = 'furnace', amount = 1 },
    pattern = {
        { 'cobblestone', 'cobblestone', 'cobblestone' },
        { 'cobblestone', false,         'cobblestone' },
        { 'cobblestone', 'cobblestone', 'cobblestone' },
    },
}

-- ── Enchanting book chain (gated on enhancements_enabled, like brewing is on potions_enabled) ──
-- Paper/Book/Enchanting Table only matter to the enchant system, so don't surface them when
-- enhancements are off (otherwise you could craft a table whose in-frame UI never loaded).
if PB_UTIL.config and PB_UTIL.config.enhancements_enabled then
    -- Paper: MC's 3 Sugar Cane in a row -> 3 Paper. Book: 3 Paper + 1 Leather (MC book; cells are
    -- cosmetic since ingredients derive from the pattern multiset).
    PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
        key = 'paper', name = 'Paper',
        output = { type = 'resource', id = 'paper', amount = 3 },
        pattern = { { false, false, false }, { 'sugar_cane', 'sugar_cane', 'sugar_cane' }, { false, false, false } },
    }
    PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
        key = 'book', name = 'Book',
        output = { type = 'resource', id = 'book', amount = 1 },
        pattern = { { 'paper', 'paper', 'paper' }, { false, 'leather', false }, { false, false, false } },
    }
    -- Enchanting Table station: faithful MC recipe (1 Book over 2 Diamond + 4 Obsidian). output.type=
    -- 'station' flips PB_UTIL.station_built('enchanting_table') on (utilities/crafting.lua).
    PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
        key = 'enchanting_table', name = 'Enchanting Table',
        output = { type = 'station', id = 'enchanting_table', amount = 1 },
        pattern = {
            { false,      'book',     false },
            { 'diamond',  'obsidian', 'diamond' },
            { 'obsidian', 'obsidian', 'obsidian' },
        },
    }
end

-- Chest: the MC ring of 8 (planks -> Wood here). A PASSIVE station: once built it EXPANDS the
-- inventory's capacity by PB_UTIL.CHEST_SLOTS (utilities/inventory_model.lua inv_capacity). Same
-- station-unlock mechanism as the Furnace.
PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
    key = 'chest',
    name = 'Chest',
    output = { type = 'station', id = 'chest', amount = 1 },
    pattern = {
        { 'wood', 'wood', 'wood' },
        { 'wood', false,  'wood' },
        { 'wood', 'wood', 'wood' },
    },
}

-- Anvil: an anvil silhouette of Iron (3 across the top + a 2-cell neck). Iron is smelt-only
-- (drop_class='refined'), so the Anvil is naturally GATED behind owning a Furnace -- thematic
-- (you need a furnace to make iron, and iron to make an anvil). A Base station: once built it
-- opens the Anvil overlay, a TABBED screen -- "Forge Sheets" (2 of one ore -> a Sheet) and
-- "Combine Tools" (merge two same-type+material tools -> stack enchants + pool uses).
-- 5 iron is the default cost (tunable); same shape as an iron pickaxe but the neck is iron not
-- sticks, so the cell-id matcher keeps them distinct.
PB_UTIL.RECIPES[#PB_UTIL.RECIPES + 1] = {
    key = 'anvil',
    name = 'Anvil',
    output = { type = 'station', id = 'anvil', amount = 1 },
    pattern = {
        { 'iron', 'iron', 'iron' },
        { false,  'iron', false  },
        { false,  'iron', false  },
    },
}

-- Multiset of ingredients derived from the pattern (single source of truth).
function PB_UTIL.recipe_ingredients(recipe)
    local need = {}
    for i = 1, 3 do
        for j = 1, 3 do
            local cell = recipe.pattern[i][j]
            if cell then need[cell] = (need[cell] or 0) + 1 end
        end
    end
    return need
end

function PB_UTIL.recipe_by_key(key)
    for _, r in ipairs(PB_UTIL.RECIPES) do
        if r.key == key then return r end
    end
    return nil
end
