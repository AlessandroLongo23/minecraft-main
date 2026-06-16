# Minekreift — Crafting System (v1) — Design Spec

**Date:** 2026-06-16
**Mod:** Minekreift (`minecraft-main`), Balatro + Steamodded (SMODS) + Lovely
**Status:** Approved for implementation planning
**Builds on:** the Resource content type (`docs/superpowers/specs/2026-06-15-minekreift-resource-type-design.md`, implemented on `feature/resource-type`). Crafting consumes the resource counts that system already maintains.

---

## 1. Goal

Add a Minecraft-style **crafting system**: a mid-blind **Crafting Table** modal where the player turns resources into useful things via **shaped 3×3 recipes**. Crafting is a real **tree** — recipes can output either a **crafted resource** (an intermediate, e.g. Sticks) or a **tool-Joker** — and the whole thing is **data-driven and expandable** (new resources/recipes/tiers are just data).

## 2. Locked design decisions

| Decision | Choice |
|---|---|
| Recipe matching | **Shaped** — the 3×3 arrangement matters, position-normalized (pattern can sit anywhere in the grid; empty border rows/cols trimmed). No mirroring in v1. |
| Outputs | **Resources OR Jokers.** A recipe produces either a crafted resource (count++) or a tool-Joker (into the joker row). |
| Tools | Exist as normal `SMODS.Joker`s (reuse the joker system). |
| Access | **Mid-blind** (during play), via a small **"Crafting Table"** prompt under the resource hotbar. NOT shop-gated. |
| Modal | Centered (deck-preview style): **recipes list left**, **3×3 grid + output slot + Craft button right**, **resource palette along the bottom**. |
| Recipe-click | Clicking a recipe **auto-fills** the grid with its pattern; **manual drag** of tiles is also supported and the game matches the built shape. |
| Resource kinds | **Gathered** (the 6 ores) and **Crafted** (intermediates like Sticks, only obtainable by crafting; never in drop/pack pools). |
| v1 intermediate | **Sticks** only (one intermediate, to prove a 2-tier tree). |
| Expandability | Recipe + resource registries are pure data; matching/UI code is content-agnostic. |
| Build phasing | **Phase 1**: modal + recipe book + click-to-craft + tool-jokers + slot gating (playable loop). **Phase 2**: manual drag-and-drop into cells + shaped matching of hand-placed tiles. |
| Out of scope (roadmap) | Inventory screen via the `I` key (reuse this modal pattern later); planks/ingots and other tiers; the other wiki tools (axe/hoe/fishing rod); diamond-tier tools; ore-mining-from-cards (separate mechanic). |

## 3. Resource model changes (extends the existing system)

The existing resource type stores integer counts at `G.GAME.minecraft.resources[id]` (seeded by an `init_game_object` wrapper) and mutates them only through `PB_UTIL.add_resource(id, amount)` (clamps ≥ 0). Crafting reuses this verbatim: **spend = `add_resource(id, -n)`**, **produce-resource = `add_resource(id, +n)`**.

`PB_UTIL.RESOURCES` entries gain a **`kind`** field:
```lua
{ id='wood',        kind='gathered', tier=1, pos={x=0,y=0} },
...
{ id='sticks',      kind='crafted',           pos={x=<n>,y=<n>} },  -- new
```
- **Gathered** (`kind='gathered'`): the 6 ores; eligible for drops/packs.
- **Crafted** (`kind='crafted'`): Sticks; **excluded** from all drop/pack pools.

**Drop-pool guard:** `random_ore_of_tier` / `grant_blind_drop` (Task 4 of the resource feature) must only consider `kind=='gathered'` resources, so crafted intermediates can never drop. (Sticks has no `tier`, so it's already excluded — but filter on `kind` explicitly for safety/clarity.)

**Init seeding:** `init_game_object` already loops `PB_UTIL.RESOURCES` seeding each id to 0, so Sticks starts at 0 automatically.

**Art:** crafted resources need only the **34×34 inventory icon** (never a 71×95 pack card — they're never in packs). Extend `assets/gen_resources.py` to draw a Sticks tile. To **keep the 6 existing ore icon positions stable**, grow the icon sheet from 3×2 to **3×3** (9 cells: the 6 ores stay in rows 0–1 at their current `pos`, Sticks goes at `pos={x=0,y=2}`, the last two cells stay empty). The **card sheet stays 3×2 (6 ores) unchanged**. So `sticks` carries an icon-sheet `pos` but has **no card-sheet cell** — the booster/consumable code never touches crafted resources, so that asymmetry is fine.

**Hotbar panel:** the always-on hotbar continues to show the **6 gathered ores** (greyed at 0). **Crafted resources appear in the hotbar only when owned (count > 0)** — so the bar isn't cluttered with intermediates you haven't made. The crafting modal's bottom **palette shows all resources** (gathered + crafted) as draggable ingredients.

## 4. Recipe registry (data-driven, tree-shaped)

`content/resources/recipes.lua` defines `PB_UTIL.RECIPES`, a list of entries:
```lua
{
  key = 'stone_pickaxe',
  output = { type = 'joker', id = 'j_minecraft_stone_pickaxe', amount = 1 },
  -- 3x3 pattern, row-major; nil = empty cell, otherwise a resource id.
  pattern = {
    { 'cobblestone', 'cobblestone', 'cobblestone' },
    { nil,           'sticks',      nil           },
    { nil,           'sticks',      nil           },
  },
}
```
- `output.type` is `'resource'` or `'joker'`. For `'resource'`, crafting does `add_resource(output.id, output.amount)`. For `'joker'`, it creates the joker (`SMODS.create_card` → `G.jokers:emplace`) — the existing `joker_add` helper already does this.
- `ingredients` (the multiset needed) are **derived** from `pattern` (count non-nil cells by id) — single source of truth, no duplication.
- **Normalization** (matching helper): trim all-empty leading/trailing rows and columns from both the player's placed grid and each recipe `pattern`, then compare cell-by-cell. This lets a recipe be built anywhere in the 3×3.

### v1 recipe set
| key | output | pattern (row-major; `·` = empty) |
|---|---|---|
| `sticks` | resource: Sticks ×2 | `· W ·` / `· W ·` / `· · ·`  (two Wood stacked) |
| `stone_pickaxe` | joker: Stone Pickaxe | `Cob Cob Cob` / `· Stick ·` / `· Stick ·` |
| `iron_sword` | joker: Iron Sword | `· Iron ·` / `· Iron ·` / `· Stick ·` |
| `iron_shovel` | joker: Iron Shovel | `· Iron ·` / `· Stick ·` / `· Stick ·` |

### v1 tool-Joker effects (placeholder balance — tunable)
| Joker | Effect |
|---|---|
| **Stone Pickaxe** | +1 to every resource drop (boosts gathering). |
| **Iron Sword** | ×2 Mult on Boss Blinds. |
| **Iron Shovel** | +$3 each time you defeat a blind. |

Effects are deliberately simple/placeholder; refine in-game. Tools are regular `SMODS.Joker`s (keys `j_minecraft_<tool>`), using the resource card atlas or their own art.

## 5. The Crafting Table modal

### Access
A small clickable **"🪓 Crafting Table"** prompt rendered just under the resource hotbar (same `Game:update`-driven, state-gated approach as the hotbar panel). Visible in the same run states as the hotbar. Clicking opens the modal.

### Modal layout (centered overlay, via `G.FUNCS.overlay_menu`)
- **Left:** recipe list. Each row = output icon + name + ingredient summary. **Greyed/locked** when the player can't afford it, or (for joker outputs) when joker slots are full.
- **Right:** the **3×3 grid**, an **output slot** (shows the matched recipe's result), and a **Craft** button.
- **Bottom:** the resource **palette** — every resource (gathered + crafted) with its count, the source for drag (Phase 2) and the display of what you have.

### Interaction
- **Phase 1 (click-to-craft):** click a recipe in the left list → the grid displays its pattern and the output slot shows the result → **Craft** (enabled only if affordable and, for joker outputs, a slot is free) → spend ingredients via `add_resource(id, -n)`, then produce the output (resource `add_resource(+n)` or joker `emplace`). No reservation needed.
- **Phase 2 (manual drag):** drag a resource tile from the palette into a grid cell. Placing **reserves** one unit (`add_resource(id,-1)`, palette count drops); removing a tile or closing the modal **returns** it (`add_resource(id,+1)`). After each change, the matcher normalizes the placed grid and compares against all recipes; on a match the output slot fills and Craft enables. Craft consumes the placed tiles (already reserved) and produces the output. Click-to-autofill = the engine places the tiles for you (same reservation path).

### Slot gating
Joker-output recipes require an open joker slot (`#G.jokers.cards < G.jokers.config.card_limit`). If full, those recipes are locked and Craft is disabled with a "no joker room" note. Resource-output recipes (Sticks) have no slot requirement.

## 6. Architecture / files

**New files**
| File | Responsibility |
|---|---|
| `content/resources/recipes.lua` | `PB_UTIL.RECIPES` registry (patterns + outputs); derive ingredient multisets |
| `content/jokers/stone_pickaxe.lua`, `iron_sword.lua`, `iron_shovel.lua` | the 3 tool-Jokers (`SMODS.Joker`) with their effects |
| `utilities/crafting.lua` | normalization + shaped matching; affordability + slot checks; `PB_UTIL.craft(recipe)` (spend → produce); resource-vs-joker output handling |
| `utilities/crafting_ui.lua` | the Crafting Table button (under the hotbar) + the modal (recipe list, grid, output, Craft, palette). Phase 2 adds the draggable grid. |

**Edited files**
| File | Change |
|---|---|
| `content/resources/registry.lua` | add `kind` to each ore; add the **Sticks** crafted resource; grow the icon atlas registration |
| `assets/gen_resources.py` | draw a Sticks icon; regenerate `resource_icons.png` (7 cells) + 2× |
| `utilities/resources.lua` | filter drop pools to `kind=='gathered'` |
| `utilities/resource_ui.lua` | show crafted resources in the hotbar only when count > 0 |
| `utilities/definitions.lua` | add `recipes` to `ENABLED_RESOURCES`; add the 3 tool-jokers to `ENABLED_JOKERS` |
| `main.lua` | load `utilities/crafting.lua` + `utilities/crafting_ui.lua` under `resources_enabled` |
| `config.lua`, `utilities/ui.lua` | (optional) a `crafting_enabled` toggle |

**Reused building blocks (already verified for the resource feature):** `G.FUNCS.overlay_menu` for the centered modal; `G.UIT` trees + `ref_table/ref_value` for live counts; `SMODS.create_card` + `area:emplace` for jokers; the `Game:update` wrapper pattern for the button; `PB_UTIL.add_resource` as the spend/produce funnel.

## 7. Build phasing (for the plan)

- **Phase 1 — playable crafting loop (no drag):** Sticks + 3 tools as data; `crafting.lua` craft action + affordability/slot checks; the modal with a recipe list + click-to-fill + output + Craft; the Crafting Table button. Verifiable end-to-end: gather → open table → click Sticks → craft → click Stone Pickaxe → get the Joker.
- **Phase 2 — manual drag + shaped matching:** draggable palette tiles, drop targets in the 3×3, reserve/return on place/remove, normalization + pattern matching of hand-built grids, Craft on match.
- Forward seam: the modal + keybind-open code is written to be reusable by the future **`I` inventory** screen.

## 8. Open / tunable (not blocking)

- Tool effects + recipe yields (Sticks ×2, etc.) are placeholder balance.
- Exact shapes can be tuned for feel; matching is data-driven so changes are just data.
- Whether crafting should be blocked while a hand is being scored (vs any mid-blind moment) — default: allowed in the same run states the hotbar shows; revisit in-game.
- Sticks icon art is procedural placeholder (swappable like the ores).

## 9. Resolved decisions (from brainstorming)

- Shaped matching · tool-Jokers · mid-blind access · modal (recipes left / grid right) · click-autofill + manual drag · Sticks as a craftable resource · data-driven expandable tree · phased build · inventory-via-`I` is roadmap.
