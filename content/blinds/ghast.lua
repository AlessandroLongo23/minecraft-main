SMODS.Blind {
    key = 'ghast',
    loc_txt = {
        name = "The Ghast",
        text = {
            "1 in 2 chance to destroy",
            "each card left in hand;",
            "a played Straight wins"
        }
    },
    discovered = true,
    boss = {
        min = 2,
        max = 2
    },
    pos = {
        x = 0,
        y = 10
    },
    atlas = 'blinds',
    boss_colour = HEX('F0F0F0'),
    press_play = function(self)
        -- Played cards aren't in G.play yet at press_play; evaluate the highlighted set.
        local played = G.hand.highlighted
        if played and #played > 0 then
            local hand_type = G.FUNCS.get_poker_hand_info(played)
            if hand_type == 'Straight' or hand_type == 'Straight Flush' then
                -- Drop the requirement to 0 so this scored hand instantly clears the blind.
                G.GAME.blind.chips = 0
                G.GAME.blind.chip_text = number_format(0)
                G.GAME.blind:wiggle()
            end
        end

        -- After scoring, each card left in hand has a 1 in 2 chance to be destroyed.
        G.E_MANAGER:add_event(Event({
            trigger = 'after',
            delay = 0.1,
            func = function()
                for i = 1, #G.hand.cards do
                    if pseudorandom(pseudoseed('ghast')) < 0.5 then
                        G.hand.cards[i]:start_dissolve()
                    end
                end
                return true
            end
        }))
    end
}
