*Enhancement — one per mineable ore*

Ore Blocks are special enhancements: there's **one per mineable ore**, and unlike every other
enhancement they are **not** applied by a Tarot or [[Sheets|Sheet]]. They **spawn on cards in your
deck**, and you **[[Mining|mine]] them with a [[Pickaxe]]** (or, for wood, an [[Axe]]).

## Effect
When a blind is selected, some of your deck's cards turn into **ore blocks**. The block sits on the card
and the card still scores at its normal rank/suit — the block adds no scoring effect on its own. To
collect the ore you must **highlight the ore-block card(s) and Use a [[Pickaxe]]** on them (see
[[Mining]]); the card then reverts to a plain card and you gain that ore as a [[Resources|resource]].

| Ore block | Tier | Mined resource | Pickaxe level | Internal key |
| --- | --- | --- | --- | --- |
| ![[icon_wood.png\|24]] Wood | 1 | [[Wood]] | [[Axe]] / by hand | `m_balacraft_block_wood` |
| ![[icon_cobblestone.png\|24]] Cobblestone | 1 | [[Cobblestone]] | any | `m_balacraft_block_cobblestone` |
| ![[icon_coal.png\|24]] Coal | 1 | [[Coal]] | any | `m_balacraft_block_coal` |
| ![[icon_raw_iron.png\|24]] Iron | 2 | [[Raw Iron]] | Stone+ (1) | `m_balacraft_block_raw_iron` |
| ![[icon_raw_gold.png\|24]] Gold | 2 | [[Raw Gold]] | Iron+ (2) | `m_balacraft_block_raw_gold` |
| ![[icon_emerald.png\|24]] Emerald | 2 | [[Emerald]] | Iron+ (2) | `m_balacraft_block_emerald` |
| ![[icon_lapis.png\|24]] Lapis | 3 | [[Lapis Lazuli]] | Stone+ (1) | `m_balacraft_block_lapis` |
| ![[icon_redstone.png\|24]] Redstone | 3 | [[Redstone]] | Iron+ (2) | `m_balacraft_block_redstone` |
| ![[icon_diamond.png\|24]] Diamond | 3 | [[Diamond]] | Iron+ (2) | `m_balacraft_block_diamond` |
| ![[icon_obsidian.png\|24]] [[Obsidian Block]] | 3 | [[Resources/Obsidian\|Obsidian]] | Diamond (3) | `m_balacraft_block_obsidian` |
| ![[icon_netherite.png\|24]] Netherite | 4 | [[Netherite]] | Diamond (3) | `m_balacraft_block_netherite` |

> [[Iron]] and [[Gold]] are **smelt-only** — you mine the *raw* ore and smelt it in the Furnace, exactly
> like Minecraft. **[[Sand]]** is *not* an ore block (it drops/packs normally but is never mined from a card).

## How ore blocks spawn (biome + ante)
On **blind select**, fresh ore blocks are **added** onto random eligible cards. They are **additive** and
**accumulate** — un-mined blocks stay on their cards across blinds, so the deck steadily fills with ore
until you mine it. **Ante** decides *how many* and *how deep* (which tiers); your **[[Biomes|biome]]**
decides *which* ore within a tier (the same `resource_bias` that weights your blind drops). The tier gate
matches the rest of the mod: **tier 1 always, tier 2 from ante 3, tier 3 from ante 6, tier 4 (Netherite)
from ante 8.**

Roughly how many new ore-block cards each blind adds:

| Ante | Tier 1 | Tier 2 | Tier 3 | Tier 4 |
| --- | --- | --- | --- | --- |
| 1–2 | 1.0 | — | — | — |
| 3–5 | 0.75 | 1.25 | — | — |
| 6–7 | 0.5 | 1.0 | 1.0 | — |
| 8+ | 0.5 | 1.0 | 1.0 | 0.5 |

So early on you mostly mine wood/stone/coal (with most wood/cobblestone coming from blind **drops**), and
the metal tiers carry the mining economy as you go deeper — Minecraft progression, in your deck.

## Rules
- **Mining-level gate** — each ore needs a [[Pickaxe]] of a high-enough material to break it
  (Minecraft-faithful: cobblestone/coal any tool, iron from a Stone pickaxe, gold/redstone/diamond/emerald
  from an Iron pickaxe, **[[Obsidian]] and Netherite from a Diamond pickaxe**). A pickaxe that's too weak
  flashes *"Need a better pickaxe."*
- **Wood is the exception** — wood is never pickaxe-mined. Use an [[Axe]] on wood blocks (it can take
  several at once), or chop a single wood block by hand by playing it alone as a one-card hand (+1 wood).
- **One enhancement per card** — ore blocks never spawn on a card that already has an enhancement.
- **Persist until mined** — an ore block stays on its card across rounds until you mine it; there's no
  end-of-round cleanup.

## Why this exists
Beating the Night/Cave blinds increasingly drops **mob loot** (string, bone, gunpowder, …) rather than
ore — so **mining ore-block cards becomes a main way to get ores**. The [[Pickaxe]]/[[Axe]] tools exist to
power exactly this loop. See [[Mining]] and [[Resources]].

[[Enhancements|← Back to Enhancements]]
