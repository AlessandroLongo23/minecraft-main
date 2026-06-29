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
-- 4 (not 6) per row keeps the side-by-side [Recipes | craft apparatus] inside the fixed left-column
-- width LW. At 6/row the Crafting content (~10.9) OVERFLOWED LW=10, so the Crafting box grew wider
-- than every other station's and the whole modal re-centred only for Crafting -- the "this workbench
-- is aligned differently" symptom. 4/row (~9.3) fits LW with margin, so all six boxes share one width.
local RECIPES_PER_ROW  = 4
local RECIPE_PAGE_ROWS = 3                              -- rows shown per page
local RECIPES_PER_PAGE = RECIPES_PER_ROW * RECIPE_PAGE_ROWS  -- 12; page nav appears past this

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
    -- The Furnace + the Anvil's "Forge Sheets" tab share the inventory source grid + per-frame
    -- driver; each updater early-returns unless its overlay is open (crafting_ui loads before
    -- furnace.lua, so guard on existence).
    if PB_UTIL.update_furnace_modal then PB_UTIL.update_furnace_modal() end
    if PB_UTIL.update_anvil_unified then PB_UTIL.update_anvil_unified() end
    if PB_UTIL.update_brew_modal then PB_UTIL.update_brew_modal() end
    -- The Composter composts on a drag-drop (router sets _composter_dirty); rebuild the shell here, one
    -- frame later, so it never re-enters the overlay build from inside Controller:L_cursor_release.
    if PB_UTIL._composter_dirty then
        PB_UTIL._composter_dirty = nil
        if PB_UTIL.rebuild_inv_overlay then PB_UTIL.rebuild_inv_overlay() end
    end
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

-- The Crafting Table's interactive content (recipe palette + 3x3 grid + output + Craft), as an
-- embeddable node for the unified Inventory modal's station area. The shared inventory + Back live
-- in the shell (build_base_shell). Returns a single G.UIT.C.
function PB_UTIL.crafting_station_content()
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

    -- Left recipe panel content: title, the current page's grid, then -- when there's more than
    -- one page -- a clickable "[<] Page p/N [>]" nav row at the BOTTOM of the panel.
    local recipes_grid = recipe_grid_node()              -- also clamps PB_UTIL.recipe_page
    local recipe_pages = recipe_page_count()
    local left_nodes = {
        { n = G.UIT.R, config = { align = 'cm' }, nodes = { { n = G.UIT.T, config = { text = 'Recipes', scale = 0.5, colour = G.C.UI.TEXT_LIGHT } } } },
        { n = G.UIT.R, config = { align = 'cm' }, nodes = { recipes_grid } },
    }
    if recipe_pages > 1 then
        left_nodes[#left_nodes + 1] = recipe_page_nav(PB_UTIL.recipe_page, recipe_pages)
    end

    -- Crafting row: [3x3 grid] > [output cell] [Craft], vertically centered (Minecraft layout).
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

    -- Station content: [ recipes | crafting area ], centred. The selected-workbench panel (shell)
    -- provides the single black container + the "Crafting Table" title above it -- no inner panels.
    return { n = G.UIT.C, config = { align = 'cm' }, nodes = {
        { n = G.UIT.R, config = { align = 'cm', padding = 0.08 }, nodes = {
            { n = G.UIT.C, config = { align = 'cm', padding = 0.06 }, nodes = left_nodes },
            { n = G.UIT.C, config = { align = 'cm', padding = 0.06 }, nodes = {
                craft_row, output_label, warn_label,
            } },
        } },
    } }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Unified Inventory + Base modal shell. Two rows:
--   ROW 1: [ active station content        | station picker (Workbench) ]
--   ROW 2: [ Inventory (used/total) + grid | MC Consumables            ]
--   [ Close ]
-- The station picker swaps the top-left; the inventory + MC slots persist. Equip/un-equip is
-- CLICK-based and allowed only outside a blind (inv_editable). Switching stations rebuilds the
-- overlay (refresh_overlay), which credits any in-grid tiles back to inventory (lossless).
-- ─────────────────────────────────────────────────────────────────────────────

PB_UTIL.active_station = PB_UTIL.active_station or 'crafting_table'

-- The picker stations. ALL render their content in the unified shell (`inframe`); `soon` are stubs;
-- `station` ones need that station built first.
local PICKER_STATIONS = {
    { id = 'crafting_table', name = 'Crafting',  icon = 'crafting_table',   inframe = true, always = true },
    { id = 'furnace',        name = 'Furnace',   icon = 'furnace',          inframe = true, station = 'furnace' },
    { id = 'anvil',          name = 'Anvil',     icon = 'anvil',            inframe = true, station = 'anvil' },
    { id = 'composter',      name = 'Composter', icon = 'composter',        inframe = true, station = 'composter' },
    { id = 'brewing_stand',  name = 'Brewing',   icon = 'brewing_stand',    inframe = true, station = 'brewing_stand' },
    { id = 'enchant',        name = 'Enchant',   icon = 'enchanting_table', inframe = true, station = 'enchanting_table' },
}

-- Transfers (equip / un-equip) are only allowed OUTSIDE a blind (shop / blind-select). During play
-- the modal is view-only.
function PB_UTIL.inv_editable()
    return G.STATE == G.STATES.SHOP or G.STATE == G.STATES.BLIND_SELECT
end

local function station_pick_icon(icon_id)
    local pos = icon_id and PB_UTIL.STATION_ICONS and PB_UTIL.STATION_ICONS[icon_id]
    local atlas = PB_UTIL.station_icon_atlas and G.ASSET_ATLAS[PB_UTIL.station_icon_atlas.key]
    if pos and atlas then return { n = G.UIT.O, config = { object = Sprite(0, 0, 0.5, 0.5, atlas, pos) } } end
    return { n = G.UIT.T, config = { text = '?', scale = 0.4, colour = G.C.UI.TEXT_INACTIVE } }
end

-- Display name shown ABOVE the Selected-Workbench container (every widget's title lives OUTSIDE it).
local STATION_DISPLAY = {
    crafting_table = 'Crafting Table', furnace = 'Furnace', anvil = 'Anvil',
    composter = 'Composter', brewing_stand = 'Brewing Stand', enchant = 'Enchant',
}

-- A widget = a TITLE row (OUTSIDE, above) + a TRULY-FIXED-size black container with its content centred.
-- "Fixed" is load-bearing: the box uses config.w/h + no_overflow='hv', which is the ONLY way the engine
-- hard-pins a node's size (ui.lua:215-230, :588-603). Plain minw/minh are just FLOORS -- content wider
-- or taller than them grows the box, which is what made each station's box (and the whole modal)
-- a different size/position. With a hard w/h and align='cm', set_alignments centres the content inside
-- the fixed box (ui.lua:634/638), so size AND position are identical for every station. Content MUST
-- fit within (w,h) or it overflows the box edge -- so w/h are sized to the LARGEST station (Crafting).
local function titled_panel(title, content, w, h)
    return { n = G.UIT.C, config = { align = 'tm', padding = 0.04, no_overflow = 'h', w = w }, nodes = {
        { n = G.UIT.R, config = { align = 'cm', padding = 0.04, no_overflow = 'h', w = w }, nodes = {
            { n = G.UIT.T, config = { text = title, scale = 0.36, colour = G.C.UI.TEXT_LIGHT } } } },
        -- The black box MUST be wrapped in a UIT.R: a bare UIT.C sibling of the title R lays out
        -- HORIZONTALLY (ui.lua:188-203), so the outer C's content_dimensions.w summed to ~2w while
        -- no_overflow pinned its T.w to w -- and set_alignments (ui.lua:638) then shifted every child
        -- by 0.5*(w-2w) = -0.5w, yanking the title + grid half a column LEFT (clipped titles, empty
        -- middle). Wrapping in an R makes the width MAX(title_w, box_w)=w, so the offset is ~0.
        { n = G.UIT.R, config = { align = 'cm' }, nodes = {
            { n = G.UIT.C, config = { align = 'cm', padding = 0.1, r = 0.1, colour = G.C.BLACK,
                minw = w, minh = h, w = w, h = h, no_overflow = 'hv' },
              nodes = { content } },
        } },
    } }
end

-- Top-right station picker cells, 3 per row (no title / panel of its own -- titled_panel wraps it).
-- The active station is highlighted; unbuilt / soon ones are greyed and inert.
local function picker_cells_node()
    local cells = {}
    for _, st in ipairs(PICKER_STATIONS) do
        local ready
        if st.soon then ready = false
        elseif st.station then ready = (PB_UTIL.station_built and PB_UTIL.station_built(st.station)) or false
        else ready = true end
        local active = (PB_UTIL.active_station == st.id)
        local btn = ready and 'bc_pick_station' or nil
        cells[#cells + 1] = {
            n = G.UIT.C, config = {
                align = 'cm', padding = 0.06, r = 0.08, minw = 1.0, minh = 1.0,
                colour = active and G.C.GREEN or G.C.UI.TRANSPARENT_DARK,
                button = btn, ref_table = { id = st.id }, hover = ready, shadow = true,
            },
            nodes = {
                { n = G.UIT.R, config = { align = 'cm' }, nodes = { station_pick_icon(st.icon) } },
                { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                    { n = G.UIT.T, config = { text = st.soon and (st.name .. ' (soon)') or st.name,
                        scale = 0.2, colour = ready and G.C.UI.TEXT_LIGHT or G.C.UI.TEXT_INACTIVE } } } },
            },
        }
    end
    local rows = {}
    for i = 1, #cells, 3 do
        local row = { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {} }
        for j = i, math.min(i + 2, #cells) do row.nodes[#row.nodes + 1] = cells[j] end
        rows[#rows + 1] = row
    end
    return { n = G.UIT.C, config = { align = 'cm' }, nodes = rows }
end

-- The Minecraft consumables: the equipped card FACES rendered directly in the fixed container -- NO
-- per-card slot background (the panel is the only bg). Click a face to store it back to the inventory;
-- view-only during a blind. (We can't embed the live G.bc_mc_consumeables CardArea -- the overlay's
-- teardown would :remove() and destroy that persistent area -- so this is a fixed row of faces.)
--
-- AT THE ANVIL the widget instead hosts the live tools/books SOURCE (anvil_src_area, a transient area
-- rebuilt on every open so embedding it is safe): the player's tools/books are drained here and dragged
-- straight into the Anvil's slots -- "everything you need is already in the consumable area". The Anvil
-- content itself no longer carries a source box (build_anvil_consumable_source sizes the area to fit RW).
local function consumables_content()
    if PB_UTIL.active_station == 'anvil' and PB_UTIL.anvil_src_area then
        return { n = G.UIT.C, config = { align = 'cm',
            minw = PB_UTIL.anvil_src_area.T.w, minh = PB_UTIL.anvil_src_area.T.h },
          nodes = { { n = G.UIT.O, config = { object = PB_UTIL.anvil_src_area } } } }
    end
    local area = G.bc_mc_consumeables
    local editable = PB_UTIL.inv_editable()
    local CW, CH = G.CARD_W, G.CARD_H
    local cards = {}
    for i = 1, (PB_UTIL.MC_SLOTS or 2) do
        local card = area and area.cards and area.cards[i]
        local center = card and card.config and card.config.center
        local spr = (center and center.atlas and G.ASSET_ATLAS[center.atlas] and center.pos)
            and Sprite(0, 0, CW, CH, G.ASSET_ATLAS[center.atlas], center.pos) or nil
        cards[#cards + 1] = {
            n = G.UIT.C, config = {
                align = 'cm', padding = 0.06, minw = CW, minh = CH,
                button = (card and editable) and 'bc_mc_unequip' or nil,
                ref_table = { index = i }, hover = (card and editable) or false },
            nodes = spr and { { n = G.UIT.O, config = { object = spr } } } or {},
        }
    end
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = cards }
end

-- Inventory content: the paged grid + (when >1 page) the page-nav row. The "Inventory  x/y slots"
-- header lives ABOVE the container (build_base_shell), so there's no capacity label here.
local function inventory_content()
    local nodes = { { n = G.UIT.R, config = { align = 'cm' }, nodes = { PB_UTIL.build_inventory_node() } } }
    local nav = PB_UTIL.build_inv_page_nav and PB_UTIL.build_inv_page_nav()
    if nav then nodes[#nodes + 1] = nav end
    return { n = G.UIT.C, config = { align = 'cm' }, nodes = nodes }
end

local function inv_title()
    local used = (PB_UTIL.inv_slots_used and PB_UTIL.inv_slots_used()) or 0
    local cap  = (PB_UTIL.inv_capacity and PB_UTIL.inv_capacity()) or 0
    return 'Inventory   ' .. used .. '/' .. cap .. ' slots'
end

local function station_content_node()
    local s = PB_UTIL.active_station
    if s == 'furnace'       and PB_UTIL.furnace_station_content   then return PB_UTIL.furnace_station_content() end
    if s == 'enchant'       and PB_UTIL.enchant_station_content   then return PB_UTIL.enchant_station_content() end
    if s == 'anvil'         and PB_UTIL.anvil_station_content     then return PB_UTIL.anvil_station_content() end
    if s == 'brewing_stand' and PB_UTIL.brewing_station_content   then return PB_UTIL.brewing_station_content() end
    if s == 'composter'     and PB_UTIL.composter_station_content then return PB_UTIL.composter_station_content() end
    return PB_UTIL.crafting_station_content()
end

-- TRULY-FIXED 2x2 grid. Every box is hard-pinned by titled_panel (config.w/h + no_overflow), so NO
-- station can change any box's size OR position -- the modal is byte-identical across all six. CRITICAL:
-- no_overflow does NOT clip or shrink content -- content larger than (w-0.2)x(h-0.2) (the box minus its
-- 0.1 padding/side) spills PAST the box and overlaps neighbours. So each dimension is sized to the
-- LARGEST content that lands in that slot. Measured maxima (world-units, default G.UIT.padding=0):
--   WL 10.4 -> usable 10.2; widest = Anvil 9.63 / Crafting 9.50 / Brewing 9.18 / Enchant 8.62.
--   WR 4.6  -> usable 4.4;  widest = Consumables 4.22 (two full G.CARD_W~2.05 faces, even when EMPTY);
--                           the Workbench picker is only 3.16 but shares WR so the right column aligns.
--   HT 4.1  -> usable 3.9;  tallest TOP = Crafting 3.72 (Recipes title + 3 rows + page-nav) / Enchant 3.62.
--                           SEL & PICK share HT, so the Inventory and Consumables boxes below them start
--                           at the SAME y (fixes "consumables not level with inventory").
--   HB 4.7  -> usable 4.5;  tallest BOTTOM = Inventory 4.32 WHEN PAGED (3 slot rows + count labels + the
--                           "< Page x/y >" nav row); single-page is 3.79.
-- The inventory grid is spread (INV_SLOT_W in crafting_grid.lua) to FILL WL, closing the gap to the right
-- column. If WL changes, re-tune INV_SLOT_W so 9*INV_SLOT_W + ~0.3 wrapper padding stays just UNDER
-- WL-0.2 (overflow now CLIPS -- keep a small safety margin rather than filling to the pixel).
local WL, WR = 10.4, 4.6     -- left / right column box width (HARD)
local HT     = 4.1           -- top-row box height: Selected Workbench + Workbench picker (HARD)
local HB     = 4.7           -- bottom-row box height: Inventory + Consumables (HARD)

-- The 2x2 grid built as TWO fixed-width COLUMNS, NOT two rows. (Rows drift: the ROOT stretches every row
-- to the widest one and re-centres its children, so any width difference between the rows offsets the
-- panels.) Columns make alignment structural: the LEFT column stacks Selected-Workbench over Inventory,
-- both width WL, so they physically share left+right edges; the RIGHT column stacks the picker over
-- Consumables, both WR. Equal top/bottom box heights (HT for both top boxes, HB for both bottom boxes)
-- line up the rows. Panels stack VERTICALLY only when each is wrapped in a UIT.R (R children stack; a
-- bare UIT.C child lays out horizontally -- the engine keys layout off the CHILD's type, ui.lua:188-203).
local function vstack(panel)
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = { panel } }
end

function PB_UTIL.build_base_shell()
    local sel_title = STATION_DISPLAY[PB_UTIL.active_station] or 'Crafting Table'
    local left_col = { n = G.UIT.C, config = { align = 'tm', padding = 0.16 }, nodes = {
        vstack(titled_panel(sel_title, station_content_node(), WL, HT)),
        vstack(titled_panel(inv_title(), inventory_content(), WL, HB)),
    } }
    local right_col = { n = G.UIT.C, config = { align = 'tm', padding = 0.16 }, nodes = {
        vstack(titled_panel('Workbench', picker_cells_node(), WR, HT)),
        vstack(titled_panel('Consumables', consumables_content(), WR, HB)),
    } }
    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0.12, r = 0.1, colour = G.C.GREY },
        nodes = {
            { n = G.UIT.R, config = { align = 'tm' }, nodes = { left_col, right_col } },
            { n = G.UIT.R, config = { align = 'cm', minh = 0.4 }, nodes = {} },   -- gap before Close
            { n = G.UIT.R, config = { align = 'cm', minw = 8.6, padding = 0.1, r = 0.1, hover = true,
                colour = G.C.ORANGE, button = 'exit_overlay_menu', shadow = true },
              nodes = { { n = G.UIT.T, config = { text = 'Close', scale = 0.5, colour = G.C.WHITE } } } },
        },
    }
end

-- Picker-id -> the built-station id it requires (derived from PICKER_STATIONS; nil = always open).
local STATION_REQUIRES = {}
for _, st in ipairs(PICKER_STATIONS) do if st.station then STATION_REQUIRES[st.id] = st.station end end

-- Single entry point for the unified modal. `station` selects the active workbench (defaults to the
-- last one). Tears down EVERY prior station's live cells, builds the active one's + the shared
-- inventory, then (re)builds the overlay in place. Every station now renders in-frame.
function PB_UTIL.open_inventory(station, opts)
    station = station or PB_UTIL.active_station or 'crafting_table'
    local req = STATION_REQUIRES[station]
    if req and not (PB_UTIL.station_built and PB_UTIL.station_built(req)) then
        station = 'crafting_table'   -- not built yet -> fall back to the always-open table
    end
    PB_UTIL.active_station = station

    -- Tear down ALL station cell sets; only the active one is rebuilt below, so exactly one per-frame
    -- updater is ever live and no stale drag slots linger. Each destroyer self-guards + credits its
    -- reserved tiles (anvil also restores tools/books to MC/storage). They also drop the shared
    -- inventory areas, which build_inventory() recreates.
    if PB_UTIL.destroy_craft_cells   then PB_UTIL.destroy_craft_cells() end
    if PB_UTIL.destroy_furnace_cells then PB_UTIL.destroy_furnace_cells() end
    if PB_UTIL.destroy_brew_cells    then PB_UTIL.destroy_brew_cells() end
    if PB_UTIL.destroy_anvil_cells   then PB_UTIL.destroy_anvil_cells() end
    PB_UTIL.craft_on_change   = nil
    PB_UTIL.furnace_on_change = nil
    PB_UTIL.anvil_on_change   = nil

    if station == 'furnace' then
        PB_UTIL.recipe_sprites = nil   -- crafting's recipe squares aren't on screen
        PB_UTIL.furnace_state = PB_UTIL.furnace_state or { fuel_label = '', can_smelt = false }
        PB_UTIL.furnace_state.fuel_label = 'Fuel: ' .. PB_UTIL.get_furnace_fuel()
        PB_UTIL.furnace_state.can_smelt = false
        PB_UTIL.furnace_last_out = nil
        PB_UTIL.build_furnace_cells()
        PB_UTIL.furnace_on_change = PB_UTIL.update_furnace_modal
    elseif station == 'anvil' then
        PB_UTIL.recipe_sprites = nil
        PB_UTIL.build_anvil_unified_cells()       -- A/B input slots (accept ore tiles AND tool/book cards)
        PB_UTIL.build_anvil_consumable_source()   -- drain equipped + materialize stored tools/books
        PB_UTIL.anvil_on_change = PB_UTIL.update_anvil_unified
        if PB_UTIL.update_anvil_unified then PB_UTIL.update_anvil_unified() end   -- seed label/hint pre-layout
    elseif station == 'brewing_stand' then
        PB_UTIL.recipe_sprites = nil
        PB_UTIL.brew_state = PB_UTIL.brew_state or { fuel_label = '', can_brew = false, can_collect = false }
        PB_UTIL.brew_state.fuel_label = 'Fuel: ' .. PB_UTIL.get_brew_fuel()
        PB_UTIL.brew_state.can_brew = false
        PB_UTIL.brew_state.can_collect = false
        if PB_UTIL.brew_bottle_state then PB_UTIL.brew_bottle_state() end   -- ensure the persistent bottle is seeded
        PB_UTIL.build_brew_cells()
        PB_UTIL.furnace_on_change = PB_UTIL.update_brew_modal   -- the brew drop router uses furnace_on_change
    elseif station == 'composter' or station == 'enchant' then
        PB_UTIL.recipe_sprites = nil   -- these stations have no 3x3 grid / recipe squares
    else
        if not (opts and opts.keep_page) then PB_UTIL.recipe_page = 1 end
        PB_UTIL.crafting_selected = nil
        PB_UTIL.craft_state = PB_UTIL.craft_state or { output_label = '', warn_label = '', can_craft = false }
        PB_UTIL.craft_state.output_label = ''
        PB_UTIL.craft_state.warn_label = ''
        PB_UTIL.craft_state.can_craft = false
        PB_UTIL.build_craft_cells()
        PB_UTIL.craft_on_change = PB_UTIL.refresh_craft_state
    end
    PB_UTIL.build_inventory()
    -- Equipping a stored item / flipping the inventory page rebuilds via a full re-open: refresh_overlay's
    -- :remove() DESTROYS the embedded CardAreas (functions.lua), so the rebuild MUST create fresh cells
    -- (open_inventory does: destroy_*_cells credits placed tiles, then builds new areas) -- reusing the
    -- live cells would re-embed destroyed areas (cards=nil) and crash. keep_page preserves the recipe page.
    PB_UTIL.inv_overlay_rebuild = function() PB_UTIL.open_inventory(PB_UTIL.active_station, { keep_page = true }) end
    PB_UTIL.refresh_overlay(PB_UTIL.build_base_shell())
end

-- Rebuild whichever overlay currently hosts the shared inventory grid (set by its opener). Falls back
-- to the Base modal. Used by the equip / un-equip handlers so they refresh in place after moving an item.
function PB_UTIL.rebuild_inv_overlay()
    if PB_UTIL.inv_overlay_rebuild then PB_UTIL.inv_overlay_rebuild()
    else PB_UTIL.open_inventory(PB_UTIL.active_station, { keep_page = true }) end
end

-- Back-compat alias (the recipe pager + any legacy caller route through the unified modal).
function PB_UTIL.open_crafting_table(opts)
    PB_UTIL.open_inventory('crafting_table', opts)
end

G.FUNCS.bc_open_crafting = function(e) PB_UTIL.open_inventory('crafting_table') end

G.FUNCS.bc_pick_station = function(e)
    local id = e.config.ref_table and e.config.ref_table.id
    if id then PB_UTIL.open_inventory(id) end
end

G.FUNCS.bc_inv_equip = function(e)
    if not PB_UTIL.inv_editable() then play_sound('cancel'); return end
    local idx = e.config.ref_table and e.config.ref_table.index
    if idx and PB_UTIL.equip_stored_consumable and PB_UTIL.equip_stored_consumable(idx) then
        play_sound('cardSlide1')
        PB_UTIL.rebuild_inv_overlay()
    else play_sound('cancel') end
end

G.FUNCS.bc_mc_unequip = function(e)
    if not PB_UTIL.inv_editable() then play_sound('cancel'); return end
    local idx = e.config.ref_table and e.config.ref_table.index
    local area = G.bc_mc_consumeables
    local card = area and area.cards and area.cards[idx]
    if card and PB_UTIL.unequip_mc_consumable and PB_UTIL.unequip_mc_consumable(card) then
        play_sound('cardSlide1')
        PB_UTIL.rebuild_inv_overlay()
    else play_sound('cancel') end
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
    elseif recipe.output.type == 'resource' then
        -- Ingredients are already spent into the grid tiles, so check the output against the current
        -- (post-spend) inventory capacity. Blocking just leaves the placed tiles for the player to
        -- reclaim (right-click / close), so nothing is lost.
        if PB_UTIL.inv_can_fit_resource
           and not PB_UTIL.inv_can_fit_resource(recipe.output.id, recipe.output.amount or 1) then
            play_sound('cancel'); return
        end
    end
    PB_UTIL.clear_craft_cells(false)   -- destroy placed tiles in place, NO credit (spent)
    PB_UTIL.produce_output(recipe)     -- produce-half only (resource/joker/consumable/station + sound)
    -- A consumable lands in the Consumables widget and a station unlocks in the Workbench picker -- both
    -- are baked into the shell, so a full rebuild is the only way they refresh IMMEDIATELY (not just on
    -- reopen). The rebuild re-builds an empty grid (auto-refill is skipped for these), which is fine: you
    -- craft a station once, and a fresh consumable craft re-selecting the recipe is acceptable.
    if recipe.output.type == 'consumable' or recipe.output.type == 'station' then
        -- A crafted consumable lands in the VANILLA G.consumeables first; the per-frame reconcile then
        -- routes MC items (tools/potions/etc.) into G.bc_mc_consumeables (or the inventory). Run that
        -- reconcile NOW -- before the rebuild snapshots the Consumables widget -- so the new item shows
        -- immediately; otherwise it only lands after the snapshot and appears only on the next reopen.
        if recipe.output.type == 'consumable' and PB_UTIL.reconcile_mc_consumables then
            PB_UTIL.reconcile_mc_consumables()
        end
        if PB_UTIL.rebuild_inv_overlay then PB_UTIL.rebuild_inv_overlay() end
        return
    end
    -- Resource / joker outputs don't touch the shared widgets: keep the grid populated (auto-refill) so
    -- Craft can be clicked again immediately. Only if still affordable; else leave it empty (button greys).
    if PB_UTIL.can_afford(recipe) then
        PB_UTIL.fill_grid_with_recipe(recipe)
        PB_UTIL.crafting_selected = recipe.key
    end
    PB_UTIL.refresh_craft_state()      -- re-match the (refilled or empty) grid; updates button + output
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

-- THE single overlay-close teardown (Close / ESC): return every reserved tile and restore the Anvil's
-- tools/books whenever a station's cells are live, BEFORE _orig_exit runs G.OVERLAY_MENU:remove()
-- (which would area:remove the cells with no credit). Each destroyer self-guards on its own cells, and
-- only one station is ever active, so listing all four is safe. (Replaces the old per-station exit
-- wraps in furnace.lua / brewing_ui.lua.) Forward whatever args are received (exit_overlay_menu ignores them).
if not PB_UTIL._craft_exit_hooked then
    PB_UTIL._craft_exit_hooked = true
    local _orig_exit = G.FUNCS.exit_overlay_menu
    G.FUNCS.exit_overlay_menu = function(...)
        if PB_UTIL.craft_cells   then PB_UTIL.destroy_craft_cells()   end
        if PB_UTIL.furnace_cells then PB_UTIL.destroy_furnace_cells() end
        if PB_UTIL.brew_cells    then PB_UTIL.destroy_brew_cells()    end
        if PB_UTIL.anvil_unified_cells or PB_UTIL.anvil_src_area then PB_UTIL.destroy_anvil_cells() end
        PB_UTIL.craft_on_change   = nil
        PB_UTIL.furnace_on_change = nil
        PB_UTIL.anvil_on_change   = nil
        return _orig_exit(...)
    end
end
