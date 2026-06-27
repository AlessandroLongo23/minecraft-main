-- Consumable-area VIEW TOGGLE. Instead of a separate panel bonded BELOW G.consumeables
-- (which overlapped the shop), resources now share the consumable area's footprint and a
-- small flip button switches what that area shows:
--   * 'consumables' view -> vanilla consumable cards (resource overlay hidden)
--   * 'resources'   view -> a grid of resource icons + counts drawn IN the consumable box;
--                            the real consumable cards are hidden (states.visible=false,
--                            which also removes them from the draw-hash so they can't be
--                            hovered/clicked -- node.lua:129-130).
-- Two Weak-bonded UIBoxes hang off G.consumeables:
--   * toggle bar  -> ABOVE the area, right-aligned: [flip button][Crafting Table]
--   * resource overlay -> CENTERED on the area (same footprint), only in 'resources' view
-- A Game:update wrapper drives create/refresh/hide each frame and ALSO re-snaps the
-- crafting modal's inventory source cards (see crafting_grid.lua) once layout settles.
--
-- The selected view lives at G.GAME.balacraft.view_mode ('remember last' within a run;
-- seeded/reset in resources.lua's init_game_object wrapper).

-- States in which the toggle (and resource view) should be available.
-- Built at load time; G.STATES is populated before mod files run (SMODS load order).
PB_UTIL.PANEL_STATES = {
    [G.STATES.SELECTING_HAND] = true,
    [G.STATES.DRAW_TO_HAND]   = true,
    [G.STATES.HAND_PLAYED]    = true,
    [G.STATES.SHOP]           = true,
    [G.STATES.BLIND_SELECT]   = true,
    [G.STATES.ROUND_EVAL]     = true,
}

-- Tunables (tune in-game).
local PER_ROW    = 7     -- columns of resource slots (7 gathered ores fit on one row)
local ICON_SZ    = 0.5   -- resource icon sprite size (world-units)
local BAR_GAP    = 0.1   -- vertical gap between the toggle bar and the area's top edge

-- Live-bound label for the flip button. The bound T-node renders this each frame
-- (ui.lua), so update_consumable_view only writes the string -- no UIBox rebuild on toggle.
-- The label names the view the click switches TO (Minecraft-ish "what you'll see next").
PB_UTIL.view_label_ref = PB_UTIL.view_label_ref or { text = 'Resources' }

-- ---- View-mode state helpers ----

function PB_UTIL.get_view_mode()
    return (G.GAME and G.GAME.balacraft and G.GAME.balacraft.view_mode) or 'consumables'
end

function PB_UTIL.set_view_mode(mode)
    if G.GAME and G.GAME.balacraft then G.GAME.balacraft.view_mode = mode end
end

-- Make a Sprite dimmable. There is NO Sprite:set_alpha in this engine (the old guard was a
-- silent no-op), and an embedded UIT.O sprite is always drawn via object:draw() with no
-- overlay (ui.lua:148) -> draw_self uses G.C.WHITE (sprite.lua:148), full opacity. We shim the
-- instance's draw to inject a white overlay whose alpha we mutate live (bc_overlay[4]); LÖVE
-- multiplies the active colour (incl. alpha) into image draws. 1 = full, <1 = dimmed.
function PB_UTIL.make_dimmable(spr)
    if not spr then return spr end
    spr.bc_overlay = { 1, 1, 1, 1 }
    local _draw = spr.draw
    spr.draw = function(self, overlay)
        return _draw(self, overlay or self.bc_overlay)
    end
    return spr
end

-- ---- Definition builders ----

-- Toggle bar: a full-(consumable)-width clear row with the two buttons hugging the RIGHT
-- edge, so when bonded centered-above the area it reads as "above the area, aligned right".
function PB_UTIL.build_toggle_bar()
    local cons_w = (G.consumeables and G.consumeables.T.w) or (2.3 * G.CARD_W)
    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0, colour = G.C.CLEAR, minw = cons_w },
        nodes = {
            { n = G.UIT.R, config = { align = 'cr', padding = 0 }, nodes = {
                -- Flip-view button (label is live-bound to view_label_ref.text).
                { n = G.UIT.C, config = {
                    align = 'cm', padding = 0.06, r = 0.08, minw = 1.15, minh = 0.42,
                    colour = G.C.BLUE, button = 'bc_toggle_view', hover = true, shadow = true,
                  }, nodes = {
                    { n = G.UIT.T, config = { ref_table = PB_UTIL.view_label_ref, ref_value = 'text',
                        scale = 0.3, colour = G.C.UI.TEXT_LIGHT } },
                  } },
                { n = G.UIT.C, config = { minw = 0.1 } },   -- gap
                -- "Your Base" button: opens the Base launcher (Crafting Table + Furnace + future
                -- stations). Replaces the old direct "Crafting Table" button (utilities/furnace.lua).
                { n = G.UIT.C, config = {
                    align = 'cm', padding = 0.06, r = 0.08, minw = 1.4, minh = 0.42,
                    colour = G.C.GREEN, button = 'bc_open_base', hover = true, shadow = true,
                  }, nodes = {
                    { n = G.UIT.T, config = { text = 'Your Base', scale = 0.26, colour = G.C.UI.TEXT_LIGHT } },
                  } },
            } },
        },
    }
end

-- Resource overlay: the ore/crafted icons + counts, sized to the consumable footprint and
-- transparent so the area's own rounded background box shows through behind it. Gathered ORES
-- always show (greyed at 0); crafted resources AND mob drops show only when owned (mob materials
-- are occasional/situational -- always-showing all of them would clutter the hotbar).
function PB_UTIL.build_resource_overlay()
    local store = (G.GAME.balacraft and G.GAME.balacraft.resources) or {}
    local atlas = G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]
    local cells = {}
    for _, r in ipairs(PB_UTIL.RESOURCES) do
        local count = store[r.id] or 0
        if (r.kind == 'gathered' and r.drop_class == 'ore') or count > 0 then
            local owned = count > 0
            local spr = PB_UTIL.make_dimmable(Sprite(0, 0, ICON_SZ, ICON_SZ, atlas, r.pos))
            if not owned then spr.bc_overlay[4] = 0.35 end   -- dim ores you don't own yet
            cells[#cells + 1] = {
                n = G.UIT.C, config = { align = 'cm', padding = 0.03 },
                nodes = {
                    { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                        { n = G.UIT.O, config = { object = spr } },
                    } },
                    { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                        { n = G.UIT.T, config = {
                            ref_table = store, ref_value = r.id, scale = 0.3,
                            colour = owned and G.C.WHITE or G.C.UI.TEXT_INACTIVE,
                        } },
                    } },
                },
            }
        end
    end

    -- Lay the resource cells out PER_ROW columns wide.
    local rows = {}
    for i = 1, #cells, PER_ROW do
        local row = { n = G.UIT.R, config = { align = 'cm' }, nodes = {} }
        for j = i, math.min(i + PER_ROW - 1, #cells) do
            row.nodes[#row.nodes + 1] = cells[j]
        end
        rows[#rows + 1] = row
    end

    local cons_w = (G.consumeables and G.consumeables.T.w) or (2.3 * G.CARD_W)
    local cons_h = (G.consumeables and G.consumeables.T.h) or (0.95 * G.CARD_H)
    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0.04, colour = G.C.CLEAR, minw = cons_w, minh = cons_h },
        nodes = rows,
    }
end

-- ---- UIBox lifecycle ----

-- 'tm' = outer-top + horizontal-middle: the box's BOTTOM edge lands BAR_GAP above the
-- consumable area's top edge, horizontally centred over it (moveable.lua:163-167). The bar
-- ROOT is consumable-width with its content right-aligned, so it reads as right-aligned.
function PB_UTIL.attach_toggle_bar()
    if G.bc_toggle_bar and not G.bc_toggle_bar.REMOVED then G.bc_toggle_bar:remove() end
    G.bc_toggle_bar = UIBox {
        definition = PB_UTIL.build_toggle_bar(),
        config = { align = 'tm', offset = { x = 0, y = -BAR_GAP }, major = G.consumeables, bond = 'Weak' },
    }
    -- Record the area we bonded to; a new run recreates G.consumeables, and 'Weak' bonds are
    -- NOT auto-removed with their major, so we rebuild when this no longer matches.
    G.bc_toggle_bar.bc_major = G.consumeables
end

-- 'cm' = inner-centre on both axes: overlay sits exactly on the consumable footprint.
function PB_UTIL.attach_resource_overlay()
    if G.bc_resource_overlay and not G.bc_resource_overlay.REMOVED then G.bc_resource_overlay:remove() end
    G.bc_resource_overlay = UIBox {
        definition = PB_UTIL.build_resource_overlay(),
        config = { align = 'cm', offset = { x = 0, y = 0 }, major = G.consumeables, bond = 'Weak' },
    }
    -- Record the backing store + bonded area so we can detect a rotated table / recreated
    -- area (new run) and rebuild ('Weak' bonds aren't auto-removed with their major).
    G.bc_resource_overlay.bc_store = G.GAME.balacraft and G.GAME.balacraft.resources
    G.bc_resource_overlay.bc_major = G.consumeables
    G.GAME.balacraft._panel_dirty = false
end

local function remove_overlay()
    if G.bc_resource_overlay and not G.bc_resource_overlay.REMOVED then G.bc_resource_overlay:remove() end
    G.bc_resource_overlay = nil
end

local function remove_toggle_bar()
    if G.bc_toggle_bar and not G.bc_toggle_bar.REMOVED then G.bc_toggle_bar:remove() end
    G.bc_toggle_bar = nil
end

-- Show/hide the real consumable cards in place. states.visible=false also drops them from
-- the draw-hash (node.lua:129-130) so a hidden consumable can't be hovered/used/sold.
local function set_consumable_cards_visible(vis)
    if not (G.consumeables and G.consumeables.cards) then return end
    for _, c in ipairs(G.consumeables.cards) do
        c.states.visible = vis
    end
end

-- ---- Per-frame driver ----

function PB_UTIL.update_consumable_view()
    local active = G.STATE and PB_UTIL.PANEL_STATES[G.STATE]
        and G.consumeables and G.GAME and G.GAME.balacraft
        and PB_UTIL.icon_atlas and G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]

    if not active then
        -- Tear everything down AND restore card visibility -- never leave consumables hidden
        -- when our UI isn't on screen (e.g. mid-animation states, menus).
        remove_overlay()
        remove_toggle_bar()
        set_consumable_cards_visible(true)
        return
    end

    local mode = PB_UTIL.get_view_mode()

    -- Toggle bar is present whenever the area is. Keep the flip label naming the TARGET view.
    if not G.bc_toggle_bar or G.bc_toggle_bar.REMOVED
        or G.bc_toggle_bar.bc_major ~= G.consumeables then PB_UTIL.attach_toggle_bar() end
    PB_UTIL.view_label_ref.text = (mode == 'resources') and 'Items' or 'Resources'

    if mode == 'resources' then
        -- (Re)build the overlay on first show, after a run-rotation / recreated area, or when
        -- ownership of a crafted resource changed which icons appear (_panel_dirty, set by add_resource).
        if not G.bc_resource_overlay or G.bc_resource_overlay.REMOVED
            or G.bc_resource_overlay.bc_store ~= G.GAME.balacraft.resources
            or G.bc_resource_overlay.bc_major ~= G.consumeables
            or G.GAME.balacraft._panel_dirty then
            PB_UTIL.attach_resource_overlay()
        end
        set_consumable_cards_visible(false)   -- enforce each frame so new cards stay hidden too
    else
        remove_overlay()
        set_consumable_cards_visible(true)
    end
end

-- Flip the view. Persisted on G.GAME (remember-last within the run); the per-frame driver
-- reflects the change next tick (label, overlay, card visibility).
G.FUNCS.bc_toggle_view = function(e)
    PB_UTIL.set_view_mode(PB_UTIL.get_view_mode() == 'resources' and 'consumables' or 'resources')
    play_sound('cardSlide1')
end

-- Single per-frame hook: drive the view toggle, then maintain the crafting modal (inventory
-- reflow/snap + recipe-square opacity; defined in crafting_ui.lua, which loads after this
-- file). Both pcall'd so a transient error can't wedge Game:update.
local _game_update = Game.update
function Game:update(dt)
    _game_update(self, dt)
    local ok, err = pcall(PB_UTIL.update_consumable_view)
    if not ok then sendDebugMessage('view error: ' .. tostring(err), 'BalaCraft') end
    if PB_UTIL.update_crafting_modal then
        local ok2, err2 = pcall(PB_UTIL.update_crafting_modal)
        if not ok2 then sendDebugMessage('craft modal error: ' .. tostring(err2), 'BalaCraft') end
    end
end
