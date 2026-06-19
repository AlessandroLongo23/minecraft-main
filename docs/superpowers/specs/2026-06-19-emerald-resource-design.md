# Emerald resource — design

**Date:** 2026-06-19
**Status:** Approved (brainstorm) — ready for implementation plan
**Scope:** Add **Emerald** as a gathered, tier-2 ore, fully wired into the existing resource
subsystem (drops, Loot Chest packs, hotbar, Cash Out summary, wiki + art).

## Goal

Ship Emerald as a working, collectable, displayed resource that accumulates during a run,
ready to be spent later. Emerald's **use** — a Villager Trading system to exchange emeralds
for resources/tools — is deliberately a **separate, follow-up spec** and is out of scope here.

This first slice is a near-mechanical clone of the existing ores: the resource subsystem
already discovers gathered ores generically (it iterates `PB_UTIL.RESOURCES` and filters
`kind == 'gathered'`), so most of the plumbing requires no code change.

## Decisions (locked during brainstorm)

- **Use:** Villager trading currency — but that mechanic is a *future* spec. Here, emerald is
  a gathered ore with no recipe/use yet (it piles up until trading ships).
- **Kind / tier:** `gathered`, **tier 2** (joins Iron and Gold). More available than tier-3
  Diamond, which suits a currency the player will actually spend. Rarity is balance-tunable
  later via the existing tier tables.
- **Art:** A faithful Minecraft emerald — a **dedicated green beveled-gem shape** (not just a
  recolored diamond).
- **Atlas:** Uses the free cell **(1, 2)** on the existing 3×3 sheets. No atlas resize; cell
  **(2, 2)** stays free for a future 9th resource.

## Changes

### 1. Registry — `content/resources/registry.lua`
Add one entry (after Diamond reads naturally as a gem):

```lua
{ id = 'emerald', name = 'Emerald', kind = 'gathered', tier = 2, pos = { x = 1, y = 2 } },
```

No other code in this file changes. Because counts are seeded by looping
`PB_UTIL.RESOURCES` in the `Game:init_game_object` wrapper (`utilities/resources.lua`),
emerald's per-run count auto-seeds to 0, auto-saves, and auto-resets — **no save/load code.**

### 2. Art — `assets/gen_resources.py`
- Add `EMERALD_PAL = (base, highlight, shadow, outline)` in green.
- Add an `emerald_gem()` renderer with its **own** `EMERALD_SHAPE` (blockier/wider than the
  cyan `DIAMOND_SHAPE`, matching the MC emerald item), using the shared `_render(...)` helper.
- Append `("emerald", emerald_gem())` to the `ICONS` list **after** `("sticks", sticks())`,
  so its generation index is **7 → cell (1, 2)**. This keeps every existing cell position fixed
  (wood..diamond at 0..5, sticks at 6/(0,2)).
- Add `"emerald": 2` to the `tiers` dict in `build_cards`.

Regenerate both resolutions:
```bash
python assets/gen_resources.py   # 1x icons + cards
python assets/utils.py           # 2x sheets
```

Both atlases (`bc_resource_icons` 34×34 and `bc_resource_cards` 71×95) are generated from the
same `ICONS` index → position mapping, so the registry `pos = {1,2}` is correct for both the
icon (hotbar/tile/inventory/cashout) and the card (Loot Chest pack) lookups.

### 3. Hotbar — `utilities/resource_ui.lua`
Bump `PER_ROW` from `6` to `7` so all seven gathered ores stay on one row (the existing comment
already frames the row as "gathered ores fit on one row"). The row is consumable-area width, so
fitting a 7th icon **may need a small in-game width/scale tweak** — only the user can verify this
in-game. Update the inline comment to say 7.

### 4. Drops / Loot Chests / Cash Out — **no code changes**
- `random_ore_of_tier(2, ...)` (`utilities/resources.lua`) already builds its pool by filtering
  `kind == 'gathered' and r.tier == tier`, so emerald joins the tier-2 roll automatically.
  Result: emerald rolls from **boss** drops at **ante 3–5** (tier 2 is the boss `max_tier` then),
  alongside Iron and Gold.
- Loot Chest packs (`utilities/functions.lua`, `RESPACK_TIER_WEIGHT`) sample distinct gathered
  ores; emerald gets `[2] = 2` weight automatically.
- The Cash Out summary (`utilities/cashout_ui.lua`) renders each `last_drop` entry generically
  using the resource's icon at `r.pos`, so emerald drops show up with no change.

### 5. Wiki — `content/wiki/Resources/`
- `Resources.md`: bump header `Implemented: 7` → `8`; change "Gathered ores **(6)**" → **(7)**;
  add an emerald row to the resource table:
  `| ![[icon_emerald.png\|24]] [[Emerald]] | 2 | gathered | Villager trading — *coming soon* |`
- Add `Emerald.md` entry following the wiki conventions (folder-per-category, no H1, brief
  description, link forward to the future Villager Trading page).
- Generate `_img/icon_emerald.png` via `assets/gen_wiki_sprites.py` (per wiki sprite convention).

## Out of scope (next spec)
- The Villager Trading UI, trade table (which ores/tools cost how many emeralds), and any
  "enchanted" tool variants.
- A themed boss emerald drop in `PB_UTIL.BLIND_DROPS` (couples to the New Bosses work).
- Biome bias toward a mountains/hills biome in `utilities/biomes.lua` (only if that feature is
  active; `biome_ore_weight` is inert otherwise).

## Verification (hand-off — agents cannot run Balatro)
After implementation, the user verifies in-game:
1. Emerald appears in the hotbar (greyed at 0), with all 7 gathered ores on one row.
2. Beating a boss at ante 3–5 can drop emerald; the Cash Out summary shows an "Emerald gathered"
   row with the correct icon.
3. Loot Chests can offer an emerald card.
4. The emerald icon/card art renders correctly (green gem, right cell) at 1x and 2x.
