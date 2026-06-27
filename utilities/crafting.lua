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

function PB_UTIL.has_consumable_room()
    if not G.consumeables then return false end
    return #G.consumeables.cards < G.consumeables.config.card_limit
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
