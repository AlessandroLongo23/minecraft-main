-- "Enchanting Pack": choose 1 of up to 3 Enchanting Books. Only appears in the shop once the
-- Enchanting Table voucher is owned (in_pool). Tier weighting flips toward higher tiers once
-- the Sorcerer's Tome voucher is owned (see PB_UTIL.sample_pack_books).
--
-- PLACEHOLDER ART: reuses a cell on bc_resource_cards.
SMODS.Booster {
    key = 'enchant_pack',
    atlas = 'bc_resource_cards',
    pos = { x = 0, y = 1 },                  -- iron cell (placeholder pack art)
    config = { choose = 1, extra = 3 },      -- pick 1 of 3 books
    cost = 6,
    weight = 0.6,
    loc_txt = {
        name = 'Enchanting Pack',
        -- Big title shown on the open-pack screen (localize('k_booster_group_<key>')). Without
        -- group_name this falls back to a missing key and renders as "ERROR".
        group_name = 'Enchanting Pack',
        text = { 'Choose {C:attention}1{} of up to', '{C:attention}3{} Enchanting Books.' },
    },
    in_pool = function(self, args)
        return G.GAME and G.GAME.used_vouchers
            and G.GAME.used_vouchers['v_balacraft_enchanting_table'] == true
    end,
    create_card = function(self, card, i)
        return PB_UTIL.create_enchant_pack_card(card, i, self.config.extra)
    end,
}
