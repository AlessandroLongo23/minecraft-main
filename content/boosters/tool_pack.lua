-- "Toolbox" booster (Normal): show 3 tools, pick 1. A loot-chest for crafted tools -- low-tier
-- tools are common, higher tiers unlock with the ante, and (when the enchant system is on) each
-- tool has a small ante-scaled chance to arrive pre-enchanted. The Torch can also appear (never
-- enchanted). Pool / enchant-roll logic lives in utilities/tool_packs.lua.
-- PLACEHOLDER ART: reuses the wooden-sword cell on the bc_tools card sheet.
SMODS.Booster {
    key = 'tool_pack',
    atlas = 'bc_tools',
    pos = { x = 0, y = 0 },                  -- wooden sword cell (placeholder pack art)
    config = { choose = 1, extra = 3 },
    cost = 6,
    weight = 0.5,
    loc_txt = {
        name = 'Toolbox',
        group_name = 'Toolbox',              -- open-pack title; without it the screen shows "ERROR"
        text = { 'Choose {C:attention}1{} of up to', '{C:attention}3{} Minecraft tools.' },
    },
    create_card = function(self, card, i)
        return PB_UTIL.create_tool_pack_card(card, i, self.config.extra)
    end,
}
