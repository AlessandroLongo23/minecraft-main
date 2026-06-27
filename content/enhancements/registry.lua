-- Enchantment registry + math. PURE DATA + helpers; defines no SMODS centers.
-- Loaded in the enhancements_enabled block (main.lua) BEFORE enchant_consumabletype.lua.
--
-- Three enchant types, each tier 1..3. A tool holds at most ONE of each type; applying a
-- higher tier upgrades it (can't downgrade). Effects of different types combine.
--   sharpness  (sword only)        : tool -> multiplies the sword's X-mult; card -> +Mult edition
--   durability (all tools)         : multiplies max uses (ceil)
--   fortune    (pickaxe & shovel)  : random 0..tier bonus to the loot/payout
--
-- The math helpers below are also called from content/tools/tool_consumabletype.lua use()
-- (guarded there, so tools still work when enhancements_enabled is off).

-- Pre-baked enchanted-tool atlas (15 rows x 16 cols of 71x95 cells; see
-- assets/gen_enchanted_tools.py). An enchanted tool's live sprite is swapped onto a cell here
-- by PB_UTIL.refresh_tool_sprite; un-enchanted tools keep their bc_resource_cards sprite.
PB_UTIL.tool_atlas = SMODS.Atlas {
    key = 'bc_tool_cards', path = 'tool_cards.png', px = 71, py = 95,
}

-- Enchanting-book card art (3 cols x 3 rows of 71x95 cells; see assets/gen_enchant_books.py).
-- col = tier-1 (I/II/III), row = type index in PB_UTIL.ENCHANT_ORDER (sharpness/durability/fortune).
PB_UTIL.enchant_book_atlas = SMODS.Atlas {
    key = 'bc_enchant_cards', path = 'enchant_cards.png', px = 71, py = 95,
}

-- Small 34x34 book ICONS (frameless; assets/gen_enchant_icons.py) for the villager (Librarian)
-- shop offers -- the offers show icons, not scaled-down cards. 3 cols (tier) x 3 rows (type);
-- a book's card `pos` ({x=tier-1, y=type-1}) indexes this sheet directly.
PB_UTIL.enchant_icon_atlas = SMODS.Atlas {
    key = 'bc_enchant_icons', path = 'enchant_icons.png', px = 34, py = 34,
}

PB_UTIL.ENCHANTS = {
    -- Sharpness is DUAL-TARGET: on a sword these tiers multiply X-mult; on a playing card the
    -- same book applies the tiered e_balacraft_sharpness_<tier> edition (+Mult -- see content/editions/).
    sharpness = {
        name = 'Sharpness',
        applies = { sword = true },          -- tool side; cards are handled in the enchant flow
        mult = { 1.25, 1.5, 1.75 },          -- X-mult multiplier per tier (tool side)
    },
    durability = {
        name = 'Durability',
        applies = { sword = true, pickaxe = true, shovel = true },
        mult = { 1.25, 1.5, 2 },             -- max-uses multiplier per tier (ceil)
    },
    fortune = {
        name = 'Fortune',
        applies = { pickaxe = true, shovel = true },
        bonus = { 1, 2, 3 },                 -- max extra loot per tier (rolls 0..max) -- TOOL side
        -- CARD side ("Lucky" edition): Emeralds dropped per score, as per-tier weight tables.
        -- Index = emerald count (1st weight is count 0); value = weight. Averages 0.5 / 1.5 / 2.5.
        card_drops = { { 60, 30, 10 }, { 20, 30, 30, 20 }, { 0, 20, 30, 30, 20 } },
    },
}

-- Stable display / build order.
PB_UTIL.ENCHANT_ORDER = { 'sharpness', 'durability', 'fortune' }

-- Minecraft-style tier numerals.
PB_UTIL.ENCHANT_ROMAN = { 'I', 'II', 'III' }

-- $ cost of each book by tier (placeholder balance, tunable).
local BOOK_COST = { 4, 7, 10 }

-- Build the 9 books (3 types x 3 tiers) as pure data; the consumable type and the booster
-- sampler both iterate this list.
PB_UTIL.ENCHANT_BOOKS = {}
for ti, etype in ipairs(PB_UTIL.ENCHANT_ORDER) do
    local def = PB_UTIL.ENCHANTS[etype]
    for tier = 1, 3 do
        PB_UTIL.ENCHANT_BOOKS[#PB_UTIL.ENCHANT_BOOKS + 1] = {
            id    = etype .. '_' .. tier,                          -- 'sharpness_2'
            etype = etype,
            tier  = tier,
            name  = def.name .. ' ' .. PB_UTIL.ENCHANT_ROMAN[tier], -- 'Sharpness II'
            cost  = BOOK_COST[tier],
            pos   = { x = tier - 1, y = ti - 1 },                  -- bc_enchant_cards cell
        }
    end
end
PB_UTIL.ENCHANT_BOOK_BY_ID = {}
for _, b in ipairs(PB_UTIL.ENCHANT_BOOKS) do PB_UTIL.ENCHANT_BOOK_BY_ID[b.id] = b end

-- ── Math helpers ──────────────────────────────────────────────────────────

-- Sharpness X-mult multiplier for a tier (tool side; 1 when 0/nil/off).
function PB_UTIL.sharpness_mult(tier)
    local m = PB_UTIL.ENCHANTS.sharpness.mult
    return (tier and tier >= 1 and m[tier]) or 1
end

-- Durability max-uses multiplier for a tier (1 when 0/nil/off).
function PB_UTIL.durability_mult(tier)
    local m = PB_UTIL.ENCHANTS.durability.mult
    return (tier and tier >= 1 and m[tier]) or 1
end

-- Fortune (PICKAXE side): random integer in 0..bonus[tier], run-seeded; varies per card so two
-- tools don't always roll alike. Returns 0 when tier is 0/nil.
function PB_UTIL.fortune_bonus(tier, card)
    if not tier or tier < 1 then return 0 end
    local max = PB_UTIL.ENCHANTS.fortune.bonus[tier] or tier
    local key = 'bc_fortune_' .. tostring(card and card.sort_id or 'x')
    return math.floor(pseudorandom(pseudoseed(key)) * (max + 1))
end

-- Shovel find chance: the shovel is a gamble (pays its tier value only on a hit). Base 50%,
-- and Fortune now raises the ODDS rather than the loot: +15% per Fortune tier, capped at 95%.
-- (0.5 / 0.65 / 0.80 / 0.95 for Fortune 0..3.) Tunable.
PB_UTIL.SHOVEL_BASE_CHANCE = 0.5
function PB_UTIL.shovel_find_chance(fortune_tier)
    local c = PB_UTIL.SHOVEL_BASE_CHANCE
    if fortune_tier and fortune_tier >= 1 then c = c + 0.15 * fortune_tier end
    if c > 0.95 then c = 0.95 end
    return c
end

-- Whether an enchant type can be applied to a tool kind ('sword'|'pickaxe'|'shovel').
function PB_UTIL.enchant_applies(etype, tool_kind)
    local def = PB_UTIL.ENCHANTS[etype]
    return def ~= nil and def.applies[tool_kind] == true
end

-- Lucky (Fortune's card side): how many Emeralds a Lucky card drops when it scores. One run-seeded
-- roll walks the tier's cumulative weight table; the returned count = (index - 1). pseudoseed
-- advances per call, so repeated scores vary. Returns 0 when tier is out of range.
function PB_UTIL.lucky_emeralds(tier)
    local weights = PB_UTIL.ENCHANTS.fortune.card_drops[tier]
    if not weights then return 0 end
    local total = 0
    for i = 1, #weights do total = total + weights[i] end
    if total <= 0 then return 0 end
    local r = pseudorandom(pseudoseed('bc_lucky')) * total
    local acc = 0
    for i = 1, #weights do
        acc = acc + weights[i]
        if r < acc then return i - 1 end
    end
    return #weights - 1
end
