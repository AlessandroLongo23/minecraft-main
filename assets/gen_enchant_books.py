"""Generate enchant_cards.png from the hand-made Enchantment_Book_template.png + real
Minecraft art. The template's body is sprinkled with hand-drawn Standard Galactic Alphabet
runes (the enchantment-table script); we BLANK those mock runes and lay down a clean,
evenly-spaced GRID of the 26 SGA runes instead -- a regular geometric pattern (like the
rune field behind Minecraft's enchanting table), with the only per-card variation being
*which* rune lands in each cell. The enchanted-book sprite then floats on top.

Inputs:
  assets/1x/Enchantment_Book_template.png    -- the hand-made 71x95 purple card: a rounded
                                                frame with a rune-purple inner accent, a
                                                top-RIGHT bookmark ribbon carrying the tier
                                                numeral (ships showing a serifed "III"), a
                                                body sprinkled with mock SGA runes, and a
                                                rune-purple bottom name panel.
  assets/reference/enchant_books/<enchant>.png -- per-enchant book art (Even Better
                                                Enchanted Books pack), one distinct vanilla-
                                                style design each, so NO tint is applied.
                                                BalaCraft 'durability' -> 'unbreaking'.
  assets/reference/font/bold/<A-Z>.png       -- the 6px bold pixel alphabet (tarot-extracted),
                                                the same font the tool & food cards use.

The rune tiles are a hand-condensed 5x5 set (RUNES_5X5 below) of the authentic SGA glyphs
(the originals, in assets/reference/font/sga, are 7px tall; here every rune is normalised to
a uniform 5x5 cell so they tile on a regular grid).

Per book card (one per type x tier):
  1. start from BLANK = template with the mock background runes repainted to body and the
     baked "III" repainted to the bookmark fill.
  2. lay a regular, well-spaced grid of subtle 5x5 runes across the body (fixed positions; only
     the rune in each cell is random, seeded per card), clipped to the body so they pass BEHIND
     the frame / bookmark / name panel (clipped by them, not skipped).
  3. paste the enchanted-book sprite at 3x on top, centred by its opaque bbox in the body.
  4. render the type NAME (SHARPNESS / DURABILITY / FORTUNE) on the bottom panel, 6px bold dark.
  5. draw the tier numeral (I / II / III) on the bookmark, in the template's serifed Roman style.

Output: assets/1x/enchant_cards.png (213x285, 3 cols x 3 rows; cells 71x95) + assets/2x.
Atlas key bc_enchant_cards; col = tier-1, row = type index (sharpness,durability,fortune).
Mirrors the build order of PB_UTIL.ENCHANT_BOOKS (content/enhancements/registry.lua).

Tunables (env): RUNE_GAP = px between grid tiles (default 1); BOOK_SCALE = sprite upscale
(default 3). Run:  python BalaCraft/assets/gen_enchant_books.py   (from the Mods/ parent).
"""
import os
import random
from collections import deque
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))           # BalaCraft/assets
MODS = os.path.normpath(os.path.join(HERE, "..", ".."))     # Mods/
REF = os.path.join(MODS, "assets", "reference")
BOOKS_DIR = os.path.join(REF, "enchant_books")
BOOK_TEX = {"sharpness": "sharpness.png", "durability": "unbreaking.png", "fortune": "fortune.png"}
GLYPHDIR = os.path.join(REF, "font", "bold")                # name font
OUT1 = os.path.join(HERE, "1x")
OUT2 = os.path.join(HERE, "2x")

CARD_W, CARD_H = 71, 95

# Template palette (sampled from Enchantment_Book_template.png).
BODY = (100, 87, 135, 255)     # main card body (runes are clipped to this)
DARK = (88, 85, 97, 255)       # frame / baked numeral; also the name + new numeral colour
LIGHT = (202, 194, 231, 255)   # frame highlight + bookmark fill
RUNE = (154, 133, 187, 255)    # template inner accent + name panel (structural, untouched)
GRID_RUNE = (124, 108, 158, 255)   # the scattered grid runes -- a subtler lift off BODY than
#                                    the structural accent, so they recede into the background

# Type order MUST mirror PB_UTIL.ENCHANT_ORDER (registry.lua) -> atlas row.
TYPES = [
    ("sharpness",  "SHARPNESS"),    # row 0
    ("durability", "DURABILITY"),   # row 1
    ("fortune",    "FORTUNE"),      # row 2
]
TIERS = ["I", "II", "III"]          # col 0..2

BOOK_SCALE = int(os.environ.get("BOOK_SCALE", "3"))
RUNE_GAP = int(os.environ.get("RUNE_GAP", "3"))

template = Image.open(os.path.join(OUT1, "Enchantment_Book_template.png")).convert("RGBA")


# ---------- the 26 SGA runes, hand-condensed to a uniform 5x5 cell ----------
# Each is the authentic Standard Galactic Alphabet letterform (cf. assets/reference/font/sga)
# squeezed into 5x5 so they tile on a regular grid. '#' = rune pixel.
RUNES_5X5 = {
    "A": ["..##.", ".#..#", ".#...", ".#...", "##..."],
    "B": ["..#..", "..#..", "...#.", "....#", "#####"],
    "C": [".#...", ".....", ".#...", ".##..", "..#.."],
    "D": ["#####", ".....", "##...", "..#..", "...##"],
    "E": ["#...#", "#....", "#....", "#....", "#####"],
    "F": [".....", "#####", ".....", "#.#.#", "....."],
    "G": ["...#.", "...#.", ".###.", "...#.", "...#."],
    "H": ["#####", ".....", "#####", "..#..", "..#.."],
    "I": ["..#..", "..#..", ".....", "..#..", "..#.."],
    "J": ["..#..", ".....", "..#..", ".....", "..#.."],
    "K": ["..#..", "..#..", "#.#.#", "..#..", "..#.."],
    "L": [".#...", ".#.#.", ".#...", ".#.#.", ".#..."],
    "M": ["#...#", "....#", "....#", "....#", "#####"],
    "N": ["#..#.", "#..#.", "..#..", ".#...", "#...."],
    "O": ["####.", "...#.", "..#..", ".#...", "#...."],
    "P": [".#.#.", "...#.", ".#.#.", ".#.#.", ".#.#."],
    "Q": ["..#..", "#####", "....#", "....#", "#####"],
    "R": ["#..#.", ".....", ".....", ".....", "#..#."],
    "S": [".#...", ".#...", ".##..", "..#..", "..#.."],
    "T": ["#####", "....#", "....#", "....#", "....#"],
    "U": [".....", ".#.#.", ".....", "#####", "....."],
    "V": ["..#..", "..#..", "#####", ".....", "#####"],
    "W": ["..#..", ".....", ".....", "#...#", "....."],
    "X": ["#...#", "...#.", "..#..", ".#...", "#...."],
    "Y": [".#.#.", ".#.#.", ".#.#.", ".#.#.", ".#.#."],
    "Z": ["..#..", ".#.#.", "#...#", "#...#", "#...#"],
}
TILE = 5


def build_tiles():
    tiles = {}
    for ch, rows in RUNES_5X5.items():
        im = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0)); p = im.load()
        for y, row in enumerate(rows):
            for x, c in enumerate(row):
                if c == "#":
                    p[x, y] = GRID_RUNE
        tiles[ch] = im
    return tiles


TILES = build_tiles()
TILE_KEYS = sorted(TILES)


# ---------- connected components of an exact colour (8-connected) ----------
def components(img, color):
    px = img.load()
    pts = [(x, y) for y in range(CARD_H) for x in range(CARD_W) if px[x, y] == color]
    pset, seen, out = set(pts), set(), []
    for p in pts:
        if p in seen:
            continue
        comp, q = [], deque([p]); seen.add(p)
        while q:
            cx, cy = q.popleft(); comp.append((cx, cy))
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    n = (cx + dx, cy + dy)
                    if n in pset and n not in seen:
                        seen.add(n); q.append(n)
        out.append(comp)
    return out


# ---------- blank: mock runes -> body, baked numeral -> bookmark fill ----------
# The rune-purple is shared by the *structural* inner accent + name panel (one big component)
# and the *decorative* mock runes (small isolated components). Keep the largest, repaint the
# rest to body. The baked numeral is the small DARK component isolated inside the bookmark
# (the only DARK that isn't the frame); repaint it to the bookmark fill and remember its box.
def make_blank():
    b = template.copy(); p = b.load()
    rcomps = sorted(components(b, RUNE), key=len, reverse=True)
    for comp in rcomps[1:]:                       # everything but the structural accent/panel
        for (x, y) in comp:
            p[x, y] = BODY
    dcomps = sorted(components(b, DARK), key=len, reverse=True)
    numeral_box = None
    for comp in dcomps[1:]:                        # everything but the frame == the baked numeral
        xs = [c[0] for c in comp]; ys = [c[1] for c in comp]
        numeral_box = (min(xs), min(ys), max(xs), max(ys))
        for (x, y) in comp:
            p[x, y] = LIGHT
    return b, numeral_box


BLANK, NUMERAL_BOX = make_blank()
# Bookmark numeral anchor: horizontal centre + top row of the baked "III".
TAB_CX = (NUMERAL_BOX[0] + NUMERAL_BOX[2]) // 2 if NUMERAL_BOX else 52
TAB_TOP = NUMERAL_BOX[1] if NUMERAL_BOX else 7


# ---------- regular rune grid (fixed cells; only the rune per cell is random) ----------
def grid_positions(lo, hi, tile, gap):
    """Top-left coords of evenly-spaced tiles centred within [lo, hi)."""
    pitch = tile + gap
    span = hi - lo
    n = (span - tile) // pitch + 1
    used = (n - 1) * pitch + tile
    start = lo + (span - used) // 2
    return [start + i * pitch for i in range(n)]


GX0, GX1 = 9, 62        # body span the grid fills (clipped to body when drawn)
GY0, GY1 = 6, 79
COLS = grid_positions(GX0, GX1, TILE, RUNE_GAP)
ROWS = grid_positions(GY0, GY1, TILE, RUNE_GAP)


def draw_grid(blank, seed):
    rng = random.Random(seed)
    card = blank.copy()
    bpx = blank.load()
    for ty in ROWS:
        for tx in COLS:
            tp = TILES[rng.choice(TILE_KEYS)].load()
            for y in range(TILE):
                for x in range(TILE):
                    if tp[x, y][3] == 0:
                        continue
                    px_, py_ = tx + x, ty + y
                    # clip to the body only: runes paint just where the card is body, so they
                    # fall BEHIND the bookmark / frame / name panel (clipped, not skipped).
                    if 0 <= px_ < CARD_W and 0 <= py_ < CARD_H and bpx[px_, py_] == BODY:
                        card.putpixel((px_, py_), GRID_RUNE)
    return card


# ---------- name font (same loader as gen_foods.py / gen_tool_cards.py) ----------
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


# ---------- name on the bottom panel (rune-purple, rows 81-90) ----------
PANEL_X0, PANEL_X1 = 9, 61
PANEL_Y0, PANEL_Y1 = 81, 90


def draw_name(card, name):
    w = render_word(name)
    if w.width > (PANEL_X1 - PANEL_X0):                # fall back to tight kerning if too wide
        w = render_word(name, gap=0)
    py = PANEL_Y0 + ((PANEL_Y1 - PANEL_Y0 + 1) - w.height) // 2
    card.alpha_composite(w, ((CARD_W - w.width) // 2, py))


# ---------- tier numeral on the bookmark, template's serifed Roman style ----------
# N verticals (1px wide, 2px pitch) joined by a 1px top + 1px bottom serif bar overhanging 1px
# each side -- exactly how the baked "III" is drawn. Centred on TAB_CX, top at TAB_TOP.
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
BODY_CX, BODY_CY = 35, 48


def paste_book(card, tid):
    sp = Image.open(os.path.join(BOOKS_DIR, BOOK_TEX[tid])).convert("RGBA")
    sp = sp.resize((sp.width * BOOK_SCALE, sp.height * BOOK_SCALE), Image.NEAREST)
    bb = sp.getbbox()
    bcx = (bb[0] + bb[2]) / 2.0
    bcy = (bb[1] + bb[3]) / 2.0
    card.alpha_composite(sp, (round(BODY_CX - bcx), round(BODY_CY - bcy)))


# ---------- compose one card ----------
def make_card(tid, name, tier_n, seed):
    c = draw_grid(BLANK, seed)     # geometric rune grid behind...
    paste_book(c, tid)             # ...the book floating on top
    draw_name(c, name)
    draw_numeral(c, tier_n)
    return c


if __name__ == "__main__":
    os.makedirs(OUT1, exist_ok=True); os.makedirs(OUT2, exist_ok=True)
    cols, rows = len(TIERS), len(TYPES)
    sheet = Image.new("RGBA", (CARD_W * cols, CARD_H * rows), (0, 0, 0, 0))
    pos_lines = []
    for ti, (tid, name) in enumerate(TYPES):
        for tier in range(1, cols + 1):
            card = make_card(tid, name, tier, seed=2000 + ti * 4 + tier)
            sheet.alpha_composite(card, ((tier - 1) * CARD_W, ti * CARD_H))
            pos_lines.append(f"    {tid}_{tier} -> pos {{ x = {tier - 1}, y = {ti} }}")
    sheet.save(os.path.join(OUT1, "enchant_cards.png"))
    sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(
        os.path.join(OUT2, "enchant_cards.png"))
    print("wrote assets/1x/enchant_cards.png", sheet.size, "+ 2x")
    print(f"  numeral anchor TAB_CX={TAB_CX} TAB_TOP={TAB_TOP}; grid {len(COLS)}x{len(ROWS)} "
          f"(gap {RUNE_GAP}); cols={COLS}; rows={ROWS}")
    print("\n-- atlas (content/enhancements/registry.lua):")
    print("SMODS.Atlas { key = 'bc_enchant_cards', path = 'enchant_cards.png', px = 71, py = 95 }")
    print("\n-- per-book pos (col = tier-1, row = type index):")
    print("\n".join(pos_lines))
