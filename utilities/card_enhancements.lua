-- Card enhancements ("block-cards"): Ore-Block spawn + mining, and shared helpers.
-- The SMODS.Enhancement centers live in content/card_enhancements/blocks.lua; this file
-- holds the run-flow integration (spawn on blind select, mine on play) and is loaded from
-- main.lua under card_enhancements_enabled.

-- ---- Spawn budget ----

-- Expected ore-block cards per tier this blind, by ante band (spec section 3b). `ante` sets
-- the total + tier depth; the biome sets WHICH ore (via PB_UTIL.random_ore_of_tier). Honors
-- the tier gate (T2 from ante 3, T3 from ante 6, T4 Netherite from ante 8) by leaving locked
-- tiers at 0.
function PB_UTIL.oreblock_budget(ante)
    ante = ante or 1
    if ante <= 2 then return { 2.0,  0,    0,   0   }
    elseif ante <= 5 then return { 1.5,  1.0,  0,   0   }
    elseif ante <= 7 then return { 1.0,  1.5,  0.5, 0   }
    else                 return { 0.75, 1.5,  1.0, 0.5 } end
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
-- both so detection is robust regardless of how SMODS surfaces the config.
local function oreblock_ore(c)
    if not c then return nil end
    local ctr = c.config and c.config.center
    local ore = ctr and ctr.config and ctr.config.extra and ctr.config.extra.ore
    if not ore and c.ability and c.ability.extra then ore = c.ability.extra.ore end
    return ore
end

-- Count ore blocks of a given tier currently on cards anywhere in the deck (draw pile + hand),
-- so the top-up never exceeds the ante target while blocks sit unmined ("persist until mined").
local function count_oreblocks_of_tier(tier)
    local n = 0
    local areas = { G.deck and G.deck.cards, G.hand and G.hand.cards }
    for _, list in ipairs(areas) do
        for _, c in ipairs(list or {}) do
            local ore = oreblock_ore(c)
            if ore and PB_UTIL.RESOURCE_BY_ID[ore] and PB_UTIL.RESOURCE_BY_ID[ore].tier == tier then
                n = n + 1
            end
        end
    end
    return n
end

-- Place ore blocks onto random eligible draw-pile cards, topping up toward the ante target.
function PB_UTIL.spawn_ore_blocks()
    if not (G.GAME and G.deck and G.deck.cards) then return end
    if not PB_UTIL.random_ore_of_tier then return end
    local ante = (G.GAME.round_resets and G.GAME.round_resets.ante) or 1
    local budget = PB_UTIL.oreblock_budget(ante)

    for tier = 1, 4 do
        local target = prob_round(budget[tier] or 0, 'bc_oreblock_' .. ante .. '_t' .. tier)
        local deficit = target - count_oreblocks_of_tier(tier)
        if deficit > 0 then
            -- Fresh eligible list each placement (a placed block makes its card ineligible).
            for _ = 1, deficit do
                local pool = {}
                for _, c in ipairs(G.deck.cards) do if is_eligible(c) then pool[#pool + 1] = c end end
                if #pool == 0 then break end
                local seed = 'bc_oreplace_' .. ante .. '_t' .. tier .. '_' .. #pool
                local target_card = pseudorandom_element(pool, pseudoseed(seed))
                local ore = PB_UTIL.random_ore_of_tier(tier, 'bc_orepick_' .. ante .. '_t' .. tier .. '_' .. #pool)
                if target_card and ore then
                    target_card:set_ability(G.P_CENTERS['m_balacraft_block_' .. ore])
                end
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

-- When cards are played, any ore-block card grants its ore (x the per-blind Pickaxe bonus)
-- and reverts to a base card. Wrap G.FUNCS.play_cards_from_highlighted and snapshot the
-- highlighted cards BEFORE the base call moves them to G.play. Removal is deferred a tick so
-- it doesn't fight the play animation. Guard with a flag so a card mines at most once.
if G.FUNCS and G.FUNCS.play_cards_from_highlighted then
    local _play = G.FUNCS.play_cards_from_highlighted
    G.FUNCS.play_cards_from_highlighted = function(e)
        local mined = {}
        if G.hand and G.hand.highlighted then
            for _, c in ipairs(G.hand.highlighted) do
                local ore = oreblock_ore(c)
                if ore and not (c.ability and c.ability.extra and c.ability.extra._mined) then
                    mined[#mined + 1] = { card = c, ore = ore }
                end
            end
        end
        _play(e)
        if #mined == 0 then return end
        local bonus = (G.GAME and G.GAME.balacraft and G.GAME.balacraft.mine_bonus) or 0
        for _, m in ipairs(mined) do
            local amount = 1 + bonus
            if PB_UTIL.add_resource then PB_UTIL.add_resource(m.ore, amount) end
            if m.card.ability then
                m.card.ability.extra = m.card.ability.extra or {}
                m.card.ability.extra._mined = true
            end
            local res = PB_UTIL.RESOURCE_BY_ID[m.ore]
            card_eval_status_text(m.card, 'extra', nil, nil, nil,
                { message = '+' .. amount .. ' ' .. ((res and res.name) or m.ore), colour = G.C.GOLD })
            local card = m.card
            G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.5, func = function()
                if card and not card.REMOVED and card.set_ability then
                    card:set_ability(G.P_CENTERS.c_base)
                    if card.ability and card.ability.extra then card.ability.extra._mined = nil end
                end
                return true
            end }))
        end
    end
end
