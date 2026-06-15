# Minekreift — "Resource" Content Type (v1 slice) — Design Spec

**Date:** 2026-06-15
**Mod:** Minekreift (`minecraft-main`), Balatro + Steamodded (SMODS) + Lovely
**Status:** Approved for implementation planning
**Scope of this spec:** the *Resource type itself*. The 3×3 crafting grid, recipes, ore-mining, and enchanting are **explicitly out of scope** here and get their own specs later.

---

## 1. Goal

Add a new content category the user calls a **Resource** (Minecraft ore you gather now, craft with later). This slice delivers a complete, testable loop: **gather ores → see them accumulate in an inventory → they persist across the run.** Crafting/consuming them comes in a later mechanic.

## 2. Locked design decisions

| Decision | Choice | Rationale |
|---|---|---|
| What a resource *is* | **Hybrid**: counts/stacks are the single source of truth; draggable tiles are deferred to the later crafting grid | User's explicit model; counts are clean to store and to spend later |
| Storage | Plain integers on `G.GAME.minecraft.resources`, seeded by a Lua wrapper of `Game:init_game_object` | Auto-saved, auto-restored, auto-reset on new run — zero custom save/load |
| Resource set (v1) | 6 ores in 3 tiers: **Wood, Cobblestone, Coal** (t1) · **Iron, Gold** (t2) · **Diamond** (t3) | Lean, balanceable, enough variety for crafting later |
| Inventory display | A **self-owned UIBox** bonded `Weak` to `G.consumeables`, below it; **always shows all 6 ores** (grayed when count = 0) | No HUD edit ⇒ no cross-mod conflict; fixed-size panel ⇒ only rebinds, never rebuilds |
| Gathering (v1) | (a) **boss/blind defeat drops**, (b) **resource booster pack** | Passive trickle and ore-mining are out of this slice |
| Pack "pick one" flow | **Hidden ore consumables** spawned into the pack; picking runs the base "Use" path | Reuses verified base mechanism; no custom selection UI; nothing ever lands in `G.consumeables` |
| Out of scope | 3×3 crafting grid, recipes, ore-mining, enchanting, crops/mob-drops/food | Each is its own future slice |

## 3. Architecture overview

Spine = **Approach A** (lightweight data registry; counts are truth). One borrow from **Approach B** (a *hidden* `SMODS.ConsumableType` + 6 hidden ore `SMODS.Consumable`s) used **only** to populate the booster pack. **Approach C** (resources as real stack-cards) was rejected: it makes cards the source of truth (contradicting the user's model), risks count/card desync, and needs fragile nested-CardArea save/load — all for no benefit until the later grid exists.

All evidence below was verified against the actual Steamodded/Balatro source and reference mods (Ortalab, Cryptid, Pokermon) during the design panel.

### 3.1 Persisted state shape

```lua
-- utilities/resources.lua — Lua wrapper of Game:init_game_object (NOT a lovely patch).
local _igo = Game.init_game_object
function Game:init_game_object()
    local t = _igo(self)
    t.minecraft = t.minecraft or {}
    t.minecraft.resources = {
        minecraft_wood        = 0,
        minecraft_cobblestone = 0,
        minecraft_coal        = 0,
        minecraft_iron        = 0,
        minecraft_gold        = 0,
        minecraft_diamond     = 0,
    }
    return t
end
```

- `G.GAME.minecraft.resources` is a **flat table of integers only** → trivially serializable, saved/restored automatically with `G.GAME`, re-seeded to zeros on each new run (because `init_game_object` runs fresh per run).
- Keys are mod-prefixed and identical to `PB_UTIL.RESOURCES[i].key`, so registry/UI/booster/drops all index the same key.
- Defensive guard everywhere it's read/written: `G.GAME.minecraft = G.GAME.minecraft or {}; G.GAME.minecraft.resources = G.GAME.minecraft.resources or {}`.

### 3.2 Registry (design data, not persisted)

```lua
-- content/resources/registry.lua
-- pos = shared 3x2 grid index, used the SAME in BOTH atlases below.
PB_UTIL.RESOURCES = {
  { key='minecraft_wood',        tier=1, pos={x=0,y=0} },
  { key='minecraft_cobblestone', tier=1, pos={x=1,y=0} },
  { key='minecraft_coal',        tier=1, pos={x=2,y=0} },
  { key='minecraft_iron',        tier=2, pos={x=0,y=1} },
  { key='minecraft_gold',        tier=2, pos={x=1,y=1} },
  { key='minecraft_diamond',     tier=3, pos={x=2,y=1} },
}
-- Two atlases (see §11 Art), both laid out on the same 3x2 grid so one `pos` indexes both:
-- SMODS.Atlas{ key='minecraft_resource_cards', path='resource_cards.png', px=71, py=95 } -- pack cards
-- SMODS.Atlas{ key='minecraft_resource_icons', path='resource_icons.png', px=34, py=34 } -- hotbar panel
```
Single source of truth for names/tiers/sprite positions; consumed by the panel, the booster, and the drop logic. `tier` is metadata only (not a sprite coordinate). Display names come from localization keyed by `.key` (house style).

### 3.3 Mutation funnel

```lua
PB_UTIL.add_resource(key, amount)   -- coerces to number, clamps >= 0, writes count, juices panel cell
PB_UTIL.get_resource_count(key)
PB_UTIL.set_resource(key, amount)
```
`assert(type(amount) == 'number')` keeps the state strictly serializable.

## 4. Inventory panel

- A **self-owned UIBox** (global handle e.g. `G.minecraft_resources_panel`), built from `PB_UTIL.RESOURCES`: a fixed **hotbar-style** grid of all 6 ore slots (square cells, e.g. two rows of three), each cell = a **34×34 block icon** from the `minecraft_resource_icons` atlas + a count text node. (Note: `pos={x,y}` is the sprite's location **in the atlas sheet**; the panel's on-screen arrangement is independent and cosmetic.)
- Count text is **dynamically bound**: `{ n=G.UIT.T, config={ ref_table=G.GAME.minecraft.resources, ref_value='minecraft_wood', ... } }`. This is the base game's standard dynamic-text idiom (also used by the booster's pack-choices counter), so counts update live with **no per-frame UIBox rebuild and no custom draw loop**.
- Positioned with `config={ align='cm', offset={x=0,y=<below>}, major=G.consumeables, bond='Weak' }` — same pattern the base game uses to hang the booster pack off `G.hand`. The `Weak` bond makes the panel track `G.consumeables.T` wherever it lives, so no absolute coordinates.
- **Always shows all 6 ores**; ones with count 0 render **grayed/dimmed**. Because the slot set never changes, the panel only ever **rebinds** counts (never rebuilds for count changes).
- **Show/hide** via a `Game:update` Lua wrapper (like Ortalab/Cryptid): create the panel once when entering a run state and `G.consumeables` exists; hide/remove it outside run states by checking `G.STATE`. Default visible states: `SELECTING_HAND`, `SHOP`, `BLIND_SELECT`, `ROUND_EVAL`, and pack-open states; hidden in menus/splash/game-over. (Exact list is a tunable placeholder.)
- **Conflict safety (verified, still runtime-tested in Phase 3):** Cryptid only changes `G.consumeables.config.highlighted_limit`; Cartomancer only toggles consumables visibility; JokerDisplay overrides `CardArea:draw` (not position). None reposition the consumables area, and none own a sibling UIBox bonded to it.

## 5. Gathering

Both sources funnel through `PB_UTIL.add_resource(key, amount)`.

### 5.1 Boss / blind defeat drops
- Listen on `SMODS.calculate_context({ blind_defeated = true })`, which Steamodded fires after `Blind:defeat` completes (blind state finalized).
- `PB_UTIL.grant_blind_drop(G.GAME.blind)`:
  - **Per-blind override** (opt-in): a side table `PB_UTIL.BLIND_DROPS['bl_minecraft_creeper'] = { tier=1, amount=2 }`. Keyed by blind key so it also works for vanilla blinds; does **not** reuse the existing custom `defeat` functions on minecraft blinds.
  - **Fallback tier roll** (placeholder balance): `amount = 1 + math.floor(G.GAME.round_resets.ante / 3)`; tier weighted by ante band; choose a random ore of that tier from `PB_UTIL.RESOURCES`, seeded via `pseudorandom(pseudoseed('minecraft_drop'..ante))` for run-deterministic results.

### 5.2 Resource booster pack
- `content/resources/resource_consumabletype.lua`: a **hidden** `SMODS.ConsumableType{ key='minecraft_resource', no_collection=true }` and 6 hidden `SMODS.Consumable` ores (`set='minecraft_resource'`, `atlas='minecraft_resource_cards'`, `no_collection=true`, kept out of shop/soul/normal pools, `in_pool=false`). Each ore's `use = function(self, card) PB_UTIL.add_resource(<orekey>, 1); card:start_dissolve() end`.
- `content/boosters/resource_pack.lua`: `SMODS.Booster{ key='resource_pack', config={ choose=1, extra=6 } }` with **no `select_card`**. `create_card` spawns the 6 ore consumables into `G.pack_cards` via `SMODS.create_card{ key=..., area=G.pack_cards, skip_materialize=true }`. Normal shop weight, cost ~4.
- Because neither the pack nor the ores define `select_card`, the base game (`button_callbacks.lua`) routes the chosen pack card through `card:use_consumeable(area)` + `SMODS.calculate_context({using_consumeable=true})`. `choose=1` enforces "pick one of six". **Nothing is ever added to `G.consumeables`** — the hidden ConsumableType is purely a vehicle for the pack pick.

## 6. Save / load

No custom save/load code. Counts are plain integers on `G.GAME` → serialized wholesale by the base save, restored verbatim on resume (panel reflects them via the ref binding once recreated), reset to zeros on new run via `init_game_object`. Mid-pack-open save/restore replays correctly because the grant mutates counts immediately at use time (base game snapshots booster use in the shop) and there is no nested-CardArea to restore.

## 7. File architecture

**New files**
| File | Responsibility |
|---|---|
| `content/resources/registry.lua` | `PB_UTIL.RESOURCES` (6 ores) + the two `SMODS.Atlas` registrations (cards 71×95, icons 34×34) |
| `content/resources/resource_consumabletype.lua` | Hidden `SMODS.ConsumableType` + 6 hidden ore `SMODS.Consumable`s (`atlas='minecraft_resource_cards'`, pack-only; `use` → `add_resource` → dissolve) |
| `content/boosters/resource_pack.lua` | `SMODS.Booster` (no `select_card`) spawning the 6 ores into `G.pack_cards` |
| `utilities/resources.lua` | `init_game_object` wrapper; `add_resource`/`get_resource_count`/`set_resource`; `grant_blind_drop`; `blind_defeated` listener |
| `utilities/resource_ui.lua` | `build_resources_panel` (34×34 icons + ref-bound counts), `attach_resources_panel` (Weak bond), `Game:update` show/hide |
| `assets/{1x,2x}/resource_cards.png` | 71×95 card sheet, 6 ores on a 3×2 grid → 213×190 (1x) / 426×380 (2x); used in the pack |
| `assets/{1x,2x}/resource_icons.png` | 34×34 hotbar block-icon sheet, 6 ores on a 3×2 grid → 102×68 (1x) / 204×136 (2x); used in the panel |
| `assets/gen_resources.py` | Procedural PIL generator that draws the 6 ores and writes both 1× sheets (see §11) |

**Edited files** (all following existing modular-loader house style)
| File | Change |
|---|---|
| `main.lua` | `if PB_UTIL.config.resources_enabled then` load `utilities/resources.lua`, `utilities/resource_ui.lua`, and `register_items(PB_UTIL.ENABLED_RESOURCES,'resources')` |
| `utilities/definitions.lua` | `PB_UTIL.ENABLED_RESOURCES = {'registry','resource_consumabletype'}`; add `'resource_pack'` to `ENABLED_BOOSTERS` |
| `config.lua` | `resources_enabled = true` |
| `utilities/ui.lua` | a `create_toggle` for Resources in the config tab |
| `localization/en-us.lua` | ore display names, booster name/desc, panel label |

## 8. Build order (8 phases)

0. **Loader wiring (no behavior):** config toggle + `ENABLED_RESOURCES` + `main.lua` branch + ui toggle. Verify mod still loads with empty stubs.
1. **State + helpers:** `init_game_object` wrapper + `add_resource`/`get_resource_count`/`set_resource` (number-coerced, nil-guarded). Smoke test: console `add_resource`, confirm persistence across save/quit/resume and reset on new run.
2. **Registry + atlas:** write `assets/gen_resources.py`, run it + `utils.py` to produce both 1×/2× sheets, then author `registry.lua` (the two `SMODS.Atlas` registrations). Confirm each ore sprite draws from both atlases.
3. **Inventory panel:** `resource_ui.lua` (ref-bound counts, Weak bond, `Game:update` show/hide). Verify it sits below consumables and live-updates. Re-verify with Cartomancer + JokerDisplay + Cryptid loaded.
4. **Boss drops:** `blind_defeated` listener + `grant_blind_drop` with tier-roll fallback + a couple of `BLIND_DROPS` entries. Defeat blinds, confirm increments.
5. **Resource booster:** hidden ConsumableType + 6 ores + `resource_pack` booster. Buy/open in shop; confirm one pick grants one resource, nothing lands in consumables, skip leaves counts unchanged.
6. **Hardening:** localization pass; grayed zero-count rendering; verify save/restore mid-pack-open; final 3-mod conflict pass.
7. **Forward seam (no implementation):** document that the future 3×3 grid reads `G.GAME.minecraft.resources` to materialize draggable tiles and decrement counts on craft — confirming this slice leaves counts as the clean handoff point.

## 9. Open items (tunable later, not blocking)

- **Boss-drop balance** — the ante bands and `1 + floor(ante/3)` formula are placeholders; only the *shape* (per-blind override table + ante-scaled fallback) is fixed.
- **Panel visible-states list** — exact `G.STATE` set is a tunable placeholder.
- **Cross-mod UI** — reasoned from source; must be runtime-tested with all three UI mods loaded (Phase 3).
- **`init_game_object` ordering** — load `utilities/resources.lua` before content so the wrapper is installed pre-run; multiple wrappers are additive (low risk).
- **Forward compat** — counts stay bare integers for this slice; if the later grid needs per-ore metadata (caps/locked state), migrate to `{count=int, ...}` then, not now.

## 10. Resolved decisions (from brainstorming)

- Zero-count ores → **always show all 6, grayed when 0** (fixed-size panel).
- Pack pick → **hidden ore consumables** (accepted; inert, `no_collection`, pack-only).
- Art → **two sheets** (authentic hotbar): 71×95 cards for the pack + 34×34 block icons for the panel.

## 11. Art / atlas pipeline

Two sprite sheets, both laid out on the **same 3×2 grid** (so one registry `pos` indexes both):

| Sheet | Cell (1x) | Grid | 1x size | 2x size | Atlas key | Used by |
|---|---|---|---|---|---|---|
| `resource_cards.png` | 71×95 | 3×2 | 213×190 | 426×380 | `minecraft_resource_cards` | hidden ore consumables in the booster pack |
| `resource_icons.png` | 34×34 | 3×2 | 102×68 | 204×136 | `minecraft_resource_icons` | inventory hotbar panel |

Grid order (both sheets): row 0 = Wood, Cobblestone, Coal · row 1 = Iron, Gold, Diamond.

**Pipeline (matches the existing mod workflow):**
1. Author each ore from its **16×16 Minecraft block texture** — center/frame it onto a 71×95 card for the card sheet, and place it (optionally on a slot background) onto a 34×34 cell for the icon sheet.
2. Compose the **1×** sheets in `assets/1x/`.
3. Generate the **2×** sheets with `assets/utils.py` → `scale_image(input, output, scale_factor=2)` (nearest-neighbor pixel duplication → crisp pixel art), saving to `assets/2x/`.
4. `SMODS.Atlas` `px`/`py` always reference the **1×** cell size (71×95 / 34×34); SMODS auto-selects 1×/2× from the player's texture setting.

The 6 source block textures needed: Wood (oak log/planks), Cobblestone, Coal (ore or lump), Iron (ingot or ore), Gold (ingot or ore), Diamond (gem or ore). Exact motif (ore block vs refined item) is a cosmetic choice; the icon should read clearly at 34×34.

**Production route (chosen): procedural generation.** A new self-contained script `assets/gen_resources.py` (PIL, same dependency as `utils.py`) draws each ore from a fixed palette — a stone base with colored ore speckles for Coal/Iron/Gold/Diamond, vertical grain for Wood, a blocky pattern for Cobblestone — and composes them into the two 1× sheets:
- `assets/1x/resource_icons.png` — 34×34 cells, the bare block on a subtle slot background.
- `assets/1x/resource_cards.png` — 71×95 cells, the block centered on a tier-tinted card face.

It writes deterministic output (no RNG, or fixed-seed) so regenerating is stable, then the 2× sheets are produced via `utils.py`'s `scale_image(..., scale_factor=2)`. Art is fully owned/copyright-clean and can be replaced by hand-drawn pixel art later with **no code change** (atlas keys and the 3×2 layout are fixed). Aim for "genuinely decent", not flat placeholders.
