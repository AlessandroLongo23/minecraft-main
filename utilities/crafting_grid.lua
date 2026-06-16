-- Interactive 3x3 crafting grid + palette. Owns live state while the modal is open:
-- nine single-slot CardAreas (PB_UTIL.craft_cells), spawned tiles, reserve/return
-- accounting. Tiles are real Cards from bc_resource_cards (resource_tile.lua). The
-- custom cursor-up drop hook (T5b) emplaces a dragged tile into the cell under the
-- cursor BEFORE the engine tears the drag down; cleanup-on-close (T5c) credits every
-- still-placed tile. The overlay is built ONCE and never rebuilt while open.

PB_UTIL.craft_cells = PB_UTIL.craft_cells or nil   -- 3x3 row-major of CardArea, or nil

local CELL_W = G.CARD_W
local CELL_H = 1.05 * G.CARD_H

-- Create the nine single-slot cell-areas (idempotent: destroys any prior set first).
-- type='balacraft_tile' is a CUSTOM value: set_ranks keeps drag enabled (cardarea.lua:256)
-- and align_cards no-ops (cardarea.lua:446), so we snap tiles to cell-center ourselves.
function PB_UTIL.build_craft_cells()
    PB_UTIL.destroy_craft_cells()  -- defined in T5c; safe no-op if nothing to destroy
    local cells = {}
    for i = 1, 3 do
        cells[i] = {}
        for j = 1, 3 do
            local area = CardArea(
                G.ROOM.T.x, G.ROOM.T.y,          -- X,Y throwaway; the G.UIT.O node repositions it
                CELL_W, CELL_H,
                { card_limit = 1, type = 'balacraft_tile', highlight_limit = 0, card_w = G.CARD_W }
            )
            cells[i][j] = area
        end
    end
    PB_UTIL.craft_cells = cells
    return cells
end

-- One grid cell as an overlay node embedding the CardArea (the booster-pack pattern).
local function cell_object_node(area)
    return {
        n = G.UIT.C,
        config = { align = 'cm', padding = 0.05, minw = CELL_W + 0.1, minh = CELL_H + 0.1,
                   r = 0.1, colour = G.C.UI.TRANSPARENT_DARK },
        nodes = { { n = G.UIT.O, config = { object = area } } },
    }
end

-- Build the 3x3 grid node tree (call AFTER build_craft_cells). Returns a G.UIT.C.
function PB_UTIL.build_grid_node()
    local rows = {}
    for i = 1, 3 do
        local row = { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {} }
        for j = 1, 3 do
            row.nodes[#row.nodes + 1] = cell_object_node(PB_UTIL.craft_cells[i][j])
        end
        rows[#rows + 1] = row
    end
    return { n = G.UIT.C, config = { align = 'cm', padding = 0.08, r = 0.1, colour = G.C.BLACK }, nodes = rows }
end

-- One palette source: resource icon + a live count badge. Clicking it
-- (button 'bc_palette_pick') spawns a tile into the first empty cell. Dimming for
-- unowned sources is via the UIT container colour + TEXT_INACTIVE text colour
-- (Sprite has NO set_alpha; do NOT call it -- it mirrors a pre-existing no-op in
-- resource_ui.lua:26 and would silently do nothing).
local function palette_source_node(r, count)
    local owned = count > 0
    local atlas = G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]
    local spr = Sprite(0, 0, 0.5, 0.5, atlas, r.pos)
    return {
        n = G.UIT.C,
        config = {
            align = 'cm', padding = 0.06, r = 0.08, minw = 0.8,
            colour = owned and G.C.UI.TRANSPARENT_DARK or G.C.UI.TRANSPARENT_LIGHT,
            button = owned and 'bc_palette_pick' or nil, ref_table = { id = r.id },
            hover = owned, shadow = owned,
        },
        nodes = {
            { n = G.UIT.R, config = { align = 'cm' }, nodes = { { n = G.UIT.O, config = { object = spr } } } },
            { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                { n = G.UIT.T, config = { text = 'x' .. count, scale = 0.3,
                    colour = owned and G.C.WHITE or G.C.UI.TEXT_INACTIVE } },
            } },
        },
    }
end

-- Build the palette row from current resource counts. Returns a G.UIT.R.
-- Gathered ores always show (greyed at 0); crafted resources show only when owned.
function PB_UTIL.build_palette_node()
    local store = (G.GAME.balacraft and G.GAME.balacraft.resources) or {}
    local sources = {}
    for _, r in ipairs(PB_UTIL.RESOURCES) do
        local count = store[r.id] or 0
        if r.kind == 'gathered' or count > 0 then
            sources[#sources + 1] = palette_source_node(r, count)
        end
    end
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.06 }, nodes = sources }
end

-- ---- Tile lifecycle (always go through these so reserve accounting is exact) ----

-- Return a tile to the player: credit +1, destroy. card:remove() self-detaches from
-- its area (card.lua:5244). It does NOT null G.CONTROLLER.dragging -- callers that
-- return a MID-DRAG tile must also null C.dragging.target/prev_target themselves (see
-- destroy_craft_cells and the L_cursor_release wrap). (No explicit remove_card needed
-- before card:remove.)
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

-- Public: spawn a tile for `rid` and place it in the first empty cell (palette click).
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

-- Public: spawn a tile for `rid` already grabbed by the controller as the drag target,
-- so a press on a palette source flows seamlessly into the grid. (OPTIONAL ENHANCEMENT,
-- OPEN RISK R1 -- see T5b Step 2; unwired by default. The PRIMARY palette gesture is
-- the native click path spawn_tile_to_cell via bc_palette_pick.)
function PB_UTIL.spawn_tile_for_drag(rid)
    if not PB_UTIL.craft_cells then return nil end
    local card = spawn_tile(rid)
    if not card then return nil end
    local C = G.CONTROLLER
    card.T.x = G.CURSOR.T.x - card.T.w / 2
    card.T.y = G.CURSOR.T.y - card.T.h / 2
    card.states.drag.can = true
    card.states.drag.is = true
    card.states.collide.can = true
    -- Prefer a center-pinned offset over set_offset(cursor_down.T,...) (which uses the
    -- ORIGINAL press node's coords and can make the tile jump on first move).
    card.click_offset = { x = card.T.w / 2, y = card.T.h / 2 }
    if C.cursor_down then C.cursor_down.target = card; C.cursor_down.handled = true end
    C.dragging.target = card
    C.dragging.handled = false
    return card
end

-- crafting_ui sets this to its in-place refresh so grid changes update output+button.
PB_UTIL.craft_on_change = PB_UTIL.craft_on_change or nil
local function on_change()
    if PB_UTIL.craft_on_change then PB_UTIL.craft_on_change() end
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
            -- dropped outside every cell -> return the tile (credit) and re-match
            return_tile(dropped)
            self.dragging.target = nil       -- load-bearing (see rationale)
            self.dragging.prev_target = nil   -- redundant belt-and-suspenders
            on_change()
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
-- Return (credit) every tile still in a cell + any mid-drag tile, destroy all tile
-- Cards, remove the nine CardAreas, clear state. Idempotent. Called on EVERY close
-- path (the exit_overlay_menu wrap) AND defensively from build_craft_cells.
function PB_UTIL.destroy_craft_cells()
    if not PB_UTIL.craft_cells then return end
    -- Reclaim a tile the player is still mid-dragging when the modal closes.
    local C = G.CONTROLLER
    local dragged = C and C.dragging and C.dragging.target
    if dragged and dragged.is and dragged:is(Card) and PB_UTIL.tile_resource(dragged) then
        local rid = PB_UTIL.tile_resource(dragged)
        if rid then PB_UTIL.add_resource(rid, 1) end
        dragged:remove()   -- self-detaches from area; nulls controller refs
        C.dragging.target = nil
        C.dragging.prev_target = nil
    end
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

-- ---- Clear-in-place (reuse the SAME nine embedded CardArea objects) ----
-- Empty all nine cells WITHOUT removing the CardAreas (they stay embedded in the live
-- overlay -- no re-embed, no overlay rebuild). `credit=true` returns each tile (+1);
-- `credit=false` consumes them (spent by a craft). Used by bc_grid_craft / bc_autofill
-- so the grid stays usable after a craft with NO overlay rebuild.
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
