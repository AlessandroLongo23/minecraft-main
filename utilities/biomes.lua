-- Biomes & Dimensions -- core state + run-flow integration.
--
-- A biome is the theme for ONE ante (background tint, resource bias, exclusive bosses,
-- a one-time arrival modifier). After every BOSS cash-out the player picks one of three
-- biomes from the current dimension (see utilities/biomes_ui.lua); the pick themes the
-- next ante. Dimensions (overworld / nether / end) keep isolated biome pools.
--
-- Same conventions as the rest of the mod:
--   * per-run state is plain values on G.GAME.balacraft (auto-save / auto-reset, no save code)
--   * integration is plain Lua function-wraps (init_game_object, G.FUNCS.cash_out,
--     ease_background_colour_blind) -- no Lovely patches.
-- Data lives in content/biomes/registry.lua (PB_UTIL.BIOMES / PB_UTIL.BIOME_BY_ID).

-- ---- Seed per-run state ----
-- Guarded `t.balacraft = t.balacraft or {}` so this composes with the resources/xp/health
-- init wrappers regardless of load order. Default spawn: Overworld / Plains (see design doc;
-- dimension decks will override this in their apply() in a later phase).
local _init_game_object = Game.init_game_object
function Game:init_game_object()
    local t = _init_game_object(self)
    t.balacraft = t.balacraft or {}
    t.balacraft.current_dimension = 'overworld'
    t.balacraft.current_biome = 'plains'
    return t
end

-- ---- Accessors (defensive; safe before a run exists) ----

function PB_UTIL.current_dimension()
    local g = G.GAME and G.GAME.balacraft
    return (g and g.current_dimension) or 'overworld'
end

function PB_UTIL.current_biome()
    local g = G.GAME and G.GAME.balacraft
    return (g and g.current_biome) or nil
end

function PB_UTIL.get_biome(id)
    return id and PB_UTIL.BIOME_BY_ID and PB_UTIL.BIOME_BY_ID[id] or nil
end

-- The active biome's tint colour, or nil when biomes are off / no biome is set.
-- Used by the ease_background_colour_blind wrap below and by the selection UI.
function PB_UTIL.active_biome_colour()
    if not (PB_UTIL.config and PB_UTIL.config.biomes_enabled) then return nil end
    local b = PB_UTIL.get_biome(PB_UTIL.current_biome())
    return b and b.colour or nil
end

-- ---- Biome rolling / selection ----

-- `n` distinct biome ids from `dim`, excluding `exclude`. Run-seeded deterministic
-- (same pseudorandom_element + pseudoseed idiom as the resource drops / pack sampling).
function PB_UTIL.roll_biome_choices(dim, n, exclude)
    local pool = {}
    for _, b in ipairs(PB_UTIL.BIOMES or {}) do
        if b.dimension == dim and b.id ~= exclude then pool[#pool + 1] = b.id end
    end
    local picked = {}
    n = math.min(n or 3, #pool)
    local ante = (G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or 0
    for i = 1, n do
        local el, key = pseudorandom_element(pool, pseudoseed('bc_biome_' .. ante .. '_' .. i))
        picked[#picked + 1] = el
        table.remove(pool, key)
    end
    return picked
end

-- Set the current biome and apply its on-arrival effects. Called from the selection UI.
-- Applies the background tint immediately and the one-time `on_enter` modifier (the
-- demonstrable "biome modifies the run" hook for the slice; joker-specific buffs/maluses
-- read PB_UTIL.current_biome() in their own calculate, the same way jokers already check
-- G.GAME.blind.boss -- see content/jokers/iron_sword.lua).
function PB_UTIL.set_biome(id)
    if not (G.GAME and PB_UTIL.get_biome(id)) then return end
    G.GAME.balacraft = G.GAME.balacraft or {}
    G.GAME.balacraft.current_biome = id
    local b = PB_UTIL.get_biome(id)
    pcall(ease_background_colour_blind, G.STATE)
    if b.on_enter and b.on_enter.dollars and b.on_enter.dollars ~= 0 then
        pcall(ease_dollars, b.on_enter.dollars)
    end
end

-- Switch dimension and roll a fresh starting biome from it. Used by the portal vouchers
-- and the dimension decks (random biome in the dimension).
function PB_UTIL.enter_dimension(dim)
    if not G.GAME then return end
    G.GAME.balacraft = G.GAME.balacraft or {}
    G.GAME.balacraft.current_dimension = dim
    local choices = PB_UTIL.roll_biome_choices(dim, 1, nil)
    PB_UTIL.set_biome(choices[1])
end

-- Start the run in a SPECIFIC biome (used by the per-biome start-decks). Sets the dimension
-- from the biome's own dimension, then applies the biome (tint + on_enter).
function PB_UTIL.start_in_biome(id)
    local b = PB_UTIL.get_biome(id)
    if not (G.GAME and b) then return end
    G.GAME.balacraft = G.GAME.balacraft or {}
    G.GAME.balacraft.current_dimension = b.dimension
    PB_UTIL.set_biome(id)
end

-- Whether a biome-selection screen should be offered (feature on + a real choice exists).
function PB_UTIL.should_offer_biome_select()
    if not (PB_UTIL.config and PB_UTIL.config.biomes_enabled) then return false end
    if not G.GAME then return false end
    local dim, count = PB_UTIL.current_dimension(), 0
    for _, b in ipairs(PB_UTIL.BIOMES or {}) do
        if b.dimension == dim then count = count + 1 end
    end
    return count >= 2
end

-- in_pool predicate for biome-exclusive boss blinds: eligible only while in that biome.
-- Returns false when biomes are off, so a biome boss simply never appears (never crashes).
-- The shared base blinds declare no in_pool, so they stay always-eligible -> ADDITIVE pools.
function PB_UTIL.biome_blind_in_pool(biome_id)
    return PB_UTIL.current_biome() == biome_id
end

-- ---- Background tint wrap ----
-- Re-tint the playing field to the active biome's colour for the WHOLE ante (small/big
-- blind play + shop + blind select), while letting boss blinds keep their own boss_colour
-- and pack-opening states keep their strong theming. Mirrors the base game's own formula
-- (functions/common_events.lua: ease_background_colour_blind) for the non-boss branch.
local _ease_bg_blind = ease_background_colour_blind
function ease_background_colour_blind(state, blind_override)
    local biome_col = PB_UTIL.active_biome_colour()
    if not biome_col then return _ease_bg_blind(state, blind_override) end

    local blindname = blind_override or (G.GAME.blind and G.GAME.blind.name ~= '' and G.GAME.blind.name) or 'Small Blind'
    if blindname == '' then blindname = 'Small Blind' end

    -- Defer to vanilla for boss fights (boss_colour wins), pack states, and the win screen.
    local is_boss_ctx = false
    if blindname ~= 'Small Blind' and blindname ~= 'Big Blind' then
        for _, v in pairs(G.P_BLINDS) do
            if v.name == blindname and v.boss then is_boss_ctx = true break end
        end
    end
    local pack_state = (state == G.STATES.TAROT_PACK or state == G.STATES.SPECTRAL_PACK
        or state == G.STATES.STANDARD_PACK or state == G.STATES.BUFFOON_PACK
        or state == G.STATES.PLANET_PACK)
    if is_boss_ctx or pack_state or (G.GAME and G.GAME.won) then
        return _ease_bg_blind(state, blind_override)
    end

    -- Biome tint. Set the DYN_UI accent the same way vanilla does for the matching state,
    -- then ease the background to the biome colour (same shape as the boss-colour branch).
    if state == G.STATES.SHOP then
        ease_colour(G.C.DYN_UI.MAIN, mix_colours(G.C.RED, G.C.BLACK, 0.9))
    elseif G.GAME.blind then
        G.GAME.blind:change_colour()
    end
    ease_background_colour{
        new_colour = lighten(mix_colours(biome_col, G.C.BLACK, 0.3), 0.1),
        special_colour = biome_col,
        contrast = 2,
    }
end

-- ---- Selection trigger: after a BOSS cash-out, before the shop builds ----
-- Two-part mechanism so the screen behaves like blind select (background visible) AND the
-- shop animates in afterward:
--   1) cash_out wrap: when the blind just defeated was the BOSS (the same signal the base
--      game uses to roll next tags), set a pending flag. cash_out then transitions to SHOP.
--   2) update_shop wrap: while the flag is set, HOLD the shop build (don't create G.shop) and
--      show the transparent biome-select UIBox in the play area. Choosing clears the flag, so
--      the original update_shop runs and builds the shop with its normal slide-in animation.
if G.FUNCS and G.FUNCS.cash_out then
    local _cash_out = G.FUNCS.cash_out
    G.FUNCS.cash_out = function(e)
        local was_boss = G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_states
            and G.GAME.round_resets.blind_states.Boss == 'Defeated'
        _cash_out(e)
        if was_boss and PB_UTIL.should_offer_biome_select() and G.GAME then
            G.GAME.balacraft = G.GAME.balacraft or {}
            G.GAME.balacraft._biome_pending = true
        end
    end
end

if Game.update_shop then
    local _update_shop = Game.update_shop
    function Game:update_shop(dt)
        local pending = G.GAME and G.GAME.balacraft and G.GAME.balacraft._biome_pending
        if not G.STATE_COMPLETE and pending then
            if not G.balacraft_biome_select then
                -- Couldn't build the panel (e.g. nothing to offer): abandon, don't soft-lock.
                if not (PB_UTIL.open_biome_select and PB_UTIL.open_biome_select()) then
                    G.GAME.balacraft._biome_pending = nil
                    return _update_shop(self, dt)
                end
            end
            return   -- hold: the shop is not built until a biome is chosen
        end
        return _update_shop(self, dt)
    end
end

-- ---- Per-biome ante-win tracking (unlocks the per-biome start-decks) ----
-- Wrap Blind:defeat (composes with the resources/xp wraps). A defeated BOSS = an ante won;
-- credit it to the biome that was active for that ante, BEFORE cash_out's selection picks
-- the next one. record_biome_ante_win persists + unlocks at the threshold (progression.lua).
local _biomes_blind_defeat = Blind.defeat
function Blind:defeat(silent)
    _biomes_blind_defeat(self, silent)
    if self.boss and PB_UTIL.record_biome_ante_win then
        pcall(PB_UTIL.record_biome_ante_win, PB_UTIL.current_biome())
    end
end
