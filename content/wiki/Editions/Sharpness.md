*Edition — the card side of the dual-target Sharpness book*

| Attribute | Value |
| --- | --- |
| Lane | Combat |
| Applied by | the dual-target [[Enchanting Books/Sharpness\|Sharpness book]] (highlight a card in hand + the book → **Enchant Card**) |
| Apply cost | `book tier + 1` [[Experience\|levels]] (I = 2, II = 3, III = 4) |
| Internal key | `e_balacraft_sharpness_1` / `_2` / `_3` |

## Effect
A card with the **Sharpness** glint gives **+Mult** when it scores, **doubled against a boss (mob)
[[New Bosses|blind]]**. It scales with the book's tier:

| Tier | +Mult | vs Boss |
| --- | --- | --- |
| Sharpness I | +10 | +20 |
| Sharpness II | +15 | +30 |
| Sharpness III | +20 | +40 |

The MC enchantment that adds damage, turned into a card edition that hits hardest against mobs.

## Notes
- Applied via the [[Enchanting]] flow: select the card + the Sharpness book, click **Enchant Card**,
  spend levels. Gated by the [[Enchanting Table]] voucher.
- The applier is the **dual-target [[Enchanting Books/Sharpness|Sharpness book]]**: on a **tool** it
  gives ×Mult, on a **card** it applies this Sharpness edition (+Mult). One book, two targets.
- Boss check is the same signal jokers use (`G.GAME.blind.boss`).
- Editions are mutually exclusive — a card holds one of Sharpness / Unbreaking / Lucky at a time.

[[Editions|← Back to Editions]]
