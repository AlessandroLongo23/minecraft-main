"""Generate per-entry sprite PNGs for the Obsidian wiki.

Crops the game's sprite atlases (assets/2x/*) into one image per wiki entry and
copies the standalone single-frame sprites, writing everything to
content/wiki/_img/ so each wiki page can embed `![[name.png|120]]`.

The crop maps below mirror the `pos` fields in the Lua registries
(content/resources/registry.lua, content/potions/registry.lua,
content/sheets/registry.lua, content/tools/registry.lua). When you add a
registry row, add a matching entry here and re-run.

Deterministic, no RNG. Re-run after art changes:  python assets/gen_wiki_sprites.py
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "2x")            # use the 2x sheets for crispness
BOSS_SRC = os.path.join(HERE, "source", "bosses")  # standalone boss sprites (not shipped atlases)
OUT = os.path.normpath(os.path.join(HERE, "..", "content", "wiki", "_img"))
os.makedirs(OUT, exist_ok=True)

# 2x cell sizes are double the atlas px/py declared in the Lua.
def crop_grid(sheet_name, cell_w, cell_h, cells, scale=1):
    """cells = { out_name: (col, row) }. Crops from assets/2x/<sheet_name>."""
    path = os.path.join(SRC, sheet_name)
    if not os.path.exists(path):
        print("SKIP (missing sheet):", sheet_name)
        return
    sheet = Image.open(path).convert("RGBA")
    cols = sheet.width // cell_w
    rows = sheet.height // cell_h
    for name, (col, row) in cells.items():
        if col >= cols or row >= rows:
            print("SKIP (out of range):", name, (col, row))
            continue
        box = (col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h)
        cell = sheet.crop(box)
        if scale != 1:
            cell = cell.resize((cell.width * scale, cell.height * scale), Image.NEAREST)
        cell.save(os.path.join(OUT, name + ".png"))
        print("crop", name)

def copy_single(src_name, out_name, scale=2, src_dir=SRC):
    src = os.path.join(src_dir, src_name)
    if not os.path.exists(src):
        print("SKIP (missing):", src_name)
        return
    img = Image.open(src).convert("RGBA")
    if scale != 1:
        img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    img.save(os.path.join(OUT, out_name + ".png"))
    print("copy", out_name)

# --- Boss single-frame sprites (standalone files; sourced from assets/source/bosses/) ---
BOSS_SINGLES = {
    "boss_creeper": "bossCreeperSingle.png",
    "boss_skeleton": "bossSkeletonSingle.png",
    "boss_zombie": "bossZombieSingle.png",
    "boss_enderman": "bossEndermanSingle.png",
    "boss_spider": "bossSpiderSingle.png",
    "boss_blaze": "bossBlazeSingle.png",
    "boss_drowned": "bossDrownedSingle.png",
    "boss_ghast": "bossGhastSingle.png",
    "boss_zombiepigman": "bossZombiepigmanSingle.png",
    "boss_magmacube": "bossMagmacubeSingle.png",
    "boss_slime": "bossSlimeSingle.png",
    "boss_silverfish": "bossSilverfishSingle.png",
    "boss_husk": "bossHuskSingle.png",
    "boss_phantom": "bossPhantomSingle.png",
    "boss_stray": "bossStraySingle.png",
}
for out, src in BOSS_SINGLES.items():
    copy_single(src, out, scale=2, src_dir=BOSS_SRC)

# --- Resource cards (2x cell = 142x190; 71x95 grid, 3 cols x 16 rows) ---
# Mirrors PB_UTIL.RESOURCES `pos` in content/resources/registry.lua.
RES_POS = {
    "wood": (0, 0), "cobblestone": (1, 0), "coal": (2, 0),
    "iron": (0, 1), "gold": (1, 1), "diamond": (2, 1),
    "emerald": (1, 2), "netherite": (2, 2), "sticks": (0, 2),
    "lapis": (0, 3), "string": (1, 3), "feather": (2, 3),
    "flint": (0, 4), "gunpowder": (1, 4), "bone": (2, 4),
    "spider_eye": (0, 5), "glow_ink_sac": (1, 5),
    "raw_iron": (2, 5), "raw_gold": (0, 6), "redstone": (1, 6),
    "sand": (2, 6), "glass": (0, 7), "obsidian": (1, 7),
    "ender_pearl": (2, 7), "blaze_powder": (0, 8),
    "nether_wart": (1, 8), "sugar_cane": (2, 8), "melon_slice": (0, 9),
    "carrot": (1, 9), "brown_mushroom": (2, 9), "ghast_tear": (0, 10),
    "blaze_rod": (1, 10), "glowstone_dust": (2, 10), "dragon_breath": (0, 11),
    "glass_bottle": (1, 11), "water_bottle": (2, 11), "sugar": (0, 12),
    "glistering_melon": (1, 12), "golden_carrot": (2, 12),
    "fermented_spider_eye": (0, 13), "awkward_potion": (1, 13),
    "leather": (2, 13), "paper": (0, 14), "book": (1, 14),
    "dandelion": (2, 14), "poppy": (0, 15), "cornflower": (1, 15),
    "oxeye_daisy": (2, 15),
}
crop_grid("resource_cards.png", 142, 190, {"res_" + k: v for k, v in RES_POS.items()})
crop_grid("resource_icons.png", 68, 68, {"icon_" + k: v for k, v in RES_POS.items()}, scale=2)

# --- Potion cards (2x cell = 142x190; 71x95 grid, 4 cols x 8 rows). Column 0 = base (Level I). ---
# Mirrors PB_UTIL.POTIONS `pos` in content/potions/registry.lua (one row per potion).
POTION_ROW = {
    "swiftness": 0, "strength": 1, "instant_health": 2, "healing": 3,
    "night_vision": 4, "invisibility": 5, "poison": 6, "harming": 7,
}
crop_grid("potion_cards.png", 142, 190, {"potion_" + k: (0, r) for k, r in POTION_ROW.items()})

# --- Sheet cards (2x cell = 142x190; 71x95 grid, 3 cols x 3 rows) ---
# Mirrors PB_UTIL.SHEETS `pos` in content/sheets/registry.lua.
SHEET_POS = {
    "gold": (0, 0), "iron": (1, 0), "glass": (2, 0),
    "diamond": (0, 1), "emerald": (1, 1), "redstone": (2, 1),
    "lapis": (0, 2), "coal": (1, 2),
}
crop_grid("sheet_cards.png", 142, 190, {"sheet_" + k: v for k, v in SHEET_POS.items()})

# --- Tool cards (2x cell = 142x190). Combined bc_tools sheet: 11 durability frames (cols) x 24
# rows. Column 0 = full durability. Row = atlas_row: swords 0..5, pickaxes 6..11, shovels 12..17,
# axes 18..23; materials within each block are wood, cobblestone(stone), iron, gold, diamond,
# netherite (tier 1..6). Mirrors content/tools/registry.lua. ---
TOOL_TYPES = ["sword", "pickaxe", "shovel", "axe"]
TOOL_MATS = ["wood", "cobblestone", "iron", "gold", "diamond", "netherite"]
TOOL_CELLS = {}
for ti, tool in enumerate(TOOL_TYPES):
    for mi, mat in enumerate(TOOL_MATS):
        TOOL_CELLS["tool_%s_%s" % (tool, mat)] = (0, ti * 6 + mi)
crop_grid("tools.png", 142, 190, TOOL_CELLS)

# --- One-shot tool/utility consumable cards (standalone 2x card images = 142x190 already) ---
for name in ["torch", "arrow", "bone_meal", "tnt", "firework", "flint_and_steel", "ender_eye"]:
    copy_single(name + ".png", "tool_" + name, scale=1)

# --- Food cards (2x cell = 142x190; 3x3 grid) ---
crop_grid("food_cards.png", 142, 190, {
    "food_carrot": (0, 0), "food_potato": (1, 0), "food_apple": (2, 0),
    "food_baked_potato": (0, 1), "food_cooked_chicken": (1, 1),
    "food_cooked_porkchop": (2, 1),
})

# --- Joker placeholder (enabled jokers without bespoke art share menace.png cell 0,0) ---
crop_grid("menace.png", 142, 190, {"joker_placeholder": (0, 0)})

# --- Vouchers (2x cell = 142x190). NOTE: the Nether/End Portal vouchers were removed from the mod;
# these crops are kept only so any legacy reference still resolves. ---
crop_grid("voucher_cards.png", 142, 190, {
    "voucher_nether_portal": (0, 0), "voucher_end_portal": (1, 0),
})

# --- Biome selection cards (2x cell = 180x300; 90x150 grid) ---
crop_grid("biome_cards.png", 180, 300, {
    # row 0: overworld
    "biome_plains": (0, 0), "biome_forest": (1, 0), "biome_desert": (2, 0),
    "biome_snowy_taiga": (3, 0), "biome_jungle": (4, 0), "biome_swamp": (5, 0),
    "biome_savanna": (6, 0), "biome_badlands": (7, 0),
    # row 1: nether
    "biome_nether_wastes": (0, 1), "biome_crimson_forest": (1, 1),
    "biome_soul_sand_valley": (2, 1), "biome_basalt_deltas": (3, 1),
    # row 2: end
    "biome_central_end": (0, 2), "biome_end_highlands": (1, 2),
    "biome_end_midlands": (2, 2), "biome_end_barrens": (3, 2),
})

# --- Deck backs (standalone) + biome-deck sheet + mechanic bars ---
copy_single("OverworldDeck.png", "deck_overworld", scale=2)
copy_single("NetherDeck.png", "deck_nether", scale=2)
copy_single("EndDeck.png", "deck_end", scale=2)
copy_single("biome_decks.png", "deck_biomes_sheet", scale=2)
copy_single("hearts.png", "hearts", scale=3)
copy_single("hunger.png", "hunger", scale=3)
copy_single("xp_bar.png", "xp_bar", scale=3)

print("\nDone ->", OUT)
