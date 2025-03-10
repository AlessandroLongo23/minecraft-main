SMODS.Blind {
    key = 'creeper',
    loc_txt = {
        name = "The Creeper",
        text = { 
            "Destroy a random joker,",
            "if winning at last hand"
        }
    },
    discovered = true,
    boss = {
        min = 1,
        max = 1
    },
    pos = {
        x = 0,
        y = 2
    },
    atlas = 'blinds',
    boss_colour = HEX('238C23'),
    defeat = function()
        if G.GAME.current_round.hands_left == 0 then
            local destructable_jokers = {}
            for i = 1, #G.jokers.cards do
                if not G.jokers.cards[i].ability.eternal and not G.jokers.cards[i].getting_sliced then 
                    destructable_jokers[#destructable_jokers+1] = G.jokers.cards[i] 
                end
            end
            local joker_to_destroy = #destructable_jokers > 0 and pseudorandom_element(destructable_jokers, pseudoseed('creeper')) or nil

            if joker_to_destroy and not joker_to_destroy.getting_sliced then
                joker_to_destroy.getting_sliced = true
                joker_to_destroy:juice_up(0.8, 0.8)
                joker_to_destroy:start_dissolve({G.C.BLACK}, nil, 1.6)
                play_sound('slice1', 0.96+math.random()*0.08)
            end
        end
    end
}
