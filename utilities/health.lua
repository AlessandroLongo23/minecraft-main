-- Health / Hearts mechanic (Minecraft combat).
--
-- A boss blind is a "mob". Every hand you play that does NOT beat the boss, the mob attacks
-- back and you take damage. Health is a PERSISTENT, run-long pool (carried across blinds and
-- antes); at 0 the run ends -- a new lose condition driven by attrition. Food consumables
-- (later) heal via PB_UTIL.heal().
--
-- State lives on G.GAME.balacraft.{health,max_health} as plain integers -> auto-saved and
-- auto-reset per run, same hybrid model as the resource counts (see resources.lua). There is
-- deliberately NO custom save/load code; don't add any.
--   1 HP = half a heart, so max_health = 20 -> 10 hearts.

PB_UTIL.DEFAULT_MAX_HEALTH = 20   -- 10 hearts (1 HP = half heart). Tunable.

-- ---- State init (mirrors resources.lua's init_game_object wrapper) ----
-- Stacking with the resources wrapper is order-safe: both use `t.balacraft = t.balacraft or {}`
-- and write disjoint keys, so neither clobbers the other regardless of load order.
local _init_game_object = Game.init_game_object
function Game:init_game_object()
    local t = _init_game_object(self)
    t.balacraft = t.balacraft or {}
    t.balacraft.max_health = PB_UTIL.DEFAULT_MAX_HEALTH
    t.balacraft.health     = PB_UTIL.DEFAULT_MAX_HEALTH   -- start every run at full
    return t
end

-- Defensive accessor: guarantees the fields exist (covers runs saved before this feature
-- existed -> missing fields default to full).
local function ensure_store()
    G.GAME.balacraft = G.GAME.balacraft or {}
    local s = G.GAME.balacraft
    if s.max_health == nil then s.max_health = PB_UTIL.DEFAULT_MAX_HEALTH end
    if s.health == nil then s.health = s.max_health end
    return s
end

function PB_UTIL.get_health()     return ensure_store().health end
function PB_UTIL.get_max_health() return ensure_store().max_health end

-- End the run, reusing the base game's canonical game-over trigger (the same two globals set
-- by state_events.lua:115 / :305 and G.FUNCS.DT_lose_game). Game:update_game_over then builds
-- the standard screen. Guarded to the RUN stage so we never fire it from a menu.
-- NOTE: this bypasses the `context.game_over` path Mr. Bones hooks -- intended. Mr. Bones
-- saves a chip shortfall, not death-by-attrition.
function PB_UTIL.die()
    if G.STAGE == G.STAGES.RUN then
        G.STATE = G.STATES.GAME_OVER
        G.STATE_COMPLETE = false
    end
end

-- Single mutation funnel (mirrors PB_UTIL.add_resource). Positive heals, negative damages;
-- clamps to [0, max_health]; triggers death at 0. Returns the new HP.
function PB_UTIL.add_health(amount)
    local s = ensure_store()
    local prev = s.health
    s.health = math.max(0, math.min(s.max_health, prev + math.floor(tonumber(amount) or 0)))
    if s.health <= 0 then PB_UTIL.die() end
    return s.health
end

-- Convenience wrappers. Food's healing plugs into heal() trivially later.
function PB_UTIL.heal(amount)   return PB_UTIL.add_health( math.abs(math.floor(tonumber(amount) or 0))) end
function PB_UTIL.damage(amount) return PB_UTIL.add_health(-math.abs(math.floor(tonumber(amount) or 0))) end

function PB_UTIL.set_max_health(n)
    local s = ensure_store()
    s.max_health = math.max(1, math.floor(tonumber(n) or PB_UTIL.DEFAULT_MAX_HEALTH))
    s.health = math.min(s.health, s.max_health)
    return s.max_health
end

-- ---- Per-mob damage (mirrors PB_UTIL.BLIND_DROPS; keyed by the prefixed G.GAME.blind.name) ----
-- PLACEHOLDER BALANCE (shape fixed, numbers tunable). Anything absent uses the default.
-- Values are in HP; 2 HP = 1 heart.
PB_UTIL.DEFAULT_MOB_DAMAGE = 2          -- 1 heart per failed hand
PB_UTIL.MOB_DAMAGE = {
    bl_balacraft_creeper  = 6,          -- hits hard: 3 hearts
    bl_balacraft_skeleton = 3,          -- 1.5 hearts (exercises the half-heart render)
    bl_balacraft_zombie   = 2,
    bl_balacraft_spider   = 2,
    bl_balacraft_husk     = 3,
    bl_balacraft_drowned  = 3,
    bl_balacraft_stray    = 3,
}

function PB_UTIL.mob_damage(key)
    return PB_UTIL.MOB_DAMAGE[key] or PB_UTIL.DEFAULT_MOB_DAMAGE
end

-- ---- Damage hook: wrap Game:update_hand_played (dump/game.lua:3383) ----
-- The engine's `else` branch (G.STATE = DRAW_TO_HAND) is the exact "played a hand, did NOT beat
-- the blind, and the fight continues" case, gated on the win check G.GAME.chips - G.GAME.blind.chips.
--
-- TIMING (the subtle part): we must NOT read G.GAME.chips synchronously here. The played hand's
-- score is added to G.GAME.chips by a deferred, non-blocking `ease` event (dump/state_events.lua:878)
-- that is queued AFTER G.STATE_COMPLETE is reset to false (dump/state_events.lua:553) -- i.e. after
-- the moment this body runs. So at this point G.GAME.chips still holds the PRE-hand cumulative
-- (0 on the first hand of the blind), and a synchronous `chips - blind.chips < 0` is true even on a
-- winning hand -> a heart was wrongly removed on every first hand. The engine sidesteps this by
-- doing its own win check inside a deferred `immediate` event (dump/game.lua:3389), which the queue
-- naturally orders after the chip ease.
--
-- So: capture only the static "this is an active boss fight" preconditions now (the `not
-- G.STATE_COMPLETE` gate, same as the engine, makes this arm exactly once per played hand), then
-- defer the win/loss comparison to an `immediate` event queued right after the engine's own
-- win-check event. By then G.GAME.chips holds the final eased total, so the comparison is correct.
--   * boss-only: G.GAME.blind.boss (dump/blind.lua:113), and not disabled.
--   * hands_left >= 1: the final losing hand resolves as the normal chip-loss game over
--     (keeps Mr. Bones able to save a chip shortfall cleanly). Drop this guard if you ever
--     want mobs to land a killing blow on the last hand.
local _update_hand_played = Game.update_hand_played
function Game:update_hand_played(dt)
    local arm = not G.STATE_COMPLETE
        and PB_UTIL.config and PB_UTIL.config.health_enabled
        and G.GAME and G.GAME.blind
        and G.GAME.blind.boss
        and not G.GAME.blind.disabled

    _update_hand_played(self, dt)

    if arm then
        local blind_key = G.GAME.blind.name
        G.E_MANAGER:add_event(Event({
            trigger = 'immediate',
            func = function()
                if G.GAME and G.GAME.blind and G.GAME.chips and G.GAME.blind.chips
                    and (G.GAME.chips - G.GAME.blind.chips < 0)
                    and G.GAME.current_round and (G.GAME.current_round.hands_left >= 1)
                    -- Potion of Invisibility: no boss-blind damage while active (utilities/potions.lua).
                    and not (PB_UTIL.boss_damage_blocked and PB_UTIL.boss_damage_blocked()) then
                    PB_UTIL.damage(PB_UTIL.mob_damage(blind_key))
                end
                return true
            end
        }))
    end
end
