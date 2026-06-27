-- Torch: a craft-only consumable that peeks the shop. Usable ONLY in the shop, where it
-- opens a one-shot preview modal (next two rerolls + every booster pack's contents) and is
-- then destroyed on use -- so it can't be reopened. Peek/modal logic lives in utilities/torch.lua.
-- Rides the 'balacraft_tool' consumable type (craft-only, collection-visible).

-- Dedicated single-cell card face (assets/gen_torch_card.py): the shared tool-card chrome
-- but with the material plate and durability bar smoothed off, and the authentic Minecraft
-- torch sprite centred. 71x95 like the rest of the tool/consumable cards.
SMODS.Atlas { key = 'bc_torch', path = 'torch.png', px = 71, py = 95 }

-- Small 34x34 badge icon for the crafting recipe list / output preview (assets/gen_tool_icons.py
-- adds the torch as an extra 4th row in the shared bc_tool_icons sheet, cell {x=0, y=3}). Without
-- this, make_output_sprite (crafting_ui.lua) falls back to the 71x95 card art for the torch.
-- tool_consumabletype.lua (loads first) created PB_UTIL.tool_icon_pos and bc_tool_icons; we append.
PB_UTIL.tool_icon_pos = PB_UTIL.tool_icon_pos or {}
PB_UTIL.tool_icon_pos['c_balacraft_torch'] = { x = 0, y = 3 }

SMODS.Consumable {
    key = 'torch',
    set = 'balacraft_tool',
    atlas = 'bc_torch',
    pos = { x = 0, y = 0 },
    cost = 3,
    discovered = true,
    loc_txt = {
        name = 'Torch',
        text = {
            'Peek the next two shop',
            '{C:attention}rerolls{} and what is inside',
            'every {C:attention}booster pack{}.',
            '{C:inactive}(use in the shop)',
        },
    },
    can_use = function(self, card)
        return G.STATE == G.STATES.SHOP
    end,
    use = function(self, card, area, copier)
        -- Do NOT open the overlay synchronously here: this runs in the middle of use_card's
        -- consumable state machine (STATE=PLAY_TAROT, locks.use=true, shop slid off-screen),
        -- which it only tears down via a deferred event chain. Opening mid-flow leaves that
        -- machine half-built and corrupts the NEXT consumable interaction (it gets used on a
        -- single click). schedule_torch_preview() waits for a clean shop, then opens. The peek
        -- there is still exact: the teardown touches no shop/pack RNG keys, and used_jokers is
        -- restored around the peek (see utilities/torch.lua).
        PB_UTIL.schedule_torch_preview()
    end,
}
