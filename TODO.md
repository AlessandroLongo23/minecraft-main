# BalaCraft — TODO

Issues surfaced while documenting the wiki (2026-06-19). File:line references point at the source of truth.

## Bugs / behavior ↔ tooltip mismatches
- [ ] **Silverfish runs backwards.** Tooltip says the score requirement *increases* by ×1.5 each hand, but `press_play` animates it *down* to `chips * 1.15` (a reduction). Decide the intended behavior and fix the code or the text. — `content/blinds/silverfish.lua:8,23`
- [ ] **Overworld Deck grants the wrong joker.** Description says *"Start with a Waterdrop Joker"* but `apply` calls `joker_add('j_balacraft_0164')` (the 0.164% joker). Pick one and make them match. — `content/decks/overworld.lua:17,24`
- [ ] **Blaze targets the wrong cards (confirm).** Tooltip: *"each card in played hand"*; code rolls the 1-in-5 destroy on the cards left in `G.hand` after scoring, not the played cards. Reconcile wording vs. target. — `content/blinds/blaze.lua`
- [ ] **0.164% joker cost.** No `cost` set, so it defaults to $3 (old design implied it should be free/$0). Confirm intended cost. — `content/jokers/0164.lua`

## Incomplete content (stubs)
- [ ] **Biome-exclusive bosses have no mechanic.** The Overgrowth / Magma Lord / Ender Sentinel are flavor + placeholder art only — they gate to their biome and drop resources but do nothing on play. Design + implement effects. — `content/blinds/{forest_guardian,magma_lord,ender_sentinel}.lua`
- [ ] **XP spending / enchanting not implemented.** XP is earned and levels up, but there's no `spend_xp`/`spend_level` and no enchanting mechanic to spend it on (see [[Experience]] page). — `utilities/xp.lua`

## Placeholder art
- [ ] **Bosses with no dedicated sprite** (render the base-game blind chip): Wither Skeleton, Piglin, Hoglin, Guardian, Shulker, Witch, Four Horsemen (+ the 3 biome bosses above). Add art rows to `assets/blinds.png`.
- [ ] **Tool cards reuse their material's ore card.** All three Diamond tools show the Diamond card, etc. Make a `bc_tool_cards` atlas + `gen_tools.py`. — `content/tools/tool_consumabletype.lua`
- [ ] **Torch reuses the Coal card.** Needs real torch art. — `content/tools/torch.lua`
- [ ] **All 6 enabled jokers share `menace.png`.** Each needs its own art.
- [ ] **Biome selection posters are procedural placeholders.** Real pixel-art scenes are a later task. — `assets/gen_biomes.py`

## Cleanup before release
- [ ] **Plains Deck starts with 2 Torches** — flagged in-code as a dev/testing convenience; remove for release. — `content/decks/biome_decks.lua`

## Verified OK (no action)
- Sword tool's `sword_xmult` *is* applied during scoring via the `lovely.toml` patch (`lovely.toml:82-83`) — the multiplier works despite not being read in `utilities/resources.lua`.
