# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**BalaCraft** — a Minecraft-themed *content mod* for the card-roguelike **Balatro**, written in Lua against **Steamodded (SMODS)** + the **Lovely Injector**. It adds boss blinds, jokers, a deck, a booster, and a custom **Resource** gathering/crafting subsystem. The mod is branded **BalaCraft** throughout — folder, docs, and the SMODS mod prefix in `metadata.json` (**`balacraft`**) — so every content key is `<class>_balacraft_<key>` (e.g. `j_balacraft_stone_pickaxe`). The prefix is hardcoded in `lovely.toml` patches and `BLIND_DROPS`, so changing it would invalidate existing save data.

## Build / test / run

There is **no build, lint, or automated test step** — Balatro mods are interpreted Lua loaded at game launch. The dev loop is:

1. Edit Lua under this directory (it lives in Balatro's `Mods/` folder, so the game loads it in place).
2. Launch Balatro; enable the mod in the Mods menu. Errors surface in Steamodded's in-game console / crash log.
3. **Only the user can run the game** — agents cannot launch Balatro. Hand finished work to the user for in-game verification rather than claiming it's "tested."

**Regenerating resource art** (procedural, deterministic — no committed PSDs):
```bash
python assets/gen_resources.py   # writes assets/1x/resource_icons.png + resource_cards.png
python assets/utils.py           # derives the assets/2x/ sheets
```

**Reference source** (read-only, alongside this mod in `Mods/`): Balatro's Lovely-dumped source at `../lovely/dump/`, and Steamodded itself at `../Steamodded/src/`. Grep these to verify an SMODS/base-game API before relying on it — much of this codebase's correctness depends on matching the real engine behavior (e.g. `Blind:defeat`, `G.FUNCS.overlay_menu`, center registries).

## Loading architecture

Everything is wired through a **toggle → whitelist → folder-load** pipeline; understanding it is the fastest way to be productive:

- **`main.lua`** is the entry point (`metadata.json` → `main_file`). It creates the global `PB_UTIL` namespace, reads `PB_UTIL.config` from `SMODS.current_mod.config`, then loads each category **only if its toggle is on**.
- **`config.lua`** returns the per-category boolean toggles (`blinds_enabled`, `jokers_enabled`, `resources_enabled`, …).
- **`utilities/definitions.lua`** holds the `PB_UTIL.ENABLED_*` arrays — the **whitelist of which content files actually load**. Commented-out entries are intentionally disabled WIP (e.g. unfinished bosses). To ship a new joker/blind/etc., its filename **must** be added to the matching `ENABLED_*` list.
- **`PB_UTIL.register_items(list, folder)`** (`utilities/functions.lua`) loads `content/<folder>/<name>.lua` for each whitelisted name. Each content file is a **self-executing SMODS declaration** (`SMODS.Joker {...}`, `SMODS.Blind {...}`, etc.) — no exports, the side effect *is* the registration.
- **Blinds are special:** loaded via `PB_UTIL.load_blinds` (uses `NFS.load` + `pcall`, and registers the shared `blinds` animation atlas) rather than `register_items`.

**Key naming:** SMODS auto-prefixes every key `<classprefix>_balacraft_<key>`. So joker file key `stone_pickaxe` → center key `j_balacraft_stone_pickaxe`; blind key `creeper` → `bl_balacraft_creeper`. Code that looks centers up (`G.P_CENTERS[...]`) or matches `G.GAME.blind.name` must use the **fully prefixed** form. (For SMODS boss blinds, `G.GAME.blind.name` *is* the prefixed key, because SMODS sets a blind center's name to `self.name or self.key` and these blinds only define `loc_txt.name`.)

**Localization:** strings are defined **inline** as `loc_txt` on each content declaration. `localization/en-us.lua` exists but inline `loc_txt` is the working pattern — follow it for new content.

## Lovely source patches

`lovely.toml` performs **source-level injection** into Balatro's own Lua (pattern-match + payload) for effects that can't be expressed declaratively — currently boss-blind hooks (Drowned forced-discard via `PB_UTIL.drowned_effect`, Husk discard cost) and per-ante skip tracking. These patches reference prefixed blind keys directly (e.g. `G.GAME.blind.name == 'bl_balacraft_drowned'`). When adding a blind whose mechanic needs to alter base-game flow, this is where the hook goes.

## The Resource subsystem (`resources_enabled`)

This is the mod's novel, most intricate feature. Files: `utilities/resources.lua` (state + drops), `utilities/resource_ui.lua` (hotbar panel), `utilities/crafting.lua` (craft logic), and data under `content/resources/` (`registry.lua`, `recipes.lua`, `resource_consumabletype.lua`).

**Hybrid count model — the load-bearing invariant:**
- Counts are plain integers at `G.GAME.balacraft.resources[id]`. They are **the single source of truth**.
- They're seeded by a wrapper around `Game:init_game_object` (each `PB_UTIL.RESOURCES` id → 0). Because they live on `G.GAME` as plain numbers, they are **auto-saved and auto-reset per run** — there is deliberately **no custom save/load code**. Don't add any.
- **Mutate counts only through `PB_UTIL.add_resource(id, amount)`** (clamps ≥ 0; sets `_panel_dirty` on a 0↔non-0 boundary so the hotbar can flip greyed↔active). Crafting spends with `add_resource(id, -n)` and produces with `add_resource(id, +n)`. Never write the table directly.

**Resource kinds (`registry.lua` → `PB_UTIL.RESOURCES`):** each entry has `kind`. `gathered` = the 6 ores (eligible for drops/packs, have both icon + card cells). `crafted` = intermediates like Sticks (craft-only, **excluded from all drop/pack pools**, icon cell only). Code that builds drop/booster/consumable pools must filter `kind == 'gathered'` — adding a `crafted` resource to those loops without the guard caused a past load crash. Two atlases are registered here: `bc_resource_cards` (71×95 pack cards) and `bc_resource_icons` (34×34 panel/inventory icons).

**Drops:** `PB_UTIL.grant_blind_drop(blind)` runs from a wrapper around `Blind:defeat` (wrapped in `pcall`). It grants resources on every blind win — themed overrides per boss via `PB_UTIL.BLIND_DROPS` (keyed by the prefixed blind name), else a tier-roll fallback scaled by ante. Tool-joker effects that modify gathering (Stone Pickaxe `+1`, Iron Shovel `+$3`) are applied **here**, gated on `PB_UTIL.has_joker('j_balacraft_<tool>')`.

**Crafting (`crafting.lua`):** recipes are pure data in `content/resources/recipes.lua` (`PB_UTIL.RECIPES`): each `{ key, name, output = {type, id, amount}, pattern }`, where `pattern` is a 3×3 row-major grid using literal `false` for empty cells (**never `nil`** — `nil` creates array holes; patterns are iterated `for i=1,3 do for j=1,3 do`). Ingredient multisets are *derived* from the pattern (`PB_UTIL.recipe_ingredients`), not duplicated. `output.type` is `'resource'` (→ `add_resource`) or `'joker'` (→ the global `joker_add(key)` helper, which `SMODS.create_card` + `G.jokers:emplace`). `PB_UTIL.can_craft` gates on affordability, joker-room (`#G.jokers.cards < G.jokers.config.card_limit`), and — for joker outputs — the center existing in `G.P_CENTERS` (so ingredients can't be spent on a no-op craft).

**Hotbar UI (`resource_ui.lua`):** a Weak-bonded UIBox below `G.consumeables`, shown/hidden from a `Game:update` wrapper and gated on run state + atlas readiness. Counts are live-bound via UIT `ref_table`/`ref_value`. Gathered ores always show (greyed at 0); crafted resources show only when owned.

## Conventions for new content

- All shared functions/state hang off the global **`PB_UTIL`** table.
- New content file → add it to the matching `PB_UTIL.ENABLED_*` list in `utilities/definitions.lua`, or it won't load.
- Match the existing declaration style of neighboring files in the same `content/<category>/` folder (inline `loc_txt`, `blueprint_compat`/`eternal_compat` flags, `atlas` + `pos`).
- Verify any base-game/SMODS API against the dumps in `../lovely/dump/` and `../Steamodded/src/` before depending on it.

## Planning docs

Design specs and implementation plans live under `docs/superpowers/`. The active feature plan is `docs/superpowers/plans/2026-06-16-crafting-phase1.md` (with its spec `docs/superpowers/specs/2026-06-16-balacraft-crafting-design.md`) — the crafting system is mid-implementation; check these before extending it.
