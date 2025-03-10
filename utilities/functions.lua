function joker_add(jKey)
    if type(jKey) == 'string' then
        local j = SMODS.create_card({
            key = jKey,
        })

        j:add_to_deck()
        G.jokers:emplace(j)
    end
end

function PB_UTIL.register_items(items, folder)
    for i = 1, #items do
        SMODS.load_file("content/" .. folder .. "/" .. items[i] .. ".lua")()
    end
end

function PB_UTIL.load_blinds(items)
    sendDebugMessage("Loading Blinds...", 'Minecraft')
    for i = 1, #items do
        local status, err = pcall(function()
            return NFS.load(SMODS.current_mod.path .. 'content/blinds/' .. items[i] .. '.lua')()
        end)
        sendDebugMessage("Loaded blind: " .. items[i], 'Minecraft')

        if not status then
            error(items[i] .. ": " .. err)
        end
    end
    sendDebugMessage("", 'Minecraft')

    SMODS.Atlas(
        {
            key = 'blinds', 
            path = 'blinds.png', 
            px = 34, 
            py = 34, 
            frames = 21, 
            atlas_table = 'ANIMATION_ATLAS'
        }
    )
end

-- PB_UTIL.select_random_card = function()
--     if not G.GAME.blind.disabled then
--         local any_selected = nil
--         local _cards = {}
        
--         for k, v in ipairs(G.hand.cards) do
--             _cards[#_cards+1] = v
--         end
        
--         if G.hand.cards[1] then 
--             local selected_card, card_key = pseudorandom_element(_cards, pseudoseed(G.GAME.blind.name))
--             G.hand:add_to_highlighted(selected_card, true)
--             selected_card.ability.debuff_triggered = true
--             table.remove(_cards, card_key)
--             any_selected = true
--             play_sound('card1', 1)
--         end
--     end
-- end

PB_UTIL.drowned_effect = function(e, hook)
    stop_use()
    G.CONTROLLER.interrupt.focus = true
    G.CONTROLLER:save_cardarea_focus('hand')

    for k, v in ipairs(G.playing_cards) do
        v.ability.forced_selection = nil
    end

    -- Store the initially highlighted cards to track what's being discarded
    local initially_highlighted = {}
    for _, card in ipairs(G.hand.highlighted) do
        table.insert(initially_highlighted, card)
    end

    if G.CONTROLLER.focused.target and G.CONTROLLER.focused.target.area == G.hand then G.card_area_focus_reset = {area = G.hand, rank = G.CONTROLLER.focused.target.rank} end
    local highlighted_count = math.min(#G.hand.highlighted, G.discard.config.card_limit - #G.play.cards)
    if highlighted_count > 0 then 
        update_hand_text({immediate = true, nopulse = true, delay = 0}, {mult = 0, chips = 0, level = '', handname = ''})
        table.sort(G.hand.highlighted, function(a,b) return a.T.x < b.T.x end)
        inc_career_stat('c_cards_discarded', highlighted_count)
        SMODS.calculate_context({pre_discard = true, full_hand = G.hand.highlighted, hook = hook})
        
        -- TARGET: pre_discard
        local cards = {}
        local destroyed_cards = {}
        for i=1, highlighted_count do
            G.hand.highlighted[i]:calculate_seal({discard = true})
            local removed = false
            local effects = {}
            SMODS.calculate_context({discard = true, other_card =  G.hand.highlighted[i], full_hand = G.hand.highlighted}, effects)
            SMODS.trigger_effects(effects)
            for _, eval in pairs(effects) do
                if type(eval) == 'table' then
                    for key, eval2 in pairs(eval) do
                        if key == 'remove' or (type(eval2) == 'table' and eval2.remove) then removed = true end
                    end
                end
            end
            table.insert(cards, G.hand.highlighted[i])
            if removed then
                destroyed_cards[#destroyed_cards + 1] = G.hand.highlighted[i]
                if SMODS.shatters(G.hand.highlighted[i]) then
                    G.hand.highlighted[i]:shatter()
                else
                    G.hand.highlighted[i]:start_dissolve()
                end
            else 
                G.hand.highlighted[i].ability.discarded = true
                draw_card(G.hand, G.discard, i*100/highlighted_count, 'down', false, G.hand.highlighted[i])
            end
        end

        -- context.remove_playing_cards from discard
        if destroyed_cards[1] then
            SMODS.calculate_context({remove_playing_cards = true, removed = destroyed_cards})
        end
        
        -- TARGET: effects after cards destroyed in discard

        G.GAME.round_scores.cards_discarded.amt = G.GAME.round_scores.cards_discarded.amt + #cards
        check_for_unlock({type = 'discard_custom', cards = cards})
        if not hook then
            if G.GAME.modifiers.discard_cost then
                ease_dollars(-G.GAME.modifiers.discard_cost)
            end
            -- ease_discard(-1)
            -- G.GAME.current_round.discards_used = G.GAME.current_round.discards_used + 1
            -- G.STATE = G.STATES.DRAW_TO_HAND
            -- G.E_MANAGER:add_event(Event({
            --     trigger = 'immediate',
            --     func = function()
            --         G.STATE_COMPLETE = false
            --         return true
            --     end
            -- }))
        end
        
        G.hand:unhighlight_all()
    end

    -- Select a random card from the remaining cards in hand
    local selected_card, card_key = nil, nil
    local remaining_cards = {}
    
    -- Create a list of cards that weren't discarded in the first step
    for _, card in ipairs(G.hand.cards) do
        local was_discarded = false
        for _, discarded_card in ipairs(initially_highlighted) do
            if card == discarded_card then
                was_discarded = true
                break
            end
        end
        if not was_discarded then
            table.insert(remaining_cards, card)
        end
    end
    
    if #remaining_cards > 0 then 
        selected_card, card_key = pseudorandom_element(remaining_cards, pseudoseed(G.GAME.blind.name))
        G.hand:add_to_highlighted(selected_card, true)
        play_sound('card1', 1)
    end

    stop_use()
    G.CONTROLLER.interrupt.focus = true
    G.CONTROLLER:save_cardarea_focus('hand')

    for k, v in ipairs(G.playing_cards) do
        v.ability.forced_selection = nil
    end

    if G.CONTROLLER.focused.target and G.CONTROLLER.focused.target.area == G.hand then G.card_area_focus_reset = {area = G.hand, rank = G.CONTROLLER.focused.target.rank} end
    local highlighted_count = math.min(#G.hand.highlighted, G.discard.config.card_limit - #G.play.cards)
    if highlighted_count > 0 then 
        update_hand_text({immediate = true, nopulse = true, delay = 0}, {mult = 0, chips = 0, level = '', handname = ''})
        table.sort(G.hand.highlighted, function(a,b) return a.T.x < b.T.x end)
        inc_career_stat('c_cards_discarded', highlighted_count)
        SMODS.calculate_context({pre_discard = true, full_hand = G.hand.highlighted, hook = hook})
        
        -- TARGET: pre_discard
        local cards = {}
        local destroyed_cards = {}
        for i=1, highlighted_count do
            G.hand.highlighted[i]:calculate_seal({discard = true})
            local removed = false
            local effects = {}
            SMODS.calculate_context({discard = true, other_card =  G.hand.highlighted[i], full_hand = G.hand.highlighted}, effects)
            SMODS.trigger_effects(effects)
            for _, eval in pairs(effects) do
                if type(eval) == 'table' then
                    for key, eval2 in pairs(eval) do
                        if key == 'remove' or (type(eval2) == 'table' and eval2.remove) then removed = true end
                    end
                end
            end
            table.insert(cards, G.hand.highlighted[i])
            if removed then
                destroyed_cards[#destroyed_cards + 1] = G.hand.highlighted[i]
                if SMODS.shatters(G.hand.highlighted[i]) then
                    G.hand.highlighted[i]:shatter()
                else
                    G.hand.highlighted[i]:start_dissolve()
                end
            else 
                G.hand.highlighted[i].ability.discarded = true
                draw_card(G.hand, G.discard, i*100/highlighted_count, 'down', false, G.hand.highlighted[i])
            end
        end

        -- context.remove_playing_cards from discard
        if destroyed_cards[1] then
            SMODS.calculate_context({remove_playing_cards = true, removed = destroyed_cards})
        end
        
        -- TARGET: effects after cards destroyed in discard

        G.GAME.round_scores.cards_discarded.amt = G.GAME.round_scores.cards_discarded.amt + #cards
        check_for_unlock({type = 'discard_custom', cards = cards})
        if not hook then
            if G.GAME.modifiers.discard_cost then
                ease_dollars(-G.GAME.modifiers.discard_cost)
            end
            ease_discard(-1)
            G.GAME.current_round.discards_used = G.GAME.current_round.discards_used + 1
            G.STATE = G.STATES.DRAW_TO_HAND
            G.E_MANAGER:add_event(Event({
                trigger = 'immediate',
                func = function()
                    G.STATE_COMPLETE = false
                    return true
                end
            }))
        end
        G.hand:unhighlight_all()
    end
end