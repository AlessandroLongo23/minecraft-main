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
-- Two config flags make this area behave like the vanilla consumable tray rather than a generic
-- joker stack (both are re-asserted every frame in sync_mc_consumable_area, since CardArea:load
-- replaces the whole config on run-continue):
--   align_buttons=true -- Use/Sell buttons sit to the RIGHT of the card ("cr" in Card:highlight);
--     without it they fall back to "bmi" (Use below the card, Sell hidden behind it). The base game
--     sets this on G.jokers/G.consumeables in Game:start_run but only on its own areas.
--   spread=true        -- CardArea:align_cards' joker layout SPREADS cards across the full width
--     only for G.consumeables OR when config.spread is set; without it our 2 slots take the
--     overlap ("squeeze") path meant for a stack of many jokers and the two cards crowd together.
local _prev_custom_areas = SMODS.current_mod.custom_card_areas
SMODS.current_mod.custom_card_areas = function(game)
    if _prev_custom_areas then _prev_custom_areas(game) end
    local w = (game.consumeables and game.consumeables.T.w) or (2.3 * G.CARD_W)
    local h = (game.consumeables and game.consumeables.T.h) or (0.95 * G.CARD_H)
    game.bc_mc_consumeables = CardArea(0, 0, w, h, {
        card_limit = PB_UTIL.MC_SLOTS, type = 'joker', highlight_limit = 1,
        negative_info = 'consumable', align_buttons = true, spread = true,
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
    -- Merge fungible consumables into a matching non-full stack (else append a fresh entry). Reads
    -- the card's set + center key; the merge is a no-op decision for non-stackables. See inventory_model.
    local set = card.ability and card.ability.set
    local key = card.config and card.config.center_key
    PB_UTIL.stored_merge_add(bcs.inv.stored, card:save(), set, key)
    if card.area then card.area:remove_card(card) end
    card:remove()
    bcs._panel_dirty = true
    bcs._inv_overlay_dirty = true   -- refresh the inventory modal (new cell / updated "xN") if it's open
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
                else
                    local set = c.ability and c.ability.set
                    local key = c.config and c.config.center_key
                    if PB_UTIL.inv_can_fit_consumable and PB_UTIL.inv_can_fit_consumable(set, key) then
                        PB_UTIL.store_consumable_card(c)
                    end
                end
            end
        end
    end
    -- 2) Drain any MC-area overflow beyond the 2 slots into the inventory.
    local limit = (mc.config and mc.config.card_limit) or PB_UTIL.MC_SLOTS
    local guard = 0
    while #mc.cards > limit and guard < 8 do
        guard = guard + 1
        local c = mc.cards[#mc.cards]
        local set = c.ability and c.ability.set
        local key = c.config and c.config.center_key
        if not (PB_UTIL.inv_can_fit_consumable and PB_UTIL.inv_can_fit_consumable(set, key)) then break end
        PB_UTIL.store_consumable_card(c)
    end
end

-- Equip the stored consumable at inv.stored[index]: materialize it and emplace into a free MC slot.
-- No-op (returns false) if the MC slots are full or the index is invalid. Used by the Inventory modal.
function PB_UTIL.equip_stored_consumable(index)
    local bcs = G.GAME and G.GAME.balacraft
    local stored = bcs and bcs.inv and bcs.inv.stored
    local entry = stored and stored[index]
    if not entry then return false end
    if not PB_UTIL.mc_has_room() then return false end
    -- Materialize a fresh copy from the stack's saved template (materialize copy_table's it, so the
    -- template is never mutated and the remaining stack copies stay valid).
    local card = PB_UTIL.materialize_stored_consumable(PB_UTIL.stored_entry_saved(entry))
    if not card then return false end
    card.added_to_deck = true
    if PB_UTIL.stored_entry_count(entry) > 1 then
        entry.count = PB_UTIL.stored_entry_count(entry) - 1   -- entry is new-format when count > 1
    else
        table.remove(stored, index)
    end
    G.bc_mc_consumeables:emplace(card)
    bcs._panel_dirty = true
    return true
end

-- Un-equip a live MC consumable card (serialize it back into the inventory). Thin wrapper over
-- store_consumable_card with an inventory-capacity guard. Passes the card's set + center key so a
-- stackable un-equips into an existing non-full stack even at 0 free slots (store_consumable_card
-- merges it -- no new slot). Used by the Inventory modal.
function PB_UTIL.unequip_mc_consumable(card)
    if not card then return false end
    local set = card.ability and card.ability.set
    local key = card.config and card.config.center_key
    if not (PB_UTIL.inv_can_fit_consumable and PB_UTIL.inv_can_fit_consumable(set, key)) then return false end
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

-- Resolve a stored consumable center's dedicated FRAMELESS icon (34x34) to (atlas, pos). Each MC
-- consumable SET keeps its own icon atlas + per-item cell -- tools (incl. the one-shots + bow/crossbow/
-- fishing_rod) are keyed by center key in tool_icon_pos; food/potion/sheet/enchant-book key their
-- registry entry by the '<set>_<id>' suffix of the center key. nil if unresolved. Resolved at CALL time
-- because the content registries (FOOD_BY_ID, POTION_BY_ID, ...) load AFTER this file.
local function consumable_icon_atlas_pos(center)
    local key = center.key
    if not key then return nil end
    -- Tools + anything explicitly registered in tool_icon_pos (e.g. the Glass Sheet's recipe icon).
    local tpos = PB_UTIL.tool_icon_pos and PB_UTIL.tool_icon_pos[key]
    if tpos then
        local atlas = PB_UTIL.tool_icon_atlas and G.ASSET_ATLAS[PB_UTIL.tool_icon_atlas.key]
        if atlas then return atlas, tpos end
    end
    -- Non-tool categories: (center-key prefix, id->entry map, entry's icon-cell field, icon atlas obj).
    local SPECS = {
        balacraft_food    = { pre = 'c_balacraft_food_',    by = PB_UTIL.FOOD_BY_ID,         field = 'pos',      atl = PB_UTIL.food_icon_atlas },
        balacraft_potion  = { pre = 'c_balacraft_potion_',   by = PB_UTIL.POTION_BY_ID,       field = 'icon_pos', atl = PB_UTIL.potion_icon_atlas },
        balacraft_sheet   = { pre = 'c_balacraft_sheet_',    by = PB_UTIL.SHEET_BY_ID,        field = 'icon',     atl = PB_UTIL.sheet_icon_atlas },
        balacraft_enchant = { pre = 'c_balacraft_enchant_',  by = PB_UTIL.ENCHANT_BOOK_BY_ID, field = 'pos',      atl = PB_UTIL.enchant_icon_atlas },
    }
    local spec = center.set and SPECS[center.set]
    if spec and spec.by and spec.atl and key:sub(1, #spec.pre) == spec.pre then
        local entry = spec.by[key:sub(#spec.pre + 1)]
        local pos   = entry and entry[spec.field]
        local atlas = G.ASSET_ATLAS[spec.atl.key]
        if pos and atlas then return atlas, pos end
    end
    return nil
end

-- An ICON sprite for a stored consumable in the small inventory slot. Uses the SET's dedicated frameless
-- icon (bc_tool_icons / bc_food_icons / bc_potion_icons / bc_sheet_icons / bc_enchant_icons) rather than
-- squishing the full 71x95 card face into the tiny slot. Falls back to the card face only if no frameless
-- icon can be resolved (e.g. a content type whose icon atlas isn't loaded).
function PB_UTIL.consumable_inv_icon(center, sz)
    if not center then return nil end
    local atlas, pos = consumable_icon_atlas_pos(center)
    if atlas and pos then return Sprite(0, 0, sz or 0.5, sz or 0.5, atlas, pos) end
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
    -- Re-assert our tray-style config every frame (before the geometry early-return so it always
    -- runs). CardArea:load REPLACES the whole config table with the saved one on run-continue, which
    -- drops any flag a save predates -- so reapply both here rather than only at construction:
    --   align_buttons -> Card:highlight places the Use/Sell buttons to the RIGHT ("cr") of the card
    --                    instead of below it ("bmi").
    --   spread        -> CardArea:align_cards spreads the 2 cards across the full width instead of
    --                    overlapping them (the joker-stack "squeeze").
    -- The base game sets align_buttons on G.consumeables but never on our custom area.
    if mc.config then
        mc.config.align_buttons = true
        mc.config.spread = true
    end
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
