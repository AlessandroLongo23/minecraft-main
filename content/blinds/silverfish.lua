SMODS.Blind {
    key = 'silverfish',
    loc_txt = { 
        name = "Silverfish",
        text = { 
            "After every hand played,",
            "score requirement",
            "increases by X1.5"
        }
    },
    discovered = true,
    boss = {
        min = 1,
        max = 1
    },
    pos = {
        x = 0,
        y = 14
    },
    atlas = 'blinds',
    boss_colour = HEX('758B98'),
    press_play = function(self)
        local start_chips = G.GAME.blind.chips
        local final_chips = start_chips * 1.5
        local chip_mod -- iterate over ~120 ticks
        if type(start_chips) ~= 'table' then
            chip_mod = math.ceil((final_chips - start_chips) / 120)
        else
            chip_mod = ((final_chips - start_chips) / 120):ceil()
        end
        local step = 0
        G.E_MANAGER:add_event(Event({
            trigger = 'after',
            blocking = true,
            func = function()
                G.GAME.blind.chips = G.GAME.blind.chips + G.SETTINGS.GAMESPEED * chip_mod
                if G.GAME.blind.chips < final_chips then
                    G.GAME.blind.chip_text = number_format(G.GAME.blind.chips)
                    if step % 5 == 0 then
                        play_sound('chips1', math.max(1.0 - (step * 0.005), 0.001))
                    end
                    step = step + 1
                else
                    G.GAME.blind.chips = final_chips
                    G.GAME.blind.chip_text = number_format(G.GAME.blind.chips)
                    return true
                end
            end
        }))
    end
}
