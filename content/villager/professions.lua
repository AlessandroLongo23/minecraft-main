-- Villager PROFESSIONS. PURE DATA (like content/villager/trades.lua): no SMODS declarations.
-- Each shop visit spawns ONE profession (seeded by ante+round in seed_villager_offers); its trade
-- pool is profession-specific, and a reroll KEEPS the profession, re-rolling only its trades.
-- Modelled on Minecraft villager professions, mapped onto the content BalaCraft actually ships:
--   * Toolsmith (Smithing Table) -> all tools: swords + pickaxes + shovels
--   * Librarian (Lectern)        -> enchant books (Sharpness/Durability/Fortune I-III) + Torch
--   * Mason     (Stonecutter)    -> ore/resource bundles (the VILLAGER_TRADES resource templates)
--   * Farmer    (Composter)      -> food consumables
-- villager.lua's villager_candidates(profession) reads the live registries to build offers for one.

PB_UTIL.VILLAGER_PROFESSIONS = {
    { id = 'toolsmith', name = 'Toolsmith', block = 'Smithing Table' },
    { id = 'librarian', name = 'Librarian', block = 'Lectern' },
    { id = 'mason',     name = 'Mason',     block = 'Stonecutter' },
    { id = 'farmer',    name = 'Farmer',    block = 'Composter' },
}

PB_UTIL.VILLAGER_PROFESSION_BY_ID = {}
for _, p in ipairs(PB_UTIL.VILLAGER_PROFESSIONS) do
    PB_UTIL.VILLAGER_PROFESSION_BY_ID[p.id] = p
end

-- Emerald pricing (tunable). Tool/torch/resource-bundle costs live in trades.lua; these price the
-- two trade kinds trades.lua didn't: enchant books and food.
PB_UTIL.VILLAGER_BOOK_COST = { 5, 8, 12 }   -- by book tier I/II/III
PB_UTIL.VILLAGER_FOOD_COST = { 1, 1, 2 }    -- by food tier 1/2/3

-- Villager reroll cost (Emeralds), independent of the base shop's $ reroll. Starts here and rises
-- +1 each reroll, resetting per shop visit (see villager.lua bc_reroll_villager / cash_out wrap).
PB_UTIL.VILLAGER_REROLL_BASE = 1
