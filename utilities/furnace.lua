-- The Furnace + the Anvil station logic + the station-build registry.
--
-- Furnace: a Base station that smelts RAW ores into refined ingots, burning fuel. MC-faithful
-- smelt set: raw_iron -> iron, raw_gold -> gold (1:1). Fuel is a buffer on G.GAME.balacraft
-- (seeded in resources.lua init wrapper): loading 1 coal -> +4 charges, 1 wood -> +1; each smelt
-- spends 1 charge + 1 raw -> 1 refined.
--
-- Both the Furnace and the Anvil render IN-FRAME in the unified Inventory modal (furnace_station_content
-- / anvil_station_content, embedded by crafting_ui.lua's build_base_shell). Their drag slots are
-- built/torn down by open_inventory(<station>); the shared drag router + per-frame updaters drive them.

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

-- ── Furnace overlay (Minecraft-furnace layout, drag-driven) ──────────────────
-- Build ONCE / mutate in place (like the crafting table): drag a raw ore from the bottom resource
-- grid into the INPUT slot and a fuel (coal/wood) into the FUEL slot, then click Smelt. Counts /
-- fuel gauge / button-enabled / output preview are all live (bound refs + a per-frame func), so an
-- action never rebuilds the overlay -- nothing "flies in from below" on every click.

-- Live-bound display state (seeded in open_inventory('furnace'); updated by update_furnace_modal each frame).
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
    return { n = G.UIT.C, config = { align = 'cm' }, nodes = { smelt_row } }
end

-- (The standalone Furnace modal + open_furnace are gone -- the Furnace renders in-frame via
-- furnace_station_content; open_inventory('furnace') builds its cells. See crafting_ui.lua.)

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

-- ── "Your Base" launcher ────────────────────────────────────────────────────
-- A grid of station CARDS (title on top, the block sprite in the middle, an Open button below).
-- ready=false stations show their card greyed with a "(soon)" / "(craft it)" label; later waves
-- flip them on. The Crafting Table opens with back='base' so its Back returns here.

-- Station block icons (bc_station_icons): 34x34 cells holding the genuine MC 3D isometric inventory
-- renders (assets/gen_stations.py). Registered here since the Base is the only consumer.
PB_UTIL.station_icon_atlas = SMODS.Atlas { key = 'bc_station_icons', path = 'station_icons.png', px = 34, py = 34 }

-- Atlas cell positions, MUST match assets/gen_stations.py CELLS. (Brewing Stand has no cube render,
-- so it uses its flat item sprite; Ender Chest is entity-only -> name-only card, no cell here.)
PB_UTIL.STATION_ICONS = {
    crafting_table = { x = 0, y = 0 }, furnace = { x = 1, y = 0 }, composter = { x = 2, y = 0 },
    anvil = { x = 3, y = 0 }, brewing_stand = { x = 0, y = 1 }, chest = { x = 1, y = 1 },
    enchanting_table = { x = 2, y = 1 },
}

-- The old standalone "Your Base" launcher grid is gone -- every station is now a tile in the unified
-- Inventory modal's Workbench picker (PICKER_STATIONS in crafting_ui.lua). `open_base` / `bc_open_base`
-- stay as the canonical "open the unified modal" entry (the hotbar button + any legacy caller).
function PB_UTIL.open_base()
    PB_UTIL.open_inventory('crafting_table')
end

G.FUNCS.bc_open_base = function(e) PB_UTIL.open_base() end

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

-- ── Anvil "Upgrade" (the Smithing-Table stand-in): Diamond tool + Netherite ───
-- Minecraft-faithful: netherite gear is NOT crafted at a table -- you UPGRADE the diamond tool with a
-- netherite ingot (this mod has no Smithing Table, so the Anvil hosts it). Spends NETHERITE_UPGRADE_COST
-- netherite, swaps the diamond tool for its netherite counterpart, and CARRIES OVER the diamond's
-- enchants + durability DAMAGE (a worn/enchanted diamond -> a worn/enchanted netherite -- not a free
-- repair). Self-contained like anvil_combine: set_tool_enchant is guarded so it degrades to plain
-- bookkeeping when enhancements are off.
PB_UTIL.NETHERITE_UPGRADE_COST = 1   -- netherite ingots per upgrade (Minecraft = 1)

-- True iff `card` is a Diamond tool (the only valid upgrade input). NOTE: `anvil_is_tool(card) and
-- anvil_tool_def(card)` yields `false` (not nil) for a non-tool, so guard on `d` truthiness, not `~= nil`
-- (the unified dispatch passes books/resource-tiles through here).
local function anvil_is_diamond_tool(card)
    local d = anvil_is_tool(card) and anvil_tool_def(card)
    return (d and d.material == 'diamond') and true or false
end

-- The Diamond->Netherite transform itself, WITHOUT charging netherite (callers pay differently: the
-- unified slot consumes a reserved netherite tile; the bare PB_UTIL.anvil_upgrade debits by count).
-- Removes the diamond, forges the netherite tool carrying enchants + durability damage, routes it into
-- the MC area / inventory. Returns true on success.
local function anvil_upgrade_apply(diamond_card)
    local tdef = anvil_is_diamond_tool(diamond_card) and anvil_tool_def(diamond_card)
    if not tdef then return false end
    local key = 'c_balacraft_tool_' .. tdef.tool .. '_netherite'
    if not (G.P_CENTERS and G.P_CENTERS[key]) then return false end
    -- Capture the diamond's state BEFORE mutating anything.
    local de     = (diamond_card.ability and diamond_card.ability.extra) or {}
    local damage = math.max(0, (de.max_uses or 0) - (de.uses_left or 0))
    local old_en = de.enchants or {}
    diamond_card:remove()
    -- Forge the netherite tool (same body as consumable_add, but we keep the handle to copy state).
    local c = SMODS.create_card({ key = key })
    c:add_to_deck()
    local ne = c.ability.extra
    ne.enchants = ne.enchants or { sharpness = 0, durability = 0, fortune = 0 }
    -- Carry enchants FIRST (set_tool_enchant rescales max_uses for the Durability tier + adds glint).
    for _, et in ipairs({ 'sharpness', 'durability', 'fortune' }) do
        local lvl = old_en[et] or 0
        if lvl > 0 then
            if PB_UTIL.set_tool_enchant then PB_UTIL.set_tool_enchant(c, et, lvl)
            else ne.enchants[et] = lvl end
        end
    end
    -- Carry durability as DAMAGE against the (now-final) netherite max -- faithful to MC.
    ne.uses_left = math.max(1, math.min((ne.max_uses or 5) - damage, ne.max_uses or 5))
    G.consumeables:emplace(c)
    -- Route into the freed MC slot, else the inventory (the update-loop sweep would also catch it).
    if PB_UTIL.reconcile_mc_consumables then PB_UTIL.reconcile_mc_consumables() end
    if c.juice_up then c:juice_up(0.3, 0.5) end
    return true
end

-- Upgrade a held Diamond tool to its Netherite counterpart, charging netherite by COUNT. Returns true
-- on success. (The unified Anvil pays with a reserved tile instead -- see PB_UTIL.anvil_upgrade_slots.)
function PB_UTIL.anvil_upgrade(diamond_card)
    local tdef = anvil_is_diamond_tool(diamond_card) and anvil_tool_def(diamond_card)
    if not tdef then return false end
    if not (G.P_CENTERS and G.P_CENTERS['c_balacraft_tool_' .. tdef.tool .. '_netherite']) then return false end
    local cost = PB_UTIL.NETHERITE_UPGRADE_COST or 1
    if PB_UTIL.get_resource_count('netherite') < cost then return false end
    PB_UTIL.add_resource('netherite', -cost)
    return anvil_upgrade_apply(diamond_card)
end

-- ── Forge-Sheets core (one of the four unified-Anvil mechanics) ───────────────
-- Press 2 of one ORE into the matching Sheet consumable. anvil_dispatch routes here when both unified
-- slots hold the SAME forgeable ore; anvil_do_forge consumes the two reserved slot tiles and spawns the
-- Sheet. Inert / guarded when sheets are off (PB_UTIL.SHEETS absent -> anvil_recipe_for_ore returns nil).
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
    if not (PB_UTIL.anvil_in_a and PB_UTIL.anvil_in_b) then return false end
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

-- ── Unified Anvil: one screen, the mechanic inferred from the two slot contents ──
-- The two input slots (PB_UTIL.anvil_in_a / anvil_in_b, built in crafting_grid.lua) accept BOTH
-- resource tiles AND tool/book cards. anvil_dispatch reads the pair and returns the matched mechanic +
-- a ready-to-run action. Disjoint by input type, so order of checks is safe and the pair is order-agnostic.
PB_UTIL.anvil_unified_state = PB_UTIL.anvil_unified_state or { valid = false, label = 'Anvil', hint = '' }

-- No how-to descriptions on the Anvil (the player learns by doing). The live hint shows ONLY a warning
-- when the current pair can't be combined; otherwise it's blank.
local DEFAULT_ANVIL_HINT = ''

function PB_UTIL.anvil_dispatch()
    local a = PB_UTIL.anvil_in_a and PB_UTIL.anvil_in_a.cards and PB_UTIL.anvil_in_a.cards[1]
    local b = PB_UTIL.anvil_in_b and PB_UTIL.anvil_in_b.cards and PB_UTIL.anvil_in_b.cards[1]
    if not (a and b) then return { valid = false } end
    local ra, rb = PB_UTIL.tile_resource(a), PB_UTIL.tile_resource(b)

    -- Forge: two of the SAME forgeable ore (gated on PB_UTIL.SHEETS via anvil_recipe_for_ore).
    if ra and rb and ra == rb and PB_UTIL.anvil_recipe_for_ore and PB_UTIL.anvil_recipe_for_ore(ra) then
        local sheet = PB_UTIL.anvil_recipe_for_ore(ra)
        local room  = (not PB_UTIL.has_consumable_room) or PB_UTIL.has_consumable_room()
        return { mechanic = 'forge', valid = room and true or false, label = 'Forge', sheet = sheet,
                 warn = (not room) and 'No room for the Sheet.' or nil,
                 action = function() return PB_UTIL.anvil_do_forge() end }
    end

    -- Upgrade: a Diamond tool + a Netherite ore tile (order-agnostic).
    local up_tool, up_tile
    if anvil_is_diamond_tool(a) and rb == 'netherite' then up_tool, up_tile = a, b
    elseif anvil_is_diamond_tool(b) and ra == 'netherite' then up_tool, up_tile = b, a end
    if up_tool then
        return { mechanic = 'upgrade', valid = true, label = 'Upgrade', preview_tool = up_tool,
                 action = function() return PB_UTIL.anvil_upgrade_slots(up_tool, up_tile) end }
    end

    -- Combine: two matching tools.
    if PB_UTIL.anvil_compatible(a, b) then
        return { mechanic = 'combine', valid = true, label = 'Combine', preview_tool = a,
                 action = function() return PB_UTIL.anvil_combine_slots(a, b) end }
    end

    -- Enchant: a tool + an enchant book (order-agnostic; gated on PB_UTIL.is_enchant_book existing).
    local en_tool, en_book
    if anvil_is_tool(a) and PB_UTIL.is_enchant_book and PB_UTIL.is_enchant_book(b) then en_tool, en_book = a, b
    elseif anvil_is_tool(b) and PB_UTIL.is_enchant_book and PB_UTIL.is_enchant_book(a) then en_tool, en_book = b, a end
    if en_tool then
        local ok = PB_UTIL.enchant_is_valid and PB_UTIL.enchant_is_valid(en_tool, en_book)
        return { mechanic = 'enchant', valid = ok and true or false, label = 'Enchant', preview_tool = en_tool,
                 warn = (not ok) and "That book can't enchant that tool." or nil,
                 action = function() return PB_UTIL.anvil_enchant_slots(en_tool, en_book) end }
    end

    return { valid = false, warn = "These two items can't be combined." }
end

-- Slot-aware action wrappers (the cores stay reusable for their other callers).
function PB_UTIL.anvil_upgrade_slots(tool_card, nether_tile)
    if not (tool_card and nether_tile) then return false end
    if PB_UTIL.tile_resource(nether_tile) ~= 'netherite' then return false end
    if not anvil_is_diamond_tool(tool_card) then return false end
    nether_tile:remove()                  -- the reserved tile IS the payment (already debited): no credit
    return anvil_upgrade_apply(tool_card)
end

function PB_UTIL.anvil_combine_slots(a, b)
    return PB_UTIL.anvil_combine(a, b)
end

function PB_UTIL.anvil_enchant_slots(tool, book)
    return (PB_UTIL.apply_enchant and PB_UTIL.apply_enchant(tool, book)) or false
end

-- After an action: surface any surviving tool/book left in a slot, plus any tool/book that landed in
-- the MC area (e.g. a freshly upgraded tool routed there by reconcile), back into the source row so it
-- stays draggable for chaining.
function PB_UTIL.refresh_anvil_source()
    if not PB_UTIL.anvil_src_area then return end
    if PB_UTIL.anvil_unified_cells then
        for _, slot in ipairs(PB_UTIL.anvil_unified_cells) do
            local occ = slot.area and slot.area.cards and slot.area.cards[1]
            if occ and not PB_UTIL.tile_resource(occ) then
                slot.area:remove_card(occ); occ.states.drag.is = false
                PB_UTIL.anvil_src_area:emplace(occ)
            end
        end
    end
    local mc = G.bc_mc_consumeables
    if mc and mc.cards then
        for i = #mc.cards, 1, -1 do
            local c = mc.cards[i]
            if PB_UTIL.is_anvil_consumable and PB_UTIL.is_anvil_consumable(c) then
                mc:remove_card(c); PB_UTIL.anvil_src_area:emplace(c)
            end
        end
    end
end

-- Output-preview icon, retargeted each frame from the dispatch result (sheet icon for a forge, the
-- result tool's badge for upgrade/combine/enchant). Hidden when the pair has no valid output.
function PB_UTIL.refresh_anvil_unified_output(d)
    if not (G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID) then return end
    local icon = G.OVERLAY_MENU:get_UIE_by_ID('bc_anvil_uni_output')
    if not (icon and icon.config and icon.config.object) then return end
    local obj = icon.config.object
    -- Resolve the result CENTER (so we can draw its full card face), not an icon. Sheet for a forge, the
    -- netherite tool for an upgrade, else the surviving/result tool's own center.
    local center
    if d and d.valid then
        if d.mechanic == 'forge' and d.sheet then
            center = G.P_CENTERS and G.P_CENTERS['c_balacraft_sheet_' .. d.sheet.id]
        elseif d.mechanic == 'upgrade' then
            local tdef = d.preview_tool and anvil_tool_def(d.preview_tool)
            center = tdef and G.P_CENTERS and G.P_CENTERS['c_balacraft_tool_' .. tdef.tool .. '_netherite']
        elseif d.preview_tool then
            center = d.preview_tool.config and d.preview_tool.config.center
        end
    end
    local atlas = center and center.atlas and G.ASSET_ATLAS[center.atlas]
    if atlas and center.pos then
        obj.atlas = atlas
        obj:set_sprite_pos(center.pos)
        if obj.bc_overlay then obj.bc_overlay[4] = 1 end
    elseif obj.bc_overlay then
        obj.bc_overlay[4] = 0
    end
end

-- Per-frame: classify the slots, drive the live-bound button label/hint + colour, snap settled slot
-- occupants, refresh the output preview. Inert unless the unified Anvil is open. Wired into
-- update_crafting_modal (crafting_ui.lua).
function PB_UTIL.update_anvil_unified()
    if not PB_UTIL.anvil_unified_cells then return end
    local d = PB_UTIL.anvil_dispatch()
    local st = PB_UTIL.anvil_unified_state
    st.valid = d.valid and true or false
    st.label = (d.label) or 'Anvil'
    st.hint  = d.warn or DEFAULT_ANVIL_HINT
    local C = G.CONTROLLER
    local dragged = C and C.dragging and C.dragging.target
    for _, slot in ipairs(PB_UTIL.anvil_unified_cells) do
        local area = slot.area
        local card = area and area.cards and area.cards[1]
        if card and card ~= dragged and not (card.states and card.states.drag.is) then
            local tx = area.T.x + (area.T.w - card.T.w) / 2
            local ty = area.T.y + (area.T.h - card.T.h) / 2
            card.T.x, card.T.y = tx, ty
            card.VT.x, card.VT.y = tx, ty
        end
    end
    PB_UTIL.refresh_anvil_unified_output(d)
end

local UNI_CELL = 0.76

-- The Anvil holds full tool/book CARDS, so its A/B/output slots are CARD-sized -- an ore tile or a small
-- preview icon just centres inside. With cell-sized slots a dropped card overflowed the slot and the two
-- A/B cards overlapped (the card is bigger than a cell). Computed at call-time so G.CARD_W/H are ready.
local function anvil_slot_dims() return (G.CARD_W or 0.95) + 0.08, (G.CARD_H or 1.27) + 0.08 end

-- A card-sized Anvil input slot embedding one CardArea (the dropped tool/book/ore centres inside it,
-- via the centring in update_anvil_unified -- which targets the area, itself centred in this square).
local function anvil_slot_node(area)
    local w, h = anvil_slot_dims()
    return { n = G.UIT.C, config = { align = 'cm', padding = 0.04, minw = w, minh = h,
        r = 0.1, colour = G.C.UI.TRANSPARENT_DARK },
        nodes = { { n = G.UIT.O, config = { object = area } } } }
end

-- A card-sized output square holding the result preview icon, retargeted each frame by
-- refresh_anvil_unified_output. Base atlas = sheets if present, else tools, so the dimmable sprite
-- exists even with sheets disabled (it's retargeted to the tool atlas for combine/upgrade/enchant).
local function anvil_unified_output_node()
    local atlas = (PB_UTIL.sheet_icon_atlas and G.ASSET_ATLAS[PB_UTIL.sheet_icon_atlas.key])
        or (PB_UTIL.tool_icon_atlas and G.ASSET_ATLAS[PB_UTIL.tool_icon_atlas.key])
    local inner
    if atlas and PB_UTIL.make_dimmable then
        -- CARD-sized so the output shows the FULL result card (retargeted to the result center's card-face
        -- atlas by refresh_anvil_unified_output), not a tiny icon. The base atlas here is just a hidden
        -- placeholder (bc_overlay[4]=0 until a valid pair); set_sprite_pos re-quads to the real atlas.
        local out_icon = PB_UTIL.make_dimmable(Sprite(0, 0, G.CARD_W or 0.95, G.CARD_H or 1.27, atlas, { x = 0, y = 0 }))
        out_icon.bc_overlay[4] = 0   -- hidden until a valid pair fills both slots
        inner = { n = G.UIT.O, config = { id = 'bc_anvil_uni_output', object = out_icon } }
    else
        inner = { n = G.UIT.T, config = { text = ' ', scale = 0.3 } }
    end
    local sw, sh = anvil_slot_dims()
    local square = {
        n = G.UIT.C, config = { align = 'cm', padding = 0.04, r = 0.1, colour = G.C.UI.TRANSPARENT_DARK,
                                minw = sw, minh = sh },
        nodes = { inner },
    }
    return { n = G.UIT.C, config = { align = 'cm' }, nodes = { square } }
end

-- The Anvil's interactive content (`[A] + [B] = [out]` + action button + a live warning), as an
-- embeddable node for the unified modal's station area. Built ONCE per open; the label/hint are
-- live-bound to anvil_unified_state and the preview is retargeted in place, so actions update without
-- rebuilding (never re-embed the slot CardAreas). The tool/book SOURCE (anvil_src_area) lives in the
-- Consumables widget (consumables_content in crafting_ui.lua) -- "everything is in the consumable area".
function PB_UTIL.anvil_station_content()
    local plus = { n = G.UIT.C, config = { align = 'cm', padding = 0.06 },
        nodes = { { n = G.UIT.T, config = { text = '+', scale = 0.6, colour = G.C.WHITE } } } }
    local eq   = { n = G.UIT.C, config = { align = 'cm', padding = 0.1 },
        nodes = { { n = G.UIT.T, config = { text = '=', scale = 0.6, colour = G.C.WHITE } } } }
    local action_btn = {
        n = G.UIT.C, config = { align = 'cm' }, nodes = { {
            n = G.UIT.R, config = { id = 'bc_anvil_uni_btn', align = 'cm', padding = 0.1, r = 0.1,
                minw = 1.8, minh = UNI_CELL, colour = G.C.UI.TRANSPARENT_LIGHT,
                button = 'bc_anvil_unified_action', func = 'bc_anvil_unified_action_btn', hover = true, shadow = true },
            nodes = { { n = G.UIT.T, config = { ref_table = PB_UTIL.anvil_unified_state, ref_value = 'label',
                scale = 0.4, colour = G.C.UI.TEXT_LIGHT } } },
        } } }
    local top = { n = G.UIT.R, config = { align = 'cm', padding = 0.06 }, nodes = {
        anvil_slot_node(PB_UTIL.anvil_in_a), plus,
        anvil_slot_node(PB_UTIL.anvil_in_b), eq,
        anvil_unified_output_node(), action_btn,
    } }
    -- Just the apparatus + a live warning line -- no how-to descriptions (DEFAULT_ANVIL_HINT = '') and
    -- no source box: the tools/books source (anvil_src_area) is hosted in the Consumables widget
    -- (consumables_content in crafting_ui.lua), so the player drags tools straight from there.
    return { n = G.UIT.C, config = { align = 'cm' }, nodes = {
        top,
        { n = G.UIT.R, config = { align = 'cm', minh = 0.36 }, nodes = {
            { n = G.UIT.T, config = { ref_table = PB_UTIL.anvil_unified_state, ref_value = 'hint',
                scale = 0.26, colour = G.C.RED } } } },
    } }
end

-- The single action button: run whatever the current slot pair resolves to (anvil_dispatch), then
-- surface survivors/outputs back into the source row and refresh in place (no overlay rebuild).
G.FUNCS.bc_anvil_unified_action = function(e)
    local d = PB_UTIL.anvil_dispatch()
    if d.valid and d.action and d.action() then
        play_sound('timpani', 0.8)
    else
        play_sound('cancel')
    end
    if PB_UTIL.refresh_anvil_source then PB_UTIL.refresh_anvil_source() end
    PB_UTIL.update_anvil_unified()
    PB_UTIL.update_inventory()     -- an ore may have hit 0 -> reflow the source grid
end

-- Per-frame colour on the action button (green only when the pair resolves to a valid output).
G.FUNCS.bc_anvil_unified_action_btn = function(e)
    e.config.colour = (PB_UTIL.anvil_unified_state and PB_UTIL.anvil_unified_state.valid)
        and G.C.GREEN or G.C.UI.TRANSPARENT_LIGHT
end

