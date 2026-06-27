*Overworld boss blind*

![[boss_silverfish.png|120]]

| Attribute | Value |
| --- | --- |
| Appears from | Ante 1 |
| Score requirement | Shifts after every played hand (see below) |
| Resource drop | Tier-roll (2× of a random ore, tier scales with ante) |
| Mob attack | 2 ♥ (1 heart) on a failed hand |
| Internal key | `bl_balacraft_silverfish` |

## Effect
**Intended:** after every hand you play, the remaining score requirement *increases* by ×1.5 — punishing slow, multi-hand wins.

> ⚠️ **Known discrepancy:** in the current build the code actually *reduces* the requirement to ×1.15 after each hand (the opposite direction and a different factor than the tooltip describes). This is a bug to reconcile — the wiki tracks the tooltip's intended behavior.

[[New Bosses|← Back to Bosses]]
