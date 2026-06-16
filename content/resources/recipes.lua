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
    {
        key = 'stone_pickaxe',
        name = 'Stone Pickaxe',
        output = { type = 'joker', id = 'j_minecraft_stone_pickaxe', amount = 1 },
        pattern = {
            { 'cobblestone', 'cobblestone', 'cobblestone' },
            { false,         'sticks',      false },
            { false,         'sticks',      false },
        },
    },
    {
        key = 'iron_sword',
        name = 'Iron Sword',
        output = { type = 'joker', id = 'j_minecraft_iron_sword', amount = 1 },
        pattern = {
            { false, 'iron',   false },
            { false, 'iron',   false },
            { false, 'sticks', false },
        },
    },
    {
        key = 'iron_shovel',
        name = 'Iron Shovel',
        output = { type = 'joker', id = 'j_minecraft_iron_shovel', amount = 1 },
        pattern = {
            { false, 'iron',   false },
            { false, 'sticks', false },
            { false, 'sticks', false },
        },
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
