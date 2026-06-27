-- Brewing Stand overlay — a Minecraft-faithful SPATIAL drag UI (modelled on the Furnace, NOT a list
-- of recipe buttons). Layout: a Blaze-Powder fuel slot + gauge on the LEFT, a single ingredient slot
-- on TOP, a bubble arrow down to ONE bottle slot below, a Brew button on the right, then the shared
-- Inventory grid + Back. You feed ingredients sequentially (Nether Wart -> a base -> optional
-- modifiers); the bottle advances through water -> awkward -> effect potion (+mods) and PERSISTS
-- across closing the stand (G.GAME.balacraft.brew_bottle). Collect takes the finished potion out.
--
-- All state + the transition engine live in brewing.lua (brew_step/brew_can/brew_collect/...). The
-- fuel + ingredient drop slots are real reserved-tile CardAreas (PB_UTIL.brew_cells, built in
-- crafting_grid.lua); the bottle slot holds NO card -- it is the display-only node id
-- 'bc_brew_bottle_slot' hit-tested by the shared drag router. Counts/fuel/can_brew/preview are live
-- (bound refs + a per-frame update_brew_modal), so an action never rebuilds the overlay.

local BREW_CELL = 0.85   -- bottle display square (tune in-game)

-- ---- small UI helpers (mirror furnace.lua's) ----
local function text_row(str, scale, colour)
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
        { n = G.UIT.T, config = { text = str, scale = scale or 0.4, colour = colour or G.C.UI.TEXT_LIGHT } } } }
end

local function res_icon(id, sz)
    local r = PB_UTIL.RESOURCE_BY_ID[id]
    local atlas = r and PB_UTIL.icon_atlas and G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]
    if not r or not atlas then return { n = G.UIT.T, config = { text = ' ', scale = 0.3 } } end
    return { n = G.UIT.O, config = { object = Sprite(0, 0, sz or 0.5, sz or 0.5, atlas, r.pos) } }
end

local function full_btn(label, fn, colour)
    return {
        n = G.UIT.R, config = { align = 'cm', minw = 6, padding = 0.1, r = 0.1, hover = true,
            colour = colour or G.C.ORANGE, button = fn, shadow = true },
        nodes = { { n = G.UIT.T, config = { text = label, scale = 0.5, colour = G.C.WHITE } } } }
end

-- (atlas, pos) for a brew-content's small icon: water/awkward -> the resource icon atlas; a finished
-- potion or a *_pre intermediate -> the potion icon atlas (a *_pre shows its TARGET potion's icon).
-- The potion icon shares its source sprite with the potion CARD (gen_potion_icons / gen_potion_cards).
-- Returns nil if not resolvable yet (atlas not loaded / unknown content).
local function content_atlas_pos(content)
    if content == 'water' or content == 'awkward' then
        local rid = (content == 'awkward') and 'awkward_potion' or 'water_bottle'
        local r = PB_UTIL.RESOURCE_BY_ID and PB_UTIL.RESOURCE_BY_ID[rid]
        local atlas = PB_UTIL.icon_atlas and G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]
        if r and r.pos and atlas then return atlas, r.pos end
        return nil
    end
    local pid = (content == 'poison_pre' and 'poison')
        or (content == 'harming_pre' and 'harming') or content
    local p = PB_UTIL.POTION_BY_ID and PB_UTIL.POTION_BY_ID[pid]
    local atlas = PB_UTIL.potion_icon_atlas and G.ASSET_ATLAS[PB_UTIL.potion_icon_atlas.key]
    if p and p.icon_pos and atlas then return atlas, p.icon_pos end
    return nil
end
PB_UTIL.brew_content_icon = content_atlas_pos

-- A small icon node for a brew content (blank text node if its atlas isn't ready).
local function content_icon_node(content, sz)
    local atlas, pos = content_atlas_pos(content)
    if atlas and pos then
        return { n = G.UIT.O, config = { object = Sprite(0, 0, sz or 0.4, sz or 0.4, atlas, pos) } }
    end
    return { n = G.UIT.T, config = { text = ' ', scale = 0.3 } }
end

-- Friendly name for a brew content (recipe-row tooltips).
local function content_name(content)
    if content == 'water' then return 'Water Bottle' end
    if content == 'awkward' then return 'Awkward Potion' end
    if content == 'poison_pre' then return 'Poison (add Gunpowder)' end
    if content == 'harming_pre' then return 'Harming (add Gunpowder)' end
    local p = PB_UTIL.POTION_BY_ID and PB_UTIL.POTION_BY_ID[content]
    return (p and p.name) or content
end

-- The bottle slot: a dark square (id 'bc_brew_bottle_slot', hit-tested by the drag router) holding a
-- single dimmable display Sprite (id 'bc_brew_bottle_icon') repainted from the bottle state each frame.
local function brew_bottle_node()
    local atlas = PB_UTIL.icon_atlas and G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]
    local inner
    if atlas then
        local wb = PB_UTIL.RESOURCE_BY_ID and PB_UTIL.RESOURCE_BY_ID['water_bottle']
        local pos = (wb and wb.pos) or { x = 0, y = 0 }
        local spr = PB_UTIL.make_dimmable(Sprite(0, 0, 0.62, 0.62, atlas, pos))
        spr.bc_overlay[4] = 0   -- hidden until the bottle holds something
        inner = { n = G.UIT.O, config = { id = 'bc_brew_bottle_icon', object = spr } }
    else
        inner = { n = G.UIT.T, config = { text = ' ', scale = 0.3 } }
    end
    return {
        n = G.UIT.C,
        config = { id = 'bc_brew_bottle_slot', align = 'cm', padding = 0.03, r = 0.05,
                   colour = G.C.UI.TRANSPARENT_DARK, minw = BREW_CELL, minh = BREW_CELL },
        nodes = { inner },
    }
end

-- Live display state (bound into the overlay; refreshed each frame by update_brew_modal).
PB_UTIL.brew_state = PB_UTIL.brew_state or { fuel_label = '', can_brew = false, can_collect = false }

-- Repaint the bottle icon from G.GAME.balacraft.brew_bottle, using the small 34x34 icons (NOT the
-- 71x95 card, which clipped): water/awkward -> resource icon; a finished potion -> its bottle icon;
-- an intermediate (poison_pre / harming_pre) -> the target potion's icon, dimmed; empty -> hidden.
function PB_UTIL.refresh_brew_bottle()
    if not (G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID) then return end
    local icon = G.OVERLAY_MENU:get_UIE_by_ID('bc_brew_bottle_icon')
    if not (icon and icon.config and icon.config.object) then return end
    local obj = icon.config.object
    local bottle = PB_UTIL.brew_bottle_state and PB_UTIL.brew_bottle_state()
    local content = (bottle and bottle.content) or 'empty'

    local atlas, pos = content_atlas_pos(content)
    if content == 'empty' or not (atlas and pos) then
        if obj.bc_overlay then obj.bc_overlay[4] = 0 end
        return
    end
    obj.atlas = atlas
    obj:set_sprite_pos(pos)
    obj.T.w, obj.T.h = 0.62, 0.62   -- square, same sizing as the water/awkward + potion icons
    local dim = (content == 'poison_pre' or content == 'harming_pre')
    if obj.bc_overlay then obj.bc_overlay[4] = dim and 0.45 or 1 end
end

-- ---- recipe guide (left panel) ----
-- A visual guide: vertical [ingredient] + [bottle] = [bottle] rows. Mirrors PB_UTIL.BREW_TRANSITIONS
-- (brewing.lua) in a curated order; the 3 modifier rows show the enhancers. Non-clickable; each row
-- has a name tooltip. Laid out as a 2-column grid so all 14 rows fit beside the apparatus.
local BREW_GUIDE = {
    { 'nether_wart',          'water',        'awkward' },
    { 'sugar',                'awkward',      'swiftness' },
    { 'blaze_powder',         'awkward',      'strength' },
    { 'glistering_melon',     'awkward',      'instant_health' },
    { 'ghast_tear',           'awkward',      'healing' },
    { 'golden_carrot',        'awkward',      'night_vision' },
    { 'spider_eye',           'awkward',      'poison_pre' },
    { 'gunpowder',            'poison_pre',   'poison' },
    { 'fermented_spider_eye', 'awkward',      'harming_pre' },
    { 'gunpowder',            'harming_pre',  'harming' },
    { 'fermented_spider_eye', 'night_vision', 'invisibility' },
}
-- Modifier rows: { ingredient, label, representative potion, tooltip name }.
local BREW_MODS_GUIDE = {
    { 'glowstone_dust', 'II',     'strength', 'Glowstone Dust: Level II' },
    { 'redstone',       'Long',   'strength', 'Redstone: longer effect' },
    { 'dragon_breath',  'Linger', 'poison',   "Dragon's Breath: lingering" },
}

local function glyph(t)
    return { n = G.UIT.C, config = { align = 'cm', padding = 0.015 }, nodes = {
        { n = G.UIT.T, config = { text = t, scale = 0.3, colour = G.C.UI.TEXT_INACTIVE } } } }
end

-- One guide row: [ing] + [from] = [to] (+ optional modifier label), a hoverable box w/ name tooltip.
local function guide_row(ing, from_content, to_content, label, name)
    local cells = {
        { n = G.UIT.C, config = { align = 'cm', padding = 0.015 }, nodes = { res_icon(ing, 0.32) } },
        glyph('+'),
        { n = G.UIT.C, config = { align = 'cm', padding = 0.015 }, nodes = { content_icon_node(from_content, 0.32) } },
        glyph('='),
        { n = G.UIT.C, config = { align = 'cm', padding = 0.015 }, nodes = { content_icon_node(to_content, 0.32) } },
    }
    if label then
        cells[#cells + 1] = { n = G.UIT.C, config = { align = 'cm', padding = 0.015 }, nodes = {
            { n = G.UIT.T, config = { text = label, scale = 0.26, colour = G.C.ORANGE } } } }
    end
    return { n = G.UIT.C, config = { align = 'cm', padding = 0.02 }, nodes = { {
        n = G.UIT.R, config = { align = 'cm', padding = 0.04, r = 0.05, minw = 1.9, minh = 0.46,
            colour = G.C.UI.TRANSPARENT_DARK, hover = name ~= nil,
            tooltip = name and { text = { name } } or nil },
        nodes = cells } } }
end

-- The left recipe-guide panel: a 2-column grid of all guide rows (bottle steps + modifier rows).
local function brew_recipe_panel()
    local all = {}
    for _, s in ipairs(BREW_GUIDE) do all[#all + 1] = { s[1], s[2], s[3], nil, content_name(s[3]) } end
    for _, m in ipairs(BREW_MODS_GUIDE) do all[#all + 1] = { m[1], m[3], m[3], m[2], m[4] } end
    local rows, row = {}, nil
    for i, s in ipairs(all) do
        if (i - 1) % 2 == 0 then
            row = { n = G.UIT.R, config = { align = 'cm', padding = 0.01 }, nodes = {} }
            rows[#rows + 1] = row
        end
        row.nodes[#row.nodes + 1] = guide_row(s[1], s[2], s[3], s[4], s[5])
    end
    return { n = G.UIT.C, config = { align = 'tm', padding = 0.06, r = 0.1, colour = G.C.BLACK }, nodes = {
        text_row('Recipes', 0.42, G.C.UI.TEXT_LIGHT),
        { n = G.UIT.C, config = { align = 'cm', padding = 0.01 }, nodes = rows },
    } }
end

-- ---- modal ----
function PB_UTIL.build_brewing_modal()
    -- Apparatus column: fuel slot + gauge (left), ingredient -> arrow -> bottle (centre), Brew (right).
    -- Slot nodes are each wrapped in a UIT.R (a UIT.C nested directly in a UIT.C lays out side-by-side).
    local fuel_col = { n = G.UIT.C, config = { align = 'cm', padding = 0.06 }, nodes = {
        { n = G.UIT.R, config = { align = 'cm' }, nodes = { PB_UTIL.furnace_slot_node(PB_UTIL.brew_fuel_area) } },
        { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
            res_icon('blaze_powder', 0.34),
            { n = G.UIT.T, config = { id = 'bc_brew_fuel_label', ref_table = PB_UTIL.brew_state,
                ref_value = 'fuel_label', scale = 0.32, colour = G.C.ORANGE } },
        } },
    } }

    local center_col = { n = G.UIT.C, config = { align = 'cm', padding = 0.04 }, nodes = {
        { n = G.UIT.R, config = { align = 'cm' }, nodes = { PB_UTIL.furnace_slot_node(PB_UTIL.brew_ingredient_area) } },
        { n = G.UIT.R, config = { align = 'cm', padding = 0.02 }, nodes = {
            { n = G.UIT.T, config = { text = 'v', scale = 0.5, colour = G.C.UI.TEXT_INACTIVE } } } },
        { n = G.UIT.R, config = { align = 'cm' }, nodes = { brew_bottle_node() } },
    } }

    local brew_btn = { n = G.UIT.C, config = { align = 'cm' }, nodes = { {
        n = G.UIT.R, config = { id = 'bc_brew_button', align = 'cm', padding = 0.1, r = 0.1,
            minw = 1.6, minh = BREW_CELL, colour = G.C.UI.TRANSPARENT_LIGHT,
            button = 'bc_brew_do', func = 'bc_brew_can_btn', hover = true, shadow = true },
        nodes = { { n = G.UIT.T, config = { text = 'Brew', scale = 0.45, colour = G.C.UI.TEXT_LIGHT } } },
    } } }

    local apparatus = { n = G.UIT.R, config = { align = 'cm', padding = 0.06 },
        nodes = { fuel_col, center_col, brew_btn } }

    -- Collect: green/enabled (per-frame) when a finished potion sits in the bottle and there is room.
    local collect_btn = { n = G.UIT.R, config = { id = 'bc_brew_collect_btn', align = 'cm', minw = 4,
        padding = 0.1, r = 0.1, hover = true, colour = G.C.UI.TRANSPARENT_LIGHT,
        button = 'bc_brew_collect', func = 'bc_brew_can_collect_btn', shadow = true },
        nodes = { { n = G.UIT.T, config = { text = 'Collect Potion', scale = 0.45, colour = G.C.UI.TEXT_LIGHT } } } }

    -- RIGHT panel = the apparatus + Collect; LEFT panel = the recipe guide. Two columns side by side.
    local right_panel = { n = G.UIT.C, config = { align = 'cm', padding = 0.06, r = 0.1, colour = G.C.BLACK }, nodes = {
        { n = G.UIT.R, config = { align = 'cm' }, nodes = { apparatus } },
        { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = { collect_btn } },
    } }
    local two_col = { n = G.UIT.R, config = { align = 'cm', padding = 0.06 },
        nodes = { brew_recipe_panel(), right_panel } }

    return { n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0.12, r = 0.1, colour = G.C.GREY, minw = 9, minh = 6 },
        nodes = {
            text_row('Brewing Stand', 0.6, G.C.PURPLE or G.C.ORANGE),
            two_col,
            { n = G.UIT.R, config = { align = 'cm', minh = 0.1 }, nodes = {} },
            { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                { n = G.UIT.T, config = { text = 'Inventory', scale = 0.38, colour = G.C.UI.TEXT_LIGHT } } } },
            { n = G.UIT.R, config = { align = 'cm' }, nodes = { PB_UTIL.build_inventory_node() } },
            { n = G.UIT.R, config = { align = 'cm', minh = 0.1 }, nodes = {} },
            full_btn('Back', 'bc_brewing_back'),
        } }
end

function PB_UTIL.open_brewing()
    PB_UTIL.brew_state = PB_UTIL.brew_state or { fuel_label = '', can_brew = false, can_collect = false }
    PB_UTIL.brew_state.fuel_label = 'Fuel: ' .. PB_UTIL.get_brew_fuel()
    PB_UTIL.brew_state.can_brew = false
    PB_UTIL.brew_state.can_collect = false
    PB_UTIL.brew_bottle_state()                              -- ensure the persistent bottle is seeded
    PB_UTIL.build_brew_cells()                               -- fuel + ingredient drop slots
    PB_UTIL.build_inventory()                                -- shared draggable source grid
    PB_UTIL.furnace_on_change = PB_UTIL.update_brew_modal    -- drag/right-click -> immediate refresh
    PB_UTIL.refresh_overlay(PB_UTIL.build_brewing_modal())   -- swap in place (no fly-in)
end

-- Per-frame maintenance (called from update_crafting_modal in crafting_ui.lua). Inert unless the
-- Brewing Stand is open. Keeps the fuel gauge + Brew/Collect-enabled state current, snaps slot tiles
-- to their settled centres (auto-refilled tiles are created post-layout), and repaints the bottle.
function PB_UTIL.update_brew_modal()
    if not PB_UTIL.brew_cells then return end
    PB_UTIL.brew_state.fuel_label   = 'Fuel: ' .. PB_UTIL.get_brew_fuel()
    PB_UTIL.brew_state.can_brew     = PB_UTIL.brew_can()
    PB_UTIL.brew_state.can_collect  = PB_UTIL.brew_can_collect()
    local C = G.CONTROLLER
    local dragged = C and C.dragging and C.dragging.target
    for _, slot in ipairs(PB_UTIL.brew_cells) do
        local area = slot.area
        local card = area and area.cards and area.cards[1]
        if card and card ~= dragged and not (card.states and card.states.drag.is) then
            local tx = area.T.x + (area.T.w - card.T.w) / 2
            local ty = area.T.y + (area.T.h - card.T.h) / 2
            card.T.x, card.T.y = tx, ty
            card.VT.x, card.VT.y = tx, ty
        end
    end
    PB_UTIL.refresh_brew_bottle()
end

-- ---- callbacks ----
G.FUNCS.bc_open_brewing = function(e) PB_UTIL.open_brewing() end

-- Colour-only per-frame funcs (mirror bc_furnace_can_smelt_btn). The callbacks self-guard, so the
-- buttons stay clickable and validity is enforced inside brew_step / brew_collect.
G.FUNCS.bc_brew_can_btn = function(e)
    e.config.colour = PB_UTIL.brew_state.can_brew and G.C.GREEN or G.C.UI.TRANSPARENT_LIGHT
end

G.FUNCS.bc_brew_can_collect_btn = function(e)
    e.config.colour = PB_UTIL.brew_state.can_collect and G.C.GREEN or G.C.UI.TRANSPARENT_LIGHT
end

G.FUNCS.bc_brew_do = function(e)
    if PB_UTIL.brew_step() then
        play_sound('tarot1', 1.0, 0.7)
        if G.GAME and G.GAME.balacraft then G.GAME.balacraft._panel_dirty = true end
    else
        play_sound('cancel')
    end
    PB_UTIL.update_brew_modal()   -- in-place refresh (gauge, buttons, bottle preview)
    PB_UTIL.update_inventory()    -- an ingredient/fuel may have hit 0 -> reflow the source grid
end

G.FUNCS.bc_brew_collect = function(e)
    if PB_UTIL.brew_collect() then
        play_sound('chips1', 1, 0.6)
        if G.GAME and G.GAME.balacraft then G.GAME.balacraft._panel_dirty = true end
    else
        play_sound('cancel')
    end
    PB_UTIL.update_brew_modal()
    PB_UTIL.update_inventory()
end

G.FUNCS.bc_brewing_back = function(e)
    if PB_UTIL.brew_cells then
        PB_UTIL.destroy_brew_cells()        -- credit reserved fuel/ingredient tiles (bottle persists)
        PB_UTIL.furnace_on_change = nil
    end
    if PB_UTIL.open_base then PB_UTIL.open_base() else G.FUNCS.exit_overlay_menu(e) end
end

-- Tear down the brew slots on ANY overlay close path (Close/ESC). Stacks above the crafting/furnace
-- exit wraps (brewing_ui loads last); only one station's cells are ever live, so each wrap self-guards.
if not PB_UTIL._brew_exit_hooked then
    PB_UTIL._brew_exit_hooked = true
    local _orig_exit = G.FUNCS.exit_overlay_menu
    G.FUNCS.exit_overlay_menu = function(...)
        if PB_UTIL.brew_cells then
            PB_UTIL.destroy_brew_cells()
            PB_UTIL.furnace_on_change = nil
        end
        return _orig_exit(...)
    end
end

-- The Brewing Stand is wired into the live Base modal picker (PICKER_STATIONS in crafting_ui.lua),
-- where it opens this overlay (bc_open_brewing) once the station is crafted -- parallel to the Anvil.
