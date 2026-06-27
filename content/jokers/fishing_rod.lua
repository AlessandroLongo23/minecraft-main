-- Fishing Rod (Wave 1, Archery). Crafted from 3 Sticks + 2 String. An economy/loot engine:
-- each cash-out "reels in" a random reward. blueprint_compat=false (RNG + resource/economy mutation).
-- PLACEHOLDER ART: reuses menace.png. Real art follow-up: the `fishing_rod` MC item texture.
SMODS.Atlas { key = 'bc_fishing_rod', path = 'menace.png', px = 71, py = 95 }

-- Authentic MC `fishing_rod` recipe-list icon (bc_tool_icons extras row, cell {x=2,y=3}).
PB_UTIL.tool_icon_pos = PB_UTIL.tool_icon_pos or {}
PB_UTIL.tool_icon_pos['j_balacraft_fishing_rod'] = { x = 2, y = 3 }

SMODS.Joker {
    key = 'fishing_rod',
    loc_txt = {
        name = 'Fishing Rod',
        text = {
            'At end of round, {C:attention}reel in{}:',
            '{C:green}55%{} an ore, {C:money}30%{} {C:money}$4{},',
            '{C:green}15%{} a {C:attention}mob drop{}.',
        },
    },

    unlocked = true,
    discovered = true,

    blueprint_compat = false,
    brainstorm_compat = false,
    eternal_compat = true,
    perishable_compat = true,

    rarity = 2,
    atlas = 'bc_fishing_rod',
    pos = { x = 0, y = 0 },
    cost = 6,

    calculate = function(self, card, context)
        if context.end_of_round and not context.other_card and not context.blueprint then
            local ante = (G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or 1
            local max_tier = PB_UTIL.max_ore_tier(ante)
            local roll = pseudorandom('bc_fish')

            if roll < 0.55 then
                local id = PB_UTIL.random_ore_of_tier(max_tier, 'bc_fish_ore')
                PB_UTIL.add_resource(id, 1)
                local nm = (PB_UTIL.RESOURCE_BY_ID[id] and PB_UTIL.RESOURCE_BY_ID[id].name) or 'Ore'
                return { message = 'Reeled ' .. nm .. '!', colour = G.C.FILTER, card = card }
            elseif roll < 0.85 then
                ease_dollars(4)
                return { message = '+$4', colour = G.C.MONEY, card = card }
            else
                local id = PB_UTIL.random_mob_drop(max_tier, 'bc_fish_mob')
                if id then
                    PB_UTIL.add_resource(id, 1)
                    local nm = (PB_UTIL.RESOURCE_BY_ID[id] and PB_UTIL.RESOURCE_BY_ID[id].name) or 'Loot'
                    return { message = 'Reeled ' .. nm .. '!', colour = G.C.FILTER, card = card }
                end
                ease_dollars(4)   -- no mob drop exists yet at this tier: fall back to money
                return { message = '+$4', colour = G.C.MONEY, card = card }
            end
        end
    end,
}
