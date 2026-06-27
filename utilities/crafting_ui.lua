-- Crafting Table: a "Crafting Table" button under the hotbar opens a centered
-- overlay listing recipes (left) with a live 3x3 grid + inventory row + output slot +
-- Back button (right). Minecraft-faithful layout:
--   [3x3 grid]  →  [output slot]  [Craft]
--   [inventory row of draggable source icons]
--   [Back button]
-- Build-once / mutate-in-place: overlay_menu is called EXACTLY ONCE (in open_crafting_table).

PB_UTIL.crafting_selected = PB_UTIL.crafting_selected or nil

-- Recipe square tunables (tune in-game).
local RECIPE_ICON_SZ   = 0.5
local RECIPES_PER_ROW  = 6
local RECIPE_PAGE_ROWS = 3                              -- rows shown per page
local RECIPES_PER_PAGE = RECIPES_PER_ROW * RECIPE_PAGE_ROWS  -- 18; page nav appears past this

-- Current recipe page (1-based). Persists across a page-flip reopen; reset to 1 on a fresh open.
PB_UTIL.recipe_page = PB_UTIL.recipe_page or 1

-- Sprite refs for the recipe squares, rebuilt each open and cleared on close
-- (destroy_craft_cells). update_recipe_opacity drives their live opacity + selection colour.
PB_UTIL.recipe_sprites = PB_UTIL.recipe_sprites or nil

-- Build the output-item icon Sprite for a recipe: the 34x34 resource icon for resource
-- outputs; for tool outputs the matching 34x34 tag-badge icon (bc_tool_icons); else the
-- output center's own card art (e.g. Torch). Built directly with the correct atlas, so
-- Sprite:init derives the right cell size. nil if the resource/center isn't resolvable yet.
function PB_UTIL.make_output_sprite(recipe, sz)
    local out = recipe.output
    if out.type == 'resource' then
        local r = PB_UTIL.RESOURCE_BY_ID[out.id]
        local atlas = r and G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]
        if not atlas then return nil end
        return Sprite(0, 0, sz, sz, atlas, r.pos)
    elseif out.type == 'joker' or out.type == 'consumable' then
        -- BalaCraft tools use the small framed badge icon (consistent with resources),
        -- not their full 71x95 card art. Non-tool consumables fall back to card art.
        local ipos = PB_UTIL.tool_icon_pos and PB_UTIL.tool_icon_pos[out.id]
        if ipos and PB_UTIL.tool_icon_atlas then
            local atlas = G.ASSET_ATLAS[PB_UTIL.tool_icon_atlas.key]
            if atlas then return Sprite(0, 0, sz, sz, atlas, ipos) end
        end
        local center = G.P_CENTERS[out.id]
        local atlas = center and G.ASSET_ATLAS[center.atlas or 'Joker']
        if not atlas then return nil end
        return Sprite(0, 0, sz, sz, atlas, center.pos)
    elseif out.type == 'station' then
        -- Base stations (e.g. the Furnace): the authentic MC block-face icon from bc_station_icons
        -- (furnace.lua / assets/gen_stations.py). Without this the station recipe square was blank.
        local pos   = PB_UTIL.STATION_ICONS and PB_UTIL.STATION_ICONS[out.id]
        local atlas = PB_UTIL.station_icon_atlas and G.ASSET_ATLAS[PB_UTIL.station_icon_atlas.key]
        if pos and atlas then return Sprite(0, 0, sz, sz, atlas, pos) end
    end
    return nil
end

-- Ingredient lines for a recipe's hover tooltip, in registry order (stable), e.g.
-- {'{C:attention}2{} Wood'}. Control codes are parsed by the tooltip popup builder.
local function recipe_tooltip_text(recipe)
    local need = PB_UTIL.recipe_ingredients(recipe)
    local lines = {}
    for _, r in ipairs(PB_UTIL.RESOURCES) do
        local n = need[r.id]
        if n then lines[#lines + 1] = '{C:attention}' .. n .. '{} ' .. (r.name or r.id) end
    end
    return lines
end

-- One recipe as a square output-icon button. Click -> bc_autofill (fills the craft grid).
-- Registers its sprite + node config in PB_UTIL.recipe_sprites so update_recipe_opacity can
-- drive live craftable-opacity + selection highlight without rebuilding the overlay.
local function recipe_square(recipe)
    local spr = PB_UTIL.make_dimmable(PB_UTIL.make_output_sprite(recipe, RECIPE_ICON_SZ))
    local cfg = {
        align = 'cm', padding = 0.06, r = 0.08,
        minw = RECIPE_ICON_SZ + 0.22, minh = RECIPE_ICON_SZ + 0.22,
        colour = G.C.UI.TRANSPARENT_DARK,
        button = 'bc_autofill', ref_table = { key = recipe.key },
        hover = true, shadow = true,
        tooltip = { title = recipe.name or recipe.key, text = recipe_tooltip_text(recipe) },
    }
    PB_UTIL.recipe_sprites[#PB_UTIL.recipe_sprites + 1] = { sprite = spr, recipe = recipe, config = cfg }
    return {
        n = G.UIT.C, config = cfg,
        nodes = spr and { { n = G.UIT.O, config = { object = spr } } } or {},
    }
end

-- How many pages the current recipe set spans (>= 1).
local function recipe_page_count()
    return math.max(1, math.ceil(#PB_UTIL.RECIPES / RECIPES_PER_PAGE))
end

-- A small "<" / ">" page-step button (greyed + inert at the ends).
local function page_btn(label, fn, enabled)
    return {
        n = G.UIT.C,
        config = {
            align = 'cm', padding = 0.06, r = 0.08, minw = 0.55, minh = 0.45,
            colour = enabled and G.C.BLUE or G.C.UI.TRANSPARENT_DARK,
            button = enabled and fn or nil, hover = enabled, shadow = true,
        },
        nodes = { { n = G.UIT.T, config = { text = label, scale = 0.45, colour = G.C.UI.TEXT_LIGHT } } },
    }
end

-- "[<] Page p/N [>]" nav row (only built when there's more than one page).
local function recipe_page_nav(page, pages)
    return {
        n = G.UIT.R, config = { align = 'cm', padding = 0.04 },
        nodes = {
            page_btn('<', 'bc_recipe_prev', page > 1),
            { n = G.UIT.C, config = { align = 'cm', padding = 0.06, minw = 1.3 }, nodes = {
                { n = G.UIT.T, config = { text = 'Page ' .. page .. '/' .. pages, scale = 0.3, colour = G.C.UI.TEXT_LIGHT } },
            } },
            page_btn('>', 'bc_recipe_next', page < pages),
        },
    }
end

-- Grid of recipe squares for the CURRENT page, RECIPES_PER_ROW wide. Clamps the page and resets
-- recipe_sprites first (fresh per build) so the per-frame opacity pass only tracks on-screen
-- squares. The page-nav row is added separately by build_crafting_modal (bottom of the panel).
local function recipe_grid_node()
    PB_UTIL.recipe_sprites = {}
    local total = #PB_UTIL.RECIPES
    local pages = recipe_page_count()
    local page  = math.max(1, math.min(pages, PB_UTIL.recipe_page or 1))
    PB_UTIL.recipe_page = page   -- clamp (recipe count may have shrunk since last open)

    local first = (page - 1) * RECIPES_PER_PAGE + 1
    local last  = math.min(first + RECIPES_PER_PAGE - 1, total)
    local rows, row, n = {}, nil, 0
    for i = first, last do
        if n % RECIPES_PER_ROW == 0 then
            row = { n = G.UIT.R, config = { align = 'cm', padding = 0.02 }, nodes = {} }
            rows[#rows + 1] = row
        end
        row.nodes[#row.nodes + 1] = recipe_square(PB_UTIL.RECIPES[i])
        n = n + 1
    end

    return { n = G.UIT.C, config = { align = 'cm', padding = 0.04 }, nodes = rows }
end

-- Flip the recipe page by `delta`, clamped to [1, pages]. Reopens the crafting overlay at the new
-- page via the standard open path: open_crafting_table -> build_craft_cells -> destroy_craft_cells
-- credits any in-progress grid tiles back to inventory (lossless) and rebuilds. overlay_menu only
-- does G.OVERLAY_MENU:remove() (it never calls exit_overlay_menu), so our exit wraps don't double-fire.
function PB_UTIL.change_recipe_page(delta)
    local pages = recipe_page_count()
    local p = math.max(1, math.min(pages, (PB_UTIL.recipe_page or 1) + delta))
    if p == (PB_UTIL.recipe_page or 1) then return end
    PB_UTIL.recipe_page = p
    play_sound('cardSlide1')
    PB_UTIL.open_crafting_table({ keep_page = true })
end

-- Live opacity (craftable -> 1, else dimmed) + selection highlight on the recipe squares.
function PB_UTIL.update_recipe_opacity()
    if not PB_UTIL.recipe_sprites then return end
    for _, e in ipairs(PB_UTIL.recipe_sprites) do
        if e.sprite and e.sprite.bc_overlay then
            e.sprite.bc_overlay[4] = PB_UTIL.can_craft(e.recipe) and 1 or 0.35
        end
        if e.config then
            e.config.colour = (PB_UTIL.crafting_selected == e.recipe.key)
                and G.C.GREEN or G.C.UI.TRANSPARENT_DARK
        end
    end
end

-- Single per-frame entry for the crafting modal (called from the Game:update wrap in
-- resource_ui.lua). Each half early-returns when its state is absent, so this is inert
-- whenever no crafting modal is open.
function PB_UTIL.update_crafting_modal()
    PB_UTIL.update_inventory()
    PB_UTIL.update_recipe_opacity()
    -- The Furnace shares the inventory source grid + per-frame driver; its updater early-returns
    -- unless the furnace is open (crafting_ui loads before furnace.lua, so guard on existence).
    if PB_UTIL.update_furnace_modal then PB_UTIL.update_furnace_modal() end
end

-- One state table living for the modal's lifetime. output_label is ALWAYS a string
-- ('' when no match) so the bound output T-node renders blank (tostring(nil)=='nil').
PB_UTIL.craft_state = PB_UTIL.craft_state or { output_label = '', warn_label = '', can_craft = false }

-- Per-frame func on the Craft button: ONLY changes colour from craft_state. Runs every
-- frame via UIElement:update (ui.lua:1024-1027). It must NOT toggle config.button --
-- the button is built with a non-nil button so collide/click are already enabled; the
-- bc_grid_craft callback self-guards on an invalid grid, so always-clickable is safe.
G.FUNCS.bc_can_craft_btn = function(e)
    e.config.colour = PB_UTIL.craft_state.can_craft and G.C.GREEN or G.C.UI.TRANSPARENT_LIGHT
end

-- Data-only half: compute match -> craft_state, NO UIElement lookups. Safe to call
-- before the overlay exists (during build).
function PB_UTIL.refresh_craft_state_data()
    local recipe = PB_UTIL.match_grid(PB_UTIL.read_grid())
    local can = false
    local warn = ''
    if recipe then
        local t = recipe.output.type
        -- Matched a valid card recipe but no free slot is the only "grid matches yet can't
        -- craft" case a player can actually hit (an unaffordable recipe leaves the grid empty
        -- -> no match), so spell it out instead of silently greying the button out.
        if t == 'joker' then
            local center = G.P_CENTERS[recipe.output.id]
            can = (center and PB_UTIL.has_joker_room()) and true or false
            if center and not PB_UTIL.has_joker_room() then warn = 'No Joker Slots!' end
        elseif t == 'consumable' then
            local center = G.P_CENTERS[recipe.output.id]
            can = (center and PB_UTIL.has_consumable_room()) and true or false
            if center and not PB_UTIL.has_consumable_room() then warn = 'No Card Slots!' end
        elseif t == 'station' then
            can = not (PB_UTIL.station_built and PB_UTIL.station_built(recipe.output.id))
            if not can then warn = 'Already built' end
        else
            can = true
        end
    end
    PB_UTIL.craft_state.can_craft = can
    PB_UTIL.craft_state.output_label = recipe and (recipe.name or recipe.key) or ''   -- '' not nil
    PB_UTIL.craft_state.warn_label = warn   -- '' unless a matched joker recipe has no slot
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
        local obj = icon.config.object
        local out = recipe and recipe.output
        local tpos = out and PB_UTIL.tool_icon_pos and PB_UTIL.tool_icon_pos[out.id]
        local show = false
        if out and out.type == 'resource' then
            local r = PB_UTIL.RESOURCE_BY_ID[out.id]
            if r then
                obj.atlas = G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]
                obj:set_sprite_pos(r.pos)
                show = true
            end
        elseif tpos and PB_UTIL.tool_icon_atlas then
            -- tool / torch output: its frameless icon (same 34x34 cell, so the atlas swap is safe)
            obj.atlas = G.ASSET_ATLAS[PB_UTIL.tool_icon_atlas.key]
            obj:set_sprite_pos(tpos)
            show = true
        elseif out and out.type == 'station' and PB_UTIL.STATION_ICONS
               and PB_UTIL.STATION_ICONS[out.id] and PB_UTIL.station_icon_atlas then
            -- station output (Furnace): its bc_station_icons block face (also 34x34, safe swap)
            obj.atlas = G.ASSET_ATLAS[PB_UTIL.station_icon_atlas.key]
            obj:set_sprite_pos(PB_UTIL.STATION_ICONS[out.id])
            show = true
        end
        -- Empty cell on no match (or a matched output with no icon, e.g. a future joker output):
        -- hide the icon; the name label below carries the item name.
        if obj.bc_overlay then obj.bc_overlay[4] = show and 1 or 0 end
    end
end

function PB_UTIL.build_crafting_modal()
    -- Seed craft_state from the (currently empty) grid before the UI binds to it.
    PB_UTIL.refresh_craft_state_data()   -- data-only seed (no UE lookups)

    -- Output slot: a grid-cell-style square (same look as the 3x3 cells) holding the matched
    -- item's icon. EMPTY (icon hidden) until a valid recipe sits in the grid -- the icon is
    -- dimmable and refresh_craft_state shows it (alpha 1) on a match, hides it (alpha 0) otherwise.
    local output_icon = PB_UTIL.make_dimmable(
        Sprite(0, 0, 0.5, 0.5, G.ASSET_ATLAS[PB_UTIL.icon_atlas.key], PB_UTIL.RESOURCE_BY_ID['wood'].pos))
    output_icon.bc_overlay[4] = 0   -- start empty (the grid opens empty)
    -- Output: a single 3x3-cell-sized SQUARE, vertically centred on the grid's MIDDLE row. The
    -- bg-bearing square (`output_square`) sits inside a FULL-HEIGHT transparent wrapper so it centres
    -- the way the arrow's '>' does. Why the wrapper: ui.lua stretches a row's UIT.C children to the
    -- tallest child (the 3-cell grid -- ui.lua:587), and a row's vertical-align centres only LEAF
    -- children individually (text/box/object -- ui.lua:631); a bg cell placed directly in the row
    -- either elongates (unpinned) or pins-but-sticks-to-the-top. The wrapper IS full height (so it
    -- isn't offset) and centres the fixed-size square within itself (the container path, ui.lua:634).
    local output_square = {
        n = G.UIT.C,
        config = { align = 'cm', padding = 0.03, r = 0.05, colour = G.C.UI.TRANSPARENT_DARK,
                   minw = 0.76, minh = 0.76 },   -- 0.76 = CELL 0.7 + 0.06
        nodes = {
            { n = G.UIT.O, config = { id = 'bc_craft_output_icon', object = output_icon } },
        },
    }
    local output_node = { n = G.UIT.C, config = { align = 'cm' }, nodes = { output_square } }
    -- Item name under the cell (bound; blank when no match).
    local output_label = {
        n = G.UIT.R, config = { align = 'cm' }, nodes = {
            { n = G.UIT.T, config = {
                id = 'bc_craft_output_label',
                ref_table = PB_UTIL.craft_state, ref_value = 'output_label',  -- bound (ui.lua:657)
                scale = 0.28, colour = G.C.WHITE } },
        },
    }

    -- Craft button: NON-nil button at construction so set_values:391 enables collide/click
    -- once; the per-frame func only changes colour. bc_grid_craft self-guards on an invalid
    -- grid, so an always-clickable button is safe.
    -- Craft button: 1 cell tall, to the RIGHT of the output cell, centred on the grid's middle row
    -- via the same full-height-wrapper trick as output_node above. The clickable node is the INNER
    -- one (keeps id/button/func/colour so set_values + bc_can_craft_btn still target it); the wrapper
    -- is inert. minh pins it to one cell so it reads as a normal button, not a 3-cell bar.
    local craft_btn_inner = {
        n = G.UIT.R,
        config = {
            id = 'bc_craft_button',
            align = 'cm', padding = 0.1, r = 0.1, minw = 1.6, minh = 0.76,   -- 1 cell tall
            colour = G.C.UI.TRANSPARENT_LIGHT,   -- initial; func overwrites on frame 1
            button = 'bc_grid_craft',            -- NON-nil at build (enables collide/click once)
            func = 'bc_can_craft_btn',           -- runs every frame (ui.lua:1024-1027), colour only
            hover = true, shadow = true,
        },
        nodes = { { n = G.UIT.T, config = { text = 'Craft', scale = 0.45, colour = G.C.UI.TEXT_LIGHT } } },
    }
    local craft_btn = { n = G.UIT.C, config = { align = 'cm' }, nodes = { craft_btn_inner } }

    -- Arrow node between grid and output.
    local arrow_node = {
        n = G.UIT.C, config = { align = 'cm', padding = 0.08 },
        nodes = { { n = G.UIT.T, config = { text = '>', scale = 0.6, colour = G.C.WHITE } } },
    }

    -- Back button (classic Balatro yellow/orange), FULL WIDTH. exit_overlay_menu is already
    -- wrapped by _craft_exit_hooked, which credits all tiles before closing.
    local back_btn = {
        n = G.UIT.R,
        config = {
            align = 'cm', minw = 8.6, padding = 0.1, r = 0.1, hover = true,
            colour = G.C.ORANGE,
            button = PB_UTIL.craft_back_to_base and 'bc_craft_back_to_base' or 'exit_overlay_menu',
            shadow = true,
        },
        nodes = { { n = G.UIT.T, config = { text = 'Back', scale = 0.5, colour = G.C.WHITE } } },
    }

    -- Left recipe panel content: title, the current page's grid, then -- when there's more than
    -- one page -- a clickable "[<] Page p/N [>]" nav row at the BOTTOM of the panel.
    local recipes_grid = recipe_grid_node()              -- also clamps PB_UTIL.recipe_page
    local recipe_pages = recipe_page_count()
    local left_nodes = {
        { n = G.UIT.R, config = { align = 'cm' }, nodes = { { n = G.UIT.T, config = { text = 'Recipes', scale = 0.5, colour = G.C.UI.TEXT_LIGHT } } } },
        -- Wrap the grid (a UIT.C) in a UIT.R so it STACKS below the title. Balatro lays C-type
        -- children out horizontally (ui.lua:196); an unwrapped grid-C would add its width beside
        -- the title (dead space on the right) and push the nav row to the top-right. Mirrors how
        -- build_inventory_node() is wrapped in an R below.
        { n = G.UIT.R, config = { align = 'cm' }, nodes = { recipes_grid } },
    }
    if recipe_pages > 1 then
        left_nodes[#left_nodes + 1] = recipe_page_nav(PB_UTIL.recipe_page, recipe_pages)
    end

    -- Crafting row: [3x3 grid] > [output cell] [Craft], ALL vertically centered so the arrow,
    -- output cell and Craft button line up with the grid's MIDDLE row (Minecraft layout). The
    -- name + warning labels sit on their own rows below.
    local craft_row = {
        n = G.UIT.R, config = { align = 'cm', padding = 0.06 },
        nodes = { PB_UTIL.build_grid_node(), arrow_node, output_node, craft_btn },
    }
    local warn_label = {
        n = G.UIT.R, config = { align = 'cm', padding = 0.02 }, nodes = {
            { n = G.UIT.T, config = {
                id = 'bc_craft_warn_label',
                ref_table = PB_UTIL.craft_state, ref_value = 'warn_label',
                scale = 0.28, colour = G.C.RED } },
        },
    }

    -- Vertical layout: [ TOP: recipes | crafting area ] / [ inventory ] / [ Back full width ].
    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0.1, r = 0.1, colour = G.C.GREY, minw = 9, minh = 5 },
        nodes = {
            -- TOP: split in half -- recipes (left) | crafting area (right)
            { n = G.UIT.R, config = { align = 'cm', padding = 0.08 }, nodes = {
                -- LEFT half: recipe grid + (page nav at the bottom). No minw -> the panel hugs
                -- the recipe grid (narrower than the old fixed 4.2, which left dead space).
                { n = G.UIT.C, config = { align = 'tm', padding = 0.06, r = 0.1, colour = G.C.BLACK, minh = 3 },
                  nodes = left_nodes },
                -- RIGHT half: crafting row (output cell aligned to the grid's middle row) + labels below.
                { n = G.UIT.C, config = { align = 'cm', padding = 0.06, r = 0.1, colour = G.C.BLACK, minw = 4.2, minh = 3 }, nodes = {
                    craft_row,
                    output_label,
                    warn_label,
                } },
            } },
            -- MIDDLE: inventory (8x3 generic slots)
            { n = G.UIT.R, config = { align = 'cm', minh = 0.1 }, nodes = {} },
            { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                { n = G.UIT.T, config = { text = 'Inventory', scale = 0.38, colour = G.C.UI.TEXT_LIGHT } },
            } },
            { n = G.UIT.R, config = { align = 'cm' }, nodes = { PB_UTIL.build_inventory_node() } },
            -- BOTTOM: Back (full width)
            { n = G.UIT.R, config = { align = 'cm', minh = 0.1 }, nodes = {} },
            back_btn,
        },
    }
end

function PB_UTIL.open_crafting_table(opts)
    -- Fresh open starts at page 1; a page-flip reopen (keep_page) preserves the chosen page.
    -- back='base' makes the Back button return to the Base launcher instead of closing; preserved
    -- across page-flip reopens (which pass keep_page) so paging doesn't lose the return target.
    if not (opts and opts.keep_page) then
        PB_UTIL.recipe_page = 1
        PB_UTIL.craft_back_to_base = (opts and opts.back == 'base') or false
    end
    PB_UTIL.crafting_selected = nil
    PB_UTIL.craft_state = PB_UTIL.craft_state or { output_label = '', warn_label = '', can_craft = false }
    PB_UTIL.craft_state.output_label = ''
    PB_UTIL.craft_state.warn_label = ''
    PB_UTIL.craft_state.can_craft = false
    PB_UTIL.build_craft_cells()                          -- nine live grid cell-areas (build once)
    PB_UTIL.build_inventory()                            -- 24 generic slots, populated from owned items
    PB_UTIL.craft_on_change = PB_UTIL.refresh_craft_state  -- grid changes mutate in place
    -- refresh_overlay swaps in place (no fly-in) when transitioning from another modal (the Base,
    -- a page-flip reopen); it falls back to a normal fly-in open when nothing is up (hotbar click).
    PB_UTIL.refresh_overlay(PB_UTIL.build_crafting_modal())  -- ONCE; never again while open
end

G.FUNCS.bc_open_crafting = function(e)
    PB_UTIL.open_crafting_table()
end

-- Recipe page navigation (only present when there's more than one page).
G.FUNCS.bc_recipe_prev = function(e) PB_UTIL.change_recipe_page(-1) end
G.FUNCS.bc_recipe_next = function(e) PB_UTIL.change_recipe_page(1) end

-- Spawn a recipe's 3x3 pattern into the grid cells, reserving one of each ingredient
-- (add_resource(-1)) -- the same placement clicking a recipe row performs. Callers MUST have
-- verified affordability (PB_UTIL.can_afford) and cleared/credited any prior placement first.
function PB_UTIL.fill_grid_with_recipe(recipe)
    if not recipe then return end
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
end

-- Grid Craft: placed tiles are already reserved. SELF-GUARD on an invalid grid / no
-- joker slot (the button is always clickable, so the guard is what enforces validity).
-- CONSUME placed tiles WITHOUT crediting (reuse-in-place), produce output. Never call
-- PB_UTIL.craft here (double-spend). After producing, AUTO-REFILL the grid with the same
-- recipe (if still affordable) so the player can click Craft repeatedly without re-selecting.
G.FUNCS.bc_grid_craft = function(e)
    local recipe = PB_UTIL.match_grid(PB_UTIL.read_grid())
    if not recipe then play_sound('cancel'); return end
    local kind   -- 'joker'/'consumable' for card outputs; nil for resource outputs
    if recipe.output.type == 'joker' then
        if not G.P_CENTERS[recipe.output.id] then play_sound('cancel'); return end
        if not PB_UTIL.has_joker_room() then play_sound('cancel'); return end
        kind = 'joker'
    elseif recipe.output.type == 'consumable' then
        if not G.P_CENTERS[recipe.output.id] then play_sound('cancel'); return end
        if not PB_UTIL.has_consumable_room() then play_sound('cancel'); return end
        kind = 'consumable'
    elseif recipe.output.type == 'station' then
        if PB_UTIL.station_built and PB_UTIL.station_built(recipe.output.id) then play_sound('cancel'); return end
    end
    -- A card output the active area is too full to hold but the dormant bench will catch (the
    -- room gate above already allowed it via has_*_room, which is bench-aware). Note it BEFORE
    -- produce_output mutates the bench, so we can tell the player WHERE it went: the modal's
    -- "Inventory" panel shows resources, not the consumable/joker bench, so an overflowed card
    -- would otherwise seem to vanish -- which reads as an illegal craft into a full area.
    local to_bench = kind and PB_UTIL.inventory_enabled and PB_UTIL.inventory_enabled()
        and PB_UTIL.active_has_room and not PB_UTIL.active_has_room(kind)
        and PB_UTIL.bench_has_room and PB_UTIL.bench_has_room(kind) and true or false
    PB_UTIL.clear_craft_cells(false)   -- destroy placed tiles in place, NO credit (spent)
    PB_UTIL.produce_output(recipe)     -- produce-half only (resource/joker + sound)
    -- Auto-refill: re-place the same recipe so Craft can be clicked again immediately. Only if
    -- still affordable after producing; otherwise leave the grid empty (button greys out).
    if PB_UTIL.can_afford(recipe) then
        PB_UTIL.fill_grid_with_recipe(recipe)
        PB_UTIL.crafting_selected = recipe.key
    end
    PB_UTIL.refresh_craft_state()      -- re-match the (refilled or empty) grid; updates button + output
    -- Set the transient "where it went" note AFTER refresh so the refill doesn't overwrite it.
    -- It clears on the next grid change (refresh_craft_state rewrites output_label).
    if to_bench then PB_UTIL.craft_state.output_label = 'Sent to Bench' end
end

-- Auto-fill from a recipe row click: clear current placement (returning tiles), then
-- spawn the recipe's pattern tiles into the matching cells via the reserve path.
G.FUNCS.bc_autofill = function(e)
    local recipe = e.config.ref_table and e.config.ref_table.key
        and PB_UTIL.recipe_by_key(e.config.ref_table.key)
    if not recipe then return end
    PB_UTIL.clear_craft_cells(true)    -- credit + empty prior placement (cells reused)
    if PB_UTIL.can_afford(recipe) then
        PB_UTIL.fill_grid_with_recipe(recipe)
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
            PB_UTIL.destroy_craft_cells()   -- credit + destroy all tiles + areas + inv
            PB_UTIL.craft_on_change = nil
        end
        return _orig_exit(...)
    end
end
