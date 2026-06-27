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

-- Tunable size constants (Minecraft-slot aesthetic, small squares).
local CELL_W = 0.7   -- grid cell width  (world-units) -- tune in-game
local CELL_H = 0.7   -- grid cell height (world-units) -- tune in-game

-- Inventory is a fixed generic grid: INV_COLS x INV_ROWS slots, NONE pre-assigned to a
-- resource. populate_inventory fills the first N slots with the items the player owns
-- (count > 0, registry order) and leaves the rest blank; it reflows when the owned set
-- changes. Slots are draggable sources into the craft grid (same as before).
local INV_COLS  = 8
local INV_ROWS  = 3
local INV_SLOTS = INV_COLS * INV_ROWS   -- 24

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
    for _ = 1, INV_SLOTS do
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
    PB_UTIL.populate_inventory()
end

-- Owned-item signature in registry order (e.g. 'wood,coal,sticks'). Cheap; compared each
-- frame to decide whether the inventory needs reflowing (an item appeared or hit 0).
function PB_UTIL.inventory_owned_signature()
    local store = (G.GAME.balacraft and G.GAME.balacraft.resources) or {}
    local owned = {}
    for _, r in ipairs(PB_UTIL.RESOURCES) do
        if (store[r.id] or 0) > 0 then owned[#owned + 1] = r.id end
    end
    return table.concat(owned, ',')
end

-- Assign owned items (count > 0, registry order, ALL kinds incl. crafted) to the leading
-- slots; clear the rest. Mutates the fixed areas in place (no overlay rebuild): swaps a
-- slot's source card only when its assigned resource changes. Idempotent.
function PB_UTIL.populate_inventory()
    if not PB_UTIL.inv_cells then return end
    local store = (G.GAME.balacraft and G.GAME.balacraft.resources) or {}
    local owned = {}
    for _, r in ipairs(PB_UTIL.RESOURCES) do
        if (store[r.id] or 0) > 0 then owned[#owned + 1] = r.id end
    end

    for i, entry in ipairs(PB_UTIL.inv_cells) do
        local rid = owned[i]   -- nil once we pass the owned count
        if rid then
            if entry.rid ~= rid then
                -- Re-assign this slot: drop any prior source, emplace a fresh one for rid.
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
        else
            if entry.area.cards[1] then entry.area.cards[1]:remove() end
            entry.rid = nil
            entry.label_ref.count = ''   -- blank: no icon, no number
        end
    end
    PB_UTIL._inv_signature = table.concat(owned, ',')
end

-- Build the inventory node tree (INV_ROWS rows of INV_COLS slots). Each slot: a dark square
-- with the (initially empty) CardArea embedded + a count label below (blank when empty).
function PB_UTIL.build_inventory_node()
    if not PB_UTIL.inv_cells then return { n = G.UIT.R, config = { align = 'cm' }, nodes = {} } end
    local function slot_node(entry)
        return {
            n = G.UIT.C, config = { align = 'cm', padding = 0.03 },
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
    local rows = {}
    for i = 1, INV_SLOTS, INV_COLS do
        local row = { n = G.UIT.R, config = { align = 'cm', padding = 0.02 }, nodes = {} }
        for j = i, math.min(i + INV_COLS - 1, INV_SLOTS) do
            row.nodes[#row.nodes + 1] = slot_node(PB_UTIL.inv_cells[j])
        end
        rows[#rows + 1] = row
    end
    return { n = G.UIT.C, config = { align = 'cm', padding = 0.04 }, nodes = rows }
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

    if not dragging_source and PB_UTIL.inventory_owned_signature() ~= PB_UTIL._inv_signature then
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
        -- Inventory overlay (loadout/bench swap) takes precedence when open. The handler does its
        -- own emplace + dragging.target null (same win-the-release trick as below), so on a handled
        -- drop we just defer to the original release and skip the crafting branch.
        if PB_UTIL.inventory_release and PB_UTIL.inventory_release(self, dropped, x, y) then
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
