*Mechanic — balance reference*

How many [[Resources]] you get for beating a blind, and why. This page is the **living balance
reference**: the numbers here are kept in sync with the code constants (see the *Tunable knobs* table at
the bottom), so a future tweak updates both. The headline result is that **Wood + Cobblestone are
reliable** (you can craft a [[Smelting|Furnace]] by ante 2 in most runs), while **metal ores are rare from
drops** — you're meant to **mine** those from the deck instead.

Every Balatro ante is three blinds: a **Night** (surface, the reskinned Small Blind), a **Cave**
(underground, the reskinned Big Blind), and a **Boss**. The non-boss blinds keep vanilla rules (no
debuff, skippable) but each drives an environment-specific drop pool. Each blind win rolls drops from
small discrete distributions — the variance is intentional, so every run is a little different but on
average you hit the milestones.

Drops are one of three streams: **blind drops** (this page), tool-driven **[[Mining]]** (use a
[[Pickaxe]] / [[Axe]] on deck ore-block cards), and — once you travel — dimension-specific pools
([[Dimensions]]).

## Drop categories

| Category | Items | Drop behaviour |
| --- | --- | --- |
| **Basics** | [[Wood]], [[Cobblestone]] | Guaranteed per-blind rolls, ~1.57 each/blind. The backbone of crafting. |
| **Metal ore** | [[Coal]], [[Sand]], Raw Iron, Raw Gold, [[Emerald]], [[Redstone]], [[Lapis Lazuli\|Lapis]], [[Diamond]], Netherite | Rare bonus (~0.45/blind total). Mostly **mined** from deck ore-blocks. |
| **Mob** | [[String]], [[Feather]], [[Flint]], [[Leather]], Bone, Gunpowder, Spider Eye, Glow Ink Sac | Modest additive roll (~0.40/blind on generic blinds; themed bosses always drop their signature). |
| **Organic** | Flowers (+ Sugar Cane/Carrot/Melon/Mushroom) | High rate (~1.25/blind), overworld only. Fuel for the [[Composter]] → Bone Meal; useless otherwise. |
| **Special** | Obsidian, Ender Pearl, Blaze Powder | Progression items, granted only by bespoke code (Cave/Portal, Enderman/Blaze bosses, dimension trickles). |

## Wood & Cobblestone (the guaranteed rolls)

Each is a per-blind distribution over the amount 0–3, biased by environment (Night favours Wood, Cave
favours Cobble, Boss is balanced). Both land on **every** blind type, so even a themed boss pays basics.

| | Night PMF | Cave PMF | Boss PMF | avg/blind |
| --- | --- | --- | --- | --- |
| **Wood** | `{.05,.20,.45,.30}` μ2.00 | `{.20,.55,.25,0}` μ1.05 | `{.05,.40,.40,.15}` μ1.65 | **1.57** |
| **Cobblestone** | `{.20,.55,.25,0}` μ1.05 | `{.05,.20,.45,.30}` μ2.00 | `{.05,.40,.40,.15}` μ1.65 | **1.57** |

PMF notation: `{P0,P1,P2,P3}` = the probability of dropping 0/1/2/3.

Per-cell mean (μ) and variance (σ²):

| Shape | used by | μ | σ² |
| --- | --- | --- | --- |
| `{.05,.20,.45,.30}` | Night Wood / Cave Cobble | 2.00 | 0.70 |
| `{.20,.55,.25,0}` | Night Cobble / Cave Wood | 1.05 | 0.4475 |
| `{.05,.40,.40,.15}` | Boss Wood + Cobble | 1.65 | 0.6275 |

## Metal ore (the rare bonus)

A single low-probability roll for **one** metal ore, from a pool that **excludes Wood + Cobble** (so the
tier-1 pool is just {Coal, Sand}; higher tiers unlock with the ante — T2 at ante 3, T3 at ante 6, T4 at
ante 8). On Boss (and a coin-flip of Cave) the roll uses the highest unlocked tier.

| | Night | Cave | Boss | avg/blind |
| --- | --- | --- | --- | --- |
| P(metal ore), 1 each | 0.30 | 0.45 | 0.60 | **0.45** |

## Mob & Organic

- **Mob:** generic blinds roll one mob material at **0.40**; themed bosses always drop their signature
  (e.g. Spider → 2 String). Cave can roll cave-exclusive mobs (Spider Eye, Glow Ink Sac); Night can't.
- **Organic (flowers):** overworld-only roll, PMF `{.20,.45,.25,.10}` → **μ 1.25, σ² 0.7875** per blind.
  Coexists with the brewing-ingredient drop (1/blind when Potions are on) — flowers feed the [[Composter]].

## Dimension-themed brewing drops

While [[Potions]] are enabled, **every** blind win also grants **one brewing ingredient** from the
current dimension's pool ([[Dimensions]]):

| Dimension | Ingredient pool |
| --- | --- |
| Overworld | Sugar Cane, [[Resources/Carrot\|Carrot]], Melon Slice, Brown Mushroom |
| Nether | Nether Wart, Blaze Rod, Ghast Tear, Glowstone Dust |
| End | Dragon's Breath |

These are the only source of those raws (they're kept out of every ore/mob pool), so brewing supply
follows where you travel. See [[Brewing Stand]].

## Tool bonuses on a win

Tools change what a win gives you (see [[Mining]] for the full mechanic):
- **[[Shovel]]** — using it arms a cash payout that lands on the **next blind defeated** (its [[Fortune]]
  enchant raises the find odds).
- **[[Pickaxe]] / [[Axe]]** — mine ore-block cards during the blind (yield scales with [[Fortune]]); this
  is the main metal supply, separate from the random drops above.

## Per-blind total

Useful drops (Wood + Cobble + Mob + Metal) ≈ 1.57 + 1.57 + 0.40 + 0.45 = **~4.0/blind**, plus **~1.25
organic** on top (plus 1 brewing ingredient if Potions are enabled). That's the "4–5 drops" target with
organics as bonus.

## Milestone math

### Furnace by end of ante 2 (8 Cobblestone, 6 blinds)

Six blinds = 2 × {Night, Cave, Boss}. Summing the Cobblestone cells:

- **mean** = 2 × (1.05 + 2.00 + 1.65) = **9.40**
- **variance** = 2 × (0.4475 + 0.70 + 0.6275) = **3.55**, so σ = √3.55 = **1.884**
- **P(sum ≥ 8)** with continuity correction = P(sum ≥ 7.5) = Φ((9.40 − 7.5) / 1.884) = Φ(1.01) ≈ **84%**

So ~5 runs in 6 have the Furnace by ante 2; the unlucky ~1 in 6 gets it early ante 3. A **Chest** (8
Wood) is symmetric → also **~84%**.

### Nether by ~end of ante 4 (12 blinds)

Resource-wise this is supported: [[Flint]] is a mob drop, Raw Iron is minable by ante 3 (smelt → Iron),
Obsidian comes from Cave wins (25%) or beating a Ruined Portal normally. The real gate is **when the
Ruined Portal blind appears** (`STRUCTURE_CHANCE` / portal weight in `utilities/structures.lua`), not
the drop rates — a fairly-high but not guaranteed chance, by design.

### The End by ante 7–8 (3 × Eye of Ender = 3 Ender Pearl + 3 Blaze Powder)

- **Blaze Powder** is abundant once in the Nether: 0.30 trickle/win + the Blaze boss + crafting from a
  Blaze Rod (1 → 2).
- **Ender Pearls** are the bottleneck. The Enderman boss only appears at ante 1 (it does **not** recur),
  so the Nether adds a **0.25 Pearl trickle/win** (Piglin bartering / warped-forest Endermen). Over ~9–12
  Nether wins (antes ~4–7) that's ~2.5–3 Pearls + the 1 from the boss → enough for 3 Eyes, not
  guaranteed.

## Deck ore-blocks (mining supply)

Metals come mainly from **mining** ore-block cards in the deck (use a [[Pickaxe]] on highlighted ore
cards). On **each** blind select, fresh blocks are **added** and **accumulate** on top of un-mined ones
(they are not capped to a standing target) until no plain cards remain. Per-blind adds, by ante:

| Ante | Tier 1 | Tier 2 | Tier 3 | Tier 4 |
| --- | --- | --- | --- | --- |
| 1–2 | 1.0 | – | – | – |
| 3–5 | 0.75 | 1.25 | – | – |
| 6–7 | 0.5 | 1.0 | 1.0 | – |
| 8+ | 0.5 | 1.0 | 1.0 | 0.5 |

Tier-1 blocks are {Wood, Cobblestone, Coal}; the tier-2 bump makes ~1 Raw Iron/blind minable by ante 3
(needed for the Nether's Iron). Fractional values round stochastically per blind.

## Tunable knobs

Every number above lives in code — change it there and update this page.

| Knob | Where |
| --- | --- |
| `WOOD_PMF`, `COBBLE_PMF`, `ORGANIC_PMF` | `utilities/resources.lua` (constants block) |
| `METAL_ORE_CHANCE`, `CAVE_HIGH_TIER_CHANCE` | `utilities/resources.lua` |
| `MOB_DROP_CHANCE` | `utilities/resources.lua` |
| `CAVE_OBSIDIAN_CHANCE`, `DIMENSION_MAT_CHANCE`, `NETHER_PEARL_CHANCE` | `utilities/resources.lua` |
| Metal pool exclusion (no Wood/Cobble) | `PB_UTIL.random_metal_ore_of_tier_at`, `utilities/resources.lua` |
| Themed boss overrides (Creeper/Skeleton) | `PB_UTIL.BLIND_DROPS`, `utilities/resources.lua` |
| Deck ore-block adds + accumulation | `PB_UTIL.oreblock_budget` / `spawn_ore_blocks`, `utilities/card_enhancements.lua` |
| Ante → max ore tier | `PB_UTIL.max_ore_tier`, `utilities/resources.lua` |

See also: [[Mining]] · [[Dimensions]] · [[Crafting]] · [[Smelting]] · [[Resources]] · [[Villager Trading]] · [[Composter]] · [[Brewing Stand]]

[[New mechanics|← Back to mechanics]]
