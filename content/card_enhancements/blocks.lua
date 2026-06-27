-- SMODS.Enhancement centers for BalaCraft "block-cards".
-- Tarot-applied: Hay Bale, Lapis. Ore Blocks: one per ore-block resource
-- (PB_UTIL.is_oreblock_resource), spawned naturally and pickaxe-mined (Phase B).

-- Atlas: bc_ore_blocks (71x95) -- each cell is the genuine MC block texture tiled to fill the card,
-- clipped to the rounded card mask (built by assets/gen_ore_blocks.py). Drawn UNDER the card's
-- rank/suit/pips. The ore blocks use their resource registry `pos`; the 2 tarot-applied block cards
-- below use dedicated free cells (must match the CELLS table in gen_ore_blocks.py).

-- Hay Bale — restores 1 hunger pip when this card SCORES.
SMODS.Enhancement {
    key = 'hay_bale',
    atlas = 'bc_ore_blocks',
    pos = { x = 2, y = 7 },                 -- hay bale block cell
    config = { extra = { hunger = 1 } },
    loc_txt = {
        name = 'Hay Bale Card',
        text = {
            'Restores {C:attention}#1#{} hunger',
            'when this card scores.',
        },
    },
    loc_vars = function(self, info_queue, card)
        local h = (card and card.ability and card.ability.extra and card.ability.extra.hunger) or 1
        return { vars = { h } }
    end,
    calculate = function(self, card, context)
        if context.cardarea == G.play and context.main_scoring then
            if PB_UTIL.add_hunger then PB_UTIL.add_hunger(card.ability.extra.hunger) end
            return { message = '+' .. card.ability.extra.hunger .. ' Hunger', colour = G.C.GREEN, card = card }
        end
    end,
}

-- Lapis — grants XP every time this card is PLAYED. always_scores so it fires even when the
-- card isn't part of the poker hand (the design is "each time played").
-- XP is a FRACTION of the current level's cost (not a flat number), so it stays meaningful at
-- any level on the super-exponential XP scale (a flat "+3 XP" was a rounding error past level 30).
local LAPIS_LEVEL_FRAC = 0.25   -- ~quarter of a level per play. Tunable.
-- XP this play would grant at the player's current level.
local function lapis_xp_amount()
    local level = (PB_UTIL.get_level and PB_UTIL.get_level()) or 0
    local need  = (PB_UTIL.xp_to_next and PB_UTIL.xp_to_next(level)) or 4
    return math.max(1, math.floor(LAPIS_LEVEL_FRAC * need))
end
SMODS.Enhancement {
    key = 'lapis',
    atlas = 'bc_ore_blocks',
    pos = { x = 1, y = 1 },                 -- lapis block cell
    always_scores = true,
    config = { extra = { level_frac = LAPIS_LEVEL_FRAC } },
    loc_txt = {
        name = 'Lapis Card',
        text = {
            'Gain {C:blue}XP{} ({C:attention}1/4 level{})',
            'each time this card is played.',
        },
    },
    loc_vars = function(self, info_queue, card)
        return { vars = {} }
    end,
    calculate = function(self, card, context)
        if context.cardarea == G.play and context.main_scoring then
            local amt = lapis_xp_amount()
            if PB_UTIL.add_xp then PB_UTIL.add_xp(amt) end
            return { message = '+' .. amt .. ' XP', colour = G.C.BLUE, card = card }
        end
    end,
}

-- Ore Blocks: one enhancement per GATHERED ore resource. These are art-only markers (they keep
-- the card's rank/suit and add no scoring effect). They spawn naturally
-- (utilities/card_enhancements.lua). Mining now requires a TOOL: highlight ore-block cards and Use a
-- Pickaxe (gated by its material's mining level, PB_UTIL.can_mine) to extract them. WOOD is the
-- exception -- it can be chopped with an Axe OR by playing a single wood card by hand (+1). Keyed
-- m_balacraft_block_<oreid>; art = the matching tiled-block cell on bc_ore_blocks (pos from the
-- resource registry, mirrored in gen_ore_blocks.py).
for _, r in ipairs(PB_UTIL.RESOURCES) do
    if PB_UTIL.is_oreblock_resource(r) then   -- gathered ores + opt-ins (Obsidian); excludes Sand
        local res = r
        local body
        if res.id == 'wood' then
            body = {
                'Use an {C:attention}Axe{} on this card,',
                'or play it alone, to gather {C:attention}Wood{}.',
            }
        elseif res.id == 'obsidian' then
            body = {
                'Use a {C:attention}Diamond Pickaxe{} on',
                'this card to mine {C:attention}Obsidian{}.',
            }
        else
            body = {
                'Use a {C:attention}Pickaxe{} on this',
                'card to mine {C:attention}' .. res.name .. '{}.',
            }
        end
        SMODS.Enhancement {
            key = 'block_' .. res.id,        -- => m_balacraft_block_iron, ...
            atlas = 'bc_ore_blocks',
            pos = res.pos,                   -- the ore's own card cell
            config = { extra = { ore = res.id } },
            loc_txt = {
                name = res.name .. ' Ore Card',
                text = body,
            },
        }
    end
end
