"""Generate the tool *icon* sheet for the crafting-table recipe list.

Each tool (3 tools x 6 materials = 18) is the genuine 16x16 Minecraft tool texture
scaled 2x (nearest-neighbor) and centered in its 34x34 cell -- FRAMELESS (no tag badge),
matching the frameless resource icons (see gen_resources.py). Source textures:
assets/reference/mc_tools/<tool>_<material>.png.

This is SEPARATE from the 71x95 tool *cards*. This 34x34 sheet is only for the small
recipe-list / output-preview icons.

Output (1x + 2x):
  assets/1x/tool_icons.png  -> 34x34 cells, 6 cols (material) x 4 rows (3 tools + torch) = 204x136

Grid order MUST match the `icon_pos` map in content/tools/tool_consumabletype.lua:
  row 0 = sword, row 1 = pickaxe, row 2 = shovel
  col   = wood, cobblestone, iron, gold, diamond, netherite
  torch -> row 3, col 0  ({x=0, y=3}), per content/tools/torch.lua tool_icon_pos.
"""
import os
from PIL import Image
from utils import scale_image

CELL = 34
TOOLS = ["sword", "pickaxe", "shovel"]                                   # rows
MATERIALS = ["wood", "cobblestone", "iron", "gold", "diamond", "netherite"]  # cols

_HERE = os.path.dirname(os.path.abspath(__file__))
_REF = os.path.normpath(os.path.join(_HERE, "..", "..", "assets", "reference", "mc_tools"))

# The torch texture is a thin 2x10 stick; it needs a bigger bump than the 2x tools to read.
TORCH_SCALE = 3


def nn(img, factor):
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


def centered(block):
    """A scaled sprite composited frameless and centered in a CELL x CELL transparent tile."""
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    cell.alpha_composite(block, ((CELL - block.width) // 2, (CELL - block.height) // 2))
    return cell


def load_sprite(tool, material):
    return Image.open(os.path.join(_REF, f"{tool}_{material}.png")).convert("RGBA")


def tool_cell(tool, material):
    return centered(nn(load_sprite(tool, material), 2))   # 16 -> 32, frameless


# Rows 3+ (below the 3 tool rows) = non-tool craftables, each its authentic 16x16 MC item texture.
# (filename in reference/mc_tools, col, row, scale, crop_to_bbox). The (col,row) MUST match the
# tool_icon_pos entries in: torch.lua, arrow.lua, bow/fishing_rod/crossbow jokers, bone_meal.lua,
# tnt.lua, firework.lua.
EXTRAS = [
    ("torch",          0, 3, TORCH_SCALE, True),   # thin stick -> bigger bump + tight crop
    ("bow",            1, 3, 2,           False),
    ("fishing_rod",    2, 3, 2,           False),
    ("crossbow",       3, 3, 2,           False),
    ("arrow",          4, 3, 2,           False),
    ("bone_meal",      5, 3, 2,           False),
    ("tnt",            0, 4, 2,           False),  # explosives cluster -> row 4
    ("firework_rocket",1, 4, 2,           False),
]


def extra_cell(name, scale, crop):
    spr = Image.open(os.path.join(_REF, name + ".png")).convert("RGBA")
    if crop:
        bb = spr.getbbox()
        if bb:
            spr = spr.crop(bb)
    return centered(nn(spr, scale))


def build():
    nrows = max(len(TOOLS), max(e[2] for e in EXTRAS) + 1)   # rows 0..2 tools + extras rows
    sheet = Image.new("RGBA", (CELL * len(MATERIALS), CELL * nrows), (0, 0, 0, 0))
    for row, tool in enumerate(TOOLS):
        for col, mat in enumerate(MATERIALS):
            sheet.alpha_composite(tool_cell(tool, mat), (col * CELL, row * CELL))
    for name, col, row, scale, crop in EXTRAS:
        sheet.alpha_composite(extra_cell(name, scale, crop), (col * CELL, row * CELL))
    sheet.save("BalaCraft/assets/1x/tool_icons.png")
    scale_image("BalaCraft/assets/1x/tool_icons.png", "BalaCraft/assets/2x/tool_icons.png", 2)
    print("wrote tool_icons.png", sheet.size, "(frameless; extras:", [(e[0], e[1], e[2]) for e in EXTRAS], ")")


if __name__ == "__main__":
    build()
