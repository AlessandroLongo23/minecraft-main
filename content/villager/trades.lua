-- Villager Trading offer templates + pricing. PURE DATA (like content/resources/recipes.lua):
-- no SMODS declarations, no side effects. utilities/villager.lua expands these templates into
-- concrete offers at runtime. All numbers are balance knobs -- tune freely.

-- Emerald cost of a tool offer, indexed by material tier (1..6 = Wooden..Netherite).
-- Mirrors the $ crafting cost (COST_BY_TIER) in content/tools/registry.lua.
PB_UTIL.VILLAGER_TOOL_COST  = { 3, 4, 5, 6, 8, 10 }
PB_UTIL.VILLAGER_TORCH_COST = 2

-- Resource-bundle templates -- the MASON profession's pool (utilities/villager.lua
-- villager_candidates('mason')). `weight` biases the draw; each is a bundle of `amount` of a random
-- GATHERED ore of `tier` (emerald excluded) for `cost` Emeralds. (Tools/books/food/torch are built
-- directly from their registries by the other professions, so they're not templated here.)
PB_UTIL.VILLAGER_TRADES = {
    { kind = 'resource', tier = 1, amount = 5, cost = 3, weight = 3 },
    { kind = 'resource', tier = 2, amount = 3, cost = 4, weight = 3 },
    { kind = 'resource', tier = 3, amount = 2, cost = 6, weight = 2 },
    { kind = 'resource', tier = 4, amount = 1, cost = 8, weight = 1 },
}
