-- The Brewing Stand (Base station) — fuel, brew recipes, and dimension-themed ingredient drops.
--
-- A faithful Minecraft brewing chain, fed by Crafting-Table sub-crafts (content/resources/recipes.lua):
--   Glass Bottle  -> (fill)        Water Bottle
--   Water Bottle  + Nether Wart -> Awkward Potion        (the base for every effect potion)
--   Awkward Potion + ingredient -> an effect potion       (Splash for the throwables, +Gunpowder)
-- Blaze Powder is the FUEL: 1 Blaze Powder = PB_UTIL.FUEL_PER_BLAZE brew charges, spent one per brew.
-- Brew modifiers (Glowstone/Redstone/Dragon's Breath) consume one extra ingredient and stamp a flag
-- on the produced potion card (read by utilities/potions.lua). State is plain values on
-- G.GAME.balacraft (auto-save / auto-reset; no custom save code), like the Furnace's fuel buffer.

PB_UTIL.FUEL_PER_BLAZE = 3   -- charges granted per Blaze Powder consumed (tunable)

-- Modifier -> the resource it consumes (and the ability.extra flag it stamps).
PB_UTIL.BREW_MOD_INGREDIENT = { potency = 'glowstone_dust', duration = 'redstone', lingering = 'dragon_breath' }

-- ---- Seed the fuel buffer + the single persistent brewing bottle ----
-- Both are plain values on G.GAME.balacraft (auto-saved within a run, auto-reset per run; no custom
-- save/load). brew_bottle holds the ONE in-progress bottle the spatial Brewing Stand shows; its
-- progress persists across closing the stand (MC-like). content: 'empty'|'water'|'awkward'|<potion
-- id>|<intermediate id>; mods: a set of stamped modifier flags (only on finished potions).
local _init_game_object = Game.init_game_object
function Game:init_game_object()
    local t = _init_game_object(self)
    t.balacraft = t.balacraft or {}
    t.balacraft.brew_fuel = 0
    t.balacraft.brew_bottle = { content = 'empty', mods = {} }
    return t
end

-- Live accessor for the persistent bottle (lazy-init so runs saved before this code still work).
function PB_UTIL.brew_bottle_state()
    local bc = G.GAME and G.GAME.balacraft
    if not bc then return nil end
    if not bc.brew_bottle then bc.brew_bottle = { content = 'empty', mods = {} } end
    bc.brew_bottle.mods = bc.brew_bottle.mods or {}
    return bc.brew_bottle
end

function PB_UTIL.get_brew_fuel()
    local bc = G.GAME and G.GAME.balacraft
    return (bc and bc.brew_fuel) or 0
end

-- Spend 1 Blaze Powder from inventory -> +FUEL_PER_BLAZE charges. Returns true on success.
function PB_UTIL.brew_add_fuel()
    if PB_UTIL.get_resource_count('blaze_powder') < 1 then return false end
    PB_UTIL.add_resource('blaze_powder', -1)
    G.GAME.balacraft.brew_fuel = PB_UTIL.get_brew_fuel() + PB_UTIL.FUEL_PER_BLAZE
    return true
end

-- (The legacy flat-recipe tables BREW_RECIPES/POTION_ING + can_brew/do_brew were removed with the
-- recipe-list UI. The spatial Brewing Stand uses the sequential transition engine below; the
-- ingredient economy now lives in BREW_TRANSITIONS, and Water Bottles are crafted at the Crafting
-- Table -- there is no glass_bottle -> water_bottle brew step.)

-- ---- Spatial Brewing Stand: sequential transition data ----
-- The stand feeds ONE ingredient at a time into the bottle (Minecraft order: Nether Wart -> a base
-- ingredient -> optional modifiers). BREW_TRANSITIONS[content][ingredient] = the new content. The
-- two-step potions keep every current ingredient meaningful: Spider Eye/Fermented Spider Eye make a
-- NON-collectible intermediate (poison_pre / harming_pre) that Gunpowder finishes into the Splash
-- potion; Golden Carrot makes Night Vision, which Fermented Spider Eye corrupts into Invisibility.
PB_UTIL.BREW_TRANSITIONS = {
    water   = { nether_wart = 'awkward' },
    awkward = {
        sugar = 'swiftness', blaze_powder = 'strength', glistering_melon = 'instant_health',
        ghast_tear = 'healing', golden_carrot = 'night_vision',
        spider_eye = 'poison_pre', fermented_spider_eye = 'harming_pre',
    },
    night_vision = { fermented_spider_eye = 'invisibility' },
    poison_pre   = { gunpowder = 'poison' },
    harming_pre  = { gunpowder = 'harming' },
}

-- Modifier resource -> the ability.extra flag it stamps (inverse of BREW_MOD_INGREDIENT).
PB_UTIL.BREW_MOD_BY_ING = {}
for flag, rid in pairs(PB_UTIL.BREW_MOD_INGREDIENT) do PB_UTIL.BREW_MOD_BY_ING[rid] = flag end

-- Every resource the top ingredient slot accepts (all transition ingredients + the 3 modifiers).
PB_UTIL.BREW_INGREDIENT_ACCEPTS = {}
for _, row in pairs(PB_UTIL.BREW_TRANSITIONS) do
    for ing in pairs(row) do PB_UTIL.BREW_INGREDIENT_ACCEPTS[ing] = true end
end
for rid in pairs(PB_UTIL.BREW_MOD_BY_ING) do PB_UTIL.BREW_INGREDIENT_ACCEPTS[rid] = true end

-- The bottle slot accepts the starting bottles (Water Bottle, or an Awkward Potion to skip a step).
PB_UTIL.BREW_BOTTLE_ACCEPTS = { water_bottle = true, awkward_potion = true }
function PB_UTIL.brew_bottle_accepts(rid) return PB_UTIL.BREW_BOTTLE_ACCEPTS[rid] == true end

-- A content is a finished, collectible potion iff it names a registry potion (intermediates do not).
function PB_UTIL.brew_is_finished(content)
    return content ~= nil and PB_UTIL.POTION_BY_ID ~= nil and PB_UTIL.POTION_BY_ID[content] ~= nil
end

-- ---- Spatial Brewing Stand: state engine ----
-- The held ingredient = whatever tile sits in the ingredient slot (built by build_brew_cells).
function PB_UTIL.brew_held_ingredient()
    local area = PB_UTIL.brew_ingredient_area
    local card = area and area.cards and area.cards[1]
    return card and PB_UTIL.tile_resource(card) or nil
end

-- A charge is available iff the buffer has one OR a Blaze Powder tile sits in the fuel slot.
function PB_UTIL.brew_fuel_available()
    if PB_UTIL.get_brew_fuel() >= 1 then return true end
    local fa = PB_UTIL.brew_fuel_area
    local fc = fa and fa.cards and fa.cards[1]
    return (fc and PB_UTIL.tile_resource(fc)) == 'blaze_powder'
end

-- What `ing` would do to `bottle`: 'transition', new_content  |  'mod', flag  |  nil (nothing).
function PB_UTIL.brew_outcome(bottle, ing)
    if not (bottle and ing) then return nil end
    local row = PB_UTIL.BREW_TRANSITIONS[bottle.content]
    if row and row[ing] then return 'transition', row[ing] end
    local flag = PB_UTIL.BREW_MOD_BY_ING[ing]
    if flag and PB_UTIL.brew_is_finished(bottle.content) then
        local pot = PB_UTIL.POTION_BY_ID[bottle.content]
        if pot and pot.mods and pot.mods[flag] and not (bottle.mods and bottle.mods[flag]) then
            return 'mod', flag
        end
    end
    return nil
end

-- The Brew button is live iff there is fuel AND the held ingredient would advance the bottle.
function PB_UTIL.brew_can()
    if not PB_UTIL.brew_fuel_available() then return false end
    local ing = PB_UTIL.brew_held_ingredient()
    if not ing then return false end
    return PB_UTIL.brew_outcome(PB_UTIL.brew_bottle_state(), ing) ~= nil
end

-- Perform one brew step: spend 1 charge (burning a Blaze tile from the fuel slot into the buffer if
-- needed, Furnace-style) + 1 ingredient (the reserved tile is consumed, no credit; slot auto-refills
-- from inventory), then advance the bottle. Returns true on success.
function PB_UTIL.brew_step()
    local bottle = PB_UTIL.brew_bottle_state()
    local ing = PB_UTIL.brew_held_ingredient()
    if not (bottle and ing) then return false end
    local kind, val = PB_UTIL.brew_outcome(bottle, ing)
    if not kind then return false end

    -- Ensure a fuel charge.
    if PB_UTIL.get_brew_fuel() < 1 then
        local fa = PB_UTIL.brew_fuel_area
        local fc = fa and fa.cards and fa.cards[1]
        if (fc and PB_UTIL.tile_resource(fc)) ~= 'blaze_powder' then return false end
        fc:remove()   -- burn the reserved Blaze Powder tile (NO credit)
        G.GAME.balacraft.brew_fuel = (G.GAME.balacraft.brew_fuel or 0) + PB_UTIL.FUEL_PER_BLAZE
        if PB_UTIL.get_resource_count('blaze_powder') >= 1 then
            local t = PB_UTIL.spawn_reserved_tile('blaze_powder')
            if t then PB_UTIL.place_in_area(t, fa) end
        end
    end
    if PB_UTIL.get_brew_fuel() < 1 then return false end

    -- Spend the ingredient tile (reserved -> consumed, NO credit) + 1 charge, then auto-refill.
    local ia = PB_UTIL.brew_ingredient_area
    local ic = ia and ia.cards and ia.cards[1]
    if not ic then return false end
    ic:remove()
    G.GAME.balacraft.brew_fuel = G.GAME.balacraft.brew_fuel - 1
    if PB_UTIL.get_resource_count(ing) >= 1 then
        local t = PB_UTIL.spawn_reserved_tile(ing)
        if t then PB_UTIL.place_in_area(t, ia) end
    end

    -- Advance the bottle.
    if kind == 'transition' then
        -- Carry only the modifiers the NEW potion still accepts (e.g. Night Vision +Long -> Invisibility
        -- keeps Long but drops a Level II that Invisibility can't have).
        local newmods = {}
        local pot = PB_UTIL.POTION_BY_ID[val]
        if pot and pot.mods and bottle.mods then
            for f, on in pairs(bottle.mods) do if on and pot.mods[f] then newmods[f] = true end end
        end
        bottle.content = val
        bottle.mods = newmods
    else  -- 'mod'
        bottle.mods = bottle.mods or {}
        bottle.mods[val] = true
    end
    return true
end

-- True iff the bottle holds a finished potion AND there is consumable room to take it.
function PB_UTIL.brew_can_collect()
    local bottle = PB_UTIL.brew_bottle_state()
    if not (bottle and PB_UTIL.brew_is_finished(bottle.content)) then return false end
    if PB_UTIL.has_consumable_room and not PB_UTIL.has_consumable_room() then return false end
    return true
end

-- Take the finished potion out into the consumable area (with its stamped mods), then empty the bottle.
function PB_UTIL.brew_collect()
    local bottle = PB_UTIL.brew_bottle_state()
    if not (bottle and PB_UTIL.brew_is_finished(bottle.content)) then return false end
    if PB_UTIL.has_consumable_room and not PB_UTIL.has_consumable_room() then return false end
    if PB_UTIL.brew_potion(bottle.content, bottle.mods or {}) then
        bottle.content = 'empty'
        bottle.mods = {}
        return true
    end
    return false
end

-- Create the finished potion card, stamping the brew-modifier flags onto ability.extra, then route
-- it (the per-frame reconcile in mc_consumables.lua moves it into the Minecraft consumable area).
function PB_UTIL.brew_potion(potion_id, mods)
    local key = 'c_balacraft_potion_' .. potion_id
    if not G.P_CENTERS[key] then return false end
    local c = SMODS.create_card({ key = key })
    if not c then return false end
    c.ability.extra = c.ability.extra or {}
    for m, on in pairs(mods or {}) do if on then c.ability.extra[m] = true end end
    if c.set_sprites then c:set_sprites(c.config.center, c.config.front) end   -- show the variant column now
    c:add_to_deck()
    G.consumeables:emplace(c)
    -- Route it NOW into a free Minecraft slot, else the unified inventory (mirrors the netherite-forge
    -- path in furnace.lua). brew_collect already verified there's room; doing it synchronously -- rather
    -- than waiting for the per-frame sweep -- means a slots-full potion lands in inventory immediately,
    -- so the Brewing Stand can refresh and show it instead of it seeming to vanish.
    if PB_UTIL.reconcile_mc_consumables then PB_UTIL.reconcile_mc_consumables() end
    return true
end

-- ---- Dimension-themed ingredient drops (Blind:defeat wrap, composes with the others) ----
-- Brewing raws are drop_class='special' (out of every ore/mob pool); they arrive ONLY here. On each
-- blind win, grant one ingredient from the active dimension's pool (run-seeded). Tunable.
PB_UTIL.BREW_DROPS = {
    overworld = { 'sugar_cane', 'carrot', 'melon_slice', 'brown_mushroom' },
    nether    = { 'nether_wart', 'blaze_rod', 'ghast_tear', 'glowstone_dust' },
    ['end']   = { 'dragon_breath' },
}

function PB_UTIL.grant_brewing_drop()
    if not (PB_UTIL.config and PB_UTIL.config.potions_enabled and G.GAME) then return end
    local dim = (PB_UTIL.current_dimension and PB_UTIL.current_dimension()) or 'overworld'
    local pool = PB_UTIL.BREW_DROPS[dim]
    if not (pool and #pool > 0) then return end
    local id = pseudorandom_element(pool, pseudoseed('bc_brew_drop'))
    if id then PB_UTIL.add_resource(id, 1) end
end

local _brewing_blind_defeat = Blind.defeat
function Blind:defeat(silent)
    _brewing_blind_defeat(self, silent)
    pcall(PB_UTIL.grant_brewing_drop)
end
