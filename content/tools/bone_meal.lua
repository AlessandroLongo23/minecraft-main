-- Bone Meal (mob-drop sink). Crafted from 1 Bone (content/resources/recipes.lua) -- gives the Bone
-- mob drop a use. A one-shot consumable that "grows" your cards: select up to 3 cards in hand, each
-- gains permanent Chips, and the poker hand they form is permanently buffed. Rides the craft-only
-- 'balacraft_tool' consumable type (like the Torch / Arrow); consumed on use (no durability).

-- Dedicated 71x95 card face from the authentic MC bone_meal item texture (assets/gen_bone_meal_card.py).
SMODS.Atlas { key = 'bc_bone_meal', path = 'bone_meal.png', px = 71, py = 95 }

-- Authentic MC `bone_meal` recipe-list / output-preview icon (bc_tool_icons extras row, cell
-- {x=5,y=3}; assets/gen_tool_icons.py). tool_consumabletype.lua loads first and creates the table.
PB_UTIL.tool_icon_pos = PB_UTIL.tool_icon_pos or {}
PB_UTIL.tool_icon_pos['c_balacraft_bone_meal'] = { x = 5, y = 3 }

SMODS.Consumable {
    key = 'bone_meal',
    set = 'balacraft_tool',
    atlas = 'bc_bone_meal',
    pos = { x = 0, y = 0 },
    cost = 4,
    discovered = true,
    config = { extra = { card_chips = 5, hand_chips = 5, hand_mult = 1, max_select = 3 } },

    loc_txt = {
        name = 'Bone Meal',
        text = {
            'Select up to {C:attention}#4#{} cards in hand,',
            'each gains a permanent {C:chips}+#1#{} Chips.',
            'Their {C:attention}poker hand{} also gains',
            '{C:chips}+#2#{} Chips and {C:mult}+#3#{} Mult.',
        },
    },

    loc_vars = function(self, info_queue, card)
        local e = card.ability.extra
        return { vars = { e.card_chips, e.hand_chips, e.hand_mult, e.max_select } }
    end,

    can_use = function(self, card)
        return PB_UTIL.hand_consumable_state()
            and G.hand and G.hand.highlighted
            and #G.hand.highlighted >= 1
            and #G.hand.highlighted <= card.ability.extra.max_select
    end,

    use = function(self, card, area, copier)
        -- Snapshot the selection (unhighlight clears G.hand.highlighted later).
        local hl = {}
        for _, c in ipairs(G.hand.highlighted) do hl[#hl + 1] = c end
        if #hl == 0 then return end
        -- The poker hand the selection forms (first return is the hand name, e.g. 'Pair').
        local hand_name = G.FUNCS.get_poker_hand_info(hl)
        local e = card.ability.extra

        -- +Chips to each selected card (permanent, scored via perma_bonus -- card.lua:918).
        for _, c in ipairs(hl) do
            local target = c
            G.E_MANAGER:add_event(Event({
                func = function()
                    target.ability.perma_bonus = (target.ability.perma_bonus or 0) + e.card_chips
                    target:juice_up(0.3, 0.4)
                    return true
                end,
            }))
        end
        play_sound('tarot1')

        -- Permanently buff that poker hand by bumping its BASE chips/mult and recomputing the
        -- current values from level (mirrors level_up_hand, common_events.lua:485-486). G.GAME.hands
        -- lives on G.GAME -> auto-saved/reset per run, no custom save/load.
        if hand_name and G.GAME.hands[hand_name] then
            G.E_MANAGER:add_event(Event({
                func = function()
                    local h = G.GAME.hands[hand_name]
                    h.s_chips = h.s_chips + e.hand_chips
                    h.s_mult  = h.s_mult  + e.hand_mult
                    h.chips = math.max(h.s_chips + h.l_chips * (h.level - 1), 0)
                    h.mult  = math.max(h.s_mult  + h.l_mult  * (h.level - 1), 1)
                    return true
                end,
            }))
        end

        G.hand:unhighlight_all()
    end,
}
