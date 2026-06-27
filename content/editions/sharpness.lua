-- Sharpness CARD editions (e_balacraft_sharpness_{1,2,3}) -- the card side of the dual-target
-- Sharpness book. Applied to a playing card through the Enchant flow (select a card in hand + a
-- Sharpness book; see utilities/enchanting.lua). One center per book tier so +Mult scales.
--
-- Effect: +Mult when the card scores, DOUBLED vs a boss (mob) blind.
-- Glint: the custom BalaCraft enchant shader (content/editions/enchant_shader.lua) -- a subtle
-- orange rim shimmer scaled by tier. shader = 'enchant' is prefixed to 'balacraft_enchant' (matches
-- the registered SMODS.Shader), so NO prefix_config override is needed. The shader is purely visual
-- -- the +Mult comes from calculate below. Never rolls in the shop (in_shop = false, weight = 0);
-- applied only via the Enchant flow.

local SHARP_MULT = { 10, 15, 20 }   -- +Mult per book tier (card side); doubled vs boss

for tier = 1, 3 do
    local base = SHARP_MULT[tier]
    local boss = base * 2
    SMODS.Edition {
        key = 'sharpness_' .. tier,
        shader = 'enchant',
        in_shop = false,
        weight = 0,
        config = { mult = base },
        loc_txt = {
            label = 'Sharpness ' .. PB_UTIL.ENCHANT_ROMAN[tier],
            name  = 'Sharpness ' .. PB_UTIL.ENCHANT_ROMAN[tier],
            text = {
                '{C:mult}+#1#{} Mult when this card',
                'is scored ({C:mult}+#2#{} vs a {C:attention}Boss{})',
            },
        },
        loc_vars = function(self, info_queue, card)
            return { vars = { base, boss } }
        end,
        calculate = function(self, card, context)
            -- Same trigger the vanilla foil/holo editions use for a scored playing card.
            if context.pre_joker or (context.main_scoring and context.cardarea == G.play) then
                local is_boss = G.GAME and G.GAME.blind and G.GAME.blind.boss
                return { mult = is_boss and boss or base }
            end
        end,
    }
end
