-- Sheet registry (DATA + atlases). Mirrors content/foods/registry.lua: pure data table
-- PB_UTIL.SHEETS plus lookups, and the two card/icon atlases. No SMODS centers here.
--
-- A Sheet is a consumable you craft (Anvil: 2 of one ore -> 1 sheet; the GLASS sheet is the
-- exception, crafted at the Crafting Table from Glass) and then APPLY to a playing card to give it
-- an ENHANCEMENT (the card's center -- card:set_ability, NOT an edition). The application flow lives
-- in content/sheets/sheet_consumabletype.lua (the sheet's own use() reads the highlighted hand card,
-- exactly like a Tarot).
--
-- m_key = the enhancement center the sheet applies. Gold/Iron/Glass reuse the VANILLA centers
-- (m_gold / m_steel / m_glass); the Iron sheet's m_steel is RENAMED to "Iron" for display (the
-- init_localization wrap at the bottom -- there is no "steel" in Minecraft). Lapis reuses the mod's
-- existing m_balacraft_lapis (XP per play). Diamond/Emerald/Redstone/Coal use the new centers in
-- content/card_enhancements/sheet_enhancements.lua.
--
-- ore     = the resource consumed to craft it (2x, at the station below).
-- station = 'anvil' (Forge Sheets tab) | 'table' (Crafting Table; glass only).
PB_UTIL.SHEETS = {
    { id = 'gold',     name = 'Gold Sheet',     m_key = 'm_gold',               ore = 'gold',     station = 'anvil', cost = 4, pos = { x = 0, y = 0 }, icon = { x = 0, y = 0 } },
    { id = 'iron',     name = 'Iron Sheet',     m_key = 'm_steel',              ore = 'iron',     station = 'anvil', cost = 4, pos = { x = 1, y = 0 }, icon = { x = 1, y = 0 } },
    { id = 'glass',    name = 'Glass Sheet',    m_key = 'm_glass',              ore = 'glass',    station = 'table', cost = 4, pos = { x = 2, y = 0 }, icon = { x = 2, y = 0 } },
    { id = 'diamond',  name = 'Diamond Sheet',  m_key = 'm_balacraft_diamond',  ore = 'diamond',  station = 'anvil', cost = 6, pos = { x = 0, y = 1 }, icon = { x = 0, y = 1 } },
    { id = 'emerald',  name = 'Emerald Sheet',  m_key = 'm_balacraft_emerald',  ore = 'emerald',  station = 'anvil', cost = 5, pos = { x = 1, y = 1 }, icon = { x = 1, y = 1 } },
    { id = 'redstone', name = 'Redstone Sheet', m_key = 'm_balacraft_redstone', ore = 'redstone', station = 'anvil', cost = 5, pos = { x = 2, y = 1 }, icon = { x = 2, y = 1 } },
    { id = 'lapis',    name = 'Lapis Sheet',    m_key = 'm_balacraft_lapis',    ore = 'lapis',    station = 'anvil', cost = 5, pos = { x = 0, y = 2 }, icon = { x = 0, y = 2 } },
    { id = 'coal',     name = 'Coal Sheet',     m_key = 'm_balacraft_coal',     ore = 'coal',     station = 'anvil', cost = 3, pos = { x = 1, y = 2 }, icon = { x = 1, y = 2 } },
}

PB_UTIL.SHEET_BY_ID = {}
for _, s in ipairs(PB_UTIL.SHEETS) do PB_UTIL.SHEET_BY_ID[s.id] = s end

-- Card sheet (71x95, 3x3 grid) for the consumable face; icon sheet (34x34, 3x3) for the crafting
-- recipe list / anvil output preview. Built by assets/gen_sheets.py from assets/1x/Sheet_template.png.
PB_UTIL.sheet_card_atlas = SMODS.Atlas {
    key = 'bc_sheet_cards', path = 'sheet_cards.png', px = 71, py = 95,
}
PB_UTIL.sheet_icon_atlas = SMODS.Atlas {
    key = 'bc_sheet_icons', path = 'sheet_icons.png', px = 34, py = 34,
}

-- Steel -> "Iron" display rename. The Iron sheet applies the vanilla Steel enhancement (m_steel,
-- X1.5 Mult while held) but Minecraft has no "steel", so we relabel it everywhere it shows. Same
-- technique as the Night/Cave blind rename (utilities/functions.lua): wrap init_localization (which
-- re-runs on every prototype rebuild) and overwrite the localized name AFTER the base build, rather
-- than setting it once (which would be wiped). The vanilla h_x_mult=1.5 scoring is untouched -- only
-- the label changes. This relabels ALL Steel sources (Chariot tarot, Steel Joker tooltip), which is
-- correct for a Minecraft total-conversion.
if not PB_UTIL._steel_to_iron_wrapped and type(init_localization) == 'function' then
    PB_UTIL._steel_to_iron_wrapped = true
    local _init_localization = init_localization
    function init_localization()
        _init_localization()
        local e = G.localization and G.localization.descriptions and G.localization.descriptions.Enhanced
        if e and e.m_steel then
            e.m_steel.name = 'Iron Card'
            e.m_steel.name_parsed = nil
            if e.m_steel.label then e.m_steel.label = 'Iron Card' end
        end
    end
end
