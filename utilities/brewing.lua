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

-- ---- Seed the fuel buffer (composes with the other init_game_object wraps) ----
local _init_game_object = Game.init_game_object
function Game:init_game_object()
    local t = _init_game_object(self)
    t.balacraft = t.balacraft or {}
    t.balacraft.brew_fuel = 0
    return t
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

-- ---- Brew recipes ----
-- Each: { key, name, out = {kind='resource'|'potion', id, amount?}, ing = { {id,n}, ... } }.
-- `ing` is a flat ingredient multiset (the Brewing Stand is not pattern-matched). Splash is baked
-- into the throwables' ingredient list (Gunpowder). `mods` (potion brews) lists the modifiers the
-- potion accepts -- read from the registry so the UI offers the right toggles.
PB_UTIL.BREW_RECIPES = {
    -- Base chain (produce resources).
    { key = 'water_bottle',  name = 'Water Bottle',  out = { kind = 'resource', id = 'water_bottle' },
      ing = { { 'glass_bottle', 1 } } },
    { key = 'awkward_potion', name = 'Awkward Potion', out = { kind = 'resource', id = 'awkward_potion' },
      ing = { { 'water_bottle', 1 }, { 'nether_wart', 1 } } },
}

-- The 8 potion brews, derived from the registry so the data stays in one place. Each needs an
-- Awkward Potion + the MC effect ingredient (+ Gunpowder for the Splash throwables).
local POTION_ING = {
    swiftness      = { { 'awkward_potion', 1 }, { 'sugar', 1 } },
    strength       = { { 'awkward_potion', 1 }, { 'blaze_powder', 1 } },
    instant_health = { { 'awkward_potion', 1 }, { 'glistering_melon', 1 } },
    healing        = { { 'awkward_potion', 1 }, { 'ghast_tear', 1 } },
    night_vision   = { { 'awkward_potion', 1 }, { 'golden_carrot', 1 } },
    invisibility   = { { 'awkward_potion', 1 }, { 'golden_carrot', 1 }, { 'fermented_spider_eye', 1 } },
    poison         = { { 'awkward_potion', 1 }, { 'spider_eye', 1 }, { 'gunpowder', 1 } },
    harming        = { { 'awkward_potion', 1 }, { 'fermented_spider_eye', 1 }, { 'gunpowder', 1 } },
}
for _, p in ipairs(PB_UTIL.POTIONS or {}) do
    PB_UTIL.BREW_RECIPES[#PB_UTIL.BREW_RECIPES + 1] = {
        key = 'potion_' .. p.id, name = p.name,
        out = { kind = 'potion', id = p.id },
        ing = POTION_ING[p.id] or { { 'awkward_potion', 1 } },
        mods = p.mods or {},
    }
end

-- ---- Affordability + brewing ----
-- A brew is affordable iff: >=1 fuel charge, every ingredient on hand, every selected modifier's
-- ingredient on hand, and (for potion outputs) there is consumable room.
function PB_UTIL.can_brew(recipe, mods)
    if not recipe then return false end
    if PB_UTIL.get_brew_fuel() < 1 then return false end
    for _, pair in ipairs(recipe.ing) do
        if PB_UTIL.get_resource_count(pair[1]) < pair[2] then return false end
    end
    for m, on in pairs(mods or {}) do
        if on and PB_UTIL.get_resource_count(PB_UTIL.BREW_MOD_INGREDIENT[m] or '') < 1 then return false end
    end
    if recipe.out.kind == 'potion' then
        if PB_UTIL.has_consumable_room and not PB_UTIL.has_consumable_room() then return false end
    end
    return true
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
    return true
end

-- Spend a fuel charge + the ingredients (+ modifier ingredients) and produce the output. Returns true.
function PB_UTIL.do_brew(recipe, mods)
    if not PB_UTIL.can_brew(recipe, mods) then return false end
    G.GAME.balacraft.brew_fuel = PB_UTIL.get_brew_fuel() - 1
    for _, pair in ipairs(recipe.ing) do PB_UTIL.add_resource(pair[1], -pair[2]) end
    for m, on in pairs(mods or {}) do
        if on then PB_UTIL.add_resource(PB_UTIL.BREW_MOD_INGREDIENT[m], -1) end
    end
    if recipe.out.kind == 'resource' then
        PB_UTIL.add_resource(recipe.out.id, recipe.out.amount or 1)
    else
        PB_UTIL.brew_potion(recipe.out.id, mods)
    end
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
