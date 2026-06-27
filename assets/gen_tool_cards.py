#!/usr/bin/env python3
"""Generate the 15 BalaCraft tool cards (3 tools x 5 materials) from the hand-made
wood_sword.png template + the bold pixel alphabet extracted from the tarot banners +
the Minecraft tool sprites.

Template source: wood_sword_2.png (carries the green durability bar above the name).
Pipeline: build a BLANK card (erase the sword sprite above the bar; keep the durability
bar), then per tool paste the 3x tool sprite, rebuild the rounded nameplate tab (light
fill, darker-gray border, rounded corners, centred; width adapts to the name) sliced
from wood_sword_2.png, render the material name on it in a 4px MICRO font (the 6px tarot
alphabet is too tall there), and the tool name in the bottom cream box in the 6px bold
alphabet. Durability bar colours (Minecraft-style): green when full -> yellow ~mid ->
red when low (see the palette note alongside this file).

All 18 tools live in ONE combined sheet, assets/1x/tools.png (+2x), atlas key `bc_tools`:
  - ROW = build order / the tool's atlas_row (registry.lua): swords wood..netherite = 0..5,
    pickaxes = 6..11, shovels = 12..17.
  - COLUMN = durability frame, 0 = full bar (green) .. NFRAMES-1 = empty (red).
The card sprite's atlas cell (x = frame, y = row) is swapped at runtime by
content/tools/tool_consumabletype.lua (update_durability_frame) from uses_left/max_uses -- the
bar is baked into the sprite so it rides Balatro's card shader/parallax instead of drifting.
(This row convention is shared with the enchanted-tool atlas bc_tool_cards / gen_enchanted_tools.py.)
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))            # BalaCraft/assets
MODS = os.path.normpath(os.path.join(HERE, "..", ".."))      # Mods/
REF  = os.path.join(MODS, "assets", "reference")
GLYPHDIR = os.path.join(REF, "font", "bold")
SPRITEDIR = os.path.join(REF, "tools")
OUT1 = os.path.join(HERE, "1x")
OUT2 = os.path.join(HERE, "2x")

# --- palette sampled from wood_sword.png ---
GREY   = (151, 151, 151, 255)   # card body
RECESS = (127, 127, 127, 255)   # top nameplate interior + bottom text colour
LIGHT  = (195, 199, 203, 255)   # top text colour + bevel highlight
CREAM  = (254, 253, 249, 255)   # bottom box interior

# Template source = wood_sword_2.png (has the durability bar above the name).
src = Image.open(os.path.join(HERE, "1x", "wood_sword_2.png")).convert("RGBA")
W, H = src.size                                              # 71 x 95

# ---------- blank template ----------
def is_coloured(c):
    r, g, b, a = c
    return a > 0 and (max(r, g, b) - min(r, g, b)) > 14   # non-grey => sword pixel

GREEN_BAR = (89, 164, 0, 255)            # baked green fill in the template
EMPTY_BAR = (82, 82, 82, 255)            # neutral empty groove (the unfilled-track colour)

# Capture the WHOLE fillable bar channel per row BEFORE blanking, so each durability frame
# refills the leftmost fraction of the groove. The bar is a 4px-tall rounded rect (rows
# 73-76); the channel is the green fill PLUS the empty-track colour (82,82,82) -- the
# template's green only reaches ~85%, so we must include the track tail to hit a true 100%.
sp0 = src.load()
FILL_ROWS = {}                           # row -> sorted list of x (left -> right)
for y in range(73, 77):
    xs = [x for x in range(W) if sp0[x, y] in (GREEN_BAR, EMPTY_BAR)]
    if xs:
        FILL_ROWS[y] = sorted(xs)

blank = src.copy(); bp = blank.load()
for y in range(14, 70):                  # erase sword -> card grey (above the durability bar; protect side frame)
    for x in range(9, 62):
        if is_coloured(bp[x, y]):
            bp[x, y] = GREY
for y in range(72, 77):                    # empty the durability bar; per-frame fill painted later
    for x in range(W):
        if bp[x, y] == GREEN_BAR:
            bp[x, y] = EMPTY_BAR
for y in range(82, 90):                   # erase bottom tool-name text -> clean cream
    for x in range(12, 59):
        if bp[x, y] == RECESS:
            bp[x, y] = CREAM
# (the top nameplate is rebuilt per-card by build_nameplate, below)
blank.save("/tmp/blank_card.png")

# ---------- durability bar (baked frames) ----------
# Frames are picked at runtime by content/tools/tool_consumabletype.lua (update_durability_frame).
# NFRAMES and the ordering (frame 0 = full, last = empty) MUST match that file.
NFRAMES = 11

def durability_colour(f):                # green(full) -> yellow(half) -> red(empty)
    f = max(0.0, min(1.0, f))
    g, y, r = (89, 164, 0), (200, 180, 0), (180, 40, 20)
    (c1, c2, t) = (y, g, (f - 0.5) * 2) if f >= 0.5 else (r, y, f * 2)
    return tuple(round(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)) + (255,)

def paint_bar(card, f):
    """Fill the leftmost fraction f of the groove with the durability colour for f."""
    col = durability_colour(f)
    pc = card.load()
    for y, xs in FILL_ROWS.items():
        n = 0 if f <= 0 else max(1, round(f * len(xs)))
        for i, x in enumerate(xs):
            if i < n:
                pc[x, y] = col

def build_strip(base):
    """Horizontal strip of NFRAMES cards; frame k has fill fraction 1 - k/(NFRAMES-1)."""
    strip = Image.new("RGBA", (W * NFRAMES, H), (0, 0, 0, 0))
    for k in range(NFRAMES):
        fr = base.copy()
        paint_bar(fr, 1.0 - k / (NFRAMES - 1))
        strip.alpha_composite(fr, (k * W, 0))
    return strip

# ---------- nameplate (your rounded tab: light fill, darker-gray border, rounded corners) ----------
# Rebuilt by horizontal slicing of your wood_sword_2 nameplate so it stays CENTERED and the tab
# adapts width to the material name (shoulders shrink as the tab grows). Columns picked from the
# clean (text-erased) nameplate: 0-11 = frame/bevel/groove, 16 = shoulder, 21-23 = left cap (with
# the rounded corner), 32 = tab interior fill, 46-48 = right cap, 54 = shoulder, 59-70 = frame.
NB_Y0, NB_Y1 = 2, 14
_clean = src.copy(); _cl = _clean.load()
for y in range(4, 9):                      # erase WOOD text so the tab interior is a uniform fill
    for x in range(24, 45):
        if _cl[x, y] == RECESS:
            _cl[x, y] = LIGHT
def _colstrip(x):
    return [_clean.getpixel((x, y)) for y in range(NB_Y0, NB_Y1)]
def build_nameplate(text_w):
    # Tab interior width = text + padding (min 22), but CAPPED at 39 so the assembled band
    # is always exactly the card width (71 = 30 frame/caps + mtot + N, mtot >= 2). Without the
    # cap a long name (NETHERITE, text_w 36 -> N 42) overflowed by 3px and shoved the frame.
    N = min(max(text_w + 6, 22), 39)
    mtot = 41 - N                          # leftover becomes the two shoulders (>= 2)
    mL = (mtot + 1) // 2; mR = mtot - mL   # split for a centred tab
    cols = (list(range(0, 12)) + [16] * mL + [21, 22, 23] + [32] * N
            + [46, 47, 48] + [54] * mR + list(range(59, 71)))
    band = Image.new("RGBA", (len(cols), NB_Y1 - NB_Y0), (0, 0, 0, 0))
    for i, sx in enumerate(cols):
        for j, p in enumerate(_colstrip(sx)):
            band.putpixel((i, j), p)
    return band

# ---------- alphabet ----------
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
        out.alpha_composite(im, (x, h - im.height))   # baseline-align
        x += im.width + gap
    return out

GREY_GLYPHS = load_glyphs(RECESS)   # 6px bold, for the bottom tool name

# ---------- 4px micro font (top material name; the 6px alphabet is too tall there) ----------
FONT4 = {
    "A": ["010", "101", "111", "101"],
    "D": ["110", "101", "101", "110"],
    "E": ["111", "110", "100", "111"],
    "G": ["011", "100", "101", "011"],
    "H": ["101", "101", "111", "101"],
    "I": ["111", "010", "010", "111"],
    "L": ["100", "100", "100", "111"],
    "M": ["10001", "11011", "10101", "10001"],
    "N": ["1001", "1101", "1011", "1001"],
    "O": ["111", "101", "101", "111"],
    "R": ["110", "101", "110", "101"],
    "S": ["111", "100", "001", "111"],
    "T": ["111", "010", "010", "010"],
    "W": ["10001", "10001", "10101", "01010"],
}
def render_word4(word, colour, gap=1):
    glyphs = []
    for ch in word:
        rows = FONT4[ch]; w = len(rows[0])
        im = Image.new("RGBA", (w, 4), (0, 0, 0, 0)); p = im.load()
        for y, r in enumerate(rows):
            for x, c in enumerate(r):
                if c == "1": p[x, y] = colour
        glyphs.append(im)
    tot = sum(g.width for g in glyphs) + gap * (len(glyphs) - 1)
    out = Image.new("RGBA", (tot, 4), (0, 0, 0, 0)); x = 0
    for g in glyphs:
        out.alpha_composite(g, (x, 0)); x += g.width + gap
    return out

# ---------- tool sprite ----------
SPRITE_X, SPRITE_TOP = 11, 14            # matches the original sword placement
def paste_sprite(card, tool, material_file):
    sp = Image.open(os.path.join(SPRITEDIR, f"{tool}_{material_file}.png")).convert("RGBA")
    sp = sp.resize((sp.width * 3, sp.height * 3), Image.NEAREST)   # 16 -> 48
    card.alpha_composite(sp, (SPRITE_X, SPRITE_TOP))

# ---------- compose one card ----------
def make_card(material_word, tool_word, tool, material_file):
    card = blank.copy()
    paste_sprite(card, tool, material_file)
    # top: rebuild your rounded tab sized to the name, then 4px dark text centred on it
    mw = render_word4(material_word, RECESS)
    card.alpha_composite(build_nameplate(mw.width), (0, NB_Y0))
    card.alpha_composite(mw, ((W - mw.width) // 2, 4))     # text on the tab (rows 4-7)
    # bottom: tool name, 6px bold, grey on cream, centred in the box, baseline row 88
    tw = render_word(tool_word, GREY_GLYPHS)
    card.alpha_composite(tw, ((W - tw.width) // 2, 89 - tw.height))
    return card

# material: (display word, file token, MC sprite token, tool-id material)
MATERIALS = [
    ("WOOD",      "wood",      "wooden",    "wood"),
    ("STONE",     "stone",     "stone",     "cobblestone"),
    ("IRON",      "iron",      "iron",      "iron"),
    ("GOLD",      "gold",      "golden",    "gold"),
    ("DIAMOND",   "diamond",   "diamond",   "diamond"),
    ("NETHERITE", "netherite", "netherite", "netherite"),
]
TOOLS = [("SWORD", "sword"), ("PICKAXE", "pickaxe"), ("SHOVEL", "shovel")]

if __name__ == "__main__":
    os.makedirs(OUT1, exist_ok=True); os.makedirs(OUT2, exist_ok=True)
    NROWS = len(TOOLS) * len(MATERIALS)                  # 18 tools, one per row
    sheet = Image.new("RGBA", (W * NFRAMES, H * NROWS), (0, 0, 0, 0))
    art_lines, row = [], 0
    for tdisp, tool in TOOLS:                             # SWORD, PICKAXE, SHOVEL
        for mdisp, mtok, mspr, mid in MATERIALS:          # WOOD .. NETHERITE
            card = make_card(mdisp, tdisp, tool, mspr)    # base card, empty bar groove
            strip = build_strip(card)                     # 11 durability frames, side by side
            sheet.alpha_composite(strip, (0, row * H))    # tool -> row; column = durability frame
            art_lines.append(f"    {tool}_{mid:<11} = {{ pos = {{ x = 0, y = {row:>2} }} }},")
            row += 1
    sheet.save(os.path.join(OUT1, "tools.png"))
    sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(os.path.join(OUT2, "tools.png"))
    print(f"Generated ONE combined sheet: {NROWS} tools x {NFRAMES} durability frames "
          f"-> assets/1x/tools.png {sheet.size} (+2x at {(sheet.width * 2, sheet.height * 2)}).\n")
    print("-- single atlas (content/tools/tool_consumabletype.lua):")
    print("SMODS.Atlas { key = 'bc_tools', path = 'tools.png', px = 71, py = 95 }")
    print("\n-- per-tool pos {x = 0 (full durability), y = atlas_row}:")
    print("\n".join(art_lines))
