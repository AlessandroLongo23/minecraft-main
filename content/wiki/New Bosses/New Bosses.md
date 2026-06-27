Implemented: 25 / 32

---

Every BalaCraft boss blind is a Minecraft mob. On top of its blind effect, two new systems interact with bosses:

- **Resource drops** — beating *any* blind grants resources. A few bosses have themed drops; the rest use a tier-roll that scales with the ante. See [[Resources]].
- **Mob attacks** — if you **play a hand against a boss and fail to beat it while you still have hands left**, the mob damages your [[Health|hearts]]. Your *final* failed hand resolves as a normal game-over instead (so the attack only bites when you have hands to spare).

**Ante note:** a boss becomes eligible from its **minimum ante** onward — the engine ignores the upper bound. The boss pool cycles least-recently-used first.

**Art note:** several bosses don't have finished art yet and render with the base-game blind-chip sprite as a placeholder (marked below).

## Overworld
- [x] [[Creeper|The Creeper]] — destroy a random joker if you win on the last hand
- [x] [[Drowned|The Drowned]] — each discard also discards a random card
- [x] [[Enderman|The Enderman]] — pins a random joker to the leftmost slot
- [x] [[Skeleton|The Skeleton]] — after scoring, destroy a random card in hand
- [x] [[Zombie|The Zombie]] — after beating it, the leftmost joker becomes Perishable
- [x] [[Spider|The Spider]] — debuff all enhanced cards
- [x] [[Stray|The Stray]] — Mult capped at your previous hand's Mult
- [x] [[Husk|The Husk]] — lose $2 per discard
- [x] [[Phantom|The Phantom]] — ×3 requirement if you skipped no blind this ante
- [x] [[Slime|The Slime]] — after beating it, next ante's blinds are pumped
- [x] [[Silverfish]] — requirement shifts after every hand
- [x] [[Guardian|The Guardian]] — destroys cards left in hand too long *(placeholder art)*
- [x] [[Witch|The Witch]] — shuffles your hands & discards *(placeholder art)*

## Nether
- [x] [[Blaze|The Blaze]] — after scoring, 1-in-5 chance to destroy each card in hand
- [x] [[Ghast|The Ghast]] — 1-in-2 chance to destroy each card; a Straight wins instantly
- [x] [[Magma Cube|The Magma Cube]] — after beating it, next ante's Small Blind ×2
- [x] [[Zombie Pigman|The Zombie Pigman]] — after beating it, next ante's Small Blind ×2
- [x] [[Piglin|The Piglin]] — played cards become 2s if your deck lacks Gold cards *(placeholder art)*
- [x] [[Hoglin|The Hoglin]] — removes 3 hands/discards at round start *(placeholder art)*
- [x] [[Wither Skeleton|The Wither Skeleton]] — after scoring, destroy a consumable *(placeholder art)*

## End
- [x] [[Shulker|The Shulker]] — pay $ equal to your first hand's total rank *(placeholder art)*
- [x] [[Four Horsemen|The Four Horsemen]] — debuff cards, −1 hand, −1 discard, wipe consumables *(placeholder art)*

## Biome-exclusive
These only appear while you are in their biome (see [[Biomes]]). They are mechanically **inert stubs** for now — flavor + placeholder art, no special effect yet.
- [x] [[The Overgrowth]] — Forest biome only
- [x] [[Magma Lord]] — Basalt Deltas (Nether) only
- [x] [[Ender Sentinel]] — Central End only

## Planned / not yet enabled
- [ ] **Creaking** (Overworld)
- [ ] **Raid** (End) — 3-phase fight (×0.4 / ×0.8 / ×1.6); deferred, multi-phase needs its own design
- [ ] **Mansion**, **Elder Guardian**, **Warden**, **Wither**, **Ender Dragon**
