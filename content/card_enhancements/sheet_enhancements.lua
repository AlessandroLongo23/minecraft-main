-- Sheet-applied card enhancements: the FOUR genuinely-new BalaCraft effects (Diamond / Emerald /
-- Redstone / Coal). Applied to a playing card by the matching Sheet consumable (content/sheets/).
-- The Gold/Iron/Glass sheets reuse the vanilla m_gold / m_steel / m_glass enhancements; the Lapis
-- sheet reuses the existing m_balacraft_lapis (XP per play, content/card_enhancements/blocks.lua) --
-- so only these four need new centers. Keyed m_balacraft_<id>.
--
-- Shape copied from blocks.lua (the Lapis card): key/atlas/pos/config.extra/loc_txt/loc_vars/
-- calculate. Art: bc_sheet_enh_blocks (71x95), built by assets/gen_sheet_enh_blocks.py (tile the MC
-- block face, clip to the rounded card mask -- same style as bc_ore_blocks). A dedicated atlas keeps
-- the near-full bc_ore_blocks sheet untouched. Loaded in main.lua's sheets block (after resources/xp,
-- since Emerald grants $ and the effects read card.ability.extra).

PB_UTIL.sheet_enh_atlas = SMODS.Atlas {
    key = 'bc_sheet_enh_blocks', path = 'sheet_enh_blocks.png', px = 71, py = 95,
}

-- Diamond — premium while-held xMult (above Steel x1.5 / Obsidian x1.25; justified by being
-- craft-gated behind diamonds). Mirrors the Obsidian held-mult pattern.
SMODS.Enhancement {
    key = 'diamond',
    atlas = 'bc_sheet_enh_blocks',
    pos = { x = 0, y = 0 },
    config = { extra = { x_mult = 2 } },
    loc_txt = {
        name = 'Diamond Card',
        text = {
            '{X:mult,C:white}X#1#{} Mult while this',
            'card is {C:attention}held in hand{}.',
        },
    },
    loc_vars = function(self, info_queue, card)
        local x = (card and card.ability and card.ability.extra and card.ability.extra.x_mult) or 2
        return { vars = { x } }
    end,
    calculate = function(self, card, context)
        if context.cardarea == G.hand and context.main_scoring then
            return { x_mult = card.ability.extra.x_mult, card = card }
        end
    end,
}

-- Emerald — earn money when it SCORES (emerald = the trade currency). Uses the standard on-score
-- hook (context.cardarea == G.play and context.main_scoring) but pays dollars.
SMODS.Enhancement {
    key = 'emerald',
    atlas = 'bc_sheet_enh_blocks',
    pos = { x = 1, y = 0 },
    config = { extra = { dollars = 4 } },
    loc_txt = {
        name = 'Emerald Card',
        text = {
            'Earn {C:money}$#1#{} when',
            'this card scores.',
        },
    },
    loc_vars = function(self, info_queue, card)
        local d = (card and card.ability and card.ability.extra and card.ability.extra.dollars) or 4
        return { vars = { d } }
    end,
    calculate = function(self, card, context)
        if context.cardarea == G.play and context.main_scoring then
            return { dollars = card.ability.extra.dollars, card = card }
        end
    end,
}

-- Redstone — retrigger this card when it scores (redstone = a repeating signal). Same idiom as the
-- vanilla Red seal (context.repetition -> repetitions).
SMODS.Enhancement {
    key = 'redstone',
    atlas = 'bc_sheet_enh_blocks',
    pos = { x = 0, y = 1 },
    config = { extra = { retriggers = 1 } },
    loc_txt = {
        name = 'Redstone Card',
        text = {
            '{C:attention}Retrigger{} this',
            'card {C:attention}#1#{} extra time.',
        },
    },
    loc_vars = function(self, info_queue, card)
        local n = (card and card.ability and card.ability.extra and card.ability.extra.retriggers) or 1
        return { vars = { n } }
    end,
    calculate = function(self, card, context)
        if context.repetition and context.cardarea == G.play then
            return {
                repetitions = card.ability.extra.retriggers,
                message = localize('k_again_ex'),
                card = card,
            }
        end
    end,
}

-- Coal — extra Chips when it SCORES (coal = fuel/energy). Bonus-card style on-score chips.
SMODS.Enhancement {
    key = 'coal',
    atlas = 'bc_sheet_enh_blocks',
    pos = { x = 1, y = 1 },
    config = { extra = { chips = 40 } },
    loc_txt = {
        name = 'Coal Card',
        text = {
            '{C:chips}+#1#{} Chips when',
            'this card scores.',
        },
    },
    loc_vars = function(self, info_queue, card)
        local c = (card and card.ability and card.ability.extra and card.ability.extra.chips) or 40
        return { vars = { c } }
    end,
    calculate = function(self, card, context)
        if context.cardarea == G.play and context.main_scoring then
            return { chips = card.ability.extra.chips, card = card }
        end
    end,
}
