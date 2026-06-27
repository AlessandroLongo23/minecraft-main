# Test Deck — Design

**Date:** 2026-06-19
**Status:** Approved (design); ready for implementation plan
**Scope:** Replace the Overworld deck with a developer "Test" deck that force-grants a
sandbox loadout at run start, so content (jokers, vouchers, enchanting, resources) can be
exercised immediately without grinding a full run.

> This is **Piece A** of a two-part conversation. **Piece B** — making enchanting books
> dual-target (one "Sharpness" multiplier book applicable to *either* a tool → ×Mult *or* a
> playing card → +Mult) — is intentionally deferred to its own brainstorm + spec. The Test
> Deck is the tool that will let us verify Piece B without a full run, which is why it goes
> first. The only coupling: the Test Deck's consumable list references the existing multiplier
> book `c_balacraft_enchant_smithing_1` today; when Piece B renames `smithing → sharpness`,
> that one key in the deck gets updated.

## Goal & non-goals

**Goal:** A deck whose `apply()` immediately puts the run into a richly-stocked state, with the
"what to force" knobs expressed as a handful of editable local lists at the top of the file —
the same authoring workflow as any production deck.

**Non-goals:**
- No separate config-file layer, no in-game spawner UI, no custom save/load state. It is a
  plain `SMODS.Back`; the "knobs" are local variables.
- No new art. Reuse the existing `OverworldDeck.png` sprite.
- No release-gating logic. The deck is always visible; it is removed from `ENABLED_DECKS`
  before any public release.

## Changes

### 1. Remove the Overworld deck
- Delete `content/decks/overworld.lua`.
- Remove `'overworld'` from `PB_UTIL.ENABLED_DECKS` in `utilities/definitions.lua`.
- The deck is self-contained — the only references are its own file and that one whitelist
  entry — so removal is clean. The base-game Red Deck remains the default; `nether`, `end`,
  and the per-biome `biome_decks` are unaffected.

### 2. Add `content/decks/test.lua`
A normal self-executing `SMODS.Back` declaration, matching the style of `nether.lua` / `end.lua`.

**Atlas:** re-register the existing art under a new key so the deck has a sprite without new
assets:
```lua
SMODS.Atlas { key = 'testDeck', path = 'OverworldDeck.png', px = 71, py = 95 }
```
(`assets/1x/OverworldDeck.png` and `assets/2x/OverworldDeck.png` already exist.)

**Back:** `key = 'test'` → center `b_balacraft_test`; `name = 'Test'`;
`unlocked = true`, `discovered = true`; `loc_txt` describing it as a dev sandbox.

**Editable loadout lists** (top of file — this is the "what to force" surface):
```lua
local DOLLARS     = 999                              -- extra starting cash (0 = skip)
local LEVEL       = 100                              -- starting XP level (0 = skip)
local RESOURCES   = 99                               -- every resource id set to this (0 = skip)
local JOKERS      = {}                                -- joker keys to add, e.g. 'j_balacraft_elytra'
local CONSUMABLES = { 'c_balacraft_enchant_smithing_1' } -- consumable keys to add (the multiplier book)
local VOUCHERS    = {                                 -- vouchers to force-redeem
    'v_balacraft_enchanting_table',
    'v_balacraft_sorcerers_tome',
}
local CARD_MOD    = { seal = nil, enhancement = nil, edition = nil, count = 0 } -- stamp starting cards
```

Default loadout rationale ("full sandbox, no dimension vouchers, with a multiplier book"):
- `LEVEL = 100` — start at XP level 100 (set on `G.GAME.balacraft.xp_level` directly; no
  set-funnel exists and `spend_level` writes the same field) so enchanting, which spends levels,
  can be exercised immediately.
- `DOLLARS = 999`, `RESOURCES = 99` — enough cash + every resource (gathered **and** crafted,
  since this is a sandbox) to craft/buy freely.
- `VOUCHERS` includes the **enchanting pair** (`enchanting_table`, `sorcerers_tome`) so the
  enchanting flow is live at run start, but **excludes the two dimension portals**
  (`nether_portal`, `end_portal`) per the request.
- `CONSUMABLES` includes the multiplier book (`enchant_smithing_1`) so enchanting can be tested
  immediately — this becomes `enchant_sharpness_1` after Piece B.
- `JOKERS` empty and `CARD_MOD` off by default (card-mod alters starting deck composition; it's
  opt-in).

### 3. The grant routine (`apply`)
All grants run inside `G.E_MANAGER:add_event(Event({...}))` like the existing decks so timing
matches the engine. Each category uses a verified primitive:

| Category | Mechanism | Verified against |
| --- | --- | --- |
| Money | `ease_dollars(DOLLARS)` | used throughout the mod (`utilities/resources.lua` etc.) |
| Resources | `for id in pairs(PB_UTIL.RESOURCES) do PB_UTIL.add_resource(id, RESOURCES) end` | the resource mutation funnel (CLAUDE.md invariant) |
| Jokers | `for _,k in ipairs(JOKERS) do joker_add(k) end` | `utilities/functions.lua` |
| Consumables | `for _,k in ipairs(CONSUMABLES) do consumable_add(k) end` | `utilities/functions.lua` |
| Vouchers | for each `k`: `G.GAME.used_vouchers[k] = true`; `G.GAME.starting_voucher_count = (G.GAME.starting_voucher_count or 0) + 1`; `Card.apply_to_run(nil, G.P_CENTERS[k])` | base-game deck pattern, `lovely/dump/back.lua:226-235`; `Card:apply_to_run` at `card.lua:2229` |
| Card mods | if `CARD_MOD.count > 0`, apply to that many `G.playing_cards`: `set_seal(CARD_MOD.seal)` / enhancement via `set_ability(G.P_CENTERS[CARD_MOD.enhancement])` / `set_edition({[CARD_MOD.edition]=true})` | `set_seal`/`set_edition` in `utilities/torch.lua`; `set_ability` for enhancements at `card.lua:236` / `card.lua:1482`; commented precedent in old `overworld.lua` |

Guard each grant so an empty/zero/`nil` knob is simply skipped (e.g. `if DOLLARS ~= 0 then …`,
`if next(VOUCHERS) then …`). Resource and voucher loops should `pcall`/nil-check
`G.P_CENTERS[k]` so a typo'd key in a list can't crash the run.

### 4. Register the deck
Add `'test'` to `PB_UTIL.ENABLED_DECKS` in `utilities/definitions.lua` (replacing the removed
`'overworld'` entry).

## Architecture notes
- **One unit, one purpose:** the file is a single deck declaration. Its dependency surface is
  the existing global helpers (`ease_dollars`, `PB_UTIL.add_resource`, `joker_add`,
  `consumable_add`) plus `G.GAME` / `G.P_CENTERS` — no new shared state, no new module.
- **Editing the loadout** never touches the grant routine; you only change the six locals.
- **Resource loop includes crafted resources** deliberately (sandbox). This is the opposite of
  drop/pack pools, which must filter `kind == 'gathered'` — but those guards don't apply here
  because we're force-setting counts, not sampling a pool.

## Testing
No automated tests exist (interpreted Lua). Verification is in-game by the user:
1. Launch Balatro, enable BalaCraft, confirm **Overworld** is gone from the deck list and
   **Test** is present and selectable.
2. Start a run on the Test deck; confirm: ~999 dollars, XP bar at level 100, every resource at 99 in the hotbar,
   the enchanting + sorcerer's tome voucher effects active, a Smithing book in the consumable
   slots, and (default) no dimension portal vouchers and an unmodified card composition.
3. Sanity: no crash on run start; editing a list (e.g. add a joker key) reflects next run.
