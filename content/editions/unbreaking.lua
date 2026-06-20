-- Unbreaking CARD edition (e_balacraft_unbreaking) -- the card side of the Durability book. FLAT:
-- any Durability book tier gives full protection (tier only matters on tools).
--
-- The protection itself is implemented by one-time wraps in utilities/enchanting.lua:
--   * Blind:debuff_card -> an Unbreaking card is forced un-debuffed,
--   * SMODS.shatters    -> an Unbreaking Glass card never breaks.
-- This center only provides the glint + tooltip. PLACEHOLDER glint: vanilla polychrome (visual only;
-- prefix_config.shader = false keeps it unprefixed). Never rolls (in_shop = false, weight = 0).

SMODS.Edition {
    key = 'unbreaking',
    shader = 'polychrome',
    prefix_config = { shader = false },
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
