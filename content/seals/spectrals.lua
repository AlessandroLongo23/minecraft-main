-- Spectral cards that apply the BalaCraft seals to a selected card (one per seal), mirroring
-- vanilla seal spectrals (Deja Vu / Trance / Talisman / Medium). set = 'Spectral' so they roll
-- in the shop and Spectral packs. Placeholder art reuses bc_resource_cards.
--
-- Robust to the seal-key prefix: SMODS may register the seal as 'balacraft_<key>' or '<key>';
-- we resolve whichever exists in G.P_SEALS before calling set_seal, so a prefix mismatch can't
-- crash the use().
local SEAL_SPECTRALS = {
    { key = 'spectral_ore',    bare = 'ore',    name = 'Ore Seal',    pos = { x = 2, y = 1 } },
    { key = 'spectral_soul',   bare = 'soul',   name = 'Soul Seal',   pos = { x = 2, y = 0 } },
    { key = 'spectral_cooked', bare = 'cooked', name = 'Cooked Seal', pos = { x = 0, y = 0 } },
}

local function resolve_seal_key(bare)
    if G.P_SEALS['balacraft_' .. bare] then return 'balacraft_' .. bare end
    if G.P_SEALS[bare] then return bare end
    return nil
end

for _, s in ipairs(SEAL_SPECTRALS) do
    local sp = s
    SMODS.Consumable {
        key = sp.key,                       -- => c_balacraft_spectral_ore, ...
        set = 'Spectral',
        atlas = 'bc_resource_cards',
        pos = sp.pos,
        cost = 4,
        discovered = true,
        loc_txt = {
            name = sp.name,
            text = { 'Add a {C:attention}' .. sp.name .. '{}', 'to {C:attention}1{} selected card' },
        },
        -- Show the produced seal's description as a secondary tooltip, like vanilla seal
        -- spectrals (Talisman -> Gold Seal). Resolve the seal exactly as use() does.
        loc_vars = function(self, info_queue, card)
            local key = resolve_seal_key(sp.bare)
            if key and G.P_SEALS[key] then info_queue[#info_queue + 1] = G.P_SEALS[key] end
        end,
        -- Usable whenever exactly one hand card is highlighted -- works both during a blind and
        -- while opening a Spectral pack (don't gate on G.STATE; the pack state isn't SELECTING_HAND).
        can_use = function(self, card)
            return G.hand ~= nil and #G.hand.highlighted == 1
        end,
        use = function(self, card, area, copier)
            local target = G.hand.highlighted[1]
            if not target then return end
            G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.2, func = function()
                local key = resolve_seal_key(sp.bare)
                if key and target.set_seal then
                    target:set_seal(key, nil, true)
                    target:juice_up(0.3, 0.5)
                end
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
