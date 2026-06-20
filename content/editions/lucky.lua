-- Lucky CARD editions (e_balacraft_lucky_{1,2,3}) -- the card side of the dual-target Fortune book.
-- Each time the card scores, drops 0..N Emeralds sampled from a per-tier weight table (averages
-- 0.5 / 1.5 / 2.5; see PB_UTIL.lucky_emeralds + ENCHANTS.fortune.card_drops in
-- content/enhancements/registry.lua). One center per book tier.
--
-- PLACEHOLDER glint: vanilla foil shader (visual only -- the boolean flag set is the edition type,
-- NOT card.edition.foil, so the base foil +chips do NOT apply; the only effect is the emerald drop).
-- prefix_config.shader = false keeps 'foil' unprefixed. Never rolls (in_shop = false, weight = 0).

local AVG = { '0.5', '1.5', '2.5' }   -- display only

for tier = 1, 3 do
    local t = tier
    SMODS.Edition {
        key = 'lucky_' .. t,
        shader = 'foil',
        prefix_config = { shader = false },
        in_shop = false,
        weight = 0,
        loc_txt = {
            label = 'Lucky ' .. PB_UTIL.ENCHANT_ROMAN[t],
            name  = 'Lucky ' .. PB_UTIL.ENCHANT_ROMAN[t],
            text = {
                'When scored, drops',
                '{C:attention}Emeralds{} ({C:green}~#1#{} avg)',
            },
        },
        loc_vars = function(self, info_queue, card)
            return { vars = { AVG[t] } }
        end,
        calculate = function(self, card, context)
            if context.main_scoring and context.cardarea == G.play then
                local n = (PB_UTIL.lucky_emeralds and PB_UTIL.lucky_emeralds(t)) or 0
                if n > 0 and PB_UTIL.add_resource then
                    PB_UTIL.add_resource('emerald', n)
                    if card.juice_up then card:juice_up(0.2, 0.3) end
                end
            end
        end,
    }
end
