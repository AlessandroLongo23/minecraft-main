# Emerald Resource Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add **Emerald** as a gathered, tier-2 ore that drops from blinds, appears in Loot Chests, shows in the hotbar, and is documented in the wiki — leaving its *use* (Villager Trading) for a later spec.

**Architecture:** The resource subsystem discovers gathered ores generically by iterating `PB_UTIL.RESOURCES` and filtering `kind == 'gathered'`, so most plumbing (count seeding, blind-drop tier roll, Loot Chest pack sampling, Cash Out rendering) requires no change once the registry entry and art exist. The only edits are: the registry entry, procedural art for the free atlas cell (1,2), a one-line `ORE_LOC`→`r.name` fix in the pack-consumable file (prevents a load crash and removes duplication), a hotbar column bump (6→7), and wiki updates.

**Tech Stack:** Lua (Steamodded/SMODS + Lovely Injector, no build/test runner), Python 3 + Pillow for procedural sprite generation, `luac -p` for Lua syntax checks, Obsidian-flavored Markdown wiki.

---

## Critical environment notes (read before any task)

- **Spec:** `docs/superpowers/specs/2026-06-19-emerald-resource-design.md`.
- **Working directory for art scripts:** the art generators write to `BalaCraft/assets/...` (hardcoded relative paths), so they MUST be run from the **`Mods/` parent directory**, i.e. `/Users/alessandro/Library/Application Support/Balatro/Mods`. All commands below use that directory.
- **`utils.py` is NOT a turnkey regenerator.** Its `__main__` is a scratchpad currently wired to `farlands.png`. Do not run `python assets/utils.py` to derive the 2x sheets — instead call its reusable `scale_image()` with explicit paths (shown in Task 3). The CLAUDE.md "run utils.py" note is stale.
- **No Balatro launch by agents.** Final behavioral verification (Task 6) is a hand-off checklist for the user; agents verify with `luac -p`, Python pixel assertions, and `grep`/file-existence only.
- **Atlas layout:** icon sheet `bc_resource_icons` (34×34 cells, 3×3) and card sheet `bc_resource_cards` (71×95 cells, 3×3). Used cells: wood(0,0) cobblestone(1,0) coal(2,0) iron(0,1) gold(1,1) diamond(2,1) sticks(0,2). **Emerald goes in the free cell (1,2);** (2,2) stays free. 1x sizes: icons 102×102, cards 213×285. 2x sizes: icons 204×204, cards 426×570.

---

## Task 1: Registry entry

**Files:**
- Modify: `BalaCraft/content/resources/registry.lua` (the `PB_UTIL.RESOURCES` table, after the `diamond` line)

- [ ] **Step 1: Add the emerald entry**

In `BalaCraft/content/resources/registry.lua`, insert a new line immediately after the `diamond` entry (line 9) and before the `sticks` entry:

```lua
    { id = 'diamond',     name = 'Diamond',     kind = 'gathered', tier = 3, pos = { x = 2, y = 1 } },
    { id = 'emerald',     name = 'Emerald',     kind = 'gathered', tier = 2, pos = { x = 1, y = 2 } },
    { id = 'sticks',      name = 'Sticks',      kind = 'crafted',            pos = { x = 0, y = 2 } },
```

(Only the `emerald` line is new; the `diamond` and `sticks` lines are shown for placement context — leave them unchanged.)

- [ ] **Step 2: Syntax-check the file**

Run (from the `Mods/` dir):
```bash
luac -p "BalaCraft/content/resources/registry.lua" && echo SYNTAX_OK
```
Expected: prints `SYNTAX_OK` with no parse errors.

- [ ] **Step 3: Confirm the entry is present and well-formed**

Run:
```bash
grep -n "id = 'emerald'" "BalaCraft/content/resources/registry.lua"
```
Expected: one match showing `kind = 'gathered'`, `tier = 2`, `pos = { x = 1, y = 2 }`.

- [ ] **Step 4: Commit**

```bash
git add "BalaCraft/content/resources/registry.lua"
git commit -m "feat(resources): register Emerald as a gathered tier-2 ore"
```

---

## Task 2: Procedural art (generate the emerald sprite)

**Files:**
- Modify: `BalaCraft/assets/gen_resources.py` (palette, shape, renderer, `ICONS` list, card-tier map)
- Regenerates (do not edit by hand): `BalaCraft/assets/1x/resource_icons.png`, `BalaCraft/assets/1x/resource_cards.png`

- [ ] **Step 1: Add the emerald palette**

In `BalaCraft/assets/gen_resources.py`, in the "Refined-mineral palettes" block (right after the `COAL_PAL = ...` line), add:

```python
EMERALD_PAL = ((60, 200, 110, 255),  (150, 245, 175, 255), (30, 130, 70, 255),   (18, 80, 45, 255))
```

- [ ] **Step 2: Add the emerald shape + renderer**

In the "Refined minerals" section, after the `coal_lump()` function, add a dedicated chunky beveled-octagon gem (wider/blockier than the cyan diamond so it reads as a distinct MC emerald):

```python
EMERALD_SHAPE = {3: (6, 9), 4: (5, 10), 5: (4, 11), 6: (3, 12), 7: (3, 12),
                 8: (3, 12), 9: (4, 11), 10: (5, 10), 11: (6, 9)}

def emerald_gem():
    base, hi, sh, outline = EMERALD_PAL
    facets = [((6, 5), (235, 255, 240, 255)), ((5, 6), (235, 255, 240, 255)),
              ((9, 8), sh), ((10, 9), sh), ((7, 7), hi)]
    return _render(_fill(EMERALD_SHAPE), base, hi, sh, outline, hi_rows=2, sh_rows=2, facets=facets)
```

- [ ] **Step 3: Append emerald to the ICONS list**

Emerald is a gathered ore but must be appended **after** `sticks` so its generation index is 7 → cell (1,2), keeping every existing cell fixed. Change:

```python
ICONS = ORES + [("sticks", sticks())]
```
to:
```python
# Emerald is appended AFTER sticks (index 7 -> cell (1,2)) so existing cells stay put.
ICONS = ORES + [("sticks", sticks()), ("emerald", emerald_gem())]
```

- [ ] **Step 4: Add emerald to the card-tier map**

In `build_cards()`, the `tiers` dict drives the top tier-colour band. Change:

```python
    tiers = {"wood": 1, "cobblestone": 1, "coal": 1, "iron": 2, "gold": 2, "diamond": 3, "sticks": 1}
```
to:
```python
    tiers = {"wood": 1, "cobblestone": 1, "coal": 1, "iron": 2, "gold": 2, "diamond": 3, "sticks": 1, "emerald": 2}
```

- [ ] **Step 5: Regenerate the 1x sheets**

Run (from the `Mods/` dir):
```bash
python3 BalaCraft/assets/gen_resources.py
```
Expected output: `wrote resource_icons.png (102, 102)` and `wrote resource_cards.png (213, 285)`.

- [ ] **Step 6: Verify the emerald cell is present, green, and dimensions are unchanged**

Run:
```bash
python3 -c "
from PIL import Image
ic = Image.open('BalaCraft/assets/1x/resource_icons.png').convert('RGBA')
cd = Image.open('BalaCraft/assets/1x/resource_cards.png').convert('RGBA')
assert ic.size == (102, 102), ic.size
assert cd.size == (213, 285), cd.size
# icon cell (1,2): top-left pixel (34, 68), 34x34 cell; sample the interior
px = [ic.getpixel((34 + x, 68 + y)) for x in range(4, 30) for y in range(4, 30)]
assert any(g > 120 and g > r + 30 and g > b + 30 for (r, g, b, a) in px), 'no green pixel in emerald icon cell'
# sanity: diamond cell (2,1) still cyan-ish (not moved)
dpx = [ic.getpixel((68 + x, 34 + y)) for x in range(4, 30) for y in range(4, 30)]
assert any(b > 120 and g > 120 and b > r + 20 for (r, g, b, a) in dpx), 'diamond cell changed unexpectedly'
print('art OK: emerald green in (1,2), diamond intact')
"
```
Expected: `art OK: emerald green in (1,2), diamond intact`.

- [ ] **Step 7: Derive the 2x sheets (bypassing the utils.py scratchpad)**

Run:
```bash
python3 -c "
import sys; sys.path.insert(0, 'BalaCraft/assets')
from utils import scale_image
scale_image('BalaCraft/assets/1x/resource_icons.png', 'BalaCraft/assets/2x/resource_icons.png', 2)
scale_image('BalaCraft/assets/1x/resource_cards.png', 'BalaCraft/assets/2x/resource_cards.png', 2)
"
```
Expected: two `Image scaled and saved to ...` lines.

- [ ] **Step 8: Verify 2x dimensions**

Run:
```bash
python3 -c "
from PIL import Image
assert Image.open('BalaCraft/assets/2x/resource_icons.png').size == (204, 204)
assert Image.open('BalaCraft/assets/2x/resource_cards.png').size == (426, 570)
print('2x OK')
"
```
Expected: `2x OK`.

- [ ] **Step 9: Commit**

```bash
git add "BalaCraft/assets/gen_resources.py" \
        "BalaCraft/assets/1x/resource_icons.png" "BalaCraft/assets/1x/resource_cards.png" \
        "BalaCraft/assets/2x/resource_icons.png" "BalaCraft/assets/2x/resource_cards.png"
git commit -m "feat(art): add Emerald gem sprite at atlas cell (1,2)"
```

---

## Task 3: Fix pack-consumable display name (prevent load crash) + DRY

**Files:**
- Modify: `BalaCraft/content/resources/resource_consumabletype.lua` (remove the local `ORE_LOC` table; use `r.name`)

**Why:** This file registers one `SMODS.Consumable { key = 'res_<id>' }` per gathered ore (creating `c_balacraft_res_<id>` centers used by the Loot Chest pack and as the tile base center). It currently reads each name from a hardcoded `ORE_LOC` table with no emerald entry, so `'Adds ... ' .. ORE_LOC['emerald']` would concatenate `nil` and crash at load. The registry already carries `name`, so switch to `r.name` and delete the duplicate table.

- [ ] **Step 1: Delete the `ORE_LOC` table**

Remove these lines (15–23):

```lua
-- Display metadata for each ore (name shown on the pack card's tooltip).
local ORE_LOC = {
    wood        = 'Wood',
    cobblestone = 'Cobblestone',
    coal        = 'Coal',
    iron        = 'Iron',
    gold        = 'Gold',
    diamond     = 'Diamond',
}

```

- [ ] **Step 2: Use `r.name` in the registration loop**

Change the loop body so the name comes from the registry entry. The loop becomes:

```lua
for _, r in ipairs(PB_UTIL.RESOURCES) do
    if r.kind == 'gathered' then
        local id = r.id
        local rname = r.name
        SMODS.Consumable {
            key = 'res_' .. id,
            set = 'balacraft_resource',
            atlas = 'bc_resource_cards',
            pos = r.pos,
            cost = 0,
            discovered = true,
            no_collection = true,
            loc_txt = {
                name = rname,
                text = { 'Adds {C:attention}1{} ' .. rname, 'to your resources.' },
            },
            can_use = function(self, card) return true end,
            use = function(self, card, area, copier)
                PB_UTIL.add_resource(id, 1)
            end,
            in_pool = function(self, args) return false end,
        }
    end
end
```

- [ ] **Step 3: Syntax-check + confirm ORE_LOC is gone**

Run:
```bash
luac -p "BalaCraft/content/resources/resource_consumabletype.lua" && echo SYNTAX_OK
grep -c "ORE_LOC" "BalaCraft/content/resources/resource_consumabletype.lua"
```
Expected: `SYNTAX_OK`, then `0` (no remaining `ORE_LOC` references).

- [ ] **Step 4: Commit**

```bash
git add "BalaCraft/content/resources/resource_consumabletype.lua"
git commit -m "fix(resources): name pack consumables from registry (r.name), drop ORE_LOC dupe"
```

---

## Task 4: Hotbar — fit 7 gathered ores on one row

**Files:**
- Modify: `BalaCraft/utilities/resource_ui.lua` (the `PER_ROW` constant, line ~30)

- [ ] **Step 1: Bump `PER_ROW` from 6 to 7**

Change:
```lua
local PER_ROW    = 6     -- columns of resource slots (6 gathered ores fit on one row)
```
to:
```lua
local PER_ROW    = 7     -- columns of resource slots (7 gathered ores fit on one row)
```

- [ ] **Step 2: Syntax-check + confirm the value**

Run:
```bash
luac -p "BalaCraft/utilities/resource_ui.lua" && echo SYNTAX_OK
grep -n "local PER_ROW" "BalaCraft/utilities/resource_ui.lua"
```
Expected: `SYNTAX_OK`, then a line showing `local PER_ROW    = 7`.

- [ ] **Step 3: Commit**

```bash
git add "BalaCraft/utilities/resource_ui.lua"
git commit -m "feat(ui): widen resource hotbar to 7 columns for the new ore"
```

> Note: the row is consumable-area width; fitting a 7th icon may need a minor in-game scale tweak. Flag this in the Task 6 hand-off for the user to eyeball.

---

## Task 5: Wiki — entry, table, and sprite

**Files:**
- Modify: `BalaCraft/assets/gen_wiki_sprites.py` (add emerald to the two resource `crop_grid` calls)
- Modify: `BalaCraft/content/wiki/Resources/Resources.md` (counts + table row)
- Create: `BalaCraft/content/wiki/Resources/Emerald.md`
- Regenerates: `BalaCraft/content/wiki/_img/icon_emerald.png`, `BalaCraft/content/wiki/_img/res_emerald.png`

- [ ] **Step 1: Add emerald to the wiki sprite generator**

In `BalaCraft/assets/gen_wiki_sprites.py`, in the resource **cards** crop call, add the `res_emerald` line:

```python
crop_grid("resource_cards.png", 142, 190, {
    "res_wood": (0, 0), "res_cobblestone": (1, 0), "res_coal": (2, 0),
    "res_iron": (0, 1), "res_gold": (1, 1), "res_diamond": (2, 1),
    "res_sticks": (0, 2), "res_emerald": (1, 2),
})
```

And in the resource **icons** crop call, add the `icon_emerald` line:

```python
crop_grid("resource_icons.png", 68, 68, {
    "icon_wood": (0, 0), "icon_cobblestone": (1, 0), "icon_coal": (2, 0),
    "icon_iron": (0, 1), "icon_gold": (1, 1), "icon_diamond": (2, 1),
    "icon_sticks": (0, 2), "icon_emerald": (1, 2),
}, scale=2)
```

- [ ] **Step 2: Generate the wiki sprites**

Run (from the `Mods/` dir; this script is location-independent but reads `BalaCraft/assets/2x/`, so Task 2 must be done first):
```bash
python3 BalaCraft/assets/gen_wiki_sprites.py
```
Expected: output includes `crop icon_emerald` and `crop res_emerald`.

- [ ] **Step 3: Verify the wiki sprite was written**

Run:
```bash
python3 -c "
from PIL import Image
im = Image.open('BalaCraft/content/wiki/_img/icon_emerald.png').convert('RGBA')
px = [im.getpixel((x, y)) for x in range(im.width) for y in range(im.height)]
assert any(g > 120 and g > r + 30 and g > b + 30 for (r, g, b, a) in px), 'icon_emerald not green'
print('icon_emerald.png OK', im.size)
"
ls "BalaCraft/content/wiki/_img/res_emerald.png"
```
Expected: `icon_emerald.png OK ...` and the `res_emerald.png` path listed.

- [ ] **Step 4: Update `Resources.md` header counts**

In `BalaCraft/content/wiki/Resources/Resources.md`:

Change the first line:
```
Implemented: 7 (6 ores + Sticks)
```
to:
```
Implemented: 8 (7 ores + Sticks)
```

Change the "two kinds" bullet:
```
- **Gathered ores** (6) — dropped by beating blinds and found in [[Booster Packs|Loot Chests]]. Always visible in the hotbar (greyed out at 0).
```
to:
```
- **Gathered ores** (7) — dropped by beating blinds and found in [[Booster Packs|Loot Chests]]. Always visible in the hotbar (greyed out at 0).
```

- [ ] **Step 5: Add the emerald row to the resource table**

In the same file, add an Emerald row to the resource table immediately after the Diamond row:

```
| ![[icon_diamond.png\|24]] [[Diamond]] | 3 | gathered | Diamond tools |
| ![[icon_emerald.png\|24]] [[Emerald]] | 2 | gathered | Villager trading — *coming soon* |
| ![[icon_sticks.png\|24]] [[Sticks]] | — | crafted | Handle for every tool & [[Torch]] |
```

(Only the Emerald line is new; the Diamond and Sticks lines show placement.)

- [ ] **Step 6: Create the Emerald wiki entry**

Create `BalaCraft/content/wiki/Resources/Emerald.md` (no H1 title, per wiki conventions):

```markdown
![[res_emerald.png|140]]

**Emerald** is a tier-2 [[Resources|gathered ore]]. Like Iron and Gold, it drops from boss blinds (ante 3–5) and turns up in [[Booster Packs|Loot Chests]] at tier-2 frequency, and it always shows in your resource hotbar (greyed out at 0).

Unlike the other ores, Emerald is not a crafting material. It is the currency for **Villager Trading** — spending emeralds to obtain resources and tools you can't buy directly from the shop. *(Villager Trading is coming in a future update; for now emeralds simply accumulate.)*

| Tier | Kind | Main use |
| --- | --- | --- |
| 2 | gathered | Villager trading (*coming soon*) |

## How you get it
- **Boss blinds** at ante 3–5 can drop Emerald (tier-2 roll, shared with [[Iron]] and [[Gold]]).
- **[[Booster Packs|Loot Chests]]** offer it at tier-2 weight.

[[Resources|← Back to Resources]]
```

- [ ] **Step 7: Commit**

```bash
git add "BalaCraft/assets/gen_wiki_sprites.py" \
        "BalaCraft/content/wiki/_img/icon_emerald.png" "BalaCraft/content/wiki/_img/res_emerald.png" \
        "BalaCraft/content/wiki/Resources/Resources.md" "BalaCraft/content/wiki/Resources/Emerald.md"
git commit -m "docs(wiki): add Emerald entry, table row, and sprites"
```

> If `docs/` or wiki paths are blocked by `.gitignore`, re-run the `git add` with `-f` (the repo tracks these dirs via force-add — see the spec commit).

---

## Task 6: Hand-off — in-game verification (USER runs Balatro)

Agents cannot launch Balatro. After Tasks 1–5 are committed, hand the user this checklist:

- [ ] Launch Balatro with BalaCraft enabled; start a run. No load error / crash log (confirms Task 3 fix).
- [ ] Open the resource hotbar: **Emerald** appears greyed at 0, and all **7 gathered ores sit on one row** (confirms Task 1 + Task 4; flag if the row looks too cramped — `PER_ROW`/icon scale may need tuning).
- [ ] Beat a **boss** blind at **ante 3–5** a few times: Emerald can drop, and the **Cash Out** screen shows an "Emerald gathered" row with the **green gem icon** (confirms drops + Task 2 art + generic Cash Out).
- [ ] Open a **Loot Chest** booster a few times: an **Emerald** card can appear, showing the green-gem card art and the "Adds 1 Emerald" tooltip (confirms Task 2 card + Task 3 naming).
- [ ] Spot-check the emerald art at 1x and 2x reads as a green gem in the right cell.

---

## Self-review notes

- **Spec coverage:** registry (T1), art (T2), pack-consumable `ORE_LOC` fix (T3 — spec §4), hotbar `PER_ROW` (T4 — spec §3), wiki entry/table/sprite (T5 — spec §6). Drops/Loot Chests/Cash Out (spec §5) need no code and are exercised in the T6 hand-off. Out-of-scope items (Villager Trading, themed boss drop, biome bias) are intentionally excluded.
- **Atlas index math:** `ICONS` index 7 → `(7 % 3, 7 // 3) = (1, 2)`, matching `pos = { x = 1, y = 2 }`; verified by Task 2 Step 6.
- **Name consistency:** registry `name = 'Emerald'`; pack consumable uses `r.name`; wiki uses `Emerald`. No mismatch.
