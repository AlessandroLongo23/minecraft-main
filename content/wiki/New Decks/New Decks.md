Implemented: 11 (3 dimension + 8 biome)

---

BalaCraft adds three **dimension decks** plus one **start-in-biome deck per Overworld biome**.

| Deck | Effect | Unlock |
| --- | --- | --- |
| [[Overworld Deck]] | Start with a bonus joker | Available by default |
| [[Nether Deck]] | Start the run in a random Nether biome | Buy the Nether Portal voucher 10× (lifetime) |
| [[End Deck]] | Start the run in a random End biome | Buy the End Portal voucher 10× (lifetime) |
| [[Biome Decks]] (×8) | Start the run in a specific Overworld biome | Win 10 antes in that biome (lifetime) |

See [[Biomes]] for how dimensions and biomes work, and [[New Vouchers]] for the portals that feed the dimension-deck unlocks.

## Unlock tracking
Deck unlocks are the mod's only **cross-run persistent progression** — they're saved to a small `balacraft_progression.jkr` file:
- **Portal buys** — each time you redeem a Nether/End Portal voucher, a lifetime counter ticks up. 10 buys unlocks that dimension's deck.
- **Biome ante wins** — each boss blind you beat increments a per-biome lifetime counter. 10 wins in a biome unlocks that biome's deck.
