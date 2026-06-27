-- Eye of Ender. Crafted from 1 Ender Pearl + 1 Blaze Powder (content/resources/recipes.lua).
-- A SINGLE-USE consumable (no keep_on_use): using one ARMS the next biome selection to show the
-- Eye-of-Ender trail marker. Use one each ante for three CONSECUTIVE antes, always picking the
-- marked option, to reach The End: (1) one of three random biomes, (2) the Stronghold biome,
-- (3) The End. Picking an unmarked option, or skipping an ante, resets the trail. The trail logic
-- lives in PB_UTIL.use_ender_eye + the biome-select code (utilities/biomes.lua, biomes_ui.lua).
-- Rides the craft-only 'balacraft_tool' consumable type.

-- 71x95 card face from the authentic MC ender_eye item texture (gen_item_consumable_cards.py).
SMODS.Atlas { key = 'bc_ender_eye', path = 'ender_eye.png', px = 71, py = 95 }

SMODS.Consumable {
    key = 'ender_eye',
    set = 'balacraft_tool',
    atlas = 'bc_ender_eye',
    pos = { x = 0, y = 0 },
    cost = 5,
    discovered = true,

    loc_txt = {
        name = 'Eye of Ender',
        text = {
            'Use during a round to read the',
            'Eye-of-Ender {C:attention}trail{}. At the next',
            'biome selection one option is',
            '{C:attention}marked{} -- pick it. Do this for {C:attention}3{}',
            'antes in a row to reach {C:attention}The End{}.',
            '{C:inactive}(consumed on use)',
        },
    },

    can_use = function(self, card)
        return PB_UTIL.hand_consumable_state()
    end,

    use = function(self, card, area, copier)
        if PB_UTIL.use_ender_eye then PB_UTIL.use_ender_eye() end
    end,
}
