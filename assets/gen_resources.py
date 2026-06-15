"""Procedurally generate the resource sprite sheets (deterministic, no RNG).

Outputs (1x):
  assets/1x/resource_icons.png  -> 34x34 cells, 3x2 grid (102x68)
  assets/1x/resource_cards.png  -> 71x95 cells, 3x2 grid (213x190)
Run `utils.py` afterwards to produce the 2x sheets.
Ore order (row-major): wood, cobblestone, coal, iron, gold, diamond.
"""
from PIL import Image

ICON = 34
CARD_W, CARD_H = 71, 95
COLS, ROWS = 3, 2

# Palette
STONE      = (124, 124, 124, 255)
STONE_HI   = (150, 150, 150, 255)
STONE_LO   = (98, 98, 98, 255)
WOOD       = (150, 116, 67, 255)
WOOD_LINE  = (110, 82, 44, 255)
COBBLE_LO  = (96, 96, 96, 255)
COBBLE_HI  = (160, 160, 160, 255)
COAL       = (32, 32, 32, 255)
IRON       = (208, 170, 140, 255)
GOLD       = (250, 224, 70, 255)
DIAMOND    = (90, 220, 215, 255)
CARD_BG    = (40, 44, 52, 255)
TIER_TINT  = {1: (90, 110, 90, 255), 2: (110, 100, 70, 255), 3: (70, 110, 130, 255)}

# Fixed speckle clusters (x,y) for ore blobs on a stone base, 16x16 space.
SPECKLES = [(4, 4), (5, 4), (4, 5), (10, 6), (11, 6), (6, 10), (7, 11), (11, 11), (12, 11)]

def base_stone():
    img = Image.new("RGBA", (16, 16), STONE)
    px = img.load()
    for (x, y) in [(2, 3), (9, 2), (13, 5), (3, 12), (12, 13), (7, 7)]:
        px[x, y] = STONE_LO
    for (x, y) in [(1, 8), (8, 9), (14, 9), (5, 14)]:
        px[x, y] = STONE_HI
    return img

def ore(color):
    img = base_stone()
    px = img.load()
    for (x, y) in SPECKLES:
        px[x, y] = color
    return img

def wood():
    img = Image.new("RGBA", (16, 16), WOOD)
    px = img.load()
    for x in (2, 3, 8, 9, 13):
        for y in range(16):
            if (x + y) % 3 != 0:
                px[x, y] = WOOD_LINE
    return img

def cobblestone():
    img = Image.new("RGBA", (16, 16), STONE)
    px = img.load()
    for (x, y) in [(2, 2), (3, 2), (2, 3), (9, 3), (10, 3), (4, 9), (5, 9), (11, 10), (12, 10), (7, 12)]:
        px[x, y] = COBBLE_LO
    for (x, y) in [(6, 5), (12, 6), (3, 11), (13, 12)]:
        px[x, y] = COBBLE_HI
    return img

ORES = [
    ("wood", wood()),
    ("cobblestone", cobblestone()),
    ("coal", ore(COAL)),
    ("iron", ore(IRON)),
    ("gold", ore(GOLD)),
    ("diamond", ore(DIAMOND)),
]

def nn(img, factor):
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)

def build_icons():
    sheet = Image.new("RGBA", (ICON * COLS, ICON * ROWS), (0, 0, 0, 0))
    for i, (_id, tex) in enumerate(ORES):
        cx, cy = (i % COLS) * ICON, (i // COLS) * ICON
        # dark slot background + 1px border
        slot = Image.new("RGBA", (ICON, ICON), (20, 22, 26, 255))
        for x in range(ICON):
            slot.putpixel((x, 0), (70, 74, 82, 255)); slot.putpixel((x, ICON - 1), (70, 74, 82, 255))
        for y in range(ICON):
            slot.putpixel((0, y), (70, 74, 82, 255)); slot.putpixel((ICON - 1, y), (70, 74, 82, 255))
        block = nn(tex, 2)  # 16 -> 32
        slot.alpha_composite(block, (1, 1))
        sheet.alpha_composite(slot, (cx, cy))
    sheet.save("minecraft-main/assets/1x/resource_icons.png")
    print("wrote resource_icons.png", sheet.size)

def build_cards():
    sheet = Image.new("RGBA", (CARD_W * COLS, CARD_H * ROWS), (0, 0, 0, 0))
    tiers = {"wood": 1, "cobblestone": 1, "coal": 1, "iron": 2, "gold": 2, "diamond": 3}
    for i, (_id, tex) in enumerate(ORES):
        cx, cy = (i % COLS) * CARD_W, (i // COLS) * CARD_H
        face = Image.new("RGBA", (CARD_W, CARD_H), CARD_BG)
        tint = TIER_TINT[tiers[_id]]
        for x in range(CARD_W):  # top tier-coloured band
            for y in range(6):
                face.putpixel((x, y), tint)
        block = nn(tex, 3)  # 16 -> 48
        face.alpha_composite(block, ((CARD_W - 48) // 2, (CARD_H - 48) // 2 - 4))
        sheet.alpha_composite(face, (cx, cy))
    sheet.save("minecraft-main/assets/1x/resource_cards.png")
    print("wrote resource_cards.png", sheet.size)

if __name__ == "__main__":
    build_icons()
    build_cards()
