*Enhancement — **planned**, not yet implemented — 7 ore variants*

Ore Blocks are special enhancements: there's **one per gathered [[Resources|ore]]**, and unlike every
other enhancement they are **not** applied by a Tarot. They **spawn on cards in your deck**, and you
**mine them by playing the card**.

## Effect
When a blind is selected, some of your deck's cards turn into **ore blocks**. Playing such a card
**mines it**: you gain that ore as a [[Resources|resource]], and the enhancement is **removed** (the
card reverts to normal). It's a reason to actually *play* an ore card when you want the loot.

| Ore | Tier | Mined resource | Internal key |
| --- | --- | --- | --- |
| ![[icon_wood.png\|24]] Wood block | 1 | [[Wood]] | `m_balacraft_ore_wood` (planned) |
| ![[icon_cobblestone.png\|24]] Cobblestone | 1 | [[Cobblestone]] | `m_balacraft_ore_cobblestone` (planned) |
| ![[icon_coal.png\|24]] Coal ore | 1 | [[Coal]] | `m_balacraft_ore_coal` (planned) |
| ![[icon_iron.png\|24]] Iron ore | 2 | [[Iron]] | `m_balacraft_ore_iron` (planned) |
| ![[icon_gold.png\|24]] Gold ore | 2 | [[Gold]] | `m_balacraft_ore_gold` (planned) |
| ![[icon_emerald.png\|24]] Emerald ore | 2 | [[Emerald]] | `m_balacraft_ore_emerald` (planned) |
| ![[icon_diamond.png\|24]] Diamond ore | 3 | [[Diamond]] | `m_balacraft_ore_diamond` (planned) |

## How ore blocks spawn (biome + ante)
On **blind select**, ore blocks are **topped up** onto random eligible cards toward the ante's target
total (existing un-mined blocks count, so they don't pile up endlessly). **Ante** decides *how many*
and *how deep* (which tiers); your **[[Biomes|biome]]** decides *which* ore within a tier (same
`resource_bias` that weights your blind drops). The tier gate matches the rest of the mod:
**tier 1 from ante 1, tier 2 from ante 3, tier 3 (Diamond) from ante 6.**

Expected ore-block cards per blind:

| Ante | Tier 1 | Tier 2 | Tier 3 | Total |
| --- | --- | --- | --- | --- |
| 1–2 | 2.0 | — | — | 2.0 |
| 3–5 | 1.5 | 1.0 | — | 2.5 |
| 6–7 | 1.0 | 1.5 | 0.5 | 3.0 |
| 8+ | 0.75 | 1.75 | 1.0 | 3.5 |

So early on you mostly mine wood/stone/coal; deeper antes shift toward iron/gold/emerald and finally
diamond — Minecraft progression, in your deck.

## Rules
- **One enhancement per card** — ore blocks never spawn on a card that already has an enhancement.
- **Persist until mined** — an ore block stays on its card across rounds until you **play the card to
  mine it**. There's no end-of-round cleanup; the blind-select top-up just won't exceed the ante's
  target while blocks are still sitting unmined.
- **[[Pickaxe]] boosts mining** *(planned rescope)* — the Pickaxe tool's bonus will apply to ore you
  **mine from cards** (yield `1 + N`), instead of to blind-defeat drops. See [[Pickaxe]].

## Why this exists
In a later pass, beating blinds will drop **mob loot** (string, rotten flesh, blaze rods, …) instead
of ore — so **mining ore-block cards becomes the main way to get ores**. That's exactly why the
[[Pickaxe]] moves over to boosting card-mining. See [[Resources]].

[[Enhancements|← Back to Enhancements]]
