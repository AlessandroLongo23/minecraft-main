-- Enchant button UI. A Weak-bonded "Enchant" button floats below the consumable area when a
-- valid enchant target is selected -- either a tool + book (both in consumables) OR, for any
-- dual-target book, a playing card in hand + the book. Clicking it spends levels and
-- applies the enchant (utilities/enchanting.lua, via the unified target dispatch).
--
-- Mirrors the Weak-bonded UIBox + Game:update driver in utilities/resource_ui.lua. Loads in
-- the enhancements_enabled block AFTER utilities/enchanting.lua.

-- Gap BELOW the consumable area's bottom edge where the Enchant bar floats. (Above the area
-- overflows the top of the screen and collides with the resource toggle bar, so it sits below.)
local ENCHANT_BAR_GAP = 0.15

local ENCHANT_COLOUR = HEX('8e44ad')   -- enchant purple

-- States in which enchanting is offered: anywhere consumables are interactive (shop, blind
-- select, hand selection, cash out...). Reuse the resource panel's state set so the Enchant
-- bar appears in the same places the consumable cards do. (Tools can only be USED during a
-- blind -- see their can_use -- but they can be ENCHANTED in the shop right after buying a book.)
local function enchant_state_ok()
    if PB_UTIL.PANEL_STATES then return PB_UTIL.PANEL_STATES[G.STATE] == true end
    return G.STATE == G.STATES.SELECTING_HAND
end

-- ---- Definition ----

local function build_enchant_bar(target)
    local cost  = PB_UTIL.enchant_target_cost(target)
    local label = (target.mode == 'card') and 'Enchant Card' or 'Enchant'
    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0, colour = G.C.CLEAR },
        nodes = { { n = G.UIT.R, config = { align = 'cm' }, nodes = {
            { n = G.UIT.C, config = {
                align = 'cm', padding = 0.08, r = 0.08, minw = 2.2, minh = 0.56,
                colour = ENCHANT_COLOUR, hover = true, shadow = true, one_press = true,
                button = 'bc_enchant', func = 'bc_can_enchant',
                ref_table = { target = target },
              }, nodes = {
                { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                    { n = G.UIT.T, config = { text = label, scale = 0.38,
                        colour = G.C.UI.TEXT_LIGHT, shadow = true } },
                } },
                { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                    { n = G.UIT.T, config = { text = 'Cost ', scale = 0.26, colour = G.C.UI.TEXT_LIGHT } },
                    { n = G.UIT.T, config = { text = cost .. ' Lv', scale = 0.3, colour = G.C.BLUE } },
                } },
              } },
        } } },
    }
end

-- ---- Lifecycle ----

function PB_UTIL.attach_enchant_bar(target)
    if G.bc_enchant_bar and not G.bc_enchant_bar.REMOVED then G.bc_enchant_bar:remove() end
    G.bc_enchant_bar = UIBox {
        definition = build_enchant_bar(target),
        config = { align = 'bm', offset = { x = 0, y = ENCHANT_BAR_GAP }, major = G.consumeables, bond = 'Weak' },
    }
    -- Remember the target + area so the driver rebuilds on any change (target/area swapped).
    G.bc_enchant_bar.bc_major = G.consumeables
    G.bc_enchant_bar.bc_target_key = PB_UTIL.enchant_target_key(target)
end

local function remove_enchant_bar()
    if G.bc_enchant_bar and not G.bc_enchant_bar.REMOVED then G.bc_enchant_bar:remove() end
    G.bc_enchant_bar = nil
end

-- ---- Per-frame driver ----

function PB_UTIL.update_enchant_ui()
    -- Self-heal enchanted tool sprites every frame (Card:load reverts them to the base cell;
    -- the transient fingerprint is nil after load, so this re-applies once). Runs whenever the
    -- consumable area exists -- not just during the Enchant-bar states -- so an enchanted tool
    -- shows its sprite in the shop too.
    if PB_UTIL.refresh_tool_sprite and G.consumeables and G.consumeables.cards then
        for _, c in ipairs(G.consumeables.cards) do
            if PB_UTIL.is_tool_card(c) then
                local want = PB_UTIL.tool_sprite_fingerprint(c)
                if c.bc_sprite_fp ~= want then
                    PB_UTIL.refresh_tool_sprite(c)
                    c.bc_sprite_fp = want
                end
            end
        end
    end

    local active = G.consumeables and G.GAME and G.GAME.balacraft and enchant_state_ok()
        and (not PB_UTIL.get_view_mode or PB_UTIL.get_view_mode() ~= 'resources')
    if not active then return remove_enchant_bar() end

    -- Keep two-card highlighting available even if the area was rebuilt this run.
    PB_UTIL.ensure_enchant_highlight_limit()

    -- Tool target (tool + book) OR card target (card in hand + any book).
    local target = PB_UTIL.get_enchant_target()
    if not target then return remove_enchant_bar() end

    if not G.bc_enchant_bar or G.bc_enchant_bar.REMOVED
        or G.bc_enchant_bar.bc_major ~= G.consumeables
        or G.bc_enchant_bar.bc_target_key ~= PB_UTIL.enchant_target_key(target) then
        PB_UTIL.attach_enchant_bar(target)
    end
end

-- ---- Button FUNCs ----

-- Re-evaluated each frame: enable (purple) when the target is valid AND affordable, else grey.
G.FUNCS.bc_can_enchant = function(e)
    local target = e.config.ref_table and e.config.ref_table.target
    local ok = target and PB_UTIL.enchant_target_valid(target)
        and PB_UTIL.can_spend_level
        and PB_UTIL.can_spend_level(PB_UTIL.enchant_target_cost(target))
    if ok then
        e.config.colour = ENCHANT_COLOUR
        e.config.button = 'bc_enchant'
    else
        e.config.colour = G.C.UI.BACKGROUND_INACTIVE
        e.config.button = nil
    end
end

G.FUNCS.bc_enchant = function(e)
    local target = e.config.ref_table and e.config.ref_table.target
    if target then PB_UTIL.apply_enchant_target(target) end
end

-- Drive the Enchant bar each frame (pcall'd so a transient UI error can't wedge Game:update).
local _game_update = Game.update
function Game:update(dt)
    _game_update(self, dt)
    local ok, err = pcall(PB_UTIL.update_enchant_ui)
    if not ok then sendDebugMessage('enchant ui error: ' .. tostring(err), 'BalaCraft') end
end
