-- Enchanting Table — an in-frame Base station that GENERATES enchant books. Mirrors the MC
-- enchanting screen: a Book + Lapis count "slot" pair and three rolled offers (a random enchant
-- type at tier = slot index). Taking offer N spends N levels + N lapis + 1 Book and creates that
-- enchant-book consumable in the MC consumable area. The roll persists across reopen, re-rolling on
-- a new shop (G.GAME.round change) or after a take. Applying books is FREE and happens at the Anvil.
-- Loaded in main.lua's enhancements block AFTER enchanting.lua. Renders inside the two-row Base
-- modal's Row-1-left slot (crafting_ui.lua station_content_node dispatch); inventory/consumables/
-- picker come from the shell.

PB_UTIL.ENCHANT_TABLE_REQ = { 7, 18, 30 }   -- XP level REQUIRED per tier (MC's three slots)

local function bc() return G.GAME and G.GAME.balacraft end

-- Roll three offers: slot i -> { etype = random enchant type, tier = i }. pseudoseed advances per
-- key each call, so a re-roll (round change / after a take) yields a fresh set.
function PB_UTIL.roll_enchant_offers()
    local b = bc(); if not b then return end
    local offers = {}
    local order = PB_UTIL.ENCHANT_ORDER or { 'sharpness' }
    for i = 1, 3 do
        local etype = order[1]
        if pseudorandom_element then
            etype = pseudorandom_element(order, pseudoseed('bc_ench_offer_' .. i))
        end
        offers[i] = { etype = etype, tier = i }
    end
    b.enchant_offers = offers
    b.enchant_offers_epoch = G.GAME.round
end

-- Lazily (re)roll: empty, or the round changed since the last roll (a new shop).
function PB_UTIL.ensure_enchant_offers()
    local b = bc(); if not b then return end
    if not b.enchant_offers or b.enchant_offers_epoch ~= G.GAME.round then
        PB_UTIL.roll_enchant_offers()
    end
end

-- Affordability for offer i: level >= req, lapis >= i, book >= 1, room in the MC consumable area.
local function offer_affordable(i)
    local b = bc(); if not b then return false end
    local offer = b.enchant_offers and b.enchant_offers[i]
    if not offer then return false end
    local req = PB_UTIL.ENCHANT_TABLE_REQ[i] or 0
    if not (PB_UTIL.get_level and PB_UTIL.get_level() >= req) then return false end
    if not (PB_UTIL.get_resource_count and PB_UTIL.get_resource_count('lapis') >= i) then return false end
    if not (PB_UTIL.get_resource_count and PB_UTIL.get_resource_count('book') >= 1) then return false end
    if not (PB_UTIL.mc_has_room and PB_UTIL.mc_has_room()) then return false end
    return true
end

-- A count-backed "slot": resource icon + "Name: N".
local function res_count_slot(label, rid)
    local r = PB_UTIL.RESOURCE_BY_ID and PB_UTIL.RESOURCE_BY_ID[rid]
    local atlas = PB_UTIL.icon_atlas and G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]
    local count = (PB_UTIL.get_resource_count and PB_UTIL.get_resource_count(rid)) or 0
    local icon = (r and atlas) and { n = G.UIT.O, config = { object = Sprite(0, 0, 0.6, 0.6, atlas, r.pos) } }
        or { n = G.UIT.T, config = { text = '?', scale = 0.4, colour = G.C.UI.TEXT_INACTIVE } }
    return { n = G.UIT.C, config = { align = 'cm', padding = 0.06, r = 0.08, minw = 1.1, minh = 1.1,
        colour = G.C.UI.TRANSPARENT_DARK }, nodes = {
        { n = G.UIT.R, config = { align = 'cm' }, nodes = { icon } },
        { n = G.UIT.R, config = { align = 'cm' }, nodes = {
            { n = G.UIT.T, config = { text = label .. ': ' .. count, scale = 0.22, colour = G.C.UI.TEXT_LIGHT } } } },
    } }
end

-- One offer cell (compact vertical card): tier circle / book icon / name / level requirement.
-- Sits beside the other two offers in a horizontal row.
local function offer_row(i, offer)
    local def  = PB_UTIL.ENCHANTS and PB_UTIL.ENCHANTS[offer.etype]
    local roman = (PB_UTIL.ENCHANT_ROMAN and PB_UTIL.ENCHANT_ROMAN[offer.tier]) or tostring(offer.tier)
    local name = ((def and def.name) or offer.etype) .. ' ' .. roman
    local req  = PB_UTIL.ENCHANT_TABLE_REQ[i] or 0
    local met  = (PB_UTIL.get_level and PB_UTIL.get_level() or 0) >= req

    local circle = { n = G.UIT.C, config = { align = 'cm', padding = 0.04, r = 0.5, minw = 0.4, minh = 0.4,
        colour = G.C.GREEN }, nodes = {
        { n = G.UIT.T, config = { text = tostring(i), scale = 0.3, colour = G.C.UI.TEXT_LIGHT } } } }

    local b     = PB_UTIL.ENCHANT_BOOK_BY_ID and PB_UTIL.ENCHANT_BOOK_BY_ID[offer.etype .. '_' .. offer.tier]
    local atlas = PB_UTIL.enchant_icon_atlas and G.ASSET_ATLAS[PB_UTIL.enchant_icon_atlas.key]
    local bicon = (b and b.pos and atlas) and { n = G.UIT.O, config = { object = Sprite(0, 0, 0.55, 0.55, atlas, b.pos) } }
        or { n = G.UIT.C, config = { align = 'cm', minw = 0.55, minh = 0.55 }, nodes = {} }

    return { n = G.UIT.C, config = {
        align = 'cm', padding = 0.06, r = 0.08, minw = 2.7, minh = 2.1,
        colour = G.C.UI.TRANSPARENT_DARK,
        button = 'bc_ench_take', func = 'bc_can_ench_take', ref_table = { index = i },
        hover = true, shadow = true,
    }, nodes = {
        { n = G.UIT.R, config = { align = 'cm', padding = 0.02 }, nodes = { circle } },
        { n = G.UIT.R, config = { align = 'cm', padding = 0.02 }, nodes = { bicon } },
        { n = G.UIT.R, config = { align = 'cm', padding = 0.02, maxw = 2.5 }, nodes = {
            { n = G.UIT.T, config = { text = name, scale = 0.28, colour = G.C.UI.TEXT_LIGHT } } } },
        { n = G.UIT.R, config = { align = 'cm', padding = 0.02 }, nodes = {
            { n = G.UIT.T, config = { text = 'Lv ' .. req, scale = 0.28,
                colour = met and G.C.GREEN or G.C.RED } } } },
    } }
end

-- The Row-1-left content node for the Enchanting Table station (called by station_content_node).
function PB_UTIL.enchant_station_content()
    PB_UTIL.ensure_enchant_offers()
    local b = bc()
    local offers = (b and b.enchant_offers) or {}
    local cells = {}
    for i = 1, 3 do
        if offers[i] then
            cells[#cells + 1] = { n = G.UIT.C, config = { align = 'cm', padding = 0.04 },
                nodes = { offer_row(i, offers[i]) } }
        end
    end
    return { n = G.UIT.C, config = { align = 'cm', padding = 0.06 }, nodes = {
        { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
            res_count_slot('Book', 'book'),
            res_count_slot('Lapis', 'lapis'),
        } },
        { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = cells },
    } }
end

-- ── Callbacks ──────────────────────────────────────────────────────────────
G.FUNCS.bc_can_ench_take = function(e)
    local i = e.config.ref_table and e.config.ref_table.index
    if i and offer_affordable(i) then
        e.config.colour = G.C.UI.TRANSPARENT_DARK
        e.config.button = 'bc_ench_take'
    else
        e.config.colour = G.C.UI.BACKGROUND_INACTIVE
        e.config.button = nil
    end
end

G.FUNCS.bc_ench_take = function(e)
    local i = e.config.ref_table and e.config.ref_table.index
    if not (i and offer_affordable(i)) then play_sound('cancel'); return end
    local b = bc()
    local offer = b and b.enchant_offers and b.enchant_offers[i]
    if not offer then play_sound('cancel'); return end
    PB_UTIL.spend_level(i)
    PB_UTIL.add_resource('lapis', -i)
    PB_UTIL.add_resource('book', -1)
    local key = 'c_balacraft_enchant_' .. offer.etype .. '_' .. offer.tier
    if G.P_CENTERS[key] then consumable_add(key) end
    b._panel_dirty = true
    pcall(play_sound, 'tarot1', 1.0, 0.7)
    PB_UTIL.roll_enchant_offers()
    PB_UTIL.open_inventory('enchant')
end
