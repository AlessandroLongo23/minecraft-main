-- BalaCraft skip-blind Tags. Each rewards a different subsystem; all resolve on the
-- 'new_blind_choice' context (the blind-select screen after a skip), the same hook vanilla
-- pack tags use. Placeholder art = the vanilla 'tags' atlas cell {0,0}. Each tag's in_pool
-- gates it on the subsystem it rewards, so a disabled system never offers a dead tag.

-- Create + open a booster pack centered in the play area (vanilla pack-tag pattern). Inert
-- if the pack center isn't registered (e.g. its subsystem is off).
local function grant_pack(pack_key)
    local center = G.P_CENTERS[pack_key]
    if not center then return end
    local card = Card(
        G.play.T.x + G.play.T.w / 2 - G.CARD_W * 1.27 / 2,
        G.play.T.y + G.play.T.h / 2 - G.CARD_H * 1.27 / 2,
        G.CARD_W * 1.27, G.CARD_H * 1.27,
        G.P_CARDS.empty, center,
        { bypass_discovery_center = true, bypass_discovery_ui = true }
    )
    card.cost = 0
    card.from_tag = true
    G.FUNCS.use_card({ config = { ref_table = card } })
    card:start_materialize()
end

local function cfg(flag)
    return (PB_UTIL.config and PB_UTIL.config[flag]) and true or false
end

-- Loot Tag -> free Loot Chest (Resource Pack).
SMODS.Tag {
    key = 'balacraft_loot', atlas = 'tags', pos = { x = 0, y = 0 }, discovered = true, prefix_config = { atlas = false },
    loc_txt = { name = 'Loot Tag', text = { 'Gives a free', '{C:attention}Loot Chest{} pack' } },
    -- Show the granted pack's tooltip, like vanilla pack tags (Charm Tag -> Arcana pack).
    loc_vars = function(self, info_queue, card)
        local c = G.P_CENTERS['p_balacraft_resource_pack']
        if c then info_queue[#info_queue + 1] = c end
    end,
    in_pool = function(self, args) return cfg('resources_enabled') end,
    apply = function(self, tag, context)
        if context.type == 'new_blind_choice' then
            tag:yep('+', G.C.GOLD, function() grant_pack('p_balacraft_resource_pack'); return true end)
            tag.triggered = true
            return true
        end
    end,
}

-- Food Tag -> free Food Pack.
SMODS.Tag {
    key = 'balacraft_food', atlas = 'tags', pos = { x = 0, y = 0 }, discovered = true, prefix_config = { atlas = false },
    loc_txt = { name = 'Food Tag', text = { 'Gives a free', '{C:attention}Food Pack{}' } },
    -- Show the granted pack's tooltip, like vanilla pack tags (Charm Tag -> Arcana pack).
    loc_vars = function(self, info_queue, card)
        local c = G.P_CENTERS['p_balacraft_food_pack']
        if c then info_queue[#info_queue + 1] = c end
    end,
    in_pool = function(self, args) return cfg('food_enabled') end,
    apply = function(self, tag, context)
        if context.type == 'new_blind_choice' then
            tag:yep('+', G.C.GREEN, function() grant_pack('p_balacraft_food_pack'); return true end)
            tag.triggered = true
            return true
        end
    end,
}

-- Mining Tag -> instantly gain 3 of a biome-biased ore at the ante's unlocked tier.
SMODS.Tag {
    key = 'balacraft_mining', atlas = 'tags', pos = { x = 0, y = 0 }, discovered = true, prefix_config = { atlas = false },
    loc_txt = { name = 'Mining Tag', text = { 'Gain {C:attention}3{}', 'random {C:attention}ore{}' } },
    in_pool = function(self, args) return cfg('resources_enabled') end,
    apply = function(self, tag, context)
        if context.type == 'new_blind_choice' then
            tag:yep('+', G.C.GOLD, function()
                local ante = (G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or 1
                local tier = PB_UTIL.max_ore_tier and PB_UTIL.max_ore_tier(ante) or 1
                local ore = PB_UTIL.random_ore_of_tier and PB_UTIL.random_ore_of_tier(tier, 'bc_mining_tag_' .. ante)
                if ore and PB_UTIL.add_resource then PB_UTIL.add_resource(ore, 3) end
                return true
            end)
            tag.triggered = true
            return true
        end
    end,
}

-- XP Tag -> gain roughly one level of XP.
SMODS.Tag {
    key = 'balacraft_xp', atlas = 'tags', pos = { x = 0, y = 0 }, discovered = true, prefix_config = { atlas = false },
    loc_txt = { name = 'XP Tag', text = { 'Gain about', '{C:blue}one level{} of XP' } },
    in_pool = function(self, args) return cfg('xp_enabled') end,
    apply = function(self, tag, context)
        if context.type == 'new_blind_choice' then
            tag:yep('+', G.C.BLUE, function()
                local lvl = PB_UTIL.get_level and PB_UTIL.get_level() or 0
                local amt = (PB_UTIL.xp_to_next and PB_UTIL.xp_to_next(lvl)) or 20
                if PB_UTIL.add_xp then PB_UTIL.add_xp(amt) end
                return true
            end)
            tag.triggered = true
            return true
        end
    end,
}

-- Blacksmith Tag -> a free random Tool, material tier capped by the current ante.
SMODS.Tag {
    key = 'balacraft_blacksmith', atlas = 'tags', pos = { x = 0, y = 0 }, discovered = true, prefix_config = { atlas = false },
    loc_txt = { name = 'Blacksmith Tag', text = { 'Gives a free', 'random {C:attention}Tool{}' } },
    in_pool = function(self, args) return cfg('resources_enabled') end,
    apply = function(self, tag, context)
        if context.type == 'new_blind_choice' then
            tag:yep('+', G.C.ORANGE, function()
                local ante = (G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or 1
                local cap = math.min(5, ante)
                local pool = {}
                for _, t in ipairs(PB_UTIL.TOOLS or {}) do
                    if (t.tier or 1) <= cap then pool[#pool + 1] = t.id end
                end
                if #pool > 0 and consumable_add then
                    local id = pseudorandom_element(pool, pseudoseed('bc_blacksmith_tag_' .. ante))
                    consumable_add('c_balacraft_tool_' .. id)
                end
                return true
            end)
            tag.triggered = true
            return true
        end
    end,
}

-- Explorer Tag -> the next post-boss biome screen offers 4 choices instead of 3.
SMODS.Tag {
    key = 'balacraft_explorer', atlas = 'tags', pos = { x = 0, y = 0 }, discovered = true, prefix_config = { atlas = false },
    loc_txt = { name = 'Explorer Tag', text = { '{C:attention}+1 choice{} at the', 'next biome select' } },
    in_pool = function(self, args) return cfg('biomes_enabled') end,
    apply = function(self, tag, context)
        if context.type == 'new_blind_choice' then
            tag:yep('+', G.C.PURPLE, function()
                if G.GAME and G.GAME.balacraft then G.GAME.balacraft._biome_extra = true end
                return true
            end)
            tag.triggered = true
            return true
        end
    end,
}
