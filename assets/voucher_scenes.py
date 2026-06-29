"""Deterministic PIL renderer of the Pasto/Banchetto table scenes.
Used as (a) the AI structural reference and (b) a working placeholder icon.
Coordinates are fractions of (w,h); top ~22% stays transparent (burgundy wall)."""
from PIL import Image, ImageDraw

SLATE = (79, 99, 103)
C = dict(
    surface=(239, 230, 204), drape=(221, 208, 168), edge=(247, 240, 216),
    plate=(246, 246, 246), meat=(193, 129, 63), meat_hi=(217, 156, 84),
    bone=(236, 224, 192), water=(188, 223, 232), water_lo=(127, 184, 212),
    bottle=(58, 90, 58), label=(91, 42, 48), wine=(122, 31, 43),
    grape=(106, 61, 143), flame=(255, 206, 84), flame_in=(255, 126, 62),
    metal=(207, 207, 214), shadow=(79, 99, 103),
)

def _px(v, n): return int(round(v * n))

def draw_table(d, w, h):
    """Full-width tabletop: transparent wall on top, cream surface band, straight drape."""
    back  = _px(0.27, h)
    front = _px(0.66, h)
    d.rectangle([0, back, w, front], fill=C["surface"])
    d.rectangle([0, back-2, w, back], fill=C["edge"])
    d.rectangle([0, front, w, h], fill=C["drape"])
    d.line([0, front, w, front], fill=(200, 184, 142), width=1)

def _shadow(d, cx, cy, rx, ry):
    d.ellipse([cx-rx, cy-ry, cx+rx, cy+ry], fill=(*C["shadow"], 46))

def draw_plate(d, w, h, cx, cy, rx, ry):
    _shadow(d, cx, cy+ry, int(rx*1.05), max(2, ry//2))
    d.ellipse([cx-rx, cy-ry, cx+rx, cy+ry], fill=C["plate"], outline=SLATE)

def draw_drumstick(d, cx, cy, s):
    d.ellipse([cx-6*s, cy-3*s, cx+6*s, cy+3*s], fill=C["meat"], outline=SLATE)
    d.rectangle([cx+5*s, cy-4*s, cx+7*s, cy-1*s], fill=C["bone"], outline=SLATE)

def draw_chicken(d, cx, cy, s):
    d.ellipse([cx-10*s, cy-7*s, cx+10*s, cy+7*s], fill=C["meat"], outline=SLATE)
    d.ellipse([cx-7*s, cy-7*s, cx+7*s, cy-1*s], fill=C["meat_hi"])
    d.rectangle([cx-7*s, cy+3*s, cx-5*s, cy+7*s], fill=C["bone"], outline=SLATE)
    d.rectangle([cx+5*s, cy+3*s, cx+7*s, cy+7*s], fill=C["bone"], outline=SLATE)

def draw_glass(d, cx, top, ww, hh, fill):
    d.rectangle([cx-ww, top, cx+ww, top+hh], fill=(220,240,246), outline=SLATE)
    d.rectangle([cx-ww, top+hh//3, cx+ww, top+hh], fill=fill)
    d.ellipse([cx-ww, top-2, cx+ww, top+2], fill=(223,241,246), outline=SLATE)

def draw_wineglass(d, cx, top, r, stem_h):
    d.pieslice([cx-r, top-r, cx+r, top+r], 0, 180, fill=C["wine"], outline=SLATE)
    d.ellipse([cx-r, top-2, cx+r, top+2], fill=(231,201,207), outline=SLATE)
    d.rectangle([cx-1, top+r-2, cx+1, top+r+stem_h], fill=C["metal"])

def draw_bottle(d, cx, base, bw, bh):
    d.rectangle([cx-bw, base-bh, cx+bw, base], fill=C["bottle"], outline=SLATE)
    d.rectangle([cx-bw//2, base-bh-8, cx+bw//2, base-bh], fill=C["bottle"], outline=SLATE)
    d.rectangle([cx-bw, base-bh+6, cx+bw, base-6], fill=C["label"])

def draw_candle(d, cx, base, ch):
    d.rectangle([cx-2, base-ch, cx+2, base], fill=C["surface"], outline=SLATE)
    d.ellipse([cx-3, base-ch-7, cx+3, base-ch], fill=C["flame"])
    d.ellipse([cx-1, base-ch-5, cx+1, base-ch-1], fill=C["flame_in"])

def draw_grapes(d, cx, cy, r):
    for ox, oy in [(-r,0),(r,0),(0,r),(2*r,r),(-2*r,r),(0,2*r)]:
        d.ellipse([cx+ox-r, cy+oy-r, cx+ox+r, cy+oy+r], fill=C["grape"], outline=SLATE)

def draw_fork(d, cx, cy, ln):
    d.rectangle([cx, cy, cx+ln, cy+2], fill=C["metal"], outline=SLATE)

def _canvas(w, h):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img, "RGBA")

def render_pasto(w=56, h=66):
    img, d = _canvas(w, h)
    draw_table(d, w, h)
    cx = w//2
    draw_glass(d, _px(0.74,w), _px(0.40,h), 5, 12, C["water_lo"])
    draw_plate(d, w, h, cx, _px(0.58,h), _px(0.42,w), _px(0.10,h))
    draw_drumstick(d, cx, _px(0.55,h), max(1, w//56))
    draw_fork(d, _px(0.18,w), _px(0.78,h), _px(0.18,w))
    return img

def render_banchetto(w=56, h=66):
    img, d = _canvas(w, h)
    draw_table(d, w, h)
    cx = w//2
    s = max(1, w//56)
    draw_candle(d, _px(0.20,w), _px(0.52,h), _px(0.18,h))
    draw_bottle(d, _px(0.76,w), _px(0.44,h), 5, _px(0.22,h))
    draw_plate(d, w, h, cx, _px(0.62,h), _px(0.46,w), _px(0.11,h))
    draw_chicken(d, cx, _px(0.56,h), s)
    draw_grapes(d, _px(0.16,w), _px(0.74,h), 2)
    draw_wineglass(d, _px(0.80,w), _px(0.66,h), 5, _px(0.12,h))
    return img
