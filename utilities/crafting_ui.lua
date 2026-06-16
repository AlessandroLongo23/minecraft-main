-- Crafting Table: a "Crafting Table" button under the hotbar opens a centered
-- overlay listing recipes (left) with a live 3x3 grid + palette + output slot (right).
-- Build-once / mutate-in-place: overlay_menu is called EXACTLY ONCE (in open_crafting_table).

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

-- (pattern_preview removed -- replaced by PB_UTIL.build_grid_node in crafting_grid.lua)

-- One clickable recipe row in the left list.
local function recipe_row(recipe)
    local craftable = PB_UTIL.can_craft(recipe)
    local selected = (PB_UTIL.crafting_selected == recipe.key)
    return {
        n = G.UIT.R,
        config = {
            align = 'cl', padding = 0.06, r = 0.08, minw = 3,
            colour = selected and G.C.GREEN or (craftable and G.C.UI.TRANSPARENT_DARK or G.C.UI.TRANSPARENT_LIGHT),
            button = 'bc_autofill', ref_table = { key = recipe.key },
            hover = true, shadow = true,
        },
        nodes = {
            { n = G.UIT.T, config = { text = recipe.name or recipe.key, scale = 0.36,
                colour = craftable and G.C.WHITE or G.C.UI.TEXT_INACTIVE } },
        },
    }
end

-- One state table living for the modal's lifetime. output_label is ALWAYS a string
-- ('' when no match) so the bound output T-node renders blank (tostring(nil)=='nil').
G.GAME.craft_state = G.GAME.craft_state or { output_label = '', can_craft = false }

-- Per-frame func on the Craft button: ONLY changes colour from craft_state. Runs every
-- frame via UIElement:update (ui.lua:1024-1027). It must NOT toggle config.button --
-- the button is built with a non-nil button so collide/click are already enabled; the
-- bc_grid_craft callback self-guards on an invalid grid, so always-clickable is safe.
G.FUNCS.bc_can_craft_btn = function(e)
    e.config.colour = G.GAME.craft_state.can_craft and G.C.GREEN or G.C.UI.TRANSPARENT_LIGHT
end

-- Data-only half: compute match -> craft_state, NO UIElement lookups. Safe to call
-- before the overlay exists (during build).
function PB_UTIL.refresh_craft_state_data()
    local recipe = PB_UTIL.match_grid(PB_UTIL.read_grid())
    local can = false
    if recipe then
        if recipe.output.type == 'joker' then
            can = (G.P_CENTERS[recipe.output.id] and PB_UTIL.has_joker_room()) and true or false
        else
            can = true
        end
    end
    G.GAME.craft_state.can_craft = can
    G.GAME.craft_state.output_label = recipe and (recipe.name or recipe.key) or ''   -- '' not nil
end

-- Recompute the match and reflect it IN PLACE (no overlay rebuild). Call after EVERY
-- grid change. The bound output T-node auto-updates each frame (ui.lua:1028), so we do
-- NOT call update_text on the label; we only swap the output ICON sprite (resource
-- outputs only -- jokers have no icon, the label carries their name).
function PB_UTIL.refresh_craft_state()
    PB_UTIL.refresh_craft_state_data()
    if not G.OVERLAY_MENU then return end
    local recipe = PB_UTIL.match_grid(PB_UTIL.read_grid())
    local icon = G.OVERLAY_MENU:get_UIE_by_ID('bc_craft_output_icon')
    if icon and icon.config and icon.config.object then
        local out = recipe and recipe.output
        if out and out.type == 'resource' then
            local r = PB_UTIL.RESOURCE_BY_ID[out.id]
            if r then icon.config.object:set_sprite_pos(r.pos) end
        end
    end
end

function PB_UTIL.build_crafting_modal()
    -- Seed craft_state from the (currently empty) grid before the UI binds to it.
    PB_UTIL.refresh_craft_state_data()   -- data-only seed (no UE lookups)

    local list = {}
    for _, r in ipairs(PB_UTIL.RECIPES) do list[#list + 1] = recipe_row(r) end

    -- Output slot: an icon (resource outputs) + a live text label bound to craft_state.
    local output_node = {
        n = G.UIT.C, config = { align = 'cm', padding = 0.06, r = 0.1, colour = G.C.BLACK, minw = 1.2, minh = 0.9 },
        nodes = {
            { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                { n = G.UIT.O, config = { id = 'bc_craft_output_icon',
                    object = Sprite(0, 0, 0.34, 0.34, G.ASSET_ATLAS[PB_UTIL.icon_atlas.key],
                        PB_UTIL.RESOURCE_BY_ID['wood'].pos) } },
            } },
            { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                { n = G.UIT.T, config = {
                    id = 'bc_craft_output_label',
                    ref_table = G.GAME.craft_state, ref_value = 'output_label',  -- bound (ui.lua:657)
                    scale = 0.34, colour = G.C.WHITE } },
            } },
        },
    }

    -- Craft button: NON-nil button at construction so set_values:391 enables collide/click
    -- once; the per-frame func only changes colour. bc_grid_craft self-guards on an invalid
    -- grid, so an always-clickable button is safe.
    local craft_btn = {
        n = G.UIT.C,
        config = {
            id = 'bc_craft_button',
            align = 'cm', padding = 0.1, r = 0.1, minw = 2,
            colour = G.C.UI.TRANSPARENT_LIGHT,   -- initial; func overwrites on frame 1
            button = 'bc_grid_craft',            -- NON-nil at build (enables collide/click once)
            func = 'bc_can_craft_btn',           -- runs every frame (ui.lua:1024-1027), colour only
            hover = true, shadow = true,
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
                -- RIGHT: live grid + palette + output + craft (built ONCE; mutated in place)
                { n = G.UIT.C, config = { align = 'cm', padding = 0.1 }, nodes = {
                    PB_UTIL.build_grid_node(),
                    { n = G.UIT.R, config = { align = 'cm', minh = 0.15 }, nodes = {} },
                    PB_UTIL.build_palette_node(),
                    { n = G.UIT.R, config = { align = 'cm', minh = 0.15 }, nodes = {} },
                    { n = G.UIT.R, config = { align = 'cm', padding = 0.06 }, nodes = { output_node, craft_btn } },
                } },
            } },
        },
    }
end

function PB_UTIL.open_crafting_table()
    PB_UTIL.crafting_selected = nil
    G.GAME.craft_state = G.GAME.craft_state or { output_label = '', can_craft = false }
    G.GAME.craft_state.output_label = ''
    G.GAME.craft_state.can_craft = false
    PB_UTIL.build_craft_cells()                          -- nine live cell-areas (build once)
    PB_UTIL.craft_on_change = PB_UTIL.refresh_craft_state  -- grid changes mutate in place
    G.FUNCS.overlay_menu { definition = PB_UTIL.build_crafting_modal() }  -- ONCE; never again while open
end

G.FUNCS.bc_open_crafting = function(e)
    PB_UTIL.open_crafting_table()
end

-- Palette source click: spawn a tile into the first empty cell (native button path).
G.FUNCS.bc_palette_pick = function(e)
    local id = e.config.ref_table and e.config.ref_table.id
    if id and PB_UTIL.spawn_tile_to_cell(id) then
        play_sound('cardSlide1')
        PB_UTIL.refresh_craft_state()
    end
end

-- Grid Craft: placed tiles are already reserved. SELF-GUARD on an invalid grid / no
-- joker slot (the button is always clickable, so the guard is what enforces validity).
-- CONSUME placed tiles WITHOUT crediting (reuse-in-place), produce output. Never call
-- PB_UTIL.craft here (double-spend).
G.FUNCS.bc_grid_craft = function(e)
    local recipe = PB_UTIL.match_grid(PB_UTIL.read_grid())
    if not recipe then play_sound('cancel'); return end
    if recipe.output.type == 'joker' then
        if not G.P_CENTERS[recipe.output.id] then play_sound('cancel'); return end
        if not PB_UTIL.has_joker_room() then play_sound('cancel'); return end
    end
    PB_UTIL.clear_craft_cells(false)   -- destroy placed tiles in place, NO credit (spent)
    PB_UTIL.produce_output(recipe)     -- produce-half only (resource/joker + sound)
    PB_UTIL.refresh_craft_state()      -- grid is now empty; output blanks, button greys
end

-- Auto-fill from a recipe row click: clear current placement (returning tiles), then
-- spawn the recipe's pattern tiles into the matching cells via the reserve path.
G.FUNCS.bc_autofill = function(e)
    local recipe = e.config.ref_table and e.config.ref_table.key
        and PB_UTIL.recipe_by_key(e.config.ref_table.key)
    if not recipe then return end
    PB_UTIL.clear_craft_cells(true)    -- credit + empty prior placement (cells reused)
    if not PB_UTIL.can_afford(recipe) then
        PB_UTIL.crafting_selected = recipe.key
        PB_UTIL.refresh_craft_state()
        return
    end
    for i = 1, 3 do
        for j = 1, 3 do
            local id = recipe.pattern[i][j]
            if id then
                local card = PB_UTIL.make_resource_tile(id, 0, 0)
                if card then
                    PB_UTIL.add_resource(id, -1)   -- reserve (same path as spawn)
                    local area = PB_UTIL.craft_cells[i][j]
                    card.states.drag.is = false
                    area:emplace(card)             -- custom type keeps drag.can = true
                    card.T.x = area.T.x + (area.T.w - card.T.w) / 2
                    card.T.y = area.T.y + (area.T.h - card.T.h) / 2
                end
            end
        end
    end
    PB_UTIL.crafting_selected = recipe.key
    PB_UTIL.refresh_craft_state()
end

-- Return all placed/mid-drag tiles whenever an overlay closes while our cells live,
-- BEFORE _orig_exit runs G.OVERLAY_MENU:remove() (which would area:remove the cells
-- with no credit). Forward whatever args are received (exit_overlay_menu ignores them).
if not PB_UTIL._craft_exit_hooked then
    PB_UTIL._craft_exit_hooked = true
    local _orig_exit = G.FUNCS.exit_overlay_menu
    G.FUNCS.exit_overlay_menu = function(...)
        if PB_UTIL.craft_cells then
            PB_UTIL.destroy_craft_cells()   -- credit + destroy all tiles + areas
            PB_UTIL.craft_on_change = nil
        end
        return _orig_exit(...)
    end
end
