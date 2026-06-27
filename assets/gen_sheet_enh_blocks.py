"""Generate the sheet-enhancement CARD atlas (bc_sheet_enh_blocks) -- the four NEW enhancements a
metal Sheet applies (Diamond / Emerald / Redstone / Coal). Same technique as gen_ore_blocks.py: the
genuine 16x16 MC block face TILED to fill the card, clipped to the rounded card mask, drawn UNDER the
rank/suit/pips. A dedicated atlas keeps the near-full bc_ore_blocks sheet untouched.

Inputs:
  assets/reference/sheet/<id>.png  -- genuine 16x16 MC block-face textures (diamond_block, ...).
  assets/1x/Enhancers.png          -- vanilla blank base-card cell (its alpha = the card silhouette).

Output:
  assets/1x/sheet_enh_blocks.png   -> 71x95 cells, 2x2 grid (+2x derived).
Cell layout MUST match content/card_enhancements/sheet_enhancements.lua pos values:
  diamond (0,0)  emerald (1,0)  redstone (0,1)  coal (1,1).
"""
import os
from PIL import Image
from utils import scale_image

CARD_W, CARD_H = 71, 95
COLS, ROWS = 2, 2
TILE_SCALE = 3
DARKEN = 0.90
VIGNETTE_A = 70
BASE_CELL = (1, 0)   # vanilla blank base card in Enhancers.png (alpha = normal-card silhouette)

_HERE = os.path.dirname(os.path.abspath(__file__))
_REF  = os.path.normpath(os.path.join(_HERE, "..", "..", "assets", "reference", "sheet"))
_ENH  = os.path.normpath(os.path.join(_HERE, "..", "..", "assets", "1x", "Enhancers.png"))

CELLS = {"diamond": (0, 0), "emerald": (1, 0), "redstone": (0, 1), "coal": (1, 1)}


def nn(img, factor):
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


def load_tex(idn):
    return Image.open(os.path.join(_REF, idn + ".png")).convert("RGBA")


def card_mask():
    enh = Image.open(_ENH).convert("RGBA")
    cx, cy = BASE_CELL
    cell = enh.crop((cx * CARD_W, cy * CARD_H, cx * CARD_W + CARD_W, cy * CARD_H + CARD_H))
    return cell.getchannel("A")


def tiled_fill(idn):
    tile = nn(load_tex(idn), TILE_SCALE)
    tw, th = tile.size
    fill = Image.new("RGBA", (CARD_W, CARD_H), (0, 0, 0, 255))
    ox, oy = (CARD_W - tw) // 2, (CARD_H - th) // 2
    for x in range(ox % tw - tw, CARD_W, tw):
        for y in range(oy % th - th, CARD_H, th):
            fill.alpha_composite(tile, (x, y))
    return fill


def vignette():
    v = Image.new("L", (CARD_W, CARD_H), 0)
    cx, cy = CARD_W / 2.0, CARD_H / 2.0
    maxd = (cx ** 2 + cy ** 2) ** 0.5
    px = v.load()
    for y in range(CARD_H):
        for x in range(CARD_W):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 / maxd
            px[x, y] = int(VIGNETTE_A * max(0.0, 1.0 - d / 0.6))
    return v


def make_card(idn, mask, vig):
    out = tiled_fill(idn)
    r, g, b, a = out.split()
    out = Image.merge("RGBA", (r.point(lambda v: int(v * DARKEN)),
                               g.point(lambda v: int(v * DARKEN)),
                               b.point(lambda v: int(v * DARKEN)), a))
    shadow = Image.new("RGBA", (CARD_W, CARD_H), (0, 0, 0, 0))
    shadow.putalpha(vig)
    out = Image.alpha_composite(out, shadow)
    out.putalpha(mask)
    return out


def build():
    mask = card_mask()
    vig = vignette()
    sheet = Image.new("RGBA", (CARD_W * COLS, CARD_H * ROWS), (0, 0, 0, 0))
    for idn, (col, row) in CELLS.items():
        sheet.alpha_composite(make_card(idn, mask, vig), (col * CARD_W, row * CARD_H))
    sheet.save("BalaCraft/assets/1x/sheet_enh_blocks.png")
    scale_image("BalaCraft/assets/1x/sheet_enh_blocks.png", "BalaCraft/assets/2x/sheet_enh_blocks.png", 2)
    print("wrote sheet_enh_blocks.png", sheet.size, "cells:", len(CELLS))


if __name__ == "__main__":
    build()
