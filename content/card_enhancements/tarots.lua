-- Tarot consumables that apply the tarot-applied block enhancements to a selected card.
-- set = 'Tarot' so they roll in the shop and Arcana packs like vanilla tarots.
-- Pattern mirrors vanilla enhancement tarots: can_use checks exactly one highlighted card;
-- use() calls card:set_ability(G.P_CENTERS[key]).

-- Obsidian is no longer a Tarot-applied enhancement -- it is now a Diamond-Pickaxe-mined Ore Block
-- (content/card_enhancements/blocks.lua), so only Hay Bale + Lapis have Tarot appliers here.
local APPLIERS = {
    { key = 'tarot_hay_bale', center = 'm_balacraft_hay_bale', name = 'Hay Bale',  pos = { x = 0, y = 0 } },
    { key = 'tarot_lapis',    center = 'm_balacraft_lapis',    name = 'Lapis',     pos = { x = 2, y = 0 } },
}

for _, a in ipairs(APPLIERS) do
    local app = a
    SMODS.Consumable {
        key = app.key,                       -- => c_balacraft_tarot_hay_bale, ...
        set = 'Tarot',
        atlas = 'bc_resource_cards',
        pos = app.pos,
        cost = 3,
        discovered = true,
        loc_txt = {
            name = app.name .. ' Block',
            text = {
                'Enhance {C:attention}1{} selected card',
                'into a {C:attention}' .. app.name .. '{} card.',
            },
        },
        -- Append the produced enhancement to info_queue so its description renders as a
        -- secondary tooltip box, exactly like vanilla enhancement Tarots (The Tower -> Stone).
        loc_vars = function(self, info_queue, card)
            info_queue[#info_queue + 1] = G.P_CENTERS[app.center]
        end,
        -- Usable whenever exactly one hand card is highlighted -- works both during a blind and
        -- while opening an Arcana pack (don't gate on G.STATE; the pack state isn't SELECTING_HAND).
        can_use = function(self, card)
            return G.hand ~= nil and #G.hand.highlighted == 1
        end,
        use = function(self, card, area, copier)
            local target = G.hand.highlighted[1]
            if not target then return end
            G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.2, func = function()
                target:set_ability(G.P_CENTERS[app.center])
                target:juice_up(0.3, 0.5)
                return true
            end }))
            G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.1, func = function()
                if G.hand then G.hand:unhighlight_all() end
                return true
            end }))
            delay(0.5)
        end,
    }
end
