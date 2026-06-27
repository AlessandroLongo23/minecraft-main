-- Villager Trading: offer generation + shop integration + emerald-priced buy.
-- Data/templates in content/villager/trades.lua; UI in utilities/villager_ui.lua.
-- State lives on G.GAME.balacraft (plain tables/numbers -> auto-saved within a run, auto-reset
-- per run; seeded in resources.lua's init_game_object wrapper). No custom save/load.

local N_OFFERS = 3   -- offers shown per shop (tunable)

-- Build the concrete candidate offers for ONE profession. Each candidate carries `tkey` (a
-- sub-category key) + a `weight`, so build_villager_offers weights by SUB-CATEGORY (e.g. the tool
-- TYPE, the book ENCHANT, the resource TIER) rather than by raw candidate count -- so you don't get
-- three swords or three Sharpness books. Also carries `icon = { atlas, pos }` (a small 34x34 icon
-- cell) so the UI shows item icons, not scaled-down cards. `atlas` MUST be the registered atlas
-- object's resolved `.key` (e.g. PB_UTIL.food_icon_atlas.key), NOT the literal 'bc_food_icons':
-- SMODS prefixes atlas keys with the mod prefix, so the raw string is absent from G.ASSET_ATLAS and
-- the UI's lookup would fall back to a blank spacer. `kind` is 'resource' (a bundle granted
-- via add_resource) or 'consumable' (a card granted via consumable_add). Reads the live registries,
-- so it must run at RUNTIME; keys whose center isn't registered are skipped (never grant a no-op).
function PB_UTIL.villager_candidates(profession)
    profession = profession or 'toolsmith'
    local out = {}
    local function add(c) out[#out + 1] = c end

    if profession == 'toolsmith' then
        -- All tools: swords + pickaxes + shovels. Weighted by tool TYPE so the mix varies.
        for _, tool in ipairs(PB_UTIL.TOOLS or {}) do
            local key = 'c_balacraft_tool_' .. tool.id
            if G and G.P_CENTERS and G.P_CENTERS[key] then
                add({
                    kind = 'consumable', key = key, label = tool.name,
                    cost = (PB_UTIL.VILLAGER_TOOL_COST or {})[tool.tier] or 5,
                    weight = 1, tkey = 'tool_' .. tool.tool,
                    icon = { atlas = PB_UTIL.tool_icon_atlas and PB_UTIL.tool_icon_atlas.key, pos = (PB_UTIL.tool_icon_pos or {})[key] },
                })
            end
        end

    elseif profession == 'librarian' then
        -- Enchant books (weighted by enchant type) + the Torch (MC Librarians sell lanterns).
        for _, b in ipairs(PB_UTIL.ENCHANT_BOOKS or {}) do
            local key = 'c_balacraft_enchant_' .. b.id
            if G and G.P_CENTERS and G.P_CENTERS[key] then
                add({
                    kind = 'consumable', key = key, label = b.name,
                    cost = (PB_UTIL.VILLAGER_BOOK_COST or {})[b.tier] or 6,
                    weight = 1, tkey = 'book_' .. b.etype,
                    icon = { atlas = PB_UTIL.enchant_icon_atlas and PB_UTIL.enchant_icon_atlas.key, pos = b.pos },
                })
            end
        end
        local tkey = 'c_balacraft_torch'
        if G and G.P_CENTERS and G.P_CENTERS[tkey] then
            add({
                kind = 'consumable', key = tkey, label = 'Torch',
                cost = PB_UTIL.VILLAGER_TORCH_COST or 2, weight = 1, tkey = 'torch',
                icon = { atlas = PB_UTIL.tool_icon_atlas and PB_UTIL.tool_icon_atlas.key, pos = { x = 0, y = 3 } },
            })
        end

    elseif profession == 'mason' then
        -- Ore/resource bundles (the VILLAGER_TRADES resource templates; emerald never bundled).
        for ti, t in ipairs(PB_UTIL.VILLAGER_TRADES or {}) do
            if t.kind == 'resource' then
                for _, r in ipairs(PB_UTIL.RESOURCES or {}) do
                    -- ORE bundles only (the documented intent): drop_class == 'ore' keeps mob
                    -- materials AND smelt-only refined ingots (iron/gold) out of the mason pool --
                    -- you trade for raw_iron/raw_gold and smelt them yourself.
                    if r.kind == 'gathered' and r.drop_class == 'ore' and r.tier == t.tier and r.id ~= 'emerald' then
                        add({
                            kind = 'resource', id = r.id, amount = t.amount, cost = t.cost,
                            label = t.amount .. 'x ' .. r.name, weight = t.weight or 1,
                            tkey = 'res_' .. t.tier,
                            icon = { atlas = PB_UTIL.icon_atlas and PB_UTIL.icon_atlas.key, pos = r.pos },
                        })
                    end
                end
            end
        end

    elseif profession == 'farmer' then
        -- Food consumables (weighted by tier).
        for _, f in ipairs(PB_UTIL.FOODS or {}) do
            local key = 'c_balacraft_food_' .. f.id
            if G and G.P_CENTERS and G.P_CENTERS[key] then
                add({
                    kind = 'consumable', key = key, label = f.name,
                    cost = (PB_UTIL.VILLAGER_FOOD_COST or {})[f.tier] or 2,
                    weight = 1, tkey = 'food_' .. f.tier,
                    icon = { atlas = PB_UTIL.food_icon_atlas and PB_UTIL.food_icon_atlas.key, pos = f.pos },
                })
            end
        end
    end

    return out
end

-- Pick this shop's profession, deterministic per shop (ante+round). Preserved across rerolls.
function PB_UTIL.pick_villager_profession(ante, round)
    local order = {}
    for _, p in ipairs(PB_UTIL.VILLAGER_PROFESSIONS or {}) do order[#order + 1] = p.id end
    if #order == 0 then return 'toolsmith' end
    return pseudorandom_element(order, pseudoseed('bc_villager_prof_' .. ante .. '_' .. round))
end

-- Draw up to `n` DISTINCT offers, run-seeded deterministic. TWO-STAGE so the template `weight` is
-- the per-CATEGORY probability (bundles common, tools rarer) regardless of how many concrete
-- candidates a template expands to (there are many more tool candidates than bundle ones):
--   1) pick a TEMPLATE weighted by its `weight` (only templates with candidates left),
--   2) pick a concrete candidate UNIFORMLY within that template, removing it (no replacement ->
--      distinct offers). Mirrors sample_pack_ores' weighted index-pool draw per stage.
function PB_UTIL.build_villager_offers(n, seed_key, profession)
    -- Group candidates by sub-category (preserving first-seen order).
    local groups, order = {}, {}
    for _, c in ipairs(PB_UTIL.villager_candidates(profession)) do
        local g = groups[c.tkey]
        if not g then g = { weight = c.weight or 1, items = {} }; groups[c.tkey] = g; order[#order + 1] = c.tkey end
        g.items[#g.items + 1] = c
    end

    local picked = {}
    n = n or N_OFFERS
    for _ = 1, n do
        -- Stage 1: weighted pool of template keys that still have candidates.
        local tpool = {}
        for _, k in ipairs(order) do
            local g = groups[k]
            if g and #g.items > 0 then
                for _ = 1, (g.weight or 1) do tpool[#tpool + 1] = k end
            end
        end
        if #tpool == 0 then break end
        local tkey = pseudorandom_element(tpool, pseudoseed(seed_key))
        -- Stage 2: uniform pick of a concrete candidate within that template (by index pool).
        local items = groups[tkey].items
        local ipool = {}
        for i = 1, #items do ipool[i] = i end
        local ci = pseudorandom_element(ipool, pseudoseed(seed_key))
        local c = items[ci]
        picked[#picked + 1] = {
            kind = c.kind, id = c.id, amount = c.amount, key = c.key,
            label = c.label, cost = c.cost, icon = c.icon, sold = false,
        }
        table.remove(items, ci)
    end
    return picked
end

-- Seed the current shop's offers. The PROFESSION is chosen once per shop visit and preserved
-- across rerolls (so a reroll re-rolls the trades, not the trader). seed_key varies per shop
-- (ante+round) and per reroll (villager_reroll_index), so rerolls produce different sets
-- deterministically.
function PB_UTIL.seed_villager_offers()
    local bc = G and G.GAME and G.GAME.balacraft
    if not bc then return end
    local ante  = (G.GAME.round_resets and G.GAME.round_resets.ante) or 1
    local round = G.GAME.round or 0
    if not bc.villager_profession then
        bc.villager_profession = PB_UTIL.pick_villager_profession(ante, round)
    end
    local ri    = bc.villager_reroll_index or 0
    bc.villager_offers = PB_UTIL.build_villager_offers(N_OFFERS,
        'bc_villager_' .. ante .. '_' .. round .. '_' .. ri, bc.villager_profession)
    bc._villager_dirty = true
end

-- Can `offer` be bought right now? (affordable, not sold, and -- for tool offers -- a free
-- consumable slot exists). Used by both the per-frame gate and the buy callback.
function PB_UTIL.can_buy_villager_offer(offer)
    if not offer or offer.sold then return false end
    if PB_UTIL.get_resource_count('emerald') < (offer.cost or 0) then return false end
    if offer.kind == 'consumable' then
        -- Card outputs (tools / books / torch / food) need a free Minecraft consumable slot OR
        -- inventory room (they auto-equip, else store).
        if not (PB_UTIL.has_consumable_room and PB_UTIL.has_consumable_room()) then return false end
    elseif offer.kind == 'resource' then
        -- Resource bundles must fit the inventory's real capacity (else Emeralds buy nothing).
        if PB_UTIL.inv_can_fit_resource and not PB_UTIL.inv_can_fit_resource(offer.id, offer.amount or 1) then
            return false
        end
    end
    return true
end

-- ---- Engine hooks (each self-skips when its global is absent, so the headless test can load
-- ---- this file without a running game). ----

-- Reset the per-visit seed flag when heading to the shop (mirrors biomes.lua's cash_out wrap),
-- so each shop visit re-seeds a fresh set of offers.
if G and G.FUNCS and G.FUNCS.cash_out then
    local _cash_out = G.FUNCS.cash_out
    G.FUNCS.cash_out = function(e)
        _cash_out(e)
        if G.GAME and G.GAME.balacraft then
            G.GAME.balacraft._villager_seeded = false
            G.GAME.balacraft.villager_reroll_index = 0
            G.GAME.balacraft.villager_profession = nil                       -- fresh trader next shop
            G.GAME.balacraft.villager_reroll_cost = PB_UTIL.VILLAGER_REROLL_BASE or 1  -- reset reroll price
        end
    end
end

-- Seed offers once the shop is built (mirrors biomes.lua's update_shop wrap). _villager_seeded is
-- a plain bool on G.GAME.balacraft -> saved, so a reload mid-shop keeps the existing offers.
if Game and Game.update_shop then
    local _update_shop = Game.update_shop
    function Game:update_shop(dt)
        _update_shop(self, dt)
        local bc = G.GAME and G.GAME.balacraft
        if bc and G.shop and not bc._villager_seeded then
            PB_UTIL.seed_villager_offers()
            bc._villager_seeded = true
        end
    end
end

-- DECOUPLED reroll: the villager has its OWN reroll, paid in Emeralds, independent of the base
-- shop's $ reroll. (Previously a reroll_shop wrap re-seeded villager offers on every base reroll,
-- so rerolling the normal shop silently changed the villager's offers -- and vice versa.) The base
-- reroll is now left untouched; only bc_reroll_villager below re-seeds the villager.

-- ---- Buy buttons ----

-- Per-frame gate (mirrors vanilla G.FUNCS.can_buy): green+enabled when buyable, greyed+disabled
-- otherwise.
if G and G.FUNCS then
    G.FUNCS.bc_can_buy_villager = function(e)
        local offer = e.config.ref_table
        if PB_UTIL.can_buy_villager_offer(offer) then
            e.config.colour = G.C.GREEN
            e.config.button = 'bc_buy_villager_offer'
        else
            e.config.colour = G.C.UI.BACKGROUND_INACTIVE
            e.config.button = nil
        end
    end

    G.FUNCS.bc_buy_villager_offer = function(e)
        local offer = e.config.ref_table
        if not PB_UTIL.can_buy_villager_offer(offer) then return end
        PB_UTIL.add_resource('emerald', -offer.cost)
        if offer.kind == 'resource' then
            PB_UTIL.add_resource(offer.id, offer.amount)
        else
            consumable_add(offer.key)
        end
        offer.sold = true
        if G.GAME and G.GAME.balacraft then G.GAME.balacraft._villager_dirty = true end
        play_sound('cardSlide1')
    end

    -- ---- Independent (Emerald) villager reroll ----

    -- True when the player can afford the current villager reroll.
    PB_UTIL.can_reroll_villager = function()
        local bc = G.GAME and G.GAME.balacraft
        local cost = (bc and bc.villager_reroll_cost) or PB_UTIL.VILLAGER_REROLL_BASE or 1
        return bc ~= nil and PB_UTIL.get_resource_count('emerald') >= cost
    end

    -- Per-frame gate for the villager reroll button (mirrors bc_can_buy_villager).
    G.FUNCS.bc_can_reroll_villager = function(e)
        if PB_UTIL.can_reroll_villager() then
            e.config.colour = G.C.GREEN
            e.config.button = 'bc_reroll_villager'
        else
            e.config.colour = G.C.UI.BACKGROUND_INACTIVE
            e.config.button = nil
        end
    end

    -- Reroll ONLY the villager's trades (keeps the profession). Spends Emeralds; cost rises +1 each
    -- reroll and resets per shop visit (cash_out wrap). seed_villager_offers sets _villager_dirty,
    -- so the overlay rebuilds with the new offers next frame.
    G.FUNCS.bc_reroll_villager = function(e)
        local bc = G.GAME and G.GAME.balacraft
        if not bc then return end
        local cost = bc.villager_reroll_cost or PB_UTIL.VILLAGER_REROLL_BASE or 1
        if PB_UTIL.get_resource_count('emerald') < cost then return end
        PB_UTIL.add_resource('emerald', -cost)
        bc.villager_reroll_index = (bc.villager_reroll_index or 0) + 1
        bc.villager_reroll_cost = cost + 1
        PB_UTIL.seed_villager_offers()
        play_sound('cardSlide1')
    end
end
