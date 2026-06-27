-- Unbreaking CARD edition (e_balacraft_unbreaking) -- the card side of the Durability book. FLAT:
-- any Durability book tier gives full protection (tier only matters on tools).
--
-- The protection itself is implemented by one-time wraps in utilities/enchanting.lua:
--   * Blind:debuff_card -> an Unbreaking card is forced un-debuffed,
--   * SMODS.shatters    -> an Unbreaking Glass card never breaks.
-- This center only provides the glint + tooltip. Glint: the custom BalaCraft enchant shader
-- (content/editions/enchant_shader.lua) -- a subtle cyan rim shimmer. shader = 'enchant' is
-- prefixed to 'balacraft_enchant'. Never rolls (in_shop = false, weight = 0).

SMODS.Edition {
    key = 'unbreaking',
    shader = 'enchant',
    in_shop = false,
    weight = 0,
    loc_txt = {
        label = 'Unbreaking',
        name  = 'Unbreaking',
        text = {
            'Cannot be {C:attention}debuffed{}',
            'by {C:attention}Boss Blinds{};',
            '{C:green}Glass{} cards won\'t break',
        },
    },
}
