-- Frees every joker the Enderman has pinned. Used when the lock moves to a new
-- joker and when the blind ends -- `pinned` lives on the card, not the blind, so
-- it won't clear itself.
local function clear_enderman_pins()
    if not G.jokers then return end
    for _, card in ipairs(G.jokers.cards) do
        card.pinned = nil
    end
end

-- Locks a random joker to the leftmost slot, moving the lock off whichever joker
-- currently holds it (only one is ever pinned at a time, so everything to its
-- right stays freely rearrangeable). Returns true if a joker was pinned.
local function pin_random_joker()
    if not G.jokers or #G.jokers.cards < 2 then return false end

    -- the joker currently locked (if any), so the lock jumps to a different one
    local current
    for _, card in ipairs(G.jokers.cards) do
        if card.pinned then current = card end
    end

    clear_enderman_pins()

    local choices = {}
    for _, card in ipairs(G.jokers.cards) do
        if card ~= current then choices[#choices + 1] = card end
    end
    local card = pseudorandom_element(choices, pseudoseed('enderman'))
    card.pinned = true
    G.jokers:align_cards()

    card:juice_up(0.4, 0.4)
    play_sound('whoosh1', 1.2, 0.4)
    return true
end

SMODS.Blind {
    key = 'enderman',
    loc_txt = {
        name = "The Enderman",
        text = {
            "Each played hand,",
            "locks a random joker",
            "to the leftmost slot"
        }
    },
    discovered = true,
    boss = {
        min = 1,
        max = 1
    },
    pos = {
        x = 0,
        y = 3
    },
    atlas = 'blinds',
    boss_colour = HEX('A400C9'),
    -- Lock the first joker the moment the blind starts, before any hand is played.
    set_blind = function(self)
        self.balacraft_repin_pending = nil
        pin_random_joker()
    end,
    -- Fires when a hand is played (never on discard) but BEFORE it scores, so we
    -- don't move the lock yet -- just flag that the next draw should re-pin.
    press_play = function(self)
        self.balacraft_repin_pending = true
    end,
    -- Fires after cards are redrawn: after a played hand finishes scoring, but
    -- also after discards and the round-start draw. Only move the lock when a
    -- played hand set the flag, so discards and the initial draw don't re-pin.
    drawn_to_hand = function(self)
        if not self.balacraft_repin_pending then return end
        self.balacraft_repin_pending = nil
        pin_random_joker()
    end,
    defeat = function(self)
        self.balacraft_repin_pending = nil
        clear_enderman_pins()
    end,
    disable = function(self)
        self.balacraft_repin_pending = nil
        clear_enderman_pins()
    end
}
