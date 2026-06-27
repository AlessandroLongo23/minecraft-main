"""Compose a Minecraft sprite into a Balatro *tag badge* frame.

Shared by gen_resources.py (resource icons) and gen_tool_icons.py (tool icons).

The frame comes from the mod's `assets/_templates/1x/tag_template.png` -- a strict
pixel intersection of all 24 vanilla tags that keeps the shared grey beveled
rounded-square and leaves the icon area transparent. That shared region is a chunky
~6px bevel, but a real tag reads as a THIN rounded frame around a big interior, so
`badge_icon()`:

  1. takes the full badge silhouette (bevel + inner hole) and erodes it: only the
     outer `FRAME_THICKNESS` px stay as the *frame*; everything inside becomes interior,
  2. fills that interior with a neutral, near-white backdrop,
  3. centers the Minecraft sprite in it,
  4. recolors the thin frame ring to a per-item *accent* -- mapping each pixel's
     luminance across a dark->light ramp so the bevel's directional shading survives --
     and composites it on top.

Everything is composed at 1x (34x34). Callers derive the 2x sheet with the project's
nearest-neighbour `utils.scale_image`, matching every other BalaCraft atlas.
"""
import os
from PIL import Image

CELL = 34  # tag cell is 34x34 at 1x

_HERE = os.path.dirname(os.path.abspath(__file__))            # .../Mods/BalaCraft/assets
_TEMPLATE = os.path.normpath(os.path.join(_HERE, "..", "..", "assets", "_templates",
                                          "1x", "tag_template.png"))

# --- tunables -------------------------------------------------------------------
NEUTRAL_FILL = (236, 234, 226, 255)   # light "white-ish" badge interior (same for all)
FRAME_THICKNESS = 2                   # px of the outer ring kept as the (thin) frame
FRAME_DARK_F = 0.55                   # shadow end of the recolored frame  = accent * this
FRAME_LIGHT_W = 0.20                  # highlight end = accent lightened this far toward white
DEFAULT_SPRITE_SCALE = 1              # nearest-neighbour upscale of the sprite before centering
# --------------------------------------------------------------------------------

_cache = None  # (frame_img, ring[][], interior[][], interior_bbox)


def _build():
    global _cache
    if _cache is not None:
        return _cache
    frame = Image.open(_TEMPLATE).convert("RGBA")
    w, h = frame.size
    a = frame.load()
    opaque = [[a[x, y][3] > 10 for x in range(w)] for y in range(h)]

    # exterior = transparent pixels reachable from the border (flood fill)
    vis = [[False] * w for _ in range(h)]
    st = []
    for x in range(w):
        for y in (0, h - 1):
            if not opaque[y][x] and not vis[y][x]:
                vis[y][x] = True
                st.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if not opaque[y][x] and not vis[y][x]:
                vis[y][x] = True
                st.append((x, y))
    while st:
        x, y = st.pop()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not vis[ny][nx] and not opaque[ny][nx]:
                vis[ny][nx] = True
                st.append((nx, ny))

    # silhouette = whole badge shape (frame bevel + inner hole)
    sil = [[not vis[y][x] for x in range(w)] for y in range(h)]

    # erode the silhouette by FRAME_THICKNESS -> interior; the shell left over is the thin frame
    K = FRAME_THICKNESS
    interior = [[False] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            if not sil[y][x]:
                continue
            keep = True
            for dy in range(-K, K + 1):
                for dx in range(-K, K + 1):
                    nx, ny = x + dx, y + dy
                    if not (0 <= nx < w and 0 <= ny < h and sil[ny][nx]):
                        keep = False
                        break
                if not keep:
                    break
            interior[y][x] = keep
    ring = [[sil[y][x] and not interior[y][x] for x in range(w)] for y in range(h)]

    xs = [x for y in range(h) for x in range(w) if interior[y][x]]
    ys = [y for y in range(h) for x in range(w) if interior[y][x]]
    bbox = (min(xs), min(ys), max(xs), max(ys))
    _cache = (frame, ring, interior, bbox)
    return _cache


def interior_bbox():
    return _build()[3]


def _nn(img, scale):
    if scale == 1:
        return img
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST)


def badge_icon(sprite, accent_rgb, sprite_scale=DEFAULT_SPRITE_SCALE):
    """Return a 34x34 RGBA badge: thin accent-recolored frame, neutral interior,
    `sprite` (small RGBA, e.g. 16x16) centered. `sprite_scale` nearest-upscales it."""
    frame, ring, interior, bbox = _build()
    fpx = frame.load()
    dark = tuple(int(c * FRAME_DARK_F) for c in accent_rgb[:3])
    light = tuple(min(255, int(c + (255 - c) * FRAME_LIGHT_W)) for c in accent_rgb[:3])

    out = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    px = out.load()
    for y in range(CELL):
        for x in range(CELL):
            if interior[y][x]:
                px[x, y] = NEUTRAL_FILL

    spr = _nn(sprite, sprite_scale)
    x0, y0, x1, y1 = bbox
    cx = (x0 + x1 + 1 - spr.width) // 2
    cy = (y0 + y1 + 1 - spr.height) // 2
    out.alpha_composite(spr, (cx, cy))

    for y in range(CELL):
        for x in range(CELL):
            if not ring[y][x]:
                continue
            r, g, b, al = fpx[x, y]
            t = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            px[x, y] = (
                int(dark[0] + (light[0] - dark[0]) * t),
                int(dark[1] + (light[1] - dark[1]) * t),
                int(dark[2] + (light[2] - dark[2]) * t),
                255,
            )
    return out
