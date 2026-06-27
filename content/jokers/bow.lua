-- Bow (Wave 1, Archery). Crafted from 3 String + 3 Sticks (content/resources/recipes.lua).
-- A precision scaling engine: rewards playing exactly one hand per round ("a clean shot").
-- PLACEHOLDER ART: reuses menace.png (same convention as crackedknuckles/itshome). Real Bow
-- card art is a follow-up — download the `bow` MC item texture and generate a 71x95 face.
SMODS.Atlas { key = 'bc_bow', path = 'menace.png', px = 71, py = 95 }

-- Authentic MC `bow` icon for the crafting recipe LIST / output preview (bc_tool_icons extras row,
-- assets/gen_tool_icons.py cell {x=1,y=3}). make_output_sprite checks tool_icon_pos before falling
-- back to the (placeholder) card art, so the recipe square shows real pixel art. Loads after
-- tool_consumabletype.lua (jokers block, main.lua) -> the `or {}` guard is belt-and-suspenders.
PB_UTIL.tool_icon_pos = PB_UTIL.tool_icon_pos or {}
PB_UTIL.tool_icon_pos['j_balacraft_bow'] = { x = 1, y = 3 }

SMODS.Joker {
    key = 'bow',
    loc_txt = {
        name = 'Bow',
        text = {
            'At end of round, gains {C:mult}X0.25{} Mult',
            'if you played {C:attention}exactly one{} hand.',
            '{C:inactive}(Currently {C:mult}X#1#{C:inactive} Mult)',
        },
    },

    unlocked = true,
    discovered = true,

    blueprint_compat = true,
    brainstorm_compat = true,
    eternal_compat = true,
    perishable_compat = true,

    rarity = 2,
    atlas = 'bc_bow',
    pos = { x = 0, y = 0 },
    cost = 6,

    config = { extra = { x_mult = 1 } },

    loc_vars = function(self, info_queue, center)
        return { vars = { center.ability.extra.x_mult } }
    end,

    calculate = function(self, card, context)
        -- Accumulate only on a clean, single-hand round. Guarded against Blueprint copies so a
        -- copy applies the X-Mult but doesn't double-charge (same guard Menace uses).
        if context.end_of_round and not context.other_card and not context.blueprint then
            local hp = G.GAME.current_round and G.GAME.current_round.hands_played
            if hp == 1 then
                card.ability.extra.x_mult = card.ability.extra.x_mult + 0.25
                return { message = 'Bullseye! +X0.25', colour = G.C.MULT, card = card }
            end
        end

        if context.joker_main and card.ability.extra.x_mult > 1 then
            return { x_mult = card.ability.extra.x_mult }
        end
    end,
}
