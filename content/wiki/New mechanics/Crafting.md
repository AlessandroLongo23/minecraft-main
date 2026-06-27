*Mechanic*

Crafting turns the [[Resources|ores]] you gather into [[Tools]]. It uses a Minecraft-style **3×3 grid** with **shaped** recipes.

## Opening the table
Click the **Crafting Table** button under the resource hotbar. A centered overlay opens with:
- **Recipes** list (left) — click a recipe to auto-fill it.
- **3×3 grid → output slot + Craft button** (right).
- **Inventory row** (middle) — your owned ores/sticks, draggable into the grid.
- **Back** button (bottom) — closes and refunds any placed tiles.

## How matching works
Recipes are **shaped**, not shapeless: the grid and the recipe are both trimmed to their tight bounding box and compared cell-by-cell. The *shape* matters, but its absolute position in the 3×3 doesn't. There is **no rotation or mirroring**, and empty interior cells must stay empty. The first matching recipe wins.

You can craft a recipe two ways:
- **Click the recipe** — if you can afford it, the tiles auto-fill into the grid.
- **Drag** ores from the inventory row into the grid manually.

A craft only goes through (`can_craft`) when you can **afford** every ingredient, the output exists, and you have a free **slot** if the output is a joker/consumable (no slot → a red "No Card Slots!" warning). Completing a craft also grants [[Experience]].

## Recipes
| Output | Ingredients | Shape |
| --- | --- | --- |
| 2× [[Sticks]] | 2 [[Wood]] | Wood stacked vertically |
| [[Sword]] (×5 materials) | 2 material + 1 Stick | material ×2 over a Stick |
| [[Pickaxe]] (×5 materials) | 3 material + 2 Sticks | material row + 2-Stick handle |
| [[Shovel]] (×5 materials) | 1 material + 2 Sticks | material over a 2-Stick handle |
| [[Torch]] | 1 [[Coal]] + 1 Stick | Coal above a Stick |

The 15 tool recipes come from 3 tools × 5 materials (Wood → Diamond). See each tool's page for its exact grid and per-material stats: [[Sword]], [[Pickaxe]], [[Shovel]], [[Torch]].

[[New mechanics|← Back to mechanics]]
