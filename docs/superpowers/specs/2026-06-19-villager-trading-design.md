# Villager Trading (v1) — design

**Date:** 2026-06-19
**Status:** Approved (brainstorm) — ready for implementation plan
**Scope:** A persistent **Villager Trading** section in the shop where the player spends
**emeralds** ([[Emerald]] resource) on resource bundles and plain tools — "the things you can't
buy directly from the shop." This is the use for the Emerald ore shipped 2026-06-19
(`docs/superpowers/specs/2026-06-19-emerald-resource-design.md`).

## Goal

Give emeralds a purpose. Each shop, a small set of run-seeded trade offers appears in a dedicated
shop panel; the player buys as many as they can afford (paying emeralds, not money), offers sell
out when bought and refresh next shop, and the shop's reroll re-rolls them.

## Decisions (locked during brainstorm)

- **Access:** a **persistent section of the shop** (not a booster you open).
- **Cost model:** **free to access, buy multiple**, single currency = **emeralds**.
- **Refresh:** **~3 random offers per shop**, run-seeded; buying one **sells it out** for that shop
  visit; offers **refresh each shop** and **re-roll with the shop reroll** button.
- **v1 item pool:** **resource bundles + plain tools** (Sword/Pickaxe/Shovel/Torch). Enchanted-tool
  offers, biome-flavored pools, and any new voucher are **out of scope** (fast-follow).
- **Gating:** none — always present. The emerald balance is the natural gate.
- **Placement:** **right-side vertical panel over the deck corner**, shown **only in the shop**
  (`G.STATES.SHOP`), so it overlaps the idle deck but never the in-play deck.

## Architecture

The mod has never modified the shop UIBox, but it already wraps the exact seams needed (verified
against the dump in `../lovely/dump/` and the mod):

- `Game:update_shop` is wrapped in `utilities/biomes.lua` (shop-build gating) — precedent for
  build-time behavior.
- `G.FUNCS.buy_from_shop` is wrapped in `utilities/xp.lua` (awards XP on buy).
- `G.FUNCS.reroll_shop` is wrapped in `utilities/torch.lua` (debug logging) — precedent for reroll.
- Persistent floating panels (`resource_ui.lua`, `health_ui.lua`, `xp_ui.lua`) are Weak-bonded
  `UIBox`es maintained by a `Game:update` wrap and gated on `G.STATES`.

**Chosen approach: Weak-bonded floating panel + state wraps. No Lovely source patch.** A Lovely
patch into `G.UIDEF.shop` (dump `functions/UI_definitions.lua:649`) is the fallback only if the
floating anchor proves visually unstable; we avoid it to dodge a fragile line-exact pattern match.

### Components / files
Mirror the resource subsystem's data/logic/UI split. All three loaded explicitly in `main.lua`
(like the resource files), gated on a new `villager_enabled` config toggle.

- `content/villager/trades.lua` — **pure data**: `PB_UTIL.VILLAGER_TRADES` offer templates +
  pricing tables. Loaded first (it reads nothing; later files read it).
- `utilities/villager.lua` — **state + logic**: offer schema, seeding/reroll, buy logic, and the
  `Game:update_shop` + `G.FUNCS.reroll_shop` wraps.
- `utilities/villager_ui.lua` — **the shop panel UIBox** + the button `G.FUNCS` and a `Game:update`
  wrap that creates/refreshes/hides the panel (gated on `G.STATE == G.STATES.SHOP` + run state).

### State (hybrid model — no custom save/load)
On `G.GAME.balacraft` (plain tables/numbers → auto-saved within a run, auto-reset per run):
- `villager_offers` — array of ~3 offer tables for the current shop (see schema below).
- `villager_reroll_index` — integer, bumped on each reroll, reset when a new shop is entered;
  feeds the seed key so each shop/reroll is deterministic and save-safe.

Seed it from the `Game:init_game_object` wrapper in `utilities/resources.lua` alongside the other
`balacraft` fields (`villager_offers = {}`, `villager_reroll_index = 0`).

## Offer model

Each offer is a plain table:
```lua
-- resource bundle
{ kind = 'resource', id = 'iron', amount = 3, cost = 4, sold = false }
-- tool
{ kind = 'tool', key = 'c_balacraft_tool_pickaxe_diamond', label = 'Diamond Pickaxe', cost = 8, sold = false }
```

### Generation (`PB_UTIL.seed_villager_offers()`)
- Build a weighted template pool from `PB_UTIL.VILLAGER_TRADES`.
- Draw **3 distinct** offers using `pseudorandom_element` / `pseudoseed` with key
  `'bc_villager_' .. ante .. '_' .. round .. '_' .. villager_reroll_index` (deterministic,
  run-seeded, varies per shop and per reroll).
- Resource-bundle templates pick a **gathered** ore of the template's tier (filter
  `kind == 'gathered'`, **exclude emerald** — never sell emeralds for emeralds). Tool templates
  pick a tool consumable key.
- Store the result in `G.GAME.balacraft.villager_offers`.

Called: once when the shop is built (detected in the `Game:update_shop` wrap when `G.shop` becomes
non-nil and offers are unseeded for this visit), and again from the `reroll_shop` wrap (after
bumping `villager_reroll_index`). Entering a new shop resets `villager_reroll_index = 0`.

### Templates & pricing (`content/villager/trades.lua`, all tunable)

| Template | Instantiates | Emerald cost |
| --- | --- | --- |
| Tier-1 ore bundle | 5× a random tier-1 gathered ore (wood/cobblestone/coal) | 3 |
| Tier-2 ore bundle | 3× a random tier-2 gathered ore (iron/gold) | 4 |
| Tier-3 ore bundle | 2× a random tier-3 gathered ore (diamond) | 6 |
| Tool | 1× a tool consumable `c_balacraft_tool_<tool>_<material>` | 3/4/5/6/8 by material tier (wood→diamond) |
| Torch | 1× `c_balacraft_torch` | 2 |

Template draw weights (tunable): resource bundles common, tools rarer, so a typical shop shows
~2 bundles + ~1 tool. Costs reference the existing per-tier scaling (tool crafting uses
`COST_BY_TIER = {3,4,5,6,8}` in `content/tools/registry.lua`).

## Buy logic

- **Per-frame gate** `G.FUNCS.bc_can_buy_villager(e)` (mirrors vanilla `can_buy`): the offer is
  buyable iff `not offer.sold`, `get_resource_count('emerald') >= offer.cost`, and — for `tool`
  offers — there is a free consumable slot (`#G.consumeables.cards < G.consumeables.config.card_limit`).
  Sets the button colour green/greyed and toggles `e.config.button`.
- **Buy** `G.FUNCS.bc_buy_villager_offer(e)`: re-check the same conditions; spend
  `PB_UTIL.add_resource('emerald', -offer.cost)`; grant the output —
  `add_resource(id, +amount)` for a bundle, or the `consumable_add(key)` helper for a tool; set
  `offer.sold = true`. A juice/sound feedback consistent with the mod's other buttons.

## UI (`utilities/villager_ui.lua`)

A Weak-bonded `UIBox` anchored to the right of `G.shop` (offset over the deck corner; exact offset
tunable in-game). Maintained by a `Game:update` wrap: created when `G.STATE == G.STATES.SHOP` and
the shop/atlas are ready, refreshed when offers change (`sold`/reroll), torn down otherwise. Layout:

```
┌ VILLAGER TRADES ─ ◆ 12 ┐    ◆N = live-bound emerald count (UIT ref_table/ref_value)
│ [icon] 4× Iron    ◆ 4 [Trade] │
│ [icon] Dia Pickaxe ◆ 8 [Trade] │
│ [icon] 5× Coal    ◆ 3 [Trade] │
└────────────────────────┘
```
- Each offer row: item icon (resource → `bc_resource_icons` at the ore's pos; tool → its consumable
  art), a label, the emerald cost, and a **Trade** button (`button='bc_buy_villager_offer'`,
  `func='bc_can_buy_villager'`, `ref_table = offer`).
- A sold offer shows **Sold** and a greyed button.
- The header emerald count is live-bound to `G.GAME.balacraft.resources.emerald`.

## Wiring

- `config.lua`: add `villager_enabled = true`.
- `main.lua`: when `villager_enabled`, load `content/villager/trades.lua`, then
  `utilities/villager.lua`, then `utilities/villager_ui.lua` (data → logic → UI order).
- `utilities/resources.lua` `init_game_object` wrapper: seed `villager_offers` / `villager_reroll_index`.

## Edge cases
- **No emeralds:** panel still shows; all Trade buttons greyed.
- **Tool, no consumable slot:** Trade greyed (re-checked at buy time too).
- **Save/reload mid-shop:** offers + reroll index persist on `G.GAME` (hybrid model); the panel
  rebuilds from them.
- **Tool/Torch content disabled:** tool templates whose consumable key is missing from
  `G.P_CENTERS` are skipped at generation time (so an offer can't grant a non-existent card).
- **resources_enabled off:** `villager_enabled` should no-op if the resource subsystem (emeralds)
  isn't loaded — guard the load on resources being available.

## Out of scope (fast-follow)
Enchanted-tool offers (depends on the enchanting system being verified in-game), biome-flavored
trade pools, a trading voucher/unlock, and any non-shop access point.

## Verification (hand-off — agents cannot run Balatro)
After implementation, the user verifies in-game:
1. In the shop, a Villager Trades panel shows ~3 offers in the deck corner; it disappears during a
   blind.
2. The header shows the live emerald count; buying spends emeralds and grants the item; the offer
   flips to **Sold**.
3. Unaffordable / no-slot offers are greyed; with 0 emeralds the whole panel is greyed but visible.
4. Rerolling the shop changes the offers; entering the next shop shows a fresh set.
5. Save & reload in the shop restores the same offers and sold states.
