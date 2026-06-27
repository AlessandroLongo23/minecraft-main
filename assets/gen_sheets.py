"""Generate the Sheet consumable art from the hand-made template + the recolored MC paper texture.

A Sheet is a thin pressed plate of a material, so its sprite is the genuine 16x16 Minecraft PAPER
item texture RECOLORED per material (gold paper, iron paper, ...) -- not a block face. The paper's
own shading/highlight is preserved (luminance colorize: lightest paper -> the material tint), so each
sheet reads as a tinted sheet of paper.

Outputs (1x + 2x):
  assets/1x/sheet_cards.png  -> 71x95 cells, 3x3 grid (the bc_sheet_cards atlas; consumable faces)
  assets/1x/sheet_icons.png  -> 34x34 cells, 3x3 grid (the bc_sheet_icons atlas; crafting/anvil icons)

Inputs:
  assets/1x/Sheet_template.png        -- the hand-made 71x95 card (grey metal-plate frame + dark panel).
  assets/reference/sheet/paper.png    -- the genuine 16x16 MC paper item texture (recolored per material).
  assets/reference/font/bold/<A-Z>.png -- the 6px bold pixel alphabet (tarot-extracted).

Per sheet (order + cells MUST mirror content/sheets/registry.lua `pos`/`icon`):
  CARD = template + the recolored paper scaled 3x centered on the panel + the NAME in 6px bold cream.
  ICON = the recolored paper scaled 2x, centered FRAMELESS in a 34x34 cell (matches gen_resources icons).
"""
import os
from PIL import Image, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))           # BalaCraft/assets
MODS = os.path.normpath(os.path.join(HERE, "..", ".."))     # Mods/
REF  = os.path.join(MODS, "assets", "reference")
SHEETDIR = os.path.join(REF, "sheet")
GLYPHDIR = os.path.join(REF, "font", "bold")
OUT1 = os.path.join(HERE, "1x")
OUT2 = os.path.join(HERE, "2x")

CARD_W, CARD_H = 71, 95
ICON = 34
COLS, ROWS = 3, 3

NAME_COLOUR = (78, 78, 78, 255)      # the dark panel-background grey -> engraved-label look,
                                     # high-contrast (dark on the light 191-grey nameplate)
BODY_CX, BODY_CY = 35, 42            # block-face centre on the panel
# The name is centred in the metal NAMEPLATE band at the card bottom -- its centre is DETECTED from
# the template (the longest near-full-width bright run in the bottom third), not a hardcoded baseline,
# so the text stays centred even if the plate art shifts. See _detect_nameplate / NAME_CX, NAME_CY.

# id, display NAME. Order + cell (row-major) MUST match content/sheets/registry.lua pos/icon.
SHEETS = [
    ("gold", "GOLD"), ("iron", "IRON"), ("glass", "GLASS"),
    ("diamond", "DIAMOND"), ("emerald", "EMERALD"), ("redstone", "REDSTONE"),
    ("lapis", "LAPIS"), ("coal", "COAL"),
]


def nn(img, factor):
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


# Per-material tint = the colour the LIGHTEST paper pixels become. Brightened from the genuine
# block-face averages so even the dark materials (coal/lapis/redstone) stay legible on the dark
# card panel. The paper's darkest shading maps to 0.42x of this.
PAPER_TINT = {
    "gold":     (245, 205, 70),
    "iron":     (201, 206, 213),
    "glass":    (188, 224, 231),
    "diamond":  (122, 240, 230),
    "emerald":  (60, 200, 100),
    "redstone": (201, 46, 30),
    "lapis":    (58, 98, 188),
    "coal":     (96, 93, 98),
}

_PAPER = Image.open(os.path.join(SHEETDIR, "paper.png")).convert("RGBA")
_PAPER_A = _PAPER.getchannel("A")
_PAPER_L = _PAPER.convert("L")


def recolor_paper(sid):
    """The MC paper texture tinted to `sid`: lightest paper -> PAPER_TINT, darkest -> 0.42x of it,
    keeping the paper's own shading + alpha. Returns a 16x16 RGBA sprite."""
    white_c = PAPER_TINT[sid]
    black_c = tuple(int(v * 0.42) for v in white_c)
    col = ImageOps.colorize(_PAPER_L, black=black_c, white=white_c).convert("RGBA")
    col.putalpha(_PAPER_A)
    return col


# ---------- alphabet (6px bold, tarot-extracted) ----------
def load_glyphs(colour):
    g = {}
    for f in os.listdir(GLYPHDIR):
        if not f.endswith(".png"):
            continue
        im = Image.open(os.path.join(GLYPHDIR, f)).convert("RGBA"); px = im.load()
        for y in range(im.height):
            for x in range(im.width):
                if px[x, y][3] > 0:
                    px[x, y] = colour
        g[f[0]] = im
    return g


GLYPHS = load_glyphs(NAME_COLOUR)


def render_word(word, gap=1):
    gs = [GLYPHS[c] for c in word if c != " "]
    w = sum(im.width for im in gs) + gap * (len(gs) - 1)
    h = max(im.height for im in gs)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0)); x = 0
    for im in gs:
        out.alpha_composite(im, (x, h - im.height))
        x += im.width + gap
    return out


# ---------- nameplate detection ----------
def _detect_nameplate(tmpl):
    """Centre (cx, cy) of the metal nameplate band -- the longest contiguous run of near-full-width
    bright rows in the bottom third of the template. Used to centre the name so it sits in the plate."""
    px = tmpl.load(); W, H = tmpl.size
    runs, cur = [], None
    for y in range(H * 55 // 95, H):                       # bottom region only
        xs = [x for x in range(W)
              if (px[x, y][0] + px[x, y][1] + px[x, y][2]) / 3 > 120 and px[x, y][3] > 40]
        if len(xs) >= 40:                                  # a near-full-width (plate) row
            if cur is None:
                cur = [y, y, min(xs), max(xs)]
            else:
                cur[1] = y; cur[2] = min(cur[2], min(xs)); cur[3] = max(cur[3], max(xs))
        elif cur:
            runs.append(cur); cur = None
    if cur:
        runs.append(cur)
    band = max(runs, key=lambda r: r[1] - r[0])            # the tallest band == the nameplate
    return (band[2] + band[3]) / 2.0, (band[0] + band[1]) / 2.0


_TEMPLATE = Image.open(os.path.join(OUT1, "Sheet_template.png")).convert("RGBA")
NAME_CX, NAME_CY = _detect_nameplate(_TEMPLATE)


# ---------- card ----------
def make_card(template, sid, name):
    c = template.copy()
    block = nn(recolor_paper(sid), 3)   # recolored paper, 16 -> 48
    bb = block.getbbox() or (0, 0, block.width, block.height)
    bcx, bcy = (bb[0] + bb[2]) / 2.0, (bb[1] + bb[3]) / 2.0
    c.alpha_composite(block, (round(BODY_CX - bcx), round(BODY_CY - bcy)))
    w = render_word(name)
    # centre the word on the detected nameplate (centre of a span of size n is offset (n-1)/2).
    nx = round(NAME_CX - (w.width - 1) / 2.0)
    ny = round(NAME_CY - (w.height - 1) / 2.0)
    c.alpha_composite(w, (nx, ny))
    return c


def build_cards():
    template = _TEMPLATE
    sheet = Image.new("RGBA", (CARD_W * COLS, CARD_H * ROWS), (0, 0, 0, 0))
    for i, (sid, name) in enumerate(SHEETS):
        card = make_card(template, sid, name)
        cx, cy = (i % COLS) * CARD_W, (i // COLS) * CARD_H
        sheet.alpha_composite(card, (cx, cy))
    sheet.save(os.path.join(OUT1, "sheet_cards.png"))
    sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(os.path.join(OUT2, "sheet_cards.png"))
    print("wrote sheet_cards.png", sheet.size, "+ 2x")


def build_icons():
    sheet = Image.new("RGBA", (ICON * COLS, ICON * ROWS), (0, 0, 0, 0))
    for i, (sid, _name) in enumerate(SHEETS):
        block = nn(recolor_paper(sid), 2)   # recolored paper, 16 -> 32, frameless
        cx, cy = (i % COLS) * ICON, (i // COLS) * ICON
        ox = cx + (ICON - block.width) // 2
        oy = cy + (ICON - block.height) // 2
        sheet.alpha_composite(block, (ox, oy))
    sheet.save(os.path.join(OUT1, "sheet_icons.png"))
    sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(os.path.join(OUT2, "sheet_icons.png"))
    print("wrote sheet_icons.png", sheet.size, "+ 2x")


if __name__ == "__main__":
    os.makedirs(OUT1, exist_ok=True); os.makedirs(OUT2, exist_ok=True)
    build_cards()
    build_icons()
