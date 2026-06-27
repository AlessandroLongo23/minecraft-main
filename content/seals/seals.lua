-- BalaCraft Seals: Ore (on discard -> mine a resource), Soul (on play -> XP),
-- Cooked (held in hand at end of round -> cook into a Food; the seal stays on the card).
-- Applied by the Spectral cards in content/seals/spectrals.lua. Art = the vanilla seal "wax
-- stamp" re-tinted per seal (Ore=cobblestone grey, Soul=XP-bar green, Cooked=cooked-chicken
-- brown), keeping the stock seal's lightness so the contrast matches vanilla; sheet built by
-- assets/gen_seals.py. Effects are pcall-safe / deferred so a hiccup never breaks scoring or
-- round end.

-- 71x95 seal stamps, 1 row x 3 cols: ore {0,0} soul {1,0} cooked {2,0}.
SMODS.Atlas { key = 'bc_seals', path = 'seals.png', px = 71, py = 95 }

-- Ore Seal -- on discard, mine 1 resource (biome-biased, ante-gated; same roll as blind drops).
SMODS.Seal {
    key = 'ore',
    atlas = 'bc_seals',
    pos = { x = 0, y = 0 },
    badge_colour = HEX('8c9099'), -- cobblestone grey, matches the seal sprite
    loc_txt = {
        label = 'Ore Seal', name = 'Ore Seal',
        text = { 'On {C:attention}discard{}, mine', '{C:attention}1{} random ore' },
    },
    calculate = function(self, card, context)
        if context.discard and context.other_card == card then
            local ante = (G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or 1
            local tier = PB_UTIL.max_ore_tier and PB_UTIL.max_ore_tier(ante) or 1
            local ore = PB_UTIL.random_ore_of_tier and PB_UTIL.random_ore_of_tier(tier, 'bc_ore_seal_' .. ante)
            if ore and PB_UTIL.add_resource then
                PB_UTIL.add_resource(ore, 1)
                local res = PB_UTIL.RESOURCE_BY_ID and PB_UTIL.RESOURCE_BY_ID[ore]
                return { message = '+1 ' .. ((res and res.name) or ore), colour = G.C.GOLD }
            end
        end
    end,
}

-- Soul Seal -- on play (when scored), gain XP.
SMODS.Seal {
    key = 'soul',
    atlas = 'bc_seals',
    pos = { x = 1, y = 0 },
    badge_colour = HEX('6fc63a'), -- XP-bar green, matches the seal sprite
    loc_txt = {
        label = 'Soul Seal', name = 'Soul Seal',
        text = { 'On {C:attention}play{}, gain', '{C:blue}5{} XP' },
    },
    calculate = function(self, card, context)
        if context.cardarea == G.play and context.main_scoring then
            if PB_UTIL.add_xp then PB_UTIL.add_xp(5) end
            return { message = '+5 XP', colour = G.C.BLUE }
        end
    end,
}

-- Cooked Seal -- held in hand at end of round: cook into a Food (deferred like the Blue seal's
-- Planet). The seal stays on the card and cooks again every round, like any other seal.
SMODS.Seal {
    key = 'cooked',
    atlas = 'bc_seals',
    pos = { x = 2, y = 0 },
    badge_colour = HEX('c77c49'), -- cooked-chicken brown, matches the seal sprite
    loc_txt = {
        label = 'Cooked Seal', name = 'Cooked Seal',
        text = { 'Held at end of round,', 'cooks into a {C:attention}Food{}' },
    },
    calculate = function(self, card, context)
        if context.end_of_round and context.other_card == card then
            -- Create a random food (the core reward). Deferred via an event, like Blue seal.
            G.E_MANAGER:add_event(Event({ trigger = 'before', delay = 0.0, func = function()
                pcall(function()
                    if PB_UTIL.FOODS and consumable_add then
                        local ids = {}
                        for _, f in ipairs(PB_UTIL.FOODS) do ids[#ids + 1] = 'c_balacraft_food_' .. f.id end
                        if #ids > 0 then
                            consumable_add(pseudorandom_element(ids, pseudoseed('bc_cooked_seal')))
                        end
                    end
                end)
                return true
            end }))
            return { message = 'Cooked!', colour = G.C.ORANGE }
        end
    end,
}
