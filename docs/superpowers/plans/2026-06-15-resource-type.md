# Resource Content Type (v1 slice) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Minecraft "Resource" content type to the Minekreift mod: 6 ores stored as persistent counts on `G.GAME`, shown in an always-visible hotbar panel below the consumables, gathered via blind-defeat drops and a resource booster pack.

**Architecture:** Counts are the single source of truth (`G.GAME.minecraft.resources`, plain integers, auto-saved/reset via a `Game:init_game_object` Lua wrapper). A data registry (`PB_UTIL.RESOURCES`) drives a procedurally-generated two-sheet atlas, a self-owned `Weak`-bonded UIBox panel, blind-drop logic, and a booster that spawns hidden ore consumables. No crafting/grid/ore-mining in this slice.

**Tech Stack:** Lua (LuaJIT, Balatro/LÖVE2D) · Steamodded (SMODS) · Lovely · Python 3 + Pillow (art generation).

---

## Verification model (read first)

A Balatro mod runs inside the game; there is **no unit-test runner**. Each task is verified by:
1. **(Optional) Lua syntax check** — only if `luajit`/`lua` is installed: `luajit -bl <file>.lua >/dev/null`. Not installed on this machine, so treat as optional.
2. **In-game check** — launch Balatro with the mod enabled and observe the described outcome.
3. **Console eval / debug log** — use the Steamodded debug console (if enabled in Steamodded config) to run Lua like `PB_UTIL.add_resource('wood', 5)`, or add a temporary `sendDebugMessage(...)` and read the log. Balatro's log is written under the save dir; Steamodded mirrors `sendDebugMessage` there.

**Launching the game** is the real gate for most tasks. Where a step says "In-game:", that means: quit to desktop if running, relaunch Balatro, enter a run, and check.

The work happens on branch `feature/resource-type` (already created).

---

## Naming conventions (locked — use verbatim across all tasks)

| Thing | Value |
|---|---|
| Mod prefix | `minecraft` |
| Resource ids (count keys + registry ids) | `wood`, `cobblestone`, `coal`, `iron`, `gold`, `diamond` |
| Registry global | `PB_UTIL.RESOURCES` = ordered list of `{ id, tier, pos={x,y} }` |
| Counts table | `G.GAME.minecraft.resources[id]` (integer) |
| Card atlas | `SMODS.Atlas` key `mc_resource_cards` (px=71, py=95) |
| Icon atlas | `SMODS.Atlas` key `mc_resource_icons` (px=34, py=34) |
| ConsumableType | key `minecraft_resource` (manual prefix, per Ortalab), `no_collection` |
| Hidden ore consumables | `SMODS.Consumable` key `res_<id>` → center `c_minecraft_res_<id>`, `set='minecraft_resource'` |
| Booster | `SMODS.Booster` key `resource_pack` → `p_minecraft_resource_pack` |
| Panel UIBox handle | `G.minecraft_resources_panel` |
| Config flag | `resources_enabled` |
| Enabled list | `PB_UTIL.ENABLED_RESOURCES = {'registry','resource_consumabletype'}` |

---

## File structure

**New files**
| File | Responsibility |
|---|---|
| `assets/gen_resources.py` | Procedural Pillow generator → writes `assets/1x/resource_cards.png` + `assets/1x/resource_icons.png` |
| `content/resources/registry.lua` | `PB_UTIL.RESOURCES` + the two `SMODS.Atlas` registrations; stores atlas objects for UI lookup |
| `content/resources/resource_consumabletype.lua` | Hidden `SMODS.ConsumableType` + 6 hidden ore `SMODS.Consumable`s |
| `content/boosters/resource_pack.lua` | `SMODS.Booster` spawning the 6 ores into `G.pack_cards` |
| `utilities/resources.lua` | `init_game_object` wrapper, `add_resource`/`get_resource_count`/`set_resource`, `grant_blind_drop`, `Blind:defeat` wrapper, `PB_UTIL.BLIND_DROPS` |
| `utilities/resource_ui.lua` | `build_resources_panel`, `attach_resources_panel`, `update_resources_panel`, `Game:update` wrapper, `PANEL_STATES` |

**Edited files**
| File | Change |
|---|---|
| `config.lua` | add `resources_enabled = true` |
| `utilities/definitions.lua` | add `PB_UTIL.ENABLED_RESOURCES`; add `'resource_pack'` to `ENABLED_BOOSTERS` |
| `main.lua` | load resources utilities + register before the boosters block |
| `utilities/ui.lua` | add a Resources `create_toggle` |

---

## Task 0: Loader wiring (no behavior yet)

**Files:**
- Modify: `config.lua`
- Modify: `utilities/definitions.lua:32-33` (ENABLED_BOOSTERS) and end of file (ENABLED_RESOURCES)
- Modify: `main.lua:12` (insert resources block before boosters)
- Modify: `utilities/ui.lua` (config toggle)
- Create (empty stubs): `content/resources/registry.lua`, `content/resources/resource_consumabletype.lua`, `utilities/resources.lua`, `utilities/resource_ui.lua`

- [ ] **Step 1: Add the config flag**

In `config.lua`, change the returned table to include the new flag:

```lua
return {
    blinds_enabled = true,
    boosters_enabled = true,
    decks_enabled = true,
    enhancements_enabled = true,
    jokers_enabled = true,
    tags_enabled = true,
    vouchers_enabled = true,
    resources_enabled = true,
}
```

- [ ] **Step 2: Add the enabled resources list**

At the end of `utilities/definitions.lua` add:

```lua
PB_UTIL.ENABLED_RESOURCES = {
    'registry',
    'resource_consumabletype',
}
```

Leave `PB_UTIL.ENABLED_BOOSTERS` empty for now — `'resource_pack'` is added in **Task 6**, when the booster file actually exists (adding it here would make the loader fail to find a missing file).

- [ ] **Step 3: Create empty stub files** (so the loader has something to load)

Create `utilities/resources.lua`:
```lua
-- Resource state + helpers (filled in Task 1 / Task 4)
```

Create `utilities/resource_ui.lua`:
```lua
-- Resource inventory panel (filled in Task 3)
```

Create `content/resources/registry.lua`:
```lua
-- Resource registry + atlases (filled in Task 2)
```

Create `content/resources/resource_consumabletype.lua`:
```lua
-- Hidden resource ConsumableType + ore consumables (filled in Task 5)
```

- [ ] **Step 4: Wire the loader in `main.lua`**

In `main.lua`, insert this block **immediately before** the `if PB_UTIL.config.boosters_enabled then` block (currently around line 12), so resources load before boosters:

```lua
if PB_UTIL.config.resources_enabled then
    SMODS.load_file("utilities/resources.lua")()
    SMODS.load_file("utilities/resource_ui.lua")()
    PB_UTIL.register_items(PB_UTIL.ENABLED_RESOURCES, "resources")
end
```

- [ ] **Step 5: Add the config toggle**

In `utilities/ui.lua`, inside the first column's `nodes` list (the one containing the "Decks" toggle, around line 47), add after the Decks toggle:

```lua
create_toggle {
    label = "Resources",
    ref_table = PB_UTIL.config,
    ref_value = 'resources_enabled',
},
```

- [ ] **Step 6: In-game — verify clean load**

In-game: enable the Minecraft mod, launch Balatro. Expected: the game loads with **no crash/error popup**, the mod's config tab shows a new "Resources" toggle. (Stubs do nothing yet.)

- [ ] **Step 7: Commit**

```bash
git add config.lua utilities/definitions.lua main.lua utilities/ui.lua content/resources utilities/resources.lua utilities/resource_ui.lua
git commit -m "feat(resources): loader wiring + config toggle (no behavior yet)"
```

---

## Task 1: Persistent state + mutation helpers

**Files:**
- Modify: `utilities/resources.lua`

- [ ] **Step 1: Implement state seeding + helpers**

Replace the contents of `utilities/resources.lua` with:

```lua
-- Resource state + helpers

-- Seed per-run resource counts on G.GAME via an init_game_object wrapper.
-- Runs fresh for every new run, so counts auto-reset; plain integers => auto-saved.
local _init_game_object = Game.init_game_object
function Game:init_game_object()
    local t = _init_game_object(self)
    t.minecraft = t.minecraft or {}
    t.minecraft.resources = {}
    for _, r in ipairs(PB_UTIL.RESOURCES or {}) do
        t.minecraft.resources[r.id] = 0
    end
    return t
end

-- Defensive accessor: guarantees the table exists before read/write.
local function ensure_store()
    G.GAME.minecraft = G.GAME.minecraft or {}
    G.GAME.minecraft.resources = G.GAME.minecraft.resources or {}
    return G.GAME.minecraft.resources
end

function PB_UTIL.get_resource_count(id)
    return ensure_store()[id] or 0
end

function PB_UTIL.set_resource(id, amount)
    local store = ensure_store()
    store[id] = math.max(0, math.floor(tonumber(amount) or 0))
    return store[id]
end

-- Single mutation funnel. Marks the panel dirty when an ore is first owned (0 -> >0)
-- so the UI can flip it from greyed to active (see Task 3).
function PB_UTIL.add_resource(id, amount)
    local store = ensure_store()
    local prev = store[id] or 0
    local new = math.max(0, prev + (math.floor(tonumber(amount) or 0)))
    store[id] = new
    if prev == 0 and new > 0 then
        G.GAME.minecraft._panel_dirty = true
    end
    return new
end
```

- [ ] **Step 2: In-game — verify persistence + reset**

In-game (with the Steamodded debug console, or a temporary `sendDebugMessage`):
1. Start a run. Run `PB_UTIL.add_resource('wood', 5)`; then `PB_UTIL.get_resource_count('wood')` → expect `5`.
2. Save & quit to menu, then "Continue" the run; `PB_UTIL.get_resource_count('wood')` → expect `5` (persisted).
3. Start a **new** run; `PB_UTIL.get_resource_count('wood')` → expect `0` (reset).

If you cannot open the console, add this temporary line at the end of `add_resource` and watch the log: `sendDebugMessage('wood='..tostring(PB_UTIL.get_resource_count('wood')), 'Minecraft')`, then remove it before commit.

- [ ] **Step 3: Commit**

```bash
git add utilities/resources.lua
git commit -m "feat(resources): persistent counts on G.GAME + add/get/set helpers"
```

---

## Task 2: Art generator + registry + atlases

**Files:**
- Create: `assets/gen_resources.py`
- Create: `assets/1x/resource_cards.png`, `assets/1x/resource_icons.png` (generated)
- Create: `assets/2x/resource_cards.png`, `assets/2x/resource_icons.png` (generated)
- Modify: `content/resources/registry.lua`

- [ ] **Step 1: Write the procedural art generator**

Create `assets/gen_resources.py`:

```python
"""Procedurally generate the resource sprite sheets (deterministic, no RNG).

Outputs (1x):
  assets/1x/resource_icons.png  -> 34x34 cells, 3x2 grid (102x68)
  assets/1x/resource_cards.png  -> 71x95 cells, 3x2 grid (213x190)
Run `utils.py` afterwards to produce the 2x sheets.
Ore order (row-major): wood, cobblestone, coal, iron, gold, diamond.
"""
from PIL import Image

ICON = 34
CARD_W, CARD_H = 71, 95
COLS, ROWS = 3, 2

# Palette
STONE      = (124, 124, 124, 255)
STONE_HI   = (150, 150, 150, 255)
STONE_LO   = (98, 98, 98, 255)
WOOD       = (150, 116, 67, 255)
WOOD_LINE  = (110, 82, 44, 255)
COBBLE_LO  = (96, 96, 96, 255)
COBBLE_HI  = (160, 160, 160, 255)
COAL       = (32, 32, 32, 255)
IRON       = (208, 170, 140, 255)
GOLD       = (250, 224, 70, 255)
DIAMOND    = (90, 220, 215, 255)
CARD_BG    = (40, 44, 52, 255)
TIER_TINT  = {1: (90, 110, 90, 255), 2: (110, 100, 70, 255), 3: (70, 110, 130, 255)}

# Fixed speckle clusters (x,y) for ore blobs on a stone base, 16x16 space.
SPECKLES = [(4, 4), (5, 4), (4, 5), (10, 6), (11, 6), (6, 10), (7, 11), (11, 11), (12, 11)]

def base_stone():
    img = Image.new("RGBA", (16, 16), STONE)
    px = img.load()
    for (x, y) in [(2, 3), (9, 2), (13, 5), (3, 12), (12, 13), (7, 7)]:
        px[x, y] = STONE_LO
    for (x, y) in [(1, 8), (8, 9), (14, 9), (5, 14)]:
        px[x, y] = STONE_HI
    return img

def ore(color):
    img = base_stone()
    px = img.load()
    for (x, y) in SPECKLES:
        px[x, y] = color
    return img

def wood():
    img = Image.new("RGBA", (16, 16), WOOD)
    px = img.load()
    for x in (2, 3, 8, 9, 13):
        for y in range(16):
            if (x + y) % 3 != 0:
                px[x, y] = WOOD_LINE
    return img

def cobblestone():
    img = Image.new("RGBA", (16, 16), STONE)
    px = img.load()
    for (x, y) in [(2, 2), (3, 2), (2, 3), (9, 3), (10, 3), (4, 9), (5, 9), (11, 10), (12, 10), (7, 12)]:
        px[x, y] = COBBLE_LO
    for (x, y) in [(6, 5), (12, 6), (3, 11), (13, 12)]:
        px[x, y] = COBBLE_HI
    return img

ORES = [
    ("wood", wood()),
    ("cobblestone", cobblestone()),
    ("coal", ore(COAL)),
    ("iron", ore(IRON)),
    ("gold", ore(GOLD)),
    ("diamond", ore(DIAMOND)),
]

def nn(img, factor):
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)

def build_icons():
    sheet = Image.new("RGBA", (ICON * COLS, ICON * ROWS), (0, 0, 0, 0))
    for i, (_id, tex) in enumerate(ORES):
        cx, cy = (i % COLS) * ICON, (i // COLS) * ICON
        # dark slot background + 1px border
        slot = Image.new("RGBA", (ICON, ICON), (20, 22, 26, 255))
        for x in range(ICON):
            slot.putpixel((x, 0), (70, 74, 82, 255)); slot.putpixel((x, ICON - 1), (70, 74, 82, 255))
        for y in range(ICON):
            slot.putpixel((0, y), (70, 74, 82, 255)); slot.putpixel((ICON - 1, y), (70, 74, 82, 255))
        block = nn(tex, 2)  # 16 -> 32
        slot.alpha_composite(block, (1, 1))
        sheet.alpha_composite(slot, (cx, cy))
    sheet.save("minecraft-main/assets/1x/resource_icons.png")
    print("wrote resource_icons.png", sheet.size)

def build_cards():
    sheet = Image.new("RGBA", (CARD_W * COLS, CARD_H * ROWS), (0, 0, 0, 0))
    tiers = {"wood": 1, "cobblestone": 1, "coal": 1, "iron": 2, "gold": 2, "diamond": 3}
    for i, (_id, tex) in enumerate(ORES):
        cx, cy = (i % COLS) * CARD_W, (i // COLS) * CARD_H
        face = Image.new("RGBA", (CARD_W, CARD_H), CARD_BG)
        tint = TIER_TINT[tiers[_id]]
        for x in range(CARD_W):  # top tier-coloured band
            for y in range(6):
                face.putpixel((x, y), tint)
        block = nn(tex, 3)  # 16 -> 48
        face.alpha_composite(block, ((CARD_W - 48) // 2, (CARD_H - 48) // 2 - 4))
        sheet.alpha_composite(face, (cx, cy))
    sheet.save("minecraft-main/assets/1x/resource_cards.png")
    print("wrote resource_cards.png", sheet.size)

if __name__ == "__main__":
    build_icons()
    build_cards()
```

- [ ] **Step 2: Generate the 1x sheets**

Run (from the Mods directory, so the hardcoded `minecraft-main/assets/...` paths resolve):
```bash
cd "/Users/alessandro/Library/Application Support/Balatro/Mods" && python3 minecraft-main/assets/gen_resources.py
```
Expected output:
```
wrote resource_icons.png (102, 68)
wrote resource_cards.png (213, 190)
```

- [ ] **Step 3: Generate the 2x sheets via the existing pipeline**

```bash
cd "/Users/alessandro/Library/Application Support/Balatro/Mods" && python3 - <<'PY'
import sys; sys.path.insert(0, "minecraft-main/assets")
from utils import scale_image
scale_image("minecraft-main/assets/1x/resource_icons.png", "minecraft-main/assets/2x/resource_icons.png", 2)
scale_image("minecraft-main/assets/1x/resource_cards.png", "minecraft-main/assets/2x/resource_cards.png", 2)
PY
```
Expected: two "Image scaled and saved" lines; `assets/2x/resource_icons.png` is 204×136 and `assets/2x/resource_cards.png` is 426×380.

- [ ] **Step 4: Write the registry + atlas registrations**

Replace `content/resources/registry.lua` with:

```lua
-- Resource registry + atlases.

PB_UTIL.RESOURCES = {
    { id = 'wood',        tier = 1, pos = { x = 0, y = 0 } },
    { id = 'cobblestone', tier = 1, pos = { x = 1, y = 0 } },
    { id = 'coal',        tier = 1, pos = { x = 2, y = 0 } },
    { id = 'iron',        tier = 2, pos = { x = 0, y = 1 } },
    { id = 'gold',        tier = 2, pos = { x = 1, y = 1 } },
    { id = 'diamond',     tier = 3, pos = { x = 2, y = 1 } },
}

-- Lookup by id (used by drops/UI).
PB_UTIL.RESOURCE_BY_ID = {}
for _, r in ipairs(PB_UTIL.RESOURCES) do PB_UTIL.RESOURCE_BY_ID[r.id] = r end

-- Card sheet (71x95) for the booster pack; icon sheet (34x34) for the panel.
PB_UTIL.card_atlas = SMODS.Atlas {
    key = 'mc_resource_cards', path = 'resource_cards.png', px = 71, py = 95,
}
PB_UTIL.icon_atlas = SMODS.Atlas {
    key = 'mc_resource_icons', path = 'resource_icons.png', px = 34, py = 34,
}
```

- [ ] **Step 5: In-game — verify atlases load**

In-game: start a run. In the console run:
```lua
sendDebugMessage(tostring(PB_UTIL.icon_atlas and PB_UTIL.icon_atlas.key)..' / '..tostring(G.ASSET_ATLAS[PB_UTIL.icon_atlas.key] ~= nil), 'Minecraft')
```
Expected: a non-nil key and `true` (atlas present in `G.ASSET_ATLAS`). No load error popup. (If the boolean is `false`, note the actual key by dumping `for k in pairs(G.ASSET_ATLAS) do sendDebugMessage(k,'Minecraft') end` — used in Task 3.)

- [ ] **Step 6: Commit**

```bash
git add assets/gen_resources.py assets/1x/resource_cards.png assets/1x/resource_icons.png assets/2x/resource_cards.png assets/2x/resource_icons.png content/resources/registry.lua
git commit -m "feat(resources): procedural ore art + registry + atlases"
```

---

## Task 3: Inventory hotbar panel (HIGHEST-RISK — iterate in-game)

This is the only task that must be visually tuned in the running game. Build it, then adjust `offset`/`align`/`scale` until it sits cleanly below the consumables area. A documented fallback is at the end.

**Files:**
- Modify: `utilities/resource_ui.lua`

- [ ] **Step 1: Implement the panel + show/hide loop**

Replace `utilities/resource_ui.lua` with:

```lua
-- Resource inventory hotbar panel: a self-owned UIBox bonded Weak to G.consumeables.

-- States in which the panel should be visible.
PB_UTIL.PANEL_STATES = {
    [G.STATES.SELECTING_HAND] = true,
    [G.STATES.DRAW_TO_HAND]   = true,
    [G.STATES.HAND_PLAYED]    = true,
    [G.STATES.SHOP]           = true,
    [G.STATES.BLIND_SELECT]   = true,
    [G.STATES.ROUND_EVAL]     = true,
}

local PER_ROW = 3

-- Build the UIBox definition from the registry + current counts.
function PB_UTIL.build_resources_panel()
    local store = (G.GAME.minecraft and G.GAME.minecraft.resources) or {}
    local atlas = G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]
    local cells = {}
    for _, r in ipairs(PB_UTIL.RESOURCES) do
        local count = store[r.id] or 0
        local owned = count > 0
        local spr = Sprite(0, 0, 0.5, 0.5, atlas, r.pos)
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
    local rows = {}
    for i = 1, #cells, PER_ROW do
        local row = { n = G.UIT.R, config = { align = 'cm' }, nodes = {} }
        for j = i, math.min(i + PER_ROW - 1, #cells) do
            row.nodes[#row.nodes + 1] = cells[j]
        end
        rows[#rows + 1] = row
    end
    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0.06, r = 0.1, colour = G.C.BLACK, emboss = 0.05 },
        nodes = rows,
    }
end

-- (Re)create the panel UIBox, bonded below the consumables area.
function PB_UTIL.attach_resources_panel()
    if G.minecraft_resources_panel and not G.minecraft_resources_panel.REMOVED then
        G.minecraft_resources_panel:remove()
    end
    G.GAME.minecraft._panel_dirty = false
    G.minecraft_resources_panel = UIBox {
        definition = PB_UTIL.build_resources_panel(),
        config = { align = 'cm', offset = { x = 0, y = 1.5 }, major = G.consumeables, bond = 'Weak' },
    }
end

-- Per-frame: create/refresh/hide based on game state.
function PB_UTIL.update_resources_panel()
    local can_show = G.STATE and PB_UTIL.PANEL_STATES[G.STATE]
        and G.consumeables and G.GAME and G.GAME.minecraft
    if can_show then
        if not G.minecraft_resources_panel or G.minecraft_resources_panel.REMOVED then
            PB_UTIL.attach_resources_panel()
        elseif G.GAME.minecraft._panel_dirty then
            PB_UTIL.attach_resources_panel()
        end
    elseif G.minecraft_resources_panel and not G.minecraft_resources_panel.REMOVED then
        G.minecraft_resources_panel:remove()
        G.minecraft_resources_panel = nil
    end
end

local _game_update = Game.update
function Game:update(dt)
    _game_update(self, dt)
    local ok, err = pcall(PB_UTIL.update_resources_panel)
    if not ok then sendDebugMessage('panel error: ' .. tostring(err), 'Minecraft') end
end
```

- [ ] **Step 2: In-game — verify the panel renders + live-updates**

In-game: start a run. Expected: a black panel with 6 ore icons (greyed "0"s) appears **below the consumables area**. Run `PB_UTIL.add_resource('iron', 3)`; the iron count updates to `3` in white **without** a full UI flash (live rebind), and a previously-grey icon becomes "active".

- [ ] **Step 3: In-game — tune placement**

If the panel overlaps the consumables or sits awkwardly, adjust only the `config` in `attach_resources_panel`: increase/decrease `offset.y`, or try `align = 'tm'` / `'bm'`. Re-launch and re-check until it reads as a hotbar under the consumables. Keep `major = G.consumeables, bond = 'Weak'`.

- [ ] **Step 4: In-game — verify no cross-mod conflict**

In-game: with **Cartomancer, JokerDisplay, and Cryptid** also enabled, enter a run + open the shop. Expected: the panel still appears below consumables, nothing overlaps the deck/consumables/joker rows, and no errors. (If a conflict appears, note which mod and we adjust `offset`/states — do not edit those mods.)

- [ ] **Step 5: Commit**

```bash
git add utilities/resource_ui.lua
git commit -m "feat(resources): always-visible hotbar inventory panel"
```

**Fallback (only if the Weak bond misbehaves):** replace the `config` in `attach_resources_panel` with an unbonded box, and reposition each frame in `update_resources_panel` by setting `G.minecraft_resources_panel.T.x = G.consumeables.T.x` and `.T.y = G.consumeables.T.y + 1.5` after ensuring it exists. Same visual result, explicit coordinates.

---

## Task 4: Boss / blind defeat drops

**Files:**
- Modify: `utilities/resources.lua` (append)

- [ ] **Step 1: Implement the drop table + grant logic + defeat wrapper**

Append to `utilities/resources.lua`:

```lua
-- Per-blind themed overrides (opt-in). Keyed by blind.name (the prefixed key string,
-- e.g. 'bl_minecraft_creeper'). Anything without an entry uses the tier-roll fallback.
PB_UTIL.BLIND_DROPS = {
    bl_minecraft_creeper  = { id = 'coal',   amount = 2 },
    bl_minecraft_skeleton = { id = 'iron',   amount = 1 },
    bl_minecraft_zombie   = { id = 'wood',   amount = 2 },
}

-- Returns a random ore id of exactly `tier` (run-seeded deterministic).
local function random_ore_of_tier(tier, seed_key)
    local pool = {}
    for _, r in ipairs(PB_UTIL.RESOURCES) do
        if r.tier == tier then pool[#pool + 1] = r.id end
    end
    if #pool == 0 then return PB_UTIL.RESOURCES[1].id end
    return pseudorandom_element(pool, pseudoseed(seed_key))
end

-- Grant resources for defeating `blind`. PLACEHOLDER BALANCE (shape is fixed, numbers tunable).
function PB_UTIL.grant_blind_drop(blind)
    if not blind then return end
    local spec = blind.name and PB_UTIL.BLIND_DROPS[blind.name]
    if spec then
        PB_UTIL.add_resource(spec.id, spec.amount)
        return
    end
    local ante = (G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or 1
    local is_boss = blind.boss and true or false
    local max_tier = (ante >= 6 and 3) or (ante >= 3 and 2) or 1
    -- bosses bias toward the highest unlocked tier; others toward tier 1
    local tier = is_boss and max_tier or 1
    local amount = is_boss and 2 or 1
    PB_UTIL.add_resource(random_ore_of_tier(tier, 'mc_drop_' .. ante .. '_' .. tostring(blind.name)), amount)
end

-- Wrap Blind:defeat (same technique Steamodded uses) so drops fire on every blind win.
local _blind_defeat = Blind.defeat
function Blind:defeat(silent)
    _blind_defeat(self, silent)
    pcall(PB_UTIL.grant_blind_drop, self)
end
```

- [ ] **Step 2: In-game — verify drops on blind defeat**

In-game: start a run, beat the **small blind**. Expected: a resource count increments in the panel (tier-1 ore, amount 1). Beat a **boss blind**; expect amount 2 and a tier matching the ante band (or the themed override if it's Creeper/Skeleton/Zombie). Confirm the panel reflects it immediately.

- [ ] **Step 3: In-game — verify drops persist**

In-game: after some drops, save & quit, then Continue. Expected: counts unchanged (already covered by Task 1's persistence, re-confirm with real drops).

- [ ] **Step 4: Commit**

```bash
git add utilities/resources.lua
git commit -m "feat(resources): blind-defeat drops (per-blind table + ante-scaled fallback)"
```

---

## Task 5: Hidden ConsumableType + ore consumables

**Files:**
- Modify: `content/resources/resource_consumabletype.lua`

- [ ] **Step 1: Implement the hidden type + 6 ore consumables**

Replace `content/resources/resource_consumabletype.lua` with:

```lua
-- Hidden ConsumableType used ONLY to populate the resource booster pack.
-- These never appear in the collection, shop, or normal pools.

SMODS.ConsumableType {
    key = 'minecraft_resource',
    primary_colour = HEX('6b5840'),
    secondary_colour = HEX('8b7765'),
    collection_rows = { 3, 3 },
    shop_rate = 0,
    no_collection = true,
    default = 'c_minecraft_res_wood',
    loc_txt = { name = 'Resource', collection = 'Resources' },
}

-- Display metadata for each ore (name shown on the pack card's tooltip).
local ORE_LOC = {
    wood        = 'Wood',
    cobblestone = 'Cobblestone',
    coal        = 'Coal',
    iron        = 'Iron',
    gold        = 'Gold',
    diamond     = 'Diamond',
}

for _, r in ipairs(PB_UTIL.RESOURCES) do
    local id = r.id
    SMODS.Consumable {
        key = 'res_' .. id,
        set = 'minecraft_resource',
        atlas = 'mc_resource_cards',
        pos = r.pos,
        cost = 0,
        discovered = true,
        no_collection = true,
        loc_txt = {
            name = ORE_LOC[id],
            text = { 'Adds {C:attention}1{} ' .. ORE_LOC[id], 'to your resources.' },
        },
        can_use = function(self, card) return true end,
        use = function(self, card, area, copier)
            PB_UTIL.add_resource(id, 1)
        end,
        in_pool = function(self, args) return false end,
    }
end
```

- [ ] **Step 2: In-game — verify the centers exist and stay hidden**

In-game: start a run. In console:
```lua
sendDebugMessage(tostring(G.P_CENTERS['c_minecraft_res_diamond'] ~= nil), 'Minecraft')
```
Expected: `true`. Then open the **collection** menu (Tarot/Planet/etc.) and confirm there is **no** "Resources" tab/section, and resources do not appear in the shop's consumable slot.

- [ ] **Step 3: In-game — verify `use` adds a resource**

In console: `G.P_CENTERS['c_minecraft_res_gold'].use(nil, nil, nil, nil)` is not how to call it; instead create + use a card:
```lua
local c = SMODS.create_card({ key = 'c_minecraft_res_gold', area = G.consumeables, skip_materialize = true })
c:use_consumeable(G.consumeables)
```
Expected: gold count increases by 1 in the panel. (The card is then removed by the base use flow.)

- [ ] **Step 4: Commit**

```bash
git add content/resources/resource_consumabletype.lua
git commit -m "feat(resources): hidden ConsumableType + 6 ore consumables"
```

---

## Task 6: Resource booster pack

**Files:**
- Create: `content/boosters/resource_pack.lua`

- [ ] **Step 1: Enable the booster in the loader**

In `utilities/definitions.lua`, add the booster to the (currently empty) list:

```lua
PB_UTIL.ENABLED_BOOSTERS = {
    'resource_pack',
}
```

- [ ] **Step 2: Implement the booster**

Create `content/boosters/resource_pack.lua`:

```lua
-- "Loot Chest" booster: spawns the 6 ores so the player picks one.
-- Uses the card atlas's diamond cell as a placeholder pack image (cosmetic, swap later).

SMODS.Booster {
    key = 'resource_pack',
    atlas = 'mc_resource_cards',
    pos = { x = 2, y = 1 }, -- diamond cell as placeholder pack art
    config = { choose = 1, extra = 6 },
    cost = 4,
    weight = 1,
    loc_txt = {
        name = 'Loot Chest',
        text = { 'Choose {C:attention}1{} of up to', '{C:attention}6{} Minecraft resources.' },
    },
    create_card = function(self, card, i)
        local ore = PB_UTIL.RESOURCES[i] or PB_UTIL.RESOURCES[1]
        return create_card('minecraft_resource', G.pack_cards, nil, nil, true, true,
            'c_minecraft_res_' .. ore.id, 'mc_respack')
    end,
}
```

- [ ] **Step 3: In-game — verify the pack appears and grants on pick**

In-game: reach a shop (or force one in console: `G.GAME.dollars = 50` and reroll until a Loot Chest appears, or temporarily raise `weight`). Buy the **Loot Chest**. Expected: it opens showing up to 6 ore cards (one per ore); picking one increments that resource in the panel by 1, and **nothing is added to the consumables area**. Skipping the pack leaves counts unchanged.

- [ ] **Step 4: In-game — verify save/restore mid-pack**

In-game: open the pack, then save & quit before picking; Continue. Expected: the pack state restores and picking still grants correctly (no crash, no double-grant).

- [ ] **Step 5: Commit**

```bash
git add utilities/definitions.lua content/boosters/resource_pack.lua
git commit -m "feat(resources): Loot Chest resource booster pack"
```

---

## Task 7: Hardening + polish

**Files:**
- Modify: `utilities/resource_ui.lua` (optional icon dimming)
- Modify: `metadata.json` (description), `README.md` (optional)

- [ ] **Step 1: Dim unowned icons (optional polish)**

In `build_resources_panel`, after creating `spr`, dim icons for unowned ores so "grayed when 0" applies to the **icon** too, not just the count. Replace the `local spr = Sprite(...)` line with:

```lua
        local spr = Sprite(0, 0, 0.5, 0.5, atlas, r.pos)
        if not owned and spr.set_alpha then spr:set_alpha(0.35) end
```

In-game: confirm unowned ore icons render dimmer than owned ones. If `set_alpha` is unavailable (no visible change / error in log), revert this one line — count-colour graying from Task 3 already satisfies the requirement, and this is cosmetic only.

- [ ] **Step 2: Fix the stale mod description**

In `metadata.json`, update the description to reflect the broader mod:

```json
  "description": "A Minecraft-themed content mod for Balatro: boss blinds, jokers, decks, and a Resource gathering system.",
```

- [ ] **Step 3: Full regression pass**

In-game, single session: new run → beat several blinds (watch drops) → buy a Loot Chest (pick an ore) → save/quit/continue (counts persist) → open collection (no Resources tab) → enter menu (panel hidden) → new run (counts reset to 0). Expected: all hold, no errors in the log.

- [ ] **Step 4: Commit**

```bash
git add utilities/resource_ui.lua metadata.json
git commit -m "feat(resources): polish — icon dimming + metadata; regression pass"
```

---

## Forward seam (no implementation here)

The later 3×3 crafting grid will: read `G.GAME.minecraft.resources` to know what the player has; render draggable tiles (it can reuse `PB_UTIL.icon_atlas`); and on craft, call `PB_UTIL.add_resource(id, -n)` to spend, then create the output (tool/joker/consumable). This slice deliberately leaves counts as that clean handoff point.

---

## Self-review notes

- **Spec coverage:** counts/state (Task 1), registry+atlas (Task 2), always-visible grayed panel (Task 3), blind drops (Task 4), hidden type/consumables (Task 5), booster pack (Task 6), save/load (verified across Tasks 1/4/6, no custom code by design), forward seam (documented). All spec sections map to a task.
- **Naming consistency:** ore ids (`wood`…`diamond`), center keys (`c_minecraft_res_<id>`), atlas keys (`mc_resource_cards`/`mc_resource_icons`), and `G.GAME.minecraft.resources` are used identically in every task.
- **Known risk:** Task 3 (UIBox placement) and Task 7 Step 1 (`set_alpha`) are the only steps requiring in-game iteration; both have explicit fallbacks. The atlas-key lookup (`G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]`) has a debug-dump escape hatch in Task 2 Step 5.
