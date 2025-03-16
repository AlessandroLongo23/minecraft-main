SMODS.Blind {
    key = 'phantom',
    loc_txt = {
        name = "The Phantom",
        text = { 
            "Destroy a random card",
            "in hand after scoring"
        }
    },
    discovered = true,
    boss = {
        min = 1,
        max = 1
    },
    pos = {
        x = 0,
        y = 12
    },
    atlas = 'blinds',
    boss_colour = HEX('5061AE'),
    defeat = function()
        local destructable_cards = {}
        for i = 1, #G.hand.cards do
            destructable_cards[#destructable_cards+1] = G.hand.cards[i] 
        end
        local card_to_destroy = #destructable_cards > 0 and pseudorandom_element(destructable_cards, pseudoseed('phantom')) or nil

        if card_to_destroy then
            card_to_destroy.getting_sliced = true
            card_to_destroy:juice_up(0.8, 0.8)
            card_to_destroy:start_dissolve({G.C.BLACK}, nil, 1.6)
            play_sound('slice1', 0.96+math.random()*0.08)
        end
    end
}