-- Villager Trading SHOP VIEW-TOGGLE. Replaces the old separate side-panel: the villager now
-- shares the shop's footprint via a flip toggle, exactly like resource_ui.lua does for the
-- consumable area. The two views are:
--   * 'shop'     -> the vanilla shop (our overlay hidden, G.shop drawn normally)
--   * 'villager' -> the ENTIRE base-game shop UIBox is hidden (G.shop.states.visible = false),
--                   and a full-size villager UIBox is shown in its place with its own Next Round
--                   + Reroll controls and the emerald-priced offers.
--
-- Why hiding the whole shop works (verified against the engine dumps): a CardArea embedded in a
-- UIBox gets `.parent` set (engine/ui.lua:372), so the shop's joker/voucher/booster areas are
-- SKIPPED by the global G.I.CARDAREA draw loop (game.lua:2944) and only draw through the shop
-- tree. UIBox:draw (engine/ui.lua) gates add_to_drawhash + UIRoot:draw_self/draw_children on
-- states.visible, and Node/UIElement:draw_children re-check it at every level -- so visible=false
-- drops the shop's whole subtree (cards, vouchers, boosters, buttons) from BOTH rendering and the
-- draw-hash (no hover/click). One assignment hides everything.
--
-- The flip bar and the villager overlay are SEPARATE UIBoxes bonded to G.shop for POSITION only
-- (bonding anchors position; it does not make them children of G.shop), so hiding G.shop never
-- hides them. A Game:update wrapper drives create/refresh/hide each frame, mirroring
-- resource_ui.lua's attach/maintain/teardown idiom (rebuild on a recreated shop / replaced offers
-- table / a buy that flipped an offer to sold via _villager_dirty).
--
-- View state lives at G.GAME.balacraft.shop_view_mode ('shop' default | 'villager'); it is reset
-- to 'shop' whenever a fresh G.shop instance is detected, so every shop visit opens on the
-- vanilla shop. (Seeded in resources.lua's init_game_object wrapper -> auto-saved/reset per run.)

local OFFER_ICON_SZ = 0.7    -- offer icon sprite size (world-units; tunable)
local BAR_GAP       = 0.12   -- gap between the flip bar and the shop's top edge (tunable)

-- Live-bound label for the flip button: names the view the click switches TO.
PB_UTIL.shop_view_label_ref = PB_UTIL.shop_view_label_ref or { text = 'Villager' }

-- ---- View-mode state helpers ----

function PB_UTIL.get_shop_view_mode()
    return (G.GAME and G.GAME.balacraft and G.GAME.balacraft.shop_view_mode) or 'shop'
end

function PB_UTIL.set_shop_view_mode(mode)
    if G.GAME and G.GAME.balacraft then G.GAME.balacraft.shop_view_mode = mode end
end

-- Show/hide the entire vanilla shop in place (see header for why one flag suffices).
local function set_shop_visible(vis)
    if G.shop then G.shop.states.visible = vis end
end

-- ---- Definition builders ----

-- One offer, as a vertical "card" column: icon / label / emerald cost / Trade button.
local function offer_card(offer, emerald_atlas)
    local lbl_colour = offer.sold and G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT
    local label = offer.sold and (offer.label .. ' (Sold)') or offer.label

    -- Icon: a small 34x34 ICON cell (resource / tool / book / food), carried on the offer as
    -- { atlas = <atlas key>, pos = <cell> }. Falls back to an empty spacer if the atlas/pos is
    -- missing (e.g. an icon sheet that didn't load), so the row never errors.
    local icon_node
    local ic = offer.icon
    local atlas = ic and ic.atlas and G.ASSET_ATLAS[ic.atlas]
    if atlas and ic.pos then
        icon_node = { n = G.UIT.O, config = { object = Sprite(0, 0, OFFER_ICON_SZ, OFFER_ICON_SZ, atlas, ic.pos) } }
    else
        icon_node = { n = G.UIT.C, config = { minw = OFFER_ICON_SZ, minh = OFFER_ICON_SZ } }
    end

    return { n = G.UIT.C, config = { align = 'cm', padding = 0.12, r = 0.1, colour = G.C.BLACK, minw = 1.7 }, nodes = {
        -- Icon.
        { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = { icon_node } },
        -- Item label.
        { n = G.UIT.R, config = { align = 'cm', padding = 0.03 }, nodes = {
            { n = G.UIT.T, config = { text = label, scale = 0.32, colour = lbl_colour } },
        } },
        -- Emerald cost (bare frameless emerald sprite).
        { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
            { n = G.UIT.O, config = { object = Sprite(0, 0, 0.45, 0.45, emerald_atlas, { x = 0, y = 0 }) } },
            { n = G.UIT.T, config = { text = tostring(offer.cost), scale = 0.36, colour = G.C.WHITE } },
        } },
        -- Trade button (greys/disables via bc_can_buy_villager when unaffordable/sold/no slot).
        { n = G.UIT.R, config = {
            align = 'cm', padding = 0.06, r = 0.08, minw = 1.3, minh = 0.46,
            colour = G.C.GREEN, button = 'bc_buy_villager_offer', func = 'bc_can_buy_villager',
            ref_table = offer, hover = true, shadow = true,
          }, nodes = {
            { n = G.UIT.T, config = { text = 'Trade', scale = 0.32, colour = G.C.UI.TEXT_LIGHT } },
          } },
    } }
end

-- Left control column: Next Round + Reroll, REUSING the base-game button funcs verbatim so the
-- villager view behaves exactly like the shop's controls:
--   * Next Round -> 'toggle_shop' leaves the shop. Our overlay is Weak-bonded to G.shop, so it
--     slides away WITH the (hidden) shop during the exit animation, then the per-frame driver
--     tears it down once G.STATE leaves SHOP.
--   * Reroll -> 'bc_reroll_villager' (+ 'bc_can_reroll_villager' for greying). This is the villager's
--     OWN Emerald-priced reroll, INDEPENDENT of the base shop's $ reroll: it keeps the profession and
--     re-rolls only the trades, and rerolling the normal shop no longer touches these offers.
local function shop_controls_column(emerald_atlas)
    local bc = G.GAME and G.GAME.balacraft
    return { n = G.UIT.C, config = { align = 'cm', padding = 0.1 }, nodes = {
        { n = G.UIT.R, config = { align = 'cm', minw = 2.8, minh = 1.5, r = 0.15, colour = G.C.RED,
            one_press = true, button = 'toggle_shop', hover = true, shadow = true }, nodes = {
            { n = G.UIT.R, config = { align = 'cm', maxw = 1.3 }, nodes = {
                { n = G.UIT.T, config = { text = localize('b_next_round_1'), scale = 0.4, colour = G.C.WHITE, shadow = true } },
            } },
            { n = G.UIT.R, config = { align = 'cm', maxw = 1.3 }, nodes = {
                { n = G.UIT.T, config = { text = localize('b_next_round_2'), scale = 0.4, colour = G.C.WHITE, shadow = true } },
            } },
        } },
        { n = G.UIT.R, config = { align = 'cm', minh = 0.2 }, nodes = {} },   -- gap
        { n = G.UIT.R, config = { align = 'cm', minw = 2.8, minh = 1.6, r = 0.15, colour = G.C.GREEN,
            button = 'bc_reroll_villager', func = 'bc_can_reroll_villager', hover = true, shadow = true }, nodes = {
            { n = G.UIT.R, config = { align = 'cm', maxw = 1.3 }, nodes = {
                { n = G.UIT.T, config = { text = localize('k_reroll'), scale = 0.4, colour = G.C.WHITE, shadow = true } },
            } },
            -- Emerald cost (bare emerald sprite + live-bound villager reroll price).
            { n = G.UIT.R, config = { align = 'cm', maxw = 1.3, minw = 1 }, nodes = {
                { n = G.UIT.O, config = { object = Sprite(0, 0, 0.5, 0.5, emerald_atlas, { x = 0, y = 0 }) } },
                { n = G.UIT.T, config = { ref_table = bc, ref_value = 'villager_reroll_cost', scale = 0.7, colour = G.C.WHITE, shadow = true } },
            } },
        } },
    } }
end

-- Full villager panel: [controls][offers], wrapped in the shop's themed dyn container so it reads
-- as the same shop frame with different contents. Because the vanilla shop is hidden underneath,
-- this panel is free-standing -- it need not match the shop's exact footprint.
function PB_UTIL.build_villager_panel()
    local bc = G.GAME and G.GAME.balacraft
    local offers = (bc and bc.villager_offers) or {}
    local store  = (bc and bc.resources) or {}
    local emerald_atlas = G.ASSET_ATLAS[PB_UTIL.emerald_atlas.key]

    -- This shop's profession (the trader), names the header so the player knows who they're trading
    -- with and that a reroll keeps them.
    local prof = bc and bc.villager_profession and PB_UTIL.VILLAGER_PROFESSION_BY_ID
        and PB_UTIL.VILLAGER_PROFESSION_BY_ID[bc.villager_profession]
    local prof_name = (prof and prof.name) or 'Villager'

    -- Header: "<Profession>" + bare emerald icon + live count.
    local header = { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
        { n = G.UIT.T, config = { text = prof_name .. ' ', scale = 0.5, colour = G.C.UI.TEXT_LIGHT } },
        { n = G.UIT.O, config = { object = Sprite(0, 0, 0.7, 0.7, emerald_atlas, { x = 0, y = 0 }) } },
        { n = G.UIT.T, config = { ref_table = store, ref_value = 'emerald', scale = 0.5, colour = G.C.WHITE } },
    } }

    -- Offers in a single horizontal row.
    local offer_row = { n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {} }
    for _, offer in ipairs(offers) do
        offer_row.nodes[#offer_row.nodes + 1] = offer_card(offer, emerald_atlas)
    end
    if #offer_row.nodes == 0 then
        offer_row.nodes[1] = { n = G.UIT.R, config = { align = 'cm', minh = 1.6 }, nodes = {
            { n = G.UIT.T, config = { text = 'No trades available', scale = 0.4, colour = G.C.UI.TEXT_INACTIVE } },
        } }
    end

    -- Offers area box (mirrors the shop's L_BLACK joker container; minw matches the shop).
    local offers_area = { n = G.UIT.C, config = { align = 'cm', padding = 0.2, r = 0.2, colour = G.C.L_BLACK, emboss = 0.05, minw = 8.2 }, nodes = {
        header,
        offer_row,
    } }

    local inner = {
        { n = G.UIT.C, config = { align = 'cm', padding = 0.1, emboss = 0.05, r = 0.1, colour = G.C.DYN_UI.BOSS_MAIN }, nodes = {
            { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
                shop_controls_column(emerald_atlas),
                offers_area,
            } },
        } },
    }

    return {
        n = G.UIT.ROOT,
        config = { align = 'cl', colour = G.C.CLEAR },
        nodes = { UIBox_dyn_container(inner) },
    }
end

-- Flip bar: a single button whose label names the TARGET view (live-bound to shop_view_label_ref).
function PB_UTIL.build_shop_toggle_bar()
    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0.06, r = 0.1, colour = G.C.CLEAR },
        nodes = {
            { n = G.UIT.C, config = {
                align = 'cm', padding = 0.08, r = 0.08, minw = 2.4, minh = 0.5,
                colour = G.C.BLUE, button = 'bc_toggle_shop_view', hover = true, shadow = true,
              }, nodes = {
                { n = G.UIT.T, config = { ref_table = PB_UTIL.shop_view_label_ref, ref_value = 'text',
                    scale = 0.4, colour = G.C.UI.TEXT_LIGHT } },
              } },
        },
    }
end

-- ---- UIBox lifecycle ----

-- 'tm' = the bar's BOTTOM edge lands BAR_GAP above the shop's top edge, horizontally centred.
function PB_UTIL.attach_shop_toggle_bar()
    if G.bc_shop_toggle and not G.bc_shop_toggle.REMOVED then G.bc_shop_toggle:remove() end
    G.bc_shop_toggle = UIBox {
        definition = PB_UTIL.build_shop_toggle_bar(),
        config = { align = 'tm', offset = { x = 0, y = -BAR_GAP }, major = G.shop, bond = 'Weak' },
    }
    G.bc_shop_toggle.bc_major = G.shop
end

-- 'cm' = centred on the shop's footprint (offset 0,0). The shop's transform keeps updating even
-- when hidden, so this anchors correctly in villager view.
function PB_UTIL.attach_villager_overlay()
    if G.bc_villager_overlay and not G.bc_villager_overlay.REMOVED then G.bc_villager_overlay:remove() end
    G.bc_villager_overlay = UIBox {
        definition = PB_UTIL.build_villager_panel(),
        config = { align = 'cm', offset = { x = 0, y = 0 }, major = G.shop, bond = 'Weak' },
    }
    local bc = G.GAME and G.GAME.balacraft
    G.bc_villager_overlay.bc_offers = bc and bc.villager_offers
    G.bc_villager_overlay.bc_major  = G.shop
    if bc then bc._villager_dirty = false end
end

local function remove_overlay()
    if G.bc_villager_overlay and not G.bc_villager_overlay.REMOVED then G.bc_villager_overlay:remove() end
    G.bc_villager_overlay = nil
end

local function remove_toggle_bar()
    if G.bc_shop_toggle and not G.bc_shop_toggle.REMOVED then G.bc_shop_toggle:remove() end
    G.bc_shop_toggle = nil
end

-- ---- Per-frame driver ----

function PB_UTIL.update_shop_view()
    local bc = G.GAME and G.GAME.balacraft
    local active = G.STATE and G.STATE == G.STATES.SHOP
        and G.shop and bc and bc.villager_offers
        and PB_UTIL.icon_atlas and G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]
        and PB_UTIL.emerald_atlas and G.ASSET_ATLAS[PB_UTIL.emerald_atlas.key]

    if not active then
        -- Never leave the shop hidden when our UI isn't on screen (e.g. after leaving the shop).
        set_shop_visible(true)
        remove_overlay()
        remove_toggle_bar()
        return
    end

    -- A fresh shop instance (new visit / new run) -> default back to the vanilla shop view and
    -- rebind the toggle bar. 'Weak' bonds aren't auto-removed with their major, so we detect the
    -- swap ourselves.
    if G.bc_shop_view_major ~= G.shop then
        G.bc_shop_view_major = G.shop
        PB_UTIL.set_shop_view_mode('shop')
    end

    -- The flip bar is present whenever the shop is. Keep its label naming the TARGET view.
    if not G.bc_shop_toggle or G.bc_shop_toggle.REMOVED or G.bc_shop_toggle.bc_major ~= G.shop then
        PB_UTIL.attach_shop_toggle_bar()
    end
    local mode = PB_UTIL.get_shop_view_mode()
    PB_UTIL.shop_view_label_ref.text = (mode == 'villager') and 'Shop' or 'Villager'

    if mode == 'villager' then
        set_shop_visible(false)
        -- (Re)build the overlay on first show, a recreated shop, a replaced offers table
        -- (new shop / reroll), or a buy that flipped an offer to sold (_villager_dirty).
        if not G.bc_villager_overlay or G.bc_villager_overlay.REMOVED
            or G.bc_villager_overlay.bc_major ~= G.shop
            or G.bc_villager_overlay.bc_offers ~= bc.villager_offers
            or bc._villager_dirty then
            PB_UTIL.attach_villager_overlay()
        end
    else
        set_shop_visible(true)
        remove_overlay()
    end
end

-- ---- Button ----

-- Flip the view. Persisted on G.GAME (remember-last within a single shop visit); the per-frame
-- driver reflects the change next tick (label, shop visibility, overlay).
G.FUNCS.bc_toggle_shop_view = function(e)
    PB_UTIL.set_shop_view_mode(PB_UTIL.get_shop_view_mode() == 'villager' and 'shop' or 'villager')
    play_sound('cardSlide1')
end

-- Per-frame driver (pcall'd so a transient UI error can't wedge Game:update).
local _game_update = Game.update
function Game:update(dt)
    _game_update(self, dt)
    local ok, err = pcall(PB_UTIL.update_shop_view)
    if not ok then sendDebugMessage('shop view error: ' .. tostring(err), 'BalaCraft') end
end
