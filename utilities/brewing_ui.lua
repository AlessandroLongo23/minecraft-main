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

local GUIDE_ICON = 0.5    -- recipe-row icon square (bigger than the old 0.32)

-- One guide row: [ing] + [from] = [to] (+ optional modifier label), a hoverable box w/ name tooltip.
local function guide_row(ing, from_content, to_content, label, name)
    local cells = {
        { n = G.UIT.C, config = { align = 'cm', padding = 0.02 }, nodes = { res_icon(ing, GUIDE_ICON) } },
        glyph('+'),
        { n = G.UIT.C, config = { align = 'cm', padding = 0.02 }, nodes = { content_icon_node(from_content, GUIDE_ICON) } },
        glyph('='),
        { n = G.UIT.C, config = { align = 'cm', padding = 0.02 }, nodes = { content_icon_node(to_content, GUIDE_ICON) } },
    }
    if label then
        cells[#cells + 1] = { n = G.UIT.C, config = { align = 'cm', padding = 0.02 }, nodes = {
            { n = G.UIT.T, config = { text = label, scale = 0.32, colour = G.C.ORANGE } } } }
    end
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.03 }, nodes = { {
        n = G.UIT.R, config = { align = 'cm', padding = 0.06, r = 0.07, minw = 3.0, minh = 0.62,
            colour = G.C.UI.TRANSPARENT_DARK, hover = name ~= nil,
            tooltip = name and { text = { name } } or nil },
        nodes = cells } } }
end

-- ---- recipe-guide pagination ----
-- All guide rows in display order (bottle steps then modifier rows), built once.
local function brew_guide_rows()
    local all = {}
    for _, s in ipairs(BREW_GUIDE) do all[#all + 1] = { s[1], s[2], s[3], nil, content_name(s[3]) } end
    for _, m in ipairs(BREW_MODS_GUIDE) do all[#all + 1] = { m[1], m[3], m[3], m[2], m[4] } end
    return all
end

local BREW_ROWS_PER_PAGE = 3   -- rows per recipe page (left box); 14 recipes -> 5 pages
PB_UTIL.brew_recipe_page = PB_UTIL.brew_recipe_page or 1

-- Total recipe-guide pages (>= 1).
function PB_UTIL.brew_recipe_page_count()
    return math.max(1, math.ceil(#brew_guide_rows() / BREW_ROWS_PER_PAGE))
end

-- A small page button (mirrors the inventory pager's look).
local function brew_page_btn(label, fn, enabled)
    return { n = G.UIT.C, config = {
        align = 'cm', padding = 0.06, r = 0.08, minw = 0.5, minh = 0.4,
        colour = enabled and G.C.BLUE or G.C.UI.TRANSPARENT_DARK,
        button = enabled and fn or nil, hover = enabled, shadow = true },
        nodes = { { n = G.UIT.T, config = { text = label, scale = 0.4, colour = G.C.UI.TEXT_LIGHT } } } }
end

-- The left recipe-guide panel: one column of BREW_ROWS_PER_PAGE rows for the current page, with a
-- "[<] Page p/N [>]" nav row at the bottom. No black box (the shell already provides the container).
local function brew_recipe_panel()
    local all = brew_guide_rows()
    local pages = PB_UTIL.brew_recipe_page_count()
    local page = math.max(1, math.min(pages, PB_UTIL.brew_recipe_page or 1))
    PB_UTIL.brew_recipe_page = page

    local rows = {}
    local first = (page - 1) * BREW_ROWS_PER_PAGE + 1
    for i = first, math.min(first + BREW_ROWS_PER_PAGE - 1, #all) do
        local s = all[i]
        rows[#rows + 1] = guide_row(s[1], s[2], s[3], s[4], s[5])
    end

    -- The page nav, appended as the LAST node so it sits UNDER the recipe rows. Everything here must be a
    -- UIT.R (rows + nav) so they stack VERTICALLY -- a UIT.C child would lay out horizontally instead,
    -- which is exactly what pushed the nav off to the side before.
    local nav = { n = G.UIT.R, config = { align = 'cm', padding = 0.03 }, nodes = {
        brew_page_btn('<', 'bc_brew_recipe_prev', page > 1),
        { n = G.UIT.C, config = { align = 'cm', padding = 0.06, minw = 1.4 }, nodes = {
            { n = G.UIT.T, config = { text = 'Page ' .. page .. '/' .. pages, scale = 0.32,
                colour = G.C.UI.TEXT_LIGHT } } } },
        brew_page_btn('>', 'bc_brew_recipe_next', page < pages),
    } }
    rows[#rows + 1] = nav

    return { n = G.UIT.C, config = { align = 'cm', padding = 0.04 }, nodes = rows }
end

-- Flip the recipe-guide page by `delta`, clamped to [1, pages], then rebuild the overlay in place.
function PB_UTIL.change_brew_recipe_page(delta)
    local pages = PB_UTIL.brew_recipe_page_count()
    local p = math.max(1, math.min(pages, (PB_UTIL.brew_recipe_page or 1) + delta))
    if p == (PB_UTIL.brew_recipe_page or 1) then return end
    PB_UTIL.brew_recipe_page = p
    play_sound('cardSlide1')
    if PB_UTIL.rebuild_inv_overlay then PB_UTIL.rebuild_inv_overlay() end
end
G.FUNCS.bc_brew_recipe_prev = function(e) PB_UTIL.change_brew_recipe_page(-1) end
G.FUNCS.bc_brew_recipe_next = function(e) PB_UTIL.change_brew_recipe_page(1) end

-- A subtly bordered sub-container (returns a UIT.C so two of them sit SIDE BY SIDE -- C children lay out
-- horizontally). Fixed w/h so the two Brewing boxes are equal-sized and fill the panel, like the sketch.
local BREW_BOX_W, BREW_BOX_H = 4.5, 3.0
local function brew_box(content)
    return { n = G.UIT.C, config = { align = 'cm', padding = 0.1, r = 0.1, colour = G.C.UI.TRANSPARENT_DARK,
        minw = BREW_BOX_W, minh = BREW_BOX_H }, nodes = { content } }
end

-- ---- in-frame station content ----
-- The Brewing Stand's interactive content, as an embeddable node for the unified modal's station area.
-- Laid out as TWO SIDE-BY-SIDE containers (matching the user's sketch, like the Crafting Table split):
--   * LEFT  box = the recipe guide rows + the "[<] Page p/N [>]" nav (the page nav sits UNDER the recipes).
--   * RIGHT box = the brewing station: a Fuel slot (left) | ingredient / v / bottle (centre) | Brew (right),
--                 with Collect Potion spanning the bottom.
-- Ingredients are dragged up from the shared Inventory; the bottle persists across closing
-- (G.GAME.balacraft.brew_bottle).
function PB_UTIL.brewing_station_content()
    -- Fuel slot + gauge (left of the apparatus).
    local fuel_col = { n = G.UIT.C, config = { align = 'cm', padding = 0.06 }, nodes = {
        { n = G.UIT.R, config = { align = 'cm' }, nodes = { PB_UTIL.furnace_slot_node(PB_UTIL.brew_fuel_area) } },
        { n = G.UIT.R, config = { align = 'cm', padding = 0.02 }, nodes = {
            res_icon('blaze_powder', 0.28),
            { n = G.UIT.T, config = { id = 'bc_brew_fuel_label', ref_table = PB_UTIL.brew_state,
                ref_value = 'fuel_label', scale = 0.28, colour = G.C.ORANGE } },
        } },
    } }

    -- Centre: ingredient slot ABOVE the bottle (the potion brews IN the bottle), with a 'v' between them.
    local center_col = { n = G.UIT.C, config = { align = 'cm', padding = 0.04 }, nodes = {
        { n = G.UIT.R, config = { align = 'cm' }, nodes = { PB_UTIL.furnace_slot_node(PB_UTIL.brew_ingredient_area) } },
        { n = G.UIT.R, config = { align = 'cm', padding = 0.01 }, nodes = {
            { n = G.UIT.T, config = { text = 'v', scale = 0.45, colour = G.C.UI.TEXT_INACTIVE } } } },
        { n = G.UIT.R, config = { align = 'cm' }, nodes = { brew_bottle_node() } },
    } }

    local brew_btn = { n = G.UIT.C, config = { align = 'cm' }, nodes = { {
        n = G.UIT.R, config = { id = 'bc_brew_button', align = 'cm', padding = 0.1, r = 0.1,
            minw = 1.4, minh = BREW_CELL, colour = G.C.UI.TRANSPARENT_LIGHT,
            button = 'bc_brew_do', func = 'bc_brew_can_btn', hover = true, shadow = true },
        nodes = { { n = G.UIT.T, config = { text = 'Brew', scale = 0.42, colour = G.C.UI.TEXT_LIGHT } } },
    } } }

    -- Fuel | (ingredient / v / bottle) | Brew, vertically centred (fuel + Brew sit at the bottle's level).
    local apparatus = { n = G.UIT.R, config = { align = 'cm', padding = 0.04 },
        nodes = { fuel_col, center_col, brew_btn } }

    -- Collect: spans the bottom of the box; green/enabled (per-frame) when a finished potion sits in the
    -- bottle and there is room.
    local collect_btn = { n = G.UIT.R, config = { id = 'bc_brew_collect_btn', align = 'cm', minw = 4.0,
        padding = 0.08, r = 0.1, hover = true, colour = G.C.UI.TRANSPARENT_LIGHT,
        button = 'bc_brew_collect', func = 'bc_brew_can_collect_btn', shadow = true },
        nodes = { { n = G.UIT.T, config = { text = 'Collect Potion', scale = 0.42, colour = G.C.UI.TEXT_LIGHT } } } }

    local station_content = { n = G.UIT.C, config = { align = 'cm', padding = 0.04 }, nodes = {
        { n = G.UIT.R, config = { align = 'cm' }, nodes = { apparatus } },
        { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = { collect_btn } },
    } }

    -- LEFT recipes box | RIGHT station box, side by side (two C children of one R -> horizontal).
    return { n = G.UIT.C, config = { align = 'cm' }, nodes = { {
        n = G.UIT.R, config = { align = 'cm', padding = 0.06 }, nodes = {
            brew_box(brew_recipe_panel()),
            brew_box(station_content),
        } } } }
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
    local ok = PB_UTIL.brew_collect()
    if ok then
        play_sound('chips1', 1, 0.6)
        if G.GAME and G.GAME.balacraft then G.GAME.balacraft._panel_dirty = true end
    else
        play_sound('cancel')
    end
    PB_UTIL.update_brew_modal()
    PB_UTIL.update_inventory()
    -- On a successful collect, a potion that couldn't auto-equip (both slots full) is now stored in the
    -- unified inventory (routed synchronously by brew_potion). Rebuild the modal in place so it appears
    -- immediately -- reuses the live brew + inventory CardAreas, so placed fuel/ingredient tiles are
    -- untouched (the same in-place swap station switching uses).
    if ok and PB_UTIL.rebuild_inv_overlay then
        PB_UTIL.rebuild_inv_overlay()
    end
end

-- The Brewing Stand renders in-frame in the unified modal (PICKER_STATIONS in crafting_ui.lua); its
-- cells are built by open_inventory('brewing_stand') and torn down on station switch / Close (which
-- credits reserved fuel/ingredient tiles -- the bottle persists). No standalone overlay or exit wrap.
