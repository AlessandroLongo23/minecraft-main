Implemented: 3 / 3 — Sharpness / Unbreaking / Lucky

---

Editions are the shiny shader overlays on a card (vanilla: Foil / Holographic / Polychrome /
Negative). BalaCraft's editions are framed as **Minecraft enchantment glints** and are applied through
the mod's existing **[[Enchanting]]** system — the same "books" flow used for [[Tools]], now extended
to **playing cards**.

The base game's editions still work normally; these are **added** alongside them.

| Edition | Effect |
| --- | --- |
| [[Editions/Sharpness|Sharpness]] | +Mult (scales with book tier), doubled against boss blinds |
| [[Unbreaking]] | can't be debuffed by bosses; Glass-type cards won't break |
| [[Lucky]] | drops Emeralds each time the card scores (scales with book tier) |

*(A fourth edition, **Ender** — a Negative-style "free slot" glint for jokers/consumables — is
deferred; Negative has no vanilla analog on playing cards.)*

## Applying editions — card Enchanting Books
Editions are applied with the mod's **[[Enchanting Books|Enchanting Books]]**. You **generate** a book at
the crafted **[[Enchanting Table]]** (that's where the cost is paid — [[Experience|levels]] + Lapis + a
Book), then to apply it you **highlight a card in hand + the book** and click **Enchant** — which is now
**free** (the cost was already spent forging the book). The card keeps the edition for the rest of the run.

A card holds **one edition at a time** — applying a different type is rejected; only a **higher-tier book
of the same type** upgrades it in place.

- This is why editions live next to [[Enchanting]]: they're the card branch of the same Enchanting
  Books system that enchants [[Tools]] (tools are enchanted at the [[Anvil]] instead).

## Status
- [x] **[[Editions/Sharpness|Sharpness]]** — Combat lane (Sharpness book → card)
- [x] **[[Unbreaking]]** — Protection lane (Durability book → card)
- [x] **[[Lucky]]** — Loot lane (Fortune book → card)
- [ ] **Ender** (deferred)

[[Overview|← Back to Overview]] · see [[Enchanting]]
