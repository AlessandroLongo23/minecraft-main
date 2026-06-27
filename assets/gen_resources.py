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
import math
from PIL import Image
from utils import scale_image

ICON = 34
CARD_W, CARD_H = 71, 95
COLS, ROWS = 3, 14      # 25 base + 16 brewing ingredients = 41 resources -> 14 rows (last cell free)
ICON_ROWS = 14

# Wood + Cobblestone are BLOCKS, so (like Minecraft's inventory) they render as 2:1 dimetric
# isometric cubes instead of a flat face -- top + two darker sides. Every other resource is a flat
# item/mineral and stays a flat scaled texture. See iso_block() below.
ISO_IDS = {"wood", "cobblestone"}
SHADE_TOP, SHADE_LEFT, SHADE_RIGHT = 1.0, 0.80, 0.62

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
         "raw_iron", "raw_gold",   # MC-faithful smelt set: drop raw, smelt to iron/gold
         "redstone", "sand", "glass",   # cells 19,20,21 = (1,6),(2,6),(0,7); glass is the smelt-only glass-sheet input
         "obsidian", "ender_pearl", "blaze_powder",   # cells 22,23,24 = (1,7),(2,7),(0,8); Nether/End progression items
         # ── Brewing ingredients (potions feature). cells 25.. = (1,8),(2,8),(0,9)... row-major. ──
         # Raw drops (dimension-themed, drop_class='special'): nether_wart/sugar_cane/melon_slice/
         # carrot/brown_mushroom/ghast_tear/blaze_rod/glowstone_dust/dragon_breath.
         "nether_wart", "sugar_cane", "melon_slice", "carrot", "brown_mushroom",
         "ghast_tear", "blaze_rod", "glowstone_dust", "dragon_breath",
         # Crafted intermediates (kind='crafted'): glass_bottle/water_bottle/sugar/glistering_melon/
         # golden_carrot/fermented_spider_eye/awkward_potion.
         "glass_bottle", "water_bottle", "sugar", "glistering_melon", "golden_carrot",
         "fermented_spider_eye", "awkward_potion"]
# TIERS only drives the resource-CARD backdrop tint here; the Nether/End items are drop_class='special'
# (no real tier), so these values are purely cosmetic: obsidian -> tier-4 face, pearl -> 3, powder -> 2.
TIERS = {"wood": 1, "cobblestone": 1, "coal": 1, "iron": 2, "gold": 2, "diamond": 3, "sticks": 1, "emerald": 2, "netherite": 4, "lapis": 3,
         "string": 1, "feather": 1, "flint": 1,
         "gunpowder": 1, "bone": 1, "spider_eye": 1, "glow_ink_sac": 1,
         "raw_iron": 2, "raw_gold": 2,
         "redstone": 3, "sand": 1, "glass": 1,
         "obsidian": 4, "ender_pearl": 3, "blaze_powder": 2,
         "nether_wart": 2, "sugar_cane": 1, "melon_slice": 1, "carrot": 1, "brown_mushroom": 1,
         "ghast_tear": 3, "blaze_rod": 3, "glowstone_dust": 2, "dragon_breath": 4,
         "glass_bottle": 1, "water_bottle": 1, "sugar": 1, "glistering_melon": 2, "golden_carrot": 2,
         "fermented_spider_eye": 2, "awkward_potion": 2}


def load(rid):
    return Image.open(os.path.join(_REF, rid + ".png")).convert("RGBA")


def nn(img, factor):
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


def _shade(img, k):
    r, g, b, a = img.split()
    f = lambda v: int(v * k)
    return Image.merge("RGBA", (r.point(f), g.point(f), b.point(f), a))


def iso_block(tex, target):
    """Render a uniform-texture cube as a 2:1 dimetric (MC-inventory-style) isometric block,
    sized to fit a `target`x`target` transparent square. Built at high internal res, then
    LANCZOS-downscaled for clean edges. Same texture on all three visible faces (planks/cobble),
    each face shaded (top brightest, the two sides progressively darker)."""
    SUP = 10
    s = tex.width * SUP                         # high-res face edge
    face = nn(tex, SUP)
    a = int(round(s / math.sqrt(2)))            # cube half-width == top-diamond half-width
    c = a                                        # side (vertical) height -> a cube

    # top face: rotate 45 + squash to half height -> a 2:1 diamond
    top = _shade(face, SHADE_TOP).rotate(45, expand=True, resample=Image.BICUBIC)
    D = top.width                                # ~ s*sqrt(2) ~ 2a
    top = top.resize((D, D // 2), Image.BICUBIC)

    # side faces: resize to (a, c) then vertical shear +/-0.5 (top edges follow the diamond)
    shear_h = c + a // 2 + 1
    left = _shade(face, SHADE_LEFT).resize((a, c), Image.BICUBIC)
    left = left.transform((a, shear_h), Image.AFFINE, (1, 0, 0, -0.5, 1, 0), Image.BICUBIC)
    right = _shade(face, SHADE_RIGHT).resize((a, c), Image.BICUBIC)
    right = right.transform((a, shear_h), Image.AFFINE, (1, 0, 0, 0.5, 1, -0.5 * a), Image.BICUBIC)

    W, H = D, (D // 2) + c
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    canvas.alpha_composite(left, (0, a // 2 - 1))    # 1px up: tuck the AA seam under the top face
    canvas.alpha_composite(right, (a, a // 2 - 1))
    canvas.alpha_composite(top, (0, 0))

    bb = canvas.getbbox()
    canvas = canvas.crop(bb)
    scale = target / max(canvas.width, canvas.height)
    canvas = canvas.resize((max(1, round(canvas.width * scale)),
                            max(1, round(canvas.height * scale))), Image.LANCZOS)
    out = Image.new("RGBA", (target, target), (0, 0, 0, 0))
    out.alpha_composite(canvas, ((target - canvas.width) // 2, (target - canvas.height) // 2))
    return out


def block_or_flat(rid, target):
    """Wood/cobblestone -> isometric cube; everything else -> the flat texture scaled to fit."""
    tex = load(rid)
    if rid in ISO_IDS:
        return iso_block(tex, target)
    f = max(1, target // tex.width)
    return nn(tex, f)


def build_icons():
    # Frameless: each texture scaled 2x (16 -> 32, crisp nearest-neighbor) and centered in its
    # 34x34 cell (a 1px transparent margin). Cell size + grid are unchanged, so the registry
    # `pos` values and the bc_resource_icons atlas (px=py=34) need no edits.
    sheet = Image.new("RGBA", (ICON * COLS, ICON * ICON_ROWS), (0, 0, 0, 0))
    for i, rid in enumerate(ORDER):
        cx, cy = (i % COLS) * ICON, (i // COLS) * ICON
        block = block_or_flat(rid, 32)   # wood/cobble -> iso cube; others -> flat 2x texture
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
        block = block_or_flat(rid, 48)  # 16 -> 48 (wood/cobble render as iso cubes)
        face.alpha_composite(block, ((CARD_W - block.width) // 2, (CARD_H - block.height) // 2 - 4))
        sheet.alpha_composite(face, (cx, cy))
    sheet.save("BalaCraft/assets/1x/resource_cards.png")
    scale_image("BalaCraft/assets/1x/resource_cards.png", "BalaCraft/assets/2x/resource_cards.png", 2)
    print("wrote resource_cards.png", sheet.size)


if __name__ == "__main__":
    build_icons()
    build_emerald_plain()
    build_lapis_plain()
    build_cards()
