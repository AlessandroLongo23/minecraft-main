-- Minecraft Inventory & Loadout -- LOGIC half (the UI lives in utilities/inventory_ui.lua).
--
-- Adds a "bench": +3 jokers and +2 consumables held BEYOND the active loadout. Bench cards are
-- DORMANT (added_to_deck=false) -- they never score, apply no passive effects, and aren't usable
-- during a blind. The active loadout stays in vanilla G.jokers / G.consumeables at vanilla limits.
--
-- Persistence is FREE and follows the mod's hybrid model: the bench is stored as a list of
-- serialized card tables (card:save()) on G.GAME.balacraft.bench, so it is auto-saved / auto-reset
-- per run with NO custom save/load code -- exactly like G.GAME.balacraft.resources. Bench entries
-- are materialized into live Card objects only while the inventory overlay is open (inventory_ui).
--
-- This file owns: the bench store + room helpers, card classification, serialize/materialize,
-- and the BUY/REWARD hooks that auto-overflow a pickup onto the bench when the active area is full.

-- Bench capacities (the "+N more" the player asked for).
PB_UTIL.BENCH_CAP = { joker = 3, consumable = 2 }

-- Live bench capacity for a kind = the base cap + any Base-station bonuses. The crafted Chest
-- (utilities/furnace.lua "Your Base") adds +1 to BOTH benches once built. station_built is guarded
-- so this is just the base cap when the Base / resources subsystem is off. Read EVERYWHERE the cap
-- is needed (bench_has_room / bench_free / the inventory zone N/M) so the +1 shows up consistently.
function PB_UTIL.bench_cap(kind)
    local base = PB_UTIL.BENCH_CAP[kind] or 0
    if PB_UTIL.station_built and PB_UTIL.station_built('chest') then base = base + 1 end
    return base
end

function PB_UTIL.inventory_enabled()
    return (PB_UTIL.config and PB_UTIL.config.inventory_enabled) and true or false
end

-- ── Bench store (serialized card tables on G.GAME.balacraft) ───────────────

function PB_UTIL.ensure_bench()
    G.GAME.balacraft = G.GAME.balacraft or {}
    local b = G.GAME.balacraft.bench
    if type(b) ~= 'table' then b = {}; G.GAME.balacraft.bench = b end
    b.jokers      = b.jokers      or {}
    b.consumables = b.consumables or {}
    return b
end

-- kind is 'joker' | 'consumable'.
function PB_UTIL.bench_list(kind)
    local b = PB_UTIL.ensure_bench()
    return (kind == 'joker') and b.jokers or b.consumables
end

function PB_UTIL.bench_count(kind)   return #PB_UTIL.bench_list(kind) end

-- In-flight overflow buys reserve a bench slot until their deferred bench event runs (the bought
-- card is emplaced into the active area first, then moved a beat later). Counting these "pending"
-- reservations keeps rapid buying from exceeding the cap. Synchronous bench paths leave it at 0.
PB_UTIL._bench_pending = PB_UTIL._bench_pending or { joker = 0, consumable = 0 }

function PB_UTIL.bench_has_room(kind)
    local pending = PB_UTIL._bench_pending[kind] or 0
    return (PB_UTIL.bench_count(kind) + pending) < PB_UTIL.bench_cap(kind)
end

-- How many free dormant bench slots remain for a kind (capacity minus held minus pending). Used
-- by the consumable-generation overflow patches (lovely.toml) to size how many extras to bench.
function PB_UTIL.bench_free(kind)
    local pending = PB_UTIL._bench_pending[kind] or 0
    return math.max(0, PB_UTIL.bench_cap(kind) - PB_UTIL.bench_count(kind) - pending)
end

-- The active CardArea for a kind ('joker' -> G.jokers, 'consumable' -> G.consumeables).
function PB_UTIL.inv_active_area(kind)
    if kind == 'joker' then return G.jokers end
    if kind == 'consumable' then return G.consumeables end
    return nil
end

-- Is there a free ACTIVE slot for this kind right now? (config.card_limit reflects the live limit,
-- so slot-modifying jokers / vouchers are respected.)
function PB_UTIL.active_has_room(kind)
    local a = PB_UTIL.inv_active_area(kind)
    return a and a.cards and (#a.cards < a.config.card_limit) and true or false
end

-- Route a card to the active/bench split. Jokers -> 'joker'; any consumable (Tarot, Spectral,
-- balacraft food/tool/book) -> 'consumable'. Playing cards / vouchers -> nil (never bench).
function PB_UTIL.classify_card(card)
    if not (card and card.ability) then return nil end
    if card.ability.set == 'Joker' then return 'joker' end
    if card.ability.consumeable then return 'consumable' end
    return nil
end

-- ── Serialize / materialize ───────────────────────────────────────────────

-- Build a live Card from a saved card table (card:save()). Mirrors CardArea:load
-- (cardarea.lua:698-705): the `loading` global suppresses spawn side effects during construction.
-- Returns a DORMANT card (added_to_deck=false); nil if the center can't be resolved.
function PB_UTIL.materialize_bench_card(saved)
    if not (saved and saved.save_fields and saved.save_fields.center
            and G.P_CENTERS[saved.save_fields.center]) then
        return nil
    end
    -- Card:load assigns self.ability = cardTable.ability BY REFERENCE (card.lua:5256). Deep-copy
    -- first so the live card owns an independent ability table -- otherwise a read-only display
    -- copy would share state with the live card it mirrors (and could mutate it mid-blind).
    saved = copy_table and copy_table(saved) or saved
    loading = true
    local card = Card(0, 0, G.CARD_W, G.CARD_H, G.P_CENTERS.j_joker, G.P_CENTERS.c_base)
    loading = nil
    card:load(saved)
    card.added_to_deck = false   -- bench cards are always dormant, regardless of the saved flag
    return card
end

-- A benched card is still OWNED (just dormant), so the shop pool must keep treating it as "in use".
-- But card:remove() clears G.GAME.used_jokers[center.key] whenever no LIVE copy of that center is
-- left (card.lua:5288) -- and a benched card isn't live. Dropping the key re-admits that exact
-- joker/consumable to the next pool roll, which is the duplicate the player saw (e.g. buying a
-- joker that overflowed to the bench, then being offered the same joker again). Re-mark it after
-- the remove so the pool keeps excluding it. (Materializing the bench on inventory-open already
-- sets this true as a side effect; this covers the overflow/grant paths that never open the modal.)
local function mark_center_used(card)
    local key = card and card.config and card.config.center and card.config.center.key
    if key and G.GAME and G.GAME.used_jokers then G.GAME.used_jokers[key] = true end
end

-- Move an EXISTING live card (currently in an area / added to the deck) onto the bench:
-- undo its passive effects, detach it, store a serialized snapshot, and free the live object.
function PB_UTIL.bench_existing_card(card, kind)
    if not card then return end
    if card.added_to_deck then card:remove_from_deck() end
    if card.area then card.area:remove_card(card) end
    local list = PB_UTIL.bench_list(kind)
    list[#list + 1] = card:save()
    card:remove()
    mark_center_used(card)
end

-- Bench a FRESHLY created card (from SMODS.create_card) that was never added to the deck:
-- store a serialized snapshot and free the live object. No remove_from_deck (never added).
function PB_UTIL.bench_new_card(card, kind)
    if not card then return end
    if card.area then card.area:remove_card(card) end
    card.added_to_deck = false
    local list = PB_UTIL.bench_list(kind)
    list[#list + 1] = card:save()
    card:remove()
    mark_center_used(card)
end

-- ── Room helpers used by crafting (override the crafting.lua versions to be bench-aware) ──
-- Loaded AFTER utilities/crafting.lua, so these win. With the bench, crafting a card while the
-- active area is full but the bench has room SUCCEEDS (produce_output -> the overflow-aware
-- joker_add/consumable_add below benches it). The "No Slots!" warn only shows when BOTH are full.

function PB_UTIL.has_joker_room()
    if not G.jokers then return false end
    if #G.jokers.cards < G.jokers.config.card_limit then return true end
    return PB_UTIL.inventory_enabled() and PB_UTIL.bench_has_room('joker') or false
end

function PB_UTIL.has_consumable_room()
    if not G.consumeables then return false end
    if #G.consumeables.cards < G.consumeables.config.card_limit then return true end
    return PB_UTIL.inventory_enabled() and PB_UTIL.bench_has_room('consumable') or false
end

-- ── Auto-overflow: shop purchases ─────────────────────────────────────────

-- check_for_buy_space gates whether a card can be bought (and the buy button's enabled look).
-- Wrap it: if the existing logic says "no active room", allow the buy anyway when the matching
-- bench has room. We swallow the original's "no space" alert and only re-raise it when BOTH the
-- active area and the bench are full (so the player still sees the real block).
local _orig_check_for_buy_space = G.FUNCS.check_for_buy_space
G.FUNCS.check_for_buy_space = function(card)
    local _alert = alert_no_space
    alert_no_space = function() end          -- swallow the vanilla "No space!" pop for now
    local ok = _orig_check_for_buy_space(card)
    alert_no_space = _alert

    if ok then return true end
    if PB_UTIL.inventory_enabled() then
        local kind = PB_UTIL.classify_card(card)
        if kind and PB_UTIL.bench_has_room(kind) then return true end
    end
    -- Genuinely full everywhere: show the alert the original wanted to show.
    if alert_no_space then
        alert_no_space(card, (card.ability and card.ability.consumeable) and G.consumeables or G.jokers)
    end
    return false
end

-- buy_from_shop emplaces the bought card into the (now possibly over-limit) active area and runs
-- its on-buy effects in a deferred event (delay 0.1). For an overflow buy we let all of that run
-- as vanilla, then -- a touch later (delay 0.16) -- move the freshly bought card onto the bench.
local _orig_buy_from_shop = G.FUNCS.buy_from_shop
G.FUNCS.buy_from_shop = function(e)
    local c1 = e and e.config and e.config.ref_table
    local overflow_kind = nil
    if PB_UTIL.inventory_enabled() and c1 and c1.is and c1:is(Card)
       and e.config.id ~= 'buy_and_use' then
        local kind = PB_UTIL.classify_card(c1)
        if kind and not PB_UTIL.active_has_room(kind) and PB_UTIL.bench_has_room(kind) then
            overflow_kind = kind
            -- Reserve the bench slot now so a second rapid buy sees the reduced room.
            PB_UTIL._bench_pending[kind] = (PB_UTIL._bench_pending[kind] or 0) + 1
        end
    end

    local ret = _orig_buy_from_shop(e)

    if overflow_kind then
        G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.16, func = function()
            if c1 and c1.is and c1:is(Card) then
                PB_UTIL.bench_existing_card(c1, overflow_kind)
            end
            PB_UTIL._bench_pending[overflow_kind] =
                math.max(0, (PB_UTIL._bench_pending[overflow_kind] or 0) - 1)
            return true
        end }))
    end
    return ret
end

-- ── Auto-overflow: booster-pack picks ─────────────────────────────────────
-- Picking from a pack is gated by the active area's card_limit, with NO knowledge of the bench, so a
-- full active area greys SELECT even with an empty bench. Two vanilla paths, both fixed here:
--   * Buffoon-pack jokers          -> button func 'can_select_card'  (checks G.jokers.card_limit)
--   * "take-and-hold" consumables  -> button func 'can_select_from_booster' (the tool type's
--     select_card='consumeables', enchant books, ...; checks the resolved area's card_limit)
-- Both then have use_card emplace the pick straight into the (over-limit) active area. Mirror the buy
-- hooks: enable SELECT when the matching bench has room, and divert an overflow pick to the bench.

-- For a card currently offered in a booster pack, the bench kind its pick resolves to ('consumable'/
-- 'joker'), or nil if it isn't benchable (normal used-on-the-spot consumables, playing cards, feature
-- off). A take-and-hold consumable names its target area via selectable_from_pack; a Buffoon-pack
-- joker has no select_card but use_card emplaces it straight into G.jokers, so treat it as 'joker'.
local function pack_overflow_kind(card)
    if not (PB_UTIL.inventory_enabled() and card and card.is and card:is(Card)) then return nil end
    if card.area ~= G.pack_cards then return nil end
    if booster_obj and card.selectable_from_pack then
        local area = card:selectable_from_pack(booster_obj)
        if area == 'consumeables' then return 'consumable' end
        if area == 'jokers'      then return 'joker' end
    end
    if card.ability and card.ability.set == 'Joker' then return 'joker' end
    return nil
end

-- Button enable, both gates: run vanilla (green iff the active area has room); if it stayed inactive,
-- light it up when the matching bench can hold the pick instead.
local function bench_aware_select_gate(orig)
    return function(e)
        orig(e)
        if e.config.button == 'use_card' then return end -- vanilla already enabled it
        local kind = pack_overflow_kind(e.config.ref_table)
        if kind and PB_UTIL.bench_has_room(kind) then    -- active full, but the bench has room
            e.config.colour = G.C.GREEN
            e.config.button = 'use_card'
        end
    end
end
G.FUNCS.can_select_from_booster = bench_aware_select_gate(G.FUNCS.can_select_from_booster) -- consumables
G.FUNCS.can_select_card         = bench_aware_select_gate(G.FUNCS.can_select_card)         -- Buffoon jokers

-- Selecting the pick: vanilla use_card removes the card from G.pack_cards and emplaces it (over the
-- limit) into the active area. Decide overflow BEFORE that runs; then, a beat later, move the card to
-- the bench -- the same deferred flow as an overflow buy (bench_existing_card undoes passives + saves).
local _orig_use_card_booster = G.FUNCS.use_card
G.FUNCS.use_card = function(e, ...)
    local card = e and e.config and e.config.ref_table
    local overflow_kind = nil
    local kind = pack_overflow_kind(card)
    if kind and not PB_UTIL.active_has_room(kind) and PB_UTIL.bench_has_room(kind) then
        overflow_kind = kind
        PB_UTIL._bench_pending[kind] = (PB_UTIL._bench_pending[kind] or 0) + 1
    end

    local ret = _orig_use_card_booster(e, ...)

    if overflow_kind then
        G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.16, func = function()
            if card and card.is and card:is(Card) then
                PB_UTIL.bench_existing_card(card, overflow_kind)
            end
            PB_UTIL._bench_pending[overflow_kind] =
                math.max(0, (PB_UTIL._bench_pending[overflow_kind] or 0) - 1)
            return true
        end }))
    end
    return ret
end

-- ── Auto-overflow: crafting / reward grants ───────────────────────────────
-- joker_add / consumable_add (utilities/functions.lua) are the helpers crafting outputs and other
-- grants use. Wrap them so a grant lands on the bench when the active area is full but the bench
-- has room; otherwise defer to the original (which fills the active area as before).

local _orig_joker_add = joker_add
function joker_add(jKey)
    if PB_UTIL.inventory_enabled() and type(jKey) == 'string'
       and not PB_UTIL.active_has_room('joker') and PB_UTIL.bench_has_room('joker') then
        local j = SMODS.create_card({ key = jKey })
        if j then PB_UTIL.bench_new_card(j, 'joker') end
        return
    end
    return _orig_joker_add(jKey)
end

local _orig_consumable_add = consumable_add
function consumable_add(cKey)
    if PB_UTIL.inventory_enabled() and type(cKey) == 'string'
       and not PB_UTIL.active_has_room('consumable') and PB_UTIL.bench_has_room('consumable') then
        local c = SMODS.create_card({ key = cKey })
        if c then PB_UTIL.bench_new_card(c, 'consumable') end
        return
    end
    return _orig_consumable_add(cKey)
end
