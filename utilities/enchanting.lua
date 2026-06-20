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
-- atlas_row (0..14, build order), column = a state index encoding the applied tiers. The base
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

-- Point an enchanted tool card at its bc_tool_cards cell. No-op for un-enchanted tools (state
-- 0) and when the atlas isn't registered. Mirrors what Card:set_sprites does internally.
function PB_UTIL.refresh_tool_sprite(card)
    if not PB_UTIL.is_tool_card(card) then return end
    if not (card.children and card.children.center) then return end
    local tdef = PB_UTIL.tool_def_of(card)
    if not tdef then return end
    local e = (card.ability and card.ability.extra) or {}
    local state = PB_UTIL.tool_enchant_state_index(tdef, e.enchants)
    if state <= 0 then return end                  -- un-enchanted: keep the base sprite
    local atlas = G.ASSET_ATLAS and G.ASSET_ATLAS['bc_tool_cards']
    if not atlas then return end                   -- atlas absent: no-op (safe)
    card.children.center.atlas = atlas
    card.children.center:set_sprite_pos({ x = state, y = tdef.atlas_row or 0 })
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

-- Apply `book` to `tool`: spend levels, write the enchant, re-scale durability, consume the
-- book, refresh the sprite. Returns true on success (false if invalid or unaffordable).
function PB_UTIL.apply_enchant(tool, book)
    if not PB_UTIL.enchant_is_valid(tool, book) then return false end
    local cost = PB_UTIL.enchant_cost(tool, book)
    -- Needs the level system (xp.lua). Guarded so enabling enhancements without xp can't crash.
    if not (PB_UTIL.spend_level and PB_UTIL.spend_level(cost)) then return false end

    local e = tool.ability.extra
    e.enchants = e.enchants or { sharpness = 0, durability = 0, fortune = 0 }
    local etype, tier = book.ability.extra.etype, book.ability.extra.tier
    e.enchants[etype] = tier

    -- Durability re-scales max uses (ceil) and grants the extra uses immediately.
    if etype == 'durability' then
        local tdef = PB_UTIL.tool_def_of(tool)
        local base = (tdef and tdef.base_uses) or e.max_uses or 1
        local newmax = math.ceil(base * PB_UTIL.durability_mult(tier))
        local delta  = newmax - (e.max_uses or base)
        e.max_uses  = newmax
        e.uses_left = math.max(0, (e.uses_left or 0) + delta)
    end

    -- Consume the book (Card:remove handles area removal + cleanup).
    book:remove()

    -- Visual feedback + sprite refresh (refresh is a no-op until the Phase D atlas exists).
    if PB_UTIL.refresh_tool_sprite then PB_UTIL.refresh_tool_sprite(tool) end
    tool.bc_sprite_fp = nil
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

-- Apply a book's edition to a playing card: spend levels, set the edition, consume the book.
function PB_UTIL.apply_card_enchant(card, book)
    if not PB_UTIL.enchant_card_is_valid(card, book) then return false end
    local cost = PB_UTIL.enchant_card_cost(book)
    if not (PB_UTIL.spend_level and PB_UTIL.spend_level(cost)) then return false end

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
