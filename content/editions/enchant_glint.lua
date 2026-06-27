-- Inert carrier edition (e_balacraft_enchant_glint) -- the ONLY purpose is to give an enchanted
-- TOOL a shader pass. Tools aren't editions, so to route them through the enchant glint shader we
-- attach this edition once the tool gains its first enchant (see PB_UTIL.apply_enchant in
-- utilities/enchanting.lua). It has NO config / NO calculate, so it changes nothing about gameplay;
-- the actual tiers come from card.ability.extra.enchants, read live by the shader's send_vars.
--
-- shader = 'enchant' -> prefixed to 'balacraft_enchant' (matches content/editions/enchant_shader.lua).
-- Never rolls (in_shop = false, weight = 0); only ever applied via the Enchant flow.

SMODS.Edition {
    key = 'enchant_glint',
    shader = 'enchant',
    in_shop = false,
    weight = 0,
    loc_txt = {
        label = 'Enchanted',
        name  = 'Enchanted',
        text  = { 'Enchanted' },
    },
}
