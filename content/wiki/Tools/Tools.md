xImplemented: 4 tool types (15 cards + Torch)

---

Tools are **craft-only consumable cards**. They never roll in the shop — you make them at the 3×3 [[Crafting]] table from ores and [[Sticks]]. They *do* appear in the collection.

Each of the three crafted tools comes in **5 material tiers** (Wooden → Stone → Iron → Golden → Diamond); the material decides how strong the effect is and what it costs. The fourth tool, the Torch, is a single utility card.

| Tool | What it does | Variants |
| --- | --- | --- |
| [[Sword]] | ×Mult on every hand for the rest of the Blind | 5 materials |
| [[Pickaxe]] | Gather extra ore when you beat the next blind | 5 materials |
| [[Shovel]] | Earn extra $ when you beat the next blind | 5 materials |
| [[Torch]] | Peek the shop's next rerolls & pack contents | 1 |

## How tools work
- **Craft-only** — `shop_rate = 0`, so they can't be bought; craft them (see [[Crafting]]).
- **Persistent & multi-use** — a tool stays in your consumable slots and has a **Uses** budget set by its material (Wooden 1 → Diamond 4). Using it spends one Use; at **0 Uses it breaks** (disappears). You can use a tool **once per Blind**, and only **during a blind**.
- **One per type per Blind** — at most one **Sword**, one **Pickaxe**, and one **Shovel** each Blind. You can combine across types (e.g. a Sword + a Pickaxe), but not two of the same type.
- **Sword** applies a scoring multiplier for the rest of the current blind (resets next blind). **Pickaxe** and **Shovel** *arm a one-shot* that pays out the next time you defeat a blind.
- **Enchantable** — apply [[Enchanting Books]] to boost a tool's effect (Sharpness), raise its Uses (Durability), or add bonus loot (Fortune). See [[Enchanting]].
- Tool cards currently reuse their **material's ore card art** as a placeholder (so all three Diamond tools look like the Diamond card for now); enchanted tools get a purple glint + tier pips.
- *(Planned)* the **[[Pickaxe]]** will be rescoped to boost ore **mined from [[Enhancements|Ore Blocks]]** rather than blind-defeat drops.

[[New mechanics|← Back to mechanics]]
