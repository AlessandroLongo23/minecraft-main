-- Interactive 3x3 crafting grid + draggable inventory sources. Owns live state while
-- the modal is open: nine single-slot grid CardAreas (PB_UTIL.craft_cells) plus one
-- CardArea per visible resource for the inventory row (PB_UTIL.inv_cells).
-- Tile lifecycle: only spawn_tile debits (-1) and return_tile/destroy-credit/clear(true)
-- credit (+1). Source cards in inv_cells are NEVER reserved and NEVER touched by
-- add_resource -- they only trigger a spawn_tile in the drop hook when landing on a cell.
-- The overlay is built ONCE and never rebuilt while open.

PB_UTIL.craft_cells = PB_UTIL.craft_cells or nil   -- 3x3 row-major of CardArea, or nil
PB_UTIL.inv_cells   = PB_UTIL.inv_cells   or nil   -- flat list of {area, rid, label_ref}
-- Furnace input/fuel drop slots (Minecraft-furnace layout), live only while the Furnace is open:
-- a flat list of { area=CardArea, kind='input'|'fuel', accepts=function(rid)->bool }. Drag routing
-- (L_cursor_release / right-click) treats these as a second, mutually-exclusive set of drop targets
-- (craft_cells is nil when the furnace is open and vice-versa). See utilities/furnace.lua.
PB_UTIL.furnace_cells = PB_UTIL.furnace_cells or nil
-- Brewing Stand drop slots (fuel + ingredient), live only while the Brewing Stand is open: a flat
-- list of { area=CardArea, kind='fuel'|'ingredient', accepts=function(rid)->bool }. A third,
-- mutually-exclusive set (like furnace_cells). The bottle slot is NOT here -- it holds no card; it is
-- a display-only UI node (id 'bc_brew_bottle_slot') hit-tested in the drag router. See brewing_ui.lua.
PB_UTIL.brew_cells = PB_UTIL.brew_cells or nil
-- Unified Anvil drop slots, live only while the Anvil is open: a flat list of { area=CardArea, kind }.
-- UNLIKE the others these accept BOTH resource tiles AND tool/book CARDS -- the mechanic is inferred
-- from the pair (PB_UTIL.anvil_dispatch). Kept DISTINCT from furnace_cells so the Forge/Furnace
-- branches are untouched. anvil_src_area is a transient 'joker' area holding the player's tools/books
-- (equipped + inventory-stored) as draggable cards for the overlay's lifetime. See utilities/furnace.lua.
PB_UTIL.anvil_unified_cells = PB_UTIL.anvil_unified_cells or nil
PB_UTIL.anvil_src_area      = PB_UTIL.anvil_src_area or nil
PB_UTIL.anvil_on_change     = PB_UTIL.anvil_on_change or nil

-- Tunable size constants (Minecraft-slot aesthetic, small squares).
local CELL_W = 0.7   -- grid cell width  (world-units) -- tune in-game
local CELL_H = 0.7   -- grid cell height (world-units) -- tune in-game

-- Inventory cell FOOTPRINT width (horizontal-only). The slot square itself stays CELL_W; this just
-- pads each of the INV_COLS columns out so the row spans the inventory box, instead of the small squares
-- huddling in the centre with a big empty band to the right (which read as a "gap" before the right-hand
-- Workbench/Consumables column). The box is HARD-pinned now (crafting_ui.lua titled_panel) and overflow
-- CLIPS, so this must stay UNDER the box interior: 9*INV_SLOT_W + 10*0.02 (inter-cell) + ~0.08 (grid pad)
-- must be < WL-0.2. For WL=10.4 (interior 10.2): 9*1.07 + 0.2 + 0.08 = 9.91 < 10.2 (fills with ~0.3 to
-- spare). minh is left unset so rows DON'T grow taller. Re-tune (smaller) if you ever shrink WL.
local INV_SLOT_W = 1.07  -- fills WL=10.4's interior with a safe margin; raise toward ~1.10 to fill more

-- Inventory is a generic grid: INV_COLS wide, paged INV_ROWS rows at a time. populate_inventory fills
-- the CURRENT PAGE's cells with the items the player owns (resource kinds count > 0 in registry order,
-- then stored consumables) and leaves the rest blank; it reflows when the owned set OR the page changes.
-- Slots are draggable sources into the craft grid. The grid holds exactly ONE PAGE of cells (PER_PAGE)
-- and the full inventory pages through them, so off-page item cards never exist (no corner artifacts).
-- Capacity (utilities/inventory_model.lua) is shown in the header label, separate from the page size.
local INV_COLS  = 9
local INV_ROWS  = 3                       -- rows shown per page (the rest are paged)
local PER_PAGE  = INV_COLS * INV_ROWS     -- 27 cells per page
local function inv_slot_count() return PER_PAGE end

PB_UTIL.inv_page = PB_UTIL.inv_page or 1

-- The two ordered item groups the inventory pages through: owned resource KINDS (count > 0, registry
-- order) first, then the stored-consumable list. Both derived from G.GAME the SAME way everywhere.
local function inv_owned_resources()
    local store = (G.GAME.balacraft and G.GAME.balacraft.resources) or {}
    local owned = {}
    for _, r in ipairs(PB_UTIL.RESOURCES) do
        if (store[r.id] or 0) > 0 then owned[#owned + 1] = r.id end
    end
    return owned
end
local function inv_stored_list()
    return (G.GAME.balacraft and G.GAME.balacraft.inv and G.GAME.balacraft.inv.stored) or {}
end

-- Total item cells (owned resource kinds + stored consumables) and the page count over them (>= 1).
local function inv_item_count() return #inv_owned_resources() + #inv_stored_list() end
function PB_UTIL.inv_page_count()
    return math.max(1, math.ceil(inv_item_count() / PER_PAGE))
end
-- Clamp + store the current page (the item count may have shrunk since the last build), then the
-- 0-based global item offset of this page's first cell.
local function inv_page_now()
    local p = math.max(1, math.min(PB_UTIL.inv_page_count(), PB_UTIL.inv_page or 1))
    PB_UTIL.inv_page = p
    return p
end
local function inv_page_offset() return (inv_page_now() - 1) * PER_PAGE end

-- Publish, for the CURRENT page, which of the PER_PAGE cells are stored-consumable cells:
-- _inv_consumable_set[k] = stored-list index (k = page-local cell 1..PER_PAGE). populate keeps those
-- CardAreas empty (the node paints their icon); resource cells get a source; the rest are blank.
function PB_UTIL.refresh_inv_consumable_set()
    local set = {}
    local R, C = #inv_owned_resources(), #inv_stored_list()
    local offset = inv_page_offset()
    for k = 1, PER_PAGE do
        local g = offset + k
        if g > R and g <= R + C then set[k] = g - R end   -- this cell shows stored[g - R]
    end
    PB_UTIL._inv_consumable_set = set
    return set
end

-- ---- Grid cell construction ----

-- Create the nine single-slot cell-areas (idempotent: destroys any prior set first).
-- type='title_2' is chosen deliberately: it is one of the types CardArea:draw actually PAINTS
-- (cardarea.lua:367) -- a non-drawn/custom type leaves the tiles invisible -- while still
-- (a) keeping drag enabled (set_ranks else-branch, cardarea.lua:255) and (b) being a no-op in
-- align_cards (no 'title_2' branch, cardarea.lua:446+) so WE snap tiles to cell-centre
-- ourselves. It's also an invisible_area_type (cardarea.lua:311) so the area draws no
-- background box of its own -- our modal slot squares already provide that.
function PB_UTIL.build_craft_cells()
    PB_UTIL.destroy_craft_cells()  -- safe no-op if nothing to destroy
    local cells = {}
    for i = 1, 3 do
        cells[i] = {}
        for j = 1, 3 do
            local area = CardArea(
                G.ROOM.T.x, G.ROOM.T.y,          -- X,Y throwaway; the G.UIT.O node repositions it
                CELL_W, CELL_H,
                -- no_card_count: suppress CardArea's built-in 'N/M' label (cardarea.lua:319),
                -- i.e. the '0/1' under each empty cell and the '1/1' over each inventory slot.
                { card_limit = 1, type = 'title_2', highlight_limit = 0, card_w = CELL_W,
                  no_card_count = true }
            )
            cells[i][j] = area
        end
    end
    PB_UTIL.craft_cells = cells
    return cells
end

-- One grid cell as an overlay node embedding the CardArea (the booster-pack pattern).
-- Small square with a dark inset, tight rounding -- Minecraft slot aesthetic.
local function cell_object_node(area)
    return {
        n = G.UIT.C,
        config = { align = 'cm', padding = 0.03, minw = CELL_W + 0.06, minh = CELL_H + 0.06,
                   r = 0.05, colour = G.C.UI.TRANSPARENT_DARK },
        nodes = { { n = G.UIT.O, config = { object = area } } },
    }
end

-- Build the 3x3 grid node tree (call AFTER build_craft_cells). Returns a G.UIT.C.
function PB_UTIL.build_grid_node()
    local rows = {}
    for i = 1, 3 do
        local row = { n = G.UIT.R, config = { align = 'cm', padding = 0.02 }, nodes = {} }
        for j = 1, 3 do
            row.nodes[#row.nodes + 1] = cell_object_node(PB_UTIL.craft_cells[i][j])
        end
        rows[#rows + 1] = row
    end
    return { n = G.UIT.C, config = { align = 'cm', padding = 0.04, r = 0.08, colour = G.C.BLACK }, nodes = rows }
end

-- ---- Inventory (draggable source) construction ----

-- Build the fixed INV_SLOTS (8x3) generic inventory CardAreas. NONE is pre-assigned a
-- resource: each is an empty single-slot area. populate_inventory then fills the leading
-- slots with the items the player owns. Called from open_crafting_table (after
-- build_craft_cells) so all areas live for the modal's lifetime.
function PB_UTIL.build_inventory()
    -- Tear down any stale inventory first (safety; normally nil here).
    if PB_UTIL.inv_cells then
        for _, entry in ipairs(PB_UTIL.inv_cells) do
            if entry.area then entry.area:remove() end
        end
        PB_UTIL.inv_cells = nil
    end

    local cells = {}
    for _ = 1, inv_slot_count() do
        local area = CardArea(
            G.ROOM.T.x, G.ROOM.T.y,
            CELL_W, CELL_H,
            -- no_card_count: suppress CardArea's built-in 'N/M' label (cardarea.lua:319).
            { card_limit = 1, type = 'title_2', highlight_limit = 0, card_w = CELL_W,
              no_card_count = true }
        )
        -- rid = resource currently in this slot (nil = empty); label '' renders blank.
        cells[#cells + 1] = { area = area, rid = nil, label_ref = { count = '' } }
    end
    PB_UTIL.inv_cells = cells
    PB_UTIL._inv_signature = nil   -- force the first populate
    PB_UTIL.refresh_inv_consumable_set()   -- match the node's split BEFORE the first populate
    PB_UTIL.populate_inventory()
end

-- Owned-item signature in registry order (e.g. 'wood,coal,sticks|c_balacraft_potion_healing').
-- Cheap; compared each frame to decide whether the inventory needs reflowing. Includes the STORED
-- Minecraft-consumable centers (after the '|') so the grid also reflows when a stored item appears
-- or is equipped/removed (they share the unified grid -- see build_inventory_node).
function PB_UTIL.inventory_owned_signature()
    local store = (G.GAME.balacraft and G.GAME.balacraft.resources) or {}
    local owned = {}
    for _, r in ipairs(PB_UTIL.RESOURCES) do
        if (store[r.id] or 0) > 0 then owned[#owned + 1] = r.id end
    end
    local stored = (G.GAME.balacraft and G.GAME.balacraft.inv and G.GAME.balacraft.inv.stored) or {}
    local sc = {}
    for _, s in ipairs(stored) do
        sc[#sc + 1] = (s.save_fields and s.save_fields.center) or '?'
    end
    return table.concat(owned, ',') .. '|' .. table.concat(sc, ',')
end

-- Whether a resource source is draggable at the ACTIVE station. Default = yes (all stations accept
-- ore tiles). The Composter accepts ONLY its valid organics; everything else there is immovable +
-- dimmed (populate_inventory applies this). Cheap (composter_inputs is a short list).
function PB_UTIL.inv_drag_allowed(rid)
    if PB_UTIL.active_station == 'composter' then
        if not PB_UTIL.composter_inputs then return false end
        for _, id in ipairs(PB_UTIL.composter_inputs()) do
            if id == rid then return true end
        end
        return false
    end
    return true
end

-- Assign owned items (count > 0, registry order, ALL kinds incl. crafted) to the resource
-- slots; clear the rest. Mutates the fixed areas in place (no overlay rebuild): swaps a
-- slot's source card only when its assigned resource changes. Idempotent.
--
-- The grid is UNIFIED: some cells are reserved for STORED Minecraft consumables (build_inventory_node
-- publishes their indices in PB_UTIL._inv_consumable_set). Those cells are drawn as item icons by the
-- node (not as a CardArea source), so here we keep their CardArea empty and feed resource sources only
-- into the remaining cells. Resource sources are assigned in order across the non-consumable cells, so
-- a freshly-produced resource (count 0 -> >0 between rebuilds) lands in a real drawn cell instead of
-- vanishing under a consumable icon.
function PB_UTIL.populate_inventory()
    if not PB_UTIL.inv_cells then return end
    local store  = (G.GAME.balacraft and G.GAME.balacraft.resources) or {}
    local owned  = inv_owned_resources()
    local R      = #owned
    local offset = inv_page_offset()
    PB_UTIL.refresh_inv_consumable_set()
    local cset = PB_UTIL._inv_consumable_set or {}
    for k, entry in ipairs(PB_UTIL.inv_cells) do
        local g = offset + k   -- this cell's global item index on the current page
        if (not cset[k]) and g <= R then
            -- Resource cell: emplace/keep the draggable source for the owned kind at this index.
            local rid = owned[g]
            if entry.rid ~= rid then
                if entry.area.cards[1] then entry.area.cards[1]:remove() end
                local src = PB_UTIL.make_resource_source(rid, 0, 0)
                if src then
                    src.states.drag.is = false
                    entry.area:emplace(src)
                    src.T.x = entry.area.T.x + (entry.area.T.w - src.T.w) / 2
                    src.T.y = entry.area.T.y + (entry.area.T.h - src.T.h) / 2
                    src.area = entry.area   -- backref for snap_source_home
                end
                entry.rid = rid
            end
            entry.label_ref.count = 'x' .. (store[rid] or 0)
            -- Per-station drag gating: at the Composter only valid organics are draggable; the rest are
            -- dimmed (40%) and immovable. Other stations: every source full-opacity + draggable.
            local card = entry.area.cards[1]
            if card then
                local allowed = PB_UTIL.inv_drag_allowed == nil or PB_UTIL.inv_drag_allowed(rid)
                card.states.drag.can = allowed
                if card.children and card.children.center and card.children.center.bc_overlay then
                    card.children.center.bc_overlay[4] = allowed and 1 or 0.4
                end
            end
        else
            -- Consumable cell (the node paints its icon) OR blank: keep this CardArea empty.
            if entry.area.cards[1] then entry.area.cards[1]:remove() end
            entry.rid = nil
            entry.label_ref.count = ''
        end
    end
    PB_UTIL._inv_signature = PB_UTIL.inventory_owned_signature() .. '#' .. (PB_UTIL.inv_page or 1)
end

-- "[<] Page p/N [>]" inventory pager (only shown when there's more than one page).
local function inv_page_btn(label, fn, enabled)
    return { n = G.UIT.C, config = {
        align = 'cm', padding = 0.06, r = 0.08, minw = 0.55, minh = 0.45,
        colour = enabled and G.C.BLUE or G.C.UI.TRANSPARENT_DARK,
        button = enabled and fn or nil, hover = enabled, shadow = true },
        nodes = { { n = G.UIT.T, config = { text = label, scale = 0.45, colour = G.C.UI.TEXT_LIGHT } } } }
end
local function inv_page_nav(page, pages)
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
        inv_page_btn('<', 'bc_inv_prev', page > 1),
        { n = G.UIT.C, config = { align = 'cm', padding = 0.06, minw = 1.3 }, nodes = {
            { n = G.UIT.T, config = { text = 'Page ' .. page .. '/' .. pages, scale = 0.3, colour = G.C.UI.TEXT_LIGHT } } } },
        inv_page_btn('>', 'bc_inv_next', page < pages),
    } }
end

-- Build the unified inventory node tree for the CURRENT PAGE (INV_ROWS rows of INV_COLS slots), plus a
-- page-nav row when there's more than one page. Cells, in global item order paged across pages:
--   * owned RESOURCE stacks (a CardArea source + 'xN' count below),
--   * then STORED Minecraft CONSUMABLES (an item icon + a clickable square that EQUIPS it),
--   * then blanks.
-- refresh_inv_consumable_set publishes which page-local cells are consumable cells (keyed by their
-- stored-list index) so populate_inventory never drops a resource source onto one.
function PB_UTIL.build_inventory_node()
    if not PB_UTIL.inv_cells then return { n = G.UIT.R, config = { align = 'cm' }, nodes = {} } end

    local stored = inv_stored_list()
    PB_UTIL.refresh_inv_consumable_set()
    local cset = PB_UTIL._inv_consumable_set or {}   -- page-local cell k -> stored-list index
    local editable = PB_UTIL.inv_editable and PB_UTIL.inv_editable() or false

    -- A resource slot: the live CardArea source + its 'xN' count label.
    local function resource_slot_node(entry)
        return {
            n = G.UIT.C, config = { align = 'cm', padding = 0.03, minw = INV_SLOT_W },
            nodes = {
                { n = G.UIT.R, config = { align = 'cm', padding = 0.02,
                    minw = CELL_W + 0.06, minh = CELL_H + 0.06,
                    r = 0.05, colour = G.C.UI.TRANSPARENT_DARK },
                  nodes = { { n = G.UIT.O, config = { object = entry.area } } } },
                { n = G.UIT.R, config = { align = 'cm', minh = 0.32 }, nodes = {
                    { n = G.UIT.T, config = {
                        ref_table = entry.label_ref, ref_value = 'count',
                        scale = 0.28, colour = G.C.WHITE } },
                } },
            },
        }
    end

    -- A stored-consumable slot: the item's icon + a clickable square that equips it (bc_inv_equip).
    -- Editable only outside a blind (matches the equip/un-equip rules); otherwise it's view-only.
    local function consumable_slot_node(saved, stored_index)
        local center = saved and saved.save_fields and G.P_CENTERS[saved.save_fields.center]
        local spr = center and PB_UTIL.consumable_inv_icon and PB_UTIL.consumable_inv_icon(center, 0.5)
        return {
            n = G.UIT.C, config = { align = 'cm', padding = 0.03, minw = INV_SLOT_W },
            nodes = {
                { n = G.UIT.R, config = { align = 'cm', padding = 0.02,
                    minw = CELL_W + 0.06, minh = CELL_H + 0.06,
                    r = 0.05, colour = G.C.UI.TRANSPARENT_DARK,
                    button = editable and 'bc_inv_equip' or nil,
                    ref_table = { index = stored_index },
                    hover = editable, shadow = true },
                  nodes = spr and { { n = G.UIT.O, config = { object = spr } } } or {} },
                { n = G.UIT.R, config = { align = 'cm', minh = 0.32 }, nodes = {
                    { n = G.UIT.T, config = { text = editable and 'equip' or 'stored',
                        scale = 0.24, colour = G.C.UI.TEXT_LIGHT } },
                } },
            },
        }
    end

    local rows = {}
    for i = 1, PER_PAGE, INV_COLS do
        local row = { n = G.UIT.R, config = { align = 'cm', padding = 0.02 }, nodes = {} }
        for k = i, math.min(i + INV_COLS - 1, PER_PAGE) do
            if cset[k] then
                row.nodes[#row.nodes + 1] = consumable_slot_node(stored[cset[k]], cset[k])
            else
                row.nodes[#row.nodes + 1] = resource_slot_node(PB_UTIL.inv_cells[k])
            end
        end
        rows[#rows + 1] = row
    end
    return { n = G.UIT.C, config = { align = 'cm', padding = 0.04, id = 'bc_inventory_grid' }, nodes = rows }
end

-- The inventory's "[<] Page p/N [>]" nav row, or nil when it all fits on one page. Placed by
-- build_base_shell directly below the grid (inside the inventory panel).
function PB_UTIL.build_inv_page_nav()
    local pages = PB_UTIL.inv_page_count()
    if pages <= 1 then return nil end
    return inv_page_nav(inv_page_now(), pages)
end

-- Per-frame inventory maintenance (driven from update_crafting_modal). Reflows when the owned
-- set changes (skipped mid source-drag so the dragged card isn't yanked), keeps the live count
-- labels current, and snaps each source to its laid-out slot centre. The snap is needed because
-- sources are emplaced before overlay layout and 'title_2' align is a no-op (cardarea.lua:446);
-- the area is Strong-bonded to its UIT.O node and tracks it each frame (ui.lua:410-411, 523-531),
-- so once layout settles we drop each icon into its slot. VT is hard-set so a stationary card
-- never interpolates in from the throwaway origin (corner flash). Skips the active drag target.
function PB_UTIL.update_inventory()
    if not PB_UTIL.inv_cells then return end
    local C = G.CONTROLLER
    local dragged = C and C.dragging and C.dragging.target
    local dragging_source = dragged and dragged.bc_source

    if not dragging_source and
       (PB_UTIL.inventory_owned_signature() .. '#' .. (PB_UTIL.inv_page or 1)) ~= PB_UTIL._inv_signature then
        PB_UTIL.populate_inventory()
    end

    local store = (G.GAME.balacraft and G.GAME.balacraft.resources) or {}
    for _, entry in ipairs(PB_UTIL.inv_cells) do
        if entry.rid then entry.label_ref.count = 'x' .. (store[entry.rid] or 0) end
        local area = entry.area
        local card = area and area.cards and area.cards[1]
        if card and card ~= dragged and not (card.states and card.states.drag.is) then
            local tx = area.T.x + (area.T.w - card.T.w) / 2
            local ty = area.T.y + (area.T.h - card.T.h) / 2
            card.T.x, card.T.y = tx, ty
            card.VT.x, card.VT.y = tx, ty
        end
    end
end

-- Flip the inventory page by `delta`, clamped to [1, pages]. Re-opens the modal at the new page (the
-- standard rebuild path: builds fresh inventory cells for the page -- see rebuild_inv_overlay; reusing
-- the live cells would crash, since refresh_overlay destroys embedded CardAreas). inv_page is read by
-- build_inventory -> populate_inventory, so the new page's items appear.
function PB_UTIL.change_inv_page(delta)
    local pages = PB_UTIL.inv_page_count()
    local p = math.max(1, math.min(pages, (PB_UTIL.inv_page or 1) + delta))
    if p == (PB_UTIL.inv_page or 1) then return end
    PB_UTIL.inv_page = p
    play_sound('cardSlide1')
    if PB_UTIL.rebuild_inv_overlay then PB_UTIL.rebuild_inv_overlay() end
end
G.FUNCS.bc_inv_prev = function(e) PB_UTIL.change_inv_page(-1) end
G.FUNCS.bc_inv_next = function(e) PB_UTIL.change_inv_page(1) end

-- ---- Tile lifecycle (always go through these so reserve accounting is exact) ----

-- Return a tile to the player: credit +1, destroy. card:remove() self-detaches from its
-- area (card.lua:5244) and nulls G.CONTROLLER.dragging.target if this card IS the drag
-- target (node.lua:355), but it does NOT null dragging.prev_target -- callers returning a
-- MID-DRAG tile must null C.dragging.prev_target themselves (see destroy_craft_cells and
-- the L_cursor_release wrap; that prev_target null is MANDATORY, not redundant).
-- (No explicit remove_card needed before card:remove.)
local function return_tile(card)
    if not card then return end
    local rid = PB_UTIL.tile_resource(card)
    if rid then PB_UTIL.add_resource(rid, 1) end
    card:remove()
end

-- Spawn a fresh single tile for `rid`: debit -1, build the Card. nil (no debit) if
-- the resource is unavailable or the center is missing.
local function spawn_tile(rid)
    if PB_UTIL.get_resource_count(rid) < 1 then return nil end
    local card = PB_UTIL.make_resource_tile(rid, 0, 0)
    if not card then return nil end
    PB_UTIL.add_resource(rid, -1)   -- reserve
    return card
end

-- Place `card` into a single-slot CardArea. If occupied, the prior occupant is RETURNED
-- (credit) and replaced (swap). Snap to cell-center (custom type => align_cards no-ops).
-- Slot-agnostic core shared by the crafting grid AND the furnace input/fuel slots.
local function place_in_area(card, area)
    if not area then return false end
    if area.cards[1] and area.cards[1] ~= card then
        return_tile(area.cards[1])   -- evict + credit prior occupant
    end
    if card.area then card.area:remove_card(card) end
    card.states.drag.is = false
    area:emplace(card)               -- custom type => set_ranks keeps drag.can = true
    card.T.x = area.T.x + (area.T.w - card.T.w) / 2   -- manual snap (no align for custom type)
    card.T.y = area.T.y + (area.T.h - card.T.h) / 2
    return true
end
PB_UTIL.place_in_area = place_in_area

-- Place `card` into the 3x3 crafting cell (i,j). Thin wrapper over place_in_area.
local function place_in_cell(card, i, j)
    local area = PB_UTIL.craft_cells and PB_UTIL.craft_cells[i] and PB_UTIL.craft_cells[i][j]
    return place_in_area(card, area)
end

-- Public: spawn a fresh RESERVED tile for `rid` (debit -1), or nil if unavailable. The Furnace
-- uses this to auto-refill its input/fuel slots after a smelt (same reserve accounting as a drag).
PB_UTIL.spawn_reserved_tile = spawn_tile

-- Snap a source card back to its home inventory CardArea (no count change).
local function snap_source_home(card)
    local a = card.area
    if a then
        card.T.x = a.T.x + (a.T.w - card.T.w) / 2
        card.T.y = a.T.y + (a.T.h - card.T.h) / 2
    end
    card.states.drag.is = false
end

-- ---- Unified Anvil slot helpers (accept reserved resource tiles OR unique tool/book cards) ----

-- Place `card` (a reserved resource tile OR a unique tool/book card) into a unified Anvil slot.
-- Eviction is occupant-aware: a reserved TILE is credited (return_tile); a unique CARD is sent back
-- to the source row (anvil_src_area) -- a player-owned card is NEVER destroyed here. Snap to centre.
function PB_UTIL.anvil_place_into_slot(card, area)
    if not area then return false end
    local occ = area.cards[1]
    if occ and occ ~= card then
        if PB_UTIL.tile_resource(occ) then
            return_tile(occ)                       -- reserved tile: credit + destroy
        elseif PB_UTIL.anvil_src_area then
            occ.states.drag.is = false
            if occ.area then occ.area:remove_card(occ) end
            PB_UTIL.anvil_src_area:emplace(occ)    -- unique card: back to the source row
        end
    end
    if card.area then card.area:remove_card(card) end
    card.states.drag.is = false
    area:emplace(card)
    card.T.x = area.T.x + (area.T.w - card.T.w) / 2
    card.T.y = area.T.y + (area.T.h - card.T.h) / 2
    return true
end

-- Snap a tile/card back to wherever it currently lives (its slot or the source area) -- used when it
-- is dropped outside any slot or onto its own slot. Never silently moves a card to inventory.
function PB_UTIL.anvil_snap_card_home(card)
    card.states.drag.is = false
    local a = card.area
    if a then
        card.T.x = a.T.x + (a.T.w - card.T.w) / 2
        card.T.y = a.T.y + (a.T.h - card.T.h) / 2
    end
end

-- Public: spawn a tile for `rid` and place it in the first empty cell.
-- (Used by bc_autofill; NOT used by inventory drag path.)
function PB_UTIL.spawn_tile_to_cell(rid)
    if not PB_UTIL.craft_cells then return false end
    local card = spawn_tile(rid)
    if not card then return false end
    for i = 1, 3 do
        for j = 1, 3 do
            if not PB_UTIL.craft_cells[i][j].cards[1] then
                place_in_cell(card, i, j)
                return true
            end
        end
    end
    return_tile(card)   -- no empty cell: undo the reservation
    return false
end

-- crafting_ui sets this to its in-place refresh so grid changes update output+button.
PB_UTIL.craft_on_change = PB_UTIL.craft_on_change or nil
local function on_change()
    if PB_UTIL.craft_on_change then PB_UTIL.craft_on_change() end
    -- Immediate inventory refresh after a deposit/withdraw: reflows (an item may have hit 0)
    -- and updates live counts. Per-frame update_inventory would catch it next tick anyway;
    -- this just makes the feedback instant.
    PB_UTIL.update_inventory()
end

-- ---- Custom cursor-up drop routing (wraps Controller:L_cursor_release) ----
-- RATIONALE: L_cursor_release does NOT clear self.dragging.target (controller.lua:1129-
-- 1146 only records cursor_up). The drag is torn down on the NEXT Controller:update tick
-- (controller.lua:331-337). love.mousereleased calls L_cursor_release synchronously
-- (main.lua:1130) BEFORE that update, so dragging.target is still valid here. We emplace
-- synchronously => we WIN. We then null dragging.target -- the load-bearing line: the
-- next update does prev_target = dragging.target (controller.lua:315) before released_on
-- reads prev_target (controller.lua:348), so nil propagates and native released_on cannot
-- re-touch the emplaced tile. (prev_target=nil here is redundant belt-and-suspenders.)
-- Installed once; inert unless craft_cells is live.
if not PB_UTIL._craft_release_hooked then
    PB_UTIL._craft_release_hooked = true
    local _orig_lrelease = Controller.L_cursor_release
    function Controller:L_cursor_release(x, y)
        local dropped = self.dragging.target   -- still valid at release time
        -- Unified Anvil slots. Accept BOTH resource tiles (ore/netherite) AND tool/book CARDS -- the
        -- only branch that routes non-tile cards. Mutually exclusive with the other cell sets (its own
        -- overlay). A SOURCE ore deposits a fresh reserved tile; a placed tile OR a unique card moves
        -- between slots via the occupant-aware anvil_place_into_slot; anything dropped outside snaps home.
        if PB_UTIL.anvil_unified_cells and dropped and dropped.is and dropped:is(Card) then
            local target
            for _, slot in ipairs(PB_UTIL.anvil_unified_cells) do
                if slot.area:collides_with_point(G.CURSOR.T) then target = slot; break end
            end
            local rid = PB_UTIL.tile_resource(dropped)
            if rid and dropped.bc_source then
                if target and PB_UTIL.get_resource_count(rid) >= 1 then
                    local tile = spawn_tile(rid)   -- the ONLY -1 debit
                    if tile then PB_UTIL.anvil_place_into_slot(tile, target.area); play_sound('cardSlide1') end
                end
                snap_source_home(dropped)
            elseif target and target.area.cards[1] ~= dropped then
                PB_UTIL.anvil_place_into_slot(dropped, target.area)   -- placed tile or card -> this slot
                play_sound('cardSlide1')
            else
                PB_UTIL.anvil_snap_card_home(dropped)                 -- own slot / outside: snap back
            end
            self.dragging.target = nil
            self.dragging.prev_target = nil
            if PB_UTIL.anvil_on_change then PB_UTIL.anvil_on_change() end
            return _orig_lrelease(self, x, y)
        end
        -- Composter input slot (display-only node id 'bc_composter_input'). Drop a valid organic SOURCE
        -- to compost it: composter_add consumes 1 + advances the bin (-> Bone Meal at the threshold). No
        -- tile is placed (like the brew bottle). Invalid organics are immovable (inv_drag_allowed) so
        -- only valid ones reach here; gate defensively. The source snaps home; a successful add flags a
        -- DEFERRED rebuild (update_crafting_modal) -- never rebuild the overlay inside cursor-release.
        if PB_UTIL.active_station == 'composter' and dropped and dropped.is and dropped:is(Card)
           and dropped.bc_source and PB_UTIL.tile_resource(dropped) then
            local rid = PB_UTIL.tile_resource(dropped)
            local bn = G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID
                       and G.OVERLAY_MENU:get_UIE_by_ID('bc_composter_input')
            if bn and bn:collides_with_point(G.CURSOR.T)
               and PB_UTIL.inv_drag_allowed(rid) and PB_UTIL.composter_add then
                if PB_UTIL.composter_add(rid) then play_sound('timpani', 1.0); PB_UTIL._composter_dirty = true
                else play_sound('cancel') end
            end
            snap_source_home(dropped)
            self.dragging.target = nil
            self.dragging.prev_target = nil
            return _orig_lrelease(self, x, y)
        end
        -- Furnace drop slots (input/fuel). Mutually exclusive with craft_cells (different overlay),
        -- so this is a self-contained parallel branch that leaves the crafting path untouched. Same
        -- reserve accounting as the grid: a SOURCE deposits a fresh reserved tile into the slot under
        -- the cursor (if that slot ACCEPTS the resource); a PLACED slot-tile either moves to another
        -- accepting slot or snaps back home (use right-click to pull a tile out -- below).
        if PB_UTIL.furnace_cells and dropped and dropped.is and dropped:is(Card)
           and PB_UTIL.tile_resource(dropped) then
            local rid = PB_UTIL.tile_resource(dropped)
            local target
            for _, slot in ipairs(PB_UTIL.furnace_cells) do
                if slot.area:collides_with_point(G.CURSOR.T) then target = slot; break end
            end
            if dropped.bc_source then
                if target and (not target.accepts or target.accepts(rid)) and PB_UTIL.get_resource_count(rid) >= 1 then
                    local tile = spawn_tile(rid)   -- the ONLY -1 debit
                    if tile then place_in_area(tile, target.area); play_sound('cardSlide1') end
                end
                snap_source_home(dropped)
                self.dragging.target = nil
                self.dragging.prev_target = nil
                if PB_UTIL.furnace_on_change then PB_UTIL.furnace_on_change() end
                return _orig_lrelease(self, x, y)
            else
                if target and target.area.cards[1] ~= dropped and (not target.accepts or target.accepts(rid)) then
                    place_in_area(dropped, target.area)   -- move into the other accepting slot
                    play_sound('cardSlide1')
                else
                    -- own slot, a rejecting slot, or outside: snap the tile back to its slot (no change).
                    -- (Right-click pulls a tile out and credits it; drag never silently discards here.)
                    local a = dropped.area
                    if a then
                        dropped.states.drag.is = false
                        dropped.T.x = a.T.x + (a.T.w - dropped.T.w) / 2
                        dropped.T.y = a.T.y + (a.T.h - dropped.T.h) / 2
                    end
                end
                self.dragging.target = nil
                self.dragging.prev_target = nil
                if PB_UTIL.furnace_on_change then PB_UTIL.furnace_on_change() end
                return _orig_lrelease(self, x, y)
            end
        end
        -- Brewing Stand drop slots (fuel + ingredient) + the display-only bottle slot. Mutually
        -- exclusive with furnace_cells/craft_cells. A SOURCE dropped on the bottle slot MUTATES the
        -- persistent bottle state (consumes 1 Water Bottle / Awkward Potion) instead of placing a
        -- tile; the fuel/ingredient slots behave exactly like the Furnace's.
        if PB_UTIL.brew_cells and dropped and dropped.is and dropped:is(Card)
           and PB_UTIL.tile_resource(dropped) then
            local rid = PB_UTIL.tile_resource(dropped)
            local bn = G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID
                       and G.OVERLAY_MENU:get_UIE_by_ID('bc_brew_bottle_slot')
            if dropped.bc_source and bn and bn:collides_with_point(G.CURSOR.T) then
                local bottle = PB_UTIL.brew_bottle_state and PB_UTIL.brew_bottle_state()
                if bottle and bottle.content == 'empty'
                   and PB_UTIL.brew_bottle_accepts and PB_UTIL.brew_bottle_accepts(rid)
                   and PB_UTIL.get_resource_count(rid) >= 1 then
                    PB_UTIL.add_resource(rid, -1)
                    bottle.content = (rid == 'awkward_potion') and 'awkward' or 'water'
                    bottle.mods = {}
                    play_sound('cardSlide1')
                end
                snap_source_home(dropped)
                self.dragging.target = nil
                self.dragging.prev_target = nil
                if PB_UTIL.furnace_on_change then PB_UTIL.furnace_on_change() end
                return _orig_lrelease(self, x, y)
            end
            local target
            for _, slot in ipairs(PB_UTIL.brew_cells) do
                if slot.area:collides_with_point(G.CURSOR.T) then target = slot; break end
            end
            if dropped.bc_source then
                if target and (not target.accepts or target.accepts(rid)) and PB_UTIL.get_resource_count(rid) >= 1 then
                    local tile = spawn_tile(rid)
                    if tile then place_in_area(tile, target.area); play_sound('cardSlide1') end
                end
                snap_source_home(dropped)
                self.dragging.target = nil
                self.dragging.prev_target = nil
                if PB_UTIL.furnace_on_change then PB_UTIL.furnace_on_change() end
                return _orig_lrelease(self, x, y)
            else
                if target and target.area.cards[1] ~= dropped and (not target.accepts or target.accepts(rid)) then
                    place_in_area(dropped, target.area)
                    play_sound('cardSlide1')
                else
                    local a = dropped.area
                    if a then
                        dropped.states.drag.is = false
                        dropped.T.x = a.T.x + (a.T.w - dropped.T.w) / 2
                        dropped.T.y = a.T.y + (a.T.h - dropped.T.h) / 2
                    end
                end
                self.dragging.target = nil
                self.dragging.prev_target = nil
                if PB_UTIL.furnace_on_change then PB_UTIL.furnace_on_change() end
                return _orig_lrelease(self, x, y)
            end
        end
        if PB_UTIL.craft_cells and dropped and dropped.is and dropped:is(Card)
           and PB_UTIL.tile_resource(dropped) then
            if dropped.bc_source then
                -- SOURCE drag: deposit a new reserved tile into the cell under cursor;
                -- the source card snaps back home (it is NEVER consumed or reserved).
                local rid = PB_UTIL.tile_resource(dropped)
                for i = 1, 3 do
                    for j = 1, 3 do
                        local area = PB_UTIL.craft_cells[i][j]
                        if area:collides_with_point(G.CURSOR.T) then
                            if PB_UTIL.get_resource_count(rid) >= 1 then
                                local tile = spawn_tile(rid)   -- the ONLY -1 debit
                                if tile then
                                    place_in_cell(tile, i, j)
                                    play_sound('cardSlide1')
                                end
                            end
                            snap_source_home(dropped)
                            self.dragging.target = nil       -- load-bearing (see rationale)
                            self.dragging.prev_target = nil   -- redundant belt-and-suspenders
                            on_change()
                            return _orig_lrelease(self, x, y)
                        end
                    end
                end
                -- Dropped outside every cell: just snap home, NO count change.
                snap_source_home(dropped)
                self.dragging.target = nil
                self.dragging.prev_target = nil
                return _orig_lrelease(self, x, y)
            else
                -- PLACED-TILE drag: move into the cell under cursor, or return if outside.
                for i = 1, 3 do
                    for j = 1, 3 do
                        local area = PB_UTIL.craft_cells[i][j]
                        if area:collides_with_point(G.CURSOR.T) then
                            if area.cards[1] ~= dropped then
                                place_in_cell(dropped, i, j)
                                play_sound('cardSlide1')
                            end
                            self.dragging.target = nil       -- load-bearing (see rationale)
                            self.dragging.prev_target = nil   -- redundant belt-and-suspenders
                            on_change()
                            return _orig_lrelease(self, x, y)
                        end
                    end
                end
                -- Dropped outside every cell -> return the tile (credit) and re-match.
                return_tile(dropped)
                self.dragging.target = nil       -- load-bearing (see rationale)
                self.dragging.prev_target = nil   -- redundant belt-and-suspenders
                on_change()
            end
        end
        return _orig_lrelease(self, x, y)
    end
end

-- ---- Right-click remove (no node-level right-click; wrap the controller) ----
-- queue_R_cursor_press is the only right-click entry (controller.lua:1094). If the
-- cursor is over a grid cell holding a tile, return it; else defer to vanilla.
if not PB_UTIL._craft_rclick_hooked then
    PB_UTIL._craft_rclick_hooked = true
    local _orig_rpress = Controller.queue_R_cursor_press
    function Controller:queue_R_cursor_press(x, y)
        -- Right-click a unified Anvil slot: pull a reserved ore tile back to inventory (credit), OR
        -- send a tool/book card back to the source row.
        if PB_UTIL.anvil_unified_cells then
            for _, slot in ipairs(PB_UTIL.anvil_unified_cells) do
                local area = slot.area
                local occ = area.cards and area.cards[1]
                if occ and area:collides_with_point(G.CURSOR.T) then
                    if PB_UTIL.tile_resource(occ) then
                        return_tile(occ)
                    elseif PB_UTIL.anvil_src_area then
                        occ.states.drag.is = false
                        area:remove_card(occ)
                        PB_UTIL.anvil_src_area:emplace(occ)
                    end
                    play_sound('cardSlide1')
                    if PB_UTIL.anvil_on_change then PB_UTIL.anvil_on_change() end
                    return
                end
            end
        end
        -- Right-click a Brewing Stand slot: pull a reserved fuel/ingredient tile (credit), OR refund
        -- a Water Bottle / Awkward Potion from the bottle slot (finished/intermediate bottles have no
        -- resource to refund). The persistent bottle state is reset to empty on a bottle refund.
        if PB_UTIL.brew_cells then
            local bn = G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID
                       and G.OVERLAY_MENU:get_UIE_by_ID('bc_brew_bottle_slot')
            if bn and bn:collides_with_point(G.CURSOR.T) then
                local bottle = PB_UTIL.brew_bottle_state and PB_UTIL.brew_bottle_state()
                if bottle and (bottle.content == 'water' or bottle.content == 'awkward') then
                    PB_UTIL.add_resource(bottle.content == 'awkward' and 'awkward_potion' or 'water_bottle', 1)
                    bottle.content = 'empty'
                    bottle.mods = {}
                    play_sound('cardSlide1')
                    if PB_UTIL.furnace_on_change then PB_UTIL.furnace_on_change() end
                end
                return   -- over the bottle: consume the right-click either way
            end
            for _, slot in ipairs(PB_UTIL.brew_cells) do
                local area = slot.area
                if area.cards[1] and area:collides_with_point(G.CURSOR.T) then
                    return_tile(area.cards[1])
                    play_sound('cardSlide1')
                    if PB_UTIL.furnace_on_change then PB_UTIL.furnace_on_change() end
                    return
                end
            end
        end
        -- Right-click a furnace slot to pull its reserved tile back to inventory (credit).
        if PB_UTIL.furnace_cells then
            for _, slot in ipairs(PB_UTIL.furnace_cells) do
                local area = slot.area
                if area.cards[1] and area:collides_with_point(G.CURSOR.T) then
                    return_tile(area.cards[1])
                    play_sound('cardSlide1')
                    if PB_UTIL.furnace_on_change then PB_UTIL.furnace_on_change() end
                    return
                end
            end
        end
        if PB_UTIL.craft_cells then
            for i = 1, 3 do
                for j = 1, 3 do
                    local area = PB_UTIL.craft_cells[i][j]
                    if area.cards[1] and area:collides_with_point(G.CURSOR.T) then
                        return_tile(area.cards[1])
                        play_sound('cardSlide1')
                        on_change()
                        return
                    end
                end
            end
        end
        return _orig_rpress(self, x, y)
    end
end

-- ---- Cleanup-on-close safety net (CREDITS) ----
-- Return (credit) every tile still in a grid cell + any mid-drag tile, destroy all tile
-- Cards, remove the nine grid CardAreas, ALSO remove inventory CardAreas (sources are
-- NOT reserved, so NO credit for them). Idempotent. Called on EVERY close path (the
-- exit_overlay_menu wrap) AND defensively from build_craft_cells.
function PB_UTIL.destroy_craft_cells()
    -- Reclaim a tile the player is still mid-dragging when the modal closes.
    local C = G.CONTROLLER
    local dragged = C and C.dragging and C.dragging.target
    if PB_UTIL.craft_cells and dragged and dragged.is and dragged:is(Card)
       and PB_UTIL.tile_resource(dragged) and not dragged.bc_source then
        local rid = PB_UTIL.tile_resource(dragged)
        if rid then PB_UTIL.add_resource(rid, 1) end
        dragged:remove()   -- self-detaches from area; nulls controller refs
        C.dragging.target = nil
        C.dragging.prev_target = nil
    end

    -- Credit + destroy every tile in the grid cells.
    if PB_UTIL.craft_cells then
        for i = 1, 3 do
            for j = 1, 3 do
                local area = PB_UTIL.craft_cells[i][j]
                if area then
                    local occupant = area.cards and area.cards[1]
                    if occupant then
                        local rid = PB_UTIL.tile_resource(occupant)
                        if rid then PB_UTIL.add_resource(rid, 1) end  -- return (credit)
                    end
                    area:remove()  -- CardArea:remove destroys its cards + unregisters
                end
            end
        end
        PB_UTIL.craft_cells = nil
    end

    -- Tear down inventory source areas. Sources are INERT (never reserved) -- NO credit.
    if PB_UTIL.inv_cells then
        for _, entry in ipairs(PB_UTIL.inv_cells) do
            if entry.area then entry.area:remove() end
        end
        PB_UTIL.inv_cells = nil
    end
    PB_UTIL._inv_signature = nil
    -- Drop recipe-square sprite refs (rebuilt by build_crafting_modal on next open) so the
    -- per-frame opacity pass goes inert while no modal is open.
    PB_UTIL.recipe_sprites = nil
end

-- ---- Clear-in-place (reuse the SAME nine embedded CardArea objects) ----
-- Empty all nine GRID cells WITHOUT removing the CardAreas (they stay embedded in the
-- live overlay -- no re-embed, no overlay rebuild). `credit=true` returns each tile (+1);
-- `credit=false` consumes them (spent by a craft). Used by bc_grid_craft / bc_autofill
-- so the grid stays usable after a craft with NO overlay rebuild.
-- NOTE: inventory sources are NOT touched here (they never hold reserved tiles).
function PB_UTIL.clear_craft_cells(credit)
    if not PB_UTIL.craft_cells then return end
    for i = 1, 3 do
        for j = 1, 3 do
            local area = PB_UTIL.craft_cells[i][j]
            local card = area and area.cards and area.cards[1]
            if card then
                if credit then
                    local rid = PB_UTIL.tile_resource(card)
                    if rid then PB_UTIL.add_resource(rid, 1) end
                end
                card:remove()   -- self-detaches from area; NO area:remove (cell reused)
            end
        end
    end
end

-- ---- Furnace input/fuel slots (parallel to the crafting grid; reuses ALL the lifecycle above) ----

-- Build the two Furnace drop slots (input + fuel) as single-slot CardAreas, identical to the craft
-- cells, plus per-slot `accepts` predicates so the drag router only lets a smeltable raw into the
-- input slot and a fuel resource into the fuel slot. Idempotent (destroys any prior set first).
function PB_UTIL.build_furnace_cells()
    PB_UTIL.destroy_furnace_cells()
    local function mk_area()
        return CardArea(G.ROOM.T.x, G.ROOM.T.y, CELL_W, CELL_H,
            { card_limit = 1, type = 'title_2', highlight_limit = 0, card_w = CELL_W, no_card_count = true })
    end
    PB_UTIL.furnace_input_area = mk_area()
    PB_UTIL.furnace_fuel_area  = mk_area()
    PB_UTIL.furnace_cells = {
        { area = PB_UTIL.furnace_input_area, kind = 'input',
          accepts = function(rid) return PB_UTIL.SMELT_BY_RAW and PB_UTIL.SMELT_BY_RAW[rid] ~= nil end },
        { area = PB_UTIL.furnace_fuel_area, kind = 'fuel',
          accepts = function(rid) return PB_UTIL.FUEL_VALUE and PB_UTIL.FUEL_VALUE[rid] ~= nil end },
    }
    return PB_UTIL.furnace_cells
end

-- Build the two Anvil "Forge Sheets" drop slots. Both accept an ORE the Anvil can press into a Sheet
-- (PB_UTIL.anvil_ore_accepts; the two must hold the SAME ore, checked at forge time). Same single-slot
-- CardAreas + reserve accounting as the Furnace, built into PB_UTIL.furnace_cells so the shared drag
-- router (above) and destroy_furnace_cells drive them with NO extra code. See utilities/furnace.lua.
function PB_UTIL.build_anvil_forge_cells()
    PB_UTIL.destroy_furnace_cells()
    local function mk_area()
        return CardArea(G.ROOM.T.x, G.ROOM.T.y, CELL_W, CELL_H,
            { card_limit = 1, type = 'title_2', highlight_limit = 0, card_w = CELL_W, no_card_count = true })
    end
    PB_UTIL.anvil_in_a = mk_area()
    PB_UTIL.anvil_in_b = mk_area()
    local accepts = function(rid) return PB_UTIL.anvil_ore_accepts and PB_UTIL.anvil_ore_accepts(rid) end
    PB_UTIL.furnace_cells = {
        { area = PB_UTIL.anvil_in_a, kind = 'anvil_a', accepts = accepts },
        { area = PB_UTIL.anvil_in_b, kind = 'anvil_b', accepts = accepts },
    }
    return PB_UTIL.furnace_cells
end

-- ---- Unified Anvil cells + the all-owned tools/books source ----

-- Build the two unified Anvil input slots (single-slot title_2 areas like the craft cells). NO
-- per-slot accepts: both take anything; PB_UTIL.anvil_dispatch judges the pair. Idempotent.
function PB_UTIL.build_anvil_unified_cells()
    if PB_UTIL.anvil_unified_cells or PB_UTIL.anvil_src_area then PB_UTIL.destroy_anvil_cells() end
    -- CARD-sized areas (not CELL-sized): the slots hold full tool/book cards, and the drop router hit-tests
    -- `area:collides_with_point` -- a cell-sized area made only the tiny centre a valid drop zone (finicky).
    -- align_cards/the per-frame snap position by each card's OWN T.w, so an ore tile just centres inside
    -- (not stretched). card_w stays CELL_W so any tile auto-scaling keeps the small ore look.
    local AW, AH = (G.CARD_W or 0.95) + 0.06, (G.CARD_H or 1.27) + 0.06
    local function mk_area()
        return CardArea(G.ROOM.T.x, G.ROOM.T.y, AW, AH,
            { card_limit = 1, type = 'title_2', highlight_limit = 0, card_w = CELL_W, no_card_count = true })
    end
    PB_UTIL.anvil_in_a = mk_area()
    PB_UTIL.anvil_in_b = mk_area()
    PB_UTIL.anvil_unified_cells = {
        { area = PB_UTIL.anvil_in_a, kind = 'a' },
        { area = PB_UTIL.anvil_in_b, kind = 'b' },
    }
    return PB_UTIL.anvil_unified_cells
end

-- A tool or enchant book (the only things the Anvil source surfaces). Always-loaded: the tool set is
-- intrinsic; books are guarded (only exist with enhancements). Exposed for furnace.lua.
local function is_anvil_consumable(c)
    if not (c and c.ability) then return false end
    return c.ability.set == 'balacraft_tool'
        or (PB_UTIL.is_enchant_book and PB_UTIL.is_enchant_book(c))
end
PB_UTIL.is_anvil_consumable = is_anvil_consumable

-- Build the transient draggable source of ALL owned tools/books: drain the EQUIPPED ones out of
-- G.bc_mc_consumeables and MATERIALIZE the inventory-stored ones (flagged bc_from_storage so
-- destroy_anvil_cells re-stores them). A 'joker'-type area so the real cards render + drag; the router
-- lands them in the input slots. Non-tool/book equipped consumables (food/potions) are left in place.
function PB_UTIL.build_anvil_consumable_source()
    -- Narrow enough to sit inside the Consumables widget (RW ~ 3.5 wide in crafting_ui.lua); the cards
    -- squeeze together like a vanilla joker/consumable area when the player owns more than a few tools.
    -- no_card_count hides the engine's "x/limit" tag (cardarea.lua:319) -- no more stray "0/64" label.
    local w = 3.1
    PB_UTIL.anvil_src_area = CardArea(G.ROOM.T.x, G.ROOM.T.y, w, 1.05 * G.CARD_H,
        { card_limit = 64, type = 'joker', highlight_limit = 0, no_card_count = true })
    -- These are DRAG-ONLY source cards. A click on a 'joker'-type area calls add_to_highlighted, which
    -- crashes when highlighted_limit==0 (`remove_from_highlighted(self.highlighted[1])` with [1]==nil,
    -- cardarea.lua:165/227). Card:click only enters that path when can_highlight is true (card.lua:5137),
    -- so force it false -- a click becomes a no-op and dragging (a separate path) still works.
    PB_UTIL.anvil_src_area.can_highlight = function() return false end
    local mc = G.bc_mc_consumeables
    if mc and mc.cards then
        for i = #mc.cards, 1, -1 do
            local c = mc.cards[i]
            if is_anvil_consumable(c) then
                mc:remove_card(c)
                c.bc_from_storage = nil
                PB_UTIL.anvil_src_area:emplace(c)
            end
        end
    end
    local bcs = G.GAME and G.GAME.balacraft
    local stored = bcs and bcs.inv and bcs.inv.stored
    if stored and PB_UTIL.materialize_stored_consumable then
        for i = #stored, 1, -1 do
            local saved  = stored[i]
            local center = saved and saved.save_fields and saved.save_fields.center
            local set    = center and G.P_CENTERS[center] and G.P_CENTERS[center].set
            if set == 'balacraft_tool' or set == 'balacraft_enchant' then
                local card = PB_UTIL.materialize_stored_consumable(saved)
                if card then
                    table.remove(stored, i)
                    card.added_to_deck = true
                    card.bc_from_storage = true
                    PB_UTIL.anvil_src_area:emplace(card)
                end
            end
        end
        bcs._panel_dirty = true
    end
    return PB_UTIL.anvil_src_area
end

-- Tear down the unified Anvil overlay: stop any mid-drag (null BOTH controller drag refs -- the
-- load-bearing prev_target null), credit reserved ore tiles, and RESTORE every tool/book (in slots or
-- the source row) to where it came from -- stored-origin back to inventory storage, the rest to the MC
-- consumable area (or storage if full). Then remove all transient areas + the inventory sources. Idempotent.
function PB_UTIL.destroy_anvil_cells()
    if not (PB_UTIL.anvil_unified_cells or PB_UTIL.anvil_src_area) then return end
    local C = G.CONTROLLER
    local dragged = C and C.dragging and C.dragging.target
    if dragged and dragged.is and dragged:is(Card) then
        if PB_UTIL.tile_resource(dragged) and not dragged.bc_source then
            local rid = PB_UTIL.tile_resource(dragged)
            if rid then PB_UTIL.add_resource(rid, 1) end   -- credit a mid-drag reserved tile
            dragged:remove()
        end
        C.dragging.target = nil
        C.dragging.prev_target = nil
    end

    -- Gather surviving tool/book cards from the slots + source area; credit any reserved ore tiles.
    local cards = {}
    if PB_UTIL.anvil_unified_cells then
        for _, slot in ipairs(PB_UTIL.anvil_unified_cells) do
            local occ = slot.area and slot.area.cards and slot.area.cards[1]
            if occ then
                if PB_UTIL.tile_resource(occ) then
                    local rid = PB_UTIL.tile_resource(occ)
                    if rid then PB_UTIL.add_resource(rid, 1) end   -- credit reserved tile
                    occ:remove()
                else
                    slot.area:remove_card(occ); cards[#cards + 1] = occ
                end
            end
        end
    end
    if PB_UTIL.anvil_src_area and PB_UTIL.anvil_src_area.cards then
        for i = #PB_UTIL.anvil_src_area.cards, 1, -1 do
            local c = PB_UTIL.anvil_src_area.cards[i]
            PB_UTIL.anvil_src_area:remove_card(c); cards[#cards + 1] = c
        end
    end

    for _, c in ipairs(cards) do
        c.states.drag.is = false
        if c.bc_from_storage then
            c.bc_from_storage = nil
            if PB_UTIL.store_consumable_card then PB_UTIL.store_consumable_card(c) else c:remove() end
        elseif PB_UTIL.mc_has_room and PB_UTIL.mc_has_room() then
            G.bc_mc_consumeables:emplace(c)
        elseif PB_UTIL.store_consumable_card then
            PB_UTIL.store_consumable_card(c)
        elseif G.bc_mc_consumeables then
            G.bc_mc_consumeables:emplace(c)
        end
    end

    if PB_UTIL.anvil_unified_cells then
        for _, slot in ipairs(PB_UTIL.anvil_unified_cells) do
            if slot.area then slot.area:remove() end
        end
        PB_UTIL.anvil_unified_cells = nil
    end
    PB_UTIL.anvil_in_a = nil
    PB_UTIL.anvil_in_b = nil
    if PB_UTIL.anvil_src_area then PB_UTIL.anvil_src_area:remove(); PB_UTIL.anvil_src_area = nil end

    -- Inventory sources are INERT (never reserved) -- NO credit.
    if PB_UTIL.inv_cells then
        for _, entry in ipairs(PB_UTIL.inv_cells) do
            if entry.area then entry.area:remove() end
        end
        PB_UTIL.inv_cells = nil
    end
    PB_UTIL._inv_signature = nil
    if PB_UTIL.reconcile_mc_consumables then PB_UTIL.reconcile_mc_consumables() end
end

-- Build the two Brewing Stand drop slots: fuel (accepts Blaze Powder) + ingredient (accepts every
-- brew ingredient + the 3 modifiers, from PB_UTIL.BREW_INGREDIENT_ACCEPTS). Same single-slot CardAreas
-- + reserve accounting as the Furnace; the shared drag router + destroy_brew_cells drive them. The
-- bottle is a display-only node, not a slot here. See utilities/brewing_ui.lua.
function PB_UTIL.build_brew_cells()
    PB_UTIL.destroy_brew_cells()
    local function mk_area()
        return CardArea(G.ROOM.T.x, G.ROOM.T.y, CELL_W, CELL_H,
            { card_limit = 1, type = 'title_2', highlight_limit = 0, card_w = CELL_W, no_card_count = true })
    end
    PB_UTIL.brew_fuel_area       = mk_area()
    PB_UTIL.brew_ingredient_area = mk_area()
    PB_UTIL.brew_cells = {
        { area = PB_UTIL.brew_fuel_area, kind = 'fuel',
          accepts = function(rid) return rid == 'blaze_powder' end },
        { area = PB_UTIL.brew_ingredient_area, kind = 'ingredient',
          accepts = function(rid) return PB_UTIL.BREW_INGREDIENT_ACCEPTS and PB_UTIL.BREW_INGREDIENT_ACCEPTS[rid] == true end },
    }
    return PB_UTIL.brew_cells
end

-- An overlay node embedding one furnace slot CardArea (same dark inset square as a craft cell).
function PB_UTIL.furnace_slot_node(area)
    return {
        n = G.UIT.C,
        config = { align = 'cm', padding = 0.03, minw = CELL_W + 0.06, minh = CELL_H + 0.06,
                   r = 0.05, colour = G.C.UI.TRANSPARENT_DARK },
        nodes = { { n = G.UIT.O, config = { object = area } } },
    }
end

-- Tear down the furnace slots: CREDIT back any reserved tile still sitting in a slot (they were
-- debited on placement, like craft cells), remove the slot CardAreas, AND tear down the shared
-- inventory source areas (the furnace builds them via build_inventory too). Idempotent.
function PB_UTIL.destroy_furnace_cells()
    -- Reclaim a tile mid-dragged from a furnace slot when the modal closes.
    local C = G.CONTROLLER
    local dragged = C and C.dragging and C.dragging.target
    if PB_UTIL.furnace_cells and dragged and dragged.is and dragged:is(Card)
       and PB_UTIL.tile_resource(dragged) and not dragged.bc_source then
        local rid = PB_UTIL.tile_resource(dragged)
        if rid then PB_UTIL.add_resource(rid, 1) end
        dragged:remove()
        C.dragging.target = nil
        C.dragging.prev_target = nil
    end
    if PB_UTIL.furnace_cells then
        for _, slot in ipairs(PB_UTIL.furnace_cells) do
            local area = slot.area
            if area then
                local occupant = area.cards and area.cards[1]
                if occupant then
                    local rid = PB_UTIL.tile_resource(occupant)
                    if rid then PB_UTIL.add_resource(rid, 1) end   -- return (credit)
                end
                area:remove()
            end
        end
        PB_UTIL.furnace_cells = nil
        PB_UTIL.furnace_input_area = nil
        PB_UTIL.furnace_fuel_area = nil
        PB_UTIL.anvil_in_a = nil   -- Anvil "Forge Sheets" reuses furnace_cells; clear its refs too
        PB_UTIL.anvil_in_b = nil
    end
    -- Inventory sources are INERT (never reserved) -- NO credit.
    if PB_UTIL.inv_cells then
        for _, entry in ipairs(PB_UTIL.inv_cells) do
            if entry.area then entry.area:remove() end
        end
        PB_UTIL.inv_cells = nil
    end
    PB_UTIL._inv_signature = nil
end

-- Tear down the Brewing Stand slots: CREDIT back the reserved fuel/ingredient tiles (incl. a mid-drag
-- one) + the inventory sources, then drop the slot refs. The persistent G.GAME.balacraft.brew_bottle
-- is DELIBERATELY untouched -- the bottle's progress survives closing the stand (MC-like). Idempotent.
function PB_UTIL.destroy_brew_cells()
    local C = G.CONTROLLER
    local dragged = C and C.dragging and C.dragging.target
    if PB_UTIL.brew_cells and dragged and dragged.is and dragged:is(Card)
       and PB_UTIL.tile_resource(dragged) and not dragged.bc_source then
        local rid = PB_UTIL.tile_resource(dragged)
        if rid then PB_UTIL.add_resource(rid, 1) end
        dragged:remove()
        C.dragging.target = nil
        C.dragging.prev_target = nil
    end
    if PB_UTIL.brew_cells then
        for _, slot in ipairs(PB_UTIL.brew_cells) do
            local area = slot.area
            if area then
                local occ = area.cards and area.cards[1]
                if occ then
                    local rid = PB_UTIL.tile_resource(occ)
                    if rid then PB_UTIL.add_resource(rid, 1) end   -- return (credit)
                end
                area:remove()
            end
        end
        PB_UTIL.brew_cells = nil
        PB_UTIL.brew_fuel_area = nil
        PB_UTIL.brew_ingredient_area = nil
    end
    if PB_UTIL.inv_cells then
        for _, entry in ipairs(PB_UTIL.inv_cells) do
            if entry.area then entry.area:remove() end
        end
        PB_UTIL.inv_cells = nil
    end
    PB_UTIL._inv_signature = nil
end
