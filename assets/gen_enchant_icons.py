"""Generate the enchant-book *icon* sheet for the villager (Librarian) shop offers.

Each enchant TYPE (Sharpness/Durability/Fortune) is the genuine 16x16 Minecraft enchanted-book
sprite scaled 2x (nearest-neighbor) and centered in its 34x34 cell -- FRAMELESS, matching the
resource and tool icons (gen_resources.py / gen_tool_icons.py). Source sprites:
assets/reference/enchant_books/{sharpness,unbreaking,fortune}.png.

This is SEPARATE from the 71x95 enchant *cards* (bc_enchant_cards). This 34x34 sheet is only the
small icon shown in the villager shop.

Output (1x + 2x):
  assets/1x/enchant_icons.png -> 34x34 cells, 3 cols (tier I/II/III) x 3 rows (type) = 102x102

Grid order MUST match the book `pos = { x = tier-1, y = type_index-1 }` map in
content/enhancements/registry.lua (PB_UTIL.ENCHANT_ORDER):
  row 0 = sharpness, row 1 = durability, row 2 = fortune.
The glyph only varies by TYPE (tier is shown by the offer label), so each row repeats its glyph
across all three tier columns.
"""
import os
from PIL import Image
from utils import scale_image

CELL = 34
# Row order = PB_UTIL.ENCHANT_ORDER. Durability reuses the "unbreaking" book sprite.
TYPES = ["sharpness", "durability", "fortune"]
SPRITE = {"sharpness": "sharpness", "durability": "unbreaking", "fortune": "fortune"}

_HERE = os.path.dirname(os.path.abspath(__file__))
_REF = os.path.normpath(os.path.join(_HERE, "..", "..", "assets", "reference", "enchant_books"))


def nn(img, factor):
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


def centered(block):
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    cell.alpha_composite(block, ((CELL - block.width) // 2, (CELL - block.height) // 2))
    return cell


def type_cell(etype):
    spr = Image.open(os.path.join(_REF, f"{SPRITE[etype]}.png")).convert("RGBA")
    return centered(nn(spr, 2))   # 16 -> 32, frameless


def build():
    sheet = Image.new("RGBA", (CELL * 3, CELL * len(TYPES)), (0, 0, 0, 0))
    for row, etype in enumerate(TYPES):
        cell = type_cell(etype)
        for col in range(3):                                  # repeat across the 3 tiers
            sheet.alpha_composite(cell, (col * CELL, row * CELL))
    sheet.save("BalaCraft/assets/1x/enchant_icons.png")
    scale_image("BalaCraft/assets/1x/enchant_icons.png", "BalaCraft/assets/2x/enchant_icons.png", 2)
    print("wrote enchant_icons.png", sheet.size, "(frameless; row=type, col=tier)")


if __name__ == "__main__":
    build()
