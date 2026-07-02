-- The Minecraft-style XP bar HUD widget.
--
-- A Weak-bonded UIBox (same lifecycle pattern as resource_ui.lua) anchored
-- bottom-centre under the hand, sitting in the empty band below the
-- Play/Sort/Discard buttons. It shows a recreated MC experience bar (a green
-- fill that grows left->right) with the level number above it.
--
-- The bar is a custom drawable modelled on the engine Sprite: it draws the empty
-- frame full-width, then the green frame clipped to PB_UTIL.get_xp_progress() via
-- a resized Quad -- read LIVE each frame, so the fill animates with no UIBox
-- rebuild (the same "mutate the draw, don't rebuild" idea as make_dimmable).
--
-- Fallback if the custom draw ever misbehaves: swap the UIT.O bar node for a UIT
-- node with `config.progress_bar = { max=1, ref_table=..., ref_value=..., ... }`
-- (engine built-in, ui.lua:814) driven off a live 0..1 value.

-- The XP-bar sprite sheet: 182x14 cells, frame {0,0}=empty, {0,1}=full (green).
-- py MUST match H in assets/gen_xp_bar.py (the source frame height).
PB_UTIL.xp_atlas = SMODS.Atlas {
    key = 'bc_xp_bar',
    path = 'xp_bar.png',
    px = 182,
    py = 14,
}

-- States in which the bar shows (the hand-relevant states; gated again on G.hand
-- existing). Built at load time -- G.STATES is populated before mod files run.
PB_UTIL.XP_BAR_STATES = {
    [G.STATES.SELECTING_HAND] = true,
    [G.STATES.DRAW_TO_HAND]   = true,
    [G.STATES.HAND_PLAYED]    = true,
    -- Booster-pack states (mirrors resource_ui.lua's PACK_STATES): keep the XP bar visible while
    -- choosing a pack card, so level info can inform the pick. The bar bonds to G.hand, so it sits
    -- wherever the hand is during the pack (present when a pack opens mid-blind).
    [G.STATES.TAROT_PACK]     = true,
    [G.STATES.PLANET_PACK]    = true,
    [G.STATES.SPECTRAL_PACK]  = true,
    [G.STATES.STANDARD_PACK]  = true,
    [G.STATES.BUFFOON_PACK]   = true,
}
if G.STATES.SMODS_BOOSTER_OPENED ~= nil then   -- modded packs (incl. BalaCraft's own Toolbox/Potion packs)
    PB_UTIL.XP_BAR_STATES[G.STATES.SMODS_BOOSTER_OPENED] = true
end

-- Tunables (tune in-game, like the resource_ui offsets).
local BAR_W    = 11.0   -- fallback width; the bar otherwise spans the hand area (way longer)
local BAR_H    = 0.30   -- bar thickness in world-units (thicker than MC's strict 182:5 aspect)
local BAR_DROP = 2.2    -- how far below the hand's bottom edge to sit (clears the button row)
local NUM_DY   = -0.04  -- level number's vertical nudge ON the bar (negative = up); it
                        -- overlaps the bar like MC. (UI nodes can't overlap within one
                        -- UIBox, so the number is a second UIBox bonded centred on the bar.)

-- MC lime green for the level number (Balatro's G.C.GREEN is a teal; this matches
-- the bar art). RGBA 0..1.
PB_UTIL.MC_GREEN = { 0.49, 0.95, 0.19, 1 }

-- Live-bound level label. The bound T-node renders this each frame (ui.lua), so the
-- driver only writes the string -- no UIBox rebuild when the level changes.
PB_UTIL.xp_label_ref = PB_UTIL.xp_label_ref or { text = '' }

-- ---- Custom bar drawable ----

-- A real Sprite (so the UIT.O node positions it like any other object) whose
-- draw_self is overridden to layer empty track + clipped green fill. Uses
-- self.atlas.px/py + self.image_dims (NOT hardcoded 182/5) so it is correct under
-- both 1x and 2x texture scaling -- exactly how set_sprite_pos builds the base quad.
function PB_UTIL.make_xp_bar_sprite(w, h)
    local atlas = G.ASSET_ATLAS[PB_UTIL.xp_atlas.key]
    local spr = Sprite(0, 0, w, h, atlas, { x = 0, y = 0 })  -- base = empty frame
    spr.draw_self = function(self, overlay)
        if not self.states.visible then return end
        prep_draw(self, 1)
        love.graphics.scale(1 / (self.scale.x / self.VT.w), 1 / (self.scale.y / self.VT.h))
        love.graphics.setColor(overlay or G.BRUTE_OVERLAY or G.C.WHITE)
        -- empty track (full width)
        love.graphics.draw(self.atlas.image, self.sprite, 0, 0, 0,
            self.VT.w / self.T.w, self.VT.h / self.T.h)
        -- green fill: row 1 of the atlas, clipped to the progress fraction
        local p = PB_UTIL.get_xp_progress and PB_UTIL.get_xp_progress() or 0
        if p > 0 then
            local fw = self.atlas.px * p
            if fw < 1 then fw = 1 end
            self._fill_quad = love.graphics.newQuad(0, self.atlas.py, fw, self.atlas.py,
                self.image_dims[1], self.image_dims[2])
            love.graphics.draw(self.atlas.image, self._fill_quad, 0, 0, 0,
                self.VT.w / self.T.w, self.VT.h / self.T.h)
        end
        love.graphics.pop()
        add_to_drawhash(self)
        self:draw_boundingrect()
        if self.shader_tab then love.graphics.setShader() end
    end
    return spr
end

-- ---- Definition builder ----

-- The bar UIBox (just the segmented sprite). The number is a SEPARATE UIBox
-- (build_xp_label) so it can overlap the bar -- UIT nodes can't overlap within one
-- UIBox (calculate_xywh lays children out in flow; UIT.O nodes don't even lay out
-- children -- ui.lua:127).
function PB_UTIL.build_xp_bar()
    -- Span the hand area's width so the bar reads as "way longer", centred under the
    -- Sort Hand toggle; fall back to BAR_W before the hand is measurable. The texture
    -- (with its segment notches) stretches to fit, so thickness is set independently.
    local bar_w = (G.hand and G.hand.T and G.hand.T.w) or BAR_W
    local spr = PB_UTIL.make_xp_bar_sprite(bar_w, BAR_H)
    G.bc_xp_bar_spr = spr
    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0, colour = G.C.CLEAR },
        nodes = {
            { n = G.UIT.O, config = { object = spr } },
        },
    }
end

-- The level number, drawn on top of the bar (its own UIBox, bonded centred on the
-- bar). Live-bound text -> no rebuild when the level changes; blank at level 0.
function PB_UTIL.build_xp_label()
    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0, colour = G.C.CLEAR },
        nodes = {
            { n = G.UIT.T, config = {
                ref_table = PB_UTIL.xp_label_ref, ref_value = 'text',
                scale = 0.5, colour = PB_UTIL.MC_GREEN, shadow = true,
            } },
        },
    }
end

-- ---- UIBox lifecycle ----

-- 'bm' = outer-bottom + horizontal-middle: the box's TOP edge lands BAR_DROP below
-- the hand's bottom edge, centred over it (so it reads as centred under the Sort
-- Hand toggle). Weak bond survives the hand being recreated on a new run.
function PB_UTIL.attach_xp_bar()
    if G.bc_xp_bar and not G.bc_xp_bar.REMOVED then G.bc_xp_bar:remove() end
    if G.bc_xp_label and not G.bc_xp_label.REMOVED then G.bc_xp_label:remove() end
    G.bc_xp_bar = UIBox {
        definition = PB_UTIL.build_xp_bar(),
        config = { align = 'bm', offset = { x = 0, y = BAR_DROP }, major = G.hand, bond = 'Weak' },
    }
    G.bc_xp_bar.bc_major = G.hand
    -- Number overlaid on the bar: 'cm' centres it on the bar, NUM_DY nudges it.
    G.bc_xp_label = UIBox {
        definition = PB_UTIL.build_xp_label(),
        config = { align = 'cm', offset = { x = 0, y = NUM_DY }, major = G.bc_xp_bar, bond = 'Weak' },
    }
end

local function remove_xp_bar()
    if G.bc_xp_bar and not G.bc_xp_bar.REMOVED then G.bc_xp_bar:remove() end
    if G.bc_xp_label and not G.bc_xp_label.REMOVED then G.bc_xp_label:remove() end
    G.bc_xp_bar = nil
    G.bc_xp_label = nil
    G.bc_xp_bar_spr = nil
end

-- ---- Per-frame driver ----

function PB_UTIL.update_xp_bar()
    local active = G.STATE and PB_UTIL.XP_BAR_STATES[G.STATE]
        and G.hand and G.GAME and G.GAME.balacraft
        and PB_UTIL.xp_atlas and G.ASSET_ATLAS[PB_UTIL.xp_atlas.key]

    if not active then
        remove_xp_bar()
        return
    end

    if not G.bc_xp_bar or G.bc_xp_bar.REMOVED or G.bc_xp_bar.bc_major ~= G.hand
        or not G.bc_xp_label or G.bc_xp_label.REMOVED then
        PB_UTIL.attach_xp_bar()
    end

    -- Live label: the level number, blank at level 0 (MC hides "0").
    local lvl = PB_UTIL.get_level()
    PB_UTIL.xp_label_ref.text = (lvl >= 1) and tostring(lvl) or ''

    -- Consume the level-up flag set by add_xp -> a little juice pop of the bar and
    -- the number, matching health_ui's feedback style.
    if G.GAME.balacraft._xp_levelup then
        G.GAME.balacraft._xp_levelup = false
        pcall(function() G.bc_xp_bar:juice_up(0.4, 0.15) end)
        pcall(function() G.bc_xp_label:juice_up(0.5, 0.2) end)
    end
end

-- Single per-frame hook (pcall'd, like resource_ui's): maintain the bar UIBox.
-- (Score-based XP was removed; XP is now event-driven, so there's no per-frame watcher.)
local _game_update = Game.update
function Game:update(dt)
    _game_update(self, dt)
    local ok2, err2 = pcall(PB_UTIL.update_xp_bar)
    if not ok2 then sendDebugMessage('xp bar error: ' .. tostring(err2), 'BalaCraft') end
end
