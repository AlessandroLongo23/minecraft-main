SMODS.Blind {
    key = 'phantom',
    loc_txt = {
        name = "The Phantom",
        text = { 
            "x3 if no blind was skipped this ante",
        }
    },
    discovered = true,
    boss = {
        min = 2,
        max = 2
    },
    pos = {
        x = 0,
        y = 12
    },
    atlas = 'blinds',
    boss_colour = HEX('5061AE'),
    set_blind = function(self, reset, silent)
        if not reset and not G.GAME.blind.disabled and G.GAME.skipped_blinds_this_ante == 0 then
            local final_chips = G.GAME.blind.chips / G.GAME.blind.mult * 3

            local chip_mod -- iterate over ~120 ticks
            if type(G.GAME.blind.chips) ~= 'table' then
                chip_mod = math.ceil((final_chips - G.GAME.blind.chips) / 120)
            else
                chip_mod = ((final_chips - G.GAME.blind.chips) / 120):ceil()
            end
            local step = 0
            G.E_MANAGER:add_event(Event({trigger = 'after', blocking = true, func = function()
                G.GAME.blind.chips = G.GAME.blind.chips + G.SETTINGS.GAMESPEED * chip_mod
                if G.GAME.blind.chips < final_chips then
                    G.GAME.blind.chip_text = number_format(G.GAME.blind.chips)
                    if step % 5 == 0 then
                        play_sound('chips1', 0.8 + (step * 0.005))
                    end
                    step = step + 1
                else
                    G.GAME.blind.chips = final_chips
                    G.GAME.blind.chip_text = number_format(G.GAME.blind.chips)
                    G.GAME.blind:wiggle()
                    return true
                end
            end}))
        end
    end,
}