# BalaCraft Crafting Phase 2 — Drag-and-Drop + Shaped Matching — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to execute this plan. Dispatch each numbered Task (and each sub-task within T5) to a focused implementation subagent, review its diff against the Task's steps before moving on, and never batch multiple Tasks into one subagent. Every code step below is complete and copy-pasteable — do not summarize, defer, or invent engine APIs.

**Goal:** Replace the read-only 3×3 preview in the existing Crafting Table modal with an interactive drag-and-drop grid. Players place resource **tiles** (real `Card`s) into nine single-slot `CardArea`s, the placed grid is matched **shaped/position-normalized** against `PB_UTIL.RECIPES`, and on a match the Craft button enables. Placing a tile **reserves** the resource (`add_resource(id, -1)`); removing it (drag-out, right-click) or closing the modal **returns** it — so experimentation can never lose resources.

**Architecture:** Three new modules + four edited files. `content/resources/resource_tile.lua` registers NOTHING new; `PB_UTIL.make_resource_tile(rid,x,y)` mints a draggable tile `Card` by building from an always-present harmless base center and then overriding the sprite to the real resource's 71×95 art (`bc_resource_cards`). This uniform factory works for ALL 7 resources — gathered ores AND the crafted `sticks` — and carries the resource id explicitly on the card. `utilities/crafting_match.lua` is pure logic (`read_grid`/`normalize`/`match_grid`). `utilities/crafting_grid.lua` owns the nine cell-areas + palette, tile spawn/destroy, the **custom drop-release** hook (the central risk), right-click remove, reserve/return accounting, and cleanup-on-close. `utilities/crafting_ui.lua` swaps the static preview for the live grid built **ONCE** and mutated in place; `utilities/crafting.lua` factors out `PB_UTIL.produce_output` so both craft paths produce without double-spending. All shared symbols hang off the global `PB_UTIL`; counts mutate **only** through `PB_UTIL.add_resource`.

**Tech Stack:** Lua against Steamodded (SMODS) + Lovely Injector, running in-process inside Balatro. Python 3 + Pillow for procedural asset regeneration (`assets/gen_resources.py`, `assets/utils.py`). No build/lint/test step — the mod is interpreted Lua loaded at game launch.

---

## Verification model

There is **NO automated test harness.** The mod runs only inside Balatro; `luajit`/`lua` are not installed and agents cannot launch the game. "Tests" therefore means three things, used in this order:

1. **Static re-read** — after each edit, re-read the changed file for balanced Lua (`function`/`end`, `do`/`end`, `{`/`}`, `(`/`)`), and confirm every referenced global actually exists in the research/dumps (`G.UIT.*`, `G.C.*`, `Sprite`, `Card`, `CardArea`, `G.CARD_W`/`G.CARD_H`, `G.P_CENTERS`, `G.CURSOR.T`, `G.CONTROLLER`, `play_sound`, `PB_UTIL.*`). Lua-syntax sanity can be checked with `python3 -c "..."`-style brace counting only — there is no interpreter to load `G`.
2. **Console-driven checks** — for the PURE-LOGIC matcher (T3) and the produce/reserve helpers (T4), the human pastes `PB_UTIL.*` snippets into the Steamodded in-game debug console. Real snippets are embedded in those Tasks. These run against hand-built Lua tables and do **not** require the UI.
3. **In-game observation** — anything marked **In-game:** is the human's to run by launching Balatro and operating the modal. Agents must NOT claim these pass; they hand the work over. **Handy is confirmed installed in this environment**, so the Handy-coexistence checks (drag-release routing and right-click) in T7 are MANDATORY, not optional.

Assets (T1) are verifiable by running Python directly (Pillow is available in the project's toolchain) and checking printed dimensions.

---

## File structure

**New files**

| File | Responsibility |
|---|---|
| `BalaCraft/content/resources/resource_tile.lua` | **Registers NOTHING new.** `PB_UTIL.make_resource_tile(rid,x,y)` mints a draggable tile `Card` from an always-present harmless base center (`c_balacraft_res_wood`) and then overrides `card.children.center` to the real resource's 71×95 art on `bc_resource_cards` at `r.pos`. Uniform across ALL 7 resources (gathered AND crafted `sticks`) — the id is carried explicitly on the card, NOT derived from the center key. Plus `PB_UTIL.tile_resource`. The tile is never emplaced into `G.consumeables`/`G.shop_*`/`G.pack_cards`/`G.play`, so it never pools, scores, or gets used. |
| `BalaCraft/utilities/crafting_match.lua` | Pure shaped-matching logic: `PB_UTIL.read_grid()`, `PB_UTIL.normalize(grid)`, `PB_UTIL.match_grid(grid)`. No UI. |
| `BalaCraft/utilities/crafting_grid.lua` | Nine single-slot cell-areas + palette; tile spawn/destroy; custom cursor-up drop-release; right-click remove; reserve/return; cleanup-on-close safety net. |

**Edited files**

| File | Change |
|---|---|
| `BalaCraft/utilities/crafting.lua` | Factor out `PB_UTIL.produce_output(recipe)` (the produce-half + sound); `craft` becomes spend → `produce_output`. |
| `BalaCraft/utilities/crafting_ui.lua` | Replace `pattern_preview(selected)` with the live grid + palette built **ONCE**; output-slot label + Craft button reflect `match_grid` by **mutating existing UIElements in place** (per-frame `config.func` + ref_table/ref_value binding + a single output-ICON sprite swap via `get_UIE_by_ID`), never by rebuilding the overlay; grid-craft path (`bc_grid_craft`); auto-fill spawns real tiles. |
| `BalaCraft/assets/gen_resources.py` | Draw a Sticks 71×95 card; grow card sheet **3×2 → 3×3** (per below; spec's "4×2" is the stale older shape — registry already commits to a 3-row layout). |
| `BalaCraft/content/resources/registry.lua` | **No functional pos change** (existing `pos = {x=0,y=2}` already serves the 3×3 card sheet); comment-only clarification optional. |
| `BalaCraft/utilities/definitions.lua` | Add `'resource_tile'` to `PB_UTIL.ENABLED_RESOURCES` (after `'resource_consumabletype'`). |
| `BalaCraft/main.lua` | Load `utilities/crafting_match.lua` + `utilities/crafting_grid.lua` inside the `resources_enabled` block. |

**Registration-order note:** `resource_tile.lua` must load **after** `resource_consumabletype.lua` (whose `SMODS.ConsumableType{ key='balacraft_resource' }` + per-ore `SMODS.Consumable{ set='balacraft_resource', atlas='bc_resource_cards' }` create the `c_balacraft_res_wood` base center the factory builds from). Since the whitelist loads in array order and the factory only runs at modal-open (runtime), ordering `'resource_tile'` after `'resource_consumabletype'` in `ENABLED_RESOURCES` is sufficient.

**Reused unchanged:** the Phase 1 modal shell, recipe list + greyed/locked gating, `PB_UTIL.RECIPES`/`recipe_ingredients`/`recipe_by_key`, `PB_UTIL.can_craft`/`can_afford`/`has_joker_room`, the global `joker_add`, `PB_UTIL.add_resource` as the single spend/produce funnel, `G.FUNCS.overlay_menu` + the `G.NO_MOD_CURSOR_STACK` cursor-layer-leak guard.

---

## RESERVE/PRODUCE accounting (read before T4/T5/T6/T7)

Phase 1's `PB_UTIL.craft(recipe)` **spends** (`add_resource(id, -n)`) then **produces**. In Phase 2 ingredients are **already reserved** when the player drops each tile. So the grid-craft path produces **without spending again**, and every removal path credits **exactly once**.

**The one rule:** *a tile credit fires exactly once per debit.* Place debits; every removal path (drag-out, right-click, swap-evict, modal-close) credits; commit-craft consumes WITHOUT crediting (the reservation **is** the spend).

**Build-once model (critical — there is NO refresh-rebuild path).** The nine cell-areas are embedded as `{n=G.UIT.O, config={object=area}}` and the overlay is **built exactly once** on open. We must **never** call `G.FUNCS.overlay_menu` again while the modal is open: `overlay_menu` does `G.OVERLAY_MENU:remove()` first (`button_callbacks.lua:1347`), and `UIElement:remove` destroys every embedded object — `self.config.object:remove(); self.config.object = nil` (`ui.lua:1085-1089`) → `CardArea:remove` (`cardarea.lua:715`) destroys all placed tiles **with no credit**. A rebuild-on-change design therefore silently loses resources. Phase 2 instead **mutates existing UIElements in place** (output-slot label + Craft button + output icon) after every grid change — no overlay rebuild ever.

Lifecycle of each accounting path:
- **Place a tile** (drag-drop into empty cell, palette click, auto-fill cell, swap-into) → `add_resource(id, -1)` once, at spawn. The tile now holds the reservation.
- **Remove a tile** (drag-out, right-click, swap-evict the prior occupant) → `add_resource(id, +1)` once.
- **Modal close** (Esc, the overlay close button, any `exit_overlay_menu` — note `bc_grid_craft` does NOT close the modal; it crafts in place and leaves it open) → `destroy_craft_cells` credits every still-placed tile +1 and reclaims a mid-drag tile +1, THEN destroys the areas. This is the safety net.
- **Grid Craft (commit)** → the placed tiles ARE the spent ingredients (already debited). `clear_craft_cells(false)` destroys them WITHOUT crediting; then `PB_UTIL.produce_output(recipe)`. Never call `PB_UTIL.craft` here (double-spend).
- **Overlay-teardown path.** Because embedded `G.UIT.O` CardAreas are auto-`:remove()`d by the engine whenever the *overlay UIBox* is torn down, the **only** time the UIBox is torn down while our cells are live is on **close** (there is no rebuild path). We front-run that teardown: the `exit_overlay_menu` wrap calls `destroy_craft_cells` (credit + remove) **before** `_orig_exit` runs `G.OVERLAY_MENU:remove()`. After `destroy_craft_cells`, `PB_UTIL.craft_cells = nil`; the engine's later recursive `UIElement:remove` on the (already-removed) areas is a harmless double-`:remove()` (guarded by `config.object = nil` at `ui.lua:1088`). **No tile is destroyed by the engine teardown with credit owed, because we credited and emptied the cells first.**

**One-credit-per-debit proof (every path):**

| Path | Debit | Credit | Net effect | Once? |
|---|---|---|---|---|
| **spawn-on-drag** (`spawn_tile_for_drag`) / palette spawn | `add_resource(rid,-1)` at spawn | — | tile holds reservation | ✓ exactly one debit |
| **drop-in-empty-cell** (release hook → `place_in_cell`) | (already debited at spawn) | — | reservation stays with placed tile | ✓ no extra |
| **swap-evict** (`place_in_cell`, cell occupied) | (new tile already debited) | `return_tile(old)` → `+1` | old returned once, new holds reservation | ✓ one credit for evicted |
| **drag-out** (release hook, no cell under cursor) | (debited at spawn) | `return_tile(dropped)` → `+1` | net 0 | ✓ one credit |
| **right-click** (`queue_R_cursor_press` wrap) | (debited at spawn) | `return_tile(cell tile)` → `+1` | net 0 | ✓ one credit |
| **palette-click no empty cell** (`spawn_tile_to_cell`) | `-1` at spawn | `return_tile` → `+1` | net 0 (couldn't place) | ✓ one credit |
| **grid-craft commit** (`bc_grid_craft`) | (placed tiles already debited) | **none** — `clear_craft_cells(false)` | reservation == spend; `produce_output` adds output | ✓ no credit by design |
| **modal-close** (`exit_overlay_menu` wrap → `destroy_craft_cells`) | (placed/mid-drag tiles debited) | `+1` per placed tile **and** `+1` mid-drag tile | every reservation returned | ✓ one credit each, before engine teardown |
| **overlay engine teardown** (after our wrap) | — | — | cells already emptied + nil; engine double-`:remove()` is a no-op | ✓ destroys nothing owed |
| **auto-fill** (`bc_autofill`) | `clear_craft_cells(true)` credits prior placement, then `-1` per spawned pattern cell (guarded by `can_afford`) | prior placement `+1` each | prior returned, new reserved; affordability guard prevents partial-fill strand | ✓ balanced |

There is **no path** where a tile is destroyed without either a credit or being a deliberate spend. T7's audit walks this table against the live implementation.

---

## T1 — Sticks 71×95 card art (gen_resources.py + registry + regen)

Grow the **card** sheet to **3×3** (not the spec's stale "4×2"): this keeps all 6 ore card positions byte-for-byte and lets `sticks`' existing `pos = {x=0,y=2}` index BOTH atlases (slot 6 = (0,2) in any 3-wide grid), preserving the codebase's "one pos indexes both sheets" invariant. The 4×2 alternative would force a separate `card_pos` field — rejected. **In addition to growing the sheet, T1 MUST actually DRAW the Sticks card** by iterating `ICONS` (7 entries) instead of `ORES` (6) in `build_cards()`, so cell (0,2) is filled — otherwise the third row renders blank.

**Files:**
- `BalaCraft/assets/gen_resources.py`
- `BalaCraft/content/resources/registry.lua` (comment-only)
- regenerated: `BalaCraft/assets/1x/resource_cards.png`, `BalaCraft/assets/2x/resource_cards.png`

- [ ] **Step 1** — In `gen_resources.py`, change the card grid rows from 2 to 3. Edit line 13:

```python
COLS, ROWS = 3, 3
```

- [ ] **Step 1 note (shared-COLS coupling — CAUTION).** `COLS` is shared by BOTH `build_icons()` (icon-sheet width `= ICON*COLS`) and `build_cards()` (card-sheet width `= CARD_W*COLS`); `ROWS` is used **only** by `build_cards()` for card-sheet height, while `build_icons()` uses the independent `ICON_ROWS`. This edit changes **only `ROWS` (2 → 3)** and leaves `COLS = 3` untouched, which is exactly why the icon sheet stays `102×102` and only the card sheet grows to `213×285`. **`ROWS` is the only safe knob for card-sheet height.** If a future edit ever changes `COLS`, BOTH sheets move together — do not. The expected stdout (`wrote resource_icons.png (102, 102)` / `wrote resource_cards.png (213, 285)`) holds precisely because `COLS` is unchanged.

- [ ] **Step 2** — In `gen_resources.py`, update the docstring for accuracy. Replace line 5:

```python
  assets/1x/resource_cards.png  -> 71x95 cells, 3x3 grid (213x285)
```

  And replace line 7 — drop the stale "(icons only)" note since sticks now has card art:

```python
Ore order (row-major): wood, cobblestone, coal, iron, gold, diamond, sticks.
```

- [ ] **Step 3** — In `gen_resources.py`, make `build_cards()` iterate `ICONS` (7 entries, sticks at index 6 = cell (0,2), matching registry `sticks` pos `{x=0,y=2}`) instead of `ORES`, and give sticks a tier-1 green band. Replace the two lines 110–111:

```python
    tiers = {"wood": 1, "cobblestone": 1, "coal": 1, "iron": 2, "gold": 2, "diamond": 3, "sticks": 1}
    for i, (_id, tex) in enumerate(ICONS):
```

  The rest of `build_cards()` is unchanged: each card is `CARD_BG`, a 6px tier-tint band, the 16×16 texture `nn(tex, 3)` upscaled to 48×48 and composited at `((CARD_W-48)//2, (CARD_H-48)//2 - 4)` = (11, 19). Sticks' `sticks()` texture already exists (lines 68–77) and is already in `ICONS` (line 88). **Cosmetic note:** `sticks()` returns a 16×16 with a fully transparent background (unlike the opaque ores), so the sticks card shows bare `CARD_BG` around the two sticks — this is fine/expected, just emptier-looking than the ore cards.

- [ ] **Step 4** — Regenerate the 1× sheets. Run from the `Mods/` directory:

```bash
python3 BalaCraft/assets/gen_resources.py
```

  Expected stdout (verify exactly):

```
wrote resource_icons.png (102, 102)
wrote resource_cards.png (213, 285)
```

  `resource_icons.png` is unchanged (102×102); `resource_cards.png` grows 213×190 → **213×285**.

- [ ] **Step 5** — Derive the 2× sheets. `utils.py`'s `__main__` only scales `farlands.png`, so call `scale_image` explicitly:

```bash
python3 -c "import sys; sys.path.insert(0,'BalaCraft/assets'); from utils import scale_image; scale_image('BalaCraft/assets/1x/resource_cards.png','BalaCraft/assets/2x/resource_cards.png',2); scale_image('BalaCraft/assets/1x/resource_icons.png','BalaCraft/assets/2x/resource_icons.png',2)"
```

  Expected: `2x/resource_cards.png` → **426×570**; `2x/resource_icons.png` → **204×204**.

- [ ] **Step 6** — Confirm `registry.lua` needs NO functional change. The sticks entry (line 10) already reads `pos = { x = 0, y = 2 }`, which is now correct for both `bc_resource_cards` (3×3) and `bc_resource_icons` (3×3). Optionally update the comment on line 17 to note both sheets are 3×3. Do NOT add a `card_pos` field — the single-pos invariant holds. Verify by reading the saved PNGs' sizes:

```bash
python3 -c "from PIL import Image; print(Image.open('BalaCraft/assets/1x/resource_cards.png').size, Image.open('BalaCraft/assets/2x/resource_cards.png').size)"
```

  Expected: `(213, 285) (426, 570)`.

- [ ] **Step 7 — Commit.**

```bash
git add BalaCraft/assets/gen_resources.py BalaCraft/assets/1x/resource_cards.png BalaCraft/assets/2x/resource_cards.png BalaCraft/assets/1x/resource_icons.png BalaCraft/assets/2x/resource_icons.png BalaCraft/content/resources/registry.lua
git commit -m "feat(assets): draw Sticks 71x95 card; grow card sheet to 3x3

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

**In-game:** (deferred to T6/T7) the sticks card art appears wherever a crafted resource renders as a 71×95 card.

---

## T2 — Resource-tile card mechanism (uniform inert draggable tile carrying resource id)

The tile factory **registers NOTHING new** and works **uniformly for ALL 7 resources, including the crafted `sticks`**. It does NOT reuse a per-ore `c_balacraft_res_<id>` center (that model is broken — `resource_consumabletype.lua` only creates centers for `kind=='gathered'` at line 26, so `c_balacraft_res_sticks` does not exist, and `sticks` is an ingredient in 3 of 4 recipes plus the output of the 4th). Instead the factory builds a plain `Card` from an **always-present harmless base center** (`c_balacraft_res_wood`, which always exists), then **overrides the card's center sprite** to the real resource's 71×95 art at `r.pos`. The id is carried **explicitly** on the card, NOT derived from the center key — so the base center being `wood` for a `sticks` tile is irrelevant.

**Verified:** `Sprite:set_sprite_pos` exists (sprite.lua:25); `card.children.center` is the center sprite and the engine itself sets it the same way (`children.center.atlas = G.ASSET_ATLAS[...]; children.center:set_sprite_pos(pos)`, card.lua:171-173). The override is sound for every resource. Because no `SMODS.*` call runs here, there is no loc-nil crash and no pool insert.

**Files:**
- `BalaCraft/content/resources/resource_tile.lua` (new)
- `BalaCraft/utilities/definitions.lua` (whitelist)

- [ ] **Step 1** — Create `BalaCraft/content/resources/resource_tile.lua`. This file registers NOTHING; it only defines factory helpers on `PB_UTIL`:

```lua
-- Inert, draggable, display-only resource tiles. Registers NOTHING new.
-- make_resource_tile builds a plain Card from an always-present harmless base center
-- (c_balacraft_res_wood) and then OVERRIDES the center sprite to the real resource's
-- 71x95 art on bc_resource_cards at r.pos. This works UNIFORMLY for every resource id
-- in PB_UTIL.RESOURCES -- gathered ores AND the crafted 'sticks' -- because the id is
-- carried explicitly on the card, NOT derived from the base center key. No SMODS.* call
-- runs here, so there is no loc-nil crash and no pool insert. The tile Card is never
-- emplaced into G.consumeables/G.shop_*/G.pack_cards/G.play, so it never scores or
-- gets used.

-- Build an inert, draggable tile Card for resource id `rid` (e.g. 'wood', 'sticks').
-- Returns the Card, or nil if the resource id or base center is missing.
function PB_UTIL.make_resource_tile(rid, x, y)
    local r = PB_UTIL.RESOURCE_BY_ID[rid]
    if not r then return nil end
    -- Build from an always-present harmless center, then override the sprite to the
    -- real resource's 71x95 art. Works for gathered AND crafted (sticks).
    local base = G.P_CENTERS['c_balacraft_res_wood']
    if not base then return nil end
    local card = Card(x or 0, y or 0, G.CARD_W, G.CARD_H, nil, base,
        { bypass_discovery_center = true, bypass_discovery_ui = true, discover = false })
    if card.children and card.children.center then
        card.children.center.atlas = G.ASSET_ATLAS['bc_resource_cards']
        card.children.center:set_sprite_pos(r.pos)
    end
    card.balacraft_resource = rid
    if card.ability then card.ability.balacraft_resource = rid end
    card.no_ui = true
    return card
end

-- Recover the resource id from a tile Card.
function PB_UTIL.tile_resource(card)
    if not card then return nil end
    return card.balacraft_resource or (card.ability and card.ability.balacraft_resource) or nil
end
```

- [ ] **Step 2** — Whitelist the file so `register_items` loads it. In `definitions.lua`, add `'resource_tile'` to `PB_UTIL.ENABLED_RESOURCES`, **after** `'resource_consumabletype'`:

```lua
PB_UTIL.ENABLED_RESOURCES = {
    'registry',
    'resource_consumabletype',
    'recipes',
    'resource_tile',
}
```

  Order matters: the factory builds from the `c_balacraft_res_wood` center created by `resource_consumabletype.lua`. That center injects at load; the factory only runs at modal-open (runtime), so placing `'resource_tile'` last is sufficient.

- [ ] **Step 3 — Static check.** Re-read `resource_tile.lua`. Confirm it makes **no** `SMODS.*` call (so it cannot crash at load and cannot pool). Confirm balanced `function`/`end`/`{`/`}`. Confirm referenced symbols exist: `Card(X,Y,W,H,card,center,params)` (card.lua:5), `G.CARD_W`/`G.CARD_H`, `G.P_CENTERS`, `G.ASSET_ATLAS`, `Sprite:set_sprite_pos` (sprite.lua:25), `PB_UTIL.RESOURCE_BY_ID` (registry.lua:14), `r.pos`. Confirm the base center `c_balacraft_res_wood` is registered (resource_consumabletype.lua creates `SMODS.Consumable{ key='res_wood', ... }` → `c_balacraft_res_wood`, and `wood` is `kind='gathered'`).

- [ ] **Step 4 — Commit.**

```bash
git add BalaCraft/content/resources/resource_tile.lua BalaCraft/utilities/definitions.lua
git commit -m "feat(resources): uniform resource-tile factory (sprite override, no new registration)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

**In-game (deferred to T6):** `PB_UTIL.make_resource_tile('wood', 0, 0)` returns a Card showing the Wood card art; `PB_UTIL.make_resource_tile('sticks', 0, 0)` returns a Card showing the Sticks card art (NOT nil); `PB_UTIL.tile_resource(card)` returns the id. No new center appears in the collection or shop, and the game still loads (no injection crash).

---

## T3 — crafting_match.lua (pure shaped-matching logic)

Pure logic, no UI, console-testable. `read_grid` reads the live cell-areas (provided by T5, but tolerates them being absent → all-`false`); `normalize` trims empty border rows/cols; `match_grid` compares normalized placed grid against each recipe's normalized pattern. Recipe-pattern normalization is memoized at first call.

**Files:**
- `BalaCraft/utilities/crafting_match.lua` (new)

- [ ] **Step 1** — Create `BalaCraft/utilities/crafting_match.lua`:

```lua
-- Pure shaped-matching logic for the crafting grid. No UI.
-- A "grid" here is a row-major array of rows; each row is an array of cells,
-- where a cell is a resource id string or `false` (empty). Matching is shaped
-- and position-normalized: trim empty border rows/cols from both the placed
-- grid and each recipe pattern, then compare cell-by-cell. No mirror/rotation.

-- Read the live 3x3 placed grid from PB_UTIL.craft_cells (set up by crafting_grid.lua).
-- Returns a 3x3 row-major table of ids or `false`. Tolerant of cells not existing yet.
function PB_UTIL.read_grid()
    local grid = {}
    local cells = PB_UTIL.craft_cells
    for i = 1, 3 do
        grid[i] = {}
        for j = 1, 3 do
            local id = false
            local area = cells and cells[i] and cells[i][j]
            if area and area.cards and area.cards[1] then
                id = PB_UTIL.tile_resource(area.cards[1]) or false
            end
            grid[i][j] = id
        end
    end
    return grid
end

-- Trim fully-empty leading/trailing rows and columns; return the tight bbox
-- (still row-major, `false` for interior gaps). A fully-empty grid -> {} (0 rows).
function PB_UTIL.normalize(grid)
    local rows = #grid
    if rows == 0 then return {} end
    local cols = #grid[1]
    -- find occupied bounding box
    local min_i, max_i, min_j, max_j = nil, nil, nil, nil
    for i = 1, rows do
        for j = 1, cols do
            if grid[i][j] then
                if not min_i or i < min_i then min_i = i end
                if not max_i or i > max_i then max_i = i end
                if not min_j or j < min_j then min_j = j end
                if not max_j or j > max_j then max_j = j end
            end
        end
    end
    if not min_i then return {} end -- nothing placed
    local out = {}
    for i = min_i, max_i do
        local row = {}
        for j = min_j, max_j do
            row[#row + 1] = grid[i][j] or false
        end
        out[#out + 1] = row
    end
    return out
end

-- Two normalized grids are equal iff same dims and same value in every cell.
local function grids_equal(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if #a[i] ~= #b[i] then return false end
        for j = 1, #a[i] do
            if a[i][j] ~= b[i][j] then return false end
        end
    end
    return true
end

-- Memoized normalized pattern per recipe (patterns never change at runtime).
local _norm_cache = {}
local function normalized_pattern(recipe)
    if _norm_cache[recipe] == nil then
        _norm_cache[recipe] = PB_UTIL.normalize(recipe.pattern)
    end
    return _norm_cache[recipe]
end

-- Match a placed grid (row-major of ids/false) against PB_UTIL.RECIPES.
-- Returns the matched recipe table, or nil. An empty placed grid never matches.
function PB_UTIL.match_grid(grid)
    local placed = PB_UTIL.normalize(grid)
    if #placed == 0 then return nil end
    for _, recipe in ipairs(PB_UTIL.RECIPES) do
        if grids_equal(placed, normalized_pattern(recipe)) then
            return recipe
        end
    end
    return nil
end
```

  Note: `grids_equal` compares `false == false` (both empty interior cells) and `'wood' == 'wood'` correctly; `false ~= 'wood'` distinguishes empty-vs-filled at the same normalized position, which is exactly the shaped requirement.

- [ ] **Step 2** — Load it in `main.lua` so the console checks below work. (This is also required by T6; doing it here lets T3's console checks run immediately.) In `main.lua`, inside the `resources_enabled` block, add the load line after `crafting.lua` and before `crafting_ui.lua`:

```lua
if PB_UTIL.config.resources_enabled then
    SMODS.load_file("utilities/resources.lua")()
    SMODS.load_file("utilities/resource_ui.lua")()
    SMODS.load_file("utilities/crafting.lua")()
    SMODS.load_file("utilities/crafting_match.lua")()
    SMODS.load_file("utilities/crafting_ui.lua")()
    PB_UTIL.register_items(PB_UTIL.ENABLED_RESOURCES, "resources")
end
```

  (`crafting_grid.lua` is added to this block in T6 — leave that for now.)

- [ ] **Step 3 — Static check.** Re-read `crafting_match.lua` for balanced blocks. Confirm it references only `PB_UTIL.craft_cells`, `PB_UTIL.tile_resource`, `PB_UTIL.RECIPES`, `PB_UTIL.normalize` — all defined (T2, T3, recipes.lua). It does NOT touch the engine UI, so it is safe to console-test before T5 exists (`read_grid` returns all-`false` when `craft_cells` is nil).

- [ ] **Step 4 — Console checks (human runs in the Steamodded debug console).** These exercise the pure logic on hand-built tables. Paste each and confirm the printed result:

```lua
-- (1) Sticks pattern (vertical 2x wood) matches itself, normalized:
local g = { {false,'wood',false}, {false,'wood',false}, {false,false,false} }
print(PB_UTIL.match_grid(g) and PB_UTIL.match_grid(g).key)   -- expect: sticks

-- (2) The SAME two wood tiles shifted to a different column still match (position-normalized):
local g2 = { {false,false,'wood'}, {false,false,'wood'}, {false,false,false} }
print(PB_UTIL.match_grid(g2) and PB_UTIL.match_grid(g2).key)  -- expect: sticks

-- (3) Two wood placed HORIZONTALLY must NOT match sticks (shape differs):
local g3 = { {'wood','wood',false}, {false,false,false}, {false,false,false} }
print(PB_UTIL.match_grid(g3))                                 -- expect: nil

-- (4) Stone Pickaxe exact shape matches:
local g4 = { {'cobblestone','cobblestone','cobblestone'}, {false,'sticks',false}, {false,'sticks',false} }
print(PB_UTIL.match_grid(g4) and PB_UTIL.match_grid(g4).key)  -- expect: stone_pickaxe

-- (5) Empty grid never matches:
print(PB_UTIL.match_grid({ {false,false,false},{false,false,false},{false,false,false} })) -- expect: nil

-- (6) normalize trims to the tight bbox:
local n = PB_UTIL.normalize({ {false,false,false},{false,'iron',false},{false,'sticks',false} })
print(#n, #n[1], n[1][1], n[2][1])                            -- expect: 2  1  iron  sticks

-- (7) Iron Sword vs Iron Shovel are distinguished by shape (both single-column):
local sword  = { {false,'iron',false},{false,'iron',false},{false,'sticks',false} }
local shovel = { {false,'iron',false},{false,'sticks',false},{false,'sticks',false} }
print(PB_UTIL.match_grid(sword).key, PB_UTIL.match_grid(shovel).key) -- expect: iron_sword  iron_shovel
```

  If any line prints unexpectedly, the matcher is wrong — fix before proceeding. (Cross-check recipe keys/patterns against `content/resources/recipes.lua` before relying on the exact expected strings above.)

- [ ] **Step 5 — Commit.**

```bash
git add BalaCraft/utilities/crafting_match.lua BalaCraft/main.lua
git commit -m "feat(crafting): add pure shaped-matching logic (read_grid/normalize/match_grid)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## T4 — Factor out PB_UTIL.produce_output (no double-spend)

Extract the produce-half + sound from `PB_UTIL.craft` into `PB_UTIL.produce_output(recipe)`. Phase 1 `craft` keeps spend → `produce_output`. The Phase 2 grid path (T6) calls `produce_output` directly after consuming already-reserved tiles. See the RESERVE/PRODUCE accounting section.

**Files:**
- `BalaCraft/utilities/crafting.lua`

- [ ] **Step 1** — In `crafting.lua`, replace the single `PB_UTIL.craft` function (lines 35–49) with a `produce_output` helper plus a `craft` that delegates to it. New text:

```lua
-- Produce the recipe's output (no spending). Resource -> add_resource; joker ->
-- joker_add. Plays the craft sound. Both craft paths share this so the produce
-- logic lives in one place: Phase 1 click-craft (spend then produce) and Phase 2
-- grid-craft (consume already-reserved tiles, then produce -- no second spend).
function PB_UTIL.produce_output(recipe)
    local out = recipe.output
    if out.type == 'resource' then
        PB_UTIL.add_resource(out.id, out.amount or 1)
    elseif out.type == 'joker' then
        joker_add(out.id)
    end
    play_sound('timpani', 0.8)
end

-- Returns true on success. Spends ingredients, then produces the output.
function PB_UTIL.craft(recipe)
    if not PB_UTIL.can_craft(recipe) then return false end
    for id, n in pairs(PB_UTIL.recipe_ingredients(recipe)) do
        PB_UTIL.add_resource(id, -n)
    end
    PB_UTIL.produce_output(recipe)
    return true
end
```

  This is behavior-preserving for Phase 1: `craft` still spends each ingredient then produces + plays the sound. The only change is the produce/sound moved into `produce_output`. (`out.amount or 1` matches the original at crafting.lua:43.)

- [ ] **Step 2 — Static check.** Re-read `crafting.lua`. Confirm `produce_output` is defined BEFORE `craft` uses it (it is — file order above), `joker_add` is the true global, `play_sound` and `PB_UTIL.add_resource` exist. Confirm balanced `function`/`end`.

- [ ] **Step 3 — Console checks (human, with a resource buffer first).** Verify `craft` still works exactly as before (spend + produce), and `produce_output` alone produces without spending:

```lua
-- Setup: give plenty of wood so the spend path is observable.
PB_UTIL.set_resource('wood', 10); print(PB_UTIL.get_resource_count('wood')) -- 10

-- Phase 1 craft of Sticks spends 2 wood, produces 2 sticks:
local r = PB_UTIL.recipe_by_key('sticks')
print(PB_UTIL.craft(r))                                  -- true
print(PB_UTIL.get_resource_count('wood'))                -- 8  (spent 2)
print(PB_UTIL.get_resource_count('sticks'))              -- 2  (produced 2)

-- produce_output alone produces WITHOUT spending:
PB_UTIL.produce_output(r)
print(PB_UTIL.get_resource_count('wood'))                -- 8  (unchanged -- no spend)
print(PB_UTIL.get_resource_count('sticks'))              -- 4  (+2 produced)
```

- [ ] **Step 4 — Commit.**

```bash
git add BalaCraft/utilities/crafting.lua
git commit -m "refactor(crafting): extract produce_output so grid-craft avoids double-spend

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## T5 — crafting_grid.lua (cell-areas, palette, literal drag, drop hook, right-click, cleanup)

Highest-risk module; the one non-native interaction. Real `Card`s in nine single-slot `CardArea`s embedded once as `{n=G.UIT.O, config={object=area}}`. The drop hook wins over native routing by emplacing **synchronously in `L_cursor_release` before** the next `Controller:update` tick tears the drag down.

**Critical rationale.** `Controller:L_cursor_release` does **not** clear `self.dragging.target` (it only records `cursor_up.T`/`cursor_up.target`, `controller.lua:1129-1146`). The drag is torn down later, on the **next** `Controller:update` tick: `dragging.target:stop_drag(); states.drag.is=false; dragging.target=nil` (`controller.lua:331-337`). Because `love.mousereleased` calls `L_cursor_release` **synchronously** (`main.lua:1130`) before that update, `self.dragging.target` is still valid inside our wrap. We emplace there and then **null `self.dragging.target`** — the load-bearing action: the next `Controller:update` does `self.dragging.prev_target = self.dragging.target` (`controller.lua:315`) BEFORE the native `released_on` routing reads `prev_target` (`controller.lua:348`), so nulling `dragging.target` propagates `nil` into `prev_target` next tick and neutralizes native `released_on`. (We also null `prev_target` in the wrap as belt-and-suspenders, but that line is redundant — the synchronous `dragging.target = nil` is what matters. Native `released_on` for a Card → `area:release` is a no-op anyway.)

**Custom area type keeps tiles draggable.** `CardArea:set_ranks` forces `card.states.drag.can=false` for `type ∈ {deck,play,shop,consumeable}` (`cardarea.lua:253-254`); any other type falls into the else-branch and keeps `drag.can=true` (`cardarea.lua:256`). **Each cell-area uses `type='balacraft_tile'`** (a custom value), so emplaced tiles stay draggable with no manual re-enable. `align_cards` also no-ops for custom types (`cardarea.lua:446-485`), so we snap tiles to cell-center ourselves.

**Empty-cell collision.** A generic `CardArea` has `states.collide.can=false` (`cardarea.lua:8`), so empty cells won't appear in `controller.collision_list`. We **call `area:collides_with_point(G.CURSOR.T)` directly** (works on empty areas: `container` defaults to `G.ROOM`, non-nil — `node.lua:69,145`); `G.CURSOR.T` is in the same board units as `cell.T` and `collides_with_point` applies the room offset internally (`node.lua:158-175`).

The module exposes builders + handlers consumed by T6. It does NOT itself call `overlay_menu` — `crafting_ui.lua` assembles the modal. Split into three sub-tasks; the file is APPENDED to across T5a/T5b/T5c (loaded once after all three).

### T5a — Cell-areas + palette node builders + state

**Files:** `BalaCraft/utilities/crafting_grid.lua` (new)

- [ ] **Step 1** — Create `BalaCraft/utilities/crafting_grid.lua` with module state and builders:

```lua
-- Interactive 3x3 crafting grid + palette. Owns live state while the modal is open:
-- nine single-slot CardAreas (PB_UTIL.craft_cells), spawned tiles, reserve/return
-- accounting. Tiles are real Cards from bc_resource_cards (resource_tile.lua). The
-- custom cursor-up drop hook (T5b) emplaces a dragged tile into the cell under the
-- cursor BEFORE the engine tears the drag down; cleanup-on-close (T5c) credits every
-- still-placed tile. The overlay is built ONCE and never rebuilt while open.

PB_UTIL.craft_cells = PB_UTIL.craft_cells or nil   -- 3x3 row-major of CardArea, or nil

local CELL_W = G.CARD_W
local CELL_H = 1.05 * G.CARD_H

-- Create the nine single-slot cell-areas (idempotent: destroys any prior set first).
-- type='balacraft_tile' is a CUSTOM value: set_ranks keeps drag enabled (cardarea.lua:256)
-- and align_cards no-ops (cardarea.lua:446), so we snap tiles to cell-center ourselves.
function PB_UTIL.build_craft_cells()
    PB_UTIL.destroy_craft_cells()  -- defined in T5c; safe no-op if nothing to destroy
    local cells = {}
    for i = 1, 3 do
        cells[i] = {}
        for j = 1, 3 do
            local area = CardArea(
                G.ROOM.T.x, G.ROOM.T.y,          -- X,Y throwaway; the G.UIT.O node repositions it
                CELL_W, CELL_H,
                { card_limit = 1, type = 'balacraft_tile', highlight_limit = 0, card_w = G.CARD_W }
            )
            cells[i][j] = area
        end
    end
    PB_UTIL.craft_cells = cells
    return cells
end

-- One grid cell as an overlay node embedding the CardArea (the booster-pack pattern).
local function cell_object_node(area)
    return {
        n = G.UIT.C,
        config = { align = 'cm', padding = 0.05, minw = CELL_W + 0.1, minh = CELL_H + 0.1,
                   r = 0.1, colour = G.C.UI.TRANSPARENT_DARK },
        nodes = { { n = G.UIT.O, config = { object = area } } },
    }
end

-- Build the 3x3 grid node tree (call AFTER build_craft_cells). Returns a G.UIT.C.
function PB_UTIL.build_grid_node()
    local rows = {}
    for i = 1, 3 do
        local row = { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {} }
        for j = 1, 3 do
            row.nodes[#row.nodes + 1] = cell_object_node(PB_UTIL.craft_cells[i][j])
        end
        rows[#rows + 1] = row
    end
    return { n = G.UIT.C, config = { align = 'cm', padding = 0.08, r = 0.1, colour = G.C.BLACK }, nodes = rows }
end

-- One palette source: resource icon + a live count badge. Clicking it
-- (button 'bc_palette_pick') spawns a tile into the first empty cell. Dimming for
-- unowned sources is via the UIT container colour + TEXT_INACTIVE text colour
-- (Sprite has NO set_alpha; do NOT call it -- it mirrors a pre-existing no-op in
-- resource_ui.lua:26 and would silently do nothing).
local function palette_source_node(r, count)
    local owned = count > 0
    local atlas = G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]
    local spr = Sprite(0, 0, 0.5, 0.5, atlas, r.pos)
    return {
        n = G.UIT.C,
        config = {
            align = 'cm', padding = 0.06, r = 0.08, minw = 0.8,
            colour = owned and G.C.UI.TRANSPARENT_DARK or G.C.UI.TRANSPARENT_LIGHT,
            button = owned and 'bc_palette_pick' or nil, ref_table = { id = r.id },
            hover = owned, shadow = owned,
        },
        nodes = {
            { n = G.UIT.R, config = { align = 'cm' }, nodes = { { n = G.UIT.O, config = { object = spr } } } },
            { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                { n = G.UIT.T, config = { text = 'x' .. count, scale = 0.3,
                    colour = owned and G.C.WHITE or G.C.UI.TEXT_INACTIVE } },
            } },
        },
    }
end

-- Build the palette row from current resource counts. Returns a G.UIT.R.
-- Gathered ores always show (greyed at 0); crafted resources show only when owned.
function PB_UTIL.build_palette_node()
    local store = (G.GAME.balacraft and G.GAME.balacraft.resources) or {}
    local sources = {}
    for _, r in ipairs(PB_UTIL.RESOURCES) do
        local count = store[r.id] or 0
        if r.kind == 'gathered' or count > 0 then
            sources[#sources + 1] = palette_source_node(r, count)
        end
    end
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.06 }, nodes = sources }
end
```

  Notes: `CardArea(X,Y,W,H,config)` with `card_limit=1, type='balacraft_tile', highlight_limit=0` (`cardarea.lua:5`; `highlight_limit` is stored as `highlighted_limit`). `card_limit=1` is advisory — `emplace` does not enforce it for non-deck areas; the `place_in_cell` swap (T5b) is what enforces single-occupancy. **No `area.states.collide.can = true` needed** — we call `collides_with_point` directly, which works on empty areas. The `{n=G.UIT.O, config={object=area}}` embed is the booster-pack pattern (`UI_definitions.lua:1787`). **Sprite has no `set_alpha`** — there is none anywhere in this builder.

- [ ] **Step 2 — Static check.** Re-read T5a. Confirm balanced blocks. Confirm `PB_UTIL.destroy_craft_cells` / `PB_UTIL.spawn_tile_to_cell` are referenced but defined in T5c/T5b (resolved at runtime, file loaded after all three sub-tasks append). Confirm `CardArea`, `G.ROOM.T`, `G.CARD_W/H`, `Sprite`, `G.ASSET_ATLAS`, `PB_UTIL.icon_atlas.key`, `G.GAME.balacraft.resources` exist. Confirm **no `set_alpha`** call exists.

### T5b — Spawn, drag-grab, the drop hook that WINS, swap/return, right-click

**Files:** `BalaCraft/utilities/crafting_grid.lua` (append)

- [ ] **Step 1** — Append the tile lifecycle, spawn, place/swap, the drag-grab, and the two controller hooks:

```lua
-- ---- Tile lifecycle (always go through these so reserve accounting is exact) ----

-- Return a tile to the player: credit +1, destroy. card:remove() self-detaches from
-- its area (card.lua:5244) and nulls every G.CONTROLLER reference, so destroying a
-- mid-drag tile is safe. (No explicit remove_card needed before card:remove.)
local function return_tile(card)
    if not card then return end
    local rid = PB_UTIL.tile_resource(card)
    if rid then PB_UTIL.add_resource(rid, 1) end
    card:remove()
end

-- Spawn a fresh single tile for `rid`: debit -1, build the Card. nil (no debit) if
-- the resource is unavailable or the center is missing.
local function spawn_tile(rid)
    if PB_UTIL.get_resource_count(rid) < 1 then return nil end
    local card = PB_UTIL.make_resource_tile(rid, 0, 0)
    if not card then return nil end
    PB_UTIL.add_resource(rid, -1)   -- reserve
    return card
end

-- Place `card` into cell (i,j). If occupied, the prior occupant is RETURNED (credit)
-- and replaced (swap). Snap to cell-center (custom type => align_cards no-ops).
local function place_in_cell(card, i, j)
    local area = PB_UTIL.craft_cells and PB_UTIL.craft_cells[i] and PB_UTIL.craft_cells[i][j]
    if not area then return false end
    if area.cards[1] and area.cards[1] ~= card then
        return_tile(area.cards[1])   -- evict + credit prior occupant
    end
    if card.area then card.area:remove_card(card) end
    card.states.drag.is = false
    area:emplace(card)               -- custom type => set_ranks keeps drag.can = true
    card.T.x = area.T.x + (area.T.w - card.T.w) / 2   -- manual snap (no align for custom type)
    card.T.y = area.T.y + (area.T.h - card.T.h) / 2
    return true
end

-- Public: spawn a tile for `rid` and place it in the first empty cell (palette click).
function PB_UTIL.spawn_tile_to_cell(rid)
    if not PB_UTIL.craft_cells then return false end
    local card = spawn_tile(rid)
    if not card then return false end
    for i = 1, 3 do
        for j = 1, 3 do
            if not PB_UTIL.craft_cells[i][j].cards[1] then
                place_in_cell(card, i, j)
                return true
            end
        end
    end
    return_tile(card)   -- no empty cell: undo the reservation
    return false
end

-- Public: spawn a tile for `rid` already grabbed by the controller as the drag target,
-- so a press on a palette source flows seamlessly into the grid. (OPTIONAL ENHANCEMENT,
-- OPEN RISK R1 -- see T5b Step 2; unwired by default. The PRIMARY palette gesture is
-- the native click path spawn_tile_to_cell via bc_palette_pick.)
function PB_UTIL.spawn_tile_for_drag(rid)
    if not PB_UTIL.craft_cells then return nil end
    local card = spawn_tile(rid)
    if not card then return nil end
    local C = G.CONTROLLER
    card.T.x = G.CURSOR.T.x - card.T.w / 2
    card.T.y = G.CURSOR.T.y - card.T.h / 2
    card.states.drag.can = true
    card.states.drag.is = true
    card.states.collide.can = true
    -- Prefer a center-pinned offset over set_offset(cursor_down.T,...) (which uses the
    -- ORIGINAL press node's coords and can make the tile jump on first move).
    card.click_offset = { x = card.T.w / 2, y = card.T.h / 2 }
    if C.cursor_down then C.cursor_down.target = card; C.cursor_down.handled = true end
    C.dragging.target = card
    C.dragging.handled = false
    return card
end

-- crafting_ui sets this to its in-place refresh so grid changes update output+button.
PB_UTIL.craft_on_change = PB_UTIL.craft_on_change or nil
local function on_change()
    if PB_UTIL.craft_on_change then PB_UTIL.craft_on_change() end
end

-- ---- Custom cursor-up drop routing (wraps Controller:L_cursor_release) ----
-- RATIONALE: L_cursor_release does NOT clear self.dragging.target (controller.lua:1129-
-- 1146 only records cursor_up). The drag is torn down on the NEXT Controller:update tick
-- (controller.lua:331-337). love.mousereleased calls L_cursor_release synchronously
-- (main.lua:1130) BEFORE that update, so dragging.target is still valid here. We emplace
-- synchronously => we WIN. We then null dragging.target -- the load-bearing line: the
-- next update does prev_target = dragging.target (controller.lua:315) before released_on
-- reads prev_target (controller.lua:348), so nil propagates and native released_on cannot
-- re-touch the emplaced tile. (prev_target=nil here is redundant belt-and-suspenders.)
-- Installed once; inert unless craft_cells is live.
if not PB_UTIL._craft_release_hooked then
    PB_UTIL._craft_release_hooked = true
    local _orig_lrelease = Controller.L_cursor_release
    function Controller:L_cursor_release(x, y)
        local dropped = self.dragging.target   -- still valid at release time
        if PB_UTIL.craft_cells and dropped and dropped.is and dropped:is(Card)
           and PB_UTIL.tile_resource(dropped) then
            for i = 1, 3 do
                for j = 1, 3 do
                    local area = PB_UTIL.craft_cells[i][j]
                    if area:collides_with_point(G.CURSOR.T) then
                        if area.cards[1] ~= dropped then
                            place_in_cell(dropped, i, j)
                            play_sound('cardSlide1')
                        end
                        self.dragging.target = nil       -- load-bearing (see rationale)
                        self.dragging.prev_target = nil   -- redundant belt-and-suspenders
                        on_change()
                        return _orig_lrelease(self, x, y)
                    end
                end
            end
            -- dropped outside every cell -> return the tile (credit) and re-match
            return_tile(dropped)
            self.dragging.target = nil       -- load-bearing (see rationale)
            self.dragging.prev_target = nil   -- redundant belt-and-suspenders
            on_change()
        end
        return _orig_lrelease(self, x, y)
    end
end

-- ---- Right-click remove (no node-level right-click; wrap the controller) ----
-- queue_R_cursor_press is the only right-click entry (controller.lua:1094). If the
-- cursor is over a grid cell holding a tile, return it; else defer to vanilla.
if not PB_UTIL._craft_rclick_hooked then
    PB_UTIL._craft_rclick_hooked = true
    local _orig_rpress = Controller.queue_R_cursor_press
    function Controller:queue_R_cursor_press(x, y)
        if PB_UTIL.craft_cells then
            for i = 1, 3 do
                for j = 1, 3 do
                    local area = PB_UTIL.craft_cells[i][j]
                    if area.cards[1] and area:collides_with_point(G.CURSOR.T) then
                        return_tile(area.cards[1])
                        play_sound('cardSlide1')
                        on_change()
                        return
                    end
                end
            end
        end
        return _orig_rpress(self, x, y)
    end
end
```

  Key alignment: `area:emplace` (`cardarea.lua:49`), `area:remove_card` (`cardarea.lua:83`), `card:remove()` (`card.lua:5241-5244`, self-detaches via `if self.area then self.area:remove_card(self) end` and nulls all `G.CONTROLLER` refs). Custom `type='balacraft_tile'` keeps drag enabled (no manual re-enable). `collides_with_point(G.CURSOR.T)` (`node.lua:143`) is the board-unit overlap test. Emplacing **synchronously in `L_cursor_release`** beats the next-frame teardown; nulling `dragging.target` neutralizes native `released_on`.

- [ ] **Step 2 — OPEN RISKS (record; verify in-game in T7).**
  - **(R1) Mid-press drag hand-off** (`spawn_tile_for_drag`). Beginning a drag from a palette **press** (set `dragging.target` + `cursor_down.handled=true`) is timing-sensitive vs the next `update` reading `cursor_down.handled` (`controller.lua:319-329`). **This is an OPTIONAL enhancement and is UNWIRED by default for Phase 2.** The PRIMARY palette gesture is click-to-place (`bc_palette_pick` → `spawn_tile_to_cell`, fully native button). If pursued later, the `click_offset={w/2,h/2}` branch (already used above) is preferred over `set_offset(cursor_down.T,'Click')`. **Do not block T6 on R1.**
  - **(R2) `collides_with_point` for embedded areas.** Correct helper; the post-layout board-unit `T` of each cell is engine-determined. Probe in-game: after the UIBox builds, log `cell.T.x/y/w/h` (non-zero, matching on-screen) and confirm `area:collides_with_point(G.CURSOR.T)` returns the cell you click. If cells don't register, tune `cell_object_node` `minw/minh`.
  - **(R3) Handy coexistence (MANDATORY in-game check — Handy is installed).** `love.mousereleased` early-returns if `Handy.controller.process_mouse` returns true (`main.lua:1129`), which would skip `L_cursor_release` and our wrap. Verified Handy's in-run mouse consumption is gated on `in_run = G.STAGE==RUN and not G.OVERLAY_MENU` (HandyBalatro controller.lua:855); since the crafting modal sets `G.OVERLAY_MENU`, `in_run` is false and a plain drag-release is NOT consumed, so `L_cursor_release` still runs and our wrap fires. Likewise Handy hooks `queue_R_cursor_press`; ordering with our wrap is load-order dependent. **Confirm in-game with Handy active that both the drag-release drop AND the right-click remove fire.**

### T5c — Cleanup-on-close safety net + clear-in-place + idempotent teardown

**Files:** `BalaCraft/utilities/crafting_grid.lua` (append)

- [ ] **Step 1** — Append the credit-on-close teardown (returns every still-placed + mid-drag tile, then removes the areas). Idempotent.

```lua
-- ---- Cleanup-on-close safety net (CREDITS) ----
-- Return (credit) every tile still in a cell + any mid-drag tile, destroy all tile
-- Cards, remove the nine CardAreas, clear state. Idempotent. Called on EVERY close
-- path (the exit_overlay_menu wrap) AND defensively from build_craft_cells.
function PB_UTIL.destroy_craft_cells()
    if not PB_UTIL.craft_cells then return end
    -- Reclaim a tile the player is still mid-dragging when the modal closes.
    local C = G.CONTROLLER
    local dragged = C and C.dragging and C.dragging.target
    if dragged and dragged.is and dragged:is(Card) and PB_UTIL.tile_resource(dragged) then
        local rid = PB_UTIL.tile_resource(dragged)
        if rid then PB_UTIL.add_resource(rid, 1) end
        dragged:remove()   -- self-detaches from area; nulls controller refs
        C.dragging.target = nil
        C.dragging.prev_target = nil
    end
    for i = 1, 3 do
        for j = 1, 3 do
            local area = PB_UTIL.craft_cells[i][j]
            if area then
                local occupant = area.cards and area.cards[1]
                if occupant then
                    local rid = PB_UTIL.tile_resource(occupant)
                    if rid then PB_UTIL.add_resource(rid, 1) end  -- return (credit)
                end
                area:remove()  -- CardArea:remove destroys its cards + unregisters
            end
        end
    end
    PB_UTIL.craft_cells = nil
end

-- ---- Clear-in-place (reuse the SAME nine embedded CardArea objects) ----
-- Empty all nine cells WITHOUT removing the CardAreas (they stay embedded in the live
-- overlay -- no re-embed, no overlay rebuild). `credit=true` returns each tile (+1);
-- `credit=false` consumes them (spent by a craft). Used by bc_grid_craft / bc_autofill
-- so the grid stays usable after a craft with NO overlay rebuild.
function PB_UTIL.clear_craft_cells(credit)
    if not PB_UTIL.craft_cells then return end
    for i = 1, 3 do
        for j = 1, 3 do
            local area = PB_UTIL.craft_cells[i][j]
            local card = area and area.cards and area.cards[1]
            if card then
                if credit then
                    local rid = PB_UTIL.tile_resource(card)
                    if rid then PB_UTIL.add_resource(rid, 1) end
                end
                card:remove()   -- self-detaches from area; NO area:remove (cell reused)
            end
        end
    end
end
```

  Note: `area:remove()` (`cardarea.lua:715`) removes the area's cards/children and de-registers from `G.I.CARDAREA`. In `destroy_craft_cells` we credit each occupant BEFORE removing the area so the count is right; the card is then destroyed by `area:remove()`. `clear_craft_cells` is the **default** craft/auto-fill primitive because it keeps the same nine embedded CardArea objects (avoiding any re-embed / `set_role` risk). The mid-drag reclaim covers Esc-while-dragging.

- [ ] **Step 2 — Static check.** Re-read the full `crafting_grid.lua` end to end. Confirm: balanced blocks; `destroy_craft_cells`/`clear_craft_cells` defined; `return_tile`/`spawn_tile`/`place_in_cell` are `local` and defined before use; both controller hooks guarded by `PB_UTIL._craft_*_hooked`. Confirm globals: `Controller`, `G.CONTROLLER`, `G.CURSOR.T`, `Card`, `CardArea`, `play_sound`. Confirm **no `set_alpha`** anywhere; confirm no redundant `area:remove_card(card)` immediately before `card:remove()` (Card:remove self-detaches).

- [ ] **Step 3 — Commit.**

```bash
git add BalaCraft/utilities/crafting_grid.lua
git commit -m "feat(crafting): interactive grid (cells, palette, literal drag, drop hook, cleanup)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

**In-game (deferred to T7):** open modal → drag a palette tile into a cell → it stays; drag it back out → count restored; right-click a placed tile → removed + count restored; Esc with tiles placed → all counts restored.

---

## T6 — crafting_ui.lua integration (build ONCE, mutate in place, NO overlay rebuild) + main.lua load

**The central change:** the overlay is built **exactly once** on open. Grid changes (drop, palette pick, right-click, swap, auto-fill) **never** rebuild the overlay — they **mutate existing UIElements in place**:
- **Craft button** — a per-frame `config.func` (`bc_can_craft_btn`) re-derives the button's colour from `G.GAME.craft_state` every frame (`ui.lua:1024-1027`). The button is built with a **NON-nil `button='bc_grid_craft'` at construction** so `UIElement:set_values` (`ui.lua:391`) sets `states.collide.can/click.can=true` once; the per-frame func must ONLY change `config.colour`. The `bc_grid_craft` callback SELF-GUARDS (no match / no joker slot → no-op), so an always-clickable button is safe.
- **Output-slot label** — a `G.UIT.T` node bound to `G.GAME.craft_state.output_label` (`ref_table`/`ref_value`). The engine's per-frame `UIElement:update` already calls `:update_text()` on every `G.UIT.T` node (`ui.lua:1028`), re-reading the binding, so we do NOT call `update_text` ourselves — we just set the field.
- **Output-slot ICON** — only resource outputs have an icon; we swap its sprite via `get_UIE_by_ID('bc_craft_output_icon')` + `set_sprite_pos` (the auto path won't change a sprite's pos).
- One function (`PB_UTIL.refresh_craft_state`) recomputes the match after every grid change, pushes `craft_state`, and swaps the output icon.

This replaces `refresh_modal` entirely — **`G.FUNCS.overlay_menu` is called once, in `open_crafting_table`, and never again while open** (calling it again destroys the embedded CardAreas, `button_callbacks.lua:1347` → `ui.lua:1085-1089`).

**Files:** `BalaCraft/main.lua`, `BalaCraft/utilities/crafting_ui.lua`

- [ ] **Step 1** — Load `crafting_grid.lua` in `main.lua`, after `crafting_match.lua`, before `crafting_ui.lua` (the grid module is referenced by the UI):

```lua
if PB_UTIL.config.resources_enabled then
    SMODS.load_file("utilities/resources.lua")()
    SMODS.load_file("utilities/resource_ui.lua")()
    SMODS.load_file("utilities/crafting.lua")()
    SMODS.load_file("utilities/crafting_match.lua")()
    SMODS.load_file("utilities/crafting_grid.lua")()
    SMODS.load_file("utilities/crafting_ui.lua")()
    PB_UTIL.register_items(PB_UTIL.ENABLED_RESOURCES, "resources")
end
```

- [ ] **Step 2** — In `crafting_ui.lua`, delete the now-unused `pattern_preview` (lines 19–30); the live grid replaces it. Keep `cell_node` (lines 6–17). Replace the `pattern_preview` block with a comment:

```lua
-- (pattern_preview removed -- replaced by PB_UTIL.build_grid_node in crafting_grid.lua)
```

- [ ] **Step 3** — Add the shared mutable state table + the per-frame Craft-button func + the in-place refresh, near the top of `crafting_ui.lua` (just after `PB_UTIL.crafting_selected` on line 4). Keep `output_label` a STRING always (`''` never `nil`) so the bound T-node renders blank, not `"nil"`:

```lua
-- One state table living for the modal's lifetime. output_label is ALWAYS a string
-- ('' when no match) so the bound output T-node renders blank (tostring(nil)=='nil').
G.GAME.craft_state = G.GAME.craft_state or { output_label = '', can_craft = false }

-- Per-frame func on the Craft button: ONLY changes colour from craft_state. Runs every
-- frame via UIElement:update (ui.lua:1024-1027). It must NOT toggle config.button --
-- the button is built with a non-nil button so collide/click are already enabled; the
-- bc_grid_craft callback self-guards on an invalid grid, so always-clickable is safe.
G.FUNCS.bc_can_craft_btn = function(e)
    e.config.colour = G.GAME.craft_state.can_craft and G.C.GREEN or G.C.UI.TRANSPARENT_LIGHT
end

-- Data-only half: compute match -> craft_state, NO UIElement lookups. Safe to call
-- before the overlay exists (during build).
function PB_UTIL.refresh_craft_state_data()
    local recipe = PB_UTIL.match_grid(PB_UTIL.read_grid())
    local can = false
    if recipe then
        if recipe.output.type == 'joker' then
            can = (G.P_CENTERS[recipe.output.id] and PB_UTIL.has_joker_room()) and true or false
        else
            can = true
        end
    end
    G.GAME.craft_state.can_craft = can
    G.GAME.craft_state.output_label = recipe and (recipe.name or recipe.key) or ''   -- '' not nil
end

-- Recompute the match and reflect it IN PLACE (no overlay rebuild). Call after EVERY
-- grid change. The bound output T-node auto-updates each frame (ui.lua:1028), so we do
-- NOT call update_text on the label; we only swap the output ICON sprite (resource
-- outputs only -- jokers have no icon, the label carries their name).
function PB_UTIL.refresh_craft_state()
    PB_UTIL.refresh_craft_state_data()
    if not G.OVERLAY_MENU then return end
    local recipe = PB_UTIL.match_grid(PB_UTIL.read_grid())
    local icon = G.OVERLAY_MENU:get_UIE_by_ID('bc_craft_output_icon')
    if icon and icon.config and icon.config.object then
        local out = recipe and recipe.output
        if out and out.type == 'resource' then
            local r = PB_UTIL.RESOURCE_BY_ID[out.id]
            if r then icon.config.object:set_sprite_pos(r.pos) end
        end
    end
end
```

  Note: the output label is the **text** preview (works for jokers too — e.g. "Stone Pickaxe"), solving the blank-joker-output-slot concern. `set_sprite_pos` is the verified Sprite method (`sprite.lua:25`); there is **no `set_alpha`**.

- [ ] **Step 4** — Replace the whole `build_crafting_modal` (lines 51–87) so the RIGHT column hosts the live grid + palette + an output slot (label + icon) + the Craft button with the per-frame `func`. Built ONCE; the output label binds to `craft_state`; the Craft button has a non-nil `button` at construction:

```lua
function PB_UTIL.build_crafting_modal()
    -- Seed craft_state from the (currently empty) grid before the UI binds to it.
    PB_UTIL.refresh_craft_state_data()   -- data-only seed (no UE lookups)

    local list = {}
    for _, r in ipairs(PB_UTIL.RECIPES) do list[#list + 1] = recipe_row(r) end

    -- Output slot: an icon (resource outputs) + a live text label bound to craft_state.
    local output_node = {
        n = G.UIT.C, config = { align = 'cm', padding = 0.06, r = 0.1, colour = G.C.BLACK, minw = 1.2, minh = 0.9 },
        nodes = {
            { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                { n = G.UIT.O, config = { id = 'bc_craft_output_icon',
                    object = Sprite(0, 0, 0.34, 0.34, G.ASSET_ATLAS[PB_UTIL.icon_atlas.key],
                        PB_UTIL.RESOURCE_BY_ID['wood'].pos) } },
            } },
            { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                { n = G.UIT.T, config = {
                    id = 'bc_craft_output_label',
                    ref_table = G.GAME.craft_state, ref_value = 'output_label',  -- bound (ui.lua:657)
                    scale = 0.34, colour = G.C.WHITE } },
            } },
        },
    }

    -- Craft button: NON-nil button at construction so set_values:391 enables collide/click
    -- once; the per-frame func only changes colour. bc_grid_craft self-guards on an invalid
    -- grid, so an always-clickable button is safe.
    local craft_btn = {
        n = G.UIT.C,
        config = {
            id = 'bc_craft_button',
            align = 'cm', padding = 0.1, r = 0.1, minw = 2,
            colour = G.C.UI.TRANSPARENT_LIGHT,   -- initial; func overwrites on frame 1
            button = 'bc_grid_craft',            -- NON-nil at build (enables collide/click once)
            func = 'bc_can_craft_btn',           -- runs every frame (ui.lua:1024-1027), colour only
            hover = true, shadow = true,
        },
        nodes = { { n = G.UIT.T, config = { text = 'Craft', scale = 0.5, colour = G.C.UI.TEXT_LIGHT } } },
    }

    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0.1, r = 0.1, colour = G.C.GREY, minw = 9, minh = 5 },
        nodes = {
            { n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
                -- LEFT: recipe list
                { n = G.UIT.C, config = { align = 'tm', padding = 0.06, r = 0.1, colour = G.C.BLACK, minw = 3.4 }, nodes = {
                    { n = G.UIT.R, nodes = { { n = G.UIT.T, config = { text = 'Recipes', scale = 0.5, colour = G.C.UI.TEXT_LIGHT } } } },
                    { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = { { n = G.UIT.C, nodes = list } } },
                } },
                -- RIGHT: live grid + palette + output + craft (built ONCE; mutated in place)
                { n = G.UIT.C, config = { align = 'cm', padding = 0.1 }, nodes = {
                    PB_UTIL.build_grid_node(),
                    { n = G.UIT.R, config = { align = 'cm', minh = 0.15 }, nodes = {} },
                    PB_UTIL.build_palette_node(),
                    { n = G.UIT.R, config = { align = 'cm', minh = 0.15 }, nodes = {} },
                    { n = G.UIT.R, config = { align = 'cm', padding = 0.06 }, nodes = { output_node, craft_btn } },
                } },
            } },
        },
    }
end
```

  The palette is built once here; because palette counts only change when a tile is spawned/returned, the **count badges are a known cosmetic-staleness tradeoff** of build-once — see Step 6. The grid, output label/icon, and Craft button are fully live.

- [ ] **Step 5** — Rewrite `open_crafting_table`: seed `craft_state`, build the cells, register the change-callback to `refresh_craft_state`, and call `overlay_menu` **once**. Delete `refresh_modal` entirely. Replace lines 89–101 with:

```lua
function PB_UTIL.open_crafting_table()
    PB_UTIL.crafting_selected = nil
    G.GAME.craft_state = G.GAME.craft_state or { output_label = '', can_craft = false }
    G.GAME.craft_state.output_label = ''
    G.GAME.craft_state.can_craft = false
    PB_UTIL.build_craft_cells()                          -- nine live cell-areas (build once)
    PB_UTIL.craft_on_change = PB_UTIL.refresh_craft_state  -- grid changes mutate in place
    G.FUNCS.overlay_menu { definition = PB_UTIL.build_crafting_modal() }  -- ONCE; never again while open
end
```

  There is **no `refresh_modal`** anymore. Every grid change calls `PB_UTIL.refresh_craft_state()` (mutate in place).

- [ ] **Step 5b — Palette/recipe-row staleness note (build-once tradeoff).** Because the overlay is never rebuilt while open:
  - The **palette count badges** and **recipe-row greying** reflect counts **as of modal open**. They will not visually update mid-session. Accepted cosmetic tradeoff (the grid, output label/icon, and Craft button ARE live). Live badges are roadmap (bind each badge's `G.UIT.T` to a per-source `ref_table`/`ref_value` count field) — not required for Phase 2.
  - Recipe-row **selection highlight** is likewise not live; selection now triggers **auto-fill** (Step 6), which mutates the grid (live) — the row's static colour is acceptable.

- [ ] **Step 6** — Replace the Phase 1 `bc_select_recipe`/`bc_do_craft` callbacks (lines 107–115) with the grid callbacks. Every one mutates in place via `refresh_craft_state`; **none rebuilds the overlay**. The craft and auto-fill paths use the **reuse-in-place `clear_craft_cells`** primitive (same nine embedded CardAreas — no re-embed):

```lua
-- Palette source click: spawn a tile into the first empty cell (native button path).
G.FUNCS.bc_palette_pick = function(e)
    local id = e.config.ref_table and e.config.ref_table.id
    if id and PB_UTIL.spawn_tile_to_cell(id) then
        play_sound('cardSlide1')
        PB_UTIL.refresh_craft_state()
    end
end

-- Grid Craft: placed tiles are already reserved. SELF-GUARD on an invalid grid / no
-- joker slot (the button is always clickable, so the guard is what enforces validity).
-- CONSUME placed tiles WITHOUT crediting (reuse-in-place), produce output. Never call
-- PB_UTIL.craft here (double-spend).
G.FUNCS.bc_grid_craft = function(e)
    local recipe = PB_UTIL.match_grid(PB_UTIL.read_grid())
    if not recipe then play_sound('cancel'); return end
    if recipe.output.type == 'joker' then
        if not G.P_CENTERS[recipe.output.id] then play_sound('cancel'); return end
        if not PB_UTIL.has_joker_room() then play_sound('cancel'); return end
    end
    PB_UTIL.clear_craft_cells(false)   -- destroy placed tiles in place, NO credit (spent)
    PB_UTIL.produce_output(recipe)     -- produce-half only (resource/joker + sound)
    PB_UTIL.refresh_craft_state()      -- grid is now empty; output blanks, button greys
end

-- Auto-fill from a recipe row click: clear current placement (returning tiles), then
-- spawn the recipe's pattern tiles into the matching cells via the reserve path.
G.FUNCS.bc_autofill = function(e)
    local recipe = e.config.ref_table and e.config.ref_table.key
        and PB_UTIL.recipe_by_key(e.config.ref_table.key)
    if not recipe then return end
    PB_UTIL.clear_craft_cells(true)    -- credit + empty prior placement (cells reused)
    if not PB_UTIL.can_afford(recipe) then
        PB_UTIL.crafting_selected = recipe.key
        PB_UTIL.refresh_craft_state()
        return
    end
    for i = 1, 3 do
        for j = 1, 3 do
            local id = recipe.pattern[i][j]
            if id then
                local card = PB_UTIL.make_resource_tile(id, 0, 0)
                if card then
                    PB_UTIL.add_resource(id, -1)   -- reserve (same path as spawn)
                    local area = PB_UTIL.craft_cells[i][j]
                    card.states.drag.is = false
                    area:emplace(card)             -- custom type keeps drag.can = true
                    card.T.x = area.T.x + (area.T.w - card.T.w) / 2
                    card.T.y = area.T.y + (area.T.h - card.T.h) / 2
                end
            end
        end
    end
    PB_UTIL.crafting_selected = recipe.key
    PB_UTIL.refresh_craft_state()
end
```

  Note: auto-fill places by EXACT pattern position; the `can_afford` guard prevents partial fills (no stranded reservations). Craft/auto-fill use `clear_craft_cells` (reuse-in-place) so the SAME nine CardArea objects stay embedded in the live overlay — no re-embed, no `set_role`/`recalculate` risk.

  **OPTIONAL FALLBACK (NOT the default — do not write unless reuse-in-place fails in-game).** If `clear_craft_cells` somehow proves unusable, an alternative is to rebuild a fresh cell set (`destroy_craft_cells` + `build_craft_cells`) and re-embed the new CardAreas into the existing overlay by giving each cell node an `id='bc_cell_<i>_<j>'`, walking `G.OVERLAY_MENU:get_UIE_by_ID(...)` to swap each `config.object`, and calling `G.OVERLAY_MENU:recalculate()`. This path carries **R4** (recalculate does NOT re-run `set_role`, so a swapped CardArea's role/T may not rebind — `ui.lua:323-335` vs `ui.lua:410-411`). It is documented only as a last resort; the reuse-in-place body above is what ships.

- [ ] **Step 7** — Point recipe rows at auto-fill. In `recipe_row` (line 41), change the button + ref:

```lua
            button = 'bc_autofill', ref_table = { key = recipe.key },
```

  `recipe_row`'s `craftable = PB_UTIL.can_craft(recipe)` greying is unchanged (computed at build-once time per Step 5b). `bc_autofill` re-checks affordability before spawning, so clicking a greyed row just clears/selects without stranding reservations.

- [ ] **Step 8** — Cleanup on EVERY modal-close path. Wrap `G.FUNCS.exit_overlay_menu` once so closing returns all tiles **before** the engine teardown removes the embedded areas. `exit_overlay_menu` takes no args (`button_callbacks.lua:1378`) and may be invoked colon-style (`self=G.FUNCS`); forward whatever args are received. Append to `crafting_ui.lua`:

```lua
-- Return all placed/mid-drag tiles whenever an overlay closes while our cells live,
-- BEFORE _orig_exit runs G.OVERLAY_MENU:remove() (which would area:remove the cells
-- with no credit). Forward whatever args are received (exit_overlay_menu ignores them).
if not PB_UTIL._craft_exit_hooked then
    PB_UTIL._craft_exit_hooked = true
    local _orig_exit = G.FUNCS.exit_overlay_menu
    G.FUNCS.exit_overlay_menu = function(...)
        if PB_UTIL.craft_cells then
            PB_UTIL.destroy_craft_cells()   -- credit + destroy all tiles + areas
            PB_UTIL.craft_on_change = nil
        end
        return _orig_exit(...)
    end
end
```

  This is the safety net per spec §4.2/§5: Esc, the overlay's close button, or any `exit_overlay_menu` returns every reserved tile, **front-running** the engine's `G.OVERLAY_MENU:remove()` teardown. After `destroy_craft_cells`, `craft_cells=nil`; the engine's later recursive `UIElement:remove` on the already-removed areas is a harmless double-`:remove()` (guarded by `config.object=nil` at `ui.lua:1088`).

- [ ] **Step 9 — Static check.** Re-read all of `crafting_ui.lua`. Confirm: `pattern_preview` removed and unreferenced; **no `refresh_modal` remains** and **`overlay_menu` is called exactly once** (in `open_crafting_table`); `cell_node` still defined (keep it only if still referenced — the output uses its own icon node now; if `cell_node` is otherwise unused, leave it with a comment or remove it); every new `G.FUNCS.bc_*` references only existing `PB_UTIL.*` (`spawn_tile_to_cell`, `match_grid`, `read_grid`, `clear_craft_cells`, `produce_output`, `build_craft_cells`, `destroy_craft_cells`, `can_afford`, `make_resource_tile`, `add_resource`, `recipe_by_key`, `has_joker_room`, `build_grid_node`, `build_palette_node`, `refresh_craft_state`, `refresh_craft_state_data`); the output T-node binds `ref_table = G.GAME.craft_state, ref_value = 'output_label'`; the Craft button has `button = 'bc_grid_craft'` AND `func = 'bc_can_craft_btn'`; the `bc_can_craft_btn` func changes ONLY `config.colour`; the `exit_overlay_menu` wrap forwards `...`. Confirm **no `set_alpha`** anywhere; confirm `refresh_craft_state` does NOT call `update_text` on the label (auto-updated). Confirm balanced blocks.

- [ ] **Step 10 — Commit.**

```bash
git add BalaCraft/main.lua BalaCraft/utilities/crafting_ui.lua
git commit -m "feat(crafting): build-once modal; live grid + in-place output/Craft mutation (no rebuild)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

**In-game (the human runs):**
- Open the Crafting Table → 3×3 grid + palette row with `xN` badges + output slot + Craft, built once.
- Click a palette source → a tile drops into the first empty cell; output label + Craft button update **without any flicker/rebuild**.
- Place the Sticks shape (two Wood stacked vertically) → output label shows "Sticks", Craft turns green (per-frame func).
- Click Craft → 2 Sticks produced, placed tiles consumed, grid clears, `timpani` plays, output label blanks.
- Click a recipe row you can afford → grid auto-fills that pattern; unaffordable row → clears + selects, no fill, no lost resources.
- Confirm the modal is NEVER torn down/rebuilt on any grid change (the embedded CardAreas persist — tiles never vanish on the next interaction).

---

## T7 — Hardening + full in-game regression (reserve/return integrity, incl. overlay-teardown)

No new feature code unless a regression is found. This is the reserve/return integrity audit across every path **including the overlay-teardown path**, plus the build-once/no-rebuild assertions and persistence checks. Static reasoning first, then the human's in-game pass.

**Files:** (only if a bug is found) any of `crafting_grid.lua`, `crafting_ui.lua`.

- [ ] **Step 1 — Reserve/return ledger audit (static, by hand).** Walk every path; confirm credit fires exactly once per debit. Use the proof table in the **RESERVE/PRODUCE** section as the checklist. The table MUST include the **overlay-teardown/close path**:
  - Palette click `spawn_tile_to_cell` placed → `−1` only (tile holds reservation). ✓
  - Palette click, no empty cell → `−1` then `return_tile +1`. ✓ (net 0)
  - Drag-into-empty-cell (release hook) → already `−1` at spawn; `place_in_cell`, no extra. ✓
  - Swap (release hook / `place_in_cell` occupied) → evicted occupant `return_tile +1`; new tile keeps `−1`. ✓
  - Drag-outside (release hook else) → `return_tile +1`. ✓ (net 0)
  - Right-click placed tile → `return_tile +1`. ✓ (net 0)
  - Grid Craft → `clear_craft_cells(false)` removes tiles with **NO credit**; `produce_output` adds output. ✓ (reservation = spend)
  - **Modal close (`exit_overlay_menu` wrap → `destroy_craft_cells`)** → credits every placed tile `+1` and reclaims mid-drag tile `+1`, **before** the engine teardown. ✓
  - **Overlay engine teardown (after the wrap)** → cells already emptied + `craft_cells=nil`; engine double-`:remove()` destroys nothing owed. ✓ **(explicitly audited)**
  - Auto-fill → `clear_craft_cells(true)` credits prior placement, then `−1` per spawned pattern cell, guarded by `can_afford` (no partial-fill strand). ✓

  Confirm NO path destroys a tile without either a credit (return) or being a deliberate spend (craft). Crucially confirm there is **no overlay rebuild on any grid change** — grep `crafting_ui.lua`/`crafting_grid.lua` for `overlay_menu` and verify it appears **only** in `open_crafting_table`. If a second `overlay_menu` call exists on any change path, that is the critical bug — fix before the in-game pass.

- [ ] **Step 2 — Console integrity check (human).** With the modal CLOSED, snapshot counts, then open/place/close and confirm conservation:

```lua
local function snap() local t={} for _,r in ipairs(PB_UTIL.RESOURCES) do t[r.id]=PB_UTIL.get_resource_count(r.id) end return t end
PB_UTIL.set_resource('wood', 5); PB_UTIL.set_resource('cobblestone', 5); PB_UTIL.set_resource('sticks', 5)
_G._before = snap(); print('wood', _G._before.wood)   -- 5
-- Now: open the Crafting Table, place several tiles, do a few palette picks / right-clicks,
-- then press Esc (do NOT craft). After closing, run:
local after = snap()
for id, n in pairs(_G._before) do if after[id] ~= n then print('LEAK', id, n, '->', after[id]) end end
-- Expect: NO "LEAK" lines -- every reserved tile returned on close.
```

- [ ] **Step 2b — No-rebuild assertion (human, console while modal OPEN).** Confirm the overlay is build-once and the embedded areas persist across grid changes:

```lua
-- With the crafting modal OPEN and at least one tile placed:
local uib = G.OVERLAY_MENU
print('overlay#1', tostring(uib))          -- note the table address
-- Now place another tile / right-click one / click a palette source, then:
print('overlay#2', tostring(G.OVERLAY_MENU))  -- MUST be the SAME address as overlay#1
print('cell11', tostring(PB_UTIL.craft_cells[1][1]))  -- stays valid across changes
```

  If `overlay#2` differs from `overlay#1`, the overlay was rebuilt (bug) — the embedded CardAreas would have been destroyed and resources lost. Must match.

- [ ] **Step 3 — In-game regression matrix (human runs; agent does NOT mark passing).** Launch Balatro with a run in progress and exercise:
  - **Place/remove conservation:** open modal, place every resource type (including Sticks), right-click each back out → counts return to start; no orphaned tile sprites.
  - **Sticks tile sanity (FIX A):** click the Sticks palette source (with sticks owned) → a Sticks card tile is placed (NOT a silent no-op); it shows the Sticks card art (FIX B).
  - **Drag-out return:** drag a placed tile off the grid → count restored.
  - **Swap:** drag a tile onto an occupied cell → old tile returns (+1), new stays.
  - **Grid craft (resource):** Sticks (two Wood vertical) → Craft → +2 sticks, −2 wood net, grid clears, output label blanks, Craft button greys (per-frame func).
  - **Grid craft (joker):** Stone Pickaxe (3 cobblestone row + 2 sticks column) with a free joker slot → Craft → `j_balacraft_stone_pickaxe` appears; output label showed "Stone Pickaxe" on the valid shape; with NO free slot → clicking Craft is a no-op (self-guard), button stays grey.
  - **Always-clickable Craft safety (FIX C):** click Craft on an EMPTY/invalid grid → no-op (optional fail sound), nothing produced, no error.
  - **Output label live-update:** build a valid shape → label shows the recipe name; remove a tile → label blanks; all WITHOUT the modal flickering/rebuilding.
  - **Right-click outside the modal:** with the crafting modal CLOSED, right-click during a hand still unhighlights hand cards (the `queue_R_cursor_press` wrap defers to vanilla when `craft_cells` is nil).
  - **Auto-fill:** affordable row → grid fills the exact pattern (including the 3 sticks-bearing recipes); unaffordable row → no fill, no count change.
  - **Esc / close mid-state:** place tiles, mid-drag a tile, press Esc → all reserved resources returned, no leaked sprites, no console error; `craft_cells` is nil afterward.
  - **Overlay-teardown path (the close path):** place tiles, then close via the overlay's own close button (not Esc) → counts restored (the `exit_overlay_menu` wrap fires before the engine teardown).
  - **Save-quit-continue:** craft a joker, place some tiles, Esc, save+quit, Continue → resource counts + crafted jokers persist (counts live on `G.GAME`, auto-saved). No tile centers leak into the collection/shop.
  - **New run reset:** fresh run → counts reset to 0, palette shows ores greyed at x0, no stale `craft_cells`.
  - **MANDATORY Handy-present checks (Handy is installed):** with Handy active, confirm **drag-release into a cell fires** (the `L_cursor_release` wrap runs because the open overlay disables Handy's in-run mouse consumption) AND **right-click remove fires** (the `queue_R_cursor_press` wrap). These are R3 and are NOT optional.
  - **OPEN RISK R2 verification:** `collides_with_point` hits the right cell; if not, tune `cell_object_node` `minw/minh` / log `cell.T` vs `G.CURSOR.T`.

- [ ] **Step 4 — If any regression is found:** apply the minimal fix to the offending module, re-run Step 1's ledger audit (and Step 2b's no-rebuild assertion) for the affected path, re-commit. Otherwise no code change.

- [ ] **Step 5 — Commit (only if Step 4 changed code).**

```bash
git add BalaCraft/utilities/crafting_grid.lua BalaCraft/utilities/crafting_ui.lua
git commit -m "fix(crafting): harden reserve/return integrity (incl. overlay-teardown path)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## OPEN RISKS (carried forward; not blocking the plan)

1. **(R1) Mid-press drag-from-palette hand-off** (`spawn_tile_for_drag`) — beginning a drag from a palette **press** is timing-sensitive vs the next `update` reading `cursor_down.handled` (`controller.lua:319-329`). **OPTIONAL enhancement, UNWIRED by default.** The shipped primary palette gesture is click-to-place (`bc_palette_pick` → `spawn_tile_to_cell`); the in-grid drag (placed tile cell-to-cell or off-grid) is fully working via the `L_cursor_release` hook. If wiring R1 later, prefer `click_offset={w/2,h/2}` over `set_offset`.
2. **(R2) Embedded-area cursor collision** — `area:collides_with_point(G.CURSOR.T)` is the correct helper (works on empty areas; container defaults to `G.ROOM`), but each cell's post-layout board-unit `T` is engine-determined; tune `cell_object_node` `minw/minh` in-game; log `cell.T` vs `G.CURSOR.T`.
3. **(R3) Controller wraps with Handy present (MANDATORY in-game)** — `L_cursor_release` / `queue_R_cursor_press` wraps used as `(self, x, y)`, deferring with `_orig(self, x, y)`. The drop hook WINS by emplacing synchronously before the next `Controller:update` teardown (`controller.lua:331-337`); nulling `dragging.target` neutralizes native `released_on` (via `controller.lua:315`→`348`). Handy is installed: confirm both wraps fire in-game (the open overlay disables Handy's in-run mouse consumption, so they should). Idempotent-guarded.
4. **(R4) Cell-set re-embed after Craft/auto-fill (avoided by default)** — the shipped craft/auto-fill path uses **reuse-in-place** (`clear_craft_cells`, same nine embedded CardAreas), so R4 is OFF the critical path. The re-embed fallback (`build_craft_cells` + swap `config.object` + `recalculate`) is documented only as a last resort because `recalculate` does not re-run `set_role` (`ui.lua:323-335` vs `410-411`).

No engine API beyond what the research established is invented anywhere in this plan; where end-to-end behavior is in-game-only verifiable, it is recorded above as an OPEN RISK rather than asserted.
