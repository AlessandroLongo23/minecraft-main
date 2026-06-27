function joker_add(jKey)
    if type(jKey) == 'string' then
        local j = SMODS.create_card({
            key = jKey,
        })

        j:add_to_deck()
        G.jokers:emplace(j)
    end
end

-- Consumable sibling of joker_add. SMODS.create_card resolves the area to G.consumeables
-- for a center whose `.consumeable` flag is set, so no explicit area arg is needed.
function consumable_add(cKey)
    if type(cKey) == 'string' then
        local c = SMODS.create_card({
            key = cKey,
        })

        c:add_to_deck()
        G.consumeables:emplace(c)
    end
end

function PB_UTIL.register_items(items, folder)
    for i = 1, #items do
        SMODS.load_file("content/" .. folder .. "/" .. items[i] .. ".lua")()
    end
end

-- True in every state where a HAND-TARGETING consumable may be used: normal hand-select PLUS the
-- booster-pack states where your hand is shown and highlightable (Tarot / Spectral / Planet packs
-- and the generic SMODS modded-pack state -- e.g. Cryptid's Anarkana). This MIRRORS the base
-- engine's own state list in Card:can_use_consumeable (card.lua). A consumable that hard-codes only
-- G.STATES.SELECTING_HAND greys out mid-pack even though the cards are right there -- which is the
-- bug the Torch/Arrow/Bone Meal/TNT/Firework `can_use` checks must avoid.
function PB_UTIL.hand_consumable_state()
    local S = G and G.STATES
    if not S then return false end
    return G.STATE == S.SELECTING_HAND
        or G.STATE == S.TAROT_PACK
        or G.STATE == S.SPECTRAL_PACK
        or G.STATE == S.PLANET_PACK
        or (S.SMODS_BOOSTER_OPENED ~= nil and G.STATE == S.SMODS_BOOSTER_OPENED)
end

-- Swap the open overlay's CONTENT in place, WITHOUT the fly-in slide, the room jiggle, or the
-- cursor-context-layer re-push that G.FUNCS.overlay_menu performs on every call. This is what
-- makes our modals (Base <-> Crafting Table <-> Furnace, and post-action refreshes) update in
-- place instead of "disappearing and flying back in from below" each time a button is clicked.
--
-- vs G.FUNCS.overlay_menu (button_callbacks.lua:1344): that sets offset.y = 10 then eases it to 0
-- (the slide), bumps G.ROOM.jiggle (the shake), and calls mod_cursor_context_layer (push). Here we
-- build the UIBox already at offset 0 and skip the jiggle + layer push -- the layer was pushed by
-- the FIRST overlay_menu open and is popped by the eventual exit_overlay_menu, so transitions must
-- NOT push again (that would leak the cursor layer).
--
-- NOTE: :remove() here does NOT run the exit_overlay_menu wraps (those are on the FUNC, not on
-- UIBox:remove), so it does NOT credit crafting tiles / reconcile the loadout. Callers that hold
-- live CardAreas (the crafting grid) MUST tear them down before calling this; the Base and the
-- furnace destination rebuild their own fresh areas. Falls back to a normal fly-in open when no
-- overlay is currently up (e.g. first click of "Your Base" from the hotbar).
function PB_UTIL.refresh_overlay(definition)
    if not definition then return end
    if not G.OVERLAY_MENU then
        G.FUNCS.overlay_menu { definition = definition }
        return
    end
    G.OVERLAY_MENU:remove()
    G.CONTROLLER.locks.frame_set = true
    G.CONTROLLER.locks.frame = true
    G.CONTROLLER.cursor_down.target = nil
    G.OVERLAY_MENU = UIBox {
        definition = definition,
        config = { align = 'cm', offset = { x = 0, y = 0 }, major = G.ROOM_ATTACH, bond = 'Weak' },
    }
    G.OVERLAY_MENU:align_to_major()
end

function PB_UTIL.load_blinds(items)
    sendDebugMessage("Loading Blinds...", 'BalaCraft')
    for i = 1, #items do
        local status, err = pcall(function()
            return NFS.load(SMODS.current_mod.path .. 'content/blinds/' .. items[i] .. '.lua')()
        end)
        sendDebugMessage("Loaded blind: " .. items[i], 'BalaCraft')

        if not status then
            error(items[i] .. ": " .. err)
        end
    end
    sendDebugMessage("", 'BalaCraft')

    SMODS.Atlas(
        {
            key = 'blinds',
            path = 'blinds.png',
            px = 34,
            py = 34,
            frames = 21,
            atlas_table = 'ANIMATION_ATLAS'
        }
    )

    -- Reskin the two vanilla NON-boss blinds as environments: Small Blind -> "Night" (surface),
    -- Big Blind -> "Cave" (underground). They stay mechanically vanilla (no debuff, skippable, same
    -- chip mult / dollars); only the displayed SPRITE + NAME change, and the drop pool keys off the
    -- environment (utilities/resources.lua PB_UTIL.blind_location -> grant_blind_drop).
    --   * SPRITE via take_ownership: re-points atlas/pos to the Night/Cave rows of the shared
    --     'blinds' sheet. That sheet is an ANIMATION atlas (each ROW y is one blind's 21-frame
    --     strip; pos.x = the start frame), so Night/Cave live on their own appended rows y=15/y=16
    --     (built by assets/gen_env_blinds.py). SMODS re-applies this on every re-inject, so it
    --     survives init_item_prototypes.
    --   * NAME via an init_localization wrap (NOT loc_txt): we must NOT change the blind's internal
    --     `name` -- Blind:get_type() keys on name == "Small/Big Blind", so renaming it would flip the
    --     blind to a 'Boss' (breaking chip mults, skip tags, the set_next_blind_mult wrapper below,
    --     and biomes.lua's background check). The displayed name is a localization lookup by key, so
    --     overwriting descriptions.Blind.bl_small/bl_big .name changes the label only. init_localization
    --     runs AFTER mod files (SMODS injectItems) and re-runs on every prototype rebuild, so we wrap
    --     it to re-apply the override each time rather than setting it once here (which would be wiped).
    if SMODS and SMODS.Blind and SMODS.Blind.take_ownership then
        pcall(function()
            SMODS.Blind:take_ownership('small', { atlas = 'blinds', pos = { x = 0, y = 15 } }, true)
            SMODS.Blind:take_ownership('big',   { atlas = 'blinds', pos = { x = 0, y = 16 } }, true)
        end)
    end
    if not PB_UTIL._env_blind_loc_wrapped and type(init_localization) == 'function' then
        PB_UTIL._env_blind_loc_wrapped = true
        local _init_localization = init_localization
        function init_localization()
            _init_localization()
            local d = G.localization and G.localization.descriptions and G.localization.descriptions.Blind
            if d then
                if d.bl_small then d.bl_small.name = 'Night'; d.bl_small.name_parsed = nil end
                if d.bl_big   then d.bl_big.name   = 'Cave';  d.bl_big.name_parsed   = nil end
            end
        end
    end

    -- Shared "next ante's blind is X..." mechanism (Slime, Magma Cube, Zombie Pigman).
    -- A defeated boss stores a pending per-type multiplier via PB_UTIL.set_next_blind_mult;
    -- this wrapper scales the matching ante's Small/Big blind requirement, then clears
    -- consumed entries. Installed once. (Same technique as the Blind:defeat wrap in resources.lua.)
    if not PB_UTIL._blind_setblind_wrapped then
        PB_UTIL._blind_setblind_wrapped = true
        local _set_blind = Blind.set_blind
        function Blind:set_blind(blind, reset, silent)
            _set_blind(self, blind, reset, silent)
            if reset or not blind or not blind.name or blind.name == '' or self.disabled then return end
            local spec = G.GAME and G.GAME.balacraft_next_blind
            local ante = G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante
            if not spec or not ante then return end
            if ante > spec.ante then
                G.GAME.balacraft_next_blind = nil -- stale, never consumed
                return
            end
            if ante ~= spec.ante then return end
            local factor = spec[self:get_type()] -- 'Small' / 'Big' / 'Boss'
            if factor and type(self.chips) ~= 'table' then
                self.chips = self.chips * factor
                self.chip_text = number_format(self.chips)
                spec[self:get_type()] = nil
                if not spec.Small and not spec.Big and not spec.Boss then
                    G.GAME.balacraft_next_blind = nil
                end
            end
        end
    end
end

-- Queue a multiplier for a future ante's blind requirement.
-- spec = { ante = <number>, Small = <factor>, Big = <factor> } (factors optional per type).
-- Lives on G.GAME so it auto-saves / auto-resets per run (no custom save code).
function PB_UTIL.set_next_blind_mult(spec)
    if G.GAME then G.GAME.balacraft_next_blind = spec end
end

-- PB_UTIL.select_random_card = function()
--     if not G.GAME.blind.disabled then
--         local any_selected = nil
--         local _cards = {}
        
--         for k, v in ipairs(G.hand.cards) do
--             _cards[#_cards+1] = v
--         end
        
--         if G.hand.cards[1] then 
--             local selected_card, card_key = pseudorandom_element(_cards, pseudoseed(G.GAME.blind.name))
--             G.hand:add_to_highlighted(selected_card, true)
--             selected_card.ability.debuff_triggered = true
--             table.remove(_cards, card_key)
--             any_selected = true
--             play_sound('card1', 1)
--         end
--     end
-- end

PB_UTIL.drowned_effect = function(e, hook)
    stop_use()
    G.CONTROLLER.interrupt.focus = true
    G.CONTROLLER:save_cardarea_focus('hand')

    for k, v in ipairs(G.playing_cards) do
        v.ability.forced_selection = nil
    end

    -- Store the initially highlighted cards to track what's being discarded
    local initially_highlighted = {}
    for _, card in ipairs(G.hand.highlighted) do
        table.insert(initially_highlighted, card)
    end

    if G.CONTROLLER.focused.target and G.CONTROLLER.focused.target.area == G.hand then G.card_area_focus_reset = {area = G.hand, rank = G.CONTROLLER.focused.target.rank} end
    local highlighted_count = math.min(#G.hand.highlighted, G.discard.config.card_limit - #G.play.cards)
    if highlighted_count > 0 then 
        update_hand_text({immediate = true, nopulse = true, delay = 0}, {mult = 0, chips = 0, level = '', handname = ''})
        table.sort(G.hand.highlighted, function(a,b) return a.T.x < b.T.x end)
        inc_career_stat('c_cards_discarded', highlighted_count)
        SMODS.calculate_context({pre_discard = true, full_hand = G.hand.highlighted, hook = hook})
        
        -- TARGET: pre_discard
        local cards = {}
        local destroyed_cards = {}
        for i=1, highlighted_count do
            G.hand.highlighted[i]:calculate_seal({discard = true})
            local removed = false
            local effects = {}
            SMODS.calculate_context({discard = true, other_card =  G.hand.highlighted[i], full_hand = G.hand.highlighted}, effects)
            SMODS.trigger_effects(effects)
            for _, eval in pairs(effects) do
                if type(eval) == 'table' then
                    for key, eval2 in pairs(eval) do
                        if key == 'remove' or (type(eval2) == 'table' and eval2.remove) then removed = true end
                    end
                end
            end
            table.insert(cards, G.hand.highlighted[i])
            if removed then
                destroyed_cards[#destroyed_cards + 1] = G.hand.highlighted[i]
                if SMODS.shatters(G.hand.highlighted[i]) then
                    G.hand.highlighted[i]:shatter()
                else
                    G.hand.highlighted[i]:start_dissolve()
                end
            else 
                G.hand.highlighted[i].ability.discarded = true
                draw_card(G.hand, G.discard, i*100/highlighted_count, 'down', false, G.hand.highlighted[i])
            end
        end

        -- context.remove_playing_cards from discard
        if destroyed_cards[1] then
            SMODS.calculate_context({remove_playing_cards = true, removed = destroyed_cards})
        end
        
        -- TARGET: effects after cards destroyed in discard

        G.GAME.round_scores.cards_discarded.amt = G.GAME.round_scores.cards_discarded.amt + #cards
        check_for_unlock({type = 'discard_custom', cards = cards})
        if not hook then
            if G.GAME.modifiers.discard_cost then
                ease_dollars(-G.GAME.modifiers.discard_cost)
            end
            -- ease_discard(-1)
            -- G.GAME.current_round.discards_used = G.GAME.current_round.discards_used + 1
            -- G.STATE = G.STATES.DRAW_TO_HAND
            -- G.E_MANAGER:add_event(Event({
            --     trigger = 'immediate',
            --     func = function()
            --         G.STATE_COMPLETE = false
            --         return true
            --     end
            -- }))
        end
        
        G.hand:unhighlight_all()
    end

    -- Select a random card from the remaining cards in hand
    local selected_card, card_key = nil, nil
    local remaining_cards = {}
    
    -- Create a list of cards that weren't discarded in the first step
    for _, card in ipairs(G.hand.cards) do
        local was_discarded = false
        for _, discarded_card in ipairs(initially_highlighted) do
            if card == discarded_card then
                was_discarded = true
                break
            end
        end
        if not was_discarded then
            table.insert(remaining_cards, card)
        end
    end
    
    if #remaining_cards > 0 then 
        selected_card, card_key = pseudorandom_element(remaining_cards, pseudoseed(G.GAME.blind.name))
        G.hand:add_to_highlighted(selected_card, true)
        play_sound('card1', 1)
    end

    stop_use()
    G.CONTROLLER.interrupt.focus = true
    G.CONTROLLER:save_cardarea_focus('hand')

    for k, v in ipairs(G.playing_cards) do
        v.ability.forced_selection = nil
    end

    if G.CONTROLLER.focused.target and G.CONTROLLER.focused.target.area == G.hand then G.card_area_focus_reset = {area = G.hand, rank = G.CONTROLLER.focused.target.rank} end
    local highlighted_count = math.min(#G.hand.highlighted, G.discard.config.card_limit - #G.play.cards)
    if highlighted_count > 0 then 
        update_hand_text({immediate = true, nopulse = true, delay = 0}, {mult = 0, chips = 0, level = '', handname = ''})
        table.sort(G.hand.highlighted, function(a,b) return a.T.x < b.T.x end)
        inc_career_stat('c_cards_discarded', highlighted_count)
        SMODS.calculate_context({pre_discard = true, full_hand = G.hand.highlighted, hook = hook})
        
        -- TARGET: pre_discard
        local cards = {}
        local destroyed_cards = {}
        for i=1, highlighted_count do
            G.hand.highlighted[i]:calculate_seal({discard = true})
            local removed = false
            local effects = {}
            SMODS.calculate_context({discard = true, other_card =  G.hand.highlighted[i], full_hand = G.hand.highlighted}, effects)
            SMODS.trigger_effects(effects)
            for _, eval in pairs(effects) do
                if type(eval) == 'table' then
                    for key, eval2 in pairs(eval) do
                        if key == 'remove' or (type(eval2) == 'table' and eval2.remove) then removed = true end
                    end
                end
            end
            table.insert(cards, G.hand.highlighted[i])
            if removed then
                destroyed_cards[#destroyed_cards + 1] = G.hand.highlighted[i]
                if SMODS.shatters(G.hand.highlighted[i]) then
                    G.hand.highlighted[i]:shatter()
                else
                    G.hand.highlighted[i]:start_dissolve()
                end
            else 
                G.hand.highlighted[i].ability.discarded = true
                draw_card(G.hand, G.discard, i*100/highlighted_count, 'down', false, G.hand.highlighted[i])
            end
        end

        -- context.remove_playing_cards from discard
        if destroyed_cards[1] then
            SMODS.calculate_context({remove_playing_cards = true, removed = destroyed_cards})
        end
        
        -- TARGET: effects after cards destroyed in discard

        G.GAME.round_scores.cards_discarded.amt = G.GAME.round_scores.cards_discarded.amt + #cards
        check_for_unlock({type = 'discard_custom', cards = cards})
        if not hook then
            if G.GAME.modifiers.discard_cost then
                ease_dollars(-G.GAME.modifiers.discard_cost)
            end
            ease_discard(-1)
            G.GAME.current_round.discards_used = G.GAME.current_round.discards_used + 1
            G.STATE = G.STATES.DRAW_TO_HAND
            G.E_MANAGER:add_event(Event({
                trigger = 'immediate',
                func = function()
                    G.STATE_COMPLETE = false
                    return true
                end
            }))
        end
        G.hand:unhighlight_all()
    end
end

-- ── Resource booster packs ────────────────────────────────────────────────
-- Tier-weighted distinct-ore sampling shared by all three Loot Chest sizes.
-- tier 1 : 2 : 3 : 4 appearance weight = 4 : 2 : 1 : 1, so common ores are favored and
-- bigger packs (more cards) improve the odds of surfacing a rare ore (Netherite = tier 4).
local RESPACK_TIER_WEIGHT = { [1] = 4, [2] = 2, [3] = 1, [4] = 1 }

-- Sample `n` DISTINCT gathered ores, weighted by tier, run-seeded deterministic.
-- Returns a list of ore ids. Only kind == 'gathered' ores are eligible (all gathered
-- ores); crafted resources (e.g. sticks) are excluded, matching the drop-pool guard.
function PB_UTIL.sample_pack_ores(n)
    local remaining = {}
    for _, r in ipairs(PB_UTIL.RESOURCES) do
        if r.kind == 'gathered' and r.drop_class == 'ore' then
            remaining[#remaining + 1] = { id = r.id, weight = RESPACK_TIER_WEIGHT[r.tier] or 1 }
        end
    end
    local picked = {}
    n = math.min(n or 1, #remaining)
    for _ = 1, n do
        -- Expand remaining ores into a weighted index pool, draw one, drop that ore.
        local pool = {}
        for idx, e in ipairs(remaining) do
            for _ = 1, e.weight do pool[#pool + 1] = idx end
        end
        local chosen = pseudorandom_element(pool, pseudoseed('bc_respack'))
        picked[#picked + 1] = remaining[chosen].id
        table.remove(remaining, chosen)
    end
    return picked
end

-- create_card body shared by the three resource boosters. Samples the pack's ore
-- set once (cached on the opened booster `card`), then returns the i-th ore card.
-- `n` is the booster's nominal size (config.extra); the engine can request more
-- cards when a booster_size_mod is active (card.lua Card:open), so size the sample
-- to the same total. Sampling clamps to the number of distinct gathered ores; if a
-- modifier pushes the count past that, overflow slots fall back to the first ore (no crash).
function PB_UTIL.create_resource_pack_card(card, i, n)
    if not card.balacraft_pack_ores then
        local size_mod = (G.GAME and G.GAME.modifiers and G.GAME.modifiers.booster_size_mod) or 0
        card.balacraft_pack_ores = PB_UTIL.sample_pack_ores((n or 1) + size_mod)
    end
    local id = card.balacraft_pack_ores[i]
        or card.balacraft_pack_ores[1]
        or PB_UTIL.RESOURCES[1].id
    return create_card('balacraft_resource', G.pack_cards, nil, nil, true, true,
        'c_balacraft_res_' .. id, 'bc_respack')
end

-- ── Food booster packs ────────────────────────────────────────────────────
-- Same tier-weighted distinct sampling as the resource packs (4:2:1), so cheap
-- foods are common and a rare cooked porkchop is a treat in bigger packs.
local FOODPACK_TIER_WEIGHT = { [1] = 4, [2] = 2, [3] = 1 }

function PB_UTIL.sample_pack_foods(n)
    local remaining = {}
    for _, f in ipairs(PB_UTIL.FOODS or {}) do
        remaining[#remaining + 1] = { id = f.id, weight = FOODPACK_TIER_WEIGHT[f.tier] or 1 }
    end
    local picked = {}
    n = math.min(n or 1, #remaining)
    for _ = 1, n do
        local pool = {}
        for idx, e in ipairs(remaining) do
            for _ = 1, e.weight do pool[#pool + 1] = idx end
        end
        local chosen = pseudorandom_element(pool, pseudoseed('bc_foodpack'))
        picked[#picked + 1] = remaining[chosen].id
        table.remove(remaining, chosen)
    end
    return picked
end

-- create_card body shared by the three food boosters (mirror of the resource version).
function PB_UTIL.create_food_pack_card(card, i, n)
    if not card.balacraft_pack_foods then
        local size_mod = (G.GAME and G.GAME.modifiers and G.GAME.modifiers.booster_size_mod) or 0
        card.balacraft_pack_foods = PB_UTIL.sample_pack_foods((n or 1) + size_mod)
    end
    local id = card.balacraft_pack_foods[i]
        or card.balacraft_pack_foods[1]
        or PB_UTIL.FOODS[1].id
    return create_card('balacraft_food', G.pack_cards, nil, nil, true, true,
        'c_balacraft_food_' .. id, 'bc_foodpack')
end

-- ── Enchanting booster pack ────────────────────────────────────────────────
-- Tier-weighted distinct sampling over the 9 enchanting books. Normally favours low tiers
-- (4:2:1); once the upgraded voucher (Sorcerer's Tome) is owned, the weights flip to favour
-- HIGH tiers (1:2:4). Runs only when enhancements are loaded (PB_UTIL.ENCHANT_BOOKS exists).
function PB_UTIL.sample_pack_books(n)
    local boosted = G.GAME and G.GAME.used_vouchers
        and G.GAME.used_vouchers['v_balacraft_sorcerers_tome'] == true
    local TW = boosted and { [1] = 1, [2] = 2, [3] = 4 } or { [1] = 4, [2] = 2, [3] = 1 }
    local remaining = {}
    for _, b in ipairs(PB_UTIL.ENCHANT_BOOKS or {}) do
        remaining[#remaining + 1] = { id = b.id, weight = TW[b.tier] or 1 }
    end
    local picked = {}
    n = math.min(n or 1, #remaining)
    for _ = 1, n do
        local pool = {}
        for idx, e in ipairs(remaining) do
            for _ = 1, e.weight do pool[#pool + 1] = idx end
        end
        local chosen = pseudorandom_element(pool, pseudoseed('bc_enchantpack'))
        picked[#picked + 1] = remaining[chosen].id
        table.remove(remaining, chosen)
    end
    return picked
end

-- create_card body for the Enchanting booster (mirror of the resource/food versions).
function PB_UTIL.create_enchant_pack_card(card, i, n)
    if not card.balacraft_pack_books then
        local size_mod = (G.GAME and G.GAME.modifiers and G.GAME.modifiers.booster_size_mod) or 0
        card.balacraft_pack_books = PB_UTIL.sample_pack_books((n or 1) + size_mod)
    end
    local id = card.balacraft_pack_books[i]
        or card.balacraft_pack_books[1]
        or (PB_UTIL.ENCHANT_BOOKS[1] and PB_UTIL.ENCHANT_BOOKS[1].id)
    return create_card('balacraft_enchant', G.pack_cards, nil, nil, true, true,
        'c_balacraft_enchant_' .. id, 'bc_enchantpack')
end
