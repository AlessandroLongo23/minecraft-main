#!/usr/bin/env python3
"""Generate the single Bone Meal consumable card (assets/1x/bone_meal.png + 2x), atlas `bc_bone_meal`.

Same card chrome as the Torch card (gen_torch_card.py): the tool-card body with the material plate
and the durability bar smoothed off (Bone Meal is a single-use consumable, no tier / no durability),
the authentic Minecraft `bone_meal` item texture centred, and the name in the 6px bold alphabet.

Template source: the same wood_sword_2.png used by gen_tool_cards.py / gen_torch_card.py.
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))            # BalaCraft/assets
MODS = os.path.normpath(os.path.join(HERE, "..", ".."))      # Mods/
REF  = os.path.join(MODS, "assets", "reference")
GLYPHDIR  = os.path.join(REF, "font", "bold")
SPRITEDIR = os.path.join(REF, "mc_tools")                    # authentic MC item textures
OUT1 = os.path.join(HERE, "1x")
OUT2 = os.path.join(HERE, "2x")

# --- palette (sampled from wood_sword_2.png; shared with gen_tool_cards.py) ---
GREY   = (151, 151, 151, 255)
RECESS = (127, 127, 127, 255)
LIGHT  = (195, 199, 203, 255)
CREAM  = (254, 253, 249, 255)
OUTL   = (227, 222, 213, 255)

# Bone meal is a full 16x16 item (not a thin stick like the torch) -> 3x reads well without overflow.
SCALE = int(os.environ.get("BONEMEAL_SCALE", "3"))

src = Image.open(os.path.join(HERE, "1x", "wood_sword_2.png")).convert("RGBA")
W, H = src.size                                              # 71 x 95
card = src.copy(); px = card.load()


def keep(x, y):
    c = px[x, y]
    return c == OUTL or c[3] == 0


def body_col(x):
    if x in (6, 64):           return LIGHT
    if x in (7, 8, 62, 63):    return RECESS
    return GREY


def fill_clean(y, grooves=True):
    for x in range(W):
        if keep(x, y):
            continue
        px[x, y] = body_col(x) if grooves else GREY


# 1) smooth out the TOP material plate, keeping the inner-frame border (copy a clean shoulder column)
for y in range(3, 10):
    c = src.getpixel((15, y))
    for x in range(11, 60):
        px[x, y] = c

# 1b) erase the baked-in sword sprite -> clean grey body
def is_coloured(c):
    r, g, b, a = c
    return a > 0 and (max(r, g, b) - min(r, g, b)) > 14
for y in range(14, 70):
    for x in range(9, 62):
        if is_coloured(px[x, y]):
            px[x, y] = GREY

# 2) remove the DURABILITY BAR, mirroring the TOP border at the bottom
for y in range(72, 79):
    fill_clean(y, grooves=True)
for sy in range(3, 9):
    dy = 81 - sy
    for x in range(6, 65):
        px[x, dy] = px[x, sy]

# 3) erase the baked-in bottom name ("SWORD") -> clean cream
for y in range(81, 91):
    for x in range(7, 64):
        if px[x, y] == RECESS:
            px[x, y] = CREAM

# 4) paste the bone_meal sprite, centred on its visible pixels
sp = Image.open(os.path.join(SPRITEDIR, "bone_meal.png")).convert("RGBA")
sp = sp.resize((sp.width * SCALE, sp.height * SCALE), Image.NEAREST)
bbox = sp.getbbox()
bw, bh = bbox[2] - bbox[0], bbox[3] - bbox[1]
IX0, IX1 = 9, 61
IY0, IY1 = 4, 78
cx = (IX0 + IX1) / 2
cy = (IY0 + IY1) / 2
paste_x = round(cx - (bbox[0] + bw / 2))
paste_y = round(cy - (bbox[1] + bh / 2))
card.alpha_composite(sp, (paste_x, paste_y))

# 5) render the name in the 6px bold alphabet, on the cream nameplate
def load_glyphs(colour):
    g = {}
    for f in os.listdir(GLYPHDIR):
        if not f.endswith(".png"):
            continue
        im = Image.open(os.path.join(GLYPHDIR, f)).convert("RGBA")
        p = im.load()
        for y in range(im.height):
            for x in range(im.width):
                if p[x, y][3] > 0:
                    p[x, y] = colour
        g[f[0]] = im
    return g


def render_word(word, glyphs, gap=1):
    gs = [glyphs[c] for c in word if c != " "]
    w = sum(im.width for im in gs) + gap * (len(gs) - 1)
    h = max(im.height for im in gs)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    x = 0
    for im in gs:
        out.alpha_composite(im, (x, h - im.height))
        x += im.width + gap
    return out


glyphs = load_glyphs(RECESS)
word = render_word("BONEMEAL", glyphs)
card.alpha_composite(word, ((W - word.width) // 2, 89 - word.height))

if __name__ == "__main__":
    os.makedirs(OUT1, exist_ok=True); os.makedirs(OUT2, exist_ok=True)
    card.save(os.path.join(OUT1, "bone_meal.png"))
    card.resize((W * 2, H * 2), Image.NEAREST).save(os.path.join(OUT2, "bone_meal.png"))
    print(f"Wrote assets/1x/bone_meal.png {card.size} (+2x). name width={word.width}px, sprite {bw}x{bh} at ({paste_x},{paste_y})")
