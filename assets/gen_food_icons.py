"""Generate the food *icon* sheet for the villager (Farmer) shop offers.

Each food is the genuine 16x16 Minecraft item sprite scaled 2x (nearest-neighbor) and centered in
its 34x34 cell -- FRAMELESS, matching the resource and tool icons. Source sprites:
assets/reference/food/<id>.png.

This is SEPARATE from the 71x95 food *cards* (bc_food_cards). This 34x34 sheet is only the small
icon shown in the villager shop.

Output (1x + 2x):
  assets/1x/food_icons.png -> 34x34 cells, 3 cols x 2 rows = 102x68

Grid order MUST match each food's `pos` in content/foods/registry.lua:
  carrot {0,0}  potato {1,0}  apple {2,0}
  baked_potato {0,1}  cooked_chicken {1,1}  cooked_porkchop {2,1}
"""
import os
from PIL import Image
from utils import scale_image

CELL = 34
COLS, ROWS = 3, 2
# id -> (col, row) cell; MUST match content/foods/registry.lua pos.
FOODS = {
    "carrot": (0, 0), "potato": (1, 0), "apple": (2, 0),
    "baked_potato": (0, 1), "cooked_chicken": (1, 1), "cooked_porkchop": (2, 1),
}

_HERE = os.path.dirname(os.path.abspath(__file__))
_REF = os.path.normpath(os.path.join(_HERE, "..", "..", "assets", "reference", "food"))


def nn(img, factor):
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


def centered(block):
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    cell.alpha_composite(block, ((CELL - block.width) // 2, (CELL - block.height) // 2))
    return cell


def food_cell(fid):
    spr = Image.open(os.path.join(_REF, f"{fid}.png")).convert("RGBA")
    return centered(nn(spr, 2))   # 16 -> 32, frameless


def build():
    sheet = Image.new("RGBA", (CELL * COLS, CELL * ROWS), (0, 0, 0, 0))
    for fid, (col, row) in FOODS.items():
        sheet.alpha_composite(food_cell(fid), (col * CELL, row * CELL))
    sheet.save("BalaCraft/assets/1x/food_icons.png")
    scale_image("BalaCraft/assets/1x/food_icons.png", "BalaCraft/assets/2x/food_icons.png", 2)
    print("wrote food_icons.png", sheet.size, "(frameless)")


if __name__ == "__main__":
    build()
