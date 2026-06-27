-- Minecraft Inventory & Loadout -- UI half (logic lives in utilities/inventory.lua).
--
-- An "Items" button sits above the joker row, CENTERED between the health hearts (left) and the
-- hunger drumsticks (right) -- both bars span the joker width but hug their own side, leaving the
-- centre free (health_ui.lua / hunger_ui.lua use the same 'tm' anchor on G.jokers). Clicking it
-- opens a centered overlay with three rows:
--   ROW 1  active loadout : jokers (left)  | consumables (right)   -- the real G.jokers/G.consumeables
--   ROW 2  bench (dormant) : bench jokers   | bench consumables
--   ROW 3  resources grid + an "Open Crafting" button
-- Drag a card between any two same-kind slots to swap (drop on occupied = exchange). Editing is
-- only allowed in the SHOP and BLIND_SELECT states; during a blind the overlay opens read-only.
--
-- Build pattern mirrors the crafting modal: each slot is a single-cell 'title_2' CardArea embedded
-- via a UIT.O node; cards are snapped to slot centres each frame (title_2 has no auto-align). The
-- drag drop is handled by the shared Controller:L_cursor_release wrap in crafting_grid.lua, which
-- calls PB_UTIL.inventory_release (defined below) before its own crafting logic.

-- States where the button shows (mirror the hearts/hunger). Editing only in the two shop-side ones.
PB_UTIL.INV_STATES = {
    [G.STATES.SELECTING_HAND] = true,
    [G.STATES.DRAW_TO_HAND]   = true,
    [G.STATES.HAND_PLAYED]    = true,
    [G.STATES.SHOP]           = true,
    [G.STATES.BLIND_SELECT]   = true,
    [G.STATES.ROUND_EVAL]     = true,
}

function PB_UTIL.inv_editable()
    return (G.STATE == G.STATES.SHOP or G.STATE == G.STATES.BLIND_SELECT) and true or false
end

-- Tunables (tune in-game).
-- BTN_GAP lifts the button ABOVE the joker cards' click zone. The cards' collision boxes extend
-- above their visible tops and draw over the HUD, so a button level with the hearts (gap 0.12) is
-- covered except a thin top sliver; the cover reaches ~0.57 above the joker-area top. 0.6 is about
-- the LOWEST the button can sit and still be fully clickable -- below this the cards start eating
-- clicks again. Nudge up a hair if a tall joker still clips it.
local BTN_GAP   = 0.6
local CELL_W    = G.CARD_W   -- a card's footprint (jokers/consumables render at native size)
local CELL_H    = G.CARD_H
-- Each zone is ONE multi-card CardArea of FIXED width whose cards overlap/squeeze to fit, exactly
-- like the real joker/consumable rows -- title_2 IS handled by align_cards (cardarea.lua:100), and
-- SMODS does not override it. So a zone NEVER overflows: more cards just pack tighter into the same
-- width. Widths match the live areas (game.lua:2294-2296: joker_W=4.9*CARD_W, consumeable_W=2.3*
-- CARD_W) so the loadout reads at the same density as the normal view. Tune in-game.
local JOKER_ZONE_W = 4.9 * G.CARD_W
local CONS_ZONE_W  = 2.3 * G.CARD_W
-- The vanilla Sell/Use buttons stick out the RIGHT side of a card (~1u past its edge). A zone draws
-- its black frame in node order, so a button reaching into the next zone's frame is drawn over. Give
-- each zone a button-channel of empty space on both sides (gap between zones + outer margins) so the
-- side buttons have somewhere to draw -- the same reason the live joker/consumable rows sit apart.
local BTN_PAD = 1.1

-- ── The open button (bonded between the health and hunger bars) ────────────

function PB_UTIL.build_inventory_btn()
    -- COMPACT root = just the button. With align='tm' (top-middle of G.jokers) the box centres
    -- itself horizontally over the joker row; BTN_GAP lifts it above the health/hunger bars so it
    -- clears the joker cards' click zone (see BTN_GAP). The whole pill is one collidable node, so
    -- the entire visible button is the click target.
    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0, colour = G.C.CLEAR },
        nodes = {
            { n = G.UIT.C, config = {
                align = 'cm', padding = 0.1, r = 0.1, minw = 1.8, minh = 0.5,
                colour = G.C.PURPLE, button = 'bc_open_inventory', hover = true, shadow = true,
              }, nodes = {
                { n = G.UIT.T, config = { text = 'Inventory', scale = 0.32, colour = G.C.UI.TEXT_LIGHT } },
              } },
        },
    }
end

function PB_UTIL.attach_inventory_btn()
    if G.bc_inventory_btn and not G.bc_inventory_btn.REMOVED then G.bc_inventory_btn:remove() end
    G.bc_inventory_btn = UIBox {
        definition = PB_UTIL.build_inventory_btn(),
        config = { align = 'tm', offset = { x = 0, y = -BTN_GAP }, major = G.jokers, bond = 'Weak' },
    }
    -- Only the major identity is tracked: a 'Weak' bond isn't auto-removed when G.jokers is
    -- recreated (new run). The compact box re-centres over any width change via align_to_major
    -- with NO rebuild -- so (unlike the hearts) there is no width guard that could churn the
    -- button each frame and disrupt click tracking. Mirrors resource_ui's toggle-bar lifecycle.
    G.bc_inventory_btn.bc_major = G.jokers
end

local function remove_inventory_btn()
    if G.bc_inventory_btn and not G.bc_inventory_btn.REMOVED then G.bc_inventory_btn:remove() end
    G.bc_inventory_btn = nil
end

function PB_UTIL.update_inventory_btn()
    local active = G.STATE and PB_UTIL.INV_STATES[G.STATE]
        and PB_UTIL.inventory_enabled()
        and G.jokers and G.GAME and G.GAME.balacraft

    if not active then
        remove_inventory_btn()
        return
    end
    if not G.bc_inventory_btn or G.bc_inventory_btn.REMOVED
        or G.bc_inventory_btn.bc_major ~= G.jokers then
        PB_UTIL.attach_inventory_btn()
    end
end

-- ── Zones ──────────────────────────────────────────────────────────────────
-- PB_UTIL.loadout_cells : the four zone descriptors { area, kind, zone } (zone = 'active'|'bench').
-- PB_UTIL.inv_zone      : the same four, keyed <kind>_<zone>, for build + close.
-- Each zone is ONE multi-card title_2 CardArea (NOT a row of single-card cells): its cards overlap
-- to fit a fixed width via vanilla align_cards, so the row never widens off-screen.
-- NB: DELIBERATELY named loadout_cells, NOT inv_cells -- crafting_grid.lua owns a global
-- PB_UTIL.inv_cells (resource slots) whose update_inventory() runs every frame; reusing the name
-- let that updater corrupt our zones (a resource icon leaked into the first joker slot).

-- A joker/consumable counts against its area's cap UNLESS it is Negative: Negative cards bring
-- their own slot, so they're "free" in BOTH the active loadout and the bench. Mirrors how the live
-- card_limit floats (+1 per negative joker present; set_edition / add_to_deck in card.lua).
local function card_is_negative(card)
    return (card and card.edition and card.edition.negative) and true or false
end

-- The card in `area` whose centre is nearest the cursor x (which overlapped card you grabbed).
local function nearest_card(area)
    local best, bestd
    local cx = G.CURSOR.T.x
    for _, c in ipairs(area.cards) do
        local d = math.abs((c.T.x + c.T.w / 2) - cx)
        if not bestd or d < bestd then best, bestd = c, d end
    end
    return best
end

-- Count NON-negative cards in a zone's area, optionally skipping one (the card about to leave it).
local function zone_nonneg(entry, except)
    local n = 0
    for _, c in ipairs(entry.area.cards) do
        if c ~= except and not card_is_negative(c) then n = n + 1 end
    end
    return n
end

-- How many NON-negative cards a zone may hold. Active = the base limit (slots with zero negatives,
-- captured at open); bench = the flat bench cap. Negatives never consume a slot in either area.
local function zone_cap(entry)
    if entry.zone == 'active' then
        return (PB_UTIL.inv_base_limit and PB_UTIL.inv_base_limit[entry.kind]) or 99
    end
    return PB_UTIL.bench_cap(entry.kind)   -- base + Chest station bonus
end

local function make_zone_area(kind)
    local w = (kind == 'joker') and JOKER_ZONE_W or CONS_ZONE_W
    -- type='joker' (NOT title_2) so clicking a card HIGHLIGHTS it and the vanilla pop-out buttons
    -- appear: Sell on jokers, Use+Sell on consumables (Card:highlight -> G.UIDEF.use_and_sell_buttons;
    -- the Sell node needs area type 'joker', the Use node needs card.ability.consumeable -- and
    -- can_highlight only passes for joker/consumeable/hand types). A joker area still overlaps via the
    -- same align_cards branch (cardarea.lua:100) and keeps drag enabled (set_ranks else-branch).
    -- bg_colour transparent + no_card_count hide the faint box + 'N/M' label a joker area would
    -- otherwise draw (cardarea.lua:313-323), so only our own zone frame shows.
    -- READ-ONLY (mid-blind) zones stay title_2: no highlight => no buttons, so the display copies
    -- can't be sold/used (that would be a dupe / free-money exploit); the sell/use wraps also guard.
    local atype = PB_UTIL.inv_readonly and 'title_2' or 'joker'
    -- align_buttons=true makes the pop-out Sell/Use buttons stick out the card's SIDE ('cr') instead
    -- of below it ('bmi') -- exactly how the live joker/consumable rows do it (game.lua:2339-2340).
    return CardArea(G.ROOM.T.x, G.ROOM.T.y, w, CELL_H,
        { card_limit = 64, type = atype, highlight_limit = 1, card_w = CELL_W, no_card_count = true,
          align_buttons = true, bg_colour = { 0, 0, 0, 0 } })
end

local function zone_node(area, w)
    return {
        n = G.UIT.C,
        config = { align = 'cm', padding = 0.04, minw = w + 0.1, minh = CELL_H + 0.1,
                   r = 0.06, colour = G.C.UI.TRANSPARENT_DARK },
        nodes = { { n = G.UIT.O, config = { object = area } } },
    }
end

-- Move `card` into `entry`'s area and tag it with its zone. align_cards (per-frame) positions and
-- overlaps it; no manual snap needed.
local function place_in_zone(card, entry)
    if card.area then card.area:remove_card(card) end
    if card.highlighted then card:highlight(false) end   -- drop any pop-out buttons before re-placing
    card.states.drag.is = false
    -- Force visible: a real consumable pulled from G.consumeables may be states.visible=false when
    -- the hotbar is in 'resources' view (resource_ui.lua hides them); it must show in our zone.
    card.states.visible = true
    entry.area:emplace(card)
    card.bc_inv_zone = entry
end

-- ── Open ──────────────────────────────────────────────────────────────────

function PB_UTIL.open_inventory()
    if PB_UTIL.inv_open then return end
    -- Set the flag up front so that if anything below throws, the caller's recovery (or the
    -- defensive Game:update close) runs close_inventory and restores any cards already moved
    -- out of G.jokers into cells -- they're never stranded.
    PB_UTIL.inv_open = true
    PB_UTIL.ensure_bench()
    PB_UTIL.inv_readonly = not PB_UTIL.inv_editable()

    -- Base (negative-free) capacity of each active area, captured BEFORE we move cards out: the
    -- live card_limit already includes +1 per negative currently present, so subtract them back
    -- out. A cross-zone swap is later rejected if it would push an area's NON-negative count past
    -- this -- so a swap can never leave the active loadout over its real limit (the 6/5 bug).
    local function count_neg(area)
        local n = 0
        if area and area.cards then for _, c in ipairs(area.cards) do if card_is_negative(c) then n = n + 1 end end end
        return n
    end
    PB_UTIL.inv_base_limit = {
        joker      = (((G.jokers and G.jokers.config.card_limit) or 5) - count_neg(G.jokers)),
        consumable = (((G.consumeables and G.consumeables.config.card_limit) or 2) - count_neg(G.consumeables)),
    }

    PB_UTIL.loadout_cells = {}
    PB_UTIL.inv_zone  = {}
    local function add_zone(zonekey, kind, zone)
        -- label_ref.count is the live 'N/M' shown under the zone; update_inventory_overlay keeps it
        -- current (M = the negative-aware slot count, so the player sees why a drag is/ isn't allowed).
        local entry = { area = make_zone_area(kind), kind = kind, zone = zone, label_ref = { count = '' } }
        PB_UTIL.loadout_cells[#PB_UTIL.loadout_cells + 1] = entry
        PB_UTIL.inv_zone[zonekey] = entry
    end
    add_zone('joker_active',      'joker',      'active')
    add_zone('consumable_active', 'consumable', 'active')
    add_zone('joker_bench',       'joker',      'bench')
    add_zone('consumable_bench',  'consumable', 'bench')

    -- Active zones: editable -> move the REAL cards in (so edits persist); read-only -> show
    -- display copies and leave G.jokers/G.consumeables untouched (safe to open mid-blind).
    local function fill_active(srcarea, zonekey)
        if not (srcarea and srcarea.cards) then return end
        local entry = PB_UTIL.inv_zone[zonekey]
        local src = {}
        for _, c in ipairs(srcarea.cards) do src[#src + 1] = c end   -- snapshot; we mutate cards
        for _, c in ipairs(src) do
            if PB_UTIL.inv_readonly then
                local copy = PB_UTIL.materialize_bench_card(c:save())
                if copy then place_in_zone(copy, entry) end
            else
                place_in_zone(c, entry)
            end
        end
    end
    fill_active(G.jokers,      'joker_active')
    fill_active(G.consumeables, 'consumable_active')

    -- Bench zones: materialize the serialized descriptors into live cards (both modes).
    local function fill_bench(kind, zonekey)
        local entry = PB_UTIL.inv_zone[zonekey]
        for _, saved in ipairs(PB_UTIL.bench_list(kind)) do
            local card = PB_UTIL.materialize_bench_card(saved)
            if card then place_in_zone(card, entry) end
        end
    end
    fill_bench('joker',      'joker_bench')
    fill_bench('consumable', 'consumable_bench')

    G.FUNCS.overlay_menu { definition = PB_UTIL.build_inventory_modal() }
end

-- ── Close (reconcile + persist) ───────────────────────────────────────────

function PB_UTIL.close_inventory()
    if not PB_UTIL.inv_open then return end
    PB_UTIL.inv_open = false   -- set first so the defensive re-entry / exit-wrap can't double-run

    -- A throw during open() can leave us flagged-open with no zones built yet; nothing to reconcile.
    if not (PB_UTIL.loadout_cells and PB_UTIL.inv_zone) then
        PB_UTIL.loadout_cells = nil; PB_UTIL.inv_zone = nil
        PB_UTIL.inv_readonly = nil; PB_UTIL.inv_base_limit = nil
        return
    end

    -- Release any card the player is mid-dragging so the loops below find it settled in its zone
    -- (clear drag.is too, or it would emplace into G.jokers still flagged as being dragged).
    local C = G.CONTROLLER
    if C and C.dragging and C.dragging.target and C.dragging.target.bc_inv_zone then
        C.dragging.target.states.drag.is = false
        C.dragging.target = nil
        C.dragging.prev_target = nil
    end

    -- Drop any highlighted card's pop-out Sell/Use buttons before cards change areas (else the
    -- button child would linger on a card now back in G.jokers).
    for _, entry in ipairs(PB_UTIL.loadout_cells) do
        if entry.area and entry.area.unhighlight_all then entry.area:unhighlight_all() end
    end

    -- Snapshot a zone's cards in array order (= the player's left-to-right arrangement, since
    -- align_cards keeps the array x-sorted); we mutate area.cards as we drain it.
    local function cards_of(entry)
        local out = {}
        for _, c in ipairs(entry.area.cards) do out[#out + 1] = c end
        return out
    end

    if not PB_UTIL.inv_readonly then
        -- Active zones -> back into the real areas IN ORDER, re-activating any that were benched.
        -- Emplacing in array order preserves the player's joker scoring order.
        local function restore_active(zonekey, dest)
            local entry = PB_UTIL.inv_zone[zonekey]
            for _, c in ipairs(cards_of(entry)) do
                if not c.added_to_deck then c:add_to_deck() end
                entry.area:remove_card(c)
                c.bc_inv_zone = nil
                dest:emplace(c)
            end
        end
        restore_active('joker_active',      G.jokers)
        restore_active('consumable_active', G.consumeables)

        -- Bench zones -> serialized descriptors, deactivating any that were active.
        local function collect_bench(zonekey)
            local entry = PB_UTIL.inv_zone[zonekey]
            local out = {}
            for _, c in ipairs(cards_of(entry)) do
                if c.added_to_deck then c:remove_from_deck() end
                out[#out + 1] = c:save()
                c:remove()
            end
            return out
        end
        local bench = PB_UTIL.ensure_bench()
        bench.jokers      = collect_bench('joker_bench')
        bench.consumables = collect_bench('consumable_bench')
    else
        -- Read-only: every card in a zone is a display copy. Free them; the real areas and the
        -- bench descriptors were never touched.
        for _, entry in ipairs(PB_UTIL.loadout_cells) do
            for _, c in ipairs(cards_of(entry)) do c:remove() end
        end
    end

    for _, entry in ipairs(PB_UTIL.loadout_cells) do
        if entry.area then entry.area:remove() end
    end
    PB_UTIL.loadout_cells  = nil
    PB_UTIL.inv_zone       = nil
    PB_UTIL.inv_readonly   = nil
    PB_UTIL.inv_base_limit = nil
end

-- ── Drag / swap (called from the shared L_cursor_release wrap in crafting_grid.lua) ──
-- Returns true if it handled the drop (so the crafting branch is skipped). Mirrors the crafting
-- drop's controller-ref nulling: nulling dragging.target here WINS over native released_on, which
-- only reads prev_target on the NEXT update tick (see crafting_grid.lua:299-308 for the rationale).

function PB_UTIL.inventory_release(self, dropped, x, y)
    if not (PB_UTIL.inv_open and not PB_UTIL.inv_readonly) then return false end
    if not (dropped and dropped.is and dropped:is(Card)) then return false end
    local src = dropped.bc_inv_zone
    if not src then return false end           -- not one of our cards: let other handlers run
    local kind = src.kind

    local function finish()
        self.dragging.target = nil
        self.dragging.prev_target = nil
        return true
    end

    -- The same-kind zone under the cursor (active & bench differ in Y, so this is unambiguous).
    local target
    for _, entry in ipairs(PB_UTIL.loadout_cells) do
        if entry.kind == kind and entry.area:collides_with_point(G.CURSOR.T) then target = entry; break end
    end

    -- Same zone (a reorder -- align_cards already did it live via its x-sort) or dropped off any
    -- zone: nothing to move; just release and let align_cards settle the card.
    if not target or target == src then
        dropped.states.drag.is = false
        return finish()
    end

    -- Cross-zone. A negative card is "free" (consumes no slot). Prefer a MOVE; if the target is
    -- full, swap with the nearest card there; if neither keeps BOTH areas within their caps,
    -- reject (snap back) -- so a swap can never leave an area over its limit.
    local nd = card_is_negative(dropped) and 0 or 1
    if zone_nonneg(target) + nd <= zone_cap(target) then
        place_in_zone(dropped, target)
        play_sound('cardSlide1')
        return finish()
    end

    local occ = nearest_card(target.area)
    if occ then
        local no = card_is_negative(occ) and 0 or 1
        local new_target = zone_nonneg(target, occ) + nd   -- target loses occ, gains dropped
        local new_src    = zone_nonneg(src, dropped) + no  -- src loses dropped, gains occ
        if new_target <= zone_cap(target) and new_src <= zone_cap(src) then
            place_in_zone(dropped, target)   -- place_in_zone detaches each card from its old area
            place_in_zone(occ, src)
            play_sound('cardSlide1')
            return finish()
        end
    end

    dropped.states.drag.is = false             -- would overflow an area: leave it where it was
    play_sound('cancel')
    return finish()
end

-- ── Sell / use (the card's pop-out buttons, plus right-click as a shortcut) ───────
-- Clicking a card highlights it and shows the vanilla buttons (see make_zone_area); their callbacks
-- (G.FUNCS.sell_card / use_card) are wrapped below to route our cards here. Right-click sells too.
-- inventory_sell credits sell_cost and frees the card in place (overlay stays open). NOTE: on-sell
-- joker effects aren't triggered in this v1 (the card isn't scored from a real G.jokers slot).

function PB_UTIL.inventory_sell(card)
    if not card then return end
    -- Respect eternal (bench cards bypass Card:can_sell_card's own area check, so re-check here).
    if SMODS and SMODS.is_eternal and SMODS.is_eternal(card, { from_sell = true }) then
        play_sound('cancel'); return
    end
    if card.highlighted then card:highlight(false) end
    if card.added_to_deck then card:remove_from_deck() end
    ease_dollars(card.sell_cost or 1)
    if card.area then card.area:remove_card(card) end
    card.bc_inv_zone = nil
    play_sound('cardSlide1')
    pcall(play_sound, 'coin1', 1)
    card:remove()
end

-- Use a consumable from the inventory. A consumable's effect needs the LIVE game state, but while
-- the overlay is open the real cards are held OUT of G.jokers/G.consumeables/G.hand -- so we detach
-- this card, reconcile + close the overlay (restoring everyone else), then drop it into the live
-- G.consumeables and run the normal use flow. Works for an active OR a benched consumable (a bench
-- one is effectively promoted, then consumed). Deferred a beat so the overlay teardown settles.
function PB_UTIL.inventory_use(card)
    if not (card and card.ability and card.ability.consumeable) then return end
    -- Deferred: closing the overlay tears down nodes the controller is still mid-clicking on, so let
    -- this click finish first. Then detach the card, reconcile+close, and run the normal use flow.
    G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.05, func = function()
        if card.highlighted then card:highlight(false) end
        if card.area then card.area:remove_card(card) end   -- detach so close() won't reconcile it
        card.bc_inv_zone = nil
        PB_UTIL.close_inventory()                            -- restore the rest of the loadout + bench
        pcall(function() if G.FUNCS.exit_overlay_menu then G.FUNCS.exit_overlay_menu() end end)
        if G.consumeables then
            G.consumeables:emplace(card)                     -- live area (over-limit emplace is fine)
            G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.06, func = function()
                pcall(G.FUNCS.use_card, { config = { ref_table = card } })
                return true
            end }))
        end
        return true
    end }))
end

-- Route the vanilla Sell / Use button callbacks to the inventory handlers when the clicked card is
-- one of ours (tagged bc_inv_zone) and we're editing; otherwise fall through to the base game.
-- The button-ENABLED gates (can_sell_card / can_use_consumeable) are left vanilla: can_sell_card
-- already passes for a joker-type area + non-eternal, and can_use_consumeable returns true only for
-- consumables actually usable in the current shop/blind-select state -- exactly the "when possible".
if not PB_UTIL._inv_button_hooked then
    PB_UTIL._inv_button_hooked = true
    local _orig_sell = G.FUNCS.sell_card
    G.FUNCS.sell_card = function(e)
        local card = e and e.config and e.config.ref_table
        if card and card.bc_inv_zone and PB_UTIL.inv_open and not PB_UTIL.inv_readonly then
            return PB_UTIL.inventory_sell(card)
        end
        return _orig_sell(e)
    end
    local _orig_use = G.FUNCS.use_card
    G.FUNCS.use_card = function(e, ...)
        local card = e and e.config and e.config.ref_table
        if card and card.bc_inv_zone and PB_UTIL.inv_open and not PB_UTIL.inv_readonly then
            return PB_UTIL.inventory_use(card)
        end
        return _orig_use(e, ...)
    end
end

if not PB_UTIL._inv_rclick_hooked then
    PB_UTIL._inv_rclick_hooked = true
    local _orig_rpress = Controller.queue_R_cursor_press
    function Controller:queue_R_cursor_press(qx, qy)
        if PB_UTIL.inv_open and not PB_UTIL.inv_readonly and PB_UTIL.loadout_cells then
            for _, entry in ipairs(PB_UTIL.loadout_cells) do
                if entry.area.cards[1] and entry.area:collides_with_point(G.CURSOR.T) then
                    local card = nearest_card(entry.area)   -- the overlapped card under the cursor
                    if card then PB_UTIL.inventory_sell(card); return end
                end
            end
        end
        return _orig_rpress(self, qx, qy)
    end
end

-- ── Overlay definition ────────────────────────────────────────────────────

-- Resource grid + Open Crafting button (row 3). Reuses the hotbar's dimmable-icon + live-count
-- pattern (resource_ui.lua:99-124). Guards on the resource atlas so it's inert when resources are off.
-- How many resource icon cells per row in the Inventory modal's resource grid (it's a wide modal,
-- minw=14). The resources wrap onto multiple rows like the crafting-table inventory grid rather
-- than stretching out in a single line.
local INV_RES_PER_ROW = 10

function PB_UTIL.build_inv_resource_row()
    local atlas = PB_UTIL.icon_atlas and G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]
    local store = (G.GAME.balacraft and G.GAME.balacraft.resources) or {}
    -- Build each resource icon cell, then chunk them into rows of INV_RES_PER_ROW for a grid.
    local cells = {}
    if atlas then
        for _, r in ipairs(PB_UTIL.RESOURCES or {}) do
            local count = store[r.id] or 0
            if r.kind == 'gathered' or count > 0 then
                local owned = count > 0
                local spr = PB_UTIL.make_dimmable(Sprite(0, 0, 0.5, 0.5, atlas, r.pos))
                if not owned then spr.bc_overlay[4] = 0.35 end
                cells[#cells + 1] = {
                    n = G.UIT.C, config = { align = 'cm', padding = 0.04 },
                    nodes = {
                        { n = G.UIT.R, config = { align = 'cm' }, nodes = { { n = G.UIT.O, config = { object = spr } } } },
                        { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                            { n = G.UIT.T, config = { ref_table = store, ref_value = r.id, scale = 0.3,
                                colour = owned and G.C.WHITE or G.C.UI.TEXT_INACTIVE } },
                        } },
                    },
                }
            end
        end
    end
    -- Chunk the flat cell list into rows of INV_RES_PER_ROW (the grid).
    local grid_rows = {}
    for i = 1, #cells, INV_RES_PER_ROW do
        local row = { n = G.UIT.R, config = { align = 'cm', padding = 0.02 }, nodes = {} }
        for j = i, math.min(i + INV_RES_PER_ROW - 1, #cells) do
            row.nodes[#row.nodes + 1] = cells[j]
        end
        grid_rows[#grid_rows + 1] = row
    end

    local left = {
        n = G.UIT.C, config = { align = 'cm', padding = 0.04 }, nodes = {
            { n = G.UIT.R, config = { align = 'cm' }, nodes = { { n = G.UIT.T, config = { text = 'Resources', scale = 0.3, colour = G.C.UI.TEXT_LIGHT } } } },
            { n = G.UIT.C, config = { align = 'cm' }, nodes = grid_rows },
        },
    }
    local nodes = { left }
    -- Open Crafting only when the crafting table exists (resources enabled).
    if PB_UTIL.open_crafting_table then
        nodes[#nodes + 1] = { n = G.UIT.C, config = { minw = 0.4 } }
        nodes[#nodes + 1] = {
            n = G.UIT.C, config = { align = 'cm', padding = 0.1, r = 0.1, minw = 1.9,
                colour = G.C.GREEN, button = 'bc_inv_open_crafting', hover = true, shadow = true },
            nodes = { { n = G.UIT.T, config = { text = 'Open Crafting', scale = 0.3, colour = G.C.UI.TEXT_LIGHT } } },
        }
    end
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.06, r = 0.1, colour = G.C.BLACK }, nodes = nodes }
end

function PB_UTIL.build_inventory_modal()
    -- One labelled box per zone: title on top, the overlapping card area in the middle, and a live
    -- 'N/M' count underneath (like the live joker/consumable rows) so the player can see capacity.
    local function zone_box(label, entry, w)
        return {
            n = G.UIT.C, config = { align = 'tm', padding = 0.06, r = 0.1, colour = G.C.BLACK },
            nodes = {
                { n = G.UIT.R, config = { align = 'cm' }, nodes = { { n = G.UIT.T, config = { text = label, scale = 0.3, colour = G.C.UI.TEXT_LIGHT } } } },
                { n = G.UIT.R, config = { align = 'cm' }, nodes = { zone_node(entry.area, w) } },
                { n = G.UIT.R, config = { align = 'cm', minh = 0.34 }, nodes = {
                    { n = G.UIT.T, config = { ref_table = entry.label_ref, ref_value = 'count', scale = 0.36, colour = G.C.UI.TEXT_LIGHT } },
                } },
            },
        }
    end
    local function pad() return { n = G.UIT.C, config = { minw = BTN_PAD } } end

    -- ROW 1 active: jokers left | consumables right. The pad() columns are the side-button channels.
    local active_row = { n = G.UIT.R, config = { align = 'cm', padding = 0.06 }, nodes = {
        pad(),
        zone_box('Jokers', PB_UTIL.inv_zone.joker_active, JOKER_ZONE_W),
        pad(),
        zone_box('Consumables', PB_UTIL.inv_zone.consumable_active, CONS_ZONE_W),
        pad(),
    } }
    -- ROW 2 bench: same split, dormant cards.
    local bench_row = { n = G.UIT.R, config = { align = 'cm', padding = 0.06 }, nodes = {
        pad(),
        zone_box('Bench Jokers', PB_UTIL.inv_zone.joker_bench, JOKER_ZONE_W),
        pad(),
        zone_box('Bench Items', PB_UTIL.inv_zone.consumable_bench, CONS_ZONE_W),
        pad(),
    } }

    local hint_text = PB_UTIL.inv_readonly
        and 'View only during a blind -- swap in the shop or at blind select'
        or  'Drag onto the other area to move/swap. Click a card for Sell/Use buttons (right-click sells).'

    local close_btn = {
        n = G.UIT.R, config = { align = 'cm', minw = 8, padding = 0.1, r = 0.1, hover = true,
            colour = G.C.ORANGE, button = 'exit_overlay_menu', shadow = true },
        nodes = { { n = G.UIT.T, config = { text = 'Close', scale = 0.5, colour = G.C.WHITE } } },
    }

    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0.1, r = 0.1, colour = G.C.GREY, minw = 14, minh = 5 },
        nodes = {
            { n = G.UIT.R, config = { align = 'cm' }, nodes = { { n = G.UIT.T, config = { text = 'Inventory', scale = 0.5, colour = G.C.UI.TEXT_LIGHT } } } },
            active_row,
            bench_row,
            PB_UTIL.build_inv_resource_row(),
            { n = G.UIT.R, config = { align = 'cm', padding = 0.02 }, nodes = { { n = G.UIT.T, config = { text = hint_text, scale = 0.3, colour = G.C.UI.TEXT_INACTIVE } } } },
            close_btn,
        },
    }
end

-- ── Per-frame: overlap each zone's cards across its fixed width (vanilla align_cards) ──
-- align_cards spreads/overlaps the non-dragged cards (title_2 branch, cardarea.lua:100) AND keeps
-- the array x-sorted (so dragging a card sideways reorders it live, like the real joker row). VT is
-- then hard-set to T for the settled cards so they never interpolate in from the throwaway spawn
-- origin (corner flash); the dragged card is skipped so it follows the cursor.
function PB_UTIL.update_inventory_overlay()
    if not PB_UTIL.loadout_cells then return end
    local C = G.CONTROLLER
    local dragged = C and C.dragging and C.dragging.target
    for _, entry in ipairs(PB_UTIL.loadout_cells) do
        local area = entry.area
        if area and area.cards then
            area:align_cards()
            for _, card in ipairs(area.cards) do
                if card ~= dragged and not (card.states and card.states.drag.is) then
                    card.VT.x, card.VT.y = card.T.x, card.T.y
                end
            end
            -- Live 'N/M': M is the negative-aware capacity (slot cap + the free slots the negatives
            -- present bring), so N never exceeds M and 'full' reads correctly even with negatives.
            if entry.label_ref then
                local n = #area.cards
                local negs = n - zone_nonneg(entry)
                entry.label_ref.count = n .. '/' .. (zone_cap(entry) + negs)
            end
        end
    end
end

-- ── Button callbacks ──────────────────────────────────────────────────────

G.FUNCS.bc_open_inventory = function(e)
    -- Diagnostic: confirms the click reaches the handler, and turns a silent failure inside the
    -- open path into a logged error (pcall) instead of a swallowed crash. Visible in the
    -- Steamodded console as a [BalaCraft] line.
    sendDebugMessage('inventory button clicked (inv_open=' .. tostring(PB_UTIL.inv_open)
        .. ', state=' .. tostring(G.STATE) .. ')', 'BalaCraft')
    local ok, err = pcall(PB_UTIL.open_inventory)
    if not ok then
        sendDebugMessage('open_inventory ERROR: ' .. tostring(err), 'BalaCraft')
        pcall(PB_UTIL.close_inventory)   -- restore any cards already moved into cells; clears flags
    end
end

-- Open Crafting from inside the inventory: close (reconcile + persist) first, then open the
-- crafting modal, which replaces the overlay. close before open so cards are back in G.jokers and
-- the cell areas are gone before the crafting table builds its own.
G.FUNCS.bc_inv_open_crafting = function(e)
    if PB_UTIL.inv_open then PB_UTIL.close_inventory() end
    if PB_UTIL.open_crafting_table then PB_UTIL.open_crafting_table() end
end

-- Reconcile the loadout whenever ANY overlay close path runs while the inventory is open (Close
-- button, ESC, or a forced close). Stacks on top of the crafting exit wrap (crafting_ui.lua).
if not PB_UTIL._inv_exit_hooked then
    PB_UTIL._inv_exit_hooked = true
    local _orig_exit = G.FUNCS.exit_overlay_menu
    G.FUNCS.exit_overlay_menu = function(...)
        if PB_UTIL.inv_open then PB_UTIL.close_inventory() end
        return _orig_exit(...)
    end
end

-- ── Per-frame driver (stacked Game:update wrap, like health_ui.lua) ───────
local _game_update = Game.update
function Game:update(dt)
    _game_update(self, dt)
    local ok, err = pcall(PB_UTIL.update_inventory_btn)
    if not ok then sendDebugMessage('inv btn error: ' .. tostring(err), 'BalaCraft') end
    if PB_UTIL.inv_open then
        local ok2, err2 = pcall(PB_UTIL.update_inventory_overlay)
        if not ok2 then sendDebugMessage('inv overlay error: ' .. tostring(err2), 'BalaCraft') end
        -- Defensive: if the overlay vanished by some path that didn't run our exit wrap, close so
        -- the real cards aren't stranded out of G.jokers.
        if not G.OVERLAY_MENU then pcall(PB_UTIL.close_inventory) end
    end
end
