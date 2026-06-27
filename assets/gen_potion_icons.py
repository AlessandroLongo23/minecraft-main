#!/usr/bin/env python3
"""Generate the small potion-ICON sheet (assets/1x/potion_icons.png + 2x), atlas `bc_potion_icons`
(34x34 cells).

The SAME authentic 16x16 MC bottle textures used by gen_potion_cards.py
(assets/reference/potions/<id>.png) are scaled 2x (nearest-neighbor) and centred frameless in each
34x34 cell -- matching the resource-icon look of the water/awkward bottles, so the Brewing Stand
bottle slot + recipe list read consistently. ONE source sprite per potion: used here as the icon and
(at 3x) embedded in the potion card by gen_potion_cards.py.

Row-major ORDER MUST match content/potions/registry.lua PB_UTIL.POTIONS (and gen_potion_cards.py):
8 potions in a 4-col x 2-row grid. Atlas cell -> (i % 4, i // 4).

Run from Mods/:  python BalaCraft/assets/gen_potion_icons.py
"""
import os
from PIL import Image
from utils import scale_image

ICON = 34
COLS = 4

HERE = os.path.dirname(os.path.abspath(__file__))            # BalaCraft/assets
MODS = os.path.normpath(os.path.join(HERE, "..", ".."))      # Mods/
REF  = os.path.join(MODS, "assets", "reference", "potions")

ORDER = ["swiftness", "strength", "instant_health", "healing",
         "night_vision", "invisibility", "poison", "harming"]


def load(pid):
    return Image.open(os.path.join(REF, pid + ".png")).convert("RGBA")


def nn(img, factor):
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


def build_icons():
    rows = (len(ORDER) + COLS - 1) // COLS
    sheet = Image.new("RGBA", (ICON * COLS, ICON * rows), (0, 0, 0, 0))
    for i, pid in enumerate(ORDER):
        cx, cy = (i % COLS) * ICON, (i // COLS) * ICON
        block = nn(load(pid), 2)   # 16 -> 32, crisp nearest-neighbor
        ox = cx + (ICON - block.width) // 2
        oy = cy + (ICON - block.height) // 2
        sheet.alpha_composite(block, (ox, oy))
    sheet.save("BalaCraft/assets/1x/potion_icons.png")
    scale_image("BalaCraft/assets/1x/potion_icons.png", "BalaCraft/assets/2x/potion_icons.png", 2)
    print("wrote potion_icons.png", sheet.size)


if __name__ == "__main__":
    build_icons()
