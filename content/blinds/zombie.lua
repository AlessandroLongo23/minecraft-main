SMODS.Blind {
    key = 'zombie',
    loc_txt = {
        name = "The Zombie",
        text = { 
            "After beating it,",
            "makes the leftmost joker",
            "perishable"
        }
    },
    discovered = true,
    boss = {
        min = 1,
        max = 1
    },
    pos = {
        x = 0,
        y = 1
    },
    atlas = 'blinds',
    boss_colour = HEX('4E7D3D'),
    discard = function(self)
        G.E_MANAGER:add_event(Event({ func = function()
            local any_selected = nil
            local _cards = {}
            
            for k, v in ipairs(G.hand.cards) do
                _cards[#_cards+1] = v
            end

            if G.hand.cards[1] then 
                local selected_card, card_key = pseudorandom_element(_cards, pseudoseed('drowned'))
                G.hand:add_to_highlighted(selected_card, true)
                table.remove(_cards, card_key)
                any_selected = true
                play_sound('card1', 1)
            end
            if any_selected then G.FUNCS.discard_cards_from_highlighted(nil, true) end
        return true end })) 
        self.triggered = true
        delay(0.7)
        return true
    end
}