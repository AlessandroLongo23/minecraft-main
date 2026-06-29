-- Minecraft consumable area + classification.
--
-- The vanilla consumable area (G.consumeables) keeps Tarot / Planet / Spectral and still grows via
-- vouchers. Minecraft consumables (tools / food / enchant books) live in a SEPARATE, fixed 2-slot
-- area, G.bc_mc_consumeables, created here via SMODS' custom_card_areas hook. Both areas share the
-- same on-screen footprint; a toggle (utilities/resource_ui.lua) flips which one is visible.
--
-- Persistence is automatic: save_run() (misc_functions.lua) iterates EVERY CardArea on G and saves
-- it, and custom_card_areas runs again on load to re-instantiate the area before its cards load back
-- in. So the equipped slots need no manual serialization (unlike the inventory's `stored` list).

-- The Minecraft consumable types. Anything whose center set is one of these is "MC themed"
-- and belongs in the MC area / inventory (never the vanilla consumable area).
PB_UTIL.MC_CONSUMABLE_SETS = {
    balacraft_tool    = true,
    balacraft_food    = true,
    balacraft_enchant = true,
    balacraft_sheet   = true,   -- Sheets (forged at the Anvil), applied to a card like a Tarot
    balacraft_potion  = true,   -- Potions (brewed at the Brewing Stand; drink / throw)
}

function PB_UTIL.is_mc_consumable_set(set)
    return set ~= nil and PB_UTIL.MC_CONSUMABLE_SETS[set] == true
end

-- Classify a live Card.
function PB_UTIL.is_mc_consumable_card(card)
    return card and card.ability and PB_UTIL.is_mc_consumable_set(card.ability.set) or false
end

-- Classify a center KEY (e.g. 'c_balacraft_tool_sword_wood') -- used by consumable_add, which is
-- given a key string. Reads the registered center's set.
function PB_UTIL.is_mc_consumable_key(key)
    local center = key and G.P_CENTERS[key]
    return center and PB_UTIL.is_mc_consumable_set(center.set) or false
end

-- The MC consumable area (nil until a run is started). Capacity is a hard 2 for now.
PB_UTIL.MC_SLOTS = 2

function PB_UTIL.mc_area()
    return G.bc_mc_consumeables
end

function PB_UTIL.mc_has_room()
    local a = PB_UTIL.mc_area()
    return a and a.config and (#a.cards < (a.config.card_limit or PB_UTIL.MC_SLOTS)) or false
end

-- ---- Area creation (SMODS custom_card_areas) ----
-- Chained defensively in case another hook is ever added. Mirrors G.consumeables' config
-- (type='joker', highlight_limit=1, negative_info) so the base game's Use/Sell buttons appear for a
-- highlighted MC consumable automatically (Card:highlight gates on ability.consumeable, not on the
-- specific area), and so a card here behaves exactly like one in the vanilla area when used.
--
-- align_buttons=true is REQUIRED for the Use/Sell buttons to sit to the RIGHT of the card ("cr" in
-- Card:highlight) like vanilla consumables. Without it they fall back to "bmi" -- Use below the card,
-- Sell hidden behind it. The base game sets this flag directly on G.jokers/G.consumeables in
-- Game:start_run (game.lua) but only on its own areas, so our custom area must set it itself.
local _prev_custom_areas = SMODS.current_mod.custom_card_areas
SMODS.current_mod.custom_card_areas = function(game)
    if _prev_custom_areas then _prev_custom_areas(game) end
    local w = (game.consumeables and game.consumeables.T.w) or (2.3 * G.CARD_W)
    local h = (game.consumeables and game.consumeables.T.h) or (0.95 * G.CARD_H)
    game.bc_mc_consumeables = CardArea(0, 0, w, h, {
        card_limit = PB_UTIL.MC_SLOTS, type = 'joker', highlight_limit = 1,
        negative_info = 'consumable', align_buttons = true,
    })
end

-- ---- Inventory storage (serialize / materialize) ----
-- Equipped MC consumables are live cards in G.bc_mc_consumeables (auto-persisted by save_run).
-- STORED ones live as serialized card:save() tables in G.GAME.balacraft.inv.stored and are drawn as
-- icons in the Inventory modal. Moving between the two serializes / materializes.

-- Serialize a live Minecraft consumable into the inventory's stored list, then remove the live card.
function PB_UTIL.store_consumable_card(card)
    if not card then return false end
    local bcs = G.GAME and G.GAME.balacraft
    if not (bcs and bcs.inv) then return false end
    bcs.inv.stored = bcs.inv.stored or {}
    bcs.inv.stored[#bcs.inv.stored + 1] = card:save()
    if card.area then card.area:remove_card(card) end
    card:remove()
    bcs._panel_dirty = true
    return true
end

-- Rebuild a live Card from a stored (serialized) Minecraft consumable. Mirrors the proven bench
-- materialize: a throwaway placeholder center, then :load() swaps in the saved center + ability.extra
-- (durability / enchants for tools). Returns the live card (NOT yet emplaced) or nil if its center is
-- gone (e.g. that content was disabled).
function PB_UTIL.materialize_stored_consumable(saved)
    if not (saved and saved.save_fields and saved.save_fields.center
            and G.P_CENTERS[saved.save_fields.center]) then
        return nil
    end
    saved = copy_table(saved) or saved
    loading = true
    local card = Card(0, 0, G.CARD_W, G.CARD_H, G.P_CENTERS.j_joker, G.P_CENTERS.c_base)
    loading = nil
    card:load(saved)
    return card
end

-- ---- Per-frame reconcile (acquire routing) ----
-- Every grant path (consumable_add, shop buy, pack pick with select_card='consumeables') drops the
-- new MC consumable into the VANILLA area first. This sweep moves it to a free MC slot (auto-equip),
-- else into the inventory (store), else leaves it in place to retry next frame -- so a granted item is
-- never silently lost when both are full. Also drains any MC-area overflow (multiple pack picks) into
-- the inventory. Called from the consumable-toggle driver (resource_ui.lua) while in a PANEL state.
function PB_UTIL.reconcile_mc_consumables()
    local mc = G.bc_mc_consumeables
    if not mc then return end
    -- 1) Evict MC consumables that landed in the vanilla area.
    local van = G.consumeables
    if van and van.cards then
        for i = #van.cards, 1, -1 do
            local c = van.cards[i]
            if PB_UTIL.is_mc_consumable_card(c) then
                if PB_UTIL.mc_has_room() then
                    van:remove_card(c); mc:emplace(c)
                elseif PB_UTIL.inv_can_fit_consumable and PB_UTIL.inv_can_fit_consumable() then
                    PB_UTIL.store_consumable_card(c)
                end
            end
        end
    end
    -- 2) Drain any MC-area overflow beyond the 2 slots into the inventory.
    local limit = (mc.config and mc.config.card_limit) or PB_UTIL.MC_SLOTS
    local guard = 0
    while #mc.cards > limit and guard < 8 do
        guard = guard + 1
        if not (PB_UTIL.inv_can_fit_consumable and PB_UTIL.inv_can_fit_consumable()) then break end
        PB_UTIL.store_consumable_card(mc.cards[#mc.cards])
    end
end

-- Equip the stored consumable at inv.stored[index]: materialize it and emplace into a free MC slot.
-- No-op (returns false) if the MC slots are full or the index is invalid. Used by the Inventory modal.
function PB_UTIL.equip_stored_consumable(index)
    local bcs = G.GAME and G.GAME.balacraft
    local stored = bcs and bcs.inv and bcs.inv.stored
    if not (stored and stored[index]) then return false end
    if not PB_UTIL.mc_has_room() then return false end
    local card = PB_UTIL.materialize_stored_consumable(stored[index])
    if not card then return false end
    card.added_to_deck = true
    table.remove(stored, index)
    G.bc_mc_consumeables:emplace(card)
    bcs._panel_dirty = true
    return true
end

-- Un-equip a live MC consumable card (serialize it back into the inventory). Thin wrapper over
-- store_consumable_card with an inventory-capacity guard. Used by the Inventory modal.
function PB_UTIL.unequip_mc_consumable(card)
    if not card then return false end
    if not (PB_UTIL.inv_can_fit_consumable and PB_UTIL.inv_can_fit_consumable()) then return false end
    return PB_UTIL.store_consumable_card(card)
end

-- A small icon Sprite for a center (tool / food / book / resource etc.), sized `sz`. Uses the
-- center's own atlas + pos, so it works for any registered consumable. nil if the atlas isn't ready.
function PB_UTIL.center_icon_sprite(center, sz)
    if not center then return nil end
    local atlas = center.atlas and G.ASSET_ATLAS[center.atlas]
    if not (atlas and center.pos) then return nil end
    return Sprite(0, 0, sz or 0.5, sz or 0.5, atlas, center.pos)
end

-- An ICON sprite for a stored consumable in the small inventory slot. Tools/books/etc. have a dedicated
-- small icon (bc_tool_icons, keyed by center key in PB_UTIL.tool_icon_pos); use THAT rather than squishing
-- the full card face (center.atlas) into the tiny slot. Falls back to the card face for anything without
-- a registered icon.
function PB_UTIL.consumable_inv_icon(center, sz)
    if not center then return nil end
    local pos   = center.key and PB_UTIL.tool_icon_pos and PB_UTIL.tool_icon_pos[center.key]
    local atlas = PB_UTIL.tool_icon_atlas and G.ASSET_ATLAS[PB_UTIL.tool_icon_atlas.key]
    if pos and atlas then return Sprite(0, 0, sz or 0.5, sz or 0.5, atlas, pos) end
    return PB_UTIL.center_icon_sprite(center, sz)
end

-- Iterate every persistent tool card across the MC area AND (defensively) the vanilla area, e.g. to
-- clear the per-blind use lock or find the sword that scored. Shared by resources.lua's tool scans.
function PB_UTIL.each_tool_card(fn)
    for _, area in ipairs({ G.bc_mc_consumeables, G.consumeables }) do
        if area and area.cards then
            for _, c in ipairs(area.cards) do
                if c.ability and c.ability.set == 'balacraft_tool' then fn(c) end
            end
        end
    end
end

-- ---- Positioning ----
-- Sit exactly on top of the vanilla consumable area's footprint; the toggle (resource_ui.lua) shows
-- only one side at a time, so the two never visually collide. The area's X/Y count label and its
-- equipped cards are Strong-bonded to the area (engine/ui.lua), so they follow when we move its T.
--
-- This MUST run per-frame, NOT just from set_screen_positions: on start_run the engine lays out
-- G.consumeables via set_screen_positions BEFORE the custom_card_areas loop creates our area
-- (game.lua), and never calls it again during a run -- so a one-shot mirror there can never land,
-- leaving the area stranded at its CardArea(0,0) birth spot. resource_ui.lua's per-frame consumable
-- driver calls this while the area is on screen; the dirty-check makes it a no-op once synced.
function PB_UTIL.sync_mc_consumable_area()
    local mc, cons = G.bc_mc_consumeables, G.consumeables
    if not (mc and cons) then return end
    -- Re-assert align_buttons every frame (before the geometry early-return so it always runs).
    -- Card:highlight reads self.area.config.align_buttons to place the Use/Sell buttons to the RIGHT
    -- ("cr") instead of below the card ("bmi"); the base game sets this on G.consumeables but never on
    -- our custom area. Mirror the codebase pattern of re-asserting MC-area config each run (the area is
    -- rebuilt per run) so the right-aligned buttons survive even if construction order ever drops it.
    if mc.config and not mc.config.align_buttons then mc.config.align_buttons = true end
    local t = cons.T
    if mc.T.x == t.x and mc.T.y == t.y and mc.T.w == t.w and mc.T.h == t.h then return end
    mc.T.x, mc.T.y, mc.T.w, mc.T.h = t.x, t.y, t.w, t.h
    mc:hard_set_VT()
end

-- Also mirror at the engine's layout pass (covers any RUN-stage relayout); no-ops harmlessly until
-- custom_card_areas has created our area.
local _set_screen_positions = set_screen_positions
function set_screen_positions()
    _set_screen_positions()
    PB_UTIL.sync_mc_consumable_area()
end
