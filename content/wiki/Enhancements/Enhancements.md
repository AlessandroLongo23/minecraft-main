Implemented: 3 / 3 — Lapis · Ore Blocks · Obsidian

---

Enhancements change a playing card's **body** (vanilla: Bonus / Mult / Wild / Glass / Steel / Stone /
Gold / Lucky). Balatro's Stone/Glass/Steel/Gold cards are *already* Minecraft blocks, so BalaCraft
leans in: its enhancements are **block-cards**, each tied to a subsystem.

The base game's enhancements still work normally; these are **added** alongside them. Note these are
*card enhancements*, distinct from two neighbouring systems:
- **[[Sheets]]** are the *consumables that apply* an enhancement to a card (e.g. the [[Sheets|Lapis Sheet]]) — like vanilla enhancement Tarots.
- **[[Editions]]** are the shiny *glints* on top of a card (Sharpness / Unbreaking / Lucky), a separate layer.

| Enhancement | MC block | Effect | How you get it |
| --- | --- | --- | --- |
| [[Lapis]] | lapis block | +[[Experience\|XP]] each time it's played | the [[Sheets\|Lapis Sheet]] |
| [[Ore Blocks]] | ore blocks | **mine the ore with a [[Pickaxe]] / [[Axe]]** | **spawn on your deck cards** (not a Tarot) |
| [[Obsidian Block]] | obsidian | an [[Ore Blocks\|Ore Block]] — mine it for [[Resources/Obsidian\|Obsidian]] | spawns on deck cards; **Diamond [[Pickaxe]] only** |

## Applying enhancements
[[Lapis]] is applied by a **[[Sheets|Lapis Sheet]]** — a consumable you forge from ore at the Anvil and
apply to a selected card (the same UX vanilla enhancement Tarots have).

**[[Ore Blocks]] (and [[Obsidian Block]]) are different:** they are **not** applied by sheets or tarots. They
**spawn naturally on cards in your deck** when a blind is selected, scaling with your [[Biomes|biome]]
and ante, and you **[[Mining|mine]]** them by Using a [[Pickaxe]] (or, for wood, an [[Axe]]) on the
highlighted card. See [[Ore Blocks]] for the full mechanic.

> A card can only hold **one** enhancement — Ore Blocks never spawn on a card that already has one.

## Status
- [x] **[[Lapis]]** — XP lane ([[Sheets|Lapis Sheet]])
- [x] **[[Ore Blocks]]** — Resources lane (natural spawn, [[Pickaxe]]/[[Axe]]-mined)
- [x] **[[Obsidian Block]]** — an Ore Block, Diamond-[[Pickaxe]]-only

[[Overview|← Back to Overview]]
