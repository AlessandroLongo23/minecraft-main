"""Procedurally generate PLACEHOLDER biome selection-card art (deterministic, no RNG).

Outputs:
  assets/1x/biome_cards.png  -> 90x150 cells, grid (cols = COLS, one row per dimension)
  assets/2x/biome_cards.png  -> nearest-neighbour 2x of the above

Each cell is a tall "poster": a themed vertical sky->ground gradient with a simple
silhouette on the horizon, plus a dark gradient baked into the bottom so the description
panel (drawn under the art in the UI) reads as one continuous darkening. These are
placeholders -- real pixel-art scenes are a later art task (see docs/biomes-and-dimensions.md).

Cell layout MUST match content/biomes/registry.lua (pos = {x = col, y = row}):
  row 0 (overworld): plains, forest, desert, snowy_taiga, jungle, swamp, savanna, badlands
  row 1 (nether):    nether_wastes, crimson_forest, soul_sand_valley, basalt_deltas
  row 2 (end):       central_end, end_highlands, end_midlands, end_barrens
"""
import os
from PIL import Image, ImageDraw

CELL_W, CELL_H = 90, 150
COLS = 9       # row 0 (overworld) holds 8 biomes + the ritual-only Stronghold at col 8
HORIZON = 96   # sky above, ground below

HERE = os.path.dirname(os.path.abspath(__file__))


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def vgrad(draw, x0, y0, x1, y1, c_top, c_bot):
    span = max(1, y1 - y0)
    for y in range(y0, y1):
        col = lerp(c_top, c_bot, (y - y0) / span)
        draw.line([(x0, y), (x1 - 1, y)], fill=col + (255,))


# col, row, sky(top,bot), ground(top,bot), silhouette colour, style.
BIOMES = [
    # --- Overworld (row 0) ---
    {"col": 0, "row": 0, "sky": ((135, 206, 235), (205, 232, 245)), "ground": ((124, 176, 92), (74, 116, 58)),  "sil": (58, 92, 46),    "style": "hills"},
    {"col": 1, "row": 0, "sky": ((120, 158, 168), (175, 202, 200)), "ground": ((58, 108, 52), (28, 58, 30)),    "sil": (20, 44, 22),    "style": "trees"},
    {"col": 2, "row": 0, "sky": ((242, 204, 150), (250, 232, 192)), "ground": ((224, 200, 120), (176, 146, 78)),"sil": (196, 168, 96),  "style": "dunes"},
    {"col": 3, "row": 0, "sky": ((182, 202, 222), (222, 236, 246)), "ground": ((224, 236, 242), (172, 198, 208)),"sil": (210, 228, 236),"style": "snow_trees"},
    {"col": 4, "row": 0, "sky": ((96, 154, 124), (158, 196, 166)),  "ground": ((34, 84, 40), (16, 48, 22)),    "sil": (12, 40, 18),    "style": "trees"},
    {"col": 5, "row": 0, "sky": ((124, 132, 112), (156, 160, 142)), "ground": ((74, 86, 56), (42, 52, 34)),    "sil": (38, 50, 30),    "style": "hills"},
    {"col": 6, "row": 0, "sky": ((222, 210, 150), (240, 230, 182)), "ground": ((192, 180, 96), (150, 138, 70)),"sil": (120, 100, 54),  "style": "acacia"},
    {"col": 7, "row": 0, "sky": ((232, 182, 140), (246, 212, 176)), "ground": ((182, 92, 50), (126, 58, 32)),  "sil": (150, 72, 40),   "style": "mesa"},
    # Stronghold (ritual-only Eye-of-Ender waypoint): a grey stone-hall poster.
    {"col": 8, "row": 0, "sky": ((92, 94, 104), (140, 142, 150)),   "ground": ((112, 108, 98), (66, 62, 56)),  "sil": (52, 50, 46),    "style": "pillars"},
    # --- Nether (row 1) ---
    {"col": 0, "row": 1, "sky": ((96, 24, 22), (150, 46, 32)),    "ground": ((70, 18, 16), (32, 8, 8)),    "sil": (24, 6, 6),     "style": "lava"},
    {"col": 1, "row": 1, "sky": ((120, 32, 42), (158, 56, 58)),   "ground": ((78, 22, 30), (42, 12, 18)),  "sil": (44, 12, 18),   "style": "trees"},
    {"col": 2, "row": 1, "sky": ((40, 62, 66), (74, 100, 104)),   "ground": ((30, 42, 44), (16, 24, 26)),  "sil": (96, 188, 184), "style": "soul"},
    {"col": 3, "row": 1, "sky": ((62, 56, 62), (98, 90, 94)),     "ground": ((46, 42, 48), (26, 24, 28)),  "sil": (28, 26, 32),   "style": "basalt"},
    # --- End (row 2): void sky over pale end-stone ---
    {"col": 0, "row": 2, "sky": ((12, 10, 18), (28, 22, 38)),     "ground": ((214, 210, 165), (150, 146, 112)), "sil": (44, 40, 54),    "style": "pillars"},
    {"col": 1, "row": 2, "sky": ((14, 11, 22), (32, 25, 44)),     "ground": ((210, 206, 160), (150, 146, 110)), "sil": (150, 90, 190),  "style": "chorus"},
    {"col": 2, "row": 2, "sky": ((12, 10, 18), (26, 21, 36)),     "ground": ((216, 212, 168), (156, 150, 116)), "sil": (182, 178, 140), "style": "endhills"},
    {"col": 3, "row": 2, "sky": ((10, 8, 16), (22, 18, 32)),      "ground": ((200, 196, 156), (120, 116, 92)),  "sil": (8, 6, 12),      "style": "void"},
]


def draw_silhouette(d, style, sil):
    fill = sil + (255,)
    if style == "hills":
        d.ellipse([-10, HORIZON - 16, 40, HORIZON + 20], fill=fill)
        d.ellipse([45, HORIZON - 12, 100, HORIZON + 20], fill=fill)
    elif style == "trees":
        for cx in (16, 38, 62, 80):
            d.polygon([(cx, HORIZON - 30), (cx - 12, HORIZON + 2), (cx + 12, HORIZON + 2)], fill=fill)
            d.polygon([(cx, HORIZON - 18), (cx - 14, HORIZON + 6), (cx + 14, HORIZON + 6)], fill=fill)
    elif style == "dunes":
        d.ellipse([56, 24, 78, 46], fill=(255, 238, 200, 255))
        d.ellipse([-20, HORIZON - 6, 55, HORIZON + 30], fill=fill)
        d.ellipse([40, HORIZON + 2, 110, HORIZON + 34], fill=fill)
    elif style == "snow_trees":
        for cx in (16, 38, 62, 80):
            d.polygon([(cx, HORIZON - 30), (cx - 12, HORIZON + 2), (cx + 12, HORIZON + 2)], fill=(120, 150, 140, 255))
            d.polygon([(cx, HORIZON - 30), (cx - 7, HORIZON - 14), (cx + 7, HORIZON - 14)], fill=(245, 250, 252, 255))
    elif style == "lava":
        # glowing lava lakes on the horizon
        for (x0, x1) in ((-10, 34), (40, 78), (70, 104)):
            d.ellipse([x0, HORIZON + 4, x1, HORIZON + 26], fill=(255, 140, 30, 255))
            d.ellipse([x0 + 4, HORIZON + 8, x1 - 4, HORIZON + 18], fill=(255, 200, 90, 255))
        d.line([(0, HORIZON), (CELL_W, HORIZON)], fill=fill)
    elif style == "soul":
        # teal soul-fire flames
        for cx in (20, 45, 70):
            d.polygon([(cx, HORIZON - 18), (cx - 7, HORIZON + 6), (cx + 7, HORIZON + 6)], fill=fill)
            d.polygon([(cx, HORIZON - 8), (cx - 3, HORIZON + 6), (cx + 3, HORIZON + 6)], fill=(200, 245, 240, 255))
    elif style == "basalt":
        # tall basalt columns + faint orange glow at base
        d.line([(0, HORIZON + 18), (CELL_W, HORIZON + 18)], fill=(150, 70, 20, 255))
        for x in (12, 30, 50, 68, 82):
            d.rectangle([x, HORIZON - 28, x + 8, HORIZON + 10], fill=fill)
    elif style == "pillars":
        # obsidian end pillars rising from the island
        for (x, top) in ((18, HORIZON - 40), (44, HORIZON - 52), (70, HORIZON - 34)):
            d.rectangle([x, top, x + 9, HORIZON + 4], fill=fill)
            d.rectangle([x - 1, top, x + 10, top + 4], fill=(70, 64, 88, 255))
    elif style == "chorus":
        # branching purple chorus plants
        for cx in (22, 48, 70):
            d.line([(cx, HORIZON + 2), (cx, HORIZON - 26)], fill=fill, width=3)
            d.line([(cx, HORIZON - 14), (cx + 10, HORIZON - 22)], fill=fill, width=2)
            d.line([(cx, HORIZON - 20), (cx - 9, HORIZON - 28)], fill=fill, width=2)
            d.ellipse([cx - 3, HORIZON - 30, cx + 3, HORIZON - 24], fill=(190, 130, 220, 255))
    elif style == "endhills":
        d.ellipse([-12, HORIZON - 8, 42, HORIZON + 18], fill=fill)
        d.ellipse([46, HORIZON - 4, 104, HORIZON + 18], fill=fill)
    elif style == "void":
        # dark voids eaten into the pale island
        for (x0, x1) in ((10, 30), (40, 66), (74, 92)):
            d.ellipse([x0, HORIZON + 6, x1, HORIZON + 30], fill=fill)
    elif style == "acacia":
        # flat-topped savanna trees
        for (cx, cy) in ((24, HORIZON - 18), (60, HORIZON - 24)):
            d.line([(cx, HORIZON + 2), (cx, cy)], fill=fill, width=3)
            d.rectangle([cx - 14, cy - 4, cx + 16, cy], fill=fill)
    elif style == "mesa":
        # horizontal terracotta bands + a butte
        bands = [(255, 150, 90), (210, 110, 60), (170, 80, 44), (140, 64, 36)]
        for i, c in enumerate(bands):
            y = HORIZON + 6 + i * 8
            d.rectangle([0, y, CELL_W, y + 7], fill=c + (255,))
        d.rectangle([52, HORIZON - 26, 74, HORIZON + 2], fill=fill)
        d.rectangle([58, HORIZON - 34, 68, HORIZON - 26], fill=fill)


def make_card(b):
    img = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    vgrad(d, 0, 0, CELL_W, HORIZON, b["sky"][0], b["sky"][1])
    vgrad(d, 0, HORIZON, CELL_W, CELL_H, b["ground"][0], b["ground"][1])
    draw_silhouette(d, b["style"], b["sil"])

    foot_top = int(CELL_H * 0.52)
    overlay = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    span = CELL_H - foot_top
    for y in range(foot_top, CELL_H):
        a = int(205 * ((y - foot_top) / span) ** 1.4)
        od.line([(0, y), (CELL_W - 1, y)], fill=(8, 10, 14, a))
    img = Image.alpha_composite(img, overlay)

    ImageDraw.Draw(img).rectangle([0, 0, CELL_W - 1, CELL_H - 1], outline=(18, 20, 26, 255))
    return img


def nn(img, factor):
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


# --- Biome deck splashes (71x95, one per Overworld biome; the per-biome start-decks) ---
DW, DH, DHZ = 71, 95, 56


def make_deck(b):
    img = Image.new("RGBA", (DW, DH), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    vgrad(d, 0, 0, DW, DHZ, b["sky"][0], b["sky"][1])
    vgrad(d, 0, DHZ, DW, DH, b["ground"][0], b["ground"][1])
    sil = b["sil"] + (255,)
    d.ellipse([-8, DHZ - 9, 32, DHZ + 16], fill=sil)
    d.ellipse([34, DHZ - 6, 80, DHZ + 16], fill=sil)
    d.rectangle([0, 0, DW - 1, DH - 1], outline=(18, 20, 26, 255))
    return img


def save_sheet(sheet, name):
    os.makedirs(os.path.join(HERE, "1x"), exist_ok=True)
    os.makedirs(os.path.join(HERE, "2x"), exist_ok=True)
    sheet.save(os.path.join(HERE, "1x", name))
    nn(sheet, 2).save(os.path.join(HERE, "2x", name))
    print("wrote", name, sheet.size, "(+2x)")


def build():
    rows = max(b["row"] for b in BIOMES) + 1
    sheet = Image.new("RGBA", (CELL_W * COLS, CELL_H * rows), (0, 0, 0, 0))
    for b in BIOMES:
        sheet.alpha_composite(make_card(b), (b["col"] * CELL_W, b["row"] * CELL_H))
    save_sheet(sheet, "biome_cards.png")

    # Per-biome deck splashes: Overworld biomes only (cols 0-7, row 0), in column order.
    overworld = sorted((b for b in BIOMES if b["row"] == 0), key=lambda b: b["col"])
    decks = Image.new("RGBA", (DW * len(overworld), DH), (0, 0, 0, 0))
    for b in overworld:
        decks.alpha_composite(make_deck(b), (b["col"] * DW, 0))
    save_sheet(decks, "biome_decks.png")


if __name__ == "__main__":
    build()
