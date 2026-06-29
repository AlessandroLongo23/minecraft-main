-- The Composter (Base station): turn otherwise-useless ORGANIC items (flowers + farm plants) into Bone
-- Meal. Crafted from 7 Wood (content/resources/recipes.lua, output.type='station'). A drag UI: drag a
-- valid organic resource from the inventory onto the input slot (id = 'bc_composter_input', hit-tested by
-- the shared drag router in crafting_grid.lua, which calls PB_UTIL.composter_add). Every COMPOST_THRESHOLD
-- items yields one Bone Meal consumable, auto-collected to a consumable slot (else the inventory).
--
-- State: G.GAME.balacraft.composter_fill -- a plain int, so it auto-saves within a run and auto-resets
-- per run (no custom save/load, per the mod's resource invariant).

PB_UTIL.COMPOST_THRESHOLD = 8   -- organics consumed per Bone Meal (MC: 8 items per compost -> 1 bone meal)

-- Farm organics are always accepted; flowers (PB_UTIL.FLOWERS, registered in registry.lua) are added
-- when present. Both are drop_class='special' resources that exist only to feed this station.
local BASE_ORGANICS = { 'sugar_cane', 'carrot', 'melon_slice', 'brown_mushroom' }

-- The accepted-input id list (de-duped, registry-known). Flowers append after the farm items.
function PB_UTIL.composter_inputs()
    local seen, out = {}, {}
    local function add(id)
        if id and not seen[id] and PB_UTIL.RESOURCE_BY_ID and PB_UTIL.RESOURCE_BY_ID[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    for _, id in ipairs(BASE_ORGANICS) do add(id) end
    for _, id in ipairs(PB_UTIL.FLOWERS or {}) do add(id) end
    return out
end

-- ── Fill state + compost logic ───────────────────────────────────────────────
local function get_fill()
    local bc = G.GAME and G.GAME.balacraft
    return (bc and bc.composter_fill) or 0
end
local function set_fill(v)
    local bc = G.GAME and G.GAME.balacraft
    if bc then bc.composter_fill = math.max(0, v) end
end
function PB_UTIL.composter_fill() return get_fill() end

-- Produce 1 Bone Meal once the bin is full (>= threshold). consumable_add routes it to a free MC
-- consumable slot, else stores it in the inventory (the per-frame reconcile) -- so has_consumable_room
-- (free MC slot OR inventory room) guards only the case where the bone meal would have NO home at all,
-- which would waste the composted organics. Returns true on success. Auto-called by composter_add.
function PB_UTIL.composter_harvest()
    if get_fill() < PB_UTIL.COMPOST_THRESHOLD then return false end
    if not (G.P_CENTERS and G.P_CENTERS['c_balacraft_bone_meal']) then return false end   -- center must exist
    if PB_UTIL.has_consumable_room and not PB_UTIL.has_consumable_room() then return false end
    consumable_add('c_balacraft_bone_meal')
    set_fill(get_fill() - PB_UTIL.COMPOST_THRESHOLD)
    return true
end

-- Drop one unit of organic `id` into the bin: spend 1 from inventory, raise the fill, and auto-collect a
-- Bone Meal if that tops the bin off (and there's room). Blocked when the bin is already full and can't
-- be emptied (no consumable room), so organics are never wasted. Returns true if an item went in.
function PB_UTIL.composter_add(id)
    if get_fill() >= PB_UTIL.COMPOST_THRESHOLD then
        if not PB_UTIL.composter_harvest() then return false end   -- full + no room -> refuse the add
    end
    if PB_UTIL.get_resource_count(id) < 1 then return false end
    PB_UTIL.add_resource(id, -1)
    set_fill(get_fill() + 1)
    if get_fill() >= PB_UTIL.COMPOST_THRESHOLD then PB_UTIL.composter_harvest() end
    return true
end

-- The Composter's interactive content: a [input slot] -> [output slot] drag UI, as an embeddable node
-- for the unified modal's station area. The shell shows the "Composter" title above and provides the
-- black container; this just centres the two slots + arrow. Drag a valid organic onto the input slot
-- (id = 'bc_composter_input', hit-tested by the drag router, which calls PB_UTIL.composter_add). The
-- output slot shows the fill gauge + a Bone Meal icon (faint until the bin is full). Re-run on each
-- successful add (the modal rebuilds), so it reads the live fill each time. Returns a single G.UIT.C.
function PB_UTIL.composter_station_content()
    local fill  = get_fill()
    local thr   = PB_UTIL.COMPOST_THRESHOLD
    local full  = fill >= thr
    local CELL  = 0.85

    -- INPUT slot: display-only drop target (holds no card). The router hit-tests its id.
    local input_slot = {
        n = G.UIT.C, config = { align = 'cm', padding = 0.03 }, nodes = {
            { n = G.UIT.R, config = { align = 'cm', id = 'bc_composter_input', minw = CELL, minh = CELL,
                r = 0.05, colour = G.C.UI.TRANSPARENT_DARK }, nodes = {} },
            { n = G.UIT.R, config = { align = 'cm', minh = 0.3 }, nodes = {
                { n = G.UIT.T, config = { text = 'Drop', scale = 0.26, colour = G.C.UI.TEXT_INACTIVE } } } },
        },
    }

    local arrow = { n = G.UIT.C, config = { align = 'cm', padding = 0.1 }, nodes = {
        { n = G.UIT.T, config = { text = '>', scale = 0.6, colour = G.C.WHITE } } } }

    -- OUTPUT slot: the authentic Bone Meal ICON (the small bc_tool_icons cell -- NOT the card face) +
    -- a short "x/8" gauge so the slot stays a true square (a long label would stretch it). There's no
    -- Sprite:set_alpha in this engine; PB_UTIL.make_dimmable + bc_overlay[4] is the codebase pattern.
    local bm_atlas = PB_UTIL.tool_icon_atlas and G.ASSET_ATLAS[PB_UTIL.tool_icon_atlas.key]
    local bm_pos   = PB_UTIL.tool_icon_pos and PB_UTIL.tool_icon_pos['c_balacraft_bone_meal']
    local bm_spr   = (bm_atlas and bm_pos) and Sprite(0, 0, 0.6, 0.6, bm_atlas, bm_pos) or nil
    if bm_spr and PB_UTIL.make_dimmable then
        PB_UTIL.make_dimmable(bm_spr)
        bm_spr.bc_overlay[4] = full and 1 or 0.35
    end
    local icon_node = bm_spr
        and { n = G.UIT.O, config = { object = bm_spr } }
        or  { n = G.UIT.T, config = { text = ' ', scale = 0.3 } }

    local output_slot = {
        n = G.UIT.C, config = { align = 'cm', padding = 0.03 }, nodes = {
            { n = G.UIT.R, config = { align = 'cm', minw = CELL, minh = CELL, r = 0.05,
                colour = G.C.UI.TRANSPARENT_DARK, padding = 0.04 },
              nodes = { { n = G.UIT.R, config = { align = 'cm' }, nodes = { icon_node } } } },
            { n = G.UIT.R, config = { align = 'cm', minh = 0.3 }, nodes = {
                { n = G.UIT.T, config = { text = fill .. '/' .. thr,
                    scale = 0.3, colour = full and G.C.GREEN or G.C.ORANGE } } } },
        },
    }

    return {
        n = G.UIT.C, config = { align = 'cm' }, nodes = {
            { n = G.UIT.R, config = { align = 'cm' }, nodes = { input_slot, arrow, output_slot } },
        },
    }
end

-- ── Button callbacks ─────────────────────────────────────────────────────────
-- The drag router calls PB_UTIL.composter_add directly and flags a deferred modal rebuild, so the old
-- bc_composter_add / bc_composter_harvest G.FUNCS button callbacks are gone (nothing references them).
