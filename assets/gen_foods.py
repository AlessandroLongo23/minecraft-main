"""Generate the food card sheet from the hand-made template + real Minecraft art.

  assets/1x/Food_Template.png -> assets/{1x,2x}/food_cards.png  (the sheet the game's
                                 bc_food_cards atlas loads)

Inputs:
  assets/1x/Food_Template.png          -- the hand-made 71x95 card (cream nameplate, a
                                          wheat-field body background, and a recessed bottom
                                          strip with 6 placeholder drumsticks). The
                                          placeholders are blanked and replaced by the real
                                          4-slot hunger haunches at compose time.
  assets/reference/food/<id>.png       -- real MC item sprites, 16x16 (Invicon_* from wiki).
  assets/reference/hunger/{full,half,empty}.png -- real MC haunch icons, 9x9.
  assets/reference/font/bold/<A-Z>.png -- the 6px bold pixel alphabet (tarot-extracted).

Per food (order mirrors content/foods/registry.lua):
  1. BLANK the template -- erase the 6 placeholder drumsticks by repainting the strip's
     flat tan interior (the icons sit between the recessed bevel frame).
  2. paste the 16x16 food sprite at 3x (-> 48px), centred by its opaque bbox in the body.
  3. render the NAME on the cream nameplate in dark-brown 6px bold caps; multi-word
     names wrap to two lines (the plate fits 1+6+1+6+1 = 15px, e.g. COOKED / CHICKEN).
  4. paint the food's hunger value across the 4-slot strip as full/half/empty drumsticks
     (2 hunger points = 1 drumstick, MC-style; the richest food is 8 pts = 4 full),
     filling left -> right, centred in the strip with 1px padding between haunches.

Output: assets/{1x,2x}/food_cards.png (213x285, 3x3 grid; cells 71x95).
Atlas + cell positions live in content/foods/registry.lua (bc_food_cards -> food_cards.png).
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))           # BalaCraft/assets
MODS = os.path.normpath(os.path.join(HERE, "..", ".."))     # Mods/
REF  = os.path.join(MODS, "assets", "reference")
FOODDIR   = os.path.join(REF, "food")
HUNGERDIR = os.path.join(REF, "hunger")
GLYPHDIR  = os.path.join(REF, "font", "bold")
OUT1 = os.path.join(HERE, "1x")
OUT2 = os.path.join(HERE, "2x")

CARD_W, CARD_H = 71, 95
COLS, ROWS = 3, 3

NAME_COLOUR = (94, 60, 23, 255)     # dark card-frame brown, reads on the cream nameplate
STRIP_TAN   = (226, 177, 145, 255)  # bottom-strip interior background

# id, display NAME (caps; space => 2-line wrap), hunger points. Mirrors registry.lua.
FOODS = [
    ("carrot",          "CARROT",          3),
    ("potato",          "POTATO",          1),
    ("apple",           "APPLE",           4),
    ("baked_potato",    "BAKED POTATO",    5),
    ("cooked_chicken",  "COOKED CHICKEN",  6),
    ("cooked_porkchop", "COOKED PORKCHOP", 8),
]

# (template filename, output sheet basename). One template -> the sheet the game loads.
TEMPLATES = [
    ("Food_Template.png", "food_cards.png"),
]


# ---------- template + blank ----------
def make_blank(template):
    """Erase the placeholder drumsticks (incl. their dash-like tops on row 79): per strip
    interior row, repaint the tan span (between the recessed bevel frame) with the flat tan
    background colour. Interior spans rows 78-88 (top frame 77, bottom frame 89)."""
    b = template.copy(); p = b.load()
    for y in range(78, 89):
        xs = [x for x in range(CARD_W) if p[x, y] == STRIP_TAN]
        if xs:
            for x in range(min(xs), max(xs) + 1):
                p[x, y] = STRIP_TAN
    return b


# ---------- alphabet ----------
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
        out.alpha_composite(im, (x, h - im.height))   # baseline-align (all 6px here)
        x += im.width + gap
    return out


def draw_name(card, name):
    lines = name.split(" ")
    if len(lines) == 1:
        w = render_word(lines[0])
        card.alpha_composite(w, ((CARD_W - w.width) // 2, 10))    # 1 line: centred in plate
    else:
        for ln, ty in zip(lines, (7, 14)):                        # 2 lines: 1+6+1+6+1
            w = render_word(ln)
            card.alpha_composite(w, ((CARD_W - w.width) // 2, ty))


# ---------- food sprite (centred by opaque bbox in the card body) ----------
BODY_CX, BODY_CY = 35, 49


def paste_food(card, fid):
    sp = Image.open(os.path.join(FOODDIR, fid + ".png")).convert("RGBA")
    sp = sp.resize((sp.width * 3, sp.height * 3), Image.NEAREST)   # 16 -> 48
    bb = sp.getbbox()
    bcx = (bb[0] + bb[2]) / 2.0
    bcy = (bb[1] + bb[3]) / 2.0
    card.alpha_composite(sp, (round(BODY_CX - bcx), round(BODY_CY - bcy)))


# ---------- hunger strip (4 slots = the 8pt max; 9px haunch + 1px pad, centred) ----------
HAUNCH = {k: Image.open(os.path.join(HUNGERDIR, k + ".png")).convert("RGBA")
          for k in ("full", "half", "empty")}
HAUNCH_W, GAP, SLOTS, STRIP_Y = 9, 1, 4, 79
PITCH = HAUNCH_W + GAP
STRIP_X0 = (CARD_W - (SLOTS * HAUNCH_W + (SLOTS - 1) * GAP)) // 2   # centred in the card


def paste_hunger(card, hunger):
    for i in range(SLOTS):
        pts = hunger - i * 2
        state = "full" if pts >= 2 else ("half" if pts == 1 else "empty")
        card.alpha_composite(HAUNCH[state], (STRIP_X0 + i * PITCH, STRIP_Y))


# ---------- compose ----------
def make_card(blank, fid, name, hunger):
    c = blank.copy()
    paste_food(c, fid)
    draw_name(c, name)
    paste_hunger(c, hunger)
    return c


def build_sheet(template_file):
    template = Image.open(os.path.join(OUT1, template_file)).convert("RGBA")
    blank = make_blank(template)
    sheet = Image.new("RGBA", (CARD_W * COLS, CARD_H * ROWS), (0, 0, 0, 0))
    for i, (fid, name, hunger) in enumerate(FOODS):
        card = make_card(blank, fid, name, hunger)
        cx, cy = (i % COLS) * CARD_W, (i // COLS) * CARD_H
        sheet.alpha_composite(card, (cx, cy))
    return sheet


if __name__ == "__main__":
    os.makedirs(OUT1, exist_ok=True); os.makedirs(OUT2, exist_ok=True)
    for template_file, out_name in TEMPLATES:
        sheet = build_sheet(template_file)
        sheet.save(os.path.join(OUT1, out_name))
        sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(os.path.join(OUT2, out_name))
        print("wrote assets/1x/" + out_name, sheet.size, "+ 2x")
