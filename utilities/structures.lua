-- Structure blinds + the Nether entry.
--
-- "Structures" re-theme the two NON-boss blinds (Night = bl_small, Cave = bl_big) per ante: instead
-- of always Night/Cave, an overworld ante can surface a biome-appropriate Minecraft structure
-- (Desert Temple, Witch Hut, Igloo, ...) plus the special RUINED PORTAL, which can appear in any
-- overworld biome. This is NAME-ONLY theming for now (the displayed blind name + the drop branch +
-- the Ruined-Portal lighting hook): the engine identifies Small/Big by object identity, so we keep
-- bl_small/bl_big as the real centers and only swap their localized NAME (the same loc mechanism the
-- mod already uses for Night/Cave -- utilities/functions.lua). Bespoke per-structure SPRITES are a
-- later art pass; until then a structure shows with the Night/Cave backdrop under its own name.
--
-- The Ruined Portal is the Nether entry: while playing it, using Flint and Steel with >=1 Obsidian
-- calls PB_UTIL.light_nether_portal (below) -- spend 1 Obsidian, instantly beat the blind, warp to a
-- random Nether biome, and reroll this ante's boss to a Nether boss.
--
-- Gated on blinds (it themes the Night/Cave reskin). Inert -- and a no-op -- when blinds are off.
if not (PB_UTIL.config and PB_UTIL.config.blinds_enabled) then return end

-- How often a non-boss overworld blind is re-themed as a structure (per slot, per ante). Tunable.
local STRUCTURE_CHANCE = 0.45

-- The structure pool. ARRAY (stable order => deterministic seeded picks). `biomes` is a list of
-- eligible overworld biome ids, or 'all' for any overworld biome. `weight` biases the pick (default
-- 1). `special = 'nether'` marks the Ruined Portal (the lightable one). Mappings are the real MC
-- structure->biome associations (see the plan / wiki research).
PB_UTIL.STRUCTURES = {
    { id = 'desert_temple',    name = 'Desert Temple',    biomes = { 'desert' } },
    { id = 'jungle_temple',    name = 'Jungle Temple',    biomes = { 'jungle' } },
    { id = 'witch_hut',        name = 'Witch Hut',        biomes = { 'swamp' } },
    { id = 'igloo',            name = 'Igloo',            biomes = { 'snowy_taiga' } },
    { id = 'woodland_mansion', name = 'Woodland Mansion', biomes = { 'forest' } },
    { id = 'pillager_outpost', name = 'Pillager Outpost', biomes = { 'plains', 'savanna', 'desert', 'snowy_taiga' } },
    { id = 'shipwreck',        name = 'Shipwreck',        biomes = { 'swamp' } },
    { id = 'mineshaft',        name = 'Mineshaft',        biomes = { 'badlands' } },
    { id = 'dungeon',          name = 'Dungeon',          biomes = 'all' },
    { id = 'ruined_portal',    name = 'Ruined Portal',    biomes = 'all', special = 'nether', weight = 2 },
}
PB_UTIL.STRUCTURE_BY_ID = {}
for _, s in ipairs(PB_UTIL.STRUCTURES) do PB_UTIL.STRUCTURE_BY_ID[s.id] = s end

-- Nether boss pool the Ruined Portal rerolls into (the mod's Nether-themed blinds, prefixed keys).
PB_UTIL.NETHER_BOSSES = {
    'bl_balacraft_blaze', 'bl_balacraft_ghast', 'bl_balacraft_magmacube',
    'bl_balacraft_piglin', 'bl_balacraft_hoglin', 'bl_balacraft_zombiepigman',
    'bl_balacraft_wither_skeleton', 'bl_balacraft_magma_lord',
}

local function biome_eligible(s, biome)
    if s.biomes == 'all' then return true end
    if type(s.biomes) == 'table' then
        for _, b in ipairs(s.biomes) do if b == biome then return true end end
    end
    return false
end

-- Roll the structure for one slot ('Small'/'Big') of the current ante, or false for plain Night/Cave.
-- Only overworld antes get structures (the Nether/End keep plain Night/Cave). Run-seeded deterministic.
local function roll_structure(slot)
    if not PB_UTIL.current_dimension or PB_UTIL.current_dimension() ~= 'overworld' then return false end
    local ante  = (G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or 1
    if pseudorandom('bc_struct_' .. slot .. '_' .. ante) >= STRUCTURE_CHANCE then return false end
    local biome = PB_UTIL.current_biome and PB_UTIL.current_biome()
    local pool = {}
    for _, s in ipairs(PB_UTIL.STRUCTURES) do
        if biome_eligible(s, biome) then
            for _ = 1, (s.weight or 1) do pool[#pool + 1] = s.id end
        end
    end
    if #pool == 0 then return false end
    return pseudorandom_element(pool, pseudoseed('bc_structpick_' .. slot .. '_' .. ante))
end

-- The cached {ante, Small, Big} structure assignment for the current ante (rolled once per ante).
function PB_UTIL.ante_structures()
    local bc = G.GAME and G.GAME.balacraft
    if not bc then return { Small = false, Big = false } end
    local ante = (G.GAME.round_resets and G.GAME.round_resets.ante) or 1
    local cache = bc.ante_structures
    if cache and cache.ante == ante then return cache end
    cache = { ante = ante, Small = roll_structure('Small'), Big = roll_structure('Big') }
    bc.ante_structures = cache
    return cache
end

-- Override the displayed name of a non-boss blind slot to its structure (or revert to Night/Cave).
-- Same loc-only mechanism as the Night/Cave reskin (utilities/functions.lua): never touch the
-- internal `name` (Blind:get_type keys on it), only the localization label.
local function set_slot_name(slot, struct_id)
    local d = G.localization and G.localization.descriptions and G.localization.descriptions.Blind
    if not d then return end
    local key     = (slot == 'Small') and 'bl_small' or 'bl_big'
    local default = (slot == 'Small') and 'Night'    or 'Cave'
    local name    = default
    if struct_id and PB_UTIL.STRUCTURE_BY_ID[struct_id] then name = PB_UTIL.STRUCTURE_BY_ID[struct_id].name end
    if d[key] then d[key].name = name; d[key].name_parsed = nil end
end

-- Apply both slot names for the current ante (used by the blind-select screen).
function PB_UTIL.apply_structure_names()
    local st = PB_UTIL.ante_structures()
    set_slot_name('Small', st.Small)
    set_slot_name('Big',   st.Big)
end

-- ---- Wrap Blind:set_blind: theme the slot being set + record the active structure ----
-- Installed outermost (loads after utilities/functions.lua's set_blind wrap). Sets the displayed
-- name BEFORE the inner call (so the in-round HUD reads it) and records active_structure AFTER, so
-- Flint & Steel (content/tools/flint_and_steel.lua) and the obsidian drop branch can see it.
if not PB_UTIL._struct_setblind_wrapped then
    PB_UTIL._struct_setblind_wrapped = true
    local _set_blind = Blind.set_blind
    function Blind:set_blind(blind, reset, silent)
        local slot
        if not reset and blind then
            if blind == G.P_BLINDS.bl_small then slot = 'Small'
            elseif blind == G.P_BLINDS.bl_big then slot = 'Big' end
        end
        local struct = false
        if slot then
            struct = PB_UTIL.ante_structures()[slot]
            set_slot_name(slot, struct)
        end
        _set_blind(self, blind, reset, silent)
        if not reset and G.GAME and G.GAME.balacraft then
            G.GAME.balacraft.active_structure = struct or nil
        end
    end
end

-- ---- Wrap create_UIBox_blind_select: show structure names on the blind-select screen ----
if type(create_UIBox_blind_select) == 'function' and not PB_UTIL._struct_blindselect_wrapped then
    PB_UTIL._struct_blindselect_wrapped = true
    local _build = create_UIBox_blind_select
    function create_UIBox_blind_select(...)
        pcall(PB_UTIL.apply_structure_names)
        return _build(...)
    end
end

-- ---- Nether entry: light the Ruined Portal ----
-- Called from Flint and Steel's use() (after it spends 1 Obsidian). Warps to a random Nether biome,
-- rerolls this ante's boss to a Nether boss, counts the entry, and force-wins the current blind.
function PB_UTIL.light_nether_portal()
    if not G.GAME then return end
    G.GAME.balacraft = G.GAME.balacraft or {}
    local bc = G.GAME.balacraft
    bc._portal_lit = true   -- grant_blind_drop sees this and skips the Ruined-Portal obsidian bonus

    -- Warp to a random Nether biome (sets dimension + biome + background tint).
    if PB_UTIL.enter_dimension then PB_UTIL.enter_dimension('nether') end
    -- Re-roll the rest of this ante's structure themes for the new dimension (Nether = plain Cave/Night).
    bc.ante_structures = nil

    -- Reroll this ante's boss to a Nether boss -- assign blind_choices.Boss directly (exactly what
    -- the vanilla reroll button does); it's consumed when the boss option is later selected, so this
    -- mid-ante write persists (we just beat a non-boss blind, so reset_blinds won't regenerate it).
    local rr = G.GAME.round_resets
    if rr and rr.blind_choices and PB_UTIL.NETHER_BOSSES then
        local ante = rr.ante or 1
        local pool = {}
        for _, k in ipairs(PB_UTIL.NETHER_BOSSES) do
            if G.P_BLINDS and G.P_BLINDS[k] then pool[#pool + 1] = k end
        end
        if #pool > 0 then
            rr.blind_choices.Boss = pseudorandom_element(pool, pseudoseed('bc_nether_boss_' .. ante))
        end
    end

    -- Count the Nether entry (unlocks the Nether deck at the lifetime threshold).
    if PB_UTIL.bump_progression then PB_UTIL.bump_progression('nether_entries') end

    -- Instantly beat the current (Ruined Portal) blind: meet the chip requirement, then jump to
    -- NEW_ROUND. The state machine runs end_round() (which discards the leftover hand) -> ROUND_EVAL
    -- -> cash out; Blind:defeat fires grant_blind_drop, which sees _portal_lit and skips the obsidian.
    -- Deferred via an event so we never mutate G.STATE from inside the consumable's use().
    G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.15, func = function()
        if G.GAME and G.GAME.blind and G.STATES then
            local need = G.GAME.blind.chips or 0
            if type(need) ~= 'table' and (G.GAME.chips or 0) < need then G.GAME.chips = need end
            G.STATE = G.STATES.NEW_ROUND
            G.STATE_COMPLETE = false
            pcall(play_sound, 'whoosh1', 1, 0.7)
        end
        return true
    end }))
end
