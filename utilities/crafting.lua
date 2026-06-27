-- Crafting logic: affordability, joker-room, and the craft action.
-- Spends/produces through the existing PB_UTIL.add_resource funnel.

function PB_UTIL.has_joker(key)
    if not G.jokers or not G.jokers.cards then return false end
    for _, c in ipairs(G.jokers.cards) do
        if c.config and c.config.center and c.config.center.key == key then return true end
    end
    return false
end

function PB_UTIL.can_afford(recipe)
    for id, n in pairs(PB_UTIL.recipe_ingredients(recipe)) do
        if PB_UTIL.get_resource_count(id) < n then return false end
    end
    return true
end

function PB_UTIL.has_joker_room()
    if not G.jokers then return false end
    return #G.jokers.cards < G.jokers.config.card_limit
end

-- A craftable Minecraft consumable fits if a Minecraft consumable SLOT is free (auto-equip) OR the
-- inventory can store it. (The vanilla G.consumeables area is irrelevant -- MC consumables never go
-- there permanently; the reconcile sweep routes them to the MC area / inventory.)
function PB_UTIL.has_consumable_room()
    if PB_UTIL.mc_has_room and PB_UTIL.mc_has_room() then return true end
    if PB_UTIL.inv_can_fit_consumable and PB_UTIL.inv_can_fit_consumable() then return true end
    return false
end

-- Net inventory-capacity check: simulate spending the ingredients and (for a resource output)
-- producing the result, then verify the resulting resource stacks still fit. Joker/consumable/
-- station outputs only SPEND resources, so they can never overflow the inventory -- this only
-- matters for resource outputs (e.g. Sticks) whose produced stack might need a fresh slot.
function PB_UTIL.recipe_resource_fits(recipe)
    if not recipe or not PB_UTIL.inv_capacity then return true end
    local deltas = {}
    for id, n in pairs(PB_UTIL.recipe_ingredients(recipe)) do deltas[id] = (deltas[id] or 0) - n end
    if recipe.output and recipe.output.type == 'resource' then
        local oid = recipe.output.id
        deltas[oid] = (deltas[oid] or 0) + (recipe.output.amount or 1)
    end
    local delta_slots = 0
    for id, d in pairs(deltas) do
        local cur = PB_UTIL.get_resource_count(id)
        delta_slots = delta_slots
            + PB_UTIL.resource_slots_for(math.max(0, cur + d))
            - PB_UTIL.resource_slots_for(cur)
    end
    return PB_UTIL.inv_slots_used() + delta_slots <= PB_UTIL.inv_capacity()
end

function PB_UTIL.can_craft(recipe)
    if not recipe then return false end
    -- Crossbow is a Bow upgrade: it can only be crafted while you own a Bow (Cube->Big Cube
    -- prerequisite gating). Checked before affordability so the grid greys it out cleanly.
    if recipe.key == 'crossbow' and not PB_UTIL.has_joker('j_balacraft_bow') then
        return false
    end
    -- Card outputs need both their center (else the *_add helper no-ops and ingredients
    -- are lost) and a free slot in the relevant area.
    if recipe.output.type == 'joker' then
        if not G.P_CENTERS[recipe.output.id] then return false end
        if not PB_UTIL.has_joker_room() then return false end
    elseif recipe.output.type == 'consumable' then
        if not G.P_CENTERS[recipe.output.id] then return false end
        if not PB_UTIL.has_consumable_room() then return false end
    elseif recipe.output.type == 'station' then
        -- A Base station (Furnace, ...): a one-time unlock. Already built => can't re-craft
        -- (so ingredients can't be wasted on a no-op).
        if PB_UTIL.station_built and PB_UTIL.station_built(recipe.output.id) then return false end
    elseif recipe.output.type == 'resource' then
        -- A resource output (e.g. Sticks) must fit the inventory's real capacity after the spend.
        if not PB_UTIL.recipe_resource_fits(recipe) then return false end
    end
    if not PB_UTIL.can_afford(recipe) then return false end
    return true
end

-- Produce the recipe's output (no spending). Resource -> add_resource; joker ->
-- joker_add. Plays the craft sound. Both craft paths share this so the produce
-- logic lives in one place: Phase 1 click-craft (spend then produce) and Phase 2
-- grid-craft (consume already-reserved tiles, then produce -- no second spend).
function PB_UTIL.produce_output(recipe)
    local out = recipe.output
    if out.type == 'resource' then
        PB_UTIL.add_resource(out.id, out.amount or 1)
    elseif out.type == 'joker' then
        joker_add(out.id)
    elseif out.type == 'consumable' then
        consumable_add(out.id)
    elseif out.type == 'station' then
        if PB_UTIL.build_station then PB_UTIL.build_station(out.id) end
    end
    play_sound('timpani', 0.8)
end

-- Returns true on success. Spends ingredients, then produces the output.
function PB_UTIL.craft(recipe)
    if not PB_UTIL.can_craft(recipe) then return false end
    for id, n in pairs(PB_UTIL.recipe_ingredients(recipe)) do
        PB_UTIL.add_resource(id, -n)
    end
    PB_UTIL.produce_output(recipe)
    return true
end
