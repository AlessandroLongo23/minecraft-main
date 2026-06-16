-- Interactive 3x3 crafting grid + draggable inventory sources. Owns live state while
-- the modal is open: nine single-slot grid CardAreas (PB_UTIL.craft_cells) plus one
-- CardArea per visible resource for the inventory row (PB_UTIL.inv_cells).
-- Tile lifecycle: only spawn_tile debits (-1) and return_tile/destroy-credit/clear(true)
-- credit (+1). Source cards in inv_cells are NEVER reserved and NEVER touched by
-- add_resource -- they only trigger a spawn_tile in the drop hook when landing on a cell.
-- The overlay is built ONCE and never rebuilt while open.

PB_UTIL.craft_cells = PB_UTIL.craft_cells or nil   -- 3x3 row-major of CardArea, or nil
PB_UTIL.inv_cells   = PB_UTIL.inv_cells   or nil   -- flat list of {area, rid, label_ref}

-- Tunable size constants (Minecraft-slot aesthetic, small squares).
local CELL_W = 0.7   -- grid cell width  (world-units) -- tune in-game
local CELL_H = 0.7   -- grid cell height (world-units) -- tune in-game

-- ---- Grid cell construction ----

-- Create the nine single-slot cell-areas (idempotent: destroys any prior set first).
-- type='balacraft_tile' is a CUSTOM value: set_ranks keeps drag enabled (cardarea.lua:256)
-- and align_cards no-ops (cardarea.lua:446), so we snap tiles to cell-center ourselves.
function PB_UTIL.build_craft_cells()
    PB_UTIL.destroy_craft_cells()  -- safe no-op if nothing to destroy
    local cells = {}
    for i = 1, 3 do
        cells[i] = {}
        for j = 1, 3 do
            local area = CardArea(
                G.ROOM.T.x, G.ROOM.T.y,          -- X,Y throwaway; the G.UIT.O node repositions it
                CELL_W, CELL_H,
                { card_limit = 1, type = 'balacraft_tile', highlight_limit = 0, card_w = CELL_W }
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

-- Build the inventory CardAreas and their source Cards. Called from open_crafting_table
-- (after build_craft_cells) so all areas live for the modal's lifetime.
-- Creates one single-slot CardArea per visible resource; emplaces a make_resource_source
-- card into each. Sources are NEVER reserved.
function PB_UTIL.build_inventory()
    -- Tear down any stale inventory first (safety; normally nil here).
    if PB_UTIL.inv_cells then
        for _, entry in ipairs(PB_UTIL.inv_cells) do
            if entry.area then entry.area:remove() end
        end
        PB_UTIL.inv_cells = nil
    end

    local store = (G.GAME.balacraft and G.GAME.balacraft.resources) or {}
    local cells = {}
    for _, r in ipairs(PB_UTIL.RESOURCES) do
        local count = store[r.id] or 0
        if r.kind == 'gathered' or count > 0 then
            local area = CardArea(
                G.ROOM.T.x, G.ROOM.T.y,
                CELL_W, CELL_H,
                { card_limit = 1, type = 'balacraft_tile', highlight_limit = 0, card_w = CELL_W }
            )
            local src = PB_UTIL.make_resource_source(r.id, 0, 0)
            if src then
                src.states.drag.is = false
                area:emplace(src)
                src.T.x = area.T.x + (area.T.w - src.T.w) / 2
                src.T.y = area.T.y + (area.T.h - src.T.h) / 2
                src.area = area   -- backref so snap_source_home can find the home area
            end
            local label_ref = { count = 'x' .. count }
            cells[#cells + 1] = { area = area, rid = r.id, label_ref = label_ref }
        end
    end
    PB_UTIL.inv_cells = cells
end

-- Build the inventory node row for embedding in the modal. Returns a G.UIT.R.
-- Each slot: the CardArea object + a count label below it.
function PB_UTIL.build_inventory_node()
    if not PB_UTIL.inv_cells then return { n = G.UIT.R, config = { align = 'cm' }, nodes = {} } end
    local store = (G.GAME.balacraft and G.GAME.balacraft.resources) or {}
    local slot_nodes = {}
    for _, entry in ipairs(PB_UTIL.inv_cells) do
        local count = store[entry.rid] or 0
        slot_nodes[#slot_nodes + 1] = {
            n = G.UIT.C, config = { align = 'cm', padding = 0.03 },
            nodes = {
                { n = G.UIT.R, config = { align = 'cm', padding = 0.02,
                    minw = CELL_W + 0.06, minh = CELL_H + 0.06,
                    r = 0.05, colour = G.C.UI.TRANSPARENT_DARK },
                  nodes = { { n = G.UIT.O, config = { object = entry.area } } } },
                { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                    { n = G.UIT.T, config = {
                        ref_table = entry.label_ref, ref_value = 'count',
                        scale = 0.28, colour = G.C.WHITE } },
                } },
            },
        }
    end
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = slot_nodes }
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

-- Place `card` into cell (i,j). If occupied, the prior occupant is RETURNED (credit)
-- and replaced (swap). Snap to cell-center (custom type => align_cards no-ops).
local function place_in_cell(card, i, j)
    local area = PB_UTIL.craft_cells and PB_UTIL.craft_cells[i] and PB_UTIL.craft_cells[i][j]
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
    -- Refresh inventory count labels so they stay live after a deposit.
    if PB_UTIL.inv_cells then
        local store = (G.GAME.balacraft and G.GAME.balacraft.resources) or {}
        for _, entry in ipairs(PB_UTIL.inv_cells) do
            entry.label_ref.count = 'x' .. (store[entry.rid] or 0)
        end
    end
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
