# Villager Trading (v1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent **Villager Trading** section to the shop where the player spends [[Emerald]] emeralds on ~3 run-seeded offers (resource bundles + plain tools) that sell out and reroll with the shop.

**Architecture:** Three new files mirroring the resource subsystem's data/logic/UI split — `content/villager/trades.lua` (pure-data templates+pricing), `utilities/villager.lua` (offer generation, shop/reroll hooks, emerald-priced buy), `utilities/villager_ui.lua` (a Weak-bonded floating `UIBox` over the deck corner, maintained by a `Game:update` wrap, shop-state only). State lives on `G.GAME.balacraft` (hybrid auto-save/reset model — no custom save code). No Lovely source patch; all integration via wrapping `Game:update_shop`, `G.FUNCS.cash_out`, and `G.FUNCS.reroll_shop`, exactly as `biomes.lua`/`torch.lua`/`xp.lua` already do.

**Tech Stack:** Lua (Steamodded/Lovely, no test runner), `luac -p` for syntax, standalone `lua` for a headless test of the pure offer logic, `grep` for content checks. Spec: `docs/superpowers/specs/2026-06-19-villager-trading-design.md`.

---

## Critical environment notes (read before any task)

- **Working directory:** all commands run from the `Mods/` parent dir: `/Users/alessandro/Library/Application Support/Balatro/Mods`. Mod files are under `BalaCraft/`.
- **No git commits** (the user's standing choice this session — the working tree has unrelated WIP, and several wiring-target files are already modified). Implement + verify; leave changes in the working tree. Commit steps are intentionally omitted.
- **No Balatro launch by agents.** The UI and the shop/reroll/buy hooks are runtime-only; they're verified by `luac -p` + `grep` here and by the user in-game (Task 6). The pure offer-generation logic IS verified headlessly (Task 2).
- **Load order:** villager files load INSIDE the `resources_enabled` block in `main.lua`, AFTER the tool registration (they need `PB_UTIL.RESOURCES`, `PB_UTIL.RESOURCE_BY_ID`, `PB_UTIL.TOOLS`, the `bc_resource_icons` atlas, and `consumable_add`).
- **Hooks must self-skip without the game** so the headless test can `dofile` `villager.lua`: guard every wrap with `if Game and Game.update_shop`, `if G and G.FUNCS and G.FUNCS.cash_out`, etc. (a bare `if Game.update_shop` would index a nil `Game` in the harness).

---

## Task 1: Offer templates + pricing data

**Files:**
- Create: `BalaCraft/content/villager/trades.lua`

- [ ] **Step 1: Write the data file**

```lua
-- Villager Trading offer templates + pricing. PURE DATA (like content/resources/recipes.lua):
-- no SMODS declarations, no side effects. utilities/villager.lua expands these templates into
-- concrete offers at runtime. All numbers are balance knobs -- tune freely.

-- Emerald cost of a tool offer, indexed by material tier (1..5 = Wooden..Diamond).
-- Mirrors the $ crafting cost (COST_BY_TIER) in content/tools/registry.lua.
PB_UTIL.VILLAGER_TOOL_COST  = { 3, 4, 5, 6, 8 }
PB_UTIL.VILLAGER_TORCH_COST = 2

-- Offer templates. `weight` biases the draw (bundles common, tools rarer). `kind`:
--   'resource' -> a bundle of `amount` of a random GATHERED ore of `tier` (emerald excluded), for `cost`.
--   'tool'     -> one random tool consumable (Sword/Pickaxe/Shovel x material); cost from VILLAGER_TOOL_COST[tier].
--   'torch'    -> one Torch consumable for VILLAGER_TORCH_COST.
PB_UTIL.VILLAGER_TRADES = {
    { kind = 'resource', tier = 1, amount = 5, cost = 3, weight = 3 },
    { kind = 'resource', tier = 2, amount = 3, cost = 4, weight = 3 },
    { kind = 'resource', tier = 3, amount = 2, cost = 6, weight = 2 },
    { kind = 'tool',  weight = 2 },
    { kind = 'torch', weight = 1 },
}
```

- [ ] **Step 2: Syntax-check**

Run:
```bash
luac -p "BalaCraft/content/villager/trades.lua" && echo TRADES_OK
```
Expected: `TRADES_OK`.

---

## Task 2: Offer generation, hooks, and buy logic (+ headless test)

**Files:**
- Create: `BalaCraft/utilities/villager.lua`
- Test (ephemeral): `/tmp/test_villager_offers.lua`

- [ ] **Step 1: Write the failing headless test**

Create `/tmp/test_villager_offers.lua`:

```lua
-- Headless test of the pure villager offer logic. Run with: lua /tmp/test_villager_offers.lua
-- Stubs the engine globals the logic touches, then loads the real data + logic files.

PB_UTIL = {}

-- Deterministic RNG stubs (real engine: pseudoseed advances per key; pseudorandom_element picks).
local _seed = 0
function pseudoseed(_k) _seed = _seed + 1; return _seed end
function pseudorandom_element(t, s) return t[((s - 1) % #t) + 1] end

-- Stub resource registry (incl. emerald, which must NEVER be offered as a bundle).
PB_UTIL.RESOURCES = {
    { id = 'wood',        name = 'Wood',        kind = 'gathered', tier = 1, pos = {} },
    { id = 'cobblestone', name = 'Cobblestone', kind = 'gathered', tier = 1, pos = {} },
    { id = 'coal',        name = 'Coal',        kind = 'gathered', tier = 1, pos = {} },
    { id = 'iron',        name = 'Iron',        kind = 'gathered', tier = 2, pos = {} },
    { id = 'gold',        name = 'Gold',        kind = 'gathered', tier = 2, pos = {} },
    { id = 'diamond',     name = 'Diamond',     kind = 'gathered', tier = 3, pos = {} },
    { id = 'emerald',     name = 'Emerald',     kind = 'gathered', tier = 2, pos = {} },
    { id = 'sticks',      name = 'Sticks',      kind = 'crafted',                pos = {} },
}
PB_UTIL.RESOURCE_BY_ID = {}
for _, r in ipairs(PB_UTIL.RESOURCES) do PB_UTIL.RESOURCE_BY_ID[r.id] = r end

PB_UTIL.TOOLS = {
    { id = 'sword_wood',       name = 'Wooden Sword',   tier = 1 },
    { id = 'pickaxe_diamond',  name = 'Diamond Pickaxe', tier = 5 },
}

-- G stub: P_CENTERS gates which tools exist; FUNCS table so G.FUNCS.x = fn assignments work.
G = {
    P_CENTERS = {
        ['c_balacraft_tool_sword_wood'] = true,
        ['c_balacraft_tool_pickaxe_diamond'] = true,
        ['c_balacraft_torch'] = true,
    },
    FUNCS = {},
}
-- Note: Game is intentionally left nil so villager.lua's shop/reroll/cash_out wraps self-skip.

dofile('BalaCraft/content/villager/trades.lua')
dofile('BalaCraft/utilities/villager.lua')

local offers = PB_UTIL.build_villager_offers(3, 'k1')
assert(#offers == 3, 'expected 3 offers, got ' .. #offers)

local seen = {}
for _, o in ipairs(offers) do
    assert(type(o.cost) == 'number' and o.cost > 0, 'offer has no positive cost')
    assert(o.sold == false, 'new offer should not be sold')
    if o.kind == 'resource' then
        assert(o.id ~= 'emerald', 'emerald must never be a bundle offer')
        assert(o.id and o.amount, 'resource offer missing id/amount')
    else
        assert(o.kind == 'tool' and o.key, 'tool offer missing key')
    end
    local sig = o.kind .. (o.id or o.key) .. tostring(o.amount)
    assert(not seen[sig], 'offers must be distinct, dup: ' .. sig)
    seen[sig] = true
end

-- A candidate-only-tools scenario still works (no resources defined -> only tools/torch).
assert(#PB_UTIL.villager_candidates() >= 7, 'expected >=7 candidates from the stub data')

print('villager offers test OK')
```

- [ ] **Step 2: Run the test to confirm it fails**

Run:
```bash
cd "/Users/alessandro/Library/Application Support/Balatro/Mods" && lua /tmp/test_villager_offers.lua
```
Expected: FAIL — `cannot open BalaCraft/utilities/villager.lua` (the file doesn't exist yet).

- [ ] **Step 3: Write `utilities/villager.lua`**

```lua
-- Villager Trading: offer generation + shop integration + emerald-priced buy.
-- Data/templates in content/villager/trades.lua; UI in utilities/villager_ui.lua.
-- State lives on G.GAME.balacraft (plain tables/numbers -> auto-saved within a run, auto-reset
-- per run; seeded in resources.lua's init_game_object wrapper). No custom save/load.

local N_OFFERS = 3   -- offers shown per shop (tunable)

-- Expand the templates into the full list of concrete candidate offers (each with a `weight`).
-- Reads the live registries, so it must be called at RUNTIME (not load). Tools whose consumable
-- center isn't registered are skipped, so a trade can never grant a non-existent card. Emerald is
-- never sold as a bundle.
function PB_UTIL.villager_candidates()
    local out = {}
    for _, t in ipairs(PB_UTIL.VILLAGER_TRADES or {}) do
        if t.kind == 'resource' then
            for _, r in ipairs(PB_UTIL.RESOURCES or {}) do
                if r.kind == 'gathered' and r.tier == t.tier and r.id ~= 'emerald' then
                    out[#out + 1] = {
                        kind = 'resource', id = r.id, amount = t.amount, cost = t.cost,
                        label = t.amount .. 'x ' .. r.name, weight = t.weight or 1,
                    }
                end
            end
        elseif t.kind == 'tool' then
            for _, tool in ipairs(PB_UTIL.TOOLS or {}) do
                local key = 'c_balacraft_tool_' .. tool.id
                if G and G.P_CENTERS and G.P_CENTERS[key] then
                    out[#out + 1] = {
                        kind = 'tool', key = key, label = tool.name,
                        cost = (PB_UTIL.VILLAGER_TOOL_COST or {})[tool.tier] or 5,
                        weight = t.weight or 1,
                    }
                end
            end
        elseif t.kind == 'torch' then
            local key = 'c_balacraft_torch'
            if G and G.P_CENTERS and G.P_CENTERS[key] then
                out[#out + 1] = {
                    kind = 'tool', key = key, label = 'Torch',
                    cost = PB_UTIL.VILLAGER_TORCH_COST or 2, weight = t.weight or 1,
                }
            end
        end
    end
    return out
end

-- Draw up to `n` DISTINCT offers, weighted, run-seeded deterministic (mirrors sample_pack_ores
-- in utilities/functions.lua). Returns offer tables with sold = false.
function PB_UTIL.build_villager_offers(n, seed_key)
    local remaining = PB_UTIL.villager_candidates()
    local picked = {}
    n = math.min(n or N_OFFERS, #remaining)
    for _ = 1, n do
        local pool = {}
        for idx, e in ipairs(remaining) do
            for _ = 1, (e.weight or 1) do pool[#pool + 1] = idx end
        end
        if #pool == 0 then break end
        local chosen = pseudorandom_element(pool, pseudoseed(seed_key))
        local c = remaining[chosen]
        picked[#picked + 1] = {
            kind = c.kind, id = c.id, amount = c.amount, key = c.key,
            label = c.label, cost = c.cost, sold = false,
        }
        table.remove(remaining, chosen)
    end
    return picked
end

-- Seed the current shop's offers. seed_key varies per shop (ante+round) and per reroll
-- (villager_reroll_index), so rerolls produce different sets deterministically.
function PB_UTIL.seed_villager_offers()
    local bc = G and G.GAME and G.GAME.balacraft
    if not bc then return end
    local ante  = (G.GAME.round_resets and G.GAME.round_resets.ante) or 1
    local round = G.GAME.round or 0
    local ri    = bc.villager_reroll_index or 0
    bc.villager_offers = PB_UTIL.build_villager_offers(N_OFFERS,
        'bc_villager_' .. ante .. '_' .. round .. '_' .. ri)
    bc._villager_dirty = true
end

-- Can `offer` be bought right now? (affordable, not sold, and -- for tool offers -- a free
-- consumable slot exists). Used by both the per-frame gate and the buy callback.
function PB_UTIL.can_buy_villager_offer(offer)
    if not offer or offer.sold then return false end
    if PB_UTIL.get_resource_count('emerald') < (offer.cost or 0) then return false end
    if offer.kind == 'tool' then
        if not (G.consumeables and #G.consumeables.cards < G.consumeables.config.card_limit) then
            return false
        end
    end
    return true
end

-- ---- Engine hooks (each self-skips when its global is absent, so the headless test can load
-- ---- this file without a running game). ----

-- Reset the per-visit seed flag when heading to the shop (mirrors biomes.lua's cash_out wrap),
-- so each shop visit re-seeds a fresh set of offers.
if G and G.FUNCS and G.FUNCS.cash_out then
    local _cash_out = G.FUNCS.cash_out
    G.FUNCS.cash_out = function(e)
        _cash_out(e)
        if G.GAME and G.GAME.balacraft then
            G.GAME.balacraft._villager_seeded = false
            G.GAME.balacraft.villager_reroll_index = 0
        end
    end
end

-- Seed offers once the shop is built (mirrors biomes.lua's update_shop wrap). _villager_seeded is
-- a plain bool on G.GAME.balacraft -> saved, so a reload mid-shop keeps the existing offers.
if Game and Game.update_shop then
    local _update_shop = Game.update_shop
    function Game:update_shop(dt)
        _update_shop(self, dt)
        local bc = G.GAME and G.GAME.balacraft
        if bc and G.shop and not bc._villager_seeded then
            PB_UTIL.seed_villager_offers()
            bc._villager_seeded = true
        end
    end
end

-- Re-seed offers when the player rerolls the shop (mirrors torch.lua's reroll_shop wrap).
if G and G.FUNCS and G.FUNCS.reroll_shop and not PB_UTIL._villager_reroll_hooked then
    PB_UTIL._villager_reroll_hooked = true
    local _orig_reroll = G.FUNCS.reroll_shop
    G.FUNCS.reroll_shop = function(...)
        local ret = _orig_reroll(...)
        local bc = G.GAME and G.GAME.balacraft
        if bc then
            bc.villager_reroll_index = (bc.villager_reroll_index or 0) + 1
            PB_UTIL.seed_villager_offers()
        end
        return ret
    end
end

-- ---- Buy buttons ----

-- Per-frame gate (mirrors vanilla G.FUNCS.can_buy): green+enabled when buyable, greyed+disabled
-- otherwise.
if G and G.FUNCS then
    G.FUNCS.bc_can_buy_villager = function(e)
        local offer = e.config.ref_table
        if PB_UTIL.can_buy_villager_offer(offer) then
            e.config.colour = G.C.GREEN
            e.config.button = 'bc_buy_villager_offer'
        else
            e.config.colour = G.C.UI.BACKGROUND_INACTIVE
            e.config.button = nil
        end
    end

    G.FUNCS.bc_buy_villager_offer = function(e)
        local offer = e.config.ref_table
        if not PB_UTIL.can_buy_villager_offer(offer) then return end
        PB_UTIL.add_resource('emerald', -offer.cost)
        if offer.kind == 'resource' then
            PB_UTIL.add_resource(offer.id, offer.amount)
        else
            consumable_add(offer.key)
        end
        offer.sold = true
        if G.GAME and G.GAME.balacraft then G.GAME.balacraft._villager_dirty = true end
        play_sound('cardSlide1')
    end
end
```

- [ ] **Step 4: Syntax-check, then run the test to confirm it passes**

Run:
```bash
cd "/Users/alessandro/Library/Application Support/Balatro/Mods"
luac -p "BalaCraft/utilities/villager.lua" && echo VILLAGER_OK
lua /tmp/test_villager_offers.lua
```
Expected: `VILLAGER_OK` then `villager offers test OK`.

---

## Task 3: The shop-section UI panel

**Files:**
- Create: `BalaCraft/utilities/villager_ui.lua`

- [ ] **Step 1: Write `utilities/villager_ui.lua`**

```lua
-- Villager Trading shop panel. A Weak-bonded UIBox anchored to the right of G.shop (over the
-- idle deck corner), shown ONLY in G.STATES.SHOP. Mirrors resource_ui.lua's attach/maintain/
-- teardown idiom and is driven by a Game:update wrap. Rebuilds when the offers table is replaced
-- (new shop / reroll) or a buy flips an offer to sold (_villager_dirty).

local OFFER_ICON_SZ = 0.45   -- tunable
local PANEL_OFFSET  = { x = 1.1, y = 0.6 }   -- anchor nudge toward the deck corner; TUNE IN-GAME

-- One offer row: icon | label | emerald cost | Trade button.
local function offer_row(offer, icon_atlas)
    local lbl_colour = offer.sold and G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT
    local label = offer.sold and (offer.label .. ' (Sold)') or offer.label

    -- Icon: resource -> bc_resource_icons at the ore's pos; tool -> the consumable center's own
    -- atlas/pos when available, else an empty spacer.
    local icon_node
    if offer.kind == 'resource' then
        local r = PB_UTIL.RESOURCE_BY_ID[offer.id]
        icon_node = { n = G.UIT.O, config = { object = Sprite(0, 0, OFFER_ICON_SZ, OFFER_ICON_SZ, icon_atlas, r.pos) } }
    else
        local center = G.P_CENTERS[offer.key]
        local atlas = center and center.atlas and G.ASSET_ATLAS[center.atlas]
        if atlas and center.pos then
            icon_node = { n = G.UIT.O, config = { object = Sprite(0, 0, OFFER_ICON_SZ, OFFER_ICON_SZ, atlas, center.pos) } }
        else
            icon_node = { n = G.UIT.C, config = { minw = OFFER_ICON_SZ, minh = OFFER_ICON_SZ } }
        end
    end

    return { n = G.UIT.R, config = { align = 'cl', padding = 0.03 }, nodes = {
        { n = G.UIT.C, config = { align = 'cm', padding = 0.02 }, nodes = { icon_node } },
        { n = G.UIT.C, config = { align = 'cl', minw = 1.7 }, nodes = {
            { n = G.UIT.T, config = { text = label, scale = 0.26, colour = lbl_colour } },
        } },
        { n = G.UIT.C, config = { align = 'cm', padding = 0.02 }, nodes = {
            { n = G.UIT.O, config = { object = Sprite(0, 0, 0.26, 0.26, icon_atlas, PB_UTIL.RESOURCE_BY_ID.emerald.pos) } },
            { n = G.UIT.T, config = { text = tostring(offer.cost), scale = 0.28, colour = G.C.WHITE } },
        } },
        { n = G.UIT.C, config = {
            align = 'cm', padding = 0.06, r = 0.08, minw = 0.95, minh = 0.4,
            colour = G.C.GREEN, button = 'bc_buy_villager_offer', func = 'bc_can_buy_villager',
            ref_table = offer, hover = true, shadow = true,
          }, nodes = {
            { n = G.UIT.T, config = { text = 'Trade', scale = 0.24, colour = G.C.UI.TEXT_LIGHT } },
          } },
    } }
end

function PB_UTIL.build_villager_panel()
    local bc = G.GAME and G.GAME.balacraft
    local offers = (bc and bc.villager_offers) or {}
    local store  = (bc and bc.resources) or {}
    local icon_atlas = G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]

    local rows = {}
    -- Header: "Villager" + emerald icon + live count.
    rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
        { n = G.UIT.T, config = { text = 'Villager ', scale = 0.34, colour = G.C.UI.TEXT_LIGHT } },
        { n = G.UIT.O, config = { object = Sprite(0, 0, 0.3, 0.3, icon_atlas, PB_UTIL.RESOURCE_BY_ID.emerald.pos) } },
        { n = G.UIT.T, config = { ref_table = store, ref_value = 'emerald', scale = 0.34, colour = G.C.WHITE } },
    } }
    for _, offer in ipairs(offers) do
        rows[#rows + 1] = offer_row(offer, icon_atlas)
    end

    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0.08, r = 0.1, colour = G.C.BLACK, minw = 3.2 },
        nodes = rows,
    }
end

-- 'cr' = anchor to the right of G.shop; PANEL_OFFSET nudges it down/right toward the deck corner.
-- The exact anchor is the #1 in-game tunable: if it doesn't sit over the deck, change `major` to
-- G.deck or adjust PANEL_OFFSET / align.
function PB_UTIL.attach_villager_panel()
    if G.bc_villager_panel and not G.bc_villager_panel.REMOVED then G.bc_villager_panel:remove() end
    G.bc_villager_panel = UIBox {
        definition = PB_UTIL.build_villager_panel(),
        config = { align = 'cr', offset = PANEL_OFFSET, major = G.shop, bond = 'Weak' },
    }
    local bc = G.GAME and G.GAME.balacraft
    G.bc_villager_panel.bc_offers = bc and bc.villager_offers
    G.bc_villager_panel.bc_major  = G.shop
    if bc then bc._villager_dirty = false end
end

local function remove_villager_panel()
    if G.bc_villager_panel and not G.bc_villager_panel.REMOVED then G.bc_villager_panel:remove() end
    G.bc_villager_panel = nil
end

function PB_UTIL.update_villager_panel()
    local bc = G.GAME and G.GAME.balacraft
    local active = G.STATE == G.STATES.SHOP and G.shop and bc and bc.villager_offers
        and PB_UTIL.icon_atlas and G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]
    if not active then
        remove_villager_panel()
        return
    end
    if not G.bc_villager_panel or G.bc_villager_panel.REMOVED
        or G.bc_villager_panel.bc_major ~= G.shop
        or G.bc_villager_panel.bc_offers ~= bc.villager_offers
        or bc._villager_dirty then
        PB_UTIL.attach_villager_panel()
    end
end

-- Per-frame driver (pcall'd so a transient UI error can't wedge Game:update).
local _game_update = Game.update
function Game:update(dt)
    _game_update(self, dt)
    local ok, err = pcall(PB_UTIL.update_villager_panel)
    if not ok then sendDebugMessage('villager ui error: ' .. tostring(err), 'BalaCraft') end
end
```

- [ ] **Step 2: Syntax-check + confirm the button FUNCS / hooks are referenced**

Run:
```bash
cd "/Users/alessandro/Library/Application Support/Balatro/Mods"
luac -p "BalaCraft/utilities/villager_ui.lua" && echo UI_OK
grep -c "bc_buy_villager_offer\|bc_can_buy_villager" "BalaCraft/utilities/villager_ui.lua"
```
Expected: `UI_OK`, then a count `>= 2`.

---

## Task 4: Wiring — config toggle, load order, state seeding

**Files:**
- Modify: `BalaCraft/config.lua` (add `villager_enabled`)
- Modify: `BalaCraft/main.lua` (load the 3 files inside the resources block)
- Modify: `BalaCraft/utilities/resources.lua` (seed villager fields in `init_game_object`)

- [ ] **Step 1: Add the config toggle**

In `BalaCraft/config.lua`, add a line inside the returned table (e.g. right after `resources_enabled = true,`):
```lua
    villager_enabled = true,
```

- [ ] **Step 2: Load the villager files in `main.lua`**

In `BalaCraft/main.lua`, inside the `if PB_UTIL.config.resources_enabled then` block, immediately AFTER the line
```lua
    PB_UTIL.register_items({ 'tool_consumabletype', 'torch' }, "tools")
```
add:
```lua
    -- Villager Trading: spend emeralds on resource bundles + plain tools (persistent shop
    -- section). Loads last in this block: needs PB_UTIL.RESOURCES/TOOLS, the bc_resource_icons
    -- atlas, the tool consumable centers, and consumable_add (all set up above).
    if PB_UTIL.config.villager_enabled then
        SMODS.load_file("content/villager/trades.lua")()
        SMODS.load_file("utilities/villager.lua")()
        SMODS.load_file("utilities/villager_ui.lua")()
    end
```

- [ ] **Step 3: Seed the villager state fields**

In `BalaCraft/utilities/resources.lua`, in the `Game:init_game_object` wrapper, after the existing `t.balacraft.last_drop = {}` line and before `return t`, add:
```lua
    -- Villager Trading per-shop state (plain values -> auto-saved within a run, auto-reset per
    -- run). Offers are (re)seeded by the shop/reroll hooks in utilities/villager.lua.
    t.balacraft.villager_offers       = {}
    t.balacraft.villager_reroll_index = 0
    t.balacraft._villager_seeded      = false
```

- [ ] **Step 4: Syntax-check the changed files + confirm wiring**

Run:
```bash
cd "/Users/alessandro/Library/Application Support/Balatro/Mods"
luac -p "BalaCraft/config.lua" && luac -p "BalaCraft/main.lua" && luac -p "BalaCraft/utilities/resources.lua" && echo WIRING_OK
grep -n "villager_enabled" "BalaCraft/config.lua"
grep -n "utilities/villager.lua" "BalaCraft/main.lua"
grep -n "villager_offers" "BalaCraft/utilities/resources.lua"
```
Expected: `WIRING_OK`; the `config.lua` grep shows the toggle; the `main.lua` grep shows the load line; the `resources.lua` grep shows the seeded field.

- [ ] **Step 5: Re-run the headless offer test (regression)**

Run:
```bash
cd "/Users/alessandro/Library/Application Support/Balatro/Mods" && lua /tmp/test_villager_offers.lua
```
Expected: `villager offers test OK` (the pure logic is unaffected by wiring).

---

## Task 5: Wiki — flip Villager Trading from "planned" to live

**Files:**
- Modify: `BalaCraft/content/wiki/New mechanics/Villager Trading.md`
- Modify: `BalaCraft/content/wiki/New mechanics/New mechanics.md` (drop the `*(planned)*` marker)
- Modify: `BalaCraft/content/wiki/Resources/Emerald.md` and `BalaCraft/content/wiki/Resources/Resources.md` (drop "coming soon")

- [ ] **Step 1: Rewrite the Villager Trading page in present tense**

Replace the entire contents of `BalaCraft/content/wiki/New mechanics/Villager Trading.md` with:

```markdown
*Mechanic*

**Villager Trading** is a persistent section of the **shop** where you spend ![[icon_emerald.png|20]] [[Emerald|emeralds]] on goods the normal shop doesn't sell. Where every other ore is a crafting material, Emerald is *money*: you spend it here.

## How it works
Each shop shows a small set of **trade offers** (about 3) in the Villager panel. Each offer has an **emerald price** and a **Trade** button — green when you can afford it, greyed when you can't (or, for a tool, when you have no free consumable slot). Buying spends the emeralds, grants the item, and marks that offer **Sold** for the visit.

- Offers are **random each shop** and **re-roll** when you reroll the shop.
- Buying an offer **sells it out** until the next shop.
- The panel only appears in the shop.

## What's on offer (v1)
| Offer | Example | Emerald cost |
| --- | --- | --- |
| Ore bundle | 5× a tier-1 ore / 3× tier-2 / 2× tier-3 | 3 / 4 / 6 |
| [[Tools\|Tool]] | Sword / Pickaxe / Shovel (Wooden→Diamond) | 3–8 by material |
| [[Torch]] | one Torch | 2 |

## Getting emeralds to spend
[[Emerald]] is a tier-2 [[Resources|gathered ore]]: it drops from boss blinds (ante 3–5) and appears in [[Booster Packs|Loot Chests]] at tier-2 frequency.

> **Planned:** enchanted-tool offers (tools that arrive with an [[Enchanting|enchantment]] applied) and biome-flavored trade pools.

[[New mechanics|← Back to mechanics]]
```

- [ ] **Step 2: Drop the `*(planned)*` marker in the mechanics index**

In `BalaCraft/content/wiki/New mechanics/New mechanics.md`, change the Villager Trading row from:
```
| [[Villager Trading]] | Spend [[Emerald\|emeralds]] on resources & tools you can't buy in the shop *(planned)* |
```
to:
```
| [[Villager Trading]] | Spend [[Emerald\|emeralds]] on resources & tools you can't buy in the shop |
```

- [ ] **Step 3: Drop "coming soon" on the Emerald + Resources pages**

In `BalaCraft/content/wiki/Resources/Emerald.md`, change the parenthetical in the second paragraph from:
```
 *(Villager Trading is coming in a future update; for now emeralds simply accumulate.)*
```
to:
```
 You spend them in the shop's [[Villager Trading]] section.
```
And in the small table row, change `| 2 | gathered | Villager trading (*coming soon*) |` to `| 2 | gathered | [[Villager Trading\|Villager trading]] |`.

In `BalaCraft/content/wiki/Resources/Resources.md`, change the emerald table row's last cell from `[[Villager Trading\|Villager trading]] — *coming soon*` to `[[Villager Trading\|Villager trading]]`.

- [ ] **Step 4: Confirm no dangling links / leftover "coming soon"**

Run:
```bash
cd "/Users/alessandro/Library/Application Support/Balatro/Mods/BalaCraft/content/wiki"
grep -rn "coming soon\|(planned)" "New mechanics/Villager Trading.md" "New mechanics/New mechanics.md" "Resources/Emerald.md" "Resources/Resources.md" || echo "NO_STALE_MARKERS"
```
Expected: `NO_STALE_MARKERS` (the only remaining "Planned" is the intentional enchanted-tools callout, which this grep doesn't match).

---

## Task 6: Hand-off — in-game verification (USER runs Balatro)

Agents cannot launch Balatro. After Tasks 1–5, hand the user this checklist:

- [ ] Enter a run, reach the shop. A **Villager** panel shows ~3 offers near the deck corner; it disappears during a blind. (If the anchor sits awkwardly, tune `PANEL_OFFSET` / `align` / `major` in `villager_ui.lua`.)
- [ ] The header shows the live emerald count. Buying an affordable offer **spends emeralds**, grants the item (resources appear in the hotbar; a tool appears as a consumable), and the offer flips to **Sold**.
- [ ] Offers you can't afford are **greyed**; with 0 emeralds the whole panel is greyed but visible. A tool offer is greyed when you have no free consumable slot.
- [ ] **Reroll** the shop → the offers change. Advance to the **next shop** → a fresh set appears, sold flags cleared.
- [ ] **Save & reload** while in the shop → the same offers and Sold states are restored.
- [ ] No crash/error in the Steamodded console across the above.

---

## Self-review notes

- **Spec coverage:** templates+pricing (T1 — spec "Templates & pricing"), generation/seeding/reroll/buy + hooks (T2 — spec "Generation", "Buy logic", "Architecture"), shop panel UI (T3 — spec "UI"), config/load/state-seeding (T4 — spec "Wiring", "State"), wiki (T5). Edge cases (no emeralds, no slot, missing center, save/reload) are handled in `can_buy_villager_offer` / `villager_candidates` / the hybrid-state seeding and exercised in T6.
- **Naming consistency:** `villager_offers`, `villager_reroll_index`, `_villager_seeded`, `_villager_dirty` used identically across `villager.lua`, `villager_ui.lua`, and the `resources.lua` seeding. Buy FUNCS `bc_buy_villager_offer` / gate `bc_can_buy_villager` match between `villager.lua` (definitions) and `villager_ui.lua` (`button=`/`func=`).
- **Load-order safety:** villager loads after tool centers register (main.lua), and `villager_candidates()` reads `G.P_CENTERS` at runtime, so a disabled tool/torch is skipped rather than producing a broken offer.
- **Testability:** the pure offer logic (`villager_candidates`, `build_villager_offers`) is covered by the headless `lua` test; hooks self-skip when `Game`/`G.FUNCS` are absent so that test can load the file.
