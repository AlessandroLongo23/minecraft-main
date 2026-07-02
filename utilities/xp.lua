-- Experience-points state + earning hooks.
--
-- Per-run XP with Minecraft-style levels: a running level counter plus XP toward
-- the next level. Both are plain integers on G.GAME.balacraft, so -- exactly like
-- the resource counts -- they auto-save within a run and auto-reset for a new one
-- (no custom save/load code, the mod's load-bearing convention; see resources.lua).
--
-- All XP flows through PB_UTIL.add_xp (a single mutation funnel, mirroring
-- PB_UTIL.add_resource). Earning hooks are plain Lua function-wraps installed at
-- load time -- the same technique the mod already uses for Blind:defeat,
-- Game.init_game_object and Game.update. No Lovely patches.
--
-- PB_UTIL.spend_level (below) powers the enchantment mechanic: applying an enchanting
-- book to a tool costs levels (see utilities/enchanting.lua).

-- ---- Seed per-run state ----
-- Guarded with `t.balacraft = t.balacraft or {}` so this composes with the
-- resources.lua init wrapper regardless of load order / whether resources is on.
local _init_game_object = Game.init_game_object
function Game:init_game_object()
    local t = _init_game_object(self)
    t.balacraft = t.balacraft or {}
    t.balacraft.xp = 0          -- XP banked toward the next level
    t.balacraft.xp_level = 0    -- current level (plain ints => auto-save/auto-reset)
    return t
end

-- ---- Balance (numbers tunable) ----
-- XP is EVENT-based, deliberately NOT tied to raw score. Balatro's score is super-exponential
-- (ante 1 small blind = 300 chips, ante 8 boss = 100,000, ante 13 ~ 9e10), so the old
-- `chips / score_div` award handed out billions of XP late game -> "level half a million".
--
-- Blinds are the spine of progression: award scales with ANTE-SQUARED so leveling tracks the
-- difficulty curve. Per-ante income = (4+7+14) * ante^2 = 25 * ante^2; cumulative through ante 8
-- = 25 * (1+4+9+...+64) = 25 * 204 = 5100 XP, which is ~level 49 on the Minecraft curve below.
-- Baseline level by end of each ante (before craft/buy/Lapis bonuses): ~2, 8, 15, 23, 29, 36, 42, 49.
PB_UTIL.XP_AWARDS = {
    blind = { small = 4, big = 7, boss = 14 },  -- multiplied by ante^2 (see grant_blind_xp)
    buy = 3,           -- buy a joker or consumable
    voucher = 10,      -- redeem (buy) a voucher
    sell = 2,          -- sell a joker or consumable
    craft = 5,         -- complete a craft in the Crafting Table
}

-- ---- State helpers ----

local function ensure_xp()
    G.GAME.balacraft = G.GAME.balacraft or {}
    local b = G.GAME.balacraft
    b.xp = b.xp or 0
    b.xp_level = b.xp_level or 0
    return b
end

-- Minecraft's per-level cost curve (authentic feel): XP to go from L to L+1.
function PB_UTIL.xp_to_next(level)
    level = level or 0
    if level <= 15 then return 2 * level + 7
    elseif level <= 30 then return 5 * level - 38
    else return 9 * level - 158 end
end

function PB_UTIL.get_xp()    return ensure_xp().xp end
function PB_UTIL.get_level() return ensure_xp().xp_level end

-- Fraction (0..1) of the way to the next level -- drives the bar fill.
function PB_UTIL.get_xp_progress()
    local b = ensure_xp()
    local need = PB_UTIL.xp_to_next(b.xp_level)
    if need <= 0 then return 0 end
    local p = b.xp / need
    if p < 0 then return 0 elseif p > 1 then return 1 end
    return p
end

-- Single mutation funnel. Adds whole XP, rolls over as many levels as the amount
-- covers, and flags a level-up so the UI can react (juice + sound).
function PB_UTIL.add_xp(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    local b = ensure_xp()
    b.xp = b.xp + amount
    local leveled = false
    while b.xp >= PB_UTIL.xp_to_next(b.xp_level) do
        b.xp = b.xp - PB_UTIL.xp_to_next(b.xp_level)
        b.xp_level = b.xp_level + 1
        leveled = true
    end
    if leveled then
        b._xp_levelup = true
        -- Bright shimmer for a level-up. Deliberately NOT 'gong': that is the Plasma Deck's chips/mult
        -- "balance" sting, and because XP is granted on buys/sells/crafts (earning hooks below), a gong
        -- here made those ordinary actions sound like a Plasma balance. (An authentic MC level-up .ogg
        -- registered via SMODS.Sound would be the ideal fit -- drop one in and swap this call.)
        pcall(play_sound, 'holo1', 1.15, 0.6)
    end
end

-- ---- Spending levels (enchantment mechanic) ----

-- True if the player currently has at least `n` whole levels to spend.
function PB_UTIL.can_spend_level(n)
    return PB_UTIL.get_level() >= math.floor(tonumber(n) or 0)
end

-- Spend `n` whole levels (Minecraft enchanting style). Returns false (no change) if the
-- player can't afford it. Partial XP toward the next level is kept but clamped so the bar
-- stays valid at the lower level.
function PB_UTIL.spend_level(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return true end
    local b = ensure_xp()
    if b.xp_level < n then return false end
    b.xp_level = b.xp_level - n
    local need = PB_UTIL.xp_to_next(b.xp_level)
    if b.xp >= need then b.xp = need - 1 end
    if b.xp < 0 then b.xp = 0 end
    -- Softer, lower-pitched twin of the level-up chime for SPENDING levels (enchanting). Also avoids
    -- 'gong' (the Plasma Deck balance sting) -- see add_xp.
    pcall(play_sound, 'holo1', 0.85, 0.45)
    return true
end

-- ---- Earning hooks ----

-- Defeat blind: scaled by blind type (small/big/boss) and ANTE-SQUARED, so the per-blind XP
-- keeps pace with the super-exponential blind requirement and leveling stays ~6 levels/ante.
function PB_UTIL.grant_blind_xp(blind)
    if not blind then return end
    local ante = (G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or 1
    local a = PB_UTIL.XP_AWARDS.blind
    local base
    if blind.boss then base = a.boss
    elseif blind.name == 'Big Blind' then base = a.big
    else base = a.small end
    PB_UTIL.add_xp(base * ante * ante)
end

local _blind_defeat = Blind.defeat
function Blind:defeat(silent)
    _blind_defeat(self, silent)
    pcall(PB_UTIL.grant_blind_xp, self)
end

-- Score-based XP was REMOVED: tying XP to raw chips made it explode on the super-exponential
-- late-game curve (an e12 hand granted ~1e10 XP). Progression is now purely event-based (blinds
-- scaled by ante^2, plus the action awards below). Kept as a documented no-op so the per-frame
-- caller (xp_ui.lua) and any cached reference degrade gracefully.
function PB_UTIL.update_xp_watch() end

-- Buy a joker or consumable from the shop. (Vouchers go through Card:redeem;
-- booster packs are 'Booster' set and intentionally excluded.)
if G.FUNCS and G.FUNCS.buy_from_shop then
    local _buy = G.FUNCS.buy_from_shop
    G.FUNCS.buy_from_shop = function(e)
        _buy(e)
        pcall(function()
            local c1 = e and e.config and e.config.ref_table
            if c1 and c1.ability and (c1.ability.set == 'Joker' or c1.ability.consumeable) then
                PB_UTIL.add_xp(PB_UTIL.XP_AWARDS.buy)
            end
        end)
    end
end

-- Redeem (buy) a voucher.
local _redeem = Card.redeem
function Card:redeem()
    _redeem(self)
    pcall(function()
        if self.ability and self.ability.set == 'Voucher' then
            PB_UTIL.add_xp(PB_UTIL.XP_AWARDS.voucher)
        end
    end)
end

-- Sell a joker or consumable (sell_card is only invoked for sellable cards).
local _sell_card = Card.sell_card
function Card:sell_card()
    pcall(PB_UTIL.add_xp, PB_UTIL.XP_AWARDS.sell)
    _sell_card(self)
end

-- Complete a craft. PB_UTIL.craft (crafting.lua) returns true on success; only
-- award then. Guarded because crafting only exists when resources_enabled.
if PB_UTIL.craft then
    local _craft = PB_UTIL.craft
    PB_UTIL.craft = function(recipe)
        local ok = _craft(recipe)
        if ok then pcall(PB_UTIL.add_xp, PB_UTIL.XP_AWARDS.craft) end
        return ok
    end
end
