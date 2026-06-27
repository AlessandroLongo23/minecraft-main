"""Generate Food_Template_2.png -- the food card with a procedural wheat-field background.

Takes the clean old card (assets/1x/food_template.png: frame + cream nameplate + plain
brown body + bottom hunger strip) and paints, into the body region (x 8..62, y 21..79):

  1. a flat GROUND fill in the SAME tan as the bottom hunger bar, from the horizon row
     down to the strip, so the field reads as one continuous tan that merges into the bar.
  2. a layered WHEAT FIELD built from the hand-made ear sprite the user supplied
     (assets/reference/wheat/ear_tall.png 5x15 + ear_short.png 5x12, split from the
     original two-ear sprite). Variations = {tall, short} x {upright, h-flipped} x scale.
     Three depth layers stacked with a GROWING y-gap between consecutive baselines, so the
     rows read as clearly tiered; opacity + size + base-height together fake the depth:
        back  -- small (1x), faint (~34%), up on the horizon, washed into the tan haze
        mid   -- medium (2x), ~60%
        front -- tall (2x), ~92%, sitting right on the ground line

Deterministic: a fixed SEED makes the field identical every run (bump SEED to re-roll).

Output: assets/1x/Food_Template_2_wheat.png -- a SEPARATE file, so this never overwrites
the hand-made Food_Template_2.png. (To ship the procedural field, point gen_foods.py at it.)
"""
import os
import random
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))            # BalaCraft/assets
MODS = os.path.normpath(os.path.join(HERE, "..", ".."))      # Mods/
WHEAT = os.path.join(MODS, "assets", "reference", "wheat")
OUT1 = os.path.join(HERE, "1x")

SEED = 7  # fixed -> reproducible field. bump to re-roll the layout.

# ---- card geometry (measured from food_template.png) ----
BODY_X0, BODY_X1 = 8, 62          # body interior, inclusive
BODY_BROWN = (185, 132, 90, 255)  # flat body colour to be overpainted

# the field "ground" is a flat fill in the SAME tan as the bottom hunger bar, from the
# horizon row down to the strip -- so the field merges into the bar (was a gradient).
FIELD_TAN = (226, 177, 145, 255)  # == bottom bar interior colour
FIELD_TOP = 60                    # horizon row; the tan fill spans FIELD_TOP..79
GROUND_TINT = FIELD_TAN[:3]       # back-layer ears blend toward this for haze

# ---- ear sprites ----
EAR_TALL  = Image.open(os.path.join(WHEAT, "ear_tall.png")).convert("RGBA")   # 5x15
EAR_SHORT = Image.open(os.path.join(WHEAT, "ear_short.png")).convert("RGBA")  # 5x12


def paint_ground(card):
    """Flat-fill the body's lower rows (horizon -> strip) with the bottom-bar tan, so the
    wheat grows out of a tan field that merges into the bar. Only the flat body pixels are
    touched, so the frame and strip are left alone."""
    p = card.load()
    for y in range(FIELD_TOP, 80):
        for x in range(BODY_X0, BODY_X1 + 1):
            if p[x, y] == BODY_BROWN:
                p[x, y] = FIELD_TAN


def variant(base, flip, scale, opacity, lighten):
    """Build one ear instance: optional h-flip, integer upscale (NEAREST -> crisp pixels),
    alpha scaled by `opacity`, rgb blended `lighten` (0..1) toward the soil tint."""
    im = base
    if flip:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    if scale != 1:
        im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    im = im.copy()
    px = im.load()
    tr, tg, tb = GROUND_TINT
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if lighten:
                r = round(r + (tr - r) * lighten)
                g = round(g + (tg - g) * lighten)
                b = round(b + (tb - b) * lighten)
            px[x, y] = (r, g, b, round(a * opacity))
    return im


def place(card, rng, count, base_choices, scale, base_y_range, opacity, lighten, jitter=3):
    """Scatter `count` ears across the body. Stratified: the body width is split into
    `count` slots, one ear per slot at the slot centre +/- jitter, so the field covers the
    whole width instead of clumping. cx is clamped to keep each ear inside the frame.
    Random shape/flip/base-row per ear. Anchored by stem bottom."""
    slot = (BODY_X1 - BODY_X0) / count
    for i in range(count):
        base = rng.choice(base_choices)
        ear = variant(base, rng.random() < 0.5, scale, opacity, lighten)
        half = ear.width // 2
        cx = round(BODY_X0 + (i + 0.5) * slot + rng.randint(-jitter, jitter))
        cx = max(BODY_X0 + half, min(BODY_X1 - half, cx))   # keep ear within the frame
        base_y = rng.randint(*base_y_range)
        card.alpha_composite(ear, (cx - half, base_y - ear.height))


def build():
    card = Image.open(os.path.join(OUT1, "food_template.png")).convert("RGBA")
    paint_ground(card)
    rng = random.Random(SEED)
    # Layers stacked with a GROWING vertical gap between consecutive baselines
    # (back~60 -> mid~68 -> front~78: gaps ~8 then ~10), so the rows read as tiered depth.
    # back: far, faint, small, sitting on the horizon, washed into the tan haze
    place(card, rng, count=8, base_choices=[EAR_TALL, EAR_SHORT], scale=1,
          base_y_range=(59, 62), opacity=0.34, lighten=0.45)
    # mid
    place(card, rng, count=6, base_choices=[EAR_SHORT, EAR_TALL], scale=2,
          base_y_range=(67, 69), opacity=0.60, lighten=0.16)
    # front: near, opaque, tall, on the ground line
    place(card, rng, count=5, base_choices=[EAR_TALL], scale=2,
          base_y_range=(77, 79), opacity=0.92, lighten=0.0)
    return card


if __name__ == "__main__":
    out = build()
    # Writes a SEPARATE file so it never clobbers the hand-made Food_Template_2.png.
    # To use this procedural field in-game, point gen_foods.py's TEMPLATES + the
    # bc_food_cards atlas at the sheet built from it.
    out.save(os.path.join(OUT1, "Food_Template_2_wheat.png"))
    print("wrote assets/1x/Food_Template_2_wheat.png", out.size, "(seed %d)" % SEED)
