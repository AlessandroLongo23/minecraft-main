*Overworld boss blind*

![[boss_drowned.png|120]]

| Attribute | Value |
| --- | --- |
| Appears from | Ante 2 |
| Score requirement | Standard boss (×2) |
| Resource drop | Tier-roll (2× of a random ore, tier scales with ante) |
| Mob attack | **3 ♥ (1.5 hearts)** on a failed hand |
| Internal key | `bl_balacraft_drowned` |

## Effect
**Whenever you use a discard, one additional random card from your remaining hand is discarded too.** So every discard costs you an extra card you didn't choose.

## Notes
- This effect is implemented through a source patch into the discard flow (it can't be expressed as a normal blind hook), so it fires in addition to your manual discard.

[[New Bosses|← Back to Bosses]]
