-- Resource state + helpers

-- Seed per-run resource counts on G.GAME via an init_game_object wrapper.
-- Runs fresh for every new run, so counts auto-reset; plain integers => auto-saved.
local _init_game_object = Game.init_game_object
function Game:init_game_object()
    local t = _init_game_object(self)
    t.minecraft = t.minecraft or {}
    t.minecraft.resources = {}
    for _, r in ipairs(PB_UTIL.RESOURCES or {}) do
        t.minecraft.resources[r.id] = 0
    end
    return t
end

-- Defensive accessor: guarantees the table exists before read/write.
local function ensure_store()
    G.GAME.minecraft = G.GAME.minecraft or {}
    G.GAME.minecraft.resources = G.GAME.minecraft.resources or {}
    return G.GAME.minecraft.resources
end

function PB_UTIL.get_resource_count(id)
    return ensure_store()[id] or 0
end

function PB_UTIL.set_resource(id, amount)
    local store = ensure_store()
    local prev = store[id] or 0
    store[id] = math.max(0, math.floor(tonumber(amount) or 0))
    if (prev == 0) ~= (store[id] == 0) then
        G.GAME.minecraft._panel_dirty = true
    end
    return store[id]
end

-- Single mutation funnel. Marks the panel dirty when an ore is first owned (0 -> >0)
-- so the UI can flip it from greyed to active (see Task 3).
function PB_UTIL.add_resource(id, amount)
    local store = ensure_store()
    local prev = store[id] or 0
    local new = math.max(0, prev + (math.floor(tonumber(amount) or 0)))
    store[id] = new
    if (prev == 0) ~= (new == 0) then
        G.GAME.minecraft._panel_dirty = true
    end
    return new
end

-- Per-blind themed overrides (opt-in). Keyed by blind.name.
-- NOTE: for SMODS boss blinds, blind.name IS the prefixed key (e.g. 'bl_minecraft_creeper'),
-- because SMODS sets a blind center's name to `self.name or self.key` (game_object.lua) and our
-- blinds only define loc_txt.name. (Vanilla small/big blinds use display names like 'Small Blind',
-- but we only key minecraft bosses here, so the lookup matches.) The mod's lovely.toml relies on
-- this same fact (it checks `G.GAME.blind.name == 'bl_minecraft_drowned'`).
-- Anything without an entry uses the tier-roll fallback.
PB_UTIL.BLIND_DROPS = {
    bl_minecraft_creeper  = { id = 'coal',   amount = 2 },
    bl_minecraft_skeleton = { id = 'iron',   amount = 1 },
    bl_minecraft_zombie   = { id = 'wood',   amount = 2 },
}

-- Returns a random ore id of exactly `tier` (run-seeded deterministic).
local function random_ore_of_tier(tier, seed_key)
    local pool = {}
    for _, r in ipairs(PB_UTIL.RESOURCES) do
        if r.kind == 'gathered' and r.tier == tier then pool[#pool + 1] = r.id end
    end
    if #pool == 0 then return PB_UTIL.RESOURCES[1].id end
    return pseudorandom_element(pool, pseudoseed(seed_key))
end

-- Grant resources for defeating `blind`. PLACEHOLDER BALANCE (shape is fixed, numbers tunable).
function PB_UTIL.grant_blind_drop(blind)
    if not blind then return end
    local bonus = PB_UTIL.has_joker('j_minecraft_stone_pickaxe') and 1 or 0
    if PB_UTIL.has_joker('j_minecraft_iron_shovel') then ease_dollars(3) end

    local spec = blind.name and PB_UTIL.BLIND_DROPS[blind.name]
    if spec then
        PB_UTIL.add_resource(spec.id, spec.amount + bonus)
        return
    end
    local ante = (G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or 1
    local is_boss = blind.boss and true or false
    local max_tier = (ante >= 6 and 3) or (ante >= 3 and 2) or 1
    -- bosses bias toward the highest unlocked tier; others toward tier 1
    local tier = is_boss and max_tier or 1
    local amount = (is_boss and 2 or 1) + bonus
    PB_UTIL.add_resource(random_ore_of_tier(tier, 'mc_drop_' .. ante .. '_' .. tostring(blind.name)), amount)
end

-- Wrap Blind:defeat (same technique Steamodded uses) so drops fire on every blind win.
local _blind_defeat = Blind.defeat
function Blind:defeat(silent)
    _blind_defeat(self, silent)
    pcall(PB_UTIL.grant_blind_drop, self)
end
