-- Hearts HUD: a row of Minecraft hearts top-left, ABOVE the joker row.
--
-- Mirrors the resource hotbar (resource_ui.lua): a Weak-bonded UIBox driven by a Game:update
-- wrapper, with a bc_major rebuild guard (Weak bonds are NOT auto-removed when their major is
-- recreated on a new run). Self-contained so it works even when the resource module is off.
--
-- Hearts swap sprite cells (full/half/empty) as HP changes, so the box is REBUILT on any HP /
-- max-HP change (cheap -- ~10 sprites, only on a damage/heal event, not every frame).

-- 16x16 cells in a row: full {0,0}, half {1,0}, empty {2,0}.
PB_UTIL.heart_atlas = SMODS.Atlas { key = 'bc_hearts', path = 'hearts.png', px = 16, py = 16 }

-- States where the joker row (and so the hearts) should be on screen. Own copy so this module
-- doesn't depend on resource_ui.lua's PANEL_STATES. G.STATES is populated before mod files run.
PB_UTIL.HEALTH_STATES = {
    [G.STATES.SELECTING_HAND] = true,
    [G.STATES.DRAW_TO_HAND]   = true,
    [G.STATES.HAND_PLAYED]    = true,
    [G.STATES.SHOP]           = true,
    [G.STATES.BLIND_SELECT]   = true,
    [G.STATES.ROUND_EVAL]     = true,
}

-- Tunables (tune in-game).
local MAX_SZ   = 0.34   -- max world-units per 16x16 heart sprite
local SIDE_FRAC = 0.46  -- hearts occupy at most this fraction of the joker-row width
local ROW_GAP  = 0.12   -- vertical gap between the hearts row and the joker row's top edge
local HEART_PAD = 0.012 -- horizontal padding between hearts

-- ---- Definition builder ----

function PB_UTIL.build_health_bar()
    local hp     = PB_UTIL.get_health()
    local max_hp = PB_UTIL.get_max_health()
    local hearts = math.ceil(max_hp / 2)                 -- 20 HP -> 10 heart slots
    local atlas  = G.ASSET_ATLAS[PB_UTIL.heart_atlas.key]
    local jok_w  = (G.jokers and G.jokers.T.w) or (5 * G.CARD_W)
    -- Auto-size so the hearts hug the LEFT half of the joker width, leaving room for the
    -- hunger drumsticks hugging the RIGHT half (the Minecraft HUD split) without overlap.
    local sz = math.max(0.12, math.min(MAX_SZ, (jok_w * SIDE_FRAC) / hearts - 2 * HEART_PAD))

    local cells = {}
    for i = 1, hearts do
        local filled = hp - (i - 1) * 2                   -- HP contributed to this slot
        local pos = (filled >= 2 and { x = 0, y = 0 })    -- full
                 or (filled == 1 and { x = 1, y = 0 })    -- half
                 or { x = 2, y = 0 }                       -- empty
        cells[#cells + 1] = {
            n = G.UIT.C, config = { align = 'cm', padding = HEART_PAD },
            nodes = {
                { n = G.UIT.O, config = { object = Sprite(0, 0, sz, sz, atlas, pos) } },
            },
        }
    end

    -- ROOT spans the joker-row width; the inner row is left-aligned ('cl') so the hearts hug
    -- the LEFT edge -> reads as "top-left, above the jokers". (Same trick the resource toggle
    -- bar uses with 'cr' for right-aligned.)
    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0, colour = G.C.CLEAR, minw = jok_w },
        -- The inner row spans the FULL joker width (minw) so 'cl' pushes the hearts to the
        -- left edge; the hunger bar's row mirrors this with 'cr' for the right edge.
        nodes = { { n = G.UIT.R, config = { align = 'cl', padding = 0, minw = jok_w }, nodes = cells } },
    }
end

-- ---- UIBox lifecycle ----

-- 'tm' = outer-top + horizontal-middle: the box's BOTTOM edge lands ROW_GAP above the joker
-- area's top edge, centred over it (moveable.lua). The joker-width ROOT + left-aligned content
-- makes the hearts read as left-aligned above the row.
function PB_UTIL.attach_health_bar()
    local dropped = G.bc_health_bar and G.bc_health_bar.bc_hp and (PB_UTIL.get_health() < G.bc_health_bar.bc_hp)
    if G.bc_health_bar and not G.bc_health_bar.REMOVED then G.bc_health_bar:remove() end
    G.bc_health_bar = UIBox {
        definition = PB_UTIL.build_health_bar(),
        config = { align = 'tm', offset = { x = 0, y = -ROW_GAP }, major = G.jokers, bond = 'Weak' },
    }
    -- Rebuild triggers: new run recreates G.jokers; HP/max change swaps heart cells.
    G.bc_health_bar.bc_major = G.jokers
    G.bc_health_bar.bc_hp    = PB_UTIL.get_health()
    G.bc_health_bar.bc_maxhp = PB_UTIL.get_max_health()
    G.bc_health_bar.bc_w     = (G.jokers and G.jokers.T.w) or 0

    -- Light "got hit" feedback (only when HP actually dropped).
    if dropped then
        pcall(function() G.bc_health_bar:juice_up(0.4, 0.2) end)
        pcall(play_sound, 'slice1', 0.96 + math.random() * 0.08)
    end
end

local function remove_health_bar()
    if G.bc_health_bar and not G.bc_health_bar.REMOVED then G.bc_health_bar:remove() end
    G.bc_health_bar = nil
end

-- ---- Per-frame driver ----

function PB_UTIL.update_health_bar()
    local active = G.STATE and PB_UTIL.HEALTH_STATES[G.STATE]
        and PB_UTIL.config and PB_UTIL.config.health_enabled
        and G.jokers and G.GAME and G.GAME.balacraft
        and PB_UTIL.heart_atlas and G.ASSET_ATLAS[PB_UTIL.heart_atlas.key]

    if not active then
        remove_health_bar()
        return
    end

    if not G.bc_health_bar or G.bc_health_bar.REMOVED
        or G.bc_health_bar.bc_major ~= G.jokers                 -- new run -> jokers rebuilt
        or G.bc_health_bar.bc_hp    ~= PB_UTIL.get_health()     -- damage / heal
        or G.bc_health_bar.bc_maxhp ~= PB_UTIL.get_max_health()
        or G.bc_health_bar.bc_w     ~= ((G.jokers and G.jokers.T.w) or 0) then  -- joker slots changed
        PB_UTIL.attach_health_bar()
    end
end

-- Single per-frame hook (stacked wrap; resource_ui.lua proves stacking Game:update is fine).
-- pcall'd so a transient error can't wedge Game:update.
local _game_update = Game.update
function Game:update(dt)
    _game_update(self, dt)
    local ok, err = pcall(PB_UTIL.update_health_bar)
    if not ok then sendDebugMessage('health ui error: ' .. tostring(err), 'BalaCraft') end
end
