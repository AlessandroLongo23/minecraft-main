-- Enchanting Table voucher (base of the enchanting pair). Redeeming it:
--   * unlocks Enchanting Books + the Enchanting Pack in the shop (books' in_pool reads
--     used_vouchers; the book consumable-type's shop rate is switched on here), and
--   * grants +1 consumable slot (mirrors the base-game Crystal Ball voucher).
--
-- Only offered when the enchanting system is enabled.
--
-- Registers the shared enchanting-pair voucher atlas (also used by Sorcerer's Tome, which loads
-- after this file). Art (assets/gen_enchant_vouchers.py): a side-view enchanting room built from
-- authentic MC textures -- the table flanked by a COUPLE of bookshelves (vs the Tome's full library).
-- Cell order MUST match the pos here: enchanting_table (x=0), sorcerers_tome (x=1).
SMODS.Atlas {
    key = 'bc_enchant_vouchers',
    path = 'enchant_voucher_cards.png',
    px = 71,
    py = 95,
}

SMODS.Voucher {
    key = 'enchanting_table',
    atlas = 'bc_enchant_vouchers',
    pos = { x = 0, y = 0 },
    loc_txt = {
        name = 'Enchanting Table',
        text = {
            '{C:attention}Enchanting Books{} appear',
            'in the shop. Gain {C:attention}+1{}',
            'consumable slot.',
        },
    },
    cost = 10,
    unlocked = true,
    discovered = true,
    in_pool = function(self, args)
        return PB_UTIL.config and PB_UTIL.config.enhancements_enabled == true
    end,
    redeem = function(self, card)
        -- Turn on book shop appearance (SMODS stores each ConsumableType's rate at
        -- G.GAME.<key:lower>_rate; 'balacraft_enchant' -> balacraft_enchant_rate). The shop
        -- type-roll weight is total = joker(20)+tarot(4)+planet(4)+...; rate 0.5 -> ~1.6% of
        -- shop slots, a rare find (between rare-joker ~3.3% and negative-joker ~0.2%).
        if G.GAME then G.GAME.balacraft_enchant_rate = 0.5 end
        -- +1 consumable slot (Crystal Ball mirror; persists with the run save).
        G.E_MANAGER:add_event(Event({ func = function()
            if G.consumeables and G.consumeables.config then
                G.consumeables.config.card_limit = G.consumeables.config.card_limit + 1
            end
            return true
        end }))
    end,
}
