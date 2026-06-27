-- Sorcerer's Tome voucher (upgrade of the enchanting pair; requires the Enchanting Table).
-- Redeeming it:
--   * raises how often Enchanting Books appear in the shop and unlocks Tier III books, and
--   * biases the Enchanting Pack toward higher tiers (PB_UTIL.sample_pack_books reads this
--     voucher), and
--   * grants another +1 consumable slot.
--
-- PLACEHOLDER ART: reuses a bc_vouchers cell.
SMODS.Voucher {
    key = 'sorcerers_tome',
    atlas = 'bc_vouchers',
    pos = { x = 1, y = 0 },                 -- PLACEHOLDER (shares the End Portal cell)
    loc_txt = {
        name = "Sorcerer's Tome",
        text = {
            'Books appear more often and',
            'favour {C:attention}higher tiers{}.',
            'Gain {C:attention}+1{} consumable slot.',
        },
    },
    cost = 12,
    unlocked = true,
    discovered = true,
    requires = { 'v_balacraft_enchanting_table' },   -- sequential: needs the Enchanting Table first
    in_pool = function(self, args)
        return PB_UTIL.config and PB_UTIL.config.enhancements_enabled == true
    end,
    redeem = function(self, card)
        -- Boost book shop appearance (the in_pool tier-3 gate + the pack sampler read
        -- used_vouchers['v_balacraft_sorcerers_tome'] for the higher-tier bias). Doubles the
        -- Enchanting Table's rate to ~3.2% of shop slots (~rare-joker frequency) -- "more often"
        -- but still uncommon.
        if G.GAME then G.GAME.balacraft_enchant_rate = 1.0 end
        G.E_MANAGER:add_event(Event({ func = function()
            if G.consumeables and G.consumeables.config then
                G.consumeables.config.card_limit = G.consumeables.config.card_limit + 1
            end
            return true
        end }))
    end,
}
