-- Enchanting Table voucher (base of the enchanting pair). Redeeming it:
--   * unlocks Enchanting Books + the Enchanting Pack in the shop (books' in_pool reads
--     used_vouchers; the book consumable-type's shop rate is switched on here), and
--   * grants +1 consumable slot (mirrors the base-game Crystal Ball voucher).
--
-- Only offered when the enchanting system is enabled. PLACEHOLDER ART: reuses a bc_vouchers
-- cell (the atlas currently holds only the two portal cells; dedicated art is a follow-up).
SMODS.Voucher {
    key = 'enchanting_table',
    atlas = 'bc_vouchers',
    pos = { x = 0, y = 0 },                 -- PLACEHOLDER (shares the Nether Portal cell)
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
