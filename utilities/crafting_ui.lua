-- Crafting Table: a "Crafting Table" button under the hotbar opens a centered
-- overlay listing recipes (left) with a read-only pattern preview + Craft (right).

PB_UTIL.crafting_selected = PB_UTIL.crafting_selected or nil

-- A 0.34-scale icon sprite for a resource id (or an empty slot for `false`).
local function cell_node(cell)
    if not cell then
        return { n = G.UIT.C, config = { minw = 0.34, minh = 0.34, r = 0.05, padding = 0.02, colour = G.C.UI.TRANSPARENT_DARK } }
    end
    local r = PB_UTIL.RESOURCE_BY_ID[cell]
    if not r then
        return { n = G.UIT.C, config = { minw = 0.34, minh = 0.34, r = 0.05, padding = 0.02, colour = G.C.RED } }
    end
    local spr = Sprite(0, 0, 0.34, 0.34, G.ASSET_ATLAS[PB_UTIL.icon_atlas.key], r.pos)
    return { n = G.UIT.C, config = { align = 'cm' }, nodes = { { n = G.UIT.O, config = { object = spr } } } }
end

-- Read-only 3x3 preview of a recipe's pattern.
local function pattern_preview(recipe)
    local rows = {}
    for i = 1, 3 do
        local row = { n = G.UIT.R, config = { align = 'cm', padding = 0.03 }, nodes = {} }
        for j = 1, 3 do
            row.nodes[#row.nodes + 1] = cell_node(recipe and recipe.pattern[i][j] or false)
        end
        rows[#rows + 1] = row
    end
    return { n = G.UIT.C, config = { align = 'cm', padding = 0.06, r = 0.1, colour = G.C.BLACK }, nodes = rows }
end

-- One clickable recipe row in the left list.
local function recipe_row(recipe)
    local craftable = PB_UTIL.can_craft(recipe)
    local selected = (PB_UTIL.crafting_selected == recipe.key)
    return {
        n = G.UIT.R,
        config = {
            align = 'cl', padding = 0.06, r = 0.08, minw = 3,
            colour = selected and G.C.GREEN or (craftable and G.C.UI.TRANSPARENT_DARK or G.C.UI.TRANSPARENT_LIGHT),
            button = 'bc_select_recipe', ref_table = { key = recipe.key },
            hover = true, shadow = true,
        },
        nodes = {
            { n = G.UIT.T, config = { text = recipe.name or recipe.key, scale = 0.36,
                colour = craftable and G.C.WHITE or G.C.UI.TEXT_INACTIVE } },
        },
    }
end

function PB_UTIL.build_crafting_modal()
    local selected = PB_UTIL.crafting_selected and PB_UTIL.recipe_by_key(PB_UTIL.crafting_selected) or nil

    local list = {}
    for _, r in ipairs(PB_UTIL.RECIPES) do list[#list + 1] = recipe_row(r) end

    local can = PB_UTIL.can_craft(selected)
    local craft_btn = {
        n = G.UIT.C,
        config = {
            align = 'cm', padding = 0.1, r = 0.1, minw = 2,
            colour = can and G.C.GREEN or G.C.UI.TRANSPARENT_LIGHT,
            button = can and 'bc_do_craft' or nil, hover = can, shadow = can,
        },
        nodes = { { n = G.UIT.T, config = { text = 'Craft', scale = 0.5, colour = G.C.UI.TEXT_LIGHT } } },
    }

    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0.1, r = 0.1, colour = G.C.GREY, minw = 9, minh = 5 },
        nodes = {
            { n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
                -- LEFT: recipe list
                { n = G.UIT.C, config = { align = 'tm', padding = 0.06, r = 0.1, colour = G.C.BLACK, minw = 3.4 }, nodes = {
                    { n = G.UIT.R, nodes = { { n = G.UIT.T, config = { text = 'Recipes', scale = 0.5, colour = G.C.UI.TEXT_LIGHT } } } },
                    { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = { { n = G.UIT.C, nodes = list } } },
                } },
                -- RIGHT: preview + craft
                { n = G.UIT.C, config = { align = 'cm', padding = 0.1 }, nodes = {
                    pattern_preview(selected),
                    { n = G.UIT.R, config = { align = 'cm', minh = 0.2 }, nodes = {} },
                    craft_btn,
                } },
            } },
        },
    }
end

function PB_UTIL.open_crafting_table()
    PB_UTIL.crafting_selected = nil
    G.FUNCS.overlay_menu { definition = PB_UTIL.build_crafting_modal() }
end

-- Re-render the open modal after a selection/craft.
local function refresh_modal()
    if G.OVERLAY_MENU then
        G.NO_MOD_CURSOR_STACK = true
        G.FUNCS.overlay_menu { definition = PB_UTIL.build_crafting_modal() }
        G.NO_MOD_CURSOR_STACK = nil
    end
end

G.FUNCS.bc_open_crafting = function(e)
    PB_UTIL.open_crafting_table()
end

G.FUNCS.bc_select_recipe = function(e)
    PB_UTIL.crafting_selected = e.config.ref_table.key
    refresh_modal()
end

G.FUNCS.bc_do_craft = function(e)
    local recipe = PB_UTIL.crafting_selected and PB_UTIL.recipe_by_key(PB_UTIL.crafting_selected)
    if recipe and PB_UTIL.craft(recipe) then refresh_modal() end
end
