-- End Portal voucher: the second half of the sequential pair. `requires` the Nether Portal,
-- so it only appears in the shop once the Nether Portal has been redeemed this run. Redeeming
-- warps the run into the End dimension (a random End biome themes the next ante) and counts
-- toward the lifetime total that unlocks the End deck.
--
-- Uses the shared 'bc_vouchers' atlas registered in content/vouchers/nether_portal.lua
-- (cell x=1). nether_portal must load first (it does -- see ENABLED_VOUCHERS order).
SMODS.Voucher {
    key = 'end_portal',
    atlas = 'bc_vouchers',
    pos = { x = 1, y = 0 },
    loc_txt = {
        name = 'End Portal',
        text = {
            'Open the gateway:',
            'warp to a random',
            '{C:attention}End{} biome now.',
        },
    },
    cost = 12,
    requires = { 'v_balacraft_nether_portal' },   -- sequential: needs the Nether Portal first
    discovered = true,
    redeem = function(self, card)
        if PB_UTIL.enter_dimension then PB_UTIL.enter_dimension('end') end
        if PB_UTIL.bump_progression then PB_UTIL.bump_progression('end_portal_buys') end
    end,
}
