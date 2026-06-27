"""Generate the Ore-Block CARD atlas (bc_ore_blocks) from genuine 16x16 Minecraft block textures.

These are the "ore cards" -- playing cards that carry an Ore-Block enhancement
(content/card_enhancements/blocks.lua). The enhancement's `center` sprite IS the card face, drawn
UNDER the rank/suit/pips. So unlike the booster resource cards (a single centered item on a dark
face), each ore card here is the MC block texture TILED to fill the whole card, clipped to the
rounded card mask so it never overflows, leaving the pips ("the printing") readable on top.

Pipeline (mirrors gen_resources.py): source textures live in `assets/reference/ore_blocks/<id>.png`
(downloaded from the InventivetalentDev minecraft-assets mirror, textures/block/*). The rounded card
silhouette comes from the VANILLA blank base-card cell in `assets/1x/Enhancers.png` (its alpha is the
exact NORMAL playing-card mask -- the Stone cell's corners are slightly more clipped), so these cards
round identically to a normal card.

Output:
  assets/1x/ore_blocks.png  -> 71x95 cells, 3x7 grid (213x665)   + 2x derived (426x1330)
Cell layout MUST match content/card_enhancements/blocks.lua: the 9 ore-block enhancements sit at
their resource registry `pos`; the 3 tarot-applied block cards get dedicated free cells.
"""
import os
from PIL import Image
from utils import scale_image

CARD_W, CARD_H = 71, 95
COLS, ROWS = 3, 8   # row 6 gained Redstone/Sand ore-blocks; the obsidian/hay_bale specials moved to row 7

TILE_SCALE   = 3            # 16 -> 48px tiles; repeat is visible across the 71x95 card. Tunable.
DARKEN       = 0.90         # mild overall darken so the coloured pips pop over busy stone textures
VIGNETTE_A   = 70           # 0-255 strength of a soft central shadow behind the center pip

# Vanilla Enhancers.png is a 7x5 grid; the blank white base card is cell (1,0) -- its alpha is the
# NORMAL playing-card silhouette (use this, not the Stone cell, whose corners are slightly clipped).
BASE_CELL = (1, 0)

_HERE = os.path.dirname(os.path.abspath(__file__))
_REF  = os.path.normpath(os.path.join(_HERE, "..", "..", "assets", "reference", "ore_blocks"))
_ENH  = os.path.normpath(os.path.join(_HERE, "..", "..", "assets", "1x", "Enhancers.png"))

# id (== reference texture filename) -> (col, row) in the bc_ore_blocks atlas.
# Ore blocks mirror content/resources/registry.lua `pos` (the loop in blocks.lua keeps pos=res.pos).
# The 3 specials get free cells (updated in blocks.lua to match).
CELLS = {
    # ore-block enhancements (drop_class == 'ore') -- pos == registry pos
    "wood":        (0, 0), "cobblestone": (1, 0), "coal":     (2, 0),
    "diamond":     (2, 1), "emerald":     (1, 2), "netherite": (2, 2),
    "lapis":       (0, 3), "raw_iron":    (2, 5), "raw_gold": (0, 6),
    "redstone":    (1, 6), "sand":        (2, 6),   # new ore-blocks (registry pos)
    # tarot-applied block cards (dedicated free cells; moved to row 7 to free (1,6)/(2,6))
    "lapis_block": (1, 1),                 # the "Lapis Card" XP enhancement (key 'lapis')
    "obsidian":    (1, 7), "hay_bale":     (2, 7),
}


def nn(img, factor):
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


def load_tex(idn):
    return Image.open(os.path.join(_REF, idn + ".png")).convert("RGBA")


def card_mask():
    """Alpha channel of the vanilla blank base-card cell = the exact NORMAL card silhouette."""
    enh = Image.open(_ENH).convert("RGBA")
    cx, cy = BASE_CELL
    cell = enh.crop((cx * CARD_W, cy * CARD_H, cx * CARD_W + CARD_W, cy * CARD_H + CARD_H))
    return cell.getchannel("A")


def tiled_fill(idn):
    """The 16x16 texture scaled TILE_SCALE x and tiled across a 71x95 cell, a full tile centered."""
    tile = nn(load_tex(idn), TILE_SCALE)
    tw, th = tile.size
    fill = Image.new("RGBA", (CARD_W, CARD_H), (0, 0, 0, 255))
    # Align so one whole tile sits centered (nicest behind the center pip), then cover out to edges.
    ox = (CARD_W - tw) // 2
    oy = (CARD_H - th) // 2
    for x in range(ox % tw - tw, CARD_W, tw):
        for y in range(oy % th - th, CARD_H, th):
            fill.alpha_composite(tile, (x, y))
    return fill


def vignette():
    """Soft radial darkening centered on the card, for pip contrast. Returned as an L (alpha) mask."""
    v = Image.new("L", (CARD_W, CARD_H), 0)
    cx, cy = CARD_W / 2.0, CARD_H / 2.0
    maxd = (cx ** 2 + cy ** 2) ** 0.5
    px = v.load()
    for y in range(CARD_H):
        for x in range(CARD_W):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 / maxd   # 0 center .. 1 corner
            # strongest in the middle, fades out by ~60% radius
            t = max(0.0, 1.0 - d / 0.6)
            px[x, y] = int(VIGNETTE_A * t)
    return v


def make_card(idn, mask, vig):
    """Composite one ore card: tiled texture, mild darken + center vignette, clipped to the normal
    card mask -- no frame, the texture fills to the smooth mask edge (rounds like a normal card)."""
    out = tiled_fill(idn)

    # mild overall darken
    r, g, b, a = out.split()
    out = Image.merge("RGBA", (r.point(lambda v: int(v * DARKEN)),
                               g.point(lambda v: int(v * DARKEN)),
                               b.point(lambda v: int(v * DARKEN)), a))
    # soft central shadow (multiply toward black using the vignette alpha)
    shadow = Image.new("RGBA", (CARD_W, CARD_H), (0, 0, 0, 0))
    shadow.putalpha(vig)
    out = Image.alpha_composite(out, shadow)

    # clip the texture to the normal-card silhouette
    out.putalpha(mask)
    return out


def build():
    mask = card_mask()
    assert mask.getpixel((CARD_W // 2, CARD_H // 2)) == 255, "base card interior must be opaque"
    vig = vignette()
    sheet = Image.new("RGBA", (CARD_W * COLS, CARD_H * ROWS), (0, 0, 0, 0))
    for idn, (col, row) in CELLS.items():
        card = make_card(idn, mask, vig)
        sheet.alpha_composite(card, (col * CARD_W, row * CARD_H))
    sheet.save("BalaCraft/assets/1x/ore_blocks.png")
    scale_image("BalaCraft/assets/1x/ore_blocks.png", "BalaCraft/assets/2x/ore_blocks.png", 2)
    print("wrote ore_blocks.png", sheet.size, "cells:", len(CELLS))


if __name__ == "__main__":
    build()
