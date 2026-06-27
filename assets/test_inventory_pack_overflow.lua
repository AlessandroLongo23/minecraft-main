-- Headless tests for the booster-pack -> bench overflow hooks added to utilities/inventory.lua.
-- NOT loaded by the mod. Run from the mod root:  lua assets/test_inventory_pack_overflow.lua
--
-- Covers the bug "SELECT greyed out in a Toolbox pack even though the consumable bench is empty":
--   * G.FUNCS.can_select_from_booster must light up the button when the active area is full but the
--     bench has room (and must NOT when both are full / when the feature is off).
--   * G.FUNCS.use_card must divert the pick to the bench (deferred) only in that active-full case.
-- It loads the REAL inventory.lua so the wiring (not a re-implementation) is what's under test.

-- ---- minimal engine stubs the file reads at load / the hooks read at call -----------
local pack_cards = { cards = {} }
function pack_cards:remove_card(card)
    for i, c in ipairs(self.cards) do if c == card then table.remove(self.cards, i); return end end
end
G = {
    C = { GREEN = 'GREEN', UI = { BACKGROUND_INACTIVE = 'INACTIVE' } },
    pack_cards = pack_cards,
    GAME = { balacraft = {}, used_jokers = {} },
    FUNCS = {},
    E_MANAGER = nil,
}
Card = {}                                  -- card:is(Card) identity sentinel
booster_obj = { center = 'fake_pack' }     -- truthy => "a pack is open"

local event_queue = {}
function Event(t) return t end
G.E_MANAGER = { add_event = function(_, e) event_queue[#event_queue + 1] = e; return e end }
local function drain_events() local q = event_queue; event_queue = {}; for _, e in ipairs(q) do e.func() end end

SMODS = { create_card = function() return nil end }
function copy_table(t) return t end
alert_no_space = function() end

-- Vanilla G.FUNCS the file wraps at load (only the booster ones matter here; the rest just need to
-- exist so the wraps capture a callable original).
G.FUNCS.check_for_buy_space = function() return false end
G.FUNCS.buy_from_shop = function() end
function joker_add() end
function consumable_add() end

-- Faithful copy of SMODS' vanilla can_select_from_booster (smods utils.lua:2443): green + use_card
-- only when the resolved area has room under its card_limit (+ the card's edition card_limit). Gates
-- the take-and-hold consumable SELECT button.
G.FUNCS.can_select_from_booster = function(e)
    local card = e.config.ref_table
    local area = booster_obj and card:selectable_from_pack(booster_obj)
    local edition_card_limit = card.ability.card_limit
    if area and #G[area].cards < G[area].config.card_limit + edition_card_limit then
        e.config.colour = G.C.GREEN
        e.config.button = 'use_card'
    else
        e.config.colour = G.C.UI.BACKGROUND_INACTIVE
        e.config.button = nil
    end
end

-- Faithful copy of vanilla can_select_card (button_callbacks.lua:2127): gates the Buffoon-pack joker
-- SELECT button -- green unless it's a Joker and G.jokers is at its card_limit.
G.FUNCS.can_select_card = function(e)
    local card = e.config.ref_table
    local card_limit = card.ability.card_limit - (card.ability.extra_slots_used or 0)
    if card.ability.set ~= 'Joker' or #G.jokers.cards < G.jokers.config.card_limit + card_limit then
        e.config.colour = G.C.GREEN
        e.config.button = 'use_card'
    else
        e.config.colour = G.C.UI.BACKGROUND_INACTIVE
        e.config.button = nil
    end
end

-- Vanilla use_card, reduced to the two pack-select paths: take-and-hold consumables emplace into the
-- resolved area (button_callbacks.lua:2241-2243); Buffoon-pack jokers emplace into G.jokers (2276-2278).
-- Either way the emplace can go over the active limit.
G.FUNCS.use_card = function(e)
    local card = e.config.ref_table
    local area = booster_obj and card:selectable_from_pack(booster_obj)
    if not area and card.ability.set == 'Joker' then area = 'jokers' end
    if area then
        card.area:remove_card(card)
        card.added_to_deck = true
        card.area = G[area]
        local cards = G[area].cards
        cards[#cards + 1] = card
    end
end

-- ---- area + card factories ----------------------------------------------------------
local function make_area(limit, n)
    local a = { cards = {}, config = { card_limit = limit } }
    for i = 1, (n or 0) do a.cards[i] = { filler = true } end
    function a:remove_card(card)
        for i, c in ipairs(self.cards) do if c == card then table.remove(self.cards, i); return end end
    end
    return a
end

local function make_card(opts)
    local card
    card = {
        ability = { set = opts.set, consumeable = opts.consumeable, card_limit = 0, extra_slots_used = 0 },
        config = { center = { key = opts.key or 'c_test' } },
        area = pack_cards,
        added_to_deck = false,
        is = function(self, k) return k == Card end,
        selectable_from_pack = function(self, _pack) return opts.area_name end,  -- nil for plain jokers
        remove_from_deck = function(self) self.added_to_deck = false end,
        save = function(self) return { save_fields = { center = self.config.center.key } } end,
        remove = function(self) end,
    }
    pack_cards.cards[#pack_cards.cards + 1] = card
    return card
end
-- A take-and-hold consumable pick (tool/torch/book) -> resolves to G.consumeables.
local function make_pack_card(_, area_name)
    return make_card{ set = 'balacraft_tool', consumeable = true, area_name = area_name, key = 'c_test' }
end
-- A plain Buffoon-pack joker -> no select_card; use_card emplaces it into G.jokers.
local function make_joker_pack_card()
    return make_card{ set = 'Joker', consumeable = false, area_name = nil, key = 'j_test' }
end

-- ---- load the real hooks ------------------------------------------------------------
PB_UTIL = { config = { inventory_enabled = true } }
assert(loadfile('utilities/inventory.lua'))()

-- ---- tiny harness -------------------------------------------------------------------
local pass, fail = 0, 0
local function check(name, cond)
    if cond then pass = pass + 1; print('  ok   ' .. name)
    else fail = fail + 1; print('  FAIL ' .. name) end
end
local function button_after(fn, card)
    local e = { config = { ref_table = card } }
    fn(e)
    return e.config.button
end
local function button_after_can_select(card) return button_after(G.FUNCS.can_select_from_booster, card) end
local function button_after_select_card(card) return button_after(G.FUNCS.can_select_card, card) end

-- == Button enable (the greyed-SELECT symptom) =======================================
-- Active consumeables FULL (2/2), bench EMPTY -> the fix must enable SELECT.
G.consumeables = make_area(2, 2)
G.jokers = make_area(5, 0)
G.GAME.balacraft.bench = nil
check('active full + empty bench -> SELECT enabled',
    button_after_can_select(make_pack_card('balacraft_tool', 'consumeables')) == 'use_card')

-- Active FULL and bench FULL (2/2) -> still blocked.
G.consumeables = make_area(2, 2)
G.GAME.balacraft.bench = { consumables = { {}, {} }, jokers = {} }
check('active full + bench full -> SELECT blocked',
    button_after_can_select(make_pack_card('balacraft_tool', 'consumeables')) == nil)

-- Active has room (1/2) -> vanilla already enables; wrapper leaves it.
G.consumeables = make_area(2, 1)
G.GAME.balacraft.bench = nil
check('active has room -> SELECT enabled (vanilla path)',
    button_after_can_select(make_pack_card('balacraft_tool', 'consumeables')) == 'use_card')

-- Feature OFF: behaves like vanilla -> active full means blocked even with empty bench.
PB_UTIL.config.inventory_enabled = false
G.consumeables = make_area(2, 2)
G.GAME.balacraft.bench = nil
check('inventory disabled -> active full stays blocked',
    button_after_can_select(make_pack_card('balacraft_tool', 'consumeables')) == nil)
PB_UTIL.config.inventory_enabled = true

-- == Action routing: use_card must divert an overflow pick to the bench ===============
-- Active FULL, bench EMPTY -> after use + deferred event, card lands on the bench, not the active area.
G.consumeables = make_area(2, 2)
G.GAME.balacraft.bench = nil
local picked = make_pack_card('balacraft_tool', 'consumeables')
G.FUNCS.use_card({ config = { ref_table = picked } })
check('overflow pick emplaced into active area first (over limit)', #G.consumeables.cards == 3)
drain_events()
check('overflow pick moved to the bench', PB_UTIL.bench_count('consumable') == 1)
check('overflow pick removed from the active area', #G.consumeables.cards == 2)
check('bench-pending counter settled back to 0', (PB_UTIL._bench_pending.consumable or 0) == 0)

-- Active has ROOM -> normal pick stays active, nothing benched.
G.consumeables = make_area(2, 0)
G.GAME.balacraft.bench = nil
local normal = make_pack_card('balacraft_tool', 'consumeables')
G.FUNCS.use_card({ config = { ref_table = normal } })
drain_events()
check('pick with active room stays active (not benched)',
    #G.consumeables.cards == 1 and PB_UTIL.bench_count('consumable') == 0)

-- == Buffoon-pack jokers: the same fix via the can_select_card gate ===================
-- Jokers FULL (5/5), joker bench EMPTY -> SELECT must enable.
G.jokers = make_area(5, 5)
G.GAME.balacraft.bench = nil
check('jokers full + empty joker bench -> SELECT enabled',
    button_after_select_card(make_joker_pack_card()) == 'use_card')

-- Jokers FULL and joker bench FULL (3/3) -> still blocked.
G.jokers = make_area(5, 5)
G.GAME.balacraft.bench = { jokers = { {}, {}, {} }, consumables = {} }
check('jokers full + joker bench full -> SELECT blocked',
    button_after_select_card(make_joker_pack_card()) == nil)

-- Jokers have room (4/5) -> vanilla enables; wrapper leaves it.
G.jokers = make_area(5, 4)
G.GAME.balacraft.bench = nil
check('jokers have room -> SELECT enabled (vanilla path)',
    button_after_select_card(make_joker_pack_card()) == 'use_card')

-- Action: jokers FULL, bench EMPTY -> joker pick diverts to the joker bench.
G.jokers = make_area(5, 5)
G.GAME.balacraft.bench = nil
local jpick = make_joker_pack_card()
G.FUNCS.use_card({ config = { ref_table = jpick } })
check('overflow joker emplaced into G.jokers first (over limit)', #G.jokers.cards == 6)
drain_events()
check('overflow joker moved to the joker bench', PB_UTIL.bench_count('joker') == 1)
check('overflow joker removed from G.jokers', #G.jokers.cards == 5)

print(string.format('\n%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
