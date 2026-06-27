"""Generate the resource sprite sheets from the genuine 16x16 Minecraft textures.

Source textures live in `assets/reference/resources/<id>.png` (downloaded from the
PrismarineJS minecraft-assets mirror; oak_planks/cobblestone/coal/iron_ingot/
gold_ingot/diamond/emerald/stick/lapis_lazuli). Both sheets (1x + 2x) are written here.

Outputs:
  assets/1x/resource_icons.png  -> 34x34 cells, 3x7 grid (102x238)
  assets/1x/resource_cards.png  -> 71x95 cells, 3x7 grid (213x665)
Order is row-major and MUST match content/resources/registry.lua `pos` values: the 10 ores +
sticks, then the Wave-1 archery drops (string/feather/flint), the Wave-2 Night/Cave drops
(gunpowder/bone/spider_eye/glow_ink_sac), then the raw ores (raw_iron/raw_gold). 19 resources in a
3x7 grid (last 2 cells free). NB: keep ROWS=7 -- shrinking it would truncate raw_iron/raw_gold.

The ICON sheet is the bare texture scaled 2x (nearest-neighbor), centered in each cell --
frameless, for clean readability in the hotbar/recipe/villager UIs. The CARD sheet (booster
pack art) keeps its tier-coloured face.
"""
import os
from PIL import Image
from utils import scale_image

ICON = 34
CARD_W, CARD_H = 71, 95
COLS, ROWS = 3, 7       # 19 resources -> 7 rows (raw_iron fills cell 17, raw_gold opens row 6; cells 19-20 free)
ICON_ROWS = 7

CARD_BG   = (40, 44, 52, 255)
TIER_TINT = {1: (90, 110, 90, 255), 2: (110, 100, 70, 255), 3: (70, 110, 130, 255), 4: (95, 60, 75, 255)}

_HERE = os.path.dirname(os.path.abspath(__file__))
_REF = os.path.normpath(os.path.join(_HERE, "..", "..", "assets", "reference", "resources"))

# Row-major order MUST match content/resources/registry.lua positions.
# Indices 10-12 (string, feather, flint) are the Wave 1 Archery mob drops.
# Indices 13-16 (gunpowder, bone, spider_eye, glow_ink_sac) are the Wave 2 Night/Cave mob drops.
ORDER = ["wood", "cobblestone", "coal", "iron", "gold", "diamond", "sticks", "emerald", "netherite", "lapis",
         "string", "feather", "flint",
         "gunpowder", "bone", "spider_eye", "glow_ink_sac",
         "raw_iron", "raw_gold"]   # MC-faithful smelt set: drop raw, smelt to iron/gold
TIERS = {"wood": 1, "cobblestone": 1, "coal": 1, "iron": 2, "gold": 2, "diamond": 3, "sticks": 1, "emerald": 2, "netherite": 4, "lapis": 3,
         "string": 1, "feather": 1, "flint": 1,
         "gunpowder": 1, "bone": 1, "spider_eye": 1, "glow_ink_sac": 1,
         "raw_iron": 2, "raw_gold": 2}


def load(rid):
    return Image.open(os.path.join(_REF, rid + ".png")).convert("RGBA")


def nn(img, factor):
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


def build_icons():
    # Frameless: each texture scaled 2x (16 -> 32, crisp nearest-neighbor) and centered in its
    # 34x34 cell (a 1px transparent margin). Cell size + grid are unchanged, so the registry
    # `pos` values and the bc_resource_icons atlas (px=py=34) need no edits.
    sheet = Image.new("RGBA", (ICON * COLS, ICON * ICON_ROWS), (0, 0, 0, 0))
    for i, rid in enumerate(ORDER):
        cx, cy = (i % COLS) * ICON, (i // COLS) * ICON
        block = nn(load(rid), 2)
        ox = cx + (ICON - block.width) // 2
        oy = cy + (ICON - block.height) // 2
        sheet.alpha_composite(block, (ox, oy))
    sheet.save("BalaCraft/assets/1x/resource_icons.png")
    scale_image("BalaCraft/assets/1x/resource_icons.png", "BalaCraft/assets/2x/resource_icons.png", 2)
    print("wrote resource_icons.png", sheet.size)


def build_emerald_plain():
    # Bare, frameless emerald (the genuine 16x16 texture) for the villager UI's
    # emerald counter + prices -- no tag badge, no neutral backdrop.
    em = load("emerald")
    em.save("BalaCraft/assets/1x/emerald_plain.png")
    scale_image("BalaCraft/assets/1x/emerald_plain.png", "BalaCraft/assets/2x/emerald_plain.png", 2)
    print("wrote emerald_plain.png", em.size)


def build_lapis_plain():
    # Bare, frameless lapis (the genuine 16x16 texture) for the enchant bar's cost line --
    # no tag badge, no neutral backdrop (mirrors emerald_plain for the villager UI).
    la = load("lapis")
    la.save("BalaCraft/assets/1x/lapis_plain.png")
    scale_image("BalaCraft/assets/1x/lapis_plain.png", "BalaCraft/assets/2x/lapis_plain.png", 2)
    print("wrote lapis_plain.png", la.size)


def build_cards():
    sheet = Image.new("RGBA", (CARD_W * COLS, CARD_H * ROWS), (0, 0, 0, 0))
    for i, rid in enumerate(ORDER):
        cx, cy = (i % COLS) * CARD_W, (i // COLS) * CARD_H
        face = Image.new("RGBA", (CARD_W, CARD_H), CARD_BG)
        tint = TIER_TINT[TIERS[rid]]
        for x in range(CARD_W):  # top tier-coloured band
            for y in range(6):
                face.putpixel((x, y), tint)
        block = nn(load(rid), 3)  # 16 -> 48
        face.alpha_composite(block, ((CARD_W - 48) // 2, (CARD_H - 48) // 2 - 4))
        sheet.alpha_composite(face, (cx, cy))
    sheet.save("BalaCraft/assets/1x/resource_cards.png")
    scale_image("BalaCraft/assets/1x/resource_cards.png", "BalaCraft/assets/2x/resource_cards.png", 2)
    print("wrote resource_cards.png", sheet.size)


if __name__ == "__main__":
    build_icons()
    build_emerald_plain()
    build_lapis_plain()
    build_cards()
