-- Card enhancements ("block-cards"): Ore-Block spawn + mining, and shared helpers.
-- The SMODS.Enhancement centers live in content/card_enhancements/blocks.lua; this file
-- holds the run-flow integration (spawn on blind select, mine on play) and is loaded from
-- main.lua under card_enhancements_enabled.

-- ---- Spawn budget ----

-- Ore-block cards ADDED to the deck per tier on EACH blind select (spawn_ore_blocks is additive --
-- these accumulate on top of un-mined blocks, they are NOT a standing target). `ante` sets the tier
-- depth; the biome sets WHICH ore (via PB_UTIL.random_oreblock_of_tier). Honors the tier gate (T2
-- from ante 3, T3 from ante 6, T4 Netherite from ante 8) by leaving locked tiers at 0. Metal-focused:
-- Wood/Cobble now come mostly from blind DROPS, so the tier-1 add is modest and the metal tiers (2+)
-- carry the mining economy (~1 raw_iron/blind minable by ante 3). Tunable -- expect a playtest pass.
function PB_UTIL.oreblock_budget(ante)
    ante = ante or 1
    if ante <= 2 then return { 1.0,  0,    0,   0   }
    elseif ante <= 5 then return { 0.75, 1.25, 0,   0   }
    elseif ante <= 7 then return { 0.5,  1.0,  1.0, 0   }
    else                 return { 0.5,  1.0,  1.0, 0.5 } end
end

-- Deterministic probabilistic rounding: floor(x) plus a seeded Bernoulli on the remainder.
local function prob_round(x, seed_key)
    local base = math.floor(x)
    local frac = x - base
    if frac > 0 and pseudorandom(pseudoseed(seed_key)) < frac then base = base + 1 end
    return base
end

-- ---- Spawn ----

-- True if `card` can receive an ore block: a real playing card with NO enhancement yet.
local function is_eligible(card)
    return card and card.config and card.config.center == G.P_CENTERS.c_base
end

-- The ore id of an Ore-Block card, or nil if it isn't one. The id lives on the enhancement
-- center's config.extra.ore (and is copied onto card.ability.extra.ore when applied) -- read
-- both so detection is robust regardless of how SMODS surfaces the config. Exposed on PB_UTIL so
-- the Pickaxe/Axe mining in content/tools/tool_consumabletype.lua can detect ore-block cards too.
function PB_UTIL.oreblock_ore(c)
    if not c then return nil end
    local ctr = c.config and c.config.center
    local ore = ctr and ctr.config and ctr.config.extra and ctr.config.extra.ore
    if not ore and c.ability and c.ability.extra then ore = c.ability.extra.ore end
    return ore
end
local oreblock_ore = PB_UTIL.oreblock_ore

-- Revert an ore-block card back to a plain base card once mined (deferred a tick so it doesn't
-- fight the play/use animation). Clears the per-card `_mined` guard. Shared by the bare-hand wood
-- chop below and the tool-driven mining (tool_consumabletype.lua).
function PB_UTIL.revert_oreblock_card(card, delay)
    G.E_MANAGER:add_event(Event({ trigger = 'after', delay = delay or 0.5, func = function()
        if card and not card.REMOVED and card.set_ability then
            card:set_ability(G.P_CENTERS.c_base)
            if card.ability and card.ability.extra then card.ability.extra._mined = nil end
        end
        return true
    end }))
end

-- Place ore blocks onto random eligible draw-pile cards. ADDITIVE: each blind ADDS `target` fresh
-- blocks per tier on top of whatever is already there, so un-mined blocks ACCUMULATE across blinds
-- (the deck steadily fills with ores until you mine them). Self-limiting: when no plain base cards
-- remain eligible, placement stops. A per-blind nonce (G.GAME.round, which advances each blind) keeps
-- the three blinds in an ante independent.
function PB_UTIL.spawn_ore_blocks()
    if not (G.GAME and G.deck and G.deck.cards) then return end
    if not PB_UTIL.random_oreblock_of_tier then return end
    local ante   = (G.GAME.round_resets and G.GAME.round_resets.ante) or 1
    local nonce  = tostring(G.GAME.round or 0)
    local budget = PB_UTIL.oreblock_budget(ante)

    for tier = 1, 4 do
        local target = prob_round(budget[tier] or 0, 'bc_oreblock_' .. ante .. '_t' .. tier .. '_' .. nonce)
        -- Fresh eligible list each placement (a placed block makes its card ineligible).
        for _ = 1, target do
            local pool = {}
            for _, c in ipairs(G.deck.cards) do if is_eligible(c) then pool[#pool + 1] = c end end
            if #pool == 0 then break end
            local seed = 'bc_oreplace_' .. ante .. '_t' .. tier .. '_' .. nonce .. '_' .. #pool
            local target_card = pseudorandom_element(pool, pseudoseed(seed))
            local ore = PB_UTIL.random_oreblock_of_tier(tier, 'bc_orepick_' .. ante .. '_t' .. tier .. '_' .. nonce .. '_' .. #pool)
            if target_card and ore then
                target_card:set_ability(G.P_CENTERS['m_balacraft_block_' .. ore])
            end
        end
    end
end

-- Spawn at the moment a blind is selected (before the hand is dealt). Wrap the base
-- Blind:set_blind (same global-wrap technique resources.lua uses for Blind:defeat). `reset`
-- is true for non-selection calls (e.g. disabling); only spawn on a real selection.
local _set_blind = Blind.set_blind
function Blind:set_blind(blind, reset, silent)
    _set_blind(self, blind, reset, silent)
    if not reset then
        pcall(PB_UTIL.spawn_ore_blocks)
    end
end

-- ---- Mining ----

-- Bare-hand wood chop. Ore blocks NO LONGER auto-mine when played (the old behavior) -- the only
-- way to mine an ore is to USE a Pickaxe (or, for wood, an Axe) on selected ore-block cards (see
-- content/tools/tool_consumabletype.lua). The ONE exception is wood: you may chop it by hand by
-- playing a SINGLE wood ore-block (a one-card High Card) for +1 wood. (An Axe yields more, and can
-- take several wood cards at once.) Every other ore block just scores as its base rank and persists
-- on the card until pickaxe-mined. Wrap play_cards_from_highlighted, snapshot the lone wood card
-- BEFORE the base call moves it to G.play, then grant + revert.
if G.FUNCS and G.FUNCS.play_cards_from_highlighted then
    local _play = G.FUNCS.play_cards_from_highlighted
    G.FUNCS.play_cards_from_highlighted = function(e)
        local wood_card
        if G.hand and G.hand.highlighted and #G.hand.highlighted == 1 then
            local c = G.hand.highlighted[1]
            if oreblock_ore(c) == 'wood'
                and not (c.ability and c.ability.extra and c.ability.extra._mined) then
                wood_card = c
            end
        end
        _play(e)
        if not wood_card then return end
        if PB_UTIL.add_resource then PB_UTIL.add_resource('wood', 1) end
        wood_card.ability.extra = wood_card.ability.extra or {}
        wood_card.ability.extra._mined = true
        local res = PB_UTIL.RESOURCE_BY_ID['wood']
        card_eval_status_text(wood_card, 'extra', nil, nil, nil,
            { message = '+1 ' .. ((res and res.name) or 'Wood'), colour = G.C.GOLD })
        PB_UTIL.revert_oreblock_card(wood_card, 0.5)
    end
end
