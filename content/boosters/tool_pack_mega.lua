-- "Mega Toolbox" booster: show 5 tools, pick 2. See content/boosters/tool_pack.lua for the model.
-- PLACEHOLDER ART: reuses the wooden-shovel cell on the bc_tools card sheet.
SMODS.Booster {
    key = 'tool_pack_mega',
    atlas = 'bc_tools',
    pos = { x = 0, y = 12 },                 -- wooden shovel cell (placeholder pack art)
    config = { choose = 2, extra = 5 },
    cost = 10,
    weight = 0.2,
    loc_txt = {
        name = 'Mega Toolbox',
        group_name = 'Mega Toolbox',
        text = { 'Choose {C:attention}2{} of up to', '{C:attention}5{} Minecraft tools.' },
    },
    create_card = function(self, card, i)
        return PB_UTIL.create_tool_pack_card(card, i, self.config.extra)
    end,
}
