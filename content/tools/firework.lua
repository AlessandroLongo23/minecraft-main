-- Firework Rocket (explosives cluster; Gunpowder sink). Crafted from 1 Gunpowder + 1 Stick. A
-- one-shot consumable: select a card in hand and permanently load it with Chips -- a base amount
-- plus a bonus for every Gunpowder you're currently holding (rewards a gunpowder-hoarding build;
-- the more you keep, the harder each firework hits). Rides the craft-only 'balacraft_tool' type.

-- 71x95 card face from the authentic MC firework_rocket item texture (gen_item_consumable_cards.py).
SMODS.Atlas { key = 'bc_firework', path = 'firework.png', px = 71, py = 95 }

-- Authentic MC `firework_rocket` recipe-list / output-preview icon (bc_tool_icons extras, {x=1,y=4}).
PB_UTIL.tool_icon_pos = PB_UTIL.tool_icon_pos or {}
PB_UTIL.tool_icon_pos['c_balacraft_firework'] = { x = 1, y = 4 }

SMODS.Consumable {
    key = 'firework',
    set = 'balacraft_tool',
    atlas = 'bc_firework',
    pos = { x = 0, y = 0 },
    cost = 3,
    discovered = true,
    config = { extra = { chips = 100, per_gunpowder = 50 } },

    loc_txt = {
        name = 'Firework Rocket',
        text = {
            'Select {C:attention}1{} card. It permanently',
            'gains {C:chips}+#1#{} Chips, plus {C:chips}+#2#{} for',
            'each {C:attention}Gunpowder{} you own.',
            '{C:inactive}(now {C:chips}+#3#{C:inactive} Chips)',
        },
    },

    loc_vars = function(self, info_queue, card)
        local e = card.ability.extra
        local owned = (PB_UTIL.get_resource_count and PB_UTIL.get_resource_count('gunpowder')) or 0
        return { vars = { e.chips, e.per_gunpowder, e.chips + e.per_gunpowder * owned } }
    end,

    can_use = function(self, card)
        return PB_UTIL.hand_consumable_state()
            and G.hand and G.hand.highlighted and #G.hand.highlighted == 1
    end,

    use = function(self, card, area, copier)
        local target = G.hand.highlighted and G.hand.highlighted[1]
        if not target then return end
        local e = card.ability.extra
        local owned = (PB_UTIL.get_resource_count and PB_UTIL.get_resource_count('gunpowder')) or 0
        local total = e.chips + e.per_gunpowder * owned
        G.hand:unhighlight_all()
        G.E_MANAGER:add_event(Event({
            func = function()
                target.ability.perma_bonus = (target.ability.perma_bonus or 0) + total
                target:juice_up(0.3, 0.4)
                play_sound('whoosh1')
                return true
            end,
        }))
    end,
}
