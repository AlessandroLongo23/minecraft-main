-- Hunger mechanic (Minecraft survival).
--
-- A second survival meter that drains as you progress through blinds. Foods refill it.
--   * Each blind you PLAY drains 1 drumstick; each blind you SKIP drains 2.
--   * Over-eat past full to bank SATURATION (gold drumsticks); each blind it converts to health
--     -- Minecraft's "saturation boost" (heals up to max only, never beyond). See PB_UTIL.feed.
--   * At 0 hunger, the next blind's drain costs you a full heart instead (starvation).
--
-- Like health, hunger is a PERSISTENT run-long pool stored as a plain integer on
-- G.GAME.balacraft -> auto-saved / auto-reset per run, no custom save/load.
--   Half-drumstick resolution: max_hunger = 20 -> 10 drumsticks (2 internal = 1 drumstick),
--   mirroring the half-heart system. Saturation shares the same units and caps at max_hunger.
--
-- Depends on the health module for heal/damage (saturation regen + starvation); all such calls
-- are guarded so hunger degrades gracefully if health is toggled off.

PB_UTIL.DEFAULT_MAX_HUNGER = 20    -- 10 drumsticks (1 drumstick = 2 internal). Tunable.

-- Tunables (per-blind economy). Internal units; 2 = 1 drumstick / 1 full heart.
PB_UTIL.HUNGER_DRAIN_PLAY  = 2     -- 1 drumstick per blind played
PB_UTIL.HUNGER_DRAIN_SKIP  = 4     -- 2 drumsticks per blind skipped
PB_UTIL.STARVE_DAMAGE      = 2     -- 1 full heart lost per blind while at 0 hunger
PB_UTIL.SATURATION_CONVERT = 2     -- saturation spent -> HP healed per blind (2 = 1 heart)

-- ---- State init (mirrors health.lua / resources.lua) ----
local _init_game_object = Game.init_game_object
function Game:init_game_object()
    local t = _init_game_object(self)
    t.balacraft = t.balacraft or {}
    t.balacraft.max_hunger = PB_UTIL.DEFAULT_MAX_HUNGER
    t.balacraft.hunger     = PB_UTIL.DEFAULT_MAX_HUNGER   -- start every run fed
    t.balacraft.saturation = 0                            -- no banked saturation; build it by over-eating
    return t
end

local function ensure_store()
    G.GAME.balacraft = G.GAME.balacraft or {}
    local s = G.GAME.balacraft
    if s.max_hunger == nil then s.max_hunger = PB_UTIL.DEFAULT_MAX_HUNGER end
    if s.hunger == nil then s.hunger = s.max_hunger end
    if s.saturation == nil then s.saturation = 0 end       -- covers runs saved before saturation existed
    return s
end

function PB_UTIL.get_hunger()         return ensure_store().hunger end
function PB_UTIL.get_max_hunger()     return ensure_store().max_hunger end
function PB_UTIL.get_saturation()     return ensure_store().saturation end
function PB_UTIL.get_max_saturation() return PB_UTIL.get_max_hunger() end  -- cap == hunger cap (MC-faithful)

-- Single mutation funnel (mirrors add_health/add_resource). Direct setters use this; it clamps to
-- [0, max_hunger] and does NOT bank saturation -- use PB_UTIL.feed for eating/feeding.
function PB_UTIL.add_hunger(amount)
    local s = ensure_store()
    s.hunger = math.max(0, math.min(s.max_hunger, s.hunger + math.floor(tonumber(amount) or 0)))
    return s.hunger
end

-- Eating funnel: fill hunger first, route any overflow into saturation (capped at max_hunger).
-- This is the only path that banks saturation; all food/feeding effects call it. Returns new hunger.
function PB_UTIL.feed(amount)
    local s = ensure_store()
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return s.hunger end
    local to_hunger = math.min(s.max_hunger - s.hunger, amount)
    s.hunger = s.hunger + to_hunger
    local overflow = amount - to_hunger
    if overflow > 0 then
        s.saturation = math.max(0, math.min(s.max_hunger, (s.saturation or 0) + overflow))
    end
    return s.hunger
end

function PB_UTIL.set_max_hunger(n)
    local s = ensure_store()
    s.max_hunger = math.max(1, math.floor(tonumber(n) or PB_UTIL.DEFAULT_MAX_HUNGER))
    s.hunger = math.min(s.hunger, s.max_hunger)
    return s.max_hunger
end

-- Advance one blind: drain hunger (or starve at 0), then convert banked saturation into health.
-- `drain` defaults to a played blind. Health calls are guarded (health module optional).
function PB_UTIL.hunger_tick(drain)
    if not (PB_UTIL.config and PB_UTIL.config.food_enabled) then return end
    drain = drain or PB_UTIL.HUNGER_DRAIN_PLAY
    local s = ensure_store()
    if s.hunger <= 0 then
        -- starving: a blind ticks while the bar is already empty -> lose a heart.
        -- The hearts UI auto-shakes + plays a slice when HP drops (health_ui.lua), but that
        -- reads identically to a mob hit, so surface an explicit "Starving!" callout too.
        if PB_UTIL.damage then PB_UTIL.damage(PB_UTIL.STARVE_DAMAGE) end
        pcall(function()
            if attention_text then
                attention_text({
                    scale = 0.9, text = 'Starving!  -1',
                    hold = 1.4, align = 'cm', offset = { x = 0, y = -2.7 },
                    major = G.play or G.deck, colour = G.C.RED,
                })
            end
        end)
    else
        s.hunger = math.max(0, s.hunger - drain)
    end
    -- Saturation boost: spend banked saturation to heal real damage each blind (Minecraft's
    -- saturation-boost regen). Only when below max health, so a full reserve isn't wasted at full
    -- HP -- it sits as gold drumsticks until you take a hit. No-op if the health module is off.
    s.saturation = s.saturation or 0
    if s.saturation > 0 and PB_UTIL.heal and PB_UTIL.get_health
        and PB_UTIL.get_health() < PB_UTIL.get_max_health() then
        local spend = math.min(s.saturation, PB_UTIL.SATURATION_CONVERT)
        s.saturation = s.saturation - spend
        PB_UTIL.heal(spend)   -- heal() already clamps to max_health
    end
end

-- Called from the skip-blind lovely patch (button_callbacks.lua, at the G.GAME.skips bump).
-- pcall'd so a hunger error can never wedge the base-game skip flow.
function PB_UTIL.hunger_on_skip()
    pcall(PB_UTIL.hunger_tick, PB_UTIL.HUNGER_DRAIN_SKIP)
end

-- ---- Per-blind drain on a PLAYED blind: wrap Blind:defeat (fires once per blind beaten) ----
-- Stacks cleanly on resources.lua's Blind:defeat wrap (drops). Skipping never calls defeat,
-- so play vs skip are mutually exclusive -- no double count.
local _blind_defeat = Blind.defeat
function Blind:defeat(silent)
    _blind_defeat(self, silent)
    pcall(PB_UTIL.hunger_tick, PB_UTIL.HUNGER_DRAIN_PLAY)
end
