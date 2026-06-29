-- Flint and Steel (the Nether key). Crafted from 1 Iron + 1 Flint (content/resources/recipes.lua).
-- A SINGLE-USE consumable (no keep_on_use): used while in a Ruined Portal blind and holding >= 1
-- Obsidian to LIGHT the portal -- this spends 1 Obsidian, instantly beats the blind, warps the run
-- to a random Nether biome, and rerolls this ante's boss to a Nether boss. All of that lives in
-- PB_UTIL.light_nether_portal (utilities/structures.lua); this file is just the card + the gate.
-- Rides the craft-only 'balacraft_tool' consumable type.

-- 71x95 card face from the authentic MC flint_and_steel item texture (gen_item_consumable_cards.py).
SMODS.Atlas { key = 'bc_flint_and_steel', path = 'flint_and_steel.png', px = 71, py = 95 }

-- Recipe-list icon: the frameless Flint and Steel item icon (bc_tool_icons cell {3,4},
-- gen_tool_icons.py) so the crafting list shows an icon instead of the full card.
PB_UTIL.tool_icon_pos = PB_UTIL.tool_icon_pos or {}
PB_UTIL.tool_icon_pos['c_balacraft_flint_and_steel'] = { x = 3, y = 4 }

SMODS.Consumable {
    key = 'flint_and_steel',
    set = 'balacraft_tool',
    atlas = 'bc_flint_and_steel',
    pos = { x = 0, y = 0 },
    cost = 4,
    discovered = true,

    loc_txt = {
        name = 'Flint and Steel',
        text = {
            'Use while in a {C:attention}Ruined Portal{}',
            'blind with {C:attention}1 Obsidian{}: light it to',
            'instantly beat the blind and warp',
            'to a random {C:red}Nether{} biome.',
            '{C:inactive}(consumed on use)',
        },
    },

    -- Only lightable inside a Ruined Portal blind (active_structure set by utilities/structures.lua)
    -- and only with Obsidian in stock. hand_consumable_state keeps it usable through pack states too.
    can_use = function(self, card)
        return PB_UTIL.hand_consumable_state()
            and G.GAME and G.GAME.balacraft
            and G.GAME.balacraft.active_structure == 'ruined_portal'
            and (PB_UTIL.get_resource_count('obsidian') or 0) >= 1
    end,

    use = function(self, card, area, copier)
        if PB_UTIL.add_resource then PB_UTIL.add_resource('obsidian', -1) end
        if PB_UTIL.light_nether_portal then PB_UTIL.light_nether_portal() end
    end,
}
