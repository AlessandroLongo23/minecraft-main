-- Potion effects + per-blind/multi-blind bookkeeping.
--
-- Potions are SMODS.Consumable cards (set = 'balacraft_potion', content/potions/) whose use()
-- delegates here via PB_UTIL.use_potion(id, card). All runtime state is plain values on
-- G.GAME.balacraft (auto-saved / auto-reset per run, the mod's standard hybrid model -- NO custom
-- save code). Scoring flags that a lovely.toml patch reads live TOP-LEVEL on balacraft (parallel to
-- sword_xmult / axe_xmult); the gameplay bookkeeping lives in G.GAME.balacraft.potion.
--
-- Brew modifiers ride on the card's own ability.extra (stamped at brew time -- see brewing.lua):
--   potency   (Glowstone, Lvl II)      -> bigger numbers
--   duration  (Redstone, drink-only)   -> lasts more blinds
--   lingering (Dragon's Breath, throw) -> carries into the next blind
--   splash    (Gunpowder)              -> intrinsic to the throwables; makes them throwable
-- Missing flags default to the base effect, so a potion granted before brewing exists still works.

-- ---- Seed per-run state (composes with the resources/xp/health/biomes init wraps) ----
local _init_game_object = Game.init_game_object
function Game:init_game_object()
    local t = _init_game_object(self)
    t.balacraft = t.balacraft or {}
    t.balacraft.strength_pct = 0          -- this-blind scoring balance (read by the lovely patch)
    t.balacraft.potion = {
        strength_blinds      = 0,         -- blinds Strength stays active (>1 for Redstone)
        invis_blinds         = 0,         -- blinds Invisibility blocks boss damage
        nightvis_blinds      = 0,         -- blinds Night Vision reveal persists
        nightvis_count       = 0,         -- how many upcoming cards Night Vision reveals
        regen_blinds         = 0,         -- blinds of Healing regen remaining
        regen_amount         = 0,         -- HP healed per regen tick
        poison_pct           = 0,         -- per-action blind-requirement cut while active
        poison_blinds        = 0,         -- blinds the poison keeps ticking (2 if lingering)
        harming_next_pct     = 0,         -- pending requirement cut applied at the next blind (lingering)
    }
    return t
end

local function pstate()
    G.GAME.balacraft = G.GAME.balacraft or {}
    local s = G.GAME.balacraft.potion
    if not s then
        s = { strength_blinds = 0, invis_blinds = 0, nightvis_blinds = 0, nightvis_count = 0,
              regen_blinds = 0, regen_amount = 0, poison_pct = 0, poison_blinds = 0, harming_next_pct = 0 }
        G.GAME.balacraft.potion = s
    end
    return s
end

-- ---- Usage gating (can_use), keyed by the registry's `when` field ----
function PB_UTIL.in_blind()
    return G.STATE == G.STATES.SELECTING_HAND
        or G.STATE == G.STATES.HAND_PLAYED
        or G.STATE == G.STATES.DRAW_TO_HAND
end

function PB_UTIL.potion_can_use(when)
    if not G.GAME then return false end
    if when == 'inside_blind' then
        return G.STATE == G.STATES.SELECTING_HAND
    elseif when == 'outside_blind' then
        return G.STATE == G.STATES.SHOP or G.STATE == G.STATES.BLIND_SELECT
    else -- 'anytime'
        return G.STATE == G.STATES.SELECTING_HAND
            or G.STATE == G.STATES.SHOP
            or G.STATE == G.STATES.BLIND_SELECT
    end
end

-- ---- Animated blind-requirement change (mirrors silverfish.lua's chip ease) ----
-- factor < 1 lowers the requirement. Works for plain numbers and Talisman big-nums (both support
-- * and number_format). Juices the chip text so the cut reads on screen.
function PB_UTIL.ease_blind_requirement(factor)
    if not (G.GAME and G.GAME.blind and G.GAME.blind.chips) then return end
    G.E_MANAGER:add_event(Event({
        trigger = 'immediate',
        func = function()
            G.GAME.blind.chips = G.GAME.blind.chips * factor
            G.GAME.blind.chip_text = number_format(G.GAME.blind.chips)
            if G.GAME.blind.children and G.GAME.blind.children.animatedSprite then
                G.GAME.blind.children.animatedSprite:juice_up(0.3, 0.3)
            end
            play_sound('chips2', 1, 0.7)
            return true
        end
    }))
end

-- ---- Per-blind tick: wrap the genuine "a new blind round begins" call ----
-- Fires regen heals, decrements multi-blind durations, applies lingering carry-over, and clears
-- the per-blind scoring flag. `blind ~= nil and not reset` selects a real new blind (not a reload).
local _set_blind = Blind.set_blind
function Blind:set_blind(blind, reset, silent)
    _set_blind(self, blind, reset, silent)
    if not (blind and not reset and G.GAME and G.GAME.balacraft) then return end
    local s = pstate()

    -- Healing regen: +N HP at the start of each blind while it lasts.
    if s.regen_blinds > 0 and s.regen_amount > 0 and PB_UTIL.heal then
        PB_UTIL.heal(s.regen_amount)
        s.regen_blinds = s.regen_blinds - 1
        if s.regen_blinds <= 0 then s.regen_amount = 0 end
    end

    -- Lingering Harming: a smaller pending cut hits the new blind, once.
    if s.harming_next_pct > 0 then
        PB_UTIL.ease_blind_requirement(1 - s.harming_next_pct)
        s.harming_next_pct = 0
    end

    -- Multi-blind durations tick down at the START of each new blind (so "this blind + next"
    -- = a count of 2 set on use). Strength clears its scoring flag when it expires.
    if s.strength_blinds > 0 then
        s.strength_blinds = s.strength_blinds - 1
        if s.strength_blinds <= 0 then G.GAME.balacraft.strength_pct = 0 end
    end
    if s.invis_blinds > 0 then s.invis_blinds = s.invis_blinds - 1 end
    if s.nightvis_blinds > 0 then
        s.nightvis_blinds = s.nightvis_blinds - 1
        if s.nightvis_blinds > 0 then PB_UTIL.show_night_vision(s.nightvis_count) end
    end
    if s.poison_blinds > 0 then
        s.poison_blinds = s.poison_blinds - 1
        if s.poison_blinds <= 0 then s.poison_pct = 0 end
    end
end

-- ---- Invisibility query (read by the health.lua damage hook) ----
function PB_UTIL.boss_damage_blocked()
    local s = G.GAME and G.GAME.balacraft and G.GAME.balacraft.potion
    return s and s.invis_blinds and s.invis_blinds > 0 or false
end

-- ---- Poison tick: called from the play + discard wraps below ----
function PB_UTIL.potion_poison_tick()
    local s = pstate()
    if s.poison_pct > 0 and G.GAME and G.GAME.blind then
        PB_UTIL.ease_blind_requirement(1 - s.poison_pct)
    end
end

-- Wrap hand-played: a poison tick per played hand (composes with health.lua's own wrap).
-- Game:update_hand_played runs EVERY FRAME while the HAND_PLAYED state is active (dump/game.lua:2700);
-- only its first call per hand sees G.STATE_COMPLETE == false (the engine's own one-shot latch,
-- dump/game.lua:3391). Capture that before calling the original -- same gate as health.lua's wrap --
-- or the tick fires per frame and melts the blind requirement to ~0.
local _update_hand_played = Game.update_hand_played
function Game:update_hand_played(dt)
    local first_frame = not G.STATE_COMPLETE
    _update_hand_played(self, dt)
    if first_frame then pcall(PB_UTIL.potion_poison_tick) end
end

-- Wrap discard: a poison tick per discard (composes with the drowned lovely patch, which returns
-- early only for the Drowned blind).
if G.FUNCS and G.FUNCS.discard_cards_from_highlighted then
    local _discard = G.FUNCS.discard_cards_from_highlighted
    G.FUNCS.discard_cards_from_highlighted = function(e, hook)
        _discard(e, hook)
        if not hook then pcall(PB_UTIL.potion_poison_tick) end
    end
end

-- ---- Night Vision: reveal the next N cards in draw order ----
-- The next cards drawn come off the TOP of the draw pile (the END of G.deck.cards). Show face-up
-- copies in a Weak-bonded UIBox tucked by the deck. Best-effort + pcall-guarded; flagged for
-- in-game verification (the exact draw order / positioning may want tuning).
function PB_UTIL.close_night_vision()
    if G.balacraft_night_vision then
        G.balacraft_night_vision:remove()
        G.balacraft_night_vision = nil
    end
end

function PB_UTIL.show_night_vision(n)
    pcall(function()
        PB_UTIL.close_night_vision()
        if not (G.deck and G.deck.cards and #G.deck.cards > 0) then return end
        local cards = {}
        for i = #G.deck.cards, math.max(1, #G.deck.cards - n + 1), -1 do
            local src = G.deck.cards[i]
            local c = copy_card(src, nil, nil, G.playing_card)
            c.facing = 'front'; c.sprite_facing = 'front'
            c.states.visible = true
            cards[#cards + 1] = { n = G.UIT.C, config = { align = 'cm', padding = 0.04 }, nodes = {
                { n = G.UIT.O, config = { object = c } } } }
        end
        if #cards == 0 then return end
        G.balacraft_night_vision = UIBox {
            definition = { n = G.UIT.ROOT, config = { align = 'cm', colour = G.C.CLEAR }, nodes = {
                { n = G.UIT.R, config = { align = 'cm', padding = 0.05, colour = adjust_alpha(G.C.BLACK, 0.4), r = 0.1 }, nodes = cards } } },
            config = { align = 'cm', offset = { x = 0, y = -2.6 }, major = G.deck, bond = 'Weak' },
        }
    end)
end

-- ---- Effect dispatch ----
-- Each handler reads the brew modifiers off the card (card.ability.extra) and applies the effect.
-- `card` may be nil (debug grants); handlers default every modifier to off.
local function mods_of(card)
    local e = card and card.ability and card.ability.extra or {}
    return e.potency and true or false, e.duration and true or false, e.lingering and true or false
end

PB_UTIL.POTION_EFFECTS = {
    swiftness = function(card)
        local potency = mods_of(card)
        if potency and G.GAME and G.GAME.balacraft then G.GAME.balacraft._biome_extra = true end  -- Lvl II: 4 choices
        if PB_UTIL.open_biome_select then PB_UTIL.open_biome_select() end
    end,

    strength = function(card)
        local potency, duration = mods_of(card)
        G.GAME.balacraft = G.GAME.balacraft or {}
        G.GAME.balacraft.strength_pct = potency and 0.20 or 0.10   -- pull chips & mult toward avg
        pstate().strength_blinds = duration and 2 or 1
    end,

    instant_health = function(card)
        local potency = mods_of(card)
        PB_UTIL.heal(potency and 8 or 6)                            -- 4 / 3 hearts now
    end,

    healing = function(card)
        local potency, duration = mods_of(card)
        local s = pstate()
        s.regen_amount = potency and 4 or 2                         -- 2 / 1 hearts per blind
        s.regen_blinds = duration and 4 or 3
        PB_UTIL.heal(s.regen_amount)                                -- first tick immediately
        s.regen_blinds = s.regen_blinds - 1
    end,

    night_vision = function(card)
        local potency, duration = mods_of(card)
        local s = pstate()
        s.nightvis_count  = potency and 5 or 3
        s.nightvis_blinds = duration and 2 or 1
        PB_UTIL.show_night_vision(s.nightvis_count)
    end,

    invisibility = function(card)
        local _, duration = mods_of(card)
        pstate().invis_blinds = duration and 2 or 1                 -- no boss damage this/2 blinds
    end,

    poison = function(card)
        local potency, _, lingering = mods_of(card)
        local s = pstate()
        s.poison_pct    = potency and 0.15 or 0.10                  -- -% requirement per action
        s.poison_blinds = lingering and 2 or 1
        PB_UTIL.potion_poison_tick()                               -- the throw itself counts as a tick
    end,

    harming = function(card)
        local potency, _, lingering = mods_of(card)
        PB_UTIL.ease_blind_requirement(potency and 0.35 or 0.50)   -- -65% / -50% now
        if lingering then pstate().harming_next_pct = 0.25 end     -- -25% to the next blind too
    end,
}

-- Entry point called from each potion center's use().
function PB_UTIL.use_potion(id, card)
    local fn = PB_UTIL.POTION_EFFECTS[id]
    if fn then pcall(fn, card) end
end

-- Juice for the Strength balance (called from the lovely.toml scoring patch). Pops a purple
-- "Balanced!" on the played hand, like the sword/axe score messages. Guarded + pcall-safe.
function PB_UTIL.strength_score_message()
    pcall(function()
        local bc = G.GAME and G.GAME.balacraft
        if not (bc and bc.strength_pct and bc.strength_pct ~= 0) then return end
        local card = (G.play and G.play.cards and G.play.cards[1]) or G.deck
        if not (card and card_eval_status_text) then return end
        card_eval_status_text(card, 'extra', nil, nil, nil,
            { message = 'Balanced!', colour = { 0.8, 0.45, 0.85, 1 }, sound = 'gong' })
    end)
end

-- ---- Potion booster pack sampling (mirrors PB_UTIL.sample_pack_foods) ----
-- Lower tiers are commoner; the pack hands out plain (un-modified) potions.
local POTIONPACK_TIER_WEIGHT = { [1] = 4, [2] = 2, [3] = 1 }

function PB_UTIL.sample_pack_potions(n)
    local remaining = {}
    for _, p in ipairs(PB_UTIL.POTIONS or {}) do
        remaining[#remaining + 1] = { id = p.id, weight = POTIONPACK_TIER_WEIGHT[p.tier] or 1 }
    end
    local picked = {}
    n = math.min(n or 1, #remaining)
    for _ = 1, n do
        local pool = {}
        for idx, e in ipairs(remaining) do
            for _ = 1, e.weight do pool[#pool + 1] = idx end
        end
        local chosen = pseudorandom_element(pool, pseudoseed('bc_potionpack'))
        picked[#picked + 1] = remaining[chosen].id
        table.remove(remaining, chosen)
    end
    return picked
end

function PB_UTIL.create_potion_pack_card(card, i, n)
    if not card.balacraft_pack_potions then
        local size_mod = (G.GAME and G.GAME.modifiers and G.GAME.modifiers.booster_size_mod) or 0
        card.balacraft_pack_potions = PB_UTIL.sample_pack_potions((n or 1) + size_mod)
    end
    local id = card.balacraft_pack_potions[i]
        or card.balacraft_pack_potions[1]
        or PB_UTIL.POTIONS[1].id
    return create_card('balacraft_potion', G.pack_cards, nil, nil, true, true,
        'c_balacraft_potion_' .. id, 'bc_potionpack')
end

-- ---- Variant card art (Level I/II x normal/lasts-more) ----
-- The bc_potion_cards atlas is 4 cols x 8 rows: row = the center's base pos.y (one per potion),
-- col = the (Level, lasts-more) combination from the brew flags. Compute the column here.
function PB_UTIL.potion_variant_pos(center, extra)
    if not (center and center.pos) then return nil end
    extra = extra or {}
    local col = (extra.potency and 2 or 0) + ((extra.duration or extra.lingering) and 1 or 0)
    return { x = col, y = center.pos.y }
end

-- Wrap Card:set_sprites so a brewed potion shows its variant column (called on build, hover, load,
-- area changes...). Base/un-modified potions keep column 0 (their registry pos), so the collection
-- and shop show the plain card. Guarded: untouched for every non-potion card.
local _card_set_sprites = Card.set_sprites
function Card:set_sprites(_center, _front)
    _card_set_sprites(self, _center, _front)
    if _center and _center.set == 'balacraft_potion' and self.children and self.children.center then
        local pos = PB_UTIL.potion_variant_pos(_center, self.ability and self.ability.extra)
        if pos then self.children.center:set_sprite_pos(pos) end
    end
end

-- ---- Drink / Throw button relabel ----
-- The base game hard-codes the consumable button to localize('b_use') in use_and_sell_buttons
-- (dump/functions/UI_definitions.lua:276 & :285). Wrap that builder and swap the 'Use' text node
-- for the card center's bc_use_label ('Drink' / 'Throw'); other cards are untouched (label nil).
-- G.UIDEF is created at startup (UI_definitions.lua:3) before mods load, so this installs cleanly.
local function relabel_text_nodes(nodes, from, to)
    if type(nodes) ~= 'table' then return end
    for _, node in ipairs(nodes) do
        if type(node) == 'table' then
            if node.config and node.config.text == from then node.config.text = to end
            if node.nodes then relabel_text_nodes(node.nodes, from, to) end
        end
    end
end

if G.UIDEF and G.UIDEF.use_and_sell_buttons then
    local _use_and_sell_buttons = G.UIDEF.use_and_sell_buttons
    function G.UIDEF.use_and_sell_buttons(card)
        local def = _use_and_sell_buttons(card)
        local center = card and card.config and card.config.center
        local label = center and center.bc_use_label
        if label and def and def.nodes then
            relabel_text_nodes(def.nodes, localize('b_use'), label)
        end
        return def
    end
end
