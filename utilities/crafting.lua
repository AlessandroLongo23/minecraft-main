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

function PB_UTIL.can_craft(recipe)
    if not recipe then return false end
    if recipe.output.type == 'joker' then
        -- the joker center must exist (else joker_add no-ops and ingredients are lost)
        if not G.P_CENTERS[recipe.output.id] then return false end
        if not PB_UTIL.has_joker_room() then return false end
    end
    if not PB_UTIL.can_afford(recipe) then return false end
    return true
end

-- Returns true on success. Spends ingredients, then produces the output.
function PB_UTIL.craft(recipe)
    if not PB_UTIL.can_craft(recipe) then return false end
    for id, n in pairs(PB_UTIL.recipe_ingredients(recipe)) do
        PB_UTIL.add_resource(id, -n)
    end
    local out = recipe.output
    if out.type == 'resource' then
        PB_UTIL.add_resource(out.id, out.amount or 1)
    elseif out.type == 'joker' then
        joker_add(out.id)
    end
    play_sound('timpani', 0.8)
    return true
end
