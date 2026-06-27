#!/usr/bin/env python3
"""Generate simple item-consumable cards (71x95) from authentic MC item textures, sharing the
Torch/Bone Meal card chrome (gen_torch_card.py / gen_bone_meal_card.py): the tool-card body with the
material plate + durability bar smoothed off, the MC sprite centred, and the name in the 6px bold
alphabet. One card per entry in CARDS -> assets/1x/<out>.png (+2x), atlas key bc_<out>.

Currently: TNT (explosives) and Firework Rocket (explosives), the gunpowder sinks.
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))            # BalaCraft/assets
MODS = os.path.normpath(os.path.join(HERE, "..", ".."))      # Mods/
REF  = os.path.join(MODS, "assets", "reference")
GLYPHDIR  = os.path.join(REF, "font", "bold")
SPRITEDIR = os.path.join(REF, "mc_tools")
OUT1 = os.path.join(HERE, "1x")
OUT2 = os.path.join(HERE, "2x")

# (output filename, reference sprite filename, nameplate label, sprite scale)
CARDS = [
    ("tnt",      "tnt",             "TNT",      3),
    ("firework", "firework_rocket", "FIREWORK", 3),
]

GREY   = (151, 151, 151, 255)
RECESS = (127, 127, 127, 255)
LIGHT  = (195, 199, 203, 255)
CREAM  = (254, 253, 249, 255)
OUTL   = (227, 222, 213, 255)


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


def make_card(sprite_name, label, scale, glyphs):
    src = Image.open(os.path.join(HERE, "1x", "wood_sword_2.png")).convert("RGBA")
    W, H = src.size
    card = src.copy(); px = card.load()

    def keep(x, y):
        c = px[x, y]
        return c == OUTL or c[3] == 0

    def body_col(x):
        if x in (6, 64):           return LIGHT
        if x in (7, 8, 62, 63):    return RECESS
        return GREY

    def fill_clean(y):
        for x in range(W):
            if not keep(x, y):
                px[x, y] = body_col(x)

    # 1) smooth the TOP material plate (copy a clean shoulder column across the tab gap)
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

    # 2) remove the durability bar, mirror the top border at the bottom
    for y in range(72, 79):
        fill_clean(y)
    for sy in range(3, 9):
        dy = 81 - sy
        for x in range(6, 65):
            px[x, dy] = px[x, sy]

    # 3) erase the baked-in bottom name -> clean cream
    for y in range(81, 91):
        for x in range(7, 64):
            if px[x, y] == RECESS:
                px[x, y] = CREAM

    # 4) paste the MC sprite, centred on its visible pixels
    sp = Image.open(os.path.join(SPRITEDIR, sprite_name + ".png")).convert("RGBA")
    sp = sp.resize((sp.width * scale, sp.height * scale), Image.NEAREST)
    bbox = sp.getbbox()
    bw, bh = bbox[2] - bbox[0], bbox[3] - bbox[1]
    cx, cy = (9 + 61) / 2, (4 + 78) / 2
    card.alpha_composite(sp, (round(cx - (bbox[0] + bw / 2)), round(cy - (bbox[1] + bh / 2))))

    # 5) the name on the cream nameplate
    word = render_word(label, glyphs)
    card.alpha_composite(word, ((W - word.width) // 2, 89 - word.height))
    return card, W, H


def build():
    glyphs = load_glyphs(RECESS)
    os.makedirs(OUT1, exist_ok=True); os.makedirs(OUT2, exist_ok=True)
    for out, sprite, label, scale in CARDS:
        card, W, H = make_card(sprite, label, scale, glyphs)
        card.save(os.path.join(OUT1, out + ".png"))
        card.resize((W * 2, H * 2), Image.NEAREST).save(os.path.join(OUT2, out + ".png"))
        print(f"wrote {out}.png ({W}x{H}) sprite={sprite} label={label}")


if __name__ == "__main__":
    build()
