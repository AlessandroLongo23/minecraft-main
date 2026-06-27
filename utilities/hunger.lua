-- Hunger mechanic (Minecraft survival).
--
-- A second survival meter that drains as you progress through blinds. Foods refill it.
--   * Each blind you PLAY drains 1 drumstick; each blind you SKIP drains 2.
--   * While well-fed (hunger high) you passively regenerate hearts each blind.
--   * At 0 hunger, the next blind's drain costs you a full heart instead (starvation).
--
-- Like health, hunger is a PERSISTENT run-long pool stored as a plain integer on
-- G.GAME.balacraft -> auto-saved / auto-reset per run, no custom save/load.
--   Half-drumstick resolution: max_hunger = 20 -> 10 drumsticks (2 internal = 1 drumstick),
--   mirroring the half-heart system.
--
-- Depends on the health module for heal/damage (regen + starvation); all such calls are
-- guarded so hunger degrades gracefully if health is toggled off.

PB_UTIL.DEFAULT_MAX_HUNGER = 20    -- 10 drumsticks (1 drumstick = 2 internal). Tunable.

-- Tunables (per-blind economy). Internal units; 2 = 1 drumstick / 1 full heart.
PB_UTIL.HUNGER_DRAIN_PLAY = 2      -- 1 drumstick per blind played
PB_UTIL.HUNGER_DRAIN_SKIP = 4      -- 2 drumsticks per blind skipped
PB_UTIL.STARVE_DAMAGE     = 2      -- 1 full heart lost per blind while at 0 hunger
PB_UTIL.REGEN_THRESHOLD   = 14     -- hunger >= this (>=7 drumsticks) -> well-fed regen
PB_UTIL.REGEN_AMOUNT      = 1      -- half a heart healed per blind while well-fed

-- ---- State init (mirrors health.lua / resources.lua) ----
local _init_game_object = Game.init_game_object
function Game:init_game_object()
    local t = _init_game_object(self)
    t.balacraft = t.balacraft or {}
    t.balacraft.max_hunger = PB_UTIL.DEFAULT_MAX_HUNGER
    t.balacraft.hunger     = PB_UTIL.DEFAULT_MAX_HUNGER   -- start every run fed
    return t
end

local function ensure_store()
    G.GAME.balacraft = G.GAME.balacraft or {}
    local s = G.GAME.balacraft
    if s.max_hunger == nil then s.max_hunger = PB_UTIL.DEFAULT_MAX_HUNGER end
    if s.hunger == nil then s.hunger = s.max_hunger end
    return s
end

function PB_UTIL.get_hunger()     return ensure_store().hunger end
function PB_UTIL.get_max_hunger() return ensure_store().max_hunger end

-- Single mutation funnel (mirrors add_health/add_resource). Foods feed positive amounts here.
function PB_UTIL.add_hunger(amount)
    local s = ensure_store()
    s.hunger = math.max(0, math.min(s.max_hunger, s.hunger + math.floor(tonumber(amount) or 0)))
    return s.hunger
end

function PB_UTIL.set_max_hunger(n)
    local s = ensure_store()
    s.max_hunger = math.max(1, math.floor(tonumber(n) or PB_UTIL.DEFAULT_MAX_HUNGER))
    s.hunger = math.min(s.hunger, s.max_hunger)
    return s.max_hunger
end

-- Advance one blind: drain hunger, then apply well-fed regen or (at 0) starvation.
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
    -- well-fed passive regen (heal clamps at max health; no-op if already full / health off)
    if s.hunger >= PB_UTIL.REGEN_THRESHOLD and PB_UTIL.heal then
        PB_UTIL.heal(PB_UTIL.REGEN_AMOUNT)
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
