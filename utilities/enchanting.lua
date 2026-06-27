-- Enchanting core logic: identify cards, validate/cost an enchant, and apply it.
-- The fusion-joker-style UI (select a tool + a book, click Enchant) lives in
-- utilities/enchanting_ui.lua; this file is the pure logic it calls.
--
-- Loads in the enhancements_enabled block AFTER content/enhancements/registry.lua
-- (needs PB_UTIL.ENCHANTS / helpers) and utilities/xp.lua (needs PB_UTIL.spend_level).

-- ── Card identification ───────────────────────────────────────────────────

function PB_UTIL.is_tool_card(c)
    return c ~= nil and c.ability ~= nil and c.ability.set == 'balacraft_tool'
end

function PB_UTIL.is_enchant_book(c)
    return c ~= nil and c.ability ~= nil and c.ability.set == 'balacraft_enchant'
end

-- The registry entry (tool/material/tier/base_uses/...) behind a tool card, or nil.
function PB_UTIL.tool_def_of(card)
    local key = card and card.config and card.config.center and card.config.center.key
    if not key then return nil end
    local id = key:match('^c_balacraft_tool_(.+)$')
    return id and PB_UTIL.TOOL_BY_ID[id] or nil
end

-- ── Enchanted-tool sprite (Phase D) ───────────────────────────────────────
-- An enchanted tool swaps to a cell on the pre-baked bc_tool_cards atlas: row = the tool's
-- atlas_row (0..17, build order), column = a state index encoding the applied tiers. The base
-- (un-enchanted) sprite stays on bc_resource_cards, so this is purely additive: if the atlas
-- is missing, refresh just no-ops and un-enchanted tools are untouched.

-- Column index 0..15 from the applied tiers. Sword cares about sharpness; pickaxe/shovel about
-- fortune; both about durability. (sharpness|fortune)*4 + durability.
function PB_UTIL.tool_enchant_state_index(tool_def, enchants)
    enchants = enchants or {}
    local dur = enchants.durability or 0
    if tool_def.tool == 'sword' then
        return (enchants.sharpness or 0) * 4 + dur
    else
        return (enchants.fortune or 0) * 4 + dur
    end
end

-- Transient per-card fingerprint so the per-frame self-heal only re-applies on a real change
-- (or after a save/load, which clears this non-serialized field and reverts the sprite).
function PB_UTIL.tool_sprite_fingerprint(card)
    local tdef = PB_UTIL.tool_def_of(card)
    if not tdef then return nil end
    local e = (card.ability and card.ability.extra) or {}
    return PB_UTIL.tool_enchant_state_index(tdef, e.enchants) .. '_' .. (tdef.atlas_row or 0)
end

-- RETIRED (2026-06-27): tools now keep their base bc_tools sprite at ALL times so the durability
-- frame system (update_durability_frame, content/tools/tool_consumabletype.lua) can keep animating
-- the wear bar -- on ENCHANTED tools too. Previously this swapped an enchanted tool's center onto the
-- pre-baked bc_tool_cards atlas, whose columns encode enchant STATE (not durability frames), so once
-- a tool was enchanted its wear bar froze (the durability updater bails when on that atlas). The
-- enchant LOOK is now carried entirely by the glint shader -- the inert carrier edition
-- e_balacraft_enchant_glint (Minecraft-violet, assets/shaders/balacraft_enchant.fs) -- which is
-- independent of the sprite atlas, so nothing visual is lost beyond the distinct baked blade art.
-- Kept as a no-op so existing callers (set_tool_enchant, the per-frame heal_tool_sprites) stay valid;
-- the bc_tool_cards atlas + tool_sprite_fingerprint are now dormant. To restore distinct per-enchant
-- sprites AND show durability, the enchant atlas would need durability columns (or a separate bar).
function PB_UTIL.refresh_tool_sprite(card)
    return   -- no-op: durability frames own the tool sprite; the glint shader shows the enchant
end

-- ── Validity / cost ───────────────────────────────────────────────────────

-- A book can be applied to a tool iff the type applies to that tool kind AND the book's
-- tier is strictly higher than the tool's current tier for that type (upgrade-only).
function PB_UTIL.enchant_is_valid(tool, book)
    if not (PB_UTIL.is_tool_card(tool) and PB_UTIL.is_enchant_book(book)) then return false end
    local tdef = PB_UTIL.tool_def_of(tool)
    if not tdef then return false end
    local e = book.ability.extra
    if not (e and e.etype and e.tier) then return false end
    if not PB_UTIL.enchant_applies(e.etype, tdef.tool) then return false end
    local cur = (tool.ability.extra and tool.ability.extra.enchants
        and tool.ability.extra.enchants[e.etype]) or 0
    return e.tier > cur
end

-- Level cost to apply a book: scales with book tier AND tool material tier (1..7).
function PB_UTIL.enchant_cost(tool, book)
    local tdef = PB_UTIL.tool_def_of(tool)
    local btier = (book and book.ability and book.ability.extra and book.ability.extra.tier) or 1
    local mtier = (tdef and tdef.tier) or 1
    return btier + (mtier - 1)
end

-- Lapis cost to apply a book to a TOOL: scales with book tier (I->1, II->2, III->3).
-- Spent IN ADDITION to the level cost (Minecraft-style: enchanting eats lapis + XP).
function PB_UTIL.enchant_lapis_cost(tool, book)
    return (book and book.ability and book.ability.extra and book.ability.extra.tier) or 1
end

-- Optional mob-material reagent to apply a book to a TOOL -- the SINK for the Night/Cave (Wave 2)
-- mob drops. Mapped by the book's enchant type + tier so rarer enchants demand rarer loot:
-- Sharpness II/III cost Bone / Spider Eye; Fortune II/III cost Gunpowder / Glow Ink Sac. Tier-I
-- books and Durability cost no material (keeps the early/utility enchant flow unchanged). Spent
-- ALONGSIDE the level + lapis cost, with the same check-before-spend ordering. Card enchants pay
-- no material. Returns { id, amount } or nil. (Balance: amounts of 1 -- tune freely.)
local ENCHANT_MATERIAL = {
    sharpness = { [2] = 'bone',      [3] = 'spider_eye'   },
    fortune   = { [2] = 'gunpowder', [3] = 'glow_ink_sac' },
}
function PB_UTIL.enchant_material_cost(book)
    local e = book and book.ability and book.ability.extra
    if not (e and e.etype and e.tier) then return nil end
    local by_tier = ENCHANT_MATERIAL[e.etype]
    local id = by_tier and by_tier[e.tier]
    if not id then return nil end
    return { id = id, amount = 1 }
end

-- Returns tool_card, book_card if exactly one of each is highlighted in G.consumeables.
function PB_UTIL.get_enchant_pair()
    local hl = G.consumeables and G.consumeables.highlighted
    if not hl or #hl ~= 2 then return nil end
    local tool, book
    for _, c in ipairs(hl) do
        if PB_UTIL.is_tool_card(c) then tool = c
        elseif PB_UTIL.is_enchant_book(c) then book = c end
    end
    if tool and book then return tool, book end
    return nil
end

-- Allow co-highlighting a tool + a book (vanilla consumable limit is 1). Cheap; called
-- each frame from the UI driver and re-asserted because G.consumeables is rebuilt per run.
function PB_UTIL.ensure_enchant_highlight_limit()
    if G.consumeables and G.consumeables.config then
        local cur = G.consumeables.config.highlighted_limit or 1
        if cur < 2 then G.consumeables.config.highlighted_limit = 2 end
    end
end

-- The limit of 2 above would make consumable selection "sticky" (clicking accumulates
-- highlights instead of switching, so cards keep their Use button showing and a later click
-- lands on it -> accidental use). Wrap add_to_highlighted so the SECOND highlight is only kept
-- when it forms a tool + book pair; any other click single-selects like vanilla.
if not PB_UTIL._consumable_highlight_wrapped then
    PB_UTIL._consumable_highlight_wrapped = true
    local _add_to_highlighted = CardArea.add_to_highlighted
    function CardArea:add_to_highlighted(card, silent)
        if self == G.consumeables then
            local hl = self.highlighted or {}
            local pair = false
            if #hl == 1 and hl[1] ~= card then
                local a = hl[1]
                pair = (PB_UTIL.is_tool_card(a) and PB_UTIL.is_enchant_book(card))
                    or (PB_UTIL.is_enchant_book(a) and PB_UTIL.is_tool_card(card))
            end
            if not pair then self:unhighlight_all() end
        end
        return _add_to_highlighted(self, card, silent)
    end
end

-- ── Apply ─────────────────────────────────────────────────────────────────

-- Write an enchant onto an existing tool card with NO cost. Shared by pack finds (create_tool_pack_card)
-- and apply_enchant (the enchanting table). Rescales Durability max/uses (ceil) and refreshes the
-- enchanted sprite. durability_mult / tool_def_of / refresh_tool_sprite are all from the enhancements
-- block, which loads together with this file -- so they exist whenever this is called.
function PB_UTIL.set_tool_enchant(card, etype, tier)
    local e = card.ability and card.ability.extra
    if not e then return end
    e.enchants = e.enchants or { sharpness = 0, durability = 0, fortune = 0 }
    e.enchants[etype] = tier
    if etype == 'durability' then
        local tdef = PB_UTIL.tool_def_of(card)
        local base = (tdef and tdef.base_uses) or e.max_uses or 1
        local newmax = math.ceil(base * PB_UTIL.durability_mult(tier))
        local delta  = newmax - (e.max_uses or base)
        e.max_uses  = newmax
        e.uses_left = math.max(0, (e.uses_left or 0) + delta)
    end
    if PB_UTIL.refresh_tool_sprite then PB_UTIL.refresh_tool_sprite(card) end
    card.bc_sprite_fp = nil   -- let the per-frame self-heal re-apply the enchanted cell

    -- Route the tool through the live enchant glint shader by attaching the inert carrier edition
    -- once (idempotent). The balacraft_enchant shader (content/editions/enchant_shader.lua) reads
    -- the tool's stacked tiers off e.enchants via send_vars, so one carrier covers all three enchant
    -- types at any tier. In this shared writer so BOTH the enchanting table (apply_enchant) and
    -- booster-pack finds (create_tool_pack_card) get the glint. Guarded -- a hiccup here must never
    -- undo the enchant we just wrote.
    if not (card.edition and card.edition.key == 'e_balacraft_enchant_glint') then
        pcall(function() card:set_edition('e_balacraft_enchant_glint', true) end)
    end
end

-- Apply `book` to `tool`: spend levels, write the enchant, re-scale durability, consume the
-- book, refresh the sprite. Returns true on success (false if invalid or unaffordable).
function PB_UTIL.apply_enchant(tool, book)
    if not PB_UTIL.enchant_is_valid(tool, book) then return false end
    local cost = PB_UTIL.enchant_cost(tool, book)
    -- Lapis is spent ALONGSIDE the level cost. Check affordability up front (before spending
    -- anything) so neither resource can be half-committed. Guarded on get_resource_count so
    -- enabling enhancements WITHOUT resources falls back to level-only (no crash).
    local lcost = PB_UTIL.enchant_lapis_cost(tool, book)
    if PB_UTIL.get_resource_count and lcost > 0
        and PB_UTIL.get_resource_count('lapis') < lcost then return false end
    -- Mob-material reagent (Sharpness/Fortune II-III). Same check-before-spend as lapis so nothing
    -- is half-committed; guarded so it's inert when resources are off / no material applies.
    local mat = PB_UTIL.enchant_material_cost(book)
    if mat and PB_UTIL.get_resource_count
        and PB_UTIL.get_resource_count(mat.id) < mat.amount then return false end
    -- Needs the level system (xp.lua). Guarded so enabling enhancements without xp can't crash.
    if not (PB_UTIL.spend_level and PB_UTIL.spend_level(cost)) then return false end
    -- Levels are now committed; spend the lapis + material (no-op if resources are off).
    if PB_UTIL.add_resource and lcost > 0 then PB_UTIL.add_resource('lapis', -lcost) end
    if mat and PB_UTIL.add_resource then PB_UTIL.add_resource(mat.id, -mat.amount) end

    -- Write the enchant (+ durability rescale + sprite refresh) via the shared cost-free helper.
    local etype, tier = book.ability.extra.etype, book.ability.extra.tier
    PB_UTIL.set_tool_enchant(tool, etype, tier)

    -- Consume the book (Card:remove handles area removal + cleanup).
    book:remove()

    -- Visual feedback.
    if tool.juice_up then tool:juice_up(0.3, 0.5) end
    if G.consumeables and G.consumeables.unhighlight_all then G.consumeables:unhighlight_all() end
    pcall(play_sound, 'tarot1', 1.0, 0.6)
    return true
end

-- ── Card target (dual-target books -> playing-card editions) ───────────────
-- Every enchant book is dual-target: select one playing card in your hand + one book in the
-- consumable area, then Enchant. The book maps to a card edition:
--   sharpness  -> e_balacraft_sharpness_<tier>  (+Mult, scales with tier)
--   durability -> e_balacraft_unbreaking         (anti-debuff / no-shatter, flat)
--   fortune    -> e_balacraft_lucky_<tier>        (Emerald drops on score, scales)
-- Editions are mutually exclusive on a card, so a card already holding an edition is only a valid
-- target for a STRICT same-type tier upgrade (reject-if-occupied otherwise).

-- book etype -> the card edition's logical type.
local BOOK_EDITION_TYPE = { sharpness = 'sharpness', durability = 'unbreaking', fortune = 'lucky' }

-- book -> the exact edition center key it applies (tiered for sharpness/lucky, flat for unbreaking).
function PB_UTIL.book_card_edition_key(book)
    local e = book and book.ability and book.ability.extra
    if not (e and e.etype) then return nil end
    if e.etype == 'sharpness'  then return 'e_balacraft_sharpness_' .. (e.tier or 1) end
    if e.etype == 'durability' then return 'e_balacraft_unbreaking' end
    if e.etype == 'fortune'    then return 'e_balacraft_lucky_' .. (e.tier or 1) end
    return nil
end

local function is_playing_card(c)
    return c ~= nil and c.ability ~= nil
        and (c.ability.set == 'Default' or c.ability.set == 'Enhanced')
end

-- The BalaCraft edition currently on a card as (type, tier): type is 'sharpness'|'lucky' (with its
-- tier), 'unbreaking' (flat, tier 0), 'other' for any non-BalaCraft edition, or nil for no edition.
local function card_edition_info(card)
    local k = card and card.edition and card.edition.key
    if not k then return nil end
    local n = k:match('^e_balacraft_sharpness_(%d+)$'); if n then return 'sharpness', tonumber(n) end
    n = k:match('^e_balacraft_lucky_(%d+)$');            if n then return 'lucky', tonumber(n) end
    if k == 'e_balacraft_unbreaking' then return 'unbreaking', 0 end
    return 'other', nil
end

-- Returns card, book if exactly one playing card is highlighted in G.hand AND exactly one enchant
-- book is highlighted in G.consumeables.
function PB_UTIL.get_enchant_card_pair()
    local chl = G.consumeables and G.consumeables.highlighted
    if not chl or #chl ~= 1 or not PB_UTIL.is_enchant_book(chl[1]) then return nil end
    local hhl = G.hand and G.hand.highlighted
    if not hhl or #hhl ~= 1 or not is_playing_card(hhl[1]) then return nil end
    return hhl[1], chl[1]
end

-- A book can enchant a card iff: card is a playing card, not debuffed, and either the card has no
-- edition, or it holds the SAME BalaCraft type at a strictly lower tier (an upgrade). Any other
-- existing edition (a different BalaCraft type, already-Unbreaking, or a base-game glint) -> reject.
function PB_UTIL.enchant_card_is_valid(card, book)
    if not (PB_UTIL.is_enchant_book(book) and is_playing_card(card)) then return false end
    if card.debuff then return false end
    local e = book.ability.extra
    local btype = e and BOOK_EDITION_TYPE[e.etype]
    if not btype then return false end
    local ctype, ctier = card_edition_info(card)
    if not ctype then return true end               -- no edition: any book applies
    if ctype ~= btype then return false end         -- occupied by a different edition: reject
    if btype == 'unbreaking' then return false end  -- already Unbreaking (flat): no-op
    return (e.tier or 1) > (ctier or 0)             -- same scaling type: strict tier upgrade only
end

-- Level cost to enchant a card: scaling types cost tier+1 (I=2, II=3, III=4); flat Unbreaking = 2.
function PB_UTIL.enchant_card_cost(book)
    local e = book and book.ability and book.ability.extra
    if not e then return 2 end
    if e.etype == 'durability' then return 2 end
    return (e.tier or 1) + 1
end

-- Lapis cost to enchant a CARD: scaling types (sharpness/lucky) pay book tier (1/2/3); the flat
-- Unbreaking edition (durability) pays a flat 1. Spent in addition to the level cost.
function PB_UTIL.enchant_card_lapis_cost(book)
    local e = book and book.ability and book.ability.extra
    if not e then return 1 end
    if e.etype == 'durability' then return 1 end   -- -> e_balacraft_unbreaking (flat)
    return e.tier or 1
end

-- Apply a book's edition to a playing card: spend levels, set the edition, consume the book.
function PB_UTIL.apply_card_enchant(card, book)
    if not PB_UTIL.enchant_card_is_valid(card, book) then return false end
    local cost = PB_UTIL.enchant_card_cost(book)
    -- Lapis spent alongside levels; same check-before-spend ordering as apply_enchant.
    local lcost = PB_UTIL.enchant_card_lapis_cost(book)
    if PB_UTIL.get_resource_count and lcost > 0
        and PB_UTIL.get_resource_count('lapis') < lcost then return false end
    if not (PB_UTIL.spend_level and PB_UTIL.spend_level(cost)) then return false end
    if PB_UTIL.add_resource and lcost > 0 then PB_UTIL.add_resource('lapis', -lcost) end

    local key = PB_UTIL.book_card_edition_key(book)
    if not key then return false end
    card:set_edition(key, true)
    book:remove()

    if card.juice_up then card:juice_up(0.3, 0.5) end
    if G.hand and G.hand.unhighlight_all then G.hand:unhighlight_all() end
    if G.consumeables and G.consumeables.unhighlight_all then G.consumeables:unhighlight_all() end
    pcall(play_sound, 'foil1', 1.0, 0.6)
    return true
end

-- ── Unified target dispatch (tool OR card) ─────────────────────────────────
-- The Enchant UI calls these so it doesn't care which kind of target is selected. Tool target takes
-- priority (a tool + book both in the consumable area); else a card-in-hand + any book.

function PB_UTIL.get_enchant_target()
    local tool, book = PB_UTIL.get_enchant_pair()
    if tool and book and PB_UTIL.enchant_is_valid(tool, book) then
        return { mode = 'tool', tool = tool, book = book }
    end
    local card, cbook = PB_UTIL.get_enchant_card_pair()
    if card and cbook and PB_UTIL.enchant_card_is_valid(card, cbook) then
        return { mode = 'card', card = card, book = cbook }
    end
    return nil
end

function PB_UTIL.enchant_target_key(t)
    if not t then return nil end
    if t.mode == 'tool' then
        return 'tool:' .. tostring(t.tool.sort_id) .. ':' .. tostring(t.book.sort_id)
    end
    return 'card:' .. tostring(t.card.sort_id) .. ':' .. tostring(t.book.sort_id)
end

function PB_UTIL.enchant_target_cost(t)
    if not t then return 0 end
    if t.mode == 'tool' then return PB_UTIL.enchant_cost(t.tool, t.book) end
    return PB_UTIL.enchant_card_cost(t.book)
end

-- Lapis cost for whichever target kind is selected (parallels enchant_target_cost). 0 when no target.
function PB_UTIL.enchant_target_lapis_cost(t)
    if not t then return 0 end
    if t.mode == 'tool' then return PB_UTIL.enchant_lapis_cost(t.tool, t.book) end
    return PB_UTIL.enchant_card_lapis_cost(t.book)
end

-- Mob-material reagent for the selected target. Only TOOL enchants cost a material (card enchants
-- pay none); returns { id, amount } or nil. Used by the Enchant bar (cost line + affordability gate).
function PB_UTIL.enchant_target_material_cost(t)
    if not t or t.mode ~= 'tool' then return nil end
    return PB_UTIL.enchant_material_cost(t.book)
end

function PB_UTIL.enchant_target_valid(t)
    if not t then return false end
    if t.mode == 'tool' then return PB_UTIL.enchant_is_valid(t.tool, t.book) end
    return PB_UTIL.enchant_card_is_valid(t.card, t.book)
end

function PB_UTIL.apply_enchant_target(t)
    if not t then return false end
    if t.mode == 'tool' then return PB_UTIL.apply_enchant(t.tool, t.book) end
    return PB_UTIL.apply_card_enchant(t.card, t.book)
end

-- ── Unbreaking protection (Durability's card side) ─────────────────────────
-- One-time wraps (the mod's standard pattern -- see the add_to_highlighted wrap above). A card
-- carrying e_balacraft_unbreaking:
--   * is never debuffed by a boss blind (Blind:debuff_card forces it un-debuffed),
--   * never shatters if it's a Glass card (SMODS.shatters returns false for it).
local function is_unbreaking(card)
    return card and card.edition and card.edition.key == 'e_balacraft_unbreaking'
end

if not PB_UTIL._unbreaking_wrapped then
    PB_UTIL._unbreaking_wrapped = true

    -- blind.lua:682 -- the single point where boss debuffs are applied to a card.
    local _debuff_card = Blind.debuff_card
    function Blind:debuff_card(card, from_blind)
        if is_unbreaking(card) then
            card:set_debuff(false)
            return
        end
        return _debuff_card(self, card, from_blind)
    end

    -- smods utils.lua:1072 -- the single predicate gating Glass-style shatter on score.
    if SMODS and SMODS.shatters then
        local _shatters = SMODS.shatters
        function SMODS.shatters(card)
            if is_unbreaking(card) then return false end
            return _shatters(card)
        end
    end
end
