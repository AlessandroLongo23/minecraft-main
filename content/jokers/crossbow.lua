-- Crossbow (Wave 1, Archery). Crafted from 3 String + 2 Sticks + 1 Iron, AND only craftable once
-- you own a Bow this run (the prerequisite gate lives in utilities/crafting.lua can_craft). A
-- "loaded shot" rhythm engine: charges on one hand, fires X3 on the next. blueprint_compat=false
-- (the loaded toggle would desync under a copy).
-- PLACEHOLDER ART: reuses menace.png. Real art follow-up: the `crossbow` MC item texture.
SMODS.Atlas { key = 'bc_crossbow', path = 'menace.png', px = 71, py = 95 }

-- Authentic MC `crossbow` recipe-list icon (bc_tool_icons extras row, cell {x=3,y=3}).
PB_UTIL.tool_icon_pos = PB_UTIL.tool_icon_pos or {}
PB_UTIL.tool_icon_pos['j_balacraft_crossbow'] = { x = 3, y = 3 }

SMODS.Joker {
    key = 'crossbow',
    loc_txt = {
        name = 'Crossbow',
        text = {
            'Every {C:attention}other{} hand scored fires',
            'for {C:mult}X#1#{} Mult; the off hands {C:blue}reload{}.',
        },
    },

    unlocked = true,
    discovered = true,

    blueprint_compat = false,
    brainstorm_compat = false,
    eternal_compat = true,
    perishable_compat = true,

    rarity = 3,
    atlas = 'bc_crossbow',
    pos = { x = 0, y = 0 },
    cost = 8,

    config = { extra = { loaded = false, x_mult = 3 } },

    loc_vars = function(self, info_queue, center)
        return { vars = { center.ability.extra.x_mult } }
    end,

    calculate = function(self, card, context)
        if context.joker_main then
            if card.ability.extra.loaded then
                card.ability.extra.loaded = false
                return { x_mult = card.ability.extra.x_mult, message = 'Fire!' }
            else
                card.ability.extra.loaded = true
                return { message = 'Reloading...', colour = G.C.BLUE }
            end
        end

        -- Start each round fresh (charging), so it can't be banked-then-dumped across rounds.
        if context.end_of_round and not context.other_card then
            card.ability.extra.loaded = false
        end
    end,
}
