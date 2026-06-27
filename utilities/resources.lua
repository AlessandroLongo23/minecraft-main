-- Resource state + helpers

-- Seed per-run resource counts on G.GAME via an init_game_object wrapper.
-- Runs fresh for every new run, so counts auto-reset; plain integers => auto-saved.
local _init_game_object = Game.init_game_object
function Game:init_game_object()
    local t = _init_game_object(self)
    t.balacraft = t.balacraft or {}
    t.balacraft.resources = {}
    for _, r in ipairs(PB_UTIL.RESOURCES or {}) do
        t.balacraft.resources[r.id] = 0
    end
    -- Which side the consumable-area toggle is showing ('vanilla' = Tarot/Planet/Spectral |
    -- 'minecraft' = the 2 MC consumable slots). Plain string on G.GAME => auto-saved within a
    -- run, auto-reset for a new run (same hybrid model as the counts above). 'remember last view'.
    t.balacraft.view_mode = 'vanilla'
    -- Tool consumable state (same hybrid model: plain numbers => auto-saved/reset per run).
    --   sword_xmult     : multiplicative scoring buff for the CURRENT blind (reset each blind
    --                     via reset_game_globals below; applied via the lovely.toml patch).
    --   sword_exp       : top-tier swords' Mult exponent (1 = no-op).
    --   pending_shovel  : +$N, paid out on the NEXT blind defeated.
    --   axe_chips/axe_xmult : the Axe's WEAPON-mode buff for the CURRENT blind (hybrid: a flat
    --                     +Chips AND an xMult, applied together via the same lovely.toml patch as
    --                     the sword; reset each blind). The Axe arms these only when used WITHOUT a
    --                     wood card selected; with wood selected it harvests wood instead (no buff).
    t.balacraft.sword_xmult     = 1
    t.balacraft.sword_exp       = 1   -- top-tier swords' Mult exponent (1 = no-op)
    t.balacraft.pending_shovel  = 0
    t.balacraft.axe_chips       = 0   -- +Chips this blind (Axe weapon mode; 0 = no-op)
    t.balacraft.axe_xmult       = 1   -- xMult this blind (Axe weapon mode; 1 = no-op)
    -- Furnace fuel buffer (charges). Loading 1 coal -> +4, 1 wood -> +1; each smelt spends 1.
    -- Plain integer on G.GAME => auto-saved within a run, auto-reset per run (no custom save/load).
    t.balacraft.furnace_fuel    = 0
    -- Base stations the player has CRAFTED this run (Furnace, ...). A station's Base slot is inert
    -- until its id is set true here (via PB_UTIL.build_station). Plain table => auto-saved/reset per run.
    t.balacraft.stations        = {}
    -- Per-blind, per-TYPE usage lock: at most one sword / one pickaxe / one shovel may be
    -- used each blind (mixing types is fine). Keyed by tool type ('sword'|'pickaxe'|'shovel');
    -- set in the consumable's use(), cleared each blind by reset_game_globals below. Plain
    -- table on G.GAME => auto-saved within a run, auto-reset per run. No custom save/load.
    t.balacraft.tool_type_used  = {}
    -- Resources granted on the most-recent blind defeat, for the Cash Out summary rows
    -- (cashout_ui.lua). Plain table on G.GAME => auto-saved/reset per run; overwritten fresh
    -- at the top of grant_blind_drop each blind. No custom save/load.
    t.balacraft.last_drop       = {}
    -- Villager Trading per-shop state (plain values -> auto-saved within a run, auto-reset per
    -- run). Offers are (re)seeded by the shop/reroll hooks in utilities/villager.lua.
    t.balacraft.villager_offers       = {}
    t.balacraft.villager_reroll_index = 0
    t.balacraft.villager_profession   = nil   -- chosen per shop visit (seed_villager_offers)
    t.balacraft.villager_reroll_cost  = 1     -- Emerald cost of the next villager reroll (rises +1 each)
    t.balacraft._villager_seeded      = false
    -- Shop view toggle (vanilla shop <-> villager), shared shop footprint. Reset to 'shop' per
    -- shop visit by villager_ui.lua's per-frame driver; defaulted here for a clean run start.
    t.balacraft.shop_view_mode        = 'shop'
    -- Unified Minecraft inventory (capacity model in utilities/inventory_model.lua). `stored` holds
    -- serialized (card:save()) Minecraft consumables kept in the inventory (rendered as icons). The
    -- two EQUIPPED slots are the live G.bc_mc_consumeables CardArea, which the base save system
    -- persists on its own (save_run iterates every CardArea in G), so they need no mirror here.
    -- Plain table on G.GAME => auto-saved within a run, auto-reset per run (no custom save/load).
    t.balacraft.inv = { stored = {} }
    return t
end

-- The base game calls every mod's reset_game_globals(run_start) at end of round
-- (functions/state_events.lua ~220) and at run start. We use it to clear the per-blind
-- sword buff so it never carries into the next blind. The pending pickaxe/shovel one-shots
-- are deliberately NOT cleared here: cash-out (Blind:defeat -> grant_blind_drop) runs AFTER
-- this reset, so clearing them now would swallow an armed bonus before it ever lands.
local _reset_game_globals = SMODS.current_mod.reset_game_globals
function SMODS.current_mod.reset_game_globals(run_start)
    if _reset_game_globals then _reset_game_globals(run_start) end
    if G.GAME and G.GAME.balacraft then
        G.GAME.balacraft.sword_xmult = 1
        G.GAME.balacraft.sword_exp = 1   -- top-tier swords' Mult exponent (default 1 = no-op)
        G.GAME.balacraft.axe_chips = 0   -- Axe weapon-mode +Chips (default 0 = no-op)
        G.GAME.balacraft.axe_xmult = 1   -- Axe weapon-mode xMult (default 1 = no-op)
        -- New blind: clear the per-type usage lock so one tool of each type can be used again.
        G.GAME.balacraft.tool_type_used = {}
    end
    -- Clear the once-per-blind lock on every persistent tool card so each tool can be used
    -- again next blind (tools are multi-use; see content/tools/tool_consumabletype.lua). Tools now
    -- live in the MC consumable area, so scan it (and the vanilla area defensively).
    if PB_UTIL.each_tool_card then
        PB_UTIL.each_tool_card(function(c)
            if c.ability.extra then c.ability.extra.used_this_blind = false end
        end)
    end
end

-- Sword scoring juice: make the per-blind sword X-Mult animate like a joker adding mult.
-- Called from the lovely.toml final_scoring_step patch (guarded), once per scored hand,
-- right after sword_xmult is folded into the hand mult. card_eval_status_text queues onto
-- G.E_MANAGER, so the "Xn Mult" pop + juice + multhit2 sound slot into the scoring timeline
-- (after the jokers) -- the exact path the base game uses for a joker's x_mult.
-- Only one sword can be active per blind (the per-type lock), so this is one pop per hand.
function PB_UTIL.sword_score_message()
    local bc = G.GAME and G.GAME.balacraft
    if not bc then return end
    local has_x = bc.sword_xmult and bc.sword_xmult ~= 1
    local has_e = bc.sword_exp and bc.sword_exp ~= 1
    if not has_x and not has_e then return end
    -- Find the sword card that was used this blind (its center key contains 'tool_sword'). Tools
    -- live in the MC consumable area now; each_tool_card scans it (and the vanilla area defensively).
    local sword_card
    if PB_UTIL.each_tool_card then
        PB_UTIL.each_tool_card(function(c)
            if sword_card then return end
            local center = c.config and c.config.center
            local e = c.ability and c.ability.extra
            if center and center.key and string.find(center.key, 'tool_sword', 1, true)
                and e and e.used_this_blind then
                sword_card = c
            end
        end)
    end
    -- Fall back to the deck when the sword broke (e.g. Wooden Sword, 1 use) so the buff
    -- still pops visibly even though its card is gone.
    local card = sword_card or G.deck
    if not card or not card_eval_status_text then return end
    -- Flat sword: eval_type 'x_mult' => "Xn Mult" text in G.C.XMULT + multhit2 + card:juice_up,
    -- identical to a joker's x_mult pop. (Only one sword can be used per blind, so x and exp are
    -- mutually exclusive, but pop whichever is active.)
    if has_x then
        card_eval_status_text(card, 'x_mult', bc.sword_xmult)
    end
    -- Exponent sword: there's no base eval_type for "^n", so use the generic message override.
    if has_e then
        card_eval_status_text(card, 'extra', nil, nil, nil,
            { message = '^' .. bc.sword_exp .. ' Mult', colour = G.C.XMULT, sound = 'multhit2', volume = 0.7 })
    end
end

-- Axe weapon-mode scoring juice (parallel to sword_score_message): pop the +Chips then the xMult
-- so the hybrid weapon buff animates like jokers. Called from the same lovely.toml scoring patch,
-- right after axe_chips/axe_xmult are folded into the hand. Only one axe can be used per blind.
function PB_UTIL.axe_score_message()
    local bc = G.GAME and G.GAME.balacraft
    if not bc then return end
    local has_c = bc.axe_chips and bc.axe_chips ~= 0
    local has_x = bc.axe_xmult and bc.axe_xmult ~= 1
    if not has_c and not has_x then return end
    -- Find the axe card used this blind (center key contains 'tool_axe'); fall back to the deck
    -- if it already broke, so the buff still pops.
    local axe_card
    if PB_UTIL.each_tool_card then
        PB_UTIL.each_tool_card(function(c)
            if axe_card then return end
            local center = c.config and c.config.center
            local e = c.ability and c.ability.extra
            if center and center.key and string.find(center.key, 'tool_axe', 1, true)
                and e and e.used_this_blind then
                axe_card = c
            end
        end)
    end
    local card = axe_card or G.deck
    if not card or not card_eval_status_text then return end
    if has_c then card_eval_status_text(card, 'chips', bc.axe_chips) end
    if has_x then card_eval_status_text(card, 'x_mult', bc.axe_xmult) end
end

-- Defensive accessor: guarantees the table exists before read/write.
local function ensure_store()
    G.GAME.balacraft = G.GAME.balacraft or {}
    G.GAME.balacraft.resources = G.GAME.balacraft.resources or {}
    return G.GAME.balacraft.resources
end

function PB_UTIL.get_resource_count(id)
    return ensure_store()[id] or 0
end

function PB_UTIL.set_resource(id, amount)
    local store = ensure_store()
    local prev = store[id] or 0
    store[id] = math.max(0, math.floor(tonumber(amount) or 0))
    if (prev == 0) ~= (store[id] == 0) then
        G.GAME.balacraft._panel_dirty = true
    end
    return store[id]
end

-- Single mutation funnel. Marks the panel dirty when an ore is first owned (0 -> >0)
-- so the UI can flip it from greyed to active.
--
-- Capacity-aware on ADDITIONS only: the inventory has a real slot cap (utilities/inventory_model.lua),
-- so a positive add is clamped to what actually fits (the rest is lost). Spends (amount < 0) and the
-- pre-run / model-absent paths are never capped, so crafting/smelting still spend exactly as before.
-- Callers that care about loss (drops) compare get_resource_count before/after.
function PB_UTIL.add_resource(id, amount)
    local store = ensure_store()
    local prev = store[id] or 0
    amount = math.floor(tonumber(amount) or 0)
    if amount > 0 and PB_UTIL.resource_addable then
        amount = PB_UTIL.resource_addable(id, amount)
    end
    local new = math.max(0, prev + amount)
    store[id] = new
    if (prev == 0) ~= (new == 0) then
        G.GAME.balacraft._panel_dirty = true
    end
    return new
end

-- Per-blind themed overrides (opt-in). Keyed by blind.name.
-- NOTE: for SMODS boss blinds, blind.name IS the prefixed key (e.g. 'bl_balacraft_creeper'),
-- because SMODS sets a blind center's name to `self.name or self.key` (game_object.lua) and our
-- blinds only define loc_txt.name. (Vanilla small/big blinds use display names like 'Small Blind',
-- but we only key balacraft bosses here, so the lookup matches.) The mod's lovely.toml relies on
-- this same fact (it checks `G.GAME.blind.name == 'bl_balacraft_drowned'`).
-- Anything without an entry uses the tier-roll fallback.
-- Themed ORE drops: REPLACE the ante tier-roll for this blind (list of {id, amount}; the list
-- form lets a blind grant several stacks). Keyed by the prefixed blind name.
PB_UTIL.BLIND_DROPS = {
    bl_balacraft_creeper  = { { id = 'coal', amount = 2 } },
    bl_balacraft_skeleton = { { id = 'raw_iron', amount = 1 } },
    bl_balacraft_zombie   = { { id = 'wood', amount = 2 } },
}

-- Themed MOB drops: granted ADDITIVELY on top of the ore path (so the Spider boss still pays an
-- ore AND drops its string). Keyed by prefixed blind name -> list of {id, amount}. Blinds with no
-- entry instead get the low-rate additive loot roll in grant_mob_drop (covers mobs with no blind,
-- e.g. chicken->feather / gravel->flint). Extended per wave as new mob drops ship.
PB_UTIL.BLIND_MOB_DROPS = {
    bl_balacraft_spider = { { id = 'string', amount = 2 } },
    -- End/Nether progression materials (drop_class='special', so they never appear in the generic
    -- mob loot roll -- only here). Endermen drop the Ender Pearl; Blazes drop the Blaze Powder.
    -- Pearl + Powder craft the Eye of Ender (content/resources/recipes.lua). Defeating these blinds
    -- in the overworld is the bootstrap path to the End; once in a dimension, grant_dimension_drop
    -- (below) also trickles powder in the Nether and pearls in the End.
    bl_balacraft_enderman = { { id = 'ender_pearl',  amount = 1 } },
    bl_balacraft_blaze    = { { id = 'blaze_powder', amount = 1 } },
}

-- Per-ore drop weight from the active biome (default 1 when biomes are off or unbiased).
-- Looked up at call-time so it's inert unless utilities/biomes.lua is loaded.
local function biome_ore_weight(id)
    if not PB_UTIL.current_biome then return 1 end
    local b = PB_UTIL.get_biome and PB_UTIL.get_biome(PB_UTIL.current_biome())
    local w = b and b.resource_bias and b.resource_bias[id]
    return (type(w) == 'number' and w > 0) and w or 1
end

-- Per-mob-drop weight from the active biome (default 1 when biomes are off or unbiased). Mirrors
-- biome_ore_weight: an optional `mob_bias` table on the active biome makes a signature mob material
-- more common (e.g. snowy -> Bone via the Stray). Inert unless utilities/biomes.lua is loaded, so
-- the Night/Cave mob pool works fine with biomes disabled.
local function biome_mob_weight(id)
    if not PB_UTIL.current_biome then return 1 end
    local b = PB_UTIL.get_biome and PB_UTIL.get_biome(PB_UTIL.current_biome())
    local w = b and b.mob_bias and b.mob_bias[id]
    return (type(w) == 'number' and w > 0) and w or 1
end

-- The highest ore tier unlocked at a given ante (canon shared by blind drops + ore blocks):
-- tier 1 from ante 1, tier 2 from ante 3, tier 3 from ante 6, tier 4 (Netherite) from ante 8.
function PB_UTIL.max_ore_tier(ante)
    ante = ante or 1
    return (ante >= 8 and 4) or (ante >= 6 and 3) or (ante >= 3 and 2) or 1
end

-- The Night (surface) / Cave (underground) reskin of the vanilla Small / Big blinds drives an
-- environment-specific drop pool. Detect which via the blind's config key, which stays
-- 'bl_small'/'bl_big' through the reskin (only the displayed name + sprite change -- see
-- utilities/functions.lua). Falls back to get_type(); returns nil for bosses/other blinds, which
-- keep the generic tier-roll. 'surface' = Night, 'cave' = Cave.
function PB_UTIL.blind_location(blind)
    local k = blind and blind.config and blind.config.blind and blind.config.blind.key
    if k == 'bl_small' then return 'surface' end
    if k == 'bl_big'   then return 'cave'    end
    local t = blind and blind.get_type and blind:get_type()
    if t == 'Small' then return 'surface' end
    if t == 'Big'   then return 'cave'    end
    return nil
end

-- Night/Cave drop-pool balance (all tunable). Night guarantees Wood + a chance of one surface ore;
-- Cave is ore-heavy with a chance to roll the highest unlocked tier; MOB_DROP_CHANCE is the per-win
-- odds of an ADDITIVE mob material on top (keeps drops "mostly resources, occasionally mob").
local SURFACE_WOOD_AMOUNT      = 1
local SURFACE_EXTRA_ORE_CHANCE = 0.35
local CAVE_HIGH_TIER_CHANCE    = 0.5
local CAVE_ORE_AMOUNT          = 1
local MOB_DROP_CHANCE          = 0.25
-- Nether/End progression-item drop odds.
local CAVE_OBSIDIAN_CHANCE     = 0.25   -- a Cave (underground) win also yields 1 Obsidian this often
local DIMENSION_MAT_CHANCE     = 0.30   -- any Nether/End win trickles 1 Blaze Powder / Ender Pearl

-- Returns a random ore id of exactly `tier` (run-seeded deterministic). The current biome
-- biases WHICH ore within the tier by repeating favored ids in the draw pool (weight 1 = none).
-- Exposed on PB_UTIL so card_enhancements (Ore-Block spawn), seals, and tags reuse one roll.
function PB_UTIL.random_ore_of_tier(tier, seed_key)
    local pool = {}
    for _, r in ipairs(PB_UTIL.RESOURCES) do
        if r.kind == 'gathered' and r.drop_class == 'ore' and r.tier == tier then
            for _ = 1, biome_ore_weight(r.id) do pool[#pool + 1] = r.id end
        end
    end
    if #pool == 0 then return PB_UTIL.RESOURCES[1].id end
    return pseudorandom_element(pool, pseudoseed(seed_key))
end

-- Sibling of random_ore_of_tier used ONLY by the Ore-Block spawn (utilities/card_enhancements.lua).
-- It draws from the ore-block-eligible set (PB_UTIL.is_oreblock_resource) instead of the raw
-- drop_class=='ore' pool, so it EXCLUDES Sand (no_oreblock) and INCLUDES Obsidian (drop_class
-- 'special', oreblock=true) -- which random_ore_of_tier must never surface (it's mining-only).
-- Same biome biasing; returns nil on an empty tier (spawn_ore_blocks skips a nil pick).
function PB_UTIL.random_oreblock_of_tier(tier, seed_key)
    local pool = {}
    for _, r in ipairs(PB_UTIL.RESOURCES) do
        if PB_UTIL.is_oreblock_resource(r) and r.tier == tier then
            for _ = 1, biome_ore_weight(r.id) do pool[#pool + 1] = r.id end
        end
    end
    if #pool == 0 then return nil end
    return pseudorandom_element(pool, pseudoseed(seed_key))
end

-- Environment-aware sibling of random_ore_of_tier, used ONLY by the Night/Cave blind drops. Cave
-- excludes Wood (no surface trees underground); Night keeps the full tier pool (Wood included).
-- Kept SEPARATE from random_ore_of_tier so the shared ore roll (Ore-Block cards, seals, tags,
-- Fishing Rod) is unaffected. Same biome_ore_weight biasing; safe fallback if a pool empties.
function PB_UTIL.random_ore_of_tier_at(tier, location, seed_key)
    local pool = {}
    for _, r in ipairs(PB_UTIL.RESOURCES) do
        if r.kind == 'gathered' and r.drop_class == 'ore' and r.tier == tier then
            if not (location == 'cave' and r.id == 'wood') then
                for _ = 1, biome_ore_weight(r.id) do pool[#pool + 1] = r.id end
            end
        end
    end
    if #pool == 0 then return PB_UTIL.random_ore_of_tier(tier, seed_key) end
    return pseudorandom_element(pool, pseudoseed(seed_key))
end

-- Grant `amount` of resource `id` AND record it for the Cash Out summary. Merges by id so
-- repeated grants of the same resource accumulate into one entry. All blind-drop grants must
-- route through here (never call add_resource directly in the drop path) so the summary is
-- complete.
local function record_drop(id, amount)
    -- Capacity may swallow part (or all) of the grant -- record only what actually landed, and
    -- tally the remainder so the Cash Out screen can show an "inventory full" note.
    local before = PB_UTIL.get_resource_count(id)
    PB_UTIL.add_resource(id, amount)
    local added = PB_UTIL.get_resource_count(id) - before
    local bc = G.GAME and G.GAME.balacraft
    if not bc then return end
    local lost = (amount or 0) - added
    if lost > 0 then bc.last_drop_lost = (bc.last_drop_lost or 0) + lost end
    if added <= 0 then return end
    bc.last_drop = bc.last_drop or {}
    for _, e in ipairs(bc.last_drop) do
        if e.id == id then
            e.amount = e.amount + added
            return
        end
    end
    bc.last_drop[#bc.last_drop + 1] = { id = id, amount = added }
end

-- All gathered MOB materials unlocked by `max_tier`, as a flat id pool (for the loot roll +
-- Fishing Rod). Tier-gated like ores so feather/flint don't appear before their ante. `location`
-- ('surface'/'cave') filters to mobs droppable there: a row with location 'both' (or unset) is
-- always eligible; a 'cave'-only row (spider_eye, glow_ink_sac) is excluded on the surface. Pass
-- location=nil (e.g. the Fishing Rod) for the unfiltered pool. biome_mob_weight biases the draw.
local function mob_pool(max_tier, location)
    local pool = {}
    for _, r in ipairs(PB_UTIL.RESOURCES) do
        if r.kind == 'gathered' and r.drop_class == 'mob' and (r.tier or 1) <= max_tier then
            local loc = r.location or 'both'
            if location == nil or loc == 'both' or loc == location then
                for _ = 1, biome_mob_weight(r.id) do pool[#pool + 1] = r.id end
            end
        end
    end
    return pool
end

-- Exposed for the Fishing Rod (and any "reel a mob material" effect). Returns a random mob-drop
-- id unlocked at `max_tier`, or nil if none exist yet. Optional `location` gates cave-exclusive
-- drops (nil = unfiltered). Run-seeded deterministic.
function PB_UTIL.random_mob_drop(max_tier, seed_key, location)
    local pool = mob_pool(max_tier or 1, location)
    if #pool == 0 then return nil end
    return pseudorandom_element(pool, pseudoseed(seed_key or 'bc_mobdrop'))
end

-- Additive mob-material grant for a blind win. Themed blinds (BLIND_MOB_DROPS) drop their signature
-- material every time; un-themed blinds get a low-rate roll so mobs without a blind still trickle in.
-- The roll is location-gated so Night yields only surface/shared mobs and Cave can also yield its
-- exclusive drops (spider_eye, glow_ink_sac). Bosses pass nil -> unfiltered, as before.
function PB_UTIL.grant_mob_drop(blind)
    local themed = blind.name and PB_UTIL.BLIND_MOB_DROPS[blind.name]
    if themed then
        for _, d in ipairs(themed) do record_drop(d.id, d.amount) end
        return
    end
    local ante = (G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or 1
    local loc = PB_UTIL.blind_location(blind)
    local key = 'bc_mobloot_' .. ante .. '_' .. tostring(blind.name)
    if pseudorandom(key) < MOB_DROP_CHANCE then
        local id = PB_UTIL.random_mob_drop(PB_UTIL.max_ore_tier(ante), key .. '_pick', loc)
        if id then record_drop(id, 1) end
    end
end

-- Dimension-material trickle: while in the Nether, any win has a chance to drop Blaze Powder;
-- while in the End, a chance to drop Ender Pearl. These (with the Enderman/Blaze themed drops)
-- feed the Eye-of-Ender craft. drop_class='special' keeps them out of every other pool, so this
-- is the only ambient source. Inert in the overworld and when biomes are off.
function PB_UTIL.grant_dimension_drop(blind)
    if not PB_UTIL.current_dimension then return end
    local dim  = PB_UTIL.current_dimension()
    local ante = (G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or 1
    local key  = 'bc_dimdrop_' .. ante .. '_' .. tostring(blind and blind.name)
    if dim == 'nether' and pseudorandom(key) < DIMENSION_MAT_CHANCE then
        record_drop('blaze_powder', 1)
    elseif dim == 'end' and pseudorandom(key) < DIMENSION_MAT_CHANCE then
        record_drop('ender_pearl', 1)
    end
end

-- Pay out and clear the pickaxe (+N random gathered ore) and shovel (+$N) one-shots that
-- were armed by using a tool consumable this blind. Runs on every Blind:defeat.
function PB_UTIL.apply_pending_tool_drops(blind)
    local bc = G.GAME and G.GAME.balacraft
    if not bc then return end

    local sv = bc.pending_shovel or 0
    if sv > 0 then
        ease_dollars(sv)
        bc.pending_shovel = 0
    end
end

-- Grant resources for defeating `blind`. PLACEHOLDER BALANCE (shape is fixed, numbers tunable).
function PB_UTIL.grant_blind_drop(blind)
    if not blind then return end

    -- Fresh record for this blind; the Cash Out summary reads only the most-recent win.
    if G.GAME and G.GAME.balacraft then
        G.GAME.balacraft.last_drop = {}
        G.GAME.balacraft.last_drop_lost = 0
    end

    -- Ore path: a themed entry REPLACES the tier-roll (one or more {id, amount} stacks); else roll.
    local spec = blind.name and PB_UTIL.BLIND_DROPS[blind.name]
    if spec then
        for _, d in ipairs(spec) do record_drop(d.id, d.amount) end
    else
        local ante = (G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or 1
        local loc = PB_UTIL.blind_location(blind)   -- 'surface' (Night) / 'cave' (Cave) / nil
        local max_tier = PB_UTIL.max_ore_tier(ante)
        if loc == 'surface' then
            -- Night: Wood-heavy (Wood is surface-exclusive) + an occasional tier-1 surface ore.
            record_drop('wood', SURFACE_WOOD_AMOUNT)
            if pseudorandom('bc_surf_ore_' .. ante .. '_' .. tostring(blind.name)) < SURFACE_EXTRA_ORE_CHANCE then
                record_drop(PB_UTIL.random_ore_of_tier_at(1, 'surface',
                    'bc_surf_' .. ante .. '_' .. tostring(blind.name)), 1)
            end
        elseif loc == 'cave' then
            -- Cave: ore-heavy, NO wood, scales with ante (chance to roll the highest unlocked tier).
            local tier = (pseudorandom('bc_cave_tier_' .. ante) < CAVE_HIGH_TIER_CHANCE) and max_tier or 1
            record_drop(PB_UTIL.random_ore_of_tier_at(tier, 'cave',
                'bc_cave_' .. ante .. '_' .. tostring(blind.name)), CAVE_ORE_AMOUNT)
            -- Deep underground also yields the occasional Obsidian (the Nether-portal fuel).
            if pseudorandom('bc_cave_obs_' .. ante .. '_' .. tostring(blind.name)) < CAVE_OBSIDIAN_CHANCE then
                record_drop('obsidian', 1)
            end
        else
            -- Generic fallback (bosses without a themed entry, other modded blinds): unchanged.
            local is_boss = blind.boss and true or false
            local tier = is_boss and max_tier or 1
            record_drop(PB_UTIL.random_ore_of_tier(tier,
                'bc_drop_' .. ante .. '_' .. tostring(blind.name)), is_boss and 2 or 1)
        end
    end

    -- Ruined Portal: beating it the NORMAL way banks 1 Obsidian (so you can light the NEXT one);
    -- a portal that was just LIT gives none -- you spent that Obsidian warping to the Nether
    -- (utilities/structures.lua sets _portal_lit before the forced win). active_structure is set by
    -- the structure-blind system; this is inert when that system isn't active.
    do
        local bc = G.GAME and G.GAME.balacraft
        if bc and bc.active_structure == 'ruined_portal' then
            if not bc._portal_lit then record_drop('obsidian', 1) end
            bc._portal_lit = nil
        end
    end

    -- Mob path: additive (themed mob material every time, else a low-rate loot roll).
    PB_UTIL.grant_mob_drop(blind)

    -- Dimension trickle: Blaze Powder in the Nether / Ender Pearl in the End (Eye-of-Ender mats).
    PB_UTIL.grant_dimension_drop(blind)

    -- Tool one-shots (Pickaxe / Shovel) are paid out and cleared here (Pickaxe also recorded).
    PB_UTIL.apply_pending_tool_drops(blind)

    -- Show the summary rows on the Cash Out screen (defined in cashout_ui.lua; guarded so a
    -- transient UI error can't break the drop path, and inert if that file isn't loaded).
    if PB_UTIL.show_cashout_resource_rows then
        pcall(PB_UTIL.show_cashout_resource_rows)
    end
end

-- Wrap Blind:defeat (same technique Steamodded uses) so drops fire on every blind win.
local _blind_defeat = Blind.defeat
function Blind:defeat(silent)
    _blind_defeat(self, silent)
    pcall(PB_UTIL.grant_blind_drop, self)
end
