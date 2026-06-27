-- The Furnace + "Your Base" launcher.
--
-- Furnace: a Base station that smelts RAW ores into refined ingots, burning fuel. MC-faithful
-- smelt set: raw_iron -> iron, raw_gold -> gold (1:1). Fuel is a buffer on G.GAME.balacraft
-- (seeded in resources.lua init wrapper): loading 1 coal -> +4 charges, 1 wood -> +1; each smelt
-- spends 1 charge + 1 raw -> 1 refined.
--
-- The overlays are BUTTON-DRIVEN and rebuilt on every action (open_*() re-calls overlay_menu, which
-- replaces G.OVERLAY_MENU without firing exit_overlay_menu), so counts/fuel/affordability always
-- reflect current state without per-frame binding. No craft_cells / drag state -> nothing to clean up.

-- ── Smelt data ──────────────────────────────────────────────────────────────
PB_UTIL.SMELTS = {
    { raw = 'raw_iron', out = 'iron' },
    { raw = 'raw_gold', out = 'gold' },
    -- Glass chain: Sand smelts into Glass (MC-faithful), which crafts the Glass Sheet at the
    -- Crafting Table (content/resources/recipes.lua). Picked up automatically by SMELT_BY_RAW below.
    { raw = 'sand',     out = 'glass' },
}
PB_UTIL.SMELT_BY_RAW = {}
for _, s in ipairs(PB_UTIL.SMELTS) do PB_UTIL.SMELT_BY_RAW[s.raw] = s.out end

-- Fuel: charges granted per unit of each fuel resource (coal is efficient, wood weak).
PB_UTIL.FUEL_VALUE = { coal = 4, wood = 1 }

-- ── Fuel + smelt logic ──────────────────────────────────────────────────────
function PB_UTIL.get_furnace_fuel()
    local bc = G.GAME and G.GAME.balacraft
    return (bc and bc.furnace_fuel) or 0
end

-- Spend 1 of fuel resource `kind` from inventory; add its charges to the buffer.
function PB_UTIL.furnace_load_fuel(kind)
    local val = PB_UTIL.FUEL_VALUE[kind]
    local bc = G.GAME and G.GAME.balacraft
    if not val or not bc then return false end
    if PB_UTIL.get_resource_count(kind) < 1 then return false end
    PB_UTIL.add_resource(kind, -1)
    bc.furnace_fuel = (bc.furnace_fuel or 0) + val
    return true
end

function PB_UTIL.can_smelt(raw_id)
    local out = raw_id and PB_UTIL.SMELT_BY_RAW[raw_id]
    if not out then return false end
    if PB_UTIL.get_resource_count(raw_id) < 1 then return false end
    if PB_UTIL.get_furnace_fuel() < 1 then return false end
    if PB_UTIL.inv_can_fit_resource and not PB_UTIL.inv_can_fit_resource(out, 1) then return false end
    return true
end

-- Spend 1 fuel charge + 1 raw -> +1 refined. Returns true on success.
function PB_UTIL.smelt(raw_id)
    if not PB_UTIL.can_smelt(raw_id) then return false end
    local out = PB_UTIL.SMELT_BY_RAW[raw_id]
    G.GAME.balacraft.furnace_fuel = G.GAME.balacraft.furnace_fuel - 1
    PB_UTIL.add_resource(raw_id, -1)
    PB_UTIL.add_resource(out, 1)
    return true
end

-- ── Base stations (one-time unlocks, crafted at the Crafting Table) ──────────
-- Crafting a recipe with output.type='station' calls build_station(id); the Base shows that
-- station's slot as inert ("craft it") until built, then active. State lives on G.GAME.balacraft
-- .stations (plain table => auto-saved within a run, auto-reset per run; no custom save/load).
function PB_UTIL.station_built(id)
    local bc = G.GAME and G.GAME.balacraft
    return (bc and bc.stations and bc.stations[id]) and true or false
end

function PB_UTIL.build_station(id)
    local bc = G.GAME and G.GAME.balacraft
    if not bc then return end
    bc.stations = bc.stations or {}
    bc.stations[id] = true
end

-- ── UI helpers ──────────────────────────────────────────────────────────────
-- A labelled rectangular button. enabled=false greys it and drops the callback.
local function fbtn(label, fn, enabled, colour, minw)
    enabled = enabled ~= false
    return {
        n = G.UIT.C,
        config = {
            align = 'cm', padding = 0.1, r = 0.1, minw = minw or 2.2, minh = 0.7,
            colour = enabled and (colour or G.C.BLUE) or G.C.UI.TRANSPARENT_DARK,
            button = enabled and fn or nil, hover = enabled, shadow = true,
        },
        nodes = { { n = G.UIT.T, config = { text = label, scale = 0.34, colour = G.C.UI.TEXT_LIGHT } } },
    }
end

local function text_row(str, scale, colour)
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
        { n = G.UIT.T, config = { text = str, scale = scale or 0.4, colour = colour or G.C.UI.TEXT_LIGHT } } } }
end

-- A small frameless resource icon (falls back to an empty text node if the atlas isn't ready).
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

-- ── Furnace overlay (Minecraft-furnace layout, drag-driven) ──────────────────
-- Build ONCE / mutate in place (like the crafting table): drag a raw ore from the bottom resource
-- grid into the INPUT slot and a fuel (coal/wood) into the FUEL slot, then click Smelt. Counts /
-- fuel gauge / button-enabled / output preview are all live (bound refs + a per-frame func), so an
-- action never rebuilds the overlay -- nothing "flies in from below" on every click.

-- Live-bound display state (seeded in open_furnace; updated by update_furnace_modal each frame).
PB_UTIL.furnace_state = PB_UTIL.furnace_state or { fuel_label = '', can_smelt = false }

-- True iff the input slot holds a smeltable raw AND a fuel charge is available (buffer, or a
-- burnable fuel tile sitting in the fuel slot).
function PB_UTIL.furnace_can_smelt()
    local input = PB_UTIL.furnace_input_area
    local in_card = input and input.cards and input.cards[1]
    local raw = in_card and PB_UTIL.tile_resource(in_card)
    if not (raw and PB_UTIL.SMELT_BY_RAW[raw]) then return false end
    -- The refined ingot must fit the inventory's real capacity (else the raw + fuel would be wasted).
    if PB_UTIL.inv_can_fit_resource and not PB_UTIL.inv_can_fit_resource(PB_UTIL.SMELT_BY_RAW[raw], 1) then return false end
    if PB_UTIL.get_furnace_fuel() >= 1 then return true end
    local fuelslot = PB_UTIL.furnace_fuel_area
    local f_card = fuelslot and fuelslot.cards and fuelslot.cards[1]
    local f_rid = f_card and PB_UTIL.tile_resource(f_card)
    return (f_rid and PB_UTIL.FUEL_VALUE[f_rid] ~= nil) and true or false
end

-- Perform one smelt from the slots. The input/fuel tiles are already RESERVED (debited when dragged
-- in), so consuming them is a no-credit :remove(); fuel burns into the buffer (1 coal -> +4 charges),
-- the buffer spends 1 charge per smelt, and +1 refined ingot is produced. Auto-refills both slots
-- from inventory afterwards so Smelt can be clicked repeatedly. Returns true on success.
function PB_UTIL.furnace_do_smelt()
    local input    = PB_UTIL.furnace_input_area
    local fuelslot = PB_UTIL.furnace_fuel_area
    if not (input and fuelslot) then return false end
    local in_card = input.cards and input.cards[1]
    local raw = in_card and PB_UTIL.tile_resource(in_card)
    local out = raw and PB_UTIL.SMELT_BY_RAW[raw]
    if not out then return false end

    -- Ensure a fuel charge: burn one fuel tile from the fuel slot into the buffer if empty.
    if PB_UTIL.get_furnace_fuel() < 1 then
        local f_card = fuelslot.cards and fuelslot.cards[1]
        local f_rid  = f_card and PB_UTIL.tile_resource(f_card)
        local val    = f_rid and PB_UTIL.FUEL_VALUE[f_rid]
        if not val then return false end             -- no buffer and no burnable fuel
        f_card:remove()                              -- burn the reserved fuel tile (NO credit)
        G.GAME.balacraft.furnace_fuel = (G.GAME.balacraft.furnace_fuel or 0) + val
        if PB_UTIL.get_resource_count(f_rid) >= 1 then   -- refill the fuel slot from inventory
            local t = PB_UTIL.spawn_reserved_tile(f_rid)
            if t then PB_UTIL.place_in_area(t, fuelslot) end
        end
    end
    if PB_UTIL.get_furnace_fuel() < 1 then return false end

    in_card:remove()                                 -- consume the reserved raw tile (NO credit)
    G.GAME.balacraft.furnace_fuel = G.GAME.balacraft.furnace_fuel - 1
    PB_UTIL.add_resource(out, 1)
    PB_UTIL.furnace_last_out = out
    if PB_UTIL.get_resource_count(raw) >= 1 then      -- refill the input slot from inventory
        local t = PB_UTIL.spawn_reserved_tile(raw)
        if t then PB_UTIL.place_in_area(t, input) end
    end
    return true
end

-- Drive the output-preview icon: show the ingot for whatever raw currently sits in the input slot
-- (a preview, like Minecraft), else the last thing smelted, else hidden.
function PB_UTIL.refresh_furnace_output()
    if not G.OVERLAY_MENU then return end
    local icon = G.OVERLAY_MENU:get_UIE_by_ID('bc_furnace_output_icon')
    if not (icon and icon.config and icon.config.object) then return end
    local obj = icon.config.object
    local input = PB_UTIL.furnace_input_area
    local in_card = input and input.cards and input.cards[1]
    local raw = in_card and PB_UTIL.tile_resource(in_card)
    local out = (raw and PB_UTIL.SMELT_BY_RAW[raw]) or PB_UTIL.furnace_last_out
    local r = out and PB_UTIL.RESOURCE_BY_ID[out]
    if r then
        obj.atlas = G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]
        obj:set_sprite_pos(r.pos)
        if obj.bc_overlay then obj.bc_overlay[4] = 1 end
    elseif obj.bc_overlay then
        obj.bc_overlay[4] = 0
    end
end

-- Per-frame furnace maintenance (called from update_crafting_modal in crafting_ui.lua). Inert
-- unless the furnace is open. Snaps slot tiles to their settled centres (auto-refilled tiles are
-- created post-layout), keeps the fuel gauge + Smelt-enabled state current, updates the preview.
function PB_UTIL.update_furnace_modal()
    if not PB_UTIL.furnace_cells then return end
    PB_UTIL.furnace_state.fuel_label = 'Fuel: ' .. PB_UTIL.get_furnace_fuel()
    PB_UTIL.furnace_state.can_smelt  = PB_UTIL.furnace_can_smelt()
    local C = G.CONTROLLER
    local dragged = C and C.dragging and C.dragging.target
    for _, slot in ipairs(PB_UTIL.furnace_cells) do
        local area = slot.area
        local card = area and area.cards and area.cards[1]
        if card and card ~= dragged and not (card.states and card.states.drag.is) then
            local tx = area.T.x + (area.T.w - card.T.w) / 2
            local ty = area.T.y + (area.T.h - card.T.h) / 2
            card.T.x, card.T.y = tx, ty
            card.VT.x, card.VT.y = tx, ty
        end
    end
    PB_UTIL.refresh_furnace_output()
end

-- A single grid-cell-sized output square (matches the input/fuel slot look) holding the preview icon.
local FURNACE_CELL = 0.76
local function furnace_output_node()
    local out_icon = PB_UTIL.make_dimmable(
        Sprite(0, 0, 0.5, 0.5, G.ASSET_ATLAS[PB_UTIL.icon_atlas.key], PB_UTIL.RESOURCE_BY_ID['iron'].pos))
    out_icon.bc_overlay[4] = 0   -- hidden until a raw sits in the input slot
    local square = {
        n = G.UIT.C, config = { align = 'cm', padding = 0.03, r = 0.05, colour = G.C.UI.TRANSPARENT_DARK,
                                minw = FURNACE_CELL, minh = FURNACE_CELL },
        nodes = { { n = G.UIT.O, config = { id = 'bc_furnace_output_icon', object = out_icon } } },
    }
    return { n = G.UIT.C, config = { align = 'cm' }, nodes = { square } }
end

-- The Furnace's interactive content (smelt slots + gauge + Smelt button + hint), as an embeddable
-- node for the unified Inventory modal's station area. The shared inventory + Back live in the shell.
function PB_UTIL.furnace_station_content()
    local slots_col = { n = G.UIT.C, config = { align = 'cm', padding = 0.04 }, nodes = {
        { n = G.UIT.R, config = { align = 'cm' }, nodes = { PB_UTIL.furnace_slot_node(PB_UTIL.furnace_input_area) } },
        { n = G.UIT.R, config = { align = 'cm', padding = 0.03 }, nodes = {
            res_icon('coal', 0.4),
            { n = G.UIT.T, config = { id = 'bc_furnace_fuel_label', ref_table = PB_UTIL.furnace_state,
                ref_value = 'fuel_label', scale = 0.34, colour = G.C.ORANGE } },
        } },
        { n = G.UIT.R, config = { align = 'cm' }, nodes = { PB_UTIL.furnace_slot_node(PB_UTIL.furnace_fuel_area) } },
    } }
    local arrow_node = { n = G.UIT.C, config = { align = 'cm', padding = 0.1 },
        nodes = { { n = G.UIT.T, config = { text = '>', scale = 0.6, colour = G.C.WHITE } } } }
    local smelt_btn = {
        n = G.UIT.C, config = { align = 'cm' }, nodes = { {
            n = G.UIT.R, config = { id = 'bc_furnace_smelt_btn', align = 'cm', padding = 0.1, r = 0.1,
                minw = 1.6, minh = FURNACE_CELL, colour = G.C.UI.TRANSPARENT_LIGHT,
                button = 'bc_furnace_smelt', func = 'bc_furnace_can_smelt_btn', hover = true, shadow = true },
            nodes = { { n = G.UIT.T, config = { text = 'Smelt', scale = 0.45, colour = G.C.UI.TEXT_LIGHT } } },
        } } }
    local smelt_row = { n = G.UIT.R, config = { align = 'cm', padding = 0.06 },
        nodes = { slots_col, arrow_node, furnace_output_node(), smelt_btn } }
    return { n = G.UIT.C, config = { align = 'cm', padding = 0.06 }, nodes = {
        text_row('Furnace', 0.5, G.C.ORANGE),
        { n = G.UIT.R, config = { align = 'cm', padding = 0.06, r = 0.1, colour = G.C.BLACK }, nodes = { smelt_row } },
        text_row('Drag a raw ore into the top slot and fuel (coal/wood) into the bottom.', 0.24, G.C.UI.TEXT_INACTIVE),
    } }
end

function PB_UTIL.build_furnace_modal()
    -- Slots column: input (top), the flame/fuel gauge (middle), fuel (bottom) -- the Minecraft stack.
    local slots_col = { n = G.UIT.C, config = { align = 'cm', padding = 0.04 }, nodes = {
        { n = G.UIT.R, config = { align = 'cm' }, nodes = { PB_UTIL.furnace_slot_node(PB_UTIL.furnace_input_area) } },
        { n = G.UIT.R, config = { align = 'cm', padding = 0.03 }, nodes = {
            res_icon('coal', 0.4),
            { n = G.UIT.T, config = { id = 'bc_furnace_fuel_label', ref_table = PB_UTIL.furnace_state,
                ref_value = 'fuel_label', scale = 0.34, colour = G.C.ORANGE } },
        } },
        { n = G.UIT.R, config = { align = 'cm' }, nodes = { PB_UTIL.furnace_slot_node(PB_UTIL.furnace_fuel_area) } },
    } }

    local arrow_node = { n = G.UIT.C, config = { align = 'cm', padding = 0.1 },
        nodes = { { n = G.UIT.T, config = { text = '>', scale = 0.6, colour = G.C.WHITE } } } }

    -- Smelt button: non-nil button at build (enables click once); per-frame func only flips colour
    -- (green when furnace_state.can_smelt). bc_furnace_smelt self-guards, so always-clickable is safe.
    local smelt_btn = {
        n = G.UIT.C, config = { align = 'cm' }, nodes = { {
            n = G.UIT.R, config = { id = 'bc_furnace_smelt_btn', align = 'cm', padding = 0.1, r = 0.1,
                minw = 1.6, minh = FURNACE_CELL, colour = G.C.UI.TRANSPARENT_LIGHT,
                button = 'bc_furnace_smelt', func = 'bc_furnace_can_smelt_btn', hover = true, shadow = true },
            nodes = { { n = G.UIT.T, config = { text = 'Smelt', scale = 0.45, colour = G.C.UI.TEXT_LIGHT } } },
        } } }

    local smelt_row = { n = G.UIT.R, config = { align = 'cm', padding = 0.06 },
        nodes = { slots_col, arrow_node, furnace_output_node(), smelt_btn } }

    return { n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0.12, r = 0.1, colour = G.C.GREY, minw = 9, minh = 5 },
        nodes = {
            text_row('Furnace', 0.6, G.C.ORANGE),
            { n = G.UIT.R, config = { align = 'cm', padding = 0.06, r = 0.1, colour = G.C.BLACK }, nodes = { smelt_row } },
            text_row('Drag a raw ore into the top slot and fuel (coal/wood) into the bottom slot.', 0.26, G.C.UI.TEXT_INACTIVE),
            -- Bottom: the SAME draggable resource grid as the crafting table.
            { n = G.UIT.R, config = { align = 'cm', minh = 0.1 }, nodes = {} },
            { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                { n = G.UIT.T, config = { text = 'Inventory', scale = 0.38, colour = G.C.UI.TEXT_LIGHT } } } },
            { n = G.UIT.R, config = { align = 'cm' }, nodes = { PB_UTIL.build_inventory_node() } },
            { n = G.UIT.R, config = { align = 'cm', minh = 0.1 }, nodes = {} },
            full_btn('Back', 'bc_furnace_back'),
        } }
end

function PB_UTIL.open_furnace()
    PB_UTIL.furnace_state = PB_UTIL.furnace_state or { fuel_label = '', can_smelt = false }
    PB_UTIL.furnace_state.fuel_label = 'Fuel: ' .. PB_UTIL.get_furnace_fuel()
    PB_UTIL.furnace_state.can_smelt  = false
    PB_UTIL.furnace_last_out = nil
    PB_UTIL.build_furnace_cells()                       -- input + fuel drop slots (build once)
    PB_UTIL.build_inventory()                           -- shared draggable source grid
    PB_UTIL.furnace_on_change = PB_UTIL.update_furnace_modal   -- drag/right-click -> immediate refresh
    PB_UTIL.refresh_overlay(PB_UTIL.build_furnace_modal())     -- swap in place (no fly-in)
end

-- Per-frame colour on the Smelt button (mirrors bc_can_craft_btn). Colour only -- never toggles
-- config.button (the callback self-guards, so the button stays clickable and validity is enforced there).
G.FUNCS.bc_furnace_can_smelt_btn = function(e)
    e.config.colour = PB_UTIL.furnace_state.can_smelt and G.C.GREEN or G.C.UI.TRANSPARENT_LIGHT
end

G.FUNCS.bc_furnace_smelt = function(e)
    if PB_UTIL.furnace_do_smelt() then play_sound('timpani', 0.8) else play_sound('cancel') end
    PB_UTIL.update_furnace_modal()   -- in-place refresh (fuel gauge, button, preview)
    PB_UTIL.update_inventory()       -- a raw/fuel may have hit 0 -> reflow the source grid
end

-- Back to the unified Inventory modal: credit any reserved tiles still in the slots, then return.
-- (Legacy: the standalone furnace overlay is unused now -- the Furnace is a station in the modal.)
G.FUNCS.bc_furnace_back = function(e)
    PB_UTIL.destroy_furnace_cells()
    PB_UTIL.furnace_on_change = nil
    PB_UTIL.open_inventory('crafting_table')
end

-- Tear down the furnace slots on ANY overlay close path (Close/ESC). Stacks above the crafting +
-- inventory exit wraps (furnace.lua loads after both); only one station's cells are ever live.
if not PB_UTIL._furnace_exit_hooked then
    PB_UTIL._furnace_exit_hooked = true
    local _orig_exit = G.FUNCS.exit_overlay_menu
    G.FUNCS.exit_overlay_menu = function(...)
        if PB_UTIL.furnace_cells then
            PB_UTIL.destroy_furnace_cells()
            PB_UTIL.furnace_on_change = nil
        end
        return _orig_exit(...)
    end
end

-- ── "Your Base" launcher ────────────────────────────────────────────────────
-- A grid of station CARDS (title on top, the block sprite in the middle, an Open button below).
-- ready=false stations show their card greyed with a "(soon)" / "(craft it)" label; later waves
-- flip them on. The Crafting Table opens with back='base' so its Back returns here.

-- Station block icons (bc_station_icons): 34x34 cells from authentic MC block faces
-- (assets/gen_stations.py). Registered here since the Base is the only consumer.
PB_UTIL.station_icon_atlas = SMODS.Atlas { key = 'bc_station_icons', path = 'station_icons.png', px = 34, py = 34 }

-- Atlas cell positions, MUST match assets/gen_stations.py CELLS. (Chest's icon is composited from
-- the MC chest entity front face; Ender Chest is still entity-only -> name-only card.)
PB_UTIL.STATION_ICONS = {
    crafting_table = { x = 0, y = 0 }, furnace = { x = 1, y = 0 }, composter = { x = 2, y = 0 },
    anvil = { x = 3, y = 0 }, brewing_stand = { x = 0, y = 1 }, chest = { x = 1, y = 1 },
    enchanting_table = { x = 2, y = 1 },
}

-- Each station is one of: `always` (always-open, e.g. Crafting Table), `station` + `fn` (crafted ->
-- opens an overlay, e.g. Furnace), `station` + `passive` (crafted -> a PASSIVE buff, no overlay,
-- e.g. Chest), or `soon` (a not-yet-built stub).
PB_UTIL.BASE_STATIONS = {
    { name = 'Crafting Table', icon = 'crafting_table', fn = 'bc_open_crafting_from_base', always = true },
    { name = 'Furnace',        icon = 'furnace',        fn = 'bc_open_furnace', station = 'furnace' },
    { name = 'Chest',          icon = 'chest',          station = 'chest', passive = true, built_label = '+1 Bench' },
    { name = 'Anvil',          icon = 'anvil',          fn = 'bc_open_anvil', station = 'anvil' },
    { name = 'Composter',      icon = 'composter',      soon = true },
    { name = 'Brewing Stand',  icon = 'brewing_stand',  soon = true },
    { name = 'Ender Chest',                             soon = true },
}
local BASE_PER_ROW = 4

-- The station's block sprite (0.9), or a dark placeholder square when it has no art.
local function station_icon_node(icon_id)
    local pos   = icon_id and PB_UTIL.STATION_ICONS[icon_id]
    local atlas = PB_UTIL.station_icon_atlas and G.ASSET_ATLAS[PB_UTIL.station_icon_atlas.key]
    if pos and atlas then
        return { n = G.UIT.O, config = { object = Sprite(0, 0, 0.9, 0.9, atlas, pos) } }
    end
    return { n = G.UIT.C, config = { align = 'cm', minw = 0.9, minh = 0.9, r = 0.05,
        colour = G.C.UI.TRANSPARENT_DARK }, nodes = {} }
end

function PB_UTIL.build_base_modal()
    local rows, row = {}, nil
    for i, st in ipairs(PB_UTIL.BASE_STATIONS) do
        if (i - 1) % BASE_PER_ROW == 0 then
            row = { n = G.UIT.R, config = { align = 'cm', padding = 0.06 }, nodes = {} }
            rows[#rows + 1] = row
        end
        -- Crafting Table is always open; Furnace/Anvil activate once crafted and open an overlay;
        -- the Chest is a PASSIVE buff (no overlay); the rest are stubs.
        local ready = st.always or (st.station and PB_UTIL.station_built(st.station)) or false
        -- A non-clickable status pill (greyed for craft-it/soon, green for an active passive buff).
        local function status_pill(txt, col)
            return { n = G.UIT.C, config = { align = 'cm', padding = 0.08, r = 0.08, minw = 1.5, minh = 0.5,
                colour = G.C.UI.TRANSPARENT_DARK },
                nodes = { { n = G.UIT.T, config = { text = txt, scale = 0.28, colour = col or G.C.UI.TEXT_INACTIVE } } } }
        end
        -- Action affordance under the block.
        local action
        if st.passive then
            action = ready and status_pill(st.built_label or 'Active', G.C.GREEN) or status_pill('(craft it)')
        elseif st.always or st.station then
            if ready then
                action = { n = G.UIT.C, config = { align = 'cm', padding = 0.08, r = 0.08, minw = 1.5, minh = 0.5,
                    colour = G.C.BLUE, button = st.fn, hover = true, shadow = true },
                    nodes = { { n = G.UIT.T, config = { text = 'Open', scale = 0.3, colour = G.C.UI.TEXT_LIGHT } } } }
            else
                action = status_pill('(craft it)')
            end
        else
            action = status_pill('(soon)')
        end
        row.nodes[#row.nodes + 1] = {
            n = G.UIT.C,
            config = { align = 'tm', padding = 0.1, r = 0.1, minw = 2.0,
                colour = ready and G.C.BLACK or G.C.UI.TRANSPARENT_DARK, shadow = true },
            nodes = {
                { n = G.UIT.R, config = { align = 'cm', minh = 0.4 }, nodes = {
                    { n = G.UIT.T, config = { text = st.name, scale = 0.32, colour = G.C.UI.TEXT_LIGHT } } } },
                { n = G.UIT.R, config = { align = 'cm', padding = 0.08, minh = 1.0 }, nodes = { station_icon_node(st.icon) } },
                { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = { action } },
            },
        }
    end
    -- Splice the station ROWS (UIT.R) directly as ROOT children so each row centers on the modal's
    -- axis (a narrower row -- e.g. the 3-card second row -- sits centred under the 4-card first row).
    -- Wrapping them in a UIT.C inside the R-stacking ROOT left-aligned the whole grid instead.
    local nodes = {
        text_row('Your Base', 0.6, G.C.ORANGE),
        { n = G.UIT.R, config = { align = 'cm', minh = 0.1 }, nodes = {} },
    }
    for _, r in ipairs(rows) do nodes[#nodes + 1] = r end
    nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm', minh = 0.15 }, nodes = {} }
    nodes[#nodes + 1] = full_btn('Close', 'exit_overlay_menu')
    return { n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0.12, r = 0.1, colour = G.C.GREY, minw = 8, minh = 4 },
        nodes = nodes }
end

-- The standalone "Your Base" launcher is superseded by the unified Inventory modal (its workbench
-- picker). open_base now just opens that modal, so every legacy caller (station Backs, the old
-- hotbar button) lands in the right place. build_base_modal below is dead but kept inert.
function PB_UTIL.open_base()
    PB_UTIL.open_inventory('crafting_table')
end

G.FUNCS.bc_open_base = function(e) PB_UTIL.open_base() end
G.FUNCS.bc_open_furnace = function(e) PB_UTIL.open_furnace() end
G.FUNCS.bc_open_crafting_from_base = function(e) PB_UTIL.open_crafting_table({ back = 'base' }) end

-- Crafting Table's Back, when opened FROM the Base: credit any in-grid tiles (mirrors the
-- exit_overlay_menu hook in crafting_ui.lua) and return to the Base instead of closing.
G.FUNCS.bc_craft_back_to_base = function(e)
    if PB_UTIL.craft_cells then
        PB_UTIL.destroy_craft_cells()
        PB_UTIL.craft_on_change = nil
    end
    PB_UTIL.open_base()
end

-- ── The Anvil (Base station) ─────────────────────────────────────────────────
-- Merge two tools of the SAME type + material: the survivor (first selected) takes the MAX tier of
-- each enchant and is fully repaired (uses refilled to max); the other tool is consumed. Iron-gated
-- via its recipe, so it comes online once you have a Furnace. The overlay is an isolated Base
-- sub-screen (like the Furnace): a clickable list of the tools you hold -- select two compatible
-- ones, then Combine. No drag state, so each interaction just rebuilds in place (refresh_overlay
-- -> no fly-in).
--
-- Self-contained tool identification (does NOT depend on enchanting.lua, which only loads with
-- enhancements_enabled): tools always carry uses_left/max_uses + an enchants table in config.extra,
-- so repair works standalone and the enchant-merge is a harmless no-op when there are no enchants.
local function anvil_is_tool(c)
    return c ~= nil and c.ability ~= nil and c.ability.set == 'balacraft_tool'
end

-- The shared TOOL_BY_ID def behind a tool card (the SAME table for two same-type+material tools), or nil.
local function anvil_tool_def(card)
    local key = card and card.config and card.config.center and card.config.center.key
    local id  = key and key:match('^c_balacraft_tool_(.+)$')
    return id and PB_UTIL.TOOL_BY_ID and PB_UTIL.TOOL_BY_ID[id] or nil
end

-- Two tools can be merged iff distinct cards sharing the SAME tool def (type + material).
function PB_UTIL.anvil_compatible(a, b)
    if not (anvil_is_tool(a) and anvil_is_tool(b)) or a == b then return false end
    local da = anvil_tool_def(a)
    return da ~= nil and da == anvil_tool_def(b)
end

-- Merge `consumed` INTO `keep`: keep takes the max tier of each enchant type, POOLS both tools'
-- remaining uses (capped at keep's max -- NOT a free full repair), then `consumed` is removed.
-- set_tool_enchant (enchanting.lua) does the durability rescale + glint when enhancements are on;
-- guarded so it degrades to plain bookkeeping + the use-pool when they're off (all tiers 0 anyway).
-- Returns true on success.
function PB_UTIL.anvil_combine(keep, consumed)
    if not PB_UTIL.anvil_compatible(keep, consumed) then return false end
    local ke = keep.ability and keep.ability.extra
    local ce = consumed.ability and consumed.ability.extra
    if not (ke and ce) then return false end
    -- Capture the pooled remaining uses BEFORE the merge: set_tool_enchant nudges keep.uses_left when
    -- it rescales for a higher Durability tier, so this must read both tools' current uses first.
    local pooled_uses = (ke.uses_left or 0) + (ce.uses_left or 0)
    ke.enchants = ke.enchants or { sharpness = 0, durability = 0, fortune = 0 }
    local cen = ce.enchants or {}
    for _, et in ipairs({ 'sharpness', 'durability', 'fortune' }) do
        local best = math.max(ke.enchants[et] or 0, cen[et] or 0)
        if best > (ke.enchants[et] or 0) then
            if PB_UTIL.set_tool_enchant then
                PB_UTIL.set_tool_enchant(keep, et, best)   -- rescales durability + glint
            else
                ke.enchants[et] = best                      -- enhancements off: bookkeeping only
            end
        end
    end
    -- Pooled remaining durability, capped at keep's (possibly Durability-boosted) max.
    ke.uses_left = math.min(pooled_uses, ke.max_uses or pooled_uses)
    consumed:remove()
    if keep.juice_up then keep:juice_up(0.3, 0.5) end
    pcall(play_sound, 'tarot1', 1.0, 0.7)
    return true
end

-- ── Anvil overlay ────────────────────────────────────────────────────────────
-- Selection: up to 2 selected tool sort_ids (reset fresh each open). The overlay sees the EQUIPPED
-- tools in the Minecraft consumable area (store-and-equip from the inventory to swap a tool in).
PB_UTIL.anvil_state = PB_UTIL.anvil_state or { selected = {} }

local function anvil_tools()
    local out = {}
    local area = G.bc_mc_consumeables
    if area and area.cards then
        for _, c in ipairs(area.cards) do
            if anvil_is_tool(c) then out[#out + 1] = c end
        end
    end
    return out
end

local function anvil_is_selected(sid)
    for _, s in ipairs(PB_UTIL.anvil_state.selected) do if s == sid then return true end end
    return false
end

-- Resolve the selected sort_ids back to live cards (in selection order: [1] survives a combine).
local function anvil_selected_cards()
    local sel, by_sid = {}, {}
    for _, c in ipairs(anvil_tools()) do by_sid[c.sort_id] = c end
    for _, sid in ipairs(PB_UTIL.anvil_state.selected) do
        if by_sid[sid] then sel[#sel + 1] = by_sid[sid] end
    end
    return sel
end

-- The roman-numeral enchant summary + uses line for a tool row.
local function anvil_row_text(card)
    local e  = (card.ability and card.ability.extra) or {}
    local en = e.enchants or {}
    local roman = function(n) return (PB_UTIL.ENCHANT_ROMAN and PB_UTIL.ENCHANT_ROMAN[n]) or tostring(n) end
    local parts = {}
    if (en.sharpness or 0) > 0 then parts[#parts + 1] = 'Sharp ' .. roman(en.sharpness) end
    if (en.durability or 0) > 0 then parts[#parts + 1] = 'Dura ' .. roman(en.durability) end
    if (en.fortune or 0) > 0 then parts[#parts + 1] = 'Fort ' .. roman(en.fortune) end
    local ench = (#parts > 0) and table.concat(parts, ', ') or 'no enchants'
    local uses = (e.uses_left or 0) .. '/' .. (e.max_uses or 0) .. ' uses'
    return ench, uses
end

-- A small tool badge icon (bc_tool_icons), or a blank cell.
local function anvil_tool_icon(card)
    local key   = card.config and card.config.center and card.config.center.key
    local pos   = key and PB_UTIL.tool_icon_pos and PB_UTIL.tool_icon_pos[key]
    local atlas = PB_UTIL.tool_icon_atlas and G.ASSET_ATLAS[PB_UTIL.tool_icon_atlas.key]
    if pos and atlas then
        return { n = G.UIT.O, config = { object = Sprite(0, 0, 0.6, 0.6, atlas, pos) } }
    end
    return { n = G.UIT.C, config = { align = 'cm', minw = 0.6, minh = 0.6 }, nodes = {} }
end

-- One clickable tool row (selected -> gold; else dark). Carries the card sort_id for the toggle FUNC.
local function anvil_tool_row(card)
    local tdef = anvil_tool_def(card)
    local name = (tdef and tdef.name) or 'Tool'
    local ench, uses = anvil_row_text(card)
    local sel = anvil_is_selected(card.sort_id)
    return {
        n = G.UIT.R, config = {
            align = 'cm', padding = 0.06, r = 0.08, minw = 6.4, minh = 0.7,
            colour = sel and G.C.ORANGE or G.C.UI.TRANSPARENT_DARK,
            button = 'bc_anvil_toggle', bc_sid = card.sort_id, hover = true, shadow = true,
        },
        nodes = {
            { n = G.UIT.C, config = { align = 'cm', padding = 0.05 }, nodes = { anvil_tool_icon(card) } },
            { n = G.UIT.C, config = { align = 'cl', padding = 0.05, minw = 5.4 }, nodes = {
                { n = G.UIT.R, config = { align = 'cl' }, nodes = {
                    { n = G.UIT.T, config = { text = name, scale = 0.36, colour = G.C.UI.TEXT_LIGHT } } } },
                { n = G.UIT.R, config = { align = 'cl' }, nodes = {
                    { n = G.UIT.T, config = { text = ench .. '  ·  ' .. uses, scale = 0.28,
                        colour = sel and G.C.UI.TEXT_LIGHT or G.C.UI.TEXT_INACTIVE } } } },
            } },
        },
    }
end

-- ── Anvil "Enchant" tab helpers (apply a book to a tool; free) ─────────────────
-- Enchant books currently in the MC consumable area.
local function anvil_books()
    local out = {}
    local area = G.bc_mc_consumeables
    if area and area.cards then
        for _, c in ipairs(area.cards) do
            if PB_UTIL.is_enchant_book and PB_UTIL.is_enchant_book(c) then out[#out + 1] = c end
        end
    end
    return out
end

-- Resolve a sort_id back to a live card in the MC area (tool OR book).
local function anvil_card_by_sid(sid)
    if sid == nil then return nil end
    local area = G.bc_mc_consumeables
    if area and area.cards then
        for _, c in ipairs(area.cards) do if c.sort_id == sid then return c end end
    end
    return nil
end

-- The book def (name + atlas pos) behind a book card.
local function anvil_book_def(card)
    local e = card and card.ability and card.ability.extra
    if not (e and e.etype) then return nil end
    return PB_UTIL.ENCHANT_BOOK_BY_ID and PB_UTIL.ENCHANT_BOOK_BY_ID[(e.etype) .. '_' .. (e.tier or 1)]
end

local function anvil_book_icon(card)
    local b = anvil_book_def(card)
    local atlas = PB_UTIL.enchant_icon_atlas and G.ASSET_ATLAS[PB_UTIL.enchant_icon_atlas.key]
    if b and b.pos and atlas then
        return { n = G.UIT.O, config = { object = Sprite(0, 0, 0.6, 0.6, atlas, b.pos) } }
    end
    return { n = G.UIT.C, config = { align = 'cm', minw = 0.6, minh = 0.6 }, nodes = {} }
end

-- A clickable tool row for the Enchant tab (selects PB_UTIL.anvil_state.ench_tool).
local function anvil_ench_tool_row(card)
    local tdef = anvil_tool_def(card)
    local name = (tdef and tdef.name) or 'Tool'
    local ench, uses = anvil_row_text(card)
    local sel = (PB_UTIL.anvil_state.ench_tool == card.sort_id)
    return {
        n = G.UIT.R, config = {
            align = 'cm', padding = 0.06, r = 0.08, minw = 5.6, minh = 0.66,
            colour = sel and G.C.ORANGE or G.C.UI.TRANSPARENT_DARK,
            button = 'bc_anvil_ench_pick_tool', bc_sid = card.sort_id, hover = true, shadow = true,
        },
        nodes = {
            { n = G.UIT.C, config = { align = 'cm', padding = 0.05 }, nodes = { anvil_tool_icon(card) } },
            { n = G.UIT.C, config = { align = 'cl', padding = 0.05, minw = 4.6 }, nodes = {
                { n = G.UIT.R, config = { align = 'cl' }, nodes = {
                    { n = G.UIT.T, config = { text = name, scale = 0.34, colour = G.C.UI.TEXT_LIGHT } } } },
                { n = G.UIT.R, config = { align = 'cl' }, nodes = {
                    { n = G.UIT.T, config = { text = ench .. '  ·  ' .. uses, scale = 0.26,
                        colour = sel and G.C.UI.TEXT_LIGHT or G.C.UI.TEXT_INACTIVE } } } },
            } },
        },
    }
end

-- A clickable book row for the Enchant tab (selects PB_UTIL.anvil_state.ench_book).
local function anvil_ench_book_row(card)
    local b = anvil_book_def(card)
    local name = (b and b.name) or 'Enchant Book'
    local sel = (PB_UTIL.anvil_state.ench_book == card.sort_id)
    return {
        n = G.UIT.R, config = {
            align = 'cm', padding = 0.06, r = 0.08, minw = 5.6, minh = 0.6,
            colour = sel and G.C.ORANGE or G.C.UI.TRANSPARENT_DARK,
            button = 'bc_anvil_ench_pick_book', bc_sid = card.sort_id, hover = true, shadow = true,
        },
        nodes = {
            { n = G.UIT.C, config = { align = 'cm', padding = 0.05 }, nodes = { anvil_book_icon(card) } },
            { n = G.UIT.C, config = { align = 'cl', padding = 0.05, minw = 4.6 }, nodes = {
                { n = G.UIT.T, config = { text = name, scale = 0.34, colour = G.C.UI.TEXT_LIGHT } } } },
        },
    }
end

-- ── Anvil "Forge Sheets" mode ─────────────────────────────────────────────────
-- The Anvil's second tab: press 2 of one ORE into the matching Sheet consumable. A 2-input drag
-- overlay modelled on the Furnace -- drag an ore into each of the two slots (both must be the SAME
-- ore), then Forge. Reuses the Furnace slot/reserve plumbing wholesale: build_anvil_forge_cells
-- builds into PB_UTIL.furnace_cells, so the shared drag router + the _furnace_exit_hooked teardown
-- drive it with no extra code. Inert / guarded when sheets are off (PB_UTIL.SHEETS absent).
PB_UTIL.ANVIL_COST = 2   -- ores consumed per sheet (one reserved tile in each of the two slots)

-- The 'anvil'-station Sheet whose ore == rid, or nil. Derived from PB_UTIL.SHEETS (content/sheets/).
function PB_UTIL.anvil_recipe_for_ore(rid)
    if not rid then return nil end
    for _, s in ipairs(PB_UTIL.SHEETS or {}) do
        if s.station == 'anvil' and s.ore == rid then return s end
    end
    return nil
end
function PB_UTIL.anvil_ore_accepts(rid) return PB_UTIL.anvil_recipe_for_ore(rid) ~= nil end

PB_UTIL.anvil_forge_state = PB_UTIL.anvil_forge_state or { can_forge = false }

-- True iff both slots hold the SAME forgeable ore and there is consumable room for the sheet.
function PB_UTIL.anvil_can_forge()
    if not PB_UTIL.furnace_cells then return false end
    local a = PB_UTIL.anvil_in_a and PB_UTIL.anvil_in_a.cards and PB_UTIL.anvil_in_a.cards[1]
    local b = PB_UTIL.anvil_in_b and PB_UTIL.anvil_in_b.cards and PB_UTIL.anvil_in_b.cards[1]
    if not (a and b) then return false end
    local ra, rb = PB_UTIL.tile_resource(a), PB_UTIL.tile_resource(b)
    if not (ra and rb and ra == rb and PB_UTIL.anvil_recipe_for_ore(ra)) then return false end
    if PB_UTIL.has_consumable_room and not PB_UTIL.has_consumable_room() then return false end
    return true
end

-- Forge one sheet: consume both reserved input tiles (no credit), spawn the sheet consumable, then
-- auto-refill both slots if 2 more of that ore remain (so Forge can be clicked repeatedly).
function PB_UTIL.anvil_do_forge()
    if not PB_UTIL.anvil_can_forge() then return false end
    local ra    = PB_UTIL.tile_resource(PB_UTIL.anvil_in_a.cards[1])
    local sheet = PB_UTIL.anvil_recipe_for_ore(ra)
    PB_UTIL.anvil_in_a.cards[1]:remove()   -- consume reserved tile (NO credit)
    PB_UTIL.anvil_in_b.cards[1]:remove()
    consumable_add('c_balacraft_sheet_' .. sheet.id)
    PB_UTIL.anvil_last_out = sheet.id
    if PB_UTIL.get_resource_count(ra) >= 2 then
        local t1 = PB_UTIL.spawn_reserved_tile(ra); if t1 then PB_UTIL.place_in_area(t1, PB_UTIL.anvil_in_a) end
        local t2 = PB_UTIL.spawn_reserved_tile(ra); if t2 then PB_UTIL.place_in_area(t2, PB_UTIL.anvil_in_b) end
    end
    return true
end

-- Output-preview icon: the sheet for whatever ore fills BOTH matched slots, else the last forged,
-- else hidden. (Mirrors refresh_furnace_output, but on bc_sheet_icons.)
function PB_UTIL.refresh_anvil_output()
    if not G.OVERLAY_MENU then return end
    local icon = G.OVERLAY_MENU:get_UIE_by_ID('bc_anvil_output_icon')
    if not (icon and icon.config and icon.config.object) then return end
    local obj = icon.config.object
    local a = PB_UTIL.anvil_in_a and PB_UTIL.anvil_in_a.cards and PB_UTIL.anvil_in_a.cards[1]
    local b = PB_UTIL.anvil_in_b and PB_UTIL.anvil_in_b.cards and PB_UTIL.anvil_in_b.cards[1]
    local ra = a and PB_UTIL.tile_resource(a)
    local rb = b and PB_UTIL.tile_resource(b)
    local sheet = (ra and rb and ra == rb and PB_UTIL.anvil_recipe_for_ore(ra))
        or (PB_UTIL.anvil_last_out and PB_UTIL.SHEET_BY_ID and PB_UTIL.SHEET_BY_ID[PB_UTIL.anvil_last_out])
    local atlas = PB_UTIL.sheet_icon_atlas and G.ASSET_ATLAS[PB_UTIL.sheet_icon_atlas.key]
    if sheet and atlas then
        obj.atlas = atlas
        obj:set_sprite_pos(sheet.icon)
        if obj.bc_overlay then obj.bc_overlay[4] = 1 end
    elseif obj.bc_overlay then
        obj.bc_overlay[4] = 0
    end
end

-- Per-frame: snap settled slot tiles + refresh can_forge + preview. Inert unless the forge tab is
-- open (furnace_cells + the anvil slots present). Wired into update_crafting_modal (crafting_ui.lua).
function PB_UTIL.update_anvil_forge()
    if not (PB_UTIL.furnace_cells and PB_UTIL.anvil_in_a) then return end
    PB_UTIL.anvil_forge_state.can_forge = PB_UTIL.anvil_can_forge()
    local C = G.CONTROLLER
    local dragged = C and C.dragging and C.dragging.target
    for _, slot in ipairs(PB_UTIL.furnace_cells) do
        local area = slot.area
        local card = area and area.cards and area.cards[1]
        if card and card ~= dragged and not (card.states and card.states.drag.is) then
            local tx = area.T.x + (area.T.w - card.T.w) / 2
            local ty = area.T.y + (area.T.h - card.T.h) / 2
            card.T.x, card.T.y = tx, ty
            card.VT.x, card.VT.y = tx, ty
        end
    end
    PB_UTIL.refresh_anvil_output()
end

local FORGE_CELL = 0.76
-- A single grid-cell-sized output square holding the sheet preview icon (or blank if art isn't ready).
local function anvil_forge_output_node()
    local atlas = PB_UTIL.sheet_icon_atlas and G.ASSET_ATLAS[PB_UTIL.sheet_icon_atlas.key]
    local inner
    if atlas then
        local first = (PB_UTIL.SHEETS and PB_UTIL.SHEETS[1] and PB_UTIL.SHEETS[1].icon) or { x = 0, y = 0 }
        local out_icon = PB_UTIL.make_dimmable(Sprite(0, 0, 0.5, 0.5, atlas, first))
        out_icon.bc_overlay[4] = 0   -- hidden until both slots hold a matching ore
        inner = { n = G.UIT.O, config = { id = 'bc_anvil_output_icon', object = out_icon } }
    else
        inner = { n = G.UIT.T, config = { text = ' ', scale = 0.3 } }
    end
    local square = {
        n = G.UIT.C, config = { align = 'cm', padding = 0.03, r = 0.05, colour = G.C.UI.TRANSPARENT_DARK,
                                minw = FORGE_CELL, minh = FORGE_CELL },
        nodes = { inner },
    }
    return { n = G.UIT.C, config = { align = 'cm' }, nodes = { square } }
end

-- Tab switcher shared by both Anvil modes (active tab is highlighted + non-clickable).
local function anvil_tab_row(active)
    local function tab(label, key, fn)
        local on = (active == key)
        return { n = G.UIT.C, config = { align = 'cm', padding = 0.08, r = 0.08, minw = 2.4, minh = 0.5,
            colour = on and G.C.ORANGE or G.C.UI.TRANSPARENT_DARK,
            button = (not on) and fn or nil, hover = not on, shadow = true },
            nodes = { { n = G.UIT.T, config = { text = label, scale = 0.32, colour = G.C.UI.TEXT_LIGHT } } } }
    end
    local tabs = {
        tab('Forge Sheets', 'forge', 'bc_anvil_tab_forge'),
        tab('Combine Tools', 'combine', 'bc_anvil_tab_combine'),
    }
    if PB_UTIL.ENCHANT_BOOKS then
        tabs[#tabs + 1] = tab('Enchant', 'enchant', 'bc_anvil_tab_enchant')
    end
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.06 }, nodes = tabs }
end

function PB_UTIL.build_anvil_forge_modal()
    local forge_btn = {
        n = G.UIT.C, config = { align = 'cm' }, nodes = { {
            n = G.UIT.R, config = { id = 'bc_anvil_forge_btn', align = 'cm', padding = 0.1, r = 0.1,
                minw = 1.6, minh = FORGE_CELL, colour = G.C.UI.TRANSPARENT_LIGHT,
                button = 'bc_anvil_forge', func = 'bc_anvil_can_forge_btn', hover = true, shadow = true },
            nodes = { { n = G.UIT.T, config = { text = 'Forge', scale = 0.45, colour = G.C.UI.TEXT_LIGHT } } },
        } } }
    local plus  = { n = G.UIT.C, config = { align = 'cm', padding = 0.06 },
        nodes = { { n = G.UIT.T, config = { text = '+', scale = 0.6, colour = G.C.WHITE } } } }
    local arrow = { n = G.UIT.C, config = { align = 'cm', padding = 0.1 },
        nodes = { { n = G.UIT.T, config = { text = '=', scale = 0.6, colour = G.C.WHITE } } } }
    local forge_row = { n = G.UIT.R, config = { align = 'cm', padding = 0.06 }, nodes = {
        PB_UTIL.furnace_slot_node(PB_UTIL.anvil_in_a), plus,
        PB_UTIL.furnace_slot_node(PB_UTIL.anvil_in_b), arrow,
        anvil_forge_output_node(), forge_btn,
    } }
    return { n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0.12, r = 0.1, colour = G.C.GREY, minw = 9, minh = 5 },
        nodes = {
            text_row('Anvil', 0.6, G.C.ORANGE),
            anvil_tab_row('forge'),
            { n = G.UIT.R, config = { align = 'cm', padding = 0.06, r = 0.1, colour = G.C.BLACK }, nodes = { forge_row } },
            text_row('Drag 2 of the SAME ore into the slots, then Forge a Sheet.', 0.26, G.C.UI.TEXT_INACTIVE),
            { n = G.UIT.R, config = { align = 'cm', minh = 0.1 }, nodes = {} },
            { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                { n = G.UIT.T, config = { text = 'Inventory', scale = 0.38, colour = G.C.UI.TEXT_LIGHT } } } },
            { n = G.UIT.R, config = { align = 'cm' }, nodes = { PB_UTIL.build_inventory_node() } },
            { n = G.UIT.R, config = { align = 'cm', minh = 0.1 }, nodes = {} },
            full_btn('Back', 'bc_anvil_back'),
        } }
end

function PB_UTIL.open_anvil_forge()
    PB_UTIL.anvil_state.tab = 'forge'
    PB_UTIL.anvil_forge_state.can_forge = false
    PB_UTIL.anvil_last_out = nil
    PB_UTIL.build_anvil_forge_cells()                          -- the two ore input slots
    PB_UTIL.build_inventory()                                  -- shared draggable source grid
    PB_UTIL.furnace_on_change = PB_UTIL.update_anvil_forge     -- drag/right-click -> immediate refresh
    PB_UTIL.refresh_overlay(PB_UTIL.build_anvil_forge_modal())
end

function PB_UTIL.build_anvil_modal()
    local tools = anvil_tools()
    local nodes = {
        text_row('Anvil', 0.6, G.C.ORANGE),
        anvil_tab_row('combine'),
        text_row('Combine two tools of the same type & material: keep the best enchants and pool their remaining uses.',
            0.26, G.C.UI.TEXT_INACTIVE),
        { n = G.UIT.R, config = { align = 'cm', minh = 0.12 }, nodes = {} },
    }

    if #tools < 1 then
        nodes[#nodes + 1] = text_row('You have no tools to combine.', 0.34, G.C.UI.TEXT_INACTIVE)
    else
        local list = { n = G.UIT.C, config = { align = 'cm', padding = 0.05 }, nodes = {} }
        for _, c in ipairs(tools) do list.nodes[#list.nodes + 1] = anvil_tool_row(c) end
        nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.06, r = 0.1,
            colour = G.C.BLACK }, nodes = { list } }
    end

    -- Action / status area driven by the current selection.
    local sel = anvil_selected_cards()
    nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm', minh = 0.12 }, nodes = {} }
    if #sel == 2 and PB_UTIL.anvil_compatible(sel[1], sel[2]) then
        nodes[#nodes + 1] = full_btn('Combine', 'bc_anvil_combine', G.C.GREEN)
    elseif #sel == 2 then
        nodes[#nodes + 1] = text_row('Those tools must be the same type & material.', 0.3, G.C.RED)
    else
        nodes[#nodes + 1] = text_row('Select two matching tools (' .. #sel .. '/2 selected).',
            0.3, G.C.UI.TEXT_INACTIVE)
    end
    nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm', minh = 0.1 }, nodes = {} }
    nodes[#nodes + 1] = full_btn('Back', 'bc_anvil_back')

    return { n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0.12, r = 0.1, colour = G.C.GREY, minw = 8, minh = 4 },
        nodes = nodes }
end

function PB_UTIL.build_anvil_enchant_modal()
    local tools = anvil_tools()
    local books = anvil_books()
    local nodes = {
        text_row('Anvil', 0.6, G.C.ORANGE),
        anvil_tab_row('enchant'),
        text_row('Pick a tool and an enchant book to apply it. Applying is free.', 0.26, G.C.UI.TEXT_INACTIVE),
        { n = G.UIT.R, config = { align = 'cm', minh = 0.12 }, nodes = {} },
    }
    if #tools < 1 or #books < 1 then
        nodes[#nodes + 1] = text_row('You need a tool and an enchant book in your consumable slots.',
            0.32, G.C.UI.TEXT_INACTIVE)
    else
        local tlist = { n = G.UIT.C, config = { align = 'tm', padding = 0.04 }, nodes = {} }
        for _, c in ipairs(tools) do tlist.nodes[#tlist.nodes + 1] = anvil_ench_tool_row(c) end
        local blist = { n = G.UIT.C, config = { align = 'tm', padding = 0.04 }, nodes = {} }
        for _, c in ipairs(books) do blist.nodes[#blist.nodes + 1] = anvil_ench_book_row(c) end
        nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.06, r = 0.1, colour = G.C.BLACK }, nodes = {
            { n = G.UIT.C, config = { align = 'tm', padding = 0.06 }, nodes = { text_row('Tools', 0.3), tlist } },
            { n = G.UIT.C, config = { align = 'tm', padding = 0.06 }, nodes = { text_row('Books', 0.3), blist } },
        } }
    end

    local tool = anvil_card_by_sid(PB_UTIL.anvil_state.ench_tool)
    local book = anvil_card_by_sid(PB_UTIL.anvil_state.ench_book)
    nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm', minh = 0.12 }, nodes = {} }
    if tool and book and PB_UTIL.is_enchant_book(book) and PB_UTIL.enchant_is_valid(tool, book) then
        nodes[#nodes + 1] = full_btn('Apply', 'bc_anvil_ench_apply', G.C.GREEN)
    elseif tool and book then
        nodes[#nodes + 1] = text_row("That book can't enchant that tool (wrong type, or not an upgrade).",
            0.3, G.C.RED)
    else
        nodes[#nodes + 1] = text_row('Select one tool and one book.', 0.3, G.C.UI.TEXT_INACTIVE)
    end
    nodes[#nodes + 1] = { n = G.UIT.R, config = { align = 'cm', minh = 0.1 }, nodes = {} }
    nodes[#nodes + 1] = full_btn('Back', 'bc_anvil_back')

    return { n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0.12, r = 0.1, colour = G.C.GREY, minw = 8, minh = 4 },
        nodes = nodes }
end

function PB_UTIL.open_anvil()
    PB_UTIL.anvil_state.selected = {}
    PB_UTIL.anvil_state.tab = PB_UTIL.anvil_state.tab or 'forge'
    if PB_UTIL.anvil_state.tab == 'forge' and PB_UTIL.SHEETS then
        PB_UTIL.open_anvil_forge()
    elseif PB_UTIL.anvil_state.tab == 'enchant' and PB_UTIL.ENCHANT_BOOKS then
        PB_UTIL.refresh_overlay(PB_UTIL.build_anvil_enchant_modal())
    else
        PB_UTIL.anvil_state.tab = 'combine'
        PB_UTIL.refresh_overlay(PB_UTIL.build_anvil_modal())
    end
end

-- Toggle a tool's selection (cap 2; a 3rd pick slides the oldest out), then rebuild in place.
G.FUNCS.bc_anvil_toggle = function(e)
    local sid = e.config and e.config.bc_sid
    if sid == nil then return end
    local sel = PB_UTIL.anvil_state.selected
    local at
    for i, s in ipairs(sel) do if s == sid then at = i; break end end
    if at then
        table.remove(sel, at)
    else
        sel[#sel + 1] = sid
        if #sel > 2 then table.remove(sel, 1) end
    end
    PB_UTIL.refresh_overlay(PB_UTIL.build_anvil_modal())
end

G.FUNCS.bc_anvil_combine = function(e)
    local sel = anvil_selected_cards()
    if #sel == 2 and PB_UTIL.anvil_combine(sel[1], sel[2]) then
        play_sound('timpani', 0.8)
    else
        play_sound('cancel')
    end
    PB_UTIL.anvil_state.selected = {}
    PB_UTIL.refresh_overlay(PB_UTIL.build_anvil_modal())
end

G.FUNCS.bc_anvil_back = function(e)
    -- The Forge tab holds drag slots in furnace_cells; credit any reserved tiles before leaving.
    if PB_UTIL.furnace_cells then
        PB_UTIL.destroy_furnace_cells()
        PB_UTIL.furnace_on_change = nil
    end
    PB_UTIL.anvil_state.selected = {}
    PB_UTIL.anvil_state.ench_tool = nil
    PB_UTIL.anvil_state.ench_book = nil
    PB_UTIL.open_base()
end

G.FUNCS.bc_open_anvil = function(e) PB_UTIL.open_anvil() end

-- ── Anvil tab switching ───────────────────────────────────────────────────────
G.FUNCS.bc_anvil_tab_forge = function(e)
    PB_UTIL.anvil_state.selected = {}
    PB_UTIL.anvil_state.ench_tool = nil
    PB_UTIL.anvil_state.ench_book = nil
    PB_UTIL.open_anvil_forge()
end

G.FUNCS.bc_anvil_tab_combine = function(e)
    if PB_UTIL.furnace_cells then              -- leaving the Forge tab: tear down its slots (credits tiles)
        PB_UTIL.destroy_furnace_cells()
        PB_UTIL.furnace_on_change = nil
    end
    PB_UTIL.anvil_state.tab = 'combine'
    PB_UTIL.anvil_state.selected = {}
    PB_UTIL.anvil_state.ench_tool = nil
    PB_UTIL.anvil_state.ench_book = nil
    PB_UTIL.refresh_overlay(PB_UTIL.build_anvil_modal())
end

G.FUNCS.bc_anvil_tab_enchant = function(e)
    if PB_UTIL.furnace_cells then              -- leaving the Forge tab: tear down its slots
        PB_UTIL.destroy_furnace_cells()
        PB_UTIL.furnace_on_change = nil
    end
    PB_UTIL.anvil_state.tab = 'enchant'
    PB_UTIL.anvil_state.selected = {}
    PB_UTIL.anvil_state.ench_tool = nil
    PB_UTIL.anvil_state.ench_book = nil
    PB_UTIL.refresh_overlay(PB_UTIL.build_anvil_enchant_modal())
end

G.FUNCS.bc_anvil_ench_pick_tool = function(e)
    local sid = e.config and e.config.bc_sid
    PB_UTIL.anvil_state.ench_tool = (PB_UTIL.anvil_state.ench_tool == sid) and nil or sid
    PB_UTIL.refresh_overlay(PB_UTIL.build_anvil_enchant_modal())
end

G.FUNCS.bc_anvil_ench_pick_book = function(e)
    local sid = e.config and e.config.bc_sid
    PB_UTIL.anvil_state.ench_book = (PB_UTIL.anvil_state.ench_book == sid) and nil or sid
    PB_UTIL.refresh_overlay(PB_UTIL.build_anvil_enchant_modal())
end

G.FUNCS.bc_anvil_ench_apply = function(e)
    local tool = anvil_card_by_sid(PB_UTIL.anvil_state.ench_tool)
    local book = anvil_card_by_sid(PB_UTIL.anvil_state.ench_book)
    if tool and book and PB_UTIL.apply_enchant(tool, book) then
        play_sound('timpani', 0.8)
    else
        play_sound('cancel')
    end
    PB_UTIL.anvil_state.ench_tool = nil
    PB_UTIL.anvil_state.ench_book = nil
    PB_UTIL.refresh_overlay(PB_UTIL.build_anvil_enchant_modal())
end

-- ── Forge button (mirror the Furnace's smelt button) ──────────────────────────
G.FUNCS.bc_anvil_can_forge_btn = function(e)
    e.config.colour = PB_UTIL.anvil_forge_state.can_forge and G.C.GREEN or G.C.UI.TRANSPARENT_LIGHT
end

G.FUNCS.bc_anvil_forge = function(e)
    if PB_UTIL.anvil_do_forge() then play_sound('timpani', 0.8) else play_sound('cancel') end
    PB_UTIL.update_anvil_forge()   -- in-place refresh (button + preview)
    PB_UTIL.update_inventory()     -- an ore may have hit 0 -> reflow the source grid
end
