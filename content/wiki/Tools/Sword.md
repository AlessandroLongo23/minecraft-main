*Craft-only Tool — 6 material variants*

![[tool_sword_diamond.png|105]]

## Effect
When used, the Sword boosts **every hand for the rest of the current Blind**, then **resets at the start of the next Blind**. It's a **persistent, multi-use** tool: usable **once per Blind**, it spends one **Use** each time and **breaks** when it runs out. At most **one Sword** can be used per Blind (you can still pair it with a [[Pickaxe]], a [[Shovel]] and an [[Axe]]).

How it scales depends on the material:
- **Wooden → Golden** apply a **flat ×Mult** to every hand (×1.25 → ×4).
- **Diamond & Netherite** instead **raise your hand Mult to a power** (Diamond Mult^1.25, Netherite Mult^1.5). Exponents keep up with super-exponential late-game scores where a flat ×Mult would be trivial.

**Enchantable:** [[Enchanting Books/Sharpness\|Sharpness]] strengthens it — on flat swords it multiplies the ×Mult (×1.25 / ×1.5 / ×1.75 by tier); on Diamond/Netherite it deepens the exponent (+0.05 power per tier). [[Enchanting Books/Durability\|Durability]] raises its Uses. See [[Enchanting]].

## Variants
| Material | Art | Effect (rest of Blind) | Uses | Cost |
| --- | --- | --- | --- | --- |
| Wooden | ![[icon_wood.png\|24]] | ×1.25 Mult | 1 | $3 |
| Stone | ![[icon_cobblestone.png\|24]] | ×1.5 Mult | 2 | $4 |
| Iron | ![[icon_iron.png\|24]] | ×2 Mult | 3 | $5 |
| Golden | ![[icon_gold.png\|24]] | ×4 Mult | 3 | $6 |
| Diamond | ![[icon_diamond.png\|24]] | Mult to the ^1.25 power | 4 | $8 |
| Netherite | ![[icon_netherite.png\|24]] | Mult to the ^1.5 power | 5 | $10 |

Internal keys are `c_balacraft_tool_sword_<material>` (e.g. `c_balacraft_tool_sword_diamond`).

## How to get it
Craft it at the 3×3 [[Crafting]] table. Minecraft sword shape — **2 of the material stacked, with a [[Sticks|Stick]] below**:

```
. M .
. M .
. S .
```
(M = material ore, S = Stick.)

> **Netherite is the exception.** Like in Minecraft, the Netherite Sword can't be crafted at the table. Craft the **Diamond** Sword, then **upgrade** it at the [[Anvil]] → Upgrade tab (Diamond tool + 1 [[Netherite]] → Netherite tool). The upgrade keeps the tool's enchants and durability.

[[Tools|← Back to Tools]]
