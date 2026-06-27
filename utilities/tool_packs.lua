-- Tool booster packs: pool sampling, ante scaling, enchant roll, and the pack-card builder.
-- Pure-ish logic (RNG via pseudoseed) kept in one focused file so it can be unit-tested headless
-- (assets/test_tool_packs.lua) and to match the per-feature utilities/*.lua layout (crafting.lua,
-- villager.lua, ...). Loaded in main.lua's resources_enabled block, just before the tool-pack
-- boosters register. Reads PB_UTIL.TOOLS (content/tools/registry.lua) and, when the enchant system
-- is loaded, PB_UTIL.ENCHANTS / enchant_applies / set_tool_enchant (all runtime-guarded).

-- Highest tool MATERIAL tier (1 wood .. 6 netherite) available at a given ante. 6-tier analog of
-- PB_UTIL.max_ore_tier: Stone by ante 2, Iron by 3, Gold by 5, Diamond by 6, Netherite by 8.
function PB_UTIL.max_tool_tier(ante)
    ante = ante or 1
    return (ante >= 8 and 6) or (ante >= 6 and 5) or (ante >= 5 and 4)
        or (ante >= 3 and 3) or 2
end

-- Enchant roll for ONE pack tool. Returns { etype=, tier= } or nil. Guarded on the enchant system
-- being loaded (PB_UTIL.ENCHANTS) -- there is intentionally NO voucher check, so enchanted tools
-- can appear from ante 1 (like Minecraft loot chests). Chance + tier scale with ante; tier is
-- heavily weighted to I.
function PB_UTIL.roll_pack_enchant(tool_def, ante)
    if not PB_UTIL.ENCHANTS then return nil end          -- system off: never enchanted
    ante = ante or 1
    local chance = math.min(0.25, 0.05 + 0.02 * (ante - 1))
    if pseudorandom(pseudoseed('bc_toolpack_ench')) >= chance then return nil end

    -- valid enchant types for this tool kind (sword: sharpness/durability; pick/shovel: fortune/durability)
    local types = {}
    for _, etype in ipairs(PB_UTIL.ENCHANT_ORDER or { 'sharpness', 'durability', 'fortune' }) do
        if PB_UTIL.enchant_applies(etype, tool_def.tool) then types[#types + 1] = etype end
    end
    if not types[1] then return nil end
    local etype = types[1 + math.floor(pseudorandom(pseudoseed('bc_toolpack_etype')) * #types)]

    -- tier: I always; II from ante 4; III from ante 7. Weighted to favour I.
    local weights = { 8, (ante >= 4) and 3 or 0, (ante >= 7) and 1 or 0 }
    local pool = {}
    for tier = 1, 3 do for _ = 1, weights[tier] do pool[#pool + 1] = tier end end
    local tier = pool[1 + math.floor(pseudorandom(pseudoseed('bc_toolpack_etier')) * #pool)]
    return { etype = etype, tier = tier }
end

-- Weighted, distinct sample of n pack slots from the 18 tools + Torch. Low material tiers are
-- common; higher tiers unlock with ante (max_tool_tier). Each chosen tool gets an enchant roll.
-- Mirrors PB_UTIL.sample_pack_ores. Returns { { id=<tool_id>|'torch', ench={etype,tier}|nil }, ... }.
function PB_UTIL.sample_pack_tools(n)
    local ante = (G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or 1
    local max_tier = PB_UTIL.max_tool_tier(ante)

    local remaining = {}
    for _, t in ipairs(PB_UTIL.TOOLS or {}) do
        if (t.tier or 1) <= max_tier then
            remaining[#remaining + 1] = { id = t.id, weight = (max_tier - (t.tier or 1) + 1), def = t }
        end
    end
    -- Torch: flat weight, ante-independent, only when the center exists (torch enabled). Never enchanted.
    if G.P_CENTERS and G.P_CENTERS['c_balacraft_torch'] then
        remaining[#remaining + 1] = { id = 'torch', weight = 2, def = nil }
    end

    local picked = {}
    n = math.min(n or 1, #remaining)
    for _ = 1, n do
        local pool = {}
        for idx, e in ipairs(remaining) do
            for _ = 1, e.weight do pool[#pool + 1] = idx end
        end
        local chosen = pseudorandom_element(pool, pseudoseed('bc_toolpack'))
        local entry = remaining[chosen]
        local ench = entry.def and PB_UTIL.roll_pack_enchant(entry.def, ante) or nil
        picked[#picked + 1] = { id = entry.id, ench = ench }
        table.remove(remaining, chosen)
    end
    return picked
end

-- Booster create_card body (mirror of PB_UTIL.create_resource_pack_card). Samples once (cached on
-- the opened booster `card`), builds slot i, and applies any rolled enchant for free (no level/lapis).
-- Both tools and Torch ride the 'balacraft_tool' consumable type; create_card resolves the front
-- sprite from the center (bc_tools for tools, bc_torch for the Torch).
function PB_UTIL.create_tool_pack_card(card, i, n)
    if not card.balacraft_pack_tools then
        local size_mod = (G.GAME and G.GAME.modifiers and G.GAME.modifiers.booster_size_mod) or 0
        card.balacraft_pack_tools = PB_UTIL.sample_pack_tools((n or 1) + size_mod)
    end
    local entry = card.balacraft_pack_tools[i] or card.balacraft_pack_tools[1] or { id = 'sword_wood' }
    local id = entry.id or 'sword_wood'
    local key = (id == 'torch') and 'c_balacraft_torch' or ('c_balacraft_tool_' .. id)
    local new = create_card('balacraft_tool', G.pack_cards, nil, nil, true, true, key, 'bc_toolpack')
    if entry.ench and PB_UTIL.set_tool_enchant then
        PB_UTIL.set_tool_enchant(new, entry.ench.etype, entry.ench.tier)
    end
    return new
end
