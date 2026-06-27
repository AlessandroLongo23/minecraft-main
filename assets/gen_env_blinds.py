"""Append the Night (surface) + Cave (underground) environment rows to the blinds atlas.

blinds.png is an ANIMATION_ATLAS: each ROW y is one blind's 21-frame strip (the frames are
identical horizontal copies of a single 34x34 / 68x68 tile; pos.x = the start frame). The 15 boss
rows occupy y=0..14; this script appends Night at row y=15 and Cave at row y=16, matching the
reskin in utilities/functions.lua (take_ownership pos {x=0,y=15} / {x=0,y=16}).

The tiles reuse the shared blind-chip DISC mask (the alpha of any existing cell) so Night/Cave sit
in the exact same footprint as the mob blinds, then fill it with environment art:
  * Night = a moonlit night sky (navy gradient + moon + stars).
  * Cave  = a darkened cobblestone wall with a mixed-ore vein.

Re-runnable: the 15 boss rows are cached to source/blinds_base_{1x,2x}.png on first run, and the
env rows are always rebuilt from that cache, so running this repeatedly never double-appends.
Run from anywhere: paths resolve relative to this file.
"""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))            # BalaCraft/assets
def P(*a): return os.path.join(HERE, *a)

FRAMES    = 21
BOSS_ROWS = 15
COBBLE    = P("..", "..", "assets", "reference", "resources", "cobblestone.png")  # cave wall base

# Deterministic art layouts (fractions of the cell), so 1x and 2x read the same.
STARS  = [(0.22, 0.24), (0.70, 0.16), (0.82, 0.40), (0.34, 0.54), (0.16, 0.70), (0.56, 0.70)]
VEIN   = [(0.30, 0.62), (0.38, 0.67), (0.33, 0.73), (0.47, 0.60),
          (0.51, 0.71), (0.59, 0.65), (0.43, 0.56), (0.63, 0.74)]
ORECOL = [(40, 40, 46, 255), (40, 40, 46, 255), (120, 205, 214, 255),   # coal, coal, diamond
          (222, 182, 120, 255), (96, 212, 124, 255)]                    # gold, emerald


def base_sheet(scale_path, cell):
    """Return the pristine 15-row boss base for a sheet, caching it on first run."""
    cache = P("source", "blinds_base_%dx.png" % (1 if cell == 34 else 2))
    if os.path.exists(cache):
        return Image.open(cache).convert("RGBA")
    sheet = Image.open(scale_path).convert("RGBA")
    base = sheet.crop((0, 0, sheet.width, BOSS_ROWS * cell))   # first 15 rows only
    os.makedirs(P("source"), exist_ok=True)
    base.save(cache)
    return base


def night_tile(S):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for y in range(S):                                   # navy -> indigo vertical gradient
        t = y / (S - 1)
        d.line([(0, y), (S, y)], fill=(int(10 + 16 * t), int(14 + 20 * t), int(48 + 40 * t), 255))
    for sx, sy in STARS:
        d.point((int(sx * S), int(sy * S)), fill=(236, 240, 255, 255))
    mr, mx, my = max(4, int(S * 0.20)), int(S * 0.66), int(S * 0.33)   # moon, upper-right
    d.ellipse([mx - mr, my - mr, mx + mr, my + mr], fill=(238, 236, 210, 255))
    for cx, cy, cr in [(0.35, -0.2, 0.30), (-0.15, 0.30, 0.22), (0.20, 0.45, 0.18)]:  # craters
        ox, oy, orr = int(cx * mr), int(cy * mr), max(1, int(cr * mr))
        d.ellipse([mx + ox - orr, my + oy - orr, mx + ox + orr, my + oy + orr], fill=(214, 210, 182, 255))
    return img


def cave_tile(S, cobble):
    img = cobble.resize((S, S), Image.NEAREST).convert("RGBA")
    img.alpha_composite(Image.new("RGBA", (S, S), (0, 0, 0, 95)))     # underground darkening
    d = ImageDraw.Draw(img)
    for i, (sx, sy) in enumerate(VEIN):                              # mixed-ore vein
        x, y, r = int(sx * S), int(sy * S), max(1, int(S * 0.045))
        d.ellipse([x - r, y - r, x + r, y + r], fill=ORECOL[i % len(ORECOL)])
    return img


def env_row(tile, cell, mask):
    tile = tile.copy()
    tile.putalpha(mask)                                  # clip to the shared disc footprint
    strip = Image.new("RGBA", (FRAMES * cell, cell), (0, 0, 0, 0))
    for f in range(FRAMES):
        strip.alpha_composite(tile, (f * cell, 0))
    return strip


def build(scale_path, cell, cobble):
    base = base_sheet(scale_path, cell)
    mask = base.crop((0, 0, cell, cell)).getchannel("A")           # disc alpha from a boss cell
    night = env_row(night_tile(cell), cell, mask)
    cave  = env_row(cave_tile(cell, cobble), cell, mask)
    out = Image.new("RGBA", (base.width, base.height + 2 * cell), (0, 0, 0, 0))
    out.alpha_composite(base, (0, 0))
    out.alpha_composite(night, (0, BOSS_ROWS * cell))               # row 15 = Night
    out.alpha_composite(cave,  (0, (BOSS_ROWS + 1) * cell))         # row 16 = Cave
    out.save(scale_path)
    print("wrote", os.path.relpath(scale_path, HERE), out.size, "(Night=row15, Cave=row16)")


if __name__ == "__main__":
    cobble = Image.open(COBBLE).convert("RGBA")
    build(P("1x", "blinds.png"), 34, cobble)
    build(P("2x", "blinds.png"), 68, cobble)
