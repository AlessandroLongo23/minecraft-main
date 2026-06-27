-- Nether Portal voucher: available from the start. Redeeming warps the run into the Nether
-- dimension immediately (a random Nether biome themes the next ante), and counts toward the
-- lifetime total that unlocks the Nether deck (PB_UTIL.bump_progression, utilities/progression.lua).
--
-- Registers the shared voucher atlas (also used by End Portal in Phase 3). Cell order:
-- nether_portal (x=0), end_portal (x=1) -- matches assets/gen_portals.py.
SMODS.Atlas {
    key = 'bc_vouchers',
    path = 'voucher_cards.png',
    px = 71,
    py = 95,
}

SMODS.Voucher {
    key = 'nether_portal',
    atlas = 'bc_vouchers',
    pos = { x = 0, y = 0 },
    loc_txt = {
        name = 'Nether Portal',
        text = {
            'Light the portal:',
            'warp to a random',
            '{C:attention}Nether{} biome now.',
        },
    },
    cost = 10,
    unlocked = true,
    discovered = true,
    redeem = function(self, card)
        if PB_UTIL.enter_dimension then PB_UTIL.enter_dimension('nether') end
        if G.GAME then
            G.GAME.balacraft = G.GAME.balacraft or {}
            G.GAME.balacraft.nether_portal_redeemed = true   -- gates End Portal (Phase 3)
        end
        if PB_UTIL.bump_progression then PB_UTIL.bump_progression('nether_portal_buys') end
    end,
}
