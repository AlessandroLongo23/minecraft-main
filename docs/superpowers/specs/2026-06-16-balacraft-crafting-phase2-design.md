# BalaCraft — Crafting Phase 2 (drag-and-drop + shaped matching) — Design Spec

**Date:** 2026-06-16
**Mod:** BalaCraft (`BalaCraft/`, SMODS prefix `balacraft`), Balatro + Steamodded (SMODS) + Lovely
**Status:** Approved for implementation planning
**Builds on:** Crafting Phase 1 (`docs/superpowers/specs/2026-06-16-balacraft-crafting-design.md`, implemented and committed on `feature/resource-type`). Phase 2 replaces the read-only 3×3 preview in the existing Crafting Table modal with an interactive drag-and-drop grid. Everything else from Phase 1 — the modal shell, recipe list, `PB_UTIL.craft`, affordability/slot gating, the recipe registry — is reused unchanged.

---

## 1. Goal

Let the player **hand-build recipes** by dragging resource **tiles** into the 3×3 crafting grid, Minecraft-style. The grid is matched **shaped** (arrangement matters, position-normalized) against the recipe registry; on a match the output slot fills and Craft enables. Placing a tile **reserves** the resource; removing it or closing the modal **returns** it, so experimentation can never lose resources.

## 2. Locked design decisions

| Decision | Choice |
|---|---|
| Input model | **Literal drag of real `Card` objects** (native engine drag, the proven booster-pack-in-overlay pattern). |
| Grid model | **Nine single-slot `CardArea`s** (`card_limit = 1`) laid out 3×3 — gives true 2D placement without fighting the engine's 1D row layout. |
| Tiles | **Real `Card`s** using a lightweight resource-tile center, rendered from the **71×95 card atlas** (`bc_resource_cards`). |
| Palette source | **Infinite source up to count:** one source tile per owned resource with a **count badge**; each drag spawns a fresh single tile and decrements the badge until it hits 0 (then greyed). |
| Remove gesture | **Drag out + right-click:** drag a grid tile back to the palette / outside the grid to return it, AND right-click a grid tile as a quick remove. |
| Reserve / return | Place → `add_resource(id, -1)`; remove (drag-out, right-click, or modal close) → `add_resource(id, +1)`. |
| Matching | **Shaped, position-normalized** — trim empty border rows/cols from both the placed grid and each recipe pattern, then compare cell-by-cell. No mirroring/rotation in v2. Re-run after every place/remove. |
| Sticks card art | **Procedural now** — extend `assets/gen_resources.py` to draw a Sticks 71×95 card (so every craftable ingredient has card art). |
| Auto-fill | Clicking a recipe in the left list still works — it now **spawns the pattern's tiles** into the correct cells (same reserve path), instead of drawing a static preview. |
| Out of scope (roadmap) | The `I` inventory screen (reuses this modal); recipe-book discovery/locking; rotation/mirror matching; tool tiers beyond the current set; tile art polish beyond placeholders. |

## 3. Why real Cards (feasibility, established)

Investigation of the Balatro engine dump confirmed:
- Cards are draggable by default (`card.states.drag.can = true`; `card.lua:20`). Drag is initiated/processed generically by `G.CONTROLLER` (`controller.lua:321-329`, `moveable.lua:215-246`).
- **A `CardArea` of `Card`s renders and stays interactive INSIDE a `G.FUNCS.overlay_menu`** — the booster-pack opening screen does exactly this (`G.pack_cards` embedded as `{n=G.UIT.O, config={object=G.pack_cards}}`, `UI_definitions.lua:1776-1787`). `under_overlay` (which would disable interaction) is only set for tutorial overlays, not `overlay_menu` (`game.lua:2976`). So tiles in our modal will drag.

**The one non-native piece** (and the central new work): base-game drag only **reorders within a single area** (areas sort cards by x-position on release; `cardarea.lua:484+`). Dragging a card from the palette **into a specific empty grid cell** is not a base-game interaction. Phase 2 implements a **custom release handler** that, on cursor-up, finds which cell-area the cursor overlaps and emplaces the dragged tile there (or returns it if dropped outside any cell). This is the biggest implementation risk and is isolated to one module.

## 4. Components

### 4.1 Resource-tile card center (`content/resources/resource_tile.lua`)
A minimal card representation for a resource, so a resource can exist as a draggable `Card`. Two viable shapes (decide in the plan, prefer the simpler):
- **One parameterized center** (e.g. a single `SMODS` object or a base center) whose sprite is set per-resource from `bc_resource_cards` at the resource's `pos`, with the tile's resource id stored on the card (e.g. `card.ability.resource_id` or a dedicated field).
- The center is **inert**: no `calculate`, never enters a real game area (jokers/consumeables/hand), never appears in collection/shop/packs. It exists only inside the crafting modal's areas.

Tiles must carry their **resource id** so the grid reader can reconstruct the 3×3 of ids for matching.

### 4.2 Crafting grid + palette (`utilities/crafting_grid.lua`)
Owns the interactive state while the modal is open:
- **`PB_UTIL.craft_cells`** — a 3×3 (row-major) of single-slot `CardArea`s (`card_limit = 1`, configured to accept a dropped tile). Created on modal open, destroyed on close.
- **`PB_UTIL.craft_palette`** — the source row: for each resource with `count > 0`, a **source tile** (a non-draggable display card or a UIT node) showing the resource icon/card + a live count badge. Dragging from a source spawns a new tile `Card` (see spawn).
- **Spawn:** dragging from a palette source creates a fresh single-unit tile `Card` for that resource, calls `add_resource(id, -1)`, and hands the new card to the controller as the drag target so the drag continues seamlessly into the grid.
- **Release handler (the crux):** on cursor-up while dragging a tile, determine the cell-area whose on-screen bounds contain the cursor. If found and empty → emplace the tile there; if that cell is occupied → return the existing tile to the palette (`add_resource(occupant_id, +1)`, destroy it) and place the new one (swap); if no cell (dropped on palette or outside) → return the dragged tile (`add_resource(id, +1)`, destroy it). After any resolution, re-run matching.
- **Right-click remove:** right-clicking a tile that sits in a grid cell returns it (`add_resource(id, +1)`, destroy, re-match).
- **Cleanup on close:** when the modal closes (Craft, Esc, or any exit), every tile still in a cell or mid-drag is returned (`add_resource(id, +1)`) and all tile cards + the nine cell-areas are destroyed. This is the safety net guaranteeing no resource is ever lost.

### 4.3 Shaped matcher (`utilities/crafting_match.lua`)
Pure logic, no UI — easy to reason about:
- **`PB_UTIL.read_grid()`** → a 3×3 (row-major) table of resource ids or `false`, read from `PB_UTIL.craft_cells` (each cell-area's single card's resource id, or `false` if empty).
- **`PB_UTIL.normalize(grid)`** → trims fully-empty leading/trailing rows and columns, returning the tight bounding sub-grid (still row-major, `false` for gaps inside the bbox). Empty grid → empty result.
- **`PB_UTIL.match_grid(grid)`** → for each recipe in `PB_UTIL.RECIPES`, normalize its `pattern` and compare cell-by-cell against the normalized placed grid (same dims + same id in every cell). Return the matched recipe or `nil`. Recipe-pattern normalization can be memoized once at load.

### 4.4 Modal integration (`utilities/crafting_ui.lua`, modified)
- Replace the read-only `pattern_preview` with the live grid: render the nine cell-areas (as `{n=G.UIT.O, config={object=cell_area}}` nodes) in a 3×3, plus the palette row, inside the existing right/bottom layout.
- The **output slot** shows `match_grid(read_grid())`'s result; **Craft** enables only when a recipe matches AND (for joker outputs) a joker slot is free.
- **Craft** consumes the placed (already-reserved) tiles — destroy them WITHOUT returning (they're spent) — and runs the existing `PB_UTIL.craft(recipe)` produce path. Because ingredients were reserved on placement, Craft must **not** double-spend: see §5.
- **Auto-fill** (recipe-row click): spawns the recipe's pattern tiles into the matching cells via the normal spawn/reserve path (only if affordable; otherwise the row stays greyed as in Phase 1). Clears any currently-placed tiles first (returning them).

## 5. Reserve/produce accounting (avoid double-spend)

Phase 1's `PB_UTIL.craft(recipe)` **spends ingredients itself** (`add_resource(id, -n)`) then produces. In Phase 2 the ingredients are **already reserved** on the grid. To avoid spending twice, Phase 2 Craft does:
1. Verify `match_grid` returns the recipe and (for jokers) a slot is free.
2. **Destroy the placed tiles without returning them** (they are the spent ingredients — the reserve already debited the counts).
3. Produce the output directly: resource → `add_resource(out.id, out.amount)`; joker → `joker_add(out.id)`; then `play_sound('timpani', 0.8)`.

I.e. Phase 2 Craft reuses `PB_UTIL.craft`'s **produce** half but **not** its spend half. Cleanest implementation: factor a `PB_UTIL.produce_output(recipe)` helper out of Phase 1's `craft` (the resource/joker branch + sound), call it from both — Phase 1 `craft` keeps `spend → produce_output`; Phase 2 grid-craft does `consume placed tiles → produce_output`. `PB_UTIL.can_craft` (afford + slot + center-exists) still guards the Phase 1 click path; the grid path guards on `match_grid` + slot/center checks (afford is implicit — the tiles are already reserved).

## 6. Data flow (one place→match→craft cycle)

1. Player drags a Wood source → spawn Wood tile, `add_resource('wood', -1)`, drag continues.
2. Cursor-up over cell (1,2) → release handler emplaces the tile in `craft_cells[1][2]`.
3. `read_grid()` → 3×3 of ids; `normalize` → tight bbox; `match_grid` → recipe or nil.
4. Output slot + Craft button refresh from the match.
5. Player clicks Craft (enabled) → destroy placed tiles (no return), `produce_output(recipe)`.
6. Modal close → any still-placed tiles returned; cells + tiles destroyed.

## 7. Architecture / files

**New files**
| File | Responsibility |
|---|---|
| `content/resources/resource_tile.lua` | the inert resource-tile card center(s); tiles carry their resource id |
| `utilities/crafting_grid.lua` | nine cell-areas + palette, tile spawn/destroy, the custom drop-release + right-click handlers, reserve/return, cleanup-on-close |
| `utilities/crafting_match.lua` | `read_grid` / `normalize` / `match_grid` (pure shaped-matching logic) |

**Edited files**
| File | Change |
|---|---|
| `utilities/crafting_ui.lua` | swap read-only preview → live grid + palette; output from `match_grid`; grid-craft path; auto-fill spawns tiles |
| `utilities/crafting.lua` | factor out `PB_UTIL.produce_output(recipe)`; reused by both craft paths |
| `assets/gen_resources.py` | draw a Sticks 71×95 card; grow the card sheet (3×2 → 4×2) and regenerate 1×/2× |
| `content/resources/registry.lua` | give `sticks` a card-sheet `pos` (it currently has only an icon `pos`) |
| `utilities/definitions.lua` | add `resource_tile` to `ENABLED_RESOURCES` (load the tile center) |
| `main.lua` | load `utilities/crafting_grid.lua` + `utilities/crafting_match.lua` under `resources_enabled` |

**Reused unchanged:** the Phase 1 modal shell, recipe list + greyed/locked gating, `PB_UTIL.RECIPES` + `recipe_ingredients` + `recipe_by_key`, `PB_UTIL.can_craft`/`has_joker_room`, `joker_add`, `add_resource` as the single spend/produce funnel, `G.FUNCS.overlay_menu` + the cursor-layer-leak guard.

## 8. Risks / tunables (not blocking)

- **Custom drop-release detection** is the central risk; it's isolated in `crafting_grid.lua` and must be tuned in-game. Fallback if true drop-into-cell proves too fragile: keep Phase 1 click-to-fill as the primary and treat drag as enhancement (the modal still works without drag).
- **Tile/cell sizing** in the overlay needs in-game tuning (cards are 71×95; the 3×3 + palette must fit the modal). Visual-tuning step, like the Phase 1 modal.
- **Cleanup correctness** (no orphaned tile cards, no lost/duplicated resources across open/close/Craft/Esc) is the key thing to regression-test in-game.
- Tool/recipe balance and tile art remain placeholder (as in Phase 1).

## 9. Verification model

Same as Phases past: no automated harness (mod runs only in Balatro; the human runs in-game checks). Static checks: balanced Lua, referenced globals exist, `match`/`normalize` reasoned through by hand on sample grids. The `crafting_match.lua` logic is pure and should be exercised with console calls (`PB_UTIL.match_grid` on hand-built tables) before trusting the UI. In-game: drag→place→match→craft, drag-out/right-click return, modal-close return, auto-fill, and a save/quit/continue + new-run resource-integrity pass.
