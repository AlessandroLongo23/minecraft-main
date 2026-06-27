-- DEV/TEST deck: replaces the old Overworld deck. On run start it force-grants a sandbox
-- loadout so content (jokers, vouchers, enchanting, resources) can be exercised immediately
-- without grinding a full run. The "what to force" knobs are the six locals below — edit them
-- like you'd edit any deck; the grant routine underneath doesn't need touching.
--
-- Always visible (unlocked + discovered). Remove 'test' from PB_UTIL.ENABLED_DECKS before any
-- public release. See docs/superpowers/specs/2026-06-19-test-deck-design.md.

-- ── EDIT THESE TO PICK WHAT TO FORCE ──────────────────────────────────────────
local DOLLARS     = 999                                    -- extra starting cash (0 = skip)
local LEVEL       = 100                                    -- starting XP level (0 = skip)
local RESOURCES   = 99                                     -- set EVERY resource id to this (0 = skip)
local JOKERS      = {}                                     -- joker keys, e.g. 'j_balacraft_elytra'
local CONSUMABLES = {
    'c_balacraft_enchant_sharpness_3',
    'c_balacraft_enchant_durability_3',
    'c_balacraft_enchant_fortune_3',
    'c_balacraft_tool_sword_diamond'
}  -- consumable keys (the Sharpness, Durability, and Fortune books)
local VOUCHERS    = {                                      -- vouchers to force-redeem
    'v_balacraft_enchanting_table',
    'v_balacraft_sorcerers_tome',
    -- 'v_balacraft_nether_portal',  -- dimension portals: uncomment to test dimensions
    -- 'v_balacraft_end_portal',
}
local CARD_MOD    = { seal = nil, enhancement = nil, edition = nil, count = 0 } -- stamp N starting cards
-- ──────────────────────────────────────────────────────────────────────────────

-- Reuse the existing Overworld art so no new sprite is needed.
SMODS.Atlas {
    key = 'testDeck',
    path = 'OverworldDeck.png',
    px = 71,
    py = 95,
}

SMODS.Back {
    name = 'Test',
    key = 'test',
    atlas = 'testDeck',
    pos = { x = 0, y = 0 },
    unlocked = true,
    discovered = true,
    loc_txt = {
        name = 'Test Deck',
        text = {
            '{C:attention}DEV{} sandbox: start loaded',
            'with cash, resources,',
            'vouchers and an enchant book.',
        },
    },

    apply = function(self)
        G.E_MANAGER:add_event(Event({
            func = function()
                -- Money
                if DOLLARS ~= 0 then ease_dollars(DOLLARS) end

                -- XP level: set the plain-int level field directly (no set-funnel exists;
                -- spend_level mutates this same field). Clear banked XP for a clean bar.
                if LEVEL ~= 0 then
                    G.GAME.balacraft = G.GAME.balacraft or {}
                    G.GAME.balacraft.xp_level = LEVEL
                    G.GAME.balacraft.xp = 0
                end

                -- Resources: every id (gathered + crafted — it's a sandbox). PB_UTIL.RESOURCES
                -- is an ARRAY of {id=...} defs, so iterate with ipairs and read r.id (matching
                -- the init_game_object seeding in utilities/resources.lua).
                if RESOURCES ~= 0 and PB_UTIL.RESOURCES then
                    for _, r in ipairs(PB_UTIL.RESOURCES) do
                        PB_UTIL.add_resource(r.id, RESOURCES)
                    end
                end

                -- Jokers
                for _, k in ipairs(JOKERS) do
                    if G.P_CENTERS[k] then joker_add(k) end
                end

                -- Vouchers: force-redeem using the base-game deck pattern
                -- (lovely/dump/back.lua:226). Marks it used + applies its run effect.
                -- MUST run before consumables: vouchers that grant consumable slots
                -- (Enchanting Table, Sorcerer's Tome) raise G.consumeables.config.card_limit
                -- from a *deferred* event queued inside redeem(), so the slots don't exist yet
                -- when this loop finishes.
                for _, k in ipairs(VOUCHERS) do
                    local center = G.P_CENTERS[k]
                    if center then
                        G.GAME.used_vouchers[k] = true
                        G.GAME.starting_voucher_count = (G.GAME.starting_voucher_count or 0) + 1
                        Card.apply_to_run(nil, center)
                    end
                end

                -- Consumables: deferred into its own event so it runs AFTER the voucher
                -- slot-bump events above have processed (those were queued mid-redeem, so they
                -- sit ahead of this one in the immediate-event queue). Without this, the cards
                -- are added while card_limit is still the base 2 and the extras get dropped.
                G.E_MANAGER:add_event(Event({
                    func = function()
                        for _, k in ipairs(CONSUMABLES) do
                            if G.P_CENTERS[k] then consumable_add(k) end
                        end
                        return true
                    end,
                }))

                -- Card mods: stamp the first N starting cards (off by default; alters deck comp).
                if (CARD_MOD.count or 0) > 0 and G.playing_cards then
                    local n = 0
                    for _, card in ipairs(G.playing_cards) do
                        if n >= CARD_MOD.count then break end
                        if CARD_MOD.enhancement and G.P_CENTERS[CARD_MOD.enhancement] then
                            card:set_ability(G.P_CENTERS[CARD_MOD.enhancement])
                        end
                        if CARD_MOD.seal then card:set_seal(CARD_MOD.seal, true, true) end
                        if CARD_MOD.edition then card:set_edition({ [CARD_MOD.edition] = true }, nil, true) end
                        n = n + 1
                    end
                end

                return true
            end,
        }))
    end,
}
