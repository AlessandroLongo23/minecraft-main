# Crafting System — Phase 1 (click-to-craft loop) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A playable mid-blind Crafting Table: open a modal, click a recipe, and craft it — turning resources into a crafted intermediate (Sticks) or a tool-Joker — with affordability + joker-slot gating.

**Architecture:** Pure data-driven recipe registry (`PB_UTIL.RECIPES`) consumed by a content-agnostic craft action (`PB_UTIL.craft`) that spends resource counts via the existing `PB_UTIL.add_resource` funnel and produces either a resource (`add_resource(+)`) or a joker (`joker_add`). A `G.FUNCS.overlay_menu` modal lists recipes and crafts the selected one. Builds on the implemented Resource system.

**Tech Stack:** Lua (LuaJIT, Balatro/LÖVE2D) · Steamodded (SMODS) · Python 3 + Pillow (icon art).

**Scope:** This is **Phase 1 only** — recipe-list click-to-craft. **Phase 2** (manual drag into the 3×3 + shaped pattern-matching of hand-built grids) is a separate plan written after Phase 1 is verified in-game. In Phase 1 the right side of the modal *displays* the selected recipe's pattern read-only; there is no dragging and no matcher.

---

## Verification model (same as the resource feature)

No automated test harness (the mod runs inside Balatro; `luajit`/`lua` not installed). Each task is verified by: (1) re-reading the file for balanced Lua/JSON; (2) running the Python art step where applicable (PIL is installed); (3) **in-game** observation + the Steamodded debug console (e.g. `PB_UTIL.craft(PB_UTIL.recipe_by_key('sticks'))`). Steps marked "In-game:" are the human's to run. Work continues on branch `feature/resource-type`.

## Naming conventions (locked)

| Thing | Value |
|---|---|
| Crafted resource id | `sticks` (`kind='crafted'`) |
| Recipe registry | `PB_UTIL.RECIPES` (list); empty grid cells are **`false`**, never `nil` (avoids Lua array holes) |
| Tool-Joker keys | `stone_pickaxe`, `iron_sword`, `iron_shovel` → centers `j_minecraft_<key>` |
| Craft funnel | `PB_UTIL.craft(recipe)`; selection in `PB_UTIL.crafting_selected` (recipe key string) |
| Modal opener | `PB_UTIL.open_crafting_table()` |
| Button callbacks | `G.FUNCS.mc_open_crafting`, `G.FUNCS.mc_select_recipe`, `G.FUNCS.mc_do_craft` |

## File structure

**New files**
| File | Responsibility |
|---|---|
| `content/resources/recipes.lua` | `PB_UTIL.RECIPES` (patterns + outputs) + `PB_UTIL.recipe_ingredients` / `recipe_by_key` |
| `content/jokers/stone_pickaxe.lua`, `iron_sword.lua`, `iron_shovel.lua` | the 3 tool-Jokers |
| `utilities/crafting.lua` | `can_afford` / `has_joker_room` / `can_craft` / `craft` / `has_joker` |
| `utilities/crafting_ui.lua` | the Crafting Table modal + the "Crafting Table" button under the hotbar |

**Edited files**
| File | Change |
|---|---|
| `content/resources/registry.lua` | add `kind` to the 6 ores; add the `sticks` crafted resource |
| `assets/gen_resources.py` | draw a Sticks icon; grow icon sheet to 3×3 (ore positions unchanged) |
| `utilities/resources.lua` | drop pool filters to `kind=='gathered'`; `add_resource` marks panel dirty on either 0-boundary crossing; pickaxe/shovel tool bonuses in `grant_blind_drop` |
| `utilities/resource_ui.lua` | hotbar shows crafted resources only when count > 0 |
| `utilities/definitions.lua` | add `recipes` to `ENABLED_RESOURCES`; add the 3 tool-jokers to `ENABLED_JOKERS` |
| `main.lua` | load `utilities/crafting.lua` + `utilities/crafting_ui.lua` under `resources_enabled` |

---

## Task 1: Sticks resource (kind field, art, drop guard, hotbar)

**Files:** Modify `content/resources/registry.lua`, `assets/gen_resources.py`, `utilities/resources.lua`, `utilities/resource_ui.lua`

- [ ] **Step 1: Add `kind` to ores + the Sticks resource**

Replace the `PB_UTIL.RESOURCES` table in `content/resources/registry.lua` with:

```lua
PB_UTIL.RESOURCES = {
    { id = 'wood',        kind = 'gathered', tier = 1, pos = { x = 0, y = 0 } },
    { id = 'cobblestone', kind = 'gathered', tier = 1, pos = { x = 1, y = 0 } },
    { id = 'coal',        kind = 'gathered', tier = 1, pos = { x = 2, y = 0 } },
    { id = 'iron',        kind = 'gathered', tier = 2, pos = { x = 0, y = 1 } },
    { id = 'gold',        kind = 'gathered', tier = 2, pos = { x = 1, y = 1 } },
    { id = 'diamond',     kind = 'gathered', tier = 3, pos = { x = 2, y = 1 } },
    { id = 'sticks',      kind = 'crafted',            pos = { x = 0, y = 2 } },
}
```

(`RESOURCE_BY_ID` and the two `SMODS.Atlas` registrations below it stay as-is.)

- [ ] **Step 2: Draw the Sticks icon (grow icon sheet to 3×3)**

In `assets/gen_resources.py`, change the icon grid to 3 rows and add a sticks texture. Replace the `ORES` list and the `build_icons` row count:

Add a `sticks()` texture function after `cobblestone()`:
```python
def sticks():
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    px = img.load()
    for (x, y) in [(6, 2), (7, 3), (6, 4), (7, 5), (6, 6), (7, 7), (6, 8), (7, 9), (6, 10), (7, 11)]:
        px[x, y] = WOOD
        px[x + 1, y] = WOOD_LINE
    for (x, y) in [(9, 4), (10, 5), (9, 6), (10, 7), (9, 8), (10, 9), (9, 10), (10, 11), (9, 12), (10, 13)]:
        px[x, y] = WOOD
        px[x + 1, y] = WOOD_LINE
    return img
```

The `ORES` list is used for BOTH sheets, but Sticks is icon-only. Keep `ORES` as the 6 gathered ores (for the card sheet) and add a separate `ICONS` list:
```python
ICONS = ORES + [("sticks", sticks())]
```

In `build_icons`, change `ICON * ROWS` to `ICON * 3` (3 rows) and iterate `ICONS` instead of `ORES`:
```python
def build_icons():
    sheet = Image.new("RGBA", (ICON * COLS, ICON * 3), (0, 0, 0, 0))
    for i, (_id, tex) in enumerate(ICONS):
        cx, cy = (i % COLS) * ICON, (i // COLS) * ICON
        slot = Image.new("RGBA", (ICON, ICON), (20, 22, 26, 255))
        for x in range(ICON):
            slot.putpixel((x, 0), (70, 74, 82, 255)); slot.putpixel((x, ICON - 1), (70, 74, 82, 255))
        for y in range(ICON):
            slot.putpixel((0, y), (70, 74, 82, 255)); slot.putpixel((ICON - 1, y), (70, 74, 82, 255))
        block = nn(tex, 2)
        slot.alpha_composite(block, (1, 1))
        sheet.alpha_composite(slot, (cx, cy))
    sheet.save("minecraft-main/assets/1x/resource_icons.png")
    print("wrote resource_icons.png", sheet.size)
```

`build_cards` stays as-is (6 ores only). The 6 ore icon positions are unchanged (rows 0–1); Sticks lands at `(0,2)`.

- [ ] **Step 3: Regenerate the icon sheets**

```bash
cd "/Users/alessandro/Library/Application Support/Balatro/Mods" && python3 minecraft-main/assets/gen_resources.py && python3 - <<'PY'
import sys; sys.path.insert(0, "minecraft-main/assets")
from utils import scale_image
scale_image("minecraft-main/assets/1x/resource_icons.png", "minecraft-main/assets/2x/resource_icons.png", 2)
PY
```
Expected: `wrote resource_icons.png (102, 102)` and a scaled line. Verify icons are 102×102 (1x) / 204×204 (2x): `python3 -c "from PIL import Image; print(Image.open('minecraft-main/assets/1x/resource_icons.png').size, Image.open('minecraft-main/assets/2x/resource_icons.png').size)"`. (The card sheet is untouched — still 213×190.)

- [ ] **Step 4: Guard drops to gathered resources + fix the dirty-flag boundary**

In `utilities/resources.lua`, in `random_ore_of_tier`, change the pool filter to also require gathered kind:

```lua
    for _, r in ipairs(PB_UTIL.RESOURCES) do
        if r.kind == 'gathered' and r.tier == tier then pool[#pool + 1] = r.id end
    end
```

And in `add_resource`, change the dirty-flag condition so the panel rebuilds when a resource crosses the 0 boundary in EITHER direction (so a crafted resource's cell appears at 0→>0 and disappears at >0→0). Replace:
```lua
    if prev == 0 and new > 0 then
        G.GAME.minecraft._panel_dirty = true
    end
```
with:
```lua
    if (prev == 0) ~= (new == 0) then
        G.GAME.minecraft._panel_dirty = true
    end
```

- [ ] **Step 5: Hotbar shows crafted resources only when owned**

In `utilities/resource_ui.lua`, in `build_resources_panel`, skip crafted resources with zero count. Change the loop head:
```lua
    for _, r in ipairs(PB_UTIL.RESOURCES) do
        local count = store[r.id] or 0
        if r.kind == 'gathered' or count > 0 then
            local owned = count > 0
            local spr = Sprite(0, 0, 0.5, 0.5, atlas, r.pos)
            if not owned and spr.set_alpha then spr:set_alpha(0.35) end
            cells[#cells + 1] = {
                n = G.UIT.C, config = { align = 'cm', padding = 0.04 },
                nodes = {
                    { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                        { n = G.UIT.O, config = { object = spr } },
                    } },
                    { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                        { n = G.UIT.T, config = {
                            ref_table = store, ref_value = r.id, scale = 0.32,
                            colour = owned and G.C.WHITE or G.C.UI.TEXT_INACTIVE,
                        } },
                    } },
                },
            }
        end
    end
```
(This wraps the existing cell-building body in the `if r.kind == 'gathered' or count > 0 then` guard. Everything else in the function is unchanged.)

- [ ] **Step 6: In-game — verify Sticks resource**

In-game: start a run. Console: `PB_UTIL.add_resource('sticks', 3)` → a Sticks slot appears in the hotbar with its icon and "3". `PB_UTIL.set_resource('sticks', 0)` → the Sticks slot disappears (gathered ores remain). Beat blinds repeatedly → Sticks never drops (only the 6 ores do).

- [ ] **Step 7: Commit**

```bash
git add content/resources/registry.lua assets/gen_resources.py assets/1x/resource_icons.png assets/2x/resource_icons.png utilities/resources.lua utilities/resource_ui.lua
git commit -m "feat(crafting): Sticks crafted resource + kind field + drop guard"
```

---

## Task 2: Recipe registry

**Files:** Create `content/resources/recipes.lua`; Modify `utilities/definitions.lua`

- [ ] **Step 1: Write the recipe registry**

Create `content/resources/recipes.lua`:
```lua
-- Crafting recipes (data-driven). Empty grid cells are `false` (NOT nil — nil makes
-- Lua array holes). Each recipe: 3x3 pattern of resource ids + an output.

PB_UTIL.RECIPES = {
    {
        key = 'sticks',
        name = 'Sticks',
        output = { type = 'resource', id = 'sticks', amount = 2 },
        pattern = {
            { false, 'wood',  false },
            { false, 'wood',  false },
            { false, false,   false },
        },
    },
    {
        key = 'stone_pickaxe',
        name = 'Stone Pickaxe',
        output = { type = 'joker', id = 'j_minecraft_stone_pickaxe', amount = 1 },
        pattern = {
            { 'cobblestone', 'cobblestone', 'cobblestone' },
            { false,         'sticks',      false },
            { false,         'sticks',      false },
        },
    },
    {
        key = 'iron_sword',
        name = 'Iron Sword',
        output = { type = 'joker', id = 'j_minecraft_iron_sword', amount = 1 },
        pattern = {
            { false, 'iron',   false },
            { false, 'iron',   false },
            { false, 'sticks', false },
        },
    },
    {
        key = 'iron_shovel',
        name = 'Iron Shovel',
        output = { type = 'joker', id = 'j_minecraft_iron_shovel', amount = 1 },
        pattern = {
            { false, 'iron',   false },
            { false, 'sticks', false },
            { false, 'sticks', false },
        },
    },
}

-- Multiset of ingredients derived from the pattern (single source of truth).
function PB_UTIL.recipe_ingredients(recipe)
    local need = {}
    for i = 1, 3 do
        for j = 1, 3 do
            local cell = recipe.pattern[i][j]
            if cell then need[cell] = (need[cell] or 0) + 1 end
        end
    end
    return need
end

function PB_UTIL.recipe_by_key(key)
    for _, r in ipairs(PB_UTIL.RECIPES) do
        if r.key == key then return r end
    end
    return nil
end
```

- [ ] **Step 2: Enable it in the loader**

In `utilities/definitions.lua`, add `'recipes'` to `PB_UTIL.ENABLED_RESOURCES`:
```lua
PB_UTIL.ENABLED_RESOURCES = {
    'registry',
    'resource_consumabletype',
    'recipes',
}
```

- [ ] **Step 3: In-game — verify the registry loads**

In-game: start a run. Console: `#PB_UTIL.RECIPES` → `4`. `local n = PB_UTIL.recipe_ingredients(PB_UTIL.recipe_by_key('stone_pickaxe')); sendDebugMessage(n.cobblestone..'/'..n.sticks, 'Minecraft')` → `3/2`.

- [ ] **Step 4: Commit**

```bash
git add content/resources/recipes.lua utilities/definitions.lua
git commit -m "feat(crafting): data-driven recipe registry (sticks + 3 tools)"
```

---

## Task 3: Craft logic

**Files:** Create `utilities/crafting.lua`; Modify `main.lua`

- [ ] **Step 1: Write the craft action**

Create `utilities/crafting.lua`:
```lua
-- Crafting logic: affordability, joker-room, and the craft action.
-- Spends/produces through the existing PB_UTIL.add_resource funnel.

function PB_UTIL.has_joker(key)
    if not G.jokers or not G.jokers.cards then return false end
    for _, c in ipairs(G.jokers.cards) do
        if c.config and c.config.center and c.config.center.key == key then return true end
    end
    return false
end

function PB_UTIL.can_afford(recipe)
    for id, n in pairs(PB_UTIL.recipe_ingredients(recipe)) do
        if PB_UTIL.get_resource_count(id) < n then return false end
    end
    return true
end

function PB_UTIL.has_joker_room()
    return G.jokers and (#G.jokers.cards < G.jokers.config.card_limit)
end

function PB_UTIL.can_craft(recipe)
    if not recipe then return false end
    if not PB_UTIL.can_afford(recipe) then return false end
    if recipe.output.type == 'joker' and not PB_UTIL.has_joker_room() then return false end
    return true
end

-- Returns true on success. Spends ingredients, then produces the output.
function PB_UTIL.craft(recipe)
    if not PB_UTIL.can_craft(recipe) then return false end
    for id, n in pairs(PB_UTIL.recipe_ingredients(recipe)) do
        PB_UTIL.add_resource(id, -n)
    end
    local out = recipe.output
    if out.type == 'resource' then
        PB_UTIL.add_resource(out.id, out.amount or 1)
    elseif out.type == 'joker' then
        joker_add(out.id)
    end
    play_sound('timpani', 0.8)
    return true
end
```

- [ ] **Step 2: Load it in `main.lua`**

In `main.lua`, inside the `if PB_UTIL.config.resources_enabled then` block (added by the resource feature), add a load for crafting after the two existing utility loads:
```lua
    SMODS.load_file("utilities/crafting.lua")()
```
(Place it after `SMODS.load_file("utilities/resource_ui.lua")()` and before `PB_UTIL.register_items(...)`. The `crafting_ui.lua` load is added in Task 5.)

- [ ] **Step 3: In-game — verify crafting logic**

In-game: start a run. Console:
```lua
PB_UTIL.set_resource('wood', 4)
PB_UTIL.craft(PB_UTIL.recipe_by_key('sticks'))   -- returns true
```
Expect: wood drops by 2, sticks becomes 2 (hotbar shows Sticks ×2). Then `PB_UTIL.craft(PB_UTIL.recipe_by_key('stone_pickaxe'))` with `set_resource('cobblestone',3)` first → returns true only if you also have 2 sticks and a free joker slot; a Stone Pickaxe joker appears. With a full joker row, `can_craft` returns false.

- [ ] **Step 4: Commit**

```bash
git add utilities/crafting.lua main.lua
git commit -m "feat(crafting): craft action (afford/slot checks, spend + produce)"
```

---

## Task 4: Tool-Jokers + their effects

**Files:** Create `content/jokers/stone_pickaxe.lua`, `content/jokers/iron_sword.lua`, `content/jokers/iron_shovel.lua`; Modify `utilities/definitions.lua`, `utilities/resources.lua`

Tool art is a **placeholder** — the three jokers reuse cells of the existing `mc_resource_cards` atlas (dedicated tool art is a later follow-up).

- [ ] **Step 1: Stone Pickaxe joker** (effect lives in `grant_blind_drop`, so no `calculate`)

Create `content/jokers/stone_pickaxe.lua`:
```lua
SMODS.Joker {
    key = 'stone_pickaxe',
    loc_txt = {
        name = 'Stone Pickaxe',
        text = { 'Gather {C:attention}+1{} of each resource', 'from every blind-defeat drop.' },
    },
    unlocked = true, discovered = true,
    blueprint_compat = false, eternal_compat = true,
    rarity = 2,
    atlas = 'mc_resource_cards', pos = { x = 1, y = 0 }, -- placeholder (cobblestone cell)
    cost = 5,
}
```

- [ ] **Step 2: Iron Sword joker** (scoring effect via `calculate`)

Create `content/jokers/iron_sword.lua`:
```lua
SMODS.Joker {
    key = 'iron_sword',
    loc_txt = {
        name = 'Iron Sword',
        text = { '{C:red}X2{} Mult while fighting', 'a {C:attention}Boss Blind{}.' },
    },
    unlocked = true, discovered = true,
    blueprint_compat = true, eternal_compat = true,
    rarity = 2,
    atlas = 'mc_resource_cards', pos = { x = 0, y = 1 }, -- placeholder (iron cell)
    cost = 6,
    calculate = function(self, card, context)
        if context.joker_main and G.GAME.blind and G.GAME.blind.boss then
            return { x_mult = 2 }
        end
    end,
}
```

- [ ] **Step 3: Iron Shovel joker** (effect lives in `grant_blind_drop`, so no `calculate`)

Create `content/jokers/iron_shovel.lua`:
```lua
SMODS.Joker {
    key = 'iron_shovel',
    loc_txt = {
        name = 'Iron Shovel',
        text = { 'Earn {C:money}$3{} each time', 'you defeat a blind.' },
    },
    unlocked = true, discovered = true,
    blueprint_compat = false, eternal_compat = true,
    rarity = 1,
    atlas = 'mc_resource_cards', pos = { x = 0, y = 1 }, -- placeholder (iron cell)
    cost = 4,
}
```

- [ ] **Step 4: Enable the jokers**

In `utilities/definitions.lua`, add the three keys to `PB_UTIL.ENABLED_JOKERS` (append to the existing list):
```lua
    'stone_pickaxe',
    'iron_sword',
    'iron_shovel',
```

- [ ] **Step 5: Wire Pickaxe + Shovel bonuses into `grant_blind_drop`**

In `utilities/resources.lua`, modify `PB_UTIL.grant_blind_drop` so the pickaxe adds +1 to whatever drops and the shovel pays $3. Replace the whole function body with:
```lua
function PB_UTIL.grant_blind_drop(blind)
    if not blind then return end
    local bonus = PB_UTIL.has_joker('j_minecraft_stone_pickaxe') and 1 or 0
    if PB_UTIL.has_joker('j_minecraft_iron_shovel') then ease_dollars(3) end

    local spec = blind.name and PB_UTIL.BLIND_DROPS[blind.name]
    if spec then
        PB_UTIL.add_resource(spec.id, spec.amount + bonus)
        return
    end
    local ante = (G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or 1
    local is_boss = blind.boss and true or false
    local max_tier = (ante >= 6 and 3) or (ante >= 3 and 2) or 1
    local tier = is_boss and max_tier or 1
    local amount = (is_boss and 2 or 1) + bonus
    PB_UTIL.add_resource(random_ore_of_tier(tier, 'mc_drop_' .. ante .. '_' .. tostring(blind.name)), amount)
end
```
(`PB_UTIL.has_joker` is defined in `utilities/crafting.lua`, which loads before content registration, so it exists when a blind is defeated. `ease_dollars` is a base function.)

- [ ] **Step 6: In-game — verify tool effects**

In-game:
- Console `joker_add('j_minecraft_iron_shovel')`, then beat a blind → you gain **$3**.
- `joker_add('j_minecraft_stone_pickaxe')`, beat a blind → the resource drop is **+1** larger than normal.
- `joker_add('j_minecraft_iron_sword')`, play a hand during a **Boss Blind** → mult is **×2** (and not on non-boss blinds).

- [ ] **Step 7: Commit**

```bash
git add content/jokers/stone_pickaxe.lua content/jokers/iron_sword.lua content/jokers/iron_shovel.lua utilities/definitions.lua utilities/resources.lua
git commit -m "feat(crafting): 3 tool-jokers + pickaxe/shovel/sword effects"
```

---

## Task 5: Crafting Table modal + button (HIGHEST-RISK — iterate in-game)

**Files:** Create `utilities/crafting_ui.lua`; Modify `main.lua`, `utilities/resource_ui.lua`

This is the one task that must be visually tuned in the running game (like the hotbar panel was). A simpler fallback is noted at the end.

- [ ] **Step 1: Write the modal + button logic**

Create `utilities/crafting_ui.lua`:
```lua
-- Crafting Table: a "Crafting Table" button under the hotbar opens a centered
-- overlay listing recipes (left) with a read-only pattern preview + Craft (right).

PB_UTIL.crafting_selected = PB_UTIL.crafting_selected or nil

-- A 0.4-scale icon sprite for a resource id (or an empty slot for `false`).
local function cell_node(cell)
    if not cell then
        return { n = G.UIT.C, config = { minw = 0.34, minh = 0.34, r = 0.05, padding = 0.02, colour = G.C.UI.TRANSPARENT_DARK } }
    end
    local r = PB_UTIL.RESOURCE_BY_ID[cell]
    local spr = Sprite(0, 0, 0.34, 0.34, G.ASSET_ATLAS[PB_UTIL.icon_atlas.key], r.pos)
    return { n = G.UIT.C, config = { align = 'cm' }, nodes = { { n = G.UIT.O, config = { object = spr } } } }
end

-- Read-only 3x3 preview of a recipe's pattern.
local function pattern_preview(recipe)
    local rows = {}
    for i = 1, 3 do
        local row = { n = G.UIT.R, config = { align = 'cm', padding = 0.03 }, nodes = {} }
        for j = 1, 3 do
            row.nodes[#row.nodes + 1] = cell_node(recipe and recipe.pattern[i][j] or false)
        end
        rows[#rows + 1] = row
    end
    return { n = G.UIT.C, config = { align = 'cm', padding = 0.06, r = 0.1, colour = G.C.BLACK }, nodes = rows }
end

-- One clickable recipe row in the left list.
local function recipe_row(recipe)
    local craftable = PB_UTIL.can_craft(recipe)
    local selected = (PB_UTIL.crafting_selected == recipe.key)
    return {
        n = G.UIT.R,
        config = {
            align = 'cl', padding = 0.06, r = 0.08, minw = 3,
            colour = selected and G.C.GREEN or (craftable and G.C.UI.TRANSPARENT_DARK or G.C.UI.TRANSPARENT_LIGHT),
            button = 'mc_select_recipe', ref_table = { key = recipe.key },
            hover = true, shadow = true,
        },
        nodes = {
            { n = G.UIT.T, config = { text = recipe.name or recipe.key, scale = 0.36,
                colour = craftable and G.C.WHITE or G.C.UI.TEXT_INACTIVE } },
        },
    }
end

function PB_UTIL.build_crafting_modal()
    local selected = PB_UTIL.crafting_selected and PB_UTIL.recipe_by_key(PB_UTIL.crafting_selected) or nil

    local list = {}
    for _, r in ipairs(PB_UTIL.RECIPES) do list[#list + 1] = recipe_row(r) end

    local can = PB_UTIL.can_craft(selected)
    local craft_btn = {
        n = G.UIT.C,
        config = {
            align = 'cm', padding = 0.1, r = 0.1, minw = 2,
            colour = can and G.C.GREEN or G.C.UI.TRANSPARENT_LIGHT,
            button = can and 'mc_do_craft' or nil, hover = can, shadow = can,
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
                -- RIGHT: preview + craft
                { n = G.UIT.C, config = { align = 'cm', padding = 0.1 }, nodes = {
                    pattern_preview(selected),
                    { n = G.UIT.R, config = { align = 'cm', minh = 0.2 }, nodes = {} },
                    craft_btn,
                } },
            } },
        },
    }
end

function PB_UTIL.open_crafting_table()
    G.FUNCS.overlay_menu { definition = PB_UTIL.build_crafting_modal() }
end

-- Re-render the open modal after a selection/craft.
local function refresh_modal()
    if G.OVERLAY_MENU then
        G.FUNCS.overlay_menu { definition = PB_UTIL.build_crafting_modal() }
    end
end

G.FUNCS.mc_open_crafting = function(e)
    PB_UTIL.open_crafting_table()
end

G.FUNCS.mc_select_recipe = function(e)
    PB_UTIL.crafting_selected = e.config.ref_table.key
    refresh_modal()
end

G.FUNCS.mc_do_craft = function(e)
    local recipe = PB_UTIL.crafting_selected and PB_UTIL.recipe_by_key(PB_UTIL.crafting_selected)
    if recipe and PB_UTIL.craft(recipe) then refresh_modal() end
end
```

- [ ] **Step 2: Load it in `main.lua`**

In `main.lua`, inside the `resources_enabled` block, add after the `crafting.lua` load from Task 3:
```lua
    SMODS.load_file("utilities/crafting_ui.lua")()
```

- [ ] **Step 3: Add the "Crafting Table" button under the hotbar**

In `utilities/resource_ui.lua`, in `build_resources_panel`, append a button row after the `rows` are built. Change the final `return` to add a button row beneath the resource rows:
```lua
    rows[#rows + 1] = {
        n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
            { n = G.UIT.C, config = {
                align = 'cm', padding = 0.06, r = 0.08, minw = 1.6,
                colour = G.C.GREEN, button = 'mc_open_crafting', hover = true, shadow = true,
            }, nodes = {
                { n = G.UIT.T, config = { text = 'Crafting Table', scale = 0.28, colour = G.C.UI.TEXT_LIGHT } },
            } },
        },
    }
    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0.06, r = 0.1, colour = G.C.BLACK, emboss = 0.05 },
        nodes = rows,
    }
```
(This inserts one more row into the existing `rows` list right before the existing `return`.)

- [ ] **Step 4: In-game — verify the modal end-to-end**

In-game: start a run, gather some resources (or console `PB_UTIL.set_resource('wood',6); PB_UTIL.set_resource('cobblestone',3); PB_UTIL.set_resource('iron',3)`). Expected: a **Crafting Table** button shows under the hotbar; clicking opens the centered modal; the recipe list is on the left, a pattern preview + Craft on the right. Click **Sticks** → preview shows two wood → **Craft** → wood drops by 2, sticks appears, the list updates (Stone Pickaxe/Iron Sword/Shovel become craftable as you get sticks). Crafting a tool with a free joker slot adds the joker; with a full row, its row + Craft are greyed/disabled.

- [ ] **Step 5: In-game — tune + cross-mod check**

Adjust `minw`/`padding`/`scale`/`align` in `build_crafting_modal` until it reads cleanly. Confirm the button under the hotbar doesn't overlap the panel or other mods' UI (Cartomancer/JokerDisplay/Cryptid).

- [ ] **Step 6: Commit**

```bash
git add utilities/crafting_ui.lua main.lua utilities/resource_ui.lua
git commit -m "feat(crafting): Crafting Table modal + hotbar button (click-to-craft)"
```

**Fallback (if the two-column modal misbehaves):** drop the `pattern_preview`/right column and make each recipe row craft directly — give each `recipe_row` `button = 'mc_do_craft_row'` with `ref_table={key=...}`, and `G.FUNCS.mc_do_craft_row` crafts that row's recipe and refreshes. A plain vertical list of "Stone Pickaxe — 3 Cobble, 2 Stick [Craft]" rows is the guaranteed-working minimum and still satisfies Phase 1.

---

## Task 6: Hardening

**Files:** Modify `utilities/resource_ui.lua` (button visibility), spot-fixes as needed

- [ ] **Step 1: Hide the Crafting Table button when there are no recipes/disabled**

No change needed if `resources_enabled` is on (the button rides the panel's existing state-gating). Confirm the button only shows in the panel's visible states (it inherits them since it's part of the panel UIBox).

- [ ] **Step 2: In-game — full regression**

In-game, one session: gather → open table → craft Sticks → craft Stone Pickaxe (joker appears) → verify Pickaxe's +1 drop and Shovel's +$3 and Sword's ×2-vs-boss → save/quit/Continue (resources + crafted jokers persist) → new run (resources reset, jokers gone as normal). Expected: all hold, no errors in the log.

- [ ] **Step 3: Commit (if any fixes were made)**

```bash
git add -A
git commit -m "feat(crafting): Phase 1 hardening + regression pass"
```

---

## Phase 2 (separate plan, after Phase 1 verified)

Manual drag-and-drop: draggable palette tiles, drop targets in the 3×3, reserve/return on place/remove (`add_resource(id, -/+1)`), pattern **normalization** (trim empty border rows/cols) + matching of the hand-built grid against `PB_UTIL.RECIPES`, and Craft-on-match. The modal + `overlay_menu` + recipe data from Phase 1 are reused unchanged; the matcher operates on the same `pattern` tables. The same modal/keybind code is the basis for the future `I` inventory screen.

---

## Self-review notes

- **Spec coverage:** Sticks crafted resource + kind + drop guard (Task 1), recipe registry/tree (Task 2), craft action with afford/slot gating (Task 3), tool-jokers + effects (Task 4), mid-blind modal + button (Task 5), persistence/regression (Task 6). Shaped-matching/drag is explicitly Phase 2. Inventory-via-`I` documented as roadmap.
- **Empty-cell convention:** patterns use `false` (not `nil`) everywhere, and `recipe_ingredients`/`pattern_preview` iterate `1..3` explicitly — no Lua array holes.
- **Naming consistency:** recipe keys, `j_minecraft_<tool>` center keys, `PB_UTIL.craft/can_craft/recipe_by_key/recipe_ingredients/has_joker`, and `G.FUNCS.mc_*` callbacks are used identically across tasks.
- **Known risk:** Task 5 (modal UIBox) needs in-game tuning; it has an explicit list-only fallback. Tool art is intentional placeholder (reused ore-card cells).
