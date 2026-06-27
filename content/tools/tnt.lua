-- TNT (explosives cluster; Gunpowder sink). Crafted from 4 Gunpowder + 1 Cobblestone. A one-shot
-- consumable: select a card in hand and blow it up along with the card on each side of it. Rides
-- the craft-only 'balacraft_tool' consumable type (like Torch / Arrow / Bone Meal); consumed on use.

-- 71x95 card face from the authentic MC tnt_side block texture (assets/gen_item_consumable_cards.py).
SMODS.Atlas { key = 'bc_tnt', path = 'tnt.png', px = 71, py = 95 }

-- Authentic MC `tnt` recipe-list / output-preview icon (bc_tool_icons extras, cell {x=0,y=4}).
PB_UTIL.tool_icon_pos = PB_UTIL.tool_icon_pos or {}
PB_UTIL.tool_icon_pos['c_balacraft_tnt'] = { x = 0, y = 4 }

SMODS.Consumable {
    key = 'tnt',
    set = 'balacraft_tool',
    atlas = 'bc_tnt',
    pos = { x = 0, y = 0 },
    cost = 4,
    discovered = true,

    loc_txt = {
        name = 'TNT',
        text = {
            'Select {C:attention}1{} card, then',
            '{C:attention}destroy{} it and the two',
            'cards on either side of it.',
        },
    },

    can_use = function(self, card)
        return PB_UTIL.hand_consumable_state()
            and G.hand and G.hand.highlighted and #G.hand.highlighted == 1
    end,

    use = function(self, card, area, copier)
        local sel = G.hand.highlighted and G.hand.highlighted[1]
        if not sel then return end
        -- Index of the selected card in the ordered hand, then it + its two neighbours.
        local idx
        for i, c in ipairs(G.hand.cards) do if c == sel then idx = i break end end
        if not idx then return end
        local targets = {}
        for _, j in ipairs({ idx - 1, idx, idx + 1 }) do
            local c = G.hand.cards[j]
            if c then targets[#targets + 1] = c end
        end
        G.hand:unhighlight_all()

        G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.2, func = function()
            play_sound('explosion_release1') ; card:juice_up(0.3, 0.5)
            return true
        end }))
        -- Destroy the targets (permanent, like The Hanged Man -- card.lua:1606). Glass shatters.
        G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.2, func = function()
            for i = #targets, 1, -1 do
                local t = targets[i]
                if SMODS.shatters and SMODS.shatters(t) then t:shatter()
                else t:start_dissolve() end
            end
            return true
        end }))
    end,
}
