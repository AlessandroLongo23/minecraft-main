"""Build the hunger HUD spritesheet from the real Minecraft haunch icons.

Source art (downloaded from the Minecraft Wiki, 9x9 RGBA, consistent black outline):
  assets/reference/hunger/full.png   -- Hunger_(icon).png       (meat + bone)
  assets/reference/hunger/half.png   -- Half_Hunger_(icon).png  (left meat / right socket)
  assets/reference/hunger/empty.png  -- Empty_Hunger_(icon).png (dark socket)

The 4th "saturated" cell is the full haunch with a GOLD OUTLINE (goldify, below). Vanilla
Minecraft has no saturation texture -- it's an invisible stat; AppleSkin draws saturation as a
gold outline traced over the hunger drumstick, reproduced here faithfully by recoloring only the
icon's pure-black silhouette outline gold and keeping the meat/bone body. (An earlier version
tinted the whole body gold, which left red meat specks and read as muddy.) Shows banked over-eat
(see hunger_ui.lua).

Output: assets/1x/hunger.png -> 36x9  (four 9x9 cells: full {0,0}, half {1,0}, empty {2,0}, saturated {3,0})
        assets/2x/hunger.png -> 72x18
Cells are the haunch's native size, so the art fills the cell with no upscale blur.
Cell order MUST match utilities/hunger_ui.lua and the atlas there declares px = 9, py = 9.
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))           # BalaCraft/assets
MODS = os.path.normpath(os.path.join(HERE, "..", ".."))     # Mods/
REF  = os.path.join(MODS, "assets", "reference", "hunger")
OUT1 = os.path.join(HERE, "1x")
OUT2 = os.path.join(HERE, "2x")

CELL = 9
ORDER = ["full", "half", "empty"]   # loaded from reference PNGs
NCELLS = len(ORDER) + 1             # + the derived gold "saturated" cell

GOLD = (255, 205, 50)               # AppleSkin-style bright gold for the saturation outline


def load(k):
    return Image.open(os.path.join(REF, k + ".png")).convert("RGBA")


def goldify(img):
    """Recolor only the drumstick's pure-black silhouette OUTLINE to gold, keeping the meat/bone
    body intact -- AppleSkin draws saturation as a gold outline traced over the hunger drumstick."""
    out = img.copy()
    src, dst = img.load(), out.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = src[x, y]
            if a and r == 0 and g == 0 and b == 0:   # pure-black outline pixel -> gold
                dst[x, y] = (GOLD[0], GOLD[1], GOLD[2], a)
    return out


def build_sheet():
    sheet = Image.new("RGBA", (CELL * NCELLS, CELL), (0, 0, 0, 0))
    for i, k in enumerate(ORDER):
        sheet.alpha_composite(load(k), (i * CELL, 0))
    sheet.alpha_composite(goldify(load("full")), (len(ORDER) * CELL, 0))   # saturated {3,0}
    return sheet


if __name__ == "__main__":
    os.makedirs(OUT1, exist_ok=True)
    os.makedirs(OUT2, exist_ok=True)
    s = build_sheet()
    s.save(os.path.join(OUT1, "hunger.png"))
    s.resize((s.width * 2, s.height * 2), Image.NEAREST).save(os.path.join(OUT2, "hunger.png"))
    print("wrote assets/1x/hunger.png", s.size, "and assets/2x/hunger.png", (s.width * 2, s.height * 2))
