Implemented: 3 / 3 — Sharpness / Unbreaking / Lucky

---

Editions are the shiny shader overlays on a card (vanilla: Foil / Holographic / Polychrome /
Negative). BalaCraft's editions are framed as **Minecraft enchantment glints** and are applied through
the mod's existing **[[Enchanting]]** system — the same "books" flow used for [[Tools]], now extended
to **playing cards**.

The base game's editions still work normally; these are **added** alongside them.

| Edition | Effect |
| --- | --- |
| [[Sharpness]] | +Mult (scales with book tier), doubled against boss blinds |
| [[Unbreaking]] | can't be debuffed by bosses; Glass-type cards won't break |
| [[Lucky]] | drops Emeralds each time the card scores (scales with book tier) |

*(A fourth edition, **Ender** — a Negative-style "free slot" glint for jokers/consumables — is
deferred; Negative has no vanilla analog on playing cards.)*

## Applying editions — card Enchanting Books
Editions are applied like tool enchants: you get a card-targeting **[[Enchanting Books|Enchanting
Book]]**, then **select a card + the book** and click **Enchant Card**. It **spends
[[Experience|levels]]** (Sharpness / Lucky: `book tier + 1`; Unbreaking: flat 2), not money, and the
card keeps the edition for the rest of the run. A card holds **one edition at a time** — applying a
different one is rejected (only a higher-tier same-type book upgrades in place).

- Card-edition books appear in the **shop** and the **[[Enchanting Pack]]**, both unlocked by the
  **[[Enchanting Table]]** voucher — the same gate as the tool books.
- This is why editions live next to [[Enchanting]]: they're the card branch of the same system.

## Status
- [x] **[[Sharpness]]** — Combat lane (Sharpness book → card)
- [x] **[[Unbreaking]]** — Protection lane (Durability book → card)
- [x] **[[Lucky]]** — Loot lane (Fortune book → card)
- [ ] **Ender** (deferred)

[[Overview|← Back to Overview]] · see [[Enchanting]]
