"""Generate per-entry sprite PNGs for the Obsidian wiki.

Crops the game's sprite atlases (assets/2x/*) into one image per wiki entry and
copies the standalone single-frame sprites, writing everything to
content/wiki/_img/ so each wiki page can embed `![[name.png|120]]`.

Deterministic, no RNG. Re-run after art changes:  python assets/gen_wiki_sprites.py
"""
import os
import shutil
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
    sheet = Image.open(path).convert("RGBA")
    for name, (col, row) in cells.items():
        box = (col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h)
        cell = sheet.crop(box)
        if scale != 1:
            cell = cell.resize((cell.width * scale, cell.height * scale), Image.NEAREST)
        cell.save(os.path.join(OUT, name + ".png"))
        print("crop", name)

def copy_single(src_name, out_name, scale=2, src_dir=SRC):
    src = os.path.join(src_dir, src_name)
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

# --- Resource cards (2x cell = 142x190; 71x95 grid, 3 cols) ---
crop_grid("resource_cards.png", 142, 190, {
    "res_wood": (0, 0), "res_cobblestone": (1, 0), "res_coal": (2, 0),
    "res_iron": (0, 1), "res_gold": (1, 1), "res_diamond": (2, 1),
    "res_sticks": (0, 2),
    "res_emerald": (1, 2),
    "res_netherite": (2, 2),
    "res_lapis": (0, 3),
    "res_string": (1, 3), "res_feather": (2, 3), "res_flint": (0, 4),
})

# --- Resource icons (2x cell = 68x68) -- small hotbar icons ---
crop_grid("resource_icons.png", 68, 68, {
    "icon_wood": (0, 0), "icon_cobblestone": (1, 0), "icon_coal": (2, 0),
    "icon_iron": (0, 1), "icon_gold": (1, 1), "icon_diamond": (2, 1),
    "icon_sticks": (0, 2),
    "icon_emerald": (1, 2),
    "icon_netherite": (2, 2),
    "icon_lapis": (0, 3),
    "icon_string": (1, 3), "icon_feather": (2, 3), "icon_flint": (0, 4),
}, scale=2)

# --- Food cards (2x cell = 142x190) ---
crop_grid("food_cards.png", 142, 190, {
    "food_carrot": (0, 0), "food_potato": (1, 0), "food_apple": (2, 0),
    "food_baked_potato": (0, 1), "food_cooked_chicken": (1, 1),
    "food_cooked_porkchop": (2, 1),
})

# --- Joker placeholder (all 6 enabled jokers share menace.png cell 0,0) ---
crop_grid("menace.png", 142, 190, {"joker_placeholder": (0, 0)})

# --- Vouchers (2x cell = 142x190) ---
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
