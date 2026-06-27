-- Brewing Stand overlay — a button-driven Base station (modelled on the Anvil's Combine list, NOT
-- the drag crafting table). A Blaze-Powder fuel gauge on top, then a list of brew recipes: each row
-- shows its ingredients (have/need) and a Brew button, plus a small button per applicable modifier
-- (Glowstone/Redstone/Dragon's Breath) when you hold its ingredient. No drag state -> every action
-- just rebuilds the overlay in place (refresh_overlay -> no fly-in).

-- ---- small UI helpers (local; mirror furnace.lua's) ----
local function text_row(str, scale, colour)
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.02 }, nodes = {
        { n = G.UIT.T, config = { text = str, scale = scale or 0.4, colour = colour or G.C.UI.TEXT_LIGHT } } } }
end

local function res_icon(id, sz)
    local r = PB_UTIL.RESOURCE_BY_ID and PB_UTIL.RESOURCE_BY_ID[id]
    local atlas = PB_UTIL.icon_atlas and G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]
    if r and atlas then
        return { n = G.UIT.O, config = { object = Sprite(0, 0, sz or 0.32, sz or 0.32, atlas, r.pos) } }
    end
    return { n = G.UIT.T, config = { text = ' ', scale = 0.3 } }
end

local function full_btn(label, fn, colour)
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.06 }, nodes = { {
        n = G.UIT.R, config = { align = 'cm', padding = 0.12, r = 0.1, minw = 3, colour = colour or G.C.BLUE,
            button = fn, hover = true, shadow = true },
        nodes = { { n = G.UIT.T, config = { text = label, scale = 0.42, colour = G.C.UI.TEXT_LIGHT } } } } } }
end

local function res_name(id)
    local r = PB_UTIL.RESOURCE_BY_ID and PB_UTIL.RESOURCE_BY_ID[id]
    return (r and r.name) or id
end

-- One ingredient chip: icon + have/need, dimmed red when short.
local function ing_chip(id, need)
    local have = PB_UTIL.get_resource_count(id)
    local ok = have >= need
    return { n = G.UIT.C, config = { align = 'cm', padding = 0.03 }, nodes = {
        res_icon(id, 0.3),
        { n = G.UIT.T, config = { text = have .. '/' .. need, scale = 0.26,
            colour = ok and G.C.UI.TEXT_LIGHT or G.C.RED } } } }
end

local MOD_LABEL = { potency = 'II', duration = 'Long', lingering = 'Linger' }

-- Encode a mods set as a comma-joined key string for the button callback.
local function mods_to_str(mods)
    local t = {}
    for k, v in pairs(mods or {}) do if v then t[#t + 1] = k end end
    return table.concat(t, ',')
end

-- A small Brew / modifier button carrying its full mods SET (so combined variants like II+Long work).
local function brew_btn(label, key, mods, enabled)
    return { n = G.UIT.C, config = { align = 'cm', padding = 0.05, r = 0.08, minw = 1.25, minh = 0.5,
        colour = enabled and G.C.GREEN or G.C.UI.TRANSPARENT_DARK,
        button = enabled and 'bc_brew' or nil, bc_brew_key = key, bc_brew_mods = mods_to_str(mods),
        hover = enabled, shadow = true },
        nodes = { { n = G.UIT.T, config = { text = label, scale = 0.3, colour = G.C.UI.TEXT_LIGHT } } } }
end

-- The valid (Level, lasts-more) combinations for a recipe -> one button each. `lasts` is Redstone
-- duration (drinkables) or Dragon's Breath lingering (throwables), whichever the potion accepts.
local function recipe_combos(recipe)
    local m = recipe.mods or {}
    local lasts = m.duration and 'duration' or (m.lingering and 'lingering' or nil)
    local combos = { { label = 'Brew', mods = {} } }
    if lasts then combos[#combos + 1] = { label = '+' .. MOD_LABEL[lasts], mods = { [lasts] = true } } end
    if m.potency then combos[#combos + 1] = { label = '+II', mods = { potency = true } } end
    if m.potency and lasts then
        combos[#combos + 1] = { label = '+II ' .. MOD_LABEL[lasts], mods = { potency = true, [lasts] = true } }
    end
    return combos
end

-- ---- recipe row ----
local function recipe_row(recipe)
    local ing_nodes = {}
    for _, pair in ipairs(recipe.ing) do
        ing_nodes[#ing_nodes + 1] = ing_chip(pair[1], pair[2])
    end
    -- one Brew button per valid combination (base, +lasts, +II, +II+lasts), enabled when affordable.
    local btns = {}
    for _, combo in ipairs(recipe_combos(recipe)) do
        btns[#btns + 1] = brew_btn(combo.label, recipe.key, combo.mods, PB_UTIL.can_brew(recipe, combo.mods))
    end
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.04, r = 0.08, minw = 8.6, minh = 0.66,
        colour = G.C.UI.TRANSPARENT_DARK }, nodes = {
        { n = G.UIT.C, config = { align = 'cl', padding = 0.04, minw = 2.6 }, nodes = {
            { n = G.UIT.T, config = { text = recipe.name, scale = 0.32, colour = G.C.UI.TEXT_LIGHT } } } },
        { n = G.UIT.C, config = { align = 'cm', padding = 0.04, minw = 3.0 }, nodes = {
            { n = G.UIT.R, config = { align = 'cm' }, nodes = ing_nodes } } },
        { n = G.UIT.C, config = { align = 'cr', padding = 0.04 }, nodes = {
            { n = G.UIT.R, config = { align = 'cr' }, nodes = btns } } },
    } }
end

-- ---- modal ----
function PB_UTIL.build_brewing_modal()
    local fuel = PB_UTIL.get_brew_fuel()
    local have_blaze = PB_UTIL.get_resource_count('blaze_powder')
    local fuel_row = { n = G.UIT.R, config = { align = 'cm', padding = 0.06, r = 0.1, colour = G.C.BLACK, minw = 8.6 }, nodes = {
        res_icon('blaze_powder', 0.4),
        { n = G.UIT.T, config = { text = '  Fuel: ' .. fuel .. ' charge' .. (fuel == 1 and '' or 's') .. '   ',
            scale = 0.36, colour = G.C.ORANGE } },
        { n = G.UIT.C, config = { align = 'cm', padding = 0.06, r = 0.08, minw = 2.6, minh = 0.5,
            colour = have_blaze >= 1 and G.C.BLUE or G.C.UI.TRANSPARENT_DARK,
            button = have_blaze >= 1 and 'bc_brew_add_fuel' or nil, hover = have_blaze >= 1, shadow = true },
            nodes = { { n = G.UIT.T, config = { text = 'Add Blaze Powder (' .. have_blaze .. ')',
                scale = 0.28, colour = G.C.UI.TEXT_LIGHT } } } },
    } }

    local list = { n = G.UIT.C, config = { align = 'cm', padding = 0.03 }, nodes = {} }
    for _, r in ipairs(PB_UTIL.BREW_RECIPES) do
        list.nodes[#list.nodes + 1] = recipe_row(r)
    end

    return { n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0.1, r = 0.1, colour = G.C.GREY, minw = 9, minh = 5 },
        nodes = {
            text_row('Brewing Stand', 0.6, G.C.PURPLE or G.C.ORANGE),
            fuel_row,
            { n = G.UIT.R, config = { align = 'cm', minh = 0.06 }, nodes = {} },
            { n = G.UIT.R, config = { align = 'cm' }, nodes = { list } },
            { n = G.UIT.R, config = { align = 'cm', minh = 0.06 }, nodes = {} },
            full_btn('Back', 'bc_brewing_back'),
        } }
end

function PB_UTIL.open_brewing()
    PB_UTIL.refresh_overlay(PB_UTIL.build_brewing_modal())
end

-- ---- callbacks ----
G.FUNCS.bc_open_brewing = function(e) PB_UTIL.open_brewing() end

G.FUNCS.bc_brew_add_fuel = function(e)
    if PB_UTIL.brew_add_fuel() then play_sound('chips1', 1, 0.6) else play_sound('cancel') end
    PB_UTIL.open_brewing()
end

G.FUNCS.bc_brew = function(e)
    local key = e.config and e.config.bc_brew_key
    local modstr = (e.config and e.config.bc_brew_mods) or ''
    local recipe
    for _, r in ipairs(PB_UTIL.BREW_RECIPES) do if r.key == key then recipe = r break end end
    local mods = {}
    for k in string.gmatch(modstr, '[^,]+') do mods[k] = true end
    if recipe and PB_UTIL.do_brew(recipe, mods) then
        play_sound('tarot1', 1.0, 0.7)
        if G.GAME and G.GAME.balacraft then G.GAME.balacraft._panel_dirty = true end
    else
        play_sound('cancel')
    end
    PB_UTIL.open_brewing()
end

G.FUNCS.bc_brewing_back = function(e)
    if PB_UTIL.open_base then PB_UTIL.open_base() else G.FUNCS.exit_overlay_menu(e) end
end

-- The Brewing Stand is wired into the live Base modal picker (PICKER_STATIONS in crafting_ui.lua),
-- where it opens this overlay (bc_open_brewing) once the station is crafted -- parallel to the Anvil.
