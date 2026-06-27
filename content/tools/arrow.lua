-- Arrow (Wave 1, Archery). Crafted from 1 Flint + 1 Stick + 1 Feather. A cheap one-shot
-- consumable: sharpen a card so it scores more Mult. Rides the 'balacraft_tool' craft-only
-- consumable type (like the Torch). Unlike tools it has no durability/keep_on_use -- it is
-- consumed on use.
-- 71x95 card art: the authentic `arrow` MC texture on the tool-card chrome, built by
-- assets/gen_arrow_card.py (a clone of gen_torch_card.py).
SMODS.Atlas { key = 'bc_arrow', path = 'arrow.png', px = 71, py = 95 }

-- Authentic MC `arrow` icon for the crafting recipe LIST / output preview (bc_tool_icons extras
-- row, assets/gen_tool_icons.py cell {x=4,y=3}). tool_consumabletype.lua loads first.
PB_UTIL.tool_icon_pos = PB_UTIL.tool_icon_pos or {}
PB_UTIL.tool_icon_pos['c_balacraft_arrow'] = { x = 4, y = 3 }

SMODS.Consumable {
    key = 'arrow',
    set = 'balacraft_tool',
    atlas = 'bc_arrow',
    pos = { x = 0, y = 0 },
    cost = 2,
    discovered = true,
    loc_txt = {
        name = 'Arrow',
        text = {
            'Select {C:attention}1{} card in your hand,',
            'then use to permanently give it',
            '{C:mult}+#1#{} Mult.',
        },
    },

    config = { extra = { mult = 3 } },

    loc_vars = function(self, info_queue, card)
        return { vars = { card.ability.extra.mult } }
    end,

    can_use = function(self, card)
        return PB_UTIL.hand_consumable_state()
            and G.hand and G.hand.highlighted and #G.hand.highlighted == 1
    end,

    use = function(self, card, area, copier)
        local target = G.hand.highlighted and G.hand.highlighted[1]
        if not target then return end
        local amt = card.ability.extra.mult
        G.E_MANAGER:add_event(Event({
            func = function()
                target.ability.perma_mult = (target.ability.perma_mult or 0) + amt
                target:juice_up(0.3, 0.4)
                play_sound('tarot1')
                return true
            end,
        }))
        G.hand:unhighlight_all()
    end,
}
