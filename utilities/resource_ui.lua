-- Consumable-area VIEW TOGGLE + the Inventory button.
--
-- The on-screen consumable footprint is shared by TWO card areas that overlap exactly:
--   * G.consumeables        -> vanilla Tarot / Planet / Spectral (still grows via vouchers)
--   * G.bc_mc_consumeables  -> the 2 Minecraft consumable slots (tools / food / books)
-- A small toggle bar above the area flips which one is shown (the other's cards are hidden via
-- states.visible=false, which also drops them from the draw-hash so they can't be hovered/used).
-- The second button opens the big unified Inventory + Base modal (utilities/crafting_ui.lua).
--
-- The selected side lives at G.GAME.balacraft.view_mode ('vanilla' | 'minecraft'), 'remember last'
-- within a run (seeded/reset in resources.lua's init_game_object wrapper). Resources NO LONGER show
-- here -- they live in the Inventory modal.

-- States in which the toggle + consumable areas should be interactive.
PB_UTIL.PANEL_STATES = {
    [G.STATES.SELECTING_HAND] = true,
    [G.STATES.DRAW_TO_HAND]   = true,
    [G.STATES.HAND_PLAYED]    = true,
    [G.STATES.SHOP]           = true,
    [G.STATES.BLIND_SELECT]   = true,
    [G.STATES.ROUND_EVAL]     = true,
}

local BAR_GAP = 0.1   -- vertical gap between the toggle bar and the area's top edge

-- Live-bound label for the flip button (re-rendered each frame by ui.lua, so the driver only
-- writes the string -- no UIBox rebuild on toggle). Names the side the click switches TO.
PB_UTIL.view_label_ref = PB_UTIL.view_label_ref or { text = 'Minecraft' }

function PB_UTIL.get_view_mode()
    return (G.GAME and G.GAME.balacraft and G.GAME.balacraft.view_mode) or 'vanilla'
end

function PB_UTIL.set_view_mode(mode)
    if G.GAME and G.GAME.balacraft then G.GAME.balacraft.view_mode = mode end
end

-- Make a Sprite dimmable. There is NO Sprite:set_alpha in this engine, and an embedded UIT.O sprite
-- is drawn via object:draw() with no overlay (full opacity). We shim the instance's draw to inject a
-- white overlay whose alpha we mutate live (bc_overlay[4]); LÖVE multiplies the active colour (incl.
-- alpha) into image draws. 1 = full, <1 = dimmed. Shared by the crafting/furnace/inventory icons.
function PB_UTIL.make_dimmable(spr)
    if not spr then return spr end
    spr.bc_overlay = { 1, 1, 1, 1 }
    local _draw = spr.draw
    spr.draw = function(self, overlay)
        return _draw(self, overlay or self.bc_overlay)
    end
    return spr
end

-- ---- Toggle bar definition ----
-- Full-(consumable)-width clear row with the two buttons hugging the RIGHT edge, so bonded
-- centered-above the area it reads as "above the area, aligned right".
function PB_UTIL.build_toggle_bar()
    local cons_w = (G.consumeables and G.consumeables.T.w) or (2.3 * G.CARD_W)
    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0, colour = G.C.CLEAR, minw = cons_w },
        nodes = {
            { n = G.UIT.R, config = { align = 'cr', padding = 0 }, nodes = {
                -- Flip-view button (label live-bound to view_label_ref.text).
                { n = G.UIT.C, config = {
                    align = 'cm', padding = 0.06, r = 0.08, minw = 1.25, minh = 0.42,
                    colour = G.C.BLUE, button = 'bc_toggle_view', hover = true, shadow = true,
                  }, nodes = {
                    { n = G.UIT.T, config = { ref_table = PB_UTIL.view_label_ref, ref_value = 'text',
                        scale = 0.3, colour = G.C.UI.TEXT_LIGHT } },
                  } },
                { n = G.UIT.C, config = { minw = 0.1 } },   -- gap
                -- Inventory button: opens the unified Inventory + Base modal.
                { n = G.UIT.C, config = {
                    align = 'cm', padding = 0.06, r = 0.08, minw = 1.4, minh = 0.42,
                    colour = G.C.GREEN, button = 'bc_open_inventory', hover = true, shadow = true,
                  }, nodes = {
                    { n = G.UIT.T, config = { text = 'Inventory', scale = 0.26, colour = G.C.UI.TEXT_LIGHT } },
                  } },
            } },
        },
    }
end

-- ---- UIBox lifecycle ----
-- 'tm' = outer-top + horizontal-middle: the bar's BOTTOM edge lands BAR_GAP above the consumable
-- area's top edge, centred over it. Bonded 'Weak' to G.consumeables (the stable anchor at that spot).
function PB_UTIL.attach_toggle_bar()
    if G.bc_toggle_bar and not G.bc_toggle_bar.REMOVED then G.bc_toggle_bar:remove() end
    G.bc_toggle_bar = UIBox {
        definition = PB_UTIL.build_toggle_bar(),
        config = { align = 'tm', offset = { x = 0, y = -BAR_GAP }, major = G.consumeables, bond = 'Weak' },
    }
    -- A new run recreates G.consumeables; 'Weak' bonds are NOT auto-removed with their major, so we
    -- rebuild when this no longer matches.
    G.bc_toggle_bar.bc_major = G.consumeables
end

local function remove_toggle_bar()
    if G.bc_toggle_bar and not G.bc_toggle_bar.REMOVED then G.bc_toggle_bar:remove() end
    G.bc_toggle_bar = nil
end

-- Show/hide a whole card area: its cards, its "n/2" count label, AND its draw-hash entry. The engine's
-- CardArea:draw() returns early when states.visible is false (cardarea.lua), so this also hides the
-- count label -- the two consumable areas share one footprint, so only the ACTIVE side's count must
-- ever show. (Per-card hiding would blank the cards but leave both count labels drawing on top of
-- each other -- the bug the user saw as a stray third "0/2".)
local function set_area_visible(area, vis)
    if not (area and area.states) then return end
    area.states.visible = vis
    if not vis and area.unhighlight_all then area:unhighlight_all() end
end

-- ---- Per-frame driver ----
function PB_UTIL.update_consumable_view()
    local active = G.STATE and PB_UTIL.PANEL_STATES[G.STATE]
        and G.consumeables and G.GAME and G.GAME.balacraft

    if not active then
        -- Tear the bar down and restore BOTH areas' visibility -- never leave a side hidden
        -- when our UI isn't on screen (menus, mid-animation states).
        remove_toggle_bar()
        set_area_visible(G.consumeables, true)
        set_area_visible(G.bc_mc_consumeables, true)
        return
    end

    -- Route any newly-granted MC consumables into the MC area / inventory before drawing.
    if PB_UTIL.reconcile_mc_consumables then PB_UTIL.reconcile_mc_consumables() end

    -- Pin the MC area exactly onto the vanilla consumable footprint. The engine's one-shot layout
    -- pass can't position it (it's created after set_screen_positions runs), so we mirror per frame.
    if PB_UTIL.sync_mc_consumable_area then PB_UTIL.sync_mc_consumable_area() end

    if not G.bc_toggle_bar or G.bc_toggle_bar.REMOVED
        or G.bc_toggle_bar.bc_major ~= G.consumeables then PB_UTIL.attach_toggle_bar() end

    local mc = PB_UTIL.get_view_mode() == 'minecraft'
    PB_UTIL.view_label_ref.text = mc and 'Vanilla' or 'Minecraft'
    -- Show ONLY the active side (cards + count label); hide the other entirely. Enforced each frame
    -- so a freshly-emplaced card or count change on the hidden side never flashes through.
    set_area_visible(G.consumeables, not mc)
    set_area_visible(G.bc_mc_consumeables, mc)
end

-- Flip the side. Persisted on G.GAME (remember-last within the run); the driver reflects the change
-- next tick (label + card visibility + highlight clear on the now-hidden side).
G.FUNCS.bc_toggle_view = function(e)
    PB_UTIL.set_view_mode(PB_UTIL.get_view_mode() == 'minecraft' and 'vanilla' or 'minecraft')
    play_sound('cardSlide1')
end

-- Open the unified Inventory + Base modal (defined in crafting_ui.lua). Guarded so it is inert
-- until that file is loaded.
G.FUNCS.bc_open_inventory = function(e)
    if PB_UTIL.open_inventory then PB_UTIL.open_inventory() else play_sound('cancel') end
end

-- Single per-frame hook: drive the consumable toggle, then maintain the unified modal (inventory
-- reflow/snap + recipe-square opacity; defined in crafting_ui.lua, which loads after this file).
-- Both pcall'd so a transient error can't wedge Game:update.
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
