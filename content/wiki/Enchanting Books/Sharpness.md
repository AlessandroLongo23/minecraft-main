*Enchanting Book — 3 tiers · dual-target (Sword **or** playing card)*

![[res_iron.png|100]]
*Placeholder art (uses an ore card cell for now).*

## Effect
Sharpness is **dual-target** — the same book enchants either a tool or a playing card:
- On a **[[Sword]]**: **multiplies its ×Mult** by the book's tier (on top of the material value). A Diamond Sword (×8) with Sharpness III hits **×14**.
- On a **playing card**: applies the **[[Editions/Sharpness|Sharpness edition]]** — **+4 Mult when the card scores, +8 vs a boss**. The card effect is the same at any book tier.

## Tiers (tool side)
| Tier | Sword ×Mult | Shop $ | Internal key |
| --- | --- | --- | --- |
| Sharpness I | ×1.25 | $4 | `c_balacraft_enchant_sharpness_1` |
| Sharpness II | ×1.5 | $7 | `c_balacraft_enchant_sharpness_2` |
| Sharpness III | ×1.75 | $10 | `c_balacraft_enchant_sharpness_3` |

## Applying
- **To a tool:** select a [[Sword]] + this book in your consumable slots → **Enchant**. Cost scales: `book tier + material tier − 1` [[Experience|levels]]. A higher tier upgrades an existing Sharpness.
- **To a card:** during a blind, highlight a card **in your hand** + this book in your consumable slots → **Enchant Card**. Flat **2 levels**; applies the [[Editions/Sharpness|Sharpness edition]] (any book tier works).

See [[Enchanting]].

[[Enchanting Books|← Back to Enchanting Books]]
