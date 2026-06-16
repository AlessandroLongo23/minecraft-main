-- Resource inventory hotbar panel: a self-owned UIBox bonded Weak to G.consumeables.

-- States in which the panel should be visible.
-- Built at load time; G.STATES is populated before mod files run (SMODS load order).
PB_UTIL.PANEL_STATES = {
    [G.STATES.SELECTING_HAND] = true,
    [G.STATES.DRAW_TO_HAND]   = true,
    [G.STATES.HAND_PLAYED]    = true,
    [G.STATES.SHOP]           = true,
    [G.STATES.BLIND_SELECT]   = true,
    [G.STATES.ROUND_EVAL]     = true,
}

local PER_ROW = 3

-- Build the UIBox definition from the registry + current counts.
function PB_UTIL.build_resources_panel()
    local store = (G.GAME.balacraft and G.GAME.balacraft.resources) or {}
    local atlas = G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]
    local cells = {}
    for _, r in ipairs(PB_UTIL.RESOURCES) do
        local count = store[r.id] or 0
        if r.kind == 'gathered' or count > 0 then
            local owned = count > 0
            local spr = Sprite(0, 0, 0.5, 0.5, atlas, r.pos)
            if not owned and spr.set_alpha then spr:set_alpha(0.35) end
            cells[#cells + 1] = {
                n = G.UIT.C, config = { align = 'cm', padding = 0.04 },
                nodes = {
                    { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                        { n = G.UIT.O, config = { object = spr } },
                    } },
                    { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                        { n = G.UIT.T, config = {
                            ref_table = store, ref_value = r.id, scale = 0.32,
                            colour = owned and G.C.WHITE or G.C.UI.TEXT_INACTIVE,
                        } },
                    } },
                },
            }
        end
    end
    local rows = {}
    for i = 1, #cells, PER_ROW do
        local row = { n = G.UIT.R, config = { align = 'cm' }, nodes = {} }
        for j = i, math.min(i + PER_ROW - 1, #cells) do
            row.nodes[#row.nodes + 1] = cells[j]
        end
        rows[#rows + 1] = row
    end
    rows[#rows + 1] = {
        n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
            { n = G.UIT.C, config = {
                align = 'cm', padding = 0.06, r = 0.08, minw = 1.6,
                colour = G.C.GREEN, button = 'bc_open_crafting', hover = true, shadow = true,
            }, nodes = {
                { n = G.UIT.T, config = { text = 'Crafting Table', scale = 0.28, colour = G.C.UI.TEXT_LIGHT } },
            } },
        },
    }
    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0.06, r = 0.1, colour = G.C.BLACK, emboss = 0.05 },
        nodes = rows,
    }
end

-- (Re)create the panel UIBox, bonded below the consumables area.
function PB_UTIL.attach_resources_panel()
    if G.balacraft_resources_panel and not G.balacraft_resources_panel.REMOVED then
        G.balacraft_resources_panel:remove()
    end
    G.balacraft_resources_panel = UIBox {
        definition = PB_UTIL.build_resources_panel(),
        config = { align = 'cm', offset = { x = 0, y = 1.5 }, major = G.consumeables, bond = 'Weak' },
    }
    -- Record the backing store so we can detect a rotated table (e.g. new run) and rebuild.
    G.balacraft_resources_panel.bc_store = G.GAME.balacraft and G.GAME.balacraft.resources
    G.GAME.balacraft._panel_dirty = false
end

-- Per-frame: create/refresh/hide based on game state.
function PB_UTIL.update_resources_panel()
    local can_show = G.STATE and PB_UTIL.PANEL_STATES[G.STATE]
        and G.consumeables and G.GAME and G.GAME.balacraft
        and PB_UTIL.icon_atlas and G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]
    if can_show then
        if not G.balacraft_resources_panel or G.balacraft_resources_panel.REMOVED then
            PB_UTIL.attach_resources_panel()
        elseif G.balacraft_resources_panel.bc_store ~= G.GAME.balacraft.resources then
            PB_UTIL.attach_resources_panel()
        elseif G.GAME.balacraft._panel_dirty then
            PB_UTIL.attach_resources_panel()
        end
    elseif G.balacraft_resources_panel and not G.balacraft_resources_panel.REMOVED then
        G.balacraft_resources_panel:remove()
        G.balacraft_resources_panel = nil
    end
end

local _game_update = Game.update
function Game:update(dt)
    _game_update(self, dt)
    local ok, err = pcall(PB_UTIL.update_resources_panel)
    if not ok then sendDebugMessage('panel error: ' .. tostring(err), 'BalaCraft') end
end
