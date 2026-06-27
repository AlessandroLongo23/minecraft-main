#!/usr/bin/env python3
"""Generate the single Arrow consumable card (assets/1x/arrow.png + 2x), atlas key `bc_arrow`.

Clone of gen_torch_card.py (same card chrome as the tool cards) so the Arrow reads as part of
the BalaCraft tool family, with the same two consumable differences:
  1. NO material plate on top (the arrow has no material tier).
  2. NO durability bar (single-use consumable).
The arrow sprite is the authentic Minecraft texture (assets/reference/mc_tools/arrow.png),
pasted at 4x and centred on its visible pixels. The name "ARROW" is rendered in the same 6px
bold pixel alphabet, in the bottom cream nameplate.

Template source: the same wood_sword_2.png used by gen_tool_cards.py.
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))            # BalaCraft/assets
MODS = os.path.normpath(os.path.join(HERE, "..", ".."))      # Mods/
REF  = os.path.join(MODS, "assets", "reference")
GLYPHDIR  = os.path.join(REF, "font", "bold")
SPRITEDIR = os.path.join(REF, "tools")
OUT1 = os.path.join(HERE, "1x")
OUT2 = os.path.join(HERE, "2x")

# --- palette (sampled from wood_sword_2.png; shared with gen_tool_cards.py) ---
GREY   = (151, 151, 151, 255)   # card body
RECESS = (127, 127, 127, 255)   # bevel groove + bottom text colour
LIGHT  = (195, 199, 203, 255)   # bevel highlight
CREAM  = (254, 253, 249, 255)   # bottom nameplate interior
OUTL   = (227, 222, 213, 255)   # outer card outline (carries the rounded corners)

# The MC arrow texture is a thin diagonal item; 4x makes it card-filling like the tool sprites.
SCALE = int(os.environ.get("ARROW_SCALE", "4"))

src = Image.open(os.path.join(HERE, "1x", "wood_sword_2.png")).convert("RGBA")
W, H = src.size                                              # 71 x 95
card = src.copy(); px = card.load()

def keep(x, y):
    """A pixel we must NOT touch: the rounded-corner outline or transparent margin."""
    c = px[x, y]
    return c == OUTL or c[3] == 0

# Canonical clean-body column colour (matches a clean row like y10-y15 / y68-y71):
#   outline | GREY | LIGHT bevel | RECESS groove(2) | GREY body | RECESS groove(2) | LIGHT | GREY | outline
def body_col(x):
    if x in (6, 64):           return LIGHT
    if x in (7, 8, 62, 63):    return RECESS
    return GREY                # cols 5, 9..61, 65

def fill_clean(y, grooves=True):
    for x in range(W):
        if keep(x, y):
            continue
        px[x, y] = body_col(x) if grooves else GREY

# ---------- 1) smooth out the TOP material plate, KEEPING the inner-frame border ----------
# The nameplate tab sits in the middle of the top (cols ~21-48); the rounded CORNERS and the
# horizontal top border (light highlight + recessed groove at rows 3-5) are intact in the
# template on the SHOULDERS beside the tab. So we don't flatten the top -- we just copy a clean
# shoulder column's vertical cross-section (col 15: LIGHT, RECESS, RECESS, GREY...) across the
# tab gap (cols 11-59), erasing the tab + its 'WOOD' text while the border continues unbroken.
for y in range(3, 10):
    c = src.getpixel((15, y))
    for x in range(11, 60):
        px[x, y] = c

# ---------- 1b) erase the baked-in sword sprite -> clean grey body ----------
def is_coloured(c):
    r, g, b, a = c
    return a > 0 and (max(r, g, b) - min(r, g, b)) > 14   # non-grey => sword pixel
for y in range(14, 70):
    for x in range(9, 62):
        if is_coloured(px[x, y]):
            px[x, y] = GREY

# ---------- 2) remove the DURABILITY BAR, mirroring the TOP border at the bottom ----------
# First clear the whole bar block (72-78) to clean grey body. Then build the bottom inner-frame
# border as an exact VERTICAL MIRROR of the freshly-rebuilt top border: the top's corner curve
# (highlight -> 2px groove -> the rows where it folds into the vertical side grooves) lives in
# rows 3..8, so we flip those onto rows 78..73 (dest_y = 81 - src_y). Copying the interior
# columns only (6..64) keeps each destination row's own straight-section outline at cols 4/66.
# Result: above the cream nameplate the frame closes with the same bevel as the top.
for y in range(72, 79):
    fill_clean(y, grooves=True)
for sy in range(3, 9):
    dy = 81 - sy
    for x in range(6, 65):
        px[x, dy] = px[x, sy]

# ---------- 3) erase the baked-in bottom name ("SWORD") -> clean cream ----------
for y in range(81, 91):
    for x in range(7, 64):
        if px[x, y] == RECESS:
            px[x, y] = CREAM

# ---------- 4) paste the arrow sprite (4x), centred on its visible pixels ----------
sp = Image.open(os.path.join(REF, "mc_tools", "arrow.png")).convert("RGBA")
sp = sp.resize((sp.width * SCALE, sp.height * SCALE), Image.NEAREST)
bbox = sp.getbbox()                                             # tight box of arrow pixels
bw, bh = bbox[2] - bbox[0], bbox[3] - bbox[1]
# Centre the visible torch in the card interior above the nameplate.
IX0, IX1 = 9, 61          # body columns
IY0, IY1 = 4, 78          # interior rows above the cream nameplate
cx = (IX0 + IX1) / 2
cy = (IY0 + IY1) / 2
paste_x = round(cx - (bbox[0] + bw / 2))
paste_y = round(cy - (bbox[1] + bh / 2))
card.alpha_composite(sp, (paste_x, paste_y))

# ---------- 5) render "TORCH" in the 6px bold alphabet, on the cream nameplate ----------
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
word = render_word("ARROW", glyphs)
card.alpha_composite(word, ((W - word.width) // 2, 89 - word.height))   # baseline row 88

# ---------- save ----------
if __name__ == "__main__":
    os.makedirs(OUT1, exist_ok=True); os.makedirs(OUT2, exist_ok=True)
    card.save(os.path.join(OUT1, "arrow.png"))
    card.resize((W * 2, H * 2), Image.NEAREST).save(os.path.join(OUT2, "arrow.png"))
    print(f"Wrote assets/1x/arrow.png {card.size} (+2x).")
    print("Atlas: SMODS.Atlas { key = 'bc_arrow', path = 'arrow.png', px = 71, py = 95 }")
    print(f"sprite paste at ({paste_x},{paste_y}); arrow bbox {bbox} size {bw}x{bh}")
