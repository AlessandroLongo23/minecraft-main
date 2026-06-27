-- Torch consumable logic: a NON-DESTRUCTIVE peek at the next two shop rerolls and at
-- every booster pack's would-be contents, shown in a one-shot overlay modal.
--
-- Mechanism: "freeze" the global card RNG (deep-copy G.GAME.pseudorandom) AND the used-card
-- set (deep-copy G.GAME.used_jokers -- see below), blank out tags (so a store_joker tag is
-- never consumed), and stub the UI + event emitters (so no shop/pack UI or materialize events
-- leak). Then run the REAL engine generators into throwaway cards, keep those Card objects for
-- display, and restore everything -- so the actual shop/rerolls produce exactly what was shown.
-- Every peek is pcall-guarded: a failure renders "Preview unavailable" instead of crashing.
--
-- The used_jokers restore is load-bearing for accuracy: card.lua:498-503 writes
-- G.GAME.used_jokers[center.key]=true for EVERY card created (jokers AND consumables), and
-- get_current_pool (common_events.lua:2425) culls any used key from the pool. Without
-- restoring it, our preview cards mark themselves "used", so the real reroll/pack-open then
-- AVOIDS the very cards we showed -- the previews would systematically mismatch reality.
--
-- This intentionally replays engine internals (create_card_for_shop, Card:open's content
-- loop). That is fragile by nature (a Balatro/SMODS update could shift behaviour); the pcall
-- guards keep a desync visible-but-safe rather than fatal. Tag-forced shop cards are a known
-- blind spot (we blank tags to avoid consuming them, so they aren't previewed).

PB_UTIL.torch_slots = PB_UTIL.torch_slots or nil   -- flat list of { area = CardArea, card = Card }

-- Display tunables (world units). SCALE shrinks full cards to fit several rows; tune in-game.
local CARD_SCALE = 0.7
local function slot_w() return (G.CARD_W or 1.27) * CARD_SCALE end
local function slot_h() return (G.CARD_H or 1.78) * CARD_SCALE end

-- ── One-shot debug log (predicted vs actual) ──────────────────────────────
-- Set to false to silence. Writes to the LOVE save dir, i.e.
--   ~/Library/Application Support/Balatro/balacraft_torch_debug.log
-- so the predicted previews (logged on torch use) and the ACTUAL shop reroll (logged when you
-- really reroll) can be compared line-for-line. Purely diagnostic; safe to leave on.
PB_UTIL._torch_debug = true
function PB_UTIL.torch_debug(msg)
    if not PB_UTIL._torch_debug then return end
    pcall(function()
        love.filesystem.append('balacraft_torch_debug.log', tostring(msg) .. '\n')
    end)
end

-- Comma-joined center keys (falls back to ability name) for a card list -- for the debug log.
local function card_keys(cards)
    local t = {}
    for _, c in ipairs(cards or {}) do
        t[#t + 1] = (c.config and c.config.center and c.config.center.key)
            or (c.ability and c.ability.name) or '?'
    end
    return (#t > 0) and table.concat(t, ', ') or '(none)'
end

-- Snapshot the controller/overlay state to the debug log. Used at overlay open and at exit so a
-- freeze (Close dead / ESC dead) can be traced to whichever lock/layer/pause flag is wrong.
local function ctrl_state(tag)
    if not PB_UTIL._torch_debug then return end
    local c = G.CONTROLLER
    local locks = (c and c.locks) or {}
    local lk = {}
    for k, v in pairs(locks) do if v then lk[#lk + 1] = tostring(k) end end
    table.sort(lk)
    PB_UTIL.torch_debug(string.format(
        '%s | paused=%s state=%s ctx_layer=%s hover=%s focused=%s overlay=%s locks={%s}',
        tostring(tag), tostring(G.SETTINGS.paused), tostring(G.STATE),
        tostring(c and c.cursor_context and c.cursor_context.layer),
        tostring(c and c.hovering and (c.hovering.target ~= nil)),
        tostring(c and c.focused and (c.focused.target ~= nil)),
        tostring(G.OVERLAY_MENU ~= nil), table.concat(lk, ',')))
end

-- Dump every numeric pseudorandom counter to the debug log. Compared across BEFORE_PEEK /
-- AFTER_PEEK / BEFORE_REROLL it pinpoints the accuracy bug: if AFTER_PEEK != BEFORE_PEEK the
-- peek doesn't fully restore RNG; if BEFORE_REROLL != AFTER_PEEK something advanced the RNG
-- between the peek and the real action (the changed keys say what).
local function rng_fingerprint(tag)
    if not PB_UTIL._torch_debug then return end
    local pr = G.GAME and G.GAME.pseudorandom
    if not pr then return end
    local keys = {}
    for k in pairs(pr) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        local v = pr[k]
        parts[#parts + 1] = k .. '=' .. (type(v) == 'number' and string.format('%.6f', v) or tostring(v))
    end
    PB_UTIL.torch_debug(tag .. ' RNG: ' .. table.concat(parts, ' '))
end

-- ── RNG freeze / restore ──────────────────────────────────────────────────
-- Run fn() with the card RNG frozen and side-effect emitters stubbed; restore all of it
-- afterwards. Returns fn()'s result, or nil if fn errored (pcall-guarded).
local function with_frozen_rng(fn)
    local snap_rng   = copy_table(G.GAME.pseudorandom)
    local snap_used  = G.GAME.used_jokers and copy_table(G.GAME.used_jokers) or nil
    local saved_tags = G.GAME.tags
    local saved_ui   = create_shop_card_ui
    local saved_add  = G.E_MANAGER.add_event
    local saved_pack = G.pack_cards
    -- Snapshot the controller locks. set_edition/set_seal (Standard-pack peek) and other card
    -- creation set locks like G.CONTROLLER.locks.edition/seal=true and clear them via an EVENT --
    -- but we stub add_event below, so those unlock events are dropped and the locks would stay
    -- set forever (the whole shop becomes unclickable after the modal closes). Restore in place.
    local snap_locks = {}
    if G.CONTROLLER and G.CONTROLLER.locks then
        for k, v in pairs(G.CONTROLLER.locks) do snap_locks[k] = v end
    end

    G.GAME.tags = {}
    create_shop_card_ui = function() end
    G.E_MANAGER.add_event = function() end

    local ok, result = pcall(fn)

    G.pack_cards          = saved_pack
    G.E_MANAGER.add_event = saved_add
    create_shop_card_ui   = saved_ui
    G.GAME.tags           = saved_tags
    if snap_used then G.GAME.used_jokers = snap_used end
    G.GAME.pseudorandom   = snap_rng
    if G.CONTROLLER and G.CONTROLLER.locks then
        local L = G.CONTROLLER.locks
        for k in pairs(L) do if snap_locks[k] == nil then L[k] = nil end end
        for k, v in pairs(snap_locks) do L[k] = v end
    end

    if ok then return result end
    return nil
end

-- The real reroll (reroll_shop) REMOVES every current shop card before generating new ones, and
-- Card:remove() (card.lua:5286-5290) clears G.GAME.used_jokers[key] for any removed card whose
-- key isn't also owned (SMODS.find_card only searches owned joker areas, never the shop). The
-- pool builder culls used_jokers (common_events.lua:2425), so unless we replicate this the peek
-- samples from a pool that still EXCLUDES the cards sitting in the shop while the real reroll's
-- pool INCLUDES them -- different resamples -> the RNG cascades and every card downstream differs.
-- used_jokers is restored wholesale by with_frozen_rng, so clearing here is safe.
local function simulate_shop_card_removal()
    if not (G.shop_jokers and G.shop_jokers.cards and G.GAME.used_jokers) then return end
    for _, c in ipairs(G.shop_jokers.cards) do
        local k = c.config and c.config.center and c.config.center.key
        if k and not next(SMODS.find_card(k, true)) then
            G.GAME.used_jokers[k] = nil
        end
    end
end

-- ── Reroll peek ───────────────────────────────────────────────────────────
-- Generate the cards `rerolls` consecutive shop rerolls would produce (RNG advances across
-- them, exactly mirroring real consecutive rerolls). A throwaway temp area is passed (it is
-- not G.shop_jokers and not G.pack_cards, so the sticker-RNG keys match the real shop); the
-- generated cards are detached from it so they float free for display. Returns a list of
-- card-lists, one per reroll.
local function peek_rerolls(rerolls)
    local out = {}
    local n = (G.GAME.shop and G.GAME.shop.joker_max) or 2
    simulate_shop_card_removal()   -- match the real reroll's pre-clear of shop cards
    local temp = CardArea(G.ROOM.T.x, G.ROOM.T.y, 1, 1, { card_limit = 100, highlight_limit = 0 })
    for r = 1, rerolls do
        local cards = {}
        for _ = 1, n do
            local card = create_card_for_shop(temp)
            if card then cards[#cards + 1] = card end
        end
        out[r] = cards
    end
    for _, group in ipairs(out) do
        for _, c in ipairs(group) do
            if c.area then c.area:remove_card(c) end
            c.area = nil
        end
    end
    temp:remove()
    return out
end

-- ── Pack peek ─────────────────────────────────────────────────────────────
-- Replicate Card:open's content-generation loop (functions/state_events + card.lua:2071-2124)
-- for a single shop booster `b`, minus materialize/emplace/UI. G.pack_cards is pointed at a
-- temp area so the engine's `area == G.pack_cards` sticker-RNG keys stay correct. Returns the
-- generated cards (free of any area), or nil if the pack type is unrecognised.
local function peek_pack(b)
    local booster_obj = b.config.center
    local extra = b.ability.extra or (booster_obj.config and booster_obj.config.extra) or 1
    local size = math.max(1, extra + (G.GAME.modifiers.booster_size_mod or 0))
    local name = b.ability.name or ''
    -- A read-through proxy of the real booster card: modded create_card functions cache per-pack
    -- state on this arg (e.g. our food pack stores card.balacraft_pack_foods) AND read its real
    -- fields (self.config). __index forwards reads to b; writes stay on the proxy so the actual
    -- shop booster is never mutated by the peek.
    local bproxy = setmetatable({}, { __index = b })
    local temp = CardArea(G.ROOM.T.x, G.ROOM.T.y, 1, 1, { card_limit = 100, highlight_limit = 0 })
    G.pack_cards = temp

    local cards = {}
    local recognised = false
    for i = 1, size do
        local card = nil
        -- Mirror Card:open exactly (card.lua:2073-2125). FIRST give jokers/mods a chance to inject
        -- a card via create_booster_card; this also advances RNG identically to the real open.
        local flags = SMODS.calculate_context({ create_booster_card = true, booster = b, index = i })
        if flags and flags.booster_create_flags then
            recognised = true
            card = SMODS.create_card(flags.booster_create_flags)
        elseif booster_obj.create_card and type(booster_obj.create_card) == 'function' then
            recognised = true
            local cts = booster_obj:create_card(bproxy, i)
            if type((cts or {}).is) == 'function' and cts:is(Card) then card = cts
            else card = SMODS.create_card(cts) end
        elseif name:find('Arcana') then
            recognised = true
            if G.GAME.used_vouchers.v_omen_globe and pseudorandom('omen_globe') > 0.8 then
                card = create_card('Spectral', G.pack_cards, nil, nil, true, true, nil, 'ar2')
            else
                card = create_card('Tarot', G.pack_cards, nil, nil, true, true, nil, 'ar1')
            end
        elseif name:find('Celestial') then
            recognised = true
            if G.GAME.used_vouchers.v_telescope and i == 1 then
                local _planet, _hand, _tally = nil, nil, 0
                for _, v in ipairs(G.handlist) do
                    if G.GAME.hands[v].visible and G.GAME.hands[v].played > _tally then
                        _hand = v; _tally = G.GAME.hands[v].played
                    end
                end
                if _hand then
                    for _, v in pairs(G.P_CENTER_POOLS.Planet) do
                        if v.config.hand_type == _hand then _planet = v.key end
                    end
                end
                card = create_card('Planet', G.pack_cards, nil, nil, true, true, _planet, 'pl1')
            else
                card = create_card('Planet', G.pack_cards, nil, nil, true, true, nil, 'pl1')
            end
        elseif name:find('Spectral') then
            recognised = true
            card = create_card('Spectral', G.pack_cards, nil, nil, true, true, nil, 'spe')
        elseif name:find('Standard') then
            recognised = true
            card = create_card((pseudorandom(pseudoseed('stdset' .. G.GAME.round_resets.ante)) > 0.6) and 'Enhanced' or 'Base',
                G.pack_cards, nil, nil, nil, true, nil, 'sta')
            card:set_edition(poll_edition('standard_edition' .. G.GAME.round_resets.ante, 2, true))
            card:set_seal(SMODS.poll_seal({ mod = 10 }), true, true)
        elseif name:find('Buffoon') then
            recognised = true
            card = create_card('Joker', G.pack_cards, nil, nil, true, true, nil, 'buf')
        end
        -- THEN let jokers/mods edit the made card (edition/seal/etc.) -- also matches the real RNG.
        if card then
            SMODS.calculate_context({ modify_booster_card = true, booster = b, card = card, index = i })
            cards[#cards + 1] = card
        end
    end

    -- Detach every generated card from the temp area, then drop the (now empty) temp area.
    for _, c in ipairs(cards) do
        if c.area then c.area:remove_card(c) end
        c.area = nil
    end
    temp:remove()

    if not recognised then return nil end
    return cards
end

-- DEBUG: trace every shop-card generation (peek vs real reroll) with the used_jokers pool state
-- that produced it, so a pool divergence shows up directly. Active only while _torch_trace is set.
if not PB_UTIL._torch_ccfs_hooked then
    PB_UTIL._torch_ccfs_hooked = true
    local _ccfs = create_card_for_shop
    function create_card_for_shop(area)
        local pre_cdt, ntags
        if PB_UTIL._torch_debug and PB_UTIL._torch_trace then
            local ante = G.GAME.round_resets and G.GAME.round_resets.ante or ''
            pre_cdt = G.GAME.pseudorandom and G.GAME.pseudorandom['cdt' .. tostring(ante)]
            ntags = #(G.GAME.tags or {})
        end
        local card = _ccfs(area)
        if PB_UTIL._torch_debug and PB_UTIL._torch_trace then
            PB_UTIL.torch_debug(string.format('CCFS[%s] area=%s cdt=%s ntags=%s -> %s',
                PB_UTIL._torch_trace, (area == G.shop_jokers) and 'SHOP' or 'temp',
                tostring(pre_cdt), tostring(ntags),
                (card and card.config and card.config.center and card.config.center.key) or '?'))
        end
        return card
    end
end

-- DEBUG: trace the shop TYPE poll itself -- the seed value it consumes, the computed total_rate,
-- and the ordered type list -- so we can see which input differs between PEEK and REAL even though
-- the RNG table, used_jokers and rates all log identical.
if not PB_UTIL._torch_pot_hooked then
    PB_UTIL._torch_pot_hooked = true
    local _pot = SMODS.poll_object_type
    function SMODS.poll_object_type(args)
        local before
        if PB_UTIL._torch_debug and PB_UTIL._torch_trace and args and args.seed then
            before = G.GAME.pseudorandom and G.GAME.pseudorandom[args.seed]
        end
        local t = _pot(args)
        if PB_UTIL._torch_debug and PB_UTIL._torch_trace and args and args.seed then
            local types = { 'Joker', 'playing_card' }
            for _, v in ipairs(SMODS.ConsumableType.obj_buffer or {}) do types[#types + 1] = v end
            local total, parts = 0, {}
            for _, ty in ipairs(types) do
                local rate = G.GAME[ty:lower() .. '_rate'] or 0
                total = total + rate
                parts[#parts + 1] = ty .. ':' .. tostring(rate)
            end
            PB_UTIL.torch_debug(string.format('POT[%s] seed=%s before=%s after=%s total=%s -> %s | order=[%s]',
                PB_UTIL._torch_trace, tostring(args.seed), tostring(before),
                tostring(G.GAME.pseudorandom and G.GAME.pseudorandom[args.seed]),
                tostring(total), tostring(t), table.concat(parts, ',')))
        end
        return t
    end
end

-- DEBUG: log every pseudoseed KEY consumed during the trace, so the exact RNG-key sequence of a
-- PEEK card generation can be diffed against a REAL one. Very chatty; trace-gated.
if not PB_UTIL._torch_ps_hooked then
    PB_UTIL._torch_ps_hooked = true
    local _ps = pseudoseed
    function pseudoseed(key, predict_seed)
        if PB_UTIL._torch_debug and PB_UTIL._torch_trace and type(key) == 'string' then
            PB_UTIL.torch_debug('  ps[' .. PB_UTIL._torch_trace .. '] ' .. key)
        end
        return _ps(key, predict_seed)
    end
end

-- pcall-guarded public wrappers (each pack peeked from the SAME current RNG state).
function PB_UTIL.torch_peek_rerolls(n)
    PB_UTIL._torch_trace = 'PEEK'
    local r = with_frozen_rng(function() return peek_rerolls(n) end)
    PB_UTIL._torch_trace = nil
    return r
end

function PB_UTIL.torch_peek_packs()
    local result = {}
    local boosters = (G.shop_booster and G.shop_booster.cards) or {}
    for _, b in ipairs(boosters) do
        local name = (b.ability and b.ability.name) or 'Booster'
        local cards = with_frozen_rng(function() return peek_pack(b) end)
        result[#result + 1] = { name = name, cards = cards }
    end
    return result
end

-- ── Modal ─────────────────────────────────────────────────────────────────
-- Make a generated card a pure DISPLAY object: non-collidable (so the controller's hit-test
-- skips it -- clicks reach the Close button and the card never becomes a hover/drag/focus
-- target that would dangle when destroyed), no hover tooltip (no_ui), no drag. Mirrors the
-- base game's inert display cards (UI_definitions.lua:2750/4450) and is the key fix for the
-- "modal frozen / dead Close button" bug.
-- Recursively flag a moveable and its child sprites as created_on_pause=true. The preview cards
-- are generated UNPAUSED (so pseudoseed stays deterministic -- see open_torch_preview), giving
-- them created_on_pause=false; but the modal is shown PAUSED, and Moveable:move (moveable.lua:281)
-- skips alignment for created_on_pause=false objects while paused -- so neither the card nor its
-- center sprite would move into the slot. Stamping the flag makes them render in the paused overlay.
local function stamp_created_on_pause(obj, depth)
    if type(obj) ~= 'table' or (depth or 0) > 4 then return end
    if obj.created_on_pause ~= nil then obj.created_on_pause = true end
    if type(obj.children) == 'table' then
        for _, ch in pairs(obj.children) do stamp_created_on_pause(ch, (depth or 0) + 1) end
    end
end

local function make_card_inert(card)
    if not card or not card.states then return end
    card.states.visible = true
    stamp_created_on_pause(card, 0)
    if card.states.collide then card.states.collide.can = false; card.states.collide.is = false end
    if card.states.hover then card.states.hover.can = false; card.states.hover.is = false end
    if card.states.click then card.states.click.can = false end
    if card.states.drag then card.states.drag.can = false; card.states.drag.is = false end
    card.no_ui = true
    -- Suppress the run-stake sticker (the white chip): it's drawn by a shared sticker object
    -- at the card's full-scale transform, so it floats outside our downscaled preview card
    -- (card.lua:4925). It's purely cosmetic (same stake for the whole run), so hide it.
    card.sticker = nil
    card.sticker_run = 'NONE'
    -- Consumables (Tarot/Planet/Spectral) call start_materialize() on creation, which sets
    -- dissolve=1 and spawns a materialize particle cloud; its completion events (dissolve->0,
    -- particle removal -- card.lua:2628-2643) were dropped by the peek's add_event stub, so the
    -- card is stuck showing only particles. Settle it instantly here.
    card.dissolve = 0
    if card.children and card.children.particles then
        card.children.particles:remove()
        card.children.particles = nil
    end
end

-- One labelled row of preview cards. Each card sits in its own single-slot, invisible
-- ('title_2') CardArea -- the proven crafting-grid pattern -- registered in torch_slots so
-- update_torch_modal can snap + scale it each frame (title_2 align is a no-op).
local function torch_card_row(label, cards, empty_text)
    local content
    if cards and #cards > 0 then
        local cells = {}
        for _, card in ipairs(cards) do
            local area = CardArea(G.ROOM.T.x, G.ROOM.T.y, slot_w(), slot_h(),
                { card_limit = 1, type = 'title_2', highlight_limit = 0, card_w = slot_w(), no_card_count = true })
            if card.area then card.area:remove_card(card) end
            area:emplace(card)
            make_card_inert(card)   -- AFTER emplace: emplace/set_ranks can re-enable drag on title_2
            PB_UTIL.torch_slots[#PB_UTIL.torch_slots + 1] = { area = area, card = card }
            cells[#cells + 1] = {
                n = G.UIT.C, config = { align = 'cm', padding = 0.06 },
                nodes = { { n = G.UIT.O, config = { object = area } } },
            }
        end
        content = { n = G.UIT.C, config = { align = 'cl', padding = 0.04 }, nodes = cells }
    else
        content = { n = G.UIT.C, config = { align = 'cl', padding = 0.1 }, nodes = {
            { n = G.UIT.T, config = { text = empty_text or 'Preview unavailable',
                scale = 0.36, colour = G.C.UI.TEXT_INACTIVE } },
        } }
    end
    return {
        n = G.UIT.R, config = { align = 'cm', padding = 0.05 },
        nodes = {
            { n = G.UIT.C, config = { align = 'cr', minw = 2.6, padding = 0.05 }, nodes = {
                { n = G.UIT.T, config = { text = label, scale = 0.42, colour = G.C.WHITE } },
            } },
            content,
        },
    }
end

function PB_UTIL.build_torch_modal(rerolls, packs)
    local rows = {}
    rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.06 }, nodes = {
        { n = G.UIT.T, config = { text = 'Torch -- Peek the Shop', scale = 0.6, colour = G.C.UI.TEXT_LIGHT } },
    } }

    -- Mechanic note: every preview is a snapshot of the shop AS IT IS NOW, i.e. what you'd get if
    -- that is your very next action. Acting first (rerolling/buying) changes the shared state
    -- (used_jokers pool, some RNG) so the other previews no longer hold. Make that explicit so the
    -- player isn't surprised when an after-a-reroll pack differs from what was shown.
    rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.02 }, nodes = {
        { n = G.UIT.T, config = { text = "Each preview is what you'd get if it's your next action.",
            scale = 0.32, colour = G.C.UI.TEXT_INACTIVE } },
    } }
    rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.02 }, nodes = {
        { n = G.UIT.T, config = { text = 'Rerolling or buying first will change the others.',
            scale = 0.32, colour = G.C.UI.TEXT_INACTIVE } },
    } }

    -- Reroll sections.
    rerolls = rerolls or {}
    rows[#rows + 1] = torch_card_row('Next reroll', rerolls[1], 'Preview unavailable')
    rows[#rows + 1] = torch_card_row('2nd reroll', rerolls[2], 'Preview unavailable')

    -- One section per booster pack.
    if packs and #packs > 0 then
        for _, p in ipairs(packs) do
            rows[#rows + 1] = torch_card_row(p.name, p.cards, 'Preview unavailable')
        end
    else
        rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.08 }, nodes = {
            { n = G.UIT.T, config = { text = 'No booster packs in the shop.',
                scale = 0.36, colour = G.C.UI.TEXT_INACTIVE } },
        } }
    end

    -- Close (full width, classic orange). Cleanup runs in the exit_overlay_menu wrap below.
    rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cm', minh = 0.2 }, nodes = {} }
    rows[#rows + 1] = {
        n = G.UIT.R,
        config = { align = 'cm', minw = 8, padding = 0.1, r = 0.1, hover = true,
            colour = G.C.ORANGE, button = 'exit_overlay_menu', shadow = true },
        nodes = { { n = G.UIT.T, config = { text = 'Close', scale = 0.5, colour = G.C.WHITE } } },
    }

    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0.12, r = 0.1, colour = G.C.GREY, minw = 9, minh = 5 },
        nodes = rows,
    }
end

function PB_UTIL.open_torch_preview()
    if G.OVERLAY_MENU then return end   -- never stack over an existing overlay
    PB_UTIL.torch_slots = {}
    -- Peek FIRST, while still UNPAUSED. This is critical: pseudoseed() returns a non-deterministic
    -- math.random() (and does NOT advance the counter) whenever G.SETTINGS.paused is true
    -- (misc_functions.lua:330). So if we pause before peeking, every prediction is random garbage.
    -- The real reroll runs unpaused, so the peek must too, to match it.
    if PB_UTIL._torch_debug then
        PB_UTIL.torch_debug('=== TORCH USED (ante ' .. tostring(G.GAME.round_resets and G.GAME.round_resets.ante) .. ') ===')
        rng_fingerprint('BEFORE_PEEK')
    end
    local rerolls = PB_UTIL.torch_peek_rerolls(2)
    local packs = PB_UTIL.torch_peek_packs()
    if PB_UTIL._torch_debug then
        PB_UTIL.torch_debug('PREDICT reroll 1: ' .. card_keys(rerolls and rerolls[1]))
        PB_UTIL.torch_debug('PREDICT reroll 2: ' .. card_keys(rerolls and rerolls[2]))
        for _, p in ipairs(packs or {}) do
            PB_UTIL.torch_debug('PREDICT pack [' .. tostring(p.name) .. ']: ' .. card_keys(p.cards))
        end
        rng_fingerprint('AFTER_PEEK')
    end
    -- NOW pause for display. The pause is still needed: overlay_menu does not pause
    -- (button_callbacks.lua:1344), so without it the live shop keeps the controller and the Close
    -- button can't hold focus (the freeze). The preview cards were made unpaused
    -- (created_on_pause=false); make_card_inert flips that flag to true so they still render in the
    -- paused overlay (Moveable:move/controller require created_on_pause==paused). exit_overlay_menu
    -- unpauses on close.
    G.SETTINGS.paused = true
    ctrl_state('OPEN torch overlay')
    G.FUNCS.overlay_menu { definition = PB_UTIL.build_torch_modal(rerolls, packs) }
end

-- Open the preview AFTER the consumable use-flow has fully torn down. use_card
-- (button_callbacks.lua:2245-2403) sets G.STATE=PLAY_TAROT, locks.use=true and slides the shop
-- off-screen, then restores all of it via a deferred event chain. Opening the overlay
-- synchronously inside that flow leaves the consumable state machine half-built -- which is what
-- made the NEXT consumable get used-on-click. So we poll, on a NON-BLOCKING event (a blocking
-- poll would stall the very teardown we wait on -> freeze), until we are back to a clean shop.
function PB_UTIL.schedule_torch_preview()
    local waited = 0
    G.E_MANAGER:add_event(Event({
        trigger = 'immediate',
        blocking = false,
        blockable = false,
        func = function()
            waited = waited + 1
            local locked = G.CONTROLLER and G.CONTROLLER.locks and G.CONTROLLER.locks.use
            local clean = (G.STATE == G.STATES.SHOP) and not locked
            -- ~10s safety net: never silently swallow the torch if the teardown is interrupted.
            if clean or waited > 600 then
                PB_UTIL.open_torch_preview()
                return true
            end
            return false
        end,
    }))
end

-- Per-frame snap + scale of every preview card to its slot centre (title_2 align is a no-op,
-- and the slot area only resolves its real position after overlay layout -- same reason the
-- crafting inventory snaps each frame). Inert when no torch modal is open.
function PB_UTIL.update_torch_modal()
    if not PB_UTIL.torch_slots then return end
    local cw, ch = (G.CARD_W or 1.27), (G.CARD_H or 1.78)
    for _, s in ipairs(PB_UTIL.torch_slots) do
        local a, card = s.area, s.card
        if a and card then
            -- Scale the card via the engine-native uniform scale (T.scale/VT.scale), NOT by
            -- shrinking T.w/h. The body (Sprite:draw_self) shrinks by VT.w/h, but edition shaders'
            -- soul/overlay sprites (Sprite:draw_from, sprite.lua:199-200) shrink by VT.scale -- so
            -- a T.w/h-only shrink leaves those overlays at full size. Keeping T.w/h natural and
            -- setting T.scale shrinks every layer together. Centre the scaled card in its slot
            -- (prep_draw scales around VT.x + VT.w/2).
            card.T.w, card.T.h = cw, ch
            card.T.scale = CARD_SCALE
            card.VT.scale = CARD_SCALE
            local tx = a.T.x + a.T.w / 2 - cw / 2
            local ty = a.T.y + a.T.h / 2 - ch / 2
            card.T.x, card.T.y = tx, ty
            card.VT.x, card.VT.y = tx, ty
        end
    end
end

-- Destroy every preview slot (CardArea:remove destroys its card too). Idempotent.
-- The cards are non-collidable (make_card_inert), so the controller never targets them and
-- there is nothing to null out here -- doing so corrupted the controller's click state.
function PB_UTIL.destroy_torch_slots()
    if PB_UTIL.torch_slots then
        for _, s in ipairs(PB_UTIL.torch_slots) do
            if s.area then pcall(function() s.area:remove() end) end
        end
        PB_UTIL.torch_slots = nil
    end
end

-- Drive the per-frame snap. Separate, guarded Game:update wrap (chains with the others).
if not PB_UTIL._torch_update_hooked then
    PB_UTIL._torch_update_hooked = true
    local _upd = Game.update
    function Game:update(dt)
        _upd(self, dt)
        if PB_UTIL.torch_slots then PB_UTIL.update_torch_modal() end
    end
end

-- Clean up preview cards whenever an overlay closes while ours are live. Guarded on our own
-- state so it composes with the crafting exit wrap.
if not PB_UTIL._torch_exit_hooked then
    PB_UTIL._torch_exit_hooked = true
    local _orig_exit = G.FUNCS.exit_overlay_menu
    G.FUNCS.exit_overlay_menu = function(...)
        local was_torch = PB_UTIL.torch_slots ~= nil
        if was_torch then
            ctrl_state('EXIT pre  (torch live)')
            PB_UTIL.destroy_torch_slots()   -- already pcall-guarded internally
        end
        -- ALWAYS run the real exit (unpause + remove overlay), even if cleanup above hiccuped.
        local ret = _orig_exit(...)
        if was_torch then
            ctrl_state('EXIT post (orig_exit done)')
            -- Re-check once the pending use-flow/focus events have resumed after unpause: this is
            -- where a stuck pause / lingering lock would show up if the shop is dead after close.
            if PB_UTIL._torch_debug then
                G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.4, blocking = false,
                    func = function() ctrl_state('POST-CLOSE +0.4s'); return true end }))
            end
        end
        return ret
    end
end

-- DEBUG ONLY: log the ACTUAL cards a real reroll produced, so they can be diffed against the
-- torch's PREDICT lines in balacraft_torch_debug.log. Reads the shop AFTER the reroll's
-- create-cards event has run (delay covers the 'immediate' generation event). No-op unless
-- PB_UTIL._torch_debug. Guarded so it wraps reroll_shop exactly once.
if not PB_UTIL._torch_reroll_log_hooked then
    PB_UTIL._torch_reroll_log_hooked = true
    local _orig_reroll = G.FUNCS.reroll_shop
    if _orig_reroll then
        G.FUNCS.reroll_shop = function(...)
            if PB_UTIL._torch_debug then rng_fingerprint('BEFORE_REROLL') end
            -- Trace the real generation (which runs in an immediate event after this returns) so its
            -- CCFS lines can be diffed against the PEEK lines. Cleared once generation has run.
            if PB_UTIL._torch_debug then PB_UTIL._torch_trace = 'REAL' end
            local ret = _orig_reroll(...)
            if PB_UTIL._torch_debug then
                G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.3, blocking = false, func = function()
                    PB_UTIL._torch_trace = nil
                    local cards = (G.shop_jokers and G.shop_jokers.cards) or {}
                    PB_UTIL.torch_debug('ACTUAL reroll  : ' .. card_keys(cards))
                    return true
                end }))
            end
            return ret
        end
    end
end

-- DEBUG ONLY: log the ACTUAL contents a booster pack produces when really opened, to diff
-- against the torch's PREDICT pack lines. Wraps Card:open once; reads G.pack_cards after the
-- open populates it.
if not PB_UTIL._torch_packopen_log_hooked then
    PB_UTIL._torch_packopen_log_hooked = true
    local _open = Card.open
    function Card:open(...)
        local nm = (self.ability and self.ability.name) or '?'
        if PB_UTIL._torch_debug then rng_fingerprint('BEFORE_PACKOPEN [' .. tostring(nm) .. ']') end
        local r = _open(self, ...)
        if PB_UTIL._torch_debug then
            -- Card:open fills G.pack_cards from a nested event ~1.7s later (card.lua:2070), so poll
            -- until it's populated instead of probing once too early.
            local waited = 0
            G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.1, blocking = false, blockable = false, func = function()
                waited = waited + 1
                local pc = G.pack_cards and G.pack_cards.cards
                if (pc and #pc > 0) or waited > 300 then
                    PB_UTIL.torch_debug('ACTUAL pack [' .. tostring(nm) .. ']: ' .. card_keys(pc))
                    return true
                end
                return false
            end }))
        end
        return r
    end
end
