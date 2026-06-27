Implemented: 16 biomes across 3 dimensions

---
Biomes and dimensions reshape each run. A **dimension** (Overworld, Nether, End) is a set of biomes; a **biome** is the theme for a single ante.

## Dimensions
- **Overworld** — where every run starts by default (in [[Plains]]).
- **Nether** — reached via the [[Nether Portal]] voucher or the [[Nether Deck]].
- **End** — reached via the [[End Portal]] voucher or the [[End Deck]].

Selection pools are dimension-isolated — once you're in the Nether, you pick from Nether biomes, etc.

## How biomes work
- **Picked each ante.** After every Boss cash-out, before the shop opens, you choose **1 of 3 biomes** from your current dimension (your current biome is excluded). Selection only appears if the dimension has ≥ 2 biomes.
- **Background tint.** The chosen biome recolors the table for non-boss states.
- **Ore bias.** Each biome weights which [[Resources|ores]] you roll from drops (see each biome's *ore bias*).
- **Arrival bonus.** Some biomes give a one-time $ bonus or penalty the moment you enter.
- **Exclusive bosses.** Three biomes add their own boss to the pool: [[Forest]] → [[The Overgrowth]], [[Basalt Deltas]] → [[Magma Lord]], [[Central End]] → [[Ender Sentinel]].
- **Decks.** Each Overworld biome has an unlockable start-deck (see [[Biome Decks]]).

## Overworld
| Biome | Arrival $ | Ore bias | Exclusive boss |
| --- | --- | --- | --- |
| ![[biome_plains.png\|34]] [[Plains]] | — | Wood, Cobblestone | — |
| ![[biome_forest.png\|34]] [[Forest]] | — | Wood, Coal | [[The Overgrowth]] |
| ![[biome_desert.png\|34]] [[Desert]] | +$4 | Gold, Iron | — |
| ![[biome_snowy_taiga.png\|34]] [[Snowy Taiga]] | −$2 | Diamond, Iron | — |
| ![[biome_jungle.png\|34]] [[Jungle]] | — | Wood, Coal | — |
| ![[biome_swamp.png\|34]] [[Swamp]] | −$1 | Coal, Wood | — |
| ![[biome_savanna.png\|34]] [[Savanna]] | +$2 | Cobblestone, Gold | — |
| ![[biome_badlands.png\|34]] [[Badlands]] | +$3 | Gold, Iron | — |

## Nether
| Biome | Arrival $ | Ore bias | Exclusive boss |
| --- | --- | --- | --- |
| ![[biome_nether_wastes.png\|34]] [[Nether Wastes]] | +$3 | Gold, Coal | — |
| ![[biome_crimson_forest.png\|34]] [[Crimson Forest]] | — | Wood, Gold | — |
| ![[biome_soul_sand_valley.png\|34]] [[Soul Sand Valley]] | −$2 | Coal, Iron | — |
| ![[biome_basalt_deltas.png\|34]] [[Basalt Deltas]] | — | Cobblestone, Diamond | [[Magma Lord]] |

## End
| Biome | Arrival $ | Ore bias | Exclusive boss |
| --- | --- | --- | --- |
| ![[biome_central_end.png\|34]] [[Central End]] | — | Diamond, Gold | [[Ender Sentinel]] |
| ![[biome_end_highlands.png\|34]] [[End Highlands]] | +$3 | Diamond, Iron | — |
| ![[biome_end_midlands.png\|34]] [[End Midlands]] | — | Gold, Coal | — |
| ![[biome_end_barrens.png\|34]] [[End Barrens]] | −$3 | Diamond | — |

> Art is procedurally-generated placeholder posters; real pixel-art scenes are a later task.
