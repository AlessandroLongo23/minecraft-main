Implemented: 11 (1 dev + 2 dimension + 8 biome)

---

BalaCraft ships a developer sandbox deck, two **dimension decks**, and one **start-in-biome deck per Overworld biome**.

| Deck | Effect | Unlock |
| --- | --- | --- |
| [[Test Deck]] | **Dev/sandbox**: start loaded with cash, XP, every resource, and the enchanting vouchers | Always available |
| [[Nether Deck]] | Start the run in a random Nether biome | Enter the Nether 10× (lifetime) |
| [[End Deck]] | Start the run in a random End biome | Enter the End 10× (lifetime) |
| [[Biome Decks]] (×8) | Start the run in a specific Overworld biome | Win 10 antes in that biome (lifetime) |

> ⚠️ The [[Test Deck]] is a **developer/testing deck** that replaced the old "Overworld" deck; it is meant to be removed before any public release. For a normal Overworld start, pick one of the per-biome [[Biome Decks]].

See [[Biomes]] for how dimensions and biomes work, and [[Dimensions]] for how you actually travel to the Nether and the End mid-run.

## Unlock tracking
Deck unlocks are the mod's only **cross-run persistent progression** — they're saved to a small `balacraft_progression.jkr` file:
- **Dimension entries** — each time you enter the Nether (via a Ruined Portal blind + [[Flint and Steel]]) or the End (via the [[Eye of Ender]] trail), a lifetime counter ticks up. 10 entries unlocks that dimension's deck. (The old portal *vouchers* that used to feed these counters were removed.)
- **Biome ante wins** — each boss blind you beat increments a per-biome lifetime counter. 10 wins in a biome unlocks that biome's deck.
