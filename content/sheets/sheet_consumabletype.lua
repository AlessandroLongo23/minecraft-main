-- Sheet consumable type + the 8 sheet cards. A Sheet is APPLIED to a selected playing card to give
-- it an enhancement -- the SAME UX as a Tarot: highlight one card in hand, highlight the Sheet, then
-- Use. The sheet's use() reads G.hand.highlighted directly (a sheet + a hand card live in different
-- CardAreas, each independently highlightable), so no extra floating UI is needed. The sheet is
-- consumed on use (default consumable behaviour -- no keep_on_use).
--
-- Depends on PB_UTIL.SHEETS + the bc_sheet_cards atlas (content/sheets/registry.lua) and the
-- enhancement centers it applies (vanilla m_gold/m_steel/m_glass, the mod's m_balacraft_lapis, and
-- the new m_balacraft_{diamond,emerald,redstone,coal} in content/card_enhancements/sheet_enhancements
-- .lua) -- all resolved at use-time via G.P_CENTERS, so load order is not load-bearing.

-- A real playing card (base or already-enhanced), the only valid sheet target.
function PB_UTIL.is_playing_card(c)
    return c ~= nil and c.ability ~= nil
        and (c.ability.set == 'Default' or c.ability.set == 'Enhanced')
end

-- Valid iff the target is an un-debuffed playing card, the enhancement center exists, and the card
-- doesn't already carry THIS exact enhancement (a no-op). Applying over a DIFFERENT enhancement is
-- allowed -- it replaces it (Minecraft sheets overwrite).
function PB_UTIL.sheet_apply_valid(target, sheet)
    if not (target and sheet) then return false end
    if not PB_UTIL.is_playing_card(target) then return false end
    if target.debuff then return false end
    if not (G.P_CENTERS and G.P_CENTERS[sheet.m_key]) then return false end
    local cur = target.config and target.config.center and target.config.center.key
    if cur == sheet.m_key then return false end
    return true
end

-- Apply the sheet's enhancement to the card (set its center, like a Tarot), with juice + sound.
function PB_UTIL.apply_sheet(target, sheet)
    if not PB_UTIL.sheet_apply_valid(target, sheet) then return false end
    target:set_ability(G.P_CENTERS[sheet.m_key])
    if G.hand then G.hand:unhighlight_all() end
    if target.juice_up then target:juice_up(0.3, 0.5) end
    pcall(play_sound, 'gold_seal', 1.0, 0.8)
    return true
end

SMODS.ConsumableType {
    key = 'balacraft_sheet',
    primary_colour = HEX('95a5a6'),
    secondary_colour = HEX('bdc3c7'),
    collection_rows = { 4, 4 },        -- 8 sheets, two rows of four
    shop_rate = 0,                     -- craft-only (forged at the Anvil); never rolls in the shop
    no_collection = false,
    default = 'c_balacraft_sheet_iron',
    loc_txt = { name = 'Sheet', collection = 'Sheets' },
}

for _, s in ipairs(PB_UTIL.SHEETS) do
    local sheet = s
    SMODS.Consumable {
        key = 'sheet_' .. sheet.id,         -- => c_balacraft_sheet_gold, ...
        set = 'balacraft_sheet',
        atlas = 'bc_sheet_cards',
        pos = sheet.pos,
        cost = sheet.cost,
        discovered = true,
        loc_txt = {
            name = sheet.name,
            text = {
                'Highlight a card in hand,',
                'then {C:attention}Use{} to apply',
                'its enhancement.',
            },
        },
        -- Queue the resulting enhancement center so its tooltip shows on hover (info_queue
        -- convention: content that applies another center must surface it).
        loc_vars = function(self, info_queue, card)
            local center = G.P_CENTERS and G.P_CENTERS[sheet.m_key]
            if center and info_queue then info_queue[#info_queue + 1] = center end
            return { vars = {} }
        end,

        -- Usable only while selecting a hand, with exactly one valid target highlighted.
        can_use = function(self, card)
            if G.STATE ~= G.STATES.SELECTING_HAND then return false end
            local hl = G.hand and G.hand.highlighted
            if not hl or #hl ~= 1 then return false end
            return PB_UTIL.sheet_apply_valid(hl[1], sheet)
        end,

        use = function(self, card, area, copier)
            local hl = G.hand and G.hand.highlighted
            local target = hl and hl[1]
            if target then PB_UTIL.apply_sheet(target, sheet) end
        end,
    }
end

-- The Glass Sheet is the only sheet crafted at the Crafting Table (the rest are Anvil-forged), so
-- it's the only sheet that appears in the recipe list. Give it a frameless icon (the genuine iso
-- glass-block render, bc_tool_icons cell {4,4}, gen_tool_icons.py) instead of falling back to its
-- full card art.
PB_UTIL.tool_icon_pos = PB_UTIL.tool_icon_pos or {}
PB_UTIL.tool_icon_pos['c_balacraft_sheet_glass'] = { x = 4, y = 4 }
