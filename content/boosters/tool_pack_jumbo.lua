-- "Jumbo Toolbox" booster: show 5 tools, pick 1. See content/boosters/tool_pack.lua for the model.
-- PLACEHOLDER ART: reuses the wooden-pickaxe cell on the bc_tools card sheet.
SMODS.Booster {
    key = 'tool_pack_jumbo',
    atlas = 'bc_tools',
    pos = { x = 0, y = 6 },                  -- wooden pickaxe cell (placeholder pack art)
    config = { choose = 1, extra = 5 },
    cost = 8,
    weight = 0.35,
    loc_txt = {
        name = 'Jumbo Toolbox',
        group_name = 'Jumbo Toolbox',
        text = { 'Choose {C:attention}1{} of up to', '{C:attention}5{} Minecraft tools.' },
    },
    create_card = function(self, card, i)
        return PB_UTIL.create_tool_pack_card(card, i, self.config.extra)
    end,
}
