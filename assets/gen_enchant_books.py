"""Generate enchant_cards.png from the hand-made Enchantment_Book_template.png + real
Minecraft art, mirroring assets/gen_foods.py (template + 3x MC sprite + 6px bold alphabet).

Inputs:
  assets/1x/Enchantment_Book_template.png   -- the hand-made 71x95 purple card: a top-left
                                               tier tab (ships showing a serifed "III"), a
                                               body for the book sprite, and a light bottom
                                               name panel (rows 83-90).
  assets/reference/enchant/enchanted_book.png -- the real MC enchanted-book item, 16x16
                                               (downsampled from the wiki render).
  assets/reference/font/bold/<A-Z>.png       -- the 6px bold pixel alphabet (tarot-extracted),
                                               the same font the tool & food cards use.

Per book card (one per type x tier):
  1. BLANK the baked "III" in the tier tab (repaint its dark pixels to the tab interior).
  2. paste the 16x16 enchanted-book sprite at 3x (-> 48px), centred by its opaque bbox in the
     body, TINTED to the type's colour (Sharpness=orange, Durability=cyan, Fortune=green) so the
     three types read apart at a glance (the user picked "per-type tinted book").
  3. render the type NAME (SHARPNESS / DURABILITY / FORTUNE) on the bottom panel in dark 6px bold.
  4. draw the tier numeral (I / II / III) in the tab, in the template's serifed Roman style.

Output: assets/1x/enchant_cards.png (213x285, 3 cols x 3 rows; cells 71x95) + assets/2x.
Atlas key bc_enchant_cards; col = tier-1, row = type index (sharpness,durability,fortune).
Mirrors the build order of PB_UTIL.ENCHANT_BOOKS (content/enhancements/registry.lua).

Run:  python assets/gen_enchant_books.py   (from the Mods/ parent, like the other gen scripts)
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))           # BalaCraft/assets
MODS = os.path.normpath(os.path.join(HERE, "..", ".."))     # Mods/
REF  = os.path.join(MODS, "assets", "reference")
# Per-enchantment book art (Even Better Enchanted Books pack), staged one PNG per enchant. Each is
# already a distinct vanilla-style design, so NO tint is applied. BalaCraft 'durability' -> 'unbreaking'.
BOOKS_DIR = os.path.join(REF, "enchant_books")
BOOK_TEX = {"sharpness": "sharpness.png", "durability": "unbreaking.png", "fortune": "fortune.png"}
GLYPHDIR   = os.path.join(REF, "font", "bold")
OUT1 = os.path.join(HERE, "1x")
OUT2 = os.path.join(HERE, "2x")

CARD_W, CARD_H = 71, 95

# Template palette (sampled from Enchantment_Book_template.png).
DARK  = (89, 79, 103, 255)     # frame / baked numeral colour; also the name + new numeral colour
LIGHT = (211, 180, 255, 255)   # tab interior + bottom name-panel fill

# Type order MUST mirror PB_UTIL.ENCHANT_ORDER (registry.lua) -> atlas row.
# Colours reuse the mod's existing enchant colour language (assets/gen_enchanted_tools.py:
# Smithing/sword orange, durability cyan, Fortune emerald green).
TYPES = [
    ("sharpness",  "SHARPNESS",  (235, 150, 45)),   # row 0
    ("durability", "DURABILITY", (80, 210, 235)),   # row 1
    ("fortune",    "FORTUNE",    (70, 205, 95)),    # row 2
]
TIERS = ["I", "II", "III"]                          # col 0..2

template = Image.open(os.path.join(OUT1, "Enchantment_Book_template.png")).convert("RGBA")


# ---------- blank the baked tier numeral ----------
# The baked "III" lives at x9..17, y5..11 inside the tab; repaint its dark pixels to the tab
# interior LIGHT (leaves the tab frame at x7 / bottom border at y13 untouched).
def make_blank():
    b = template.copy(); p = b.load()
    for y in range(5, 12):
        for x in range(9, 18):
            if p[x, y] == DARK:
                p[x, y] = LIGHT
    return b


BLANK = make_blank()


# ---------- alphabet (same loader as gen_foods.py / gen_tool_cards.py) ----------
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


GLYPHS = load_glyphs(DARK)


def render_word(word, gap=1):
    gs = [GLYPHS[c] for c in word if c != " "]
    w = sum(im.width for im in gs) + gap * (len(gs) - 1)
    h = max(im.height for im in gs)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0)); x = 0
    for im in gs:
        out.alpha_composite(im, (x, h - im.height))   # baseline-align (all 6px)
        x += im.width + gap
    return out


# ---------- name on the bottom panel (rows ~83-90, x 7..63) ----------
PANEL_X0, PANEL_X1 = 7, 63
PANEL_Y = 84                                           # 6px name centred in the 8px panel


def draw_name(card, name):
    w = render_word(name)
    if w.width > (PANEL_X1 - PANEL_X0):                # fall back to tight kerning if too wide
        w = render_word(name, gap=0)
    card.alpha_composite(w, ((CARD_W - w.width) // 2, PANEL_Y))


# ---------- tier numeral in the template's serifed Roman style ----------
# N verticals (1px wide, 2px pitch) joined by a 1px top + 1px bottom serif bar that overhangs
# 1px each side -- exactly how the baked "III" is drawn. Centred on the tab interior, nudged
# 1px left of the baked numeral's centre (cx=12,cy=8).
TAB_CX, TAB_TOP = 12, 6


def draw_numeral(card, n):
    w = 2 * n + 1                                       # I=3, II=5, III=7
    x0 = TAB_CX - w // 2
    p = card.load()
    for dx in range(w):                                # top + bottom serif bars
        p[x0 + dx, TAB_TOP] = DARK
        p[x0 + dx, TAB_TOP + 4] = DARK
    for i in range(n):                                 # the verticals
        vx = x0 + 1 + 2 * i
        for dy in range(1, 4):
            p[vx, TAB_TOP + dy] = DARK


# ---------- per-enchant book sprite (centred by opaque bbox in the body) ----------
BODY_CX, BODY_CY = 35, 47


def paste_book(card, tid):
    sp = Image.open(os.path.join(BOOKS_DIR, BOOK_TEX[tid])).convert("RGBA")
    sp = sp.resize((sp.width * 3, sp.height * 3), Image.NEAREST)   # 16 -> 48
    bb = sp.getbbox()
    bcx = (bb[0] + bb[2]) / 2.0
    bcy = (bb[1] + bb[3]) / 2.0
    card.alpha_composite(sp, (round(BODY_CX - bcx), round(BODY_CY - bcy)))


# ---------- compose ----------
def make_card(tid, name, tier_n):
    c = BLANK.copy()
    paste_book(c, tid)
    draw_name(c, name)
    draw_numeral(c, tier_n)
    return c


if __name__ == "__main__":
    os.makedirs(OUT1, exist_ok=True); os.makedirs(OUT2, exist_ok=True)
    cols, rows = len(TIERS), len(TYPES)
    sheet = Image.new("RGBA", (CARD_W * cols, CARD_H * rows), (0, 0, 0, 0))
    pos_lines = []
    for ti, (tid, name, rgb) in enumerate(TYPES):
        for tier in range(1, cols + 1):
            card = make_card(tid, name, tier)
            sheet.alpha_composite(card, ((tier - 1) * CARD_W, ti * CARD_H))
            pos_lines.append(f"    {tid}_{tier} -> pos {{ x = {tier - 1}, y = {ti} }}")
    sheet.save(os.path.join(OUT1, "enchant_cards.png"))
    sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(
        os.path.join(OUT2, "enchant_cards.png"))
    print("wrote assets/1x/enchant_cards.png", sheet.size, "+ 2x")
    print("\n-- atlas (content/enhancements/registry.lua):")
    print("SMODS.Atlas { key = 'bc_enchant_cards', path = 'enchant_cards.png', px = 71, py = 95 }")
    print("\n-- per-book pos (col = tier-1, row = type index):")
    print("\n".join(pos_lines))
