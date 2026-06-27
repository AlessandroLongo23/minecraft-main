"""Generate art for the two enchanting-pair vouchers, baked into the real Balatro VOUCHER frames.

Each card = a side-view "enchanting room" (authentic 16x16 MC textures) composited INTO the official
voucher ticket frame from Mods/assets/_templates/:
  * enchanting_table (base, x=0)  -> voucher_base_template    (light "VOUCHER" banner)
  * sorcerers_tome   (tier II,x=1)-> voucher_upgrade_template (teal "VOUCHER" banner)

The scene differs only in the bookshelves: the base table is flanked by a COUPLE of bookshelves; the
Tome sits against a FULL LIBRARY wall, with a brighter book glow and denser enchant runes.

How the frame is applied (the templates are a design-time bake, not a runtime overlay -- a finished
voucher sprite is one 71x95 image with the frame already drawn in):
  1. render the scene on a 71x95 canvas, laid out to fit the art window x[9,61] y[21,90] (below banner)
  2. clip it to the ticket silhouette (interior flood-fill UNION the frame's own pixels)
  3. alpha-composite the template frame on top (banner + border drawn over the art)

Source textures: Mods/assets/reference/enchant_voucher/ (InventivetalentDev mirror, see gen_stations.py).
Output (1x + nearest 2x): assets/?x/enchant_voucher_cards.png -> 71x95 cells, atlas bc_enchant_vouchers.
Cell order MUST match content/vouchers/ pos: enchanting_table (x=0), sorcerers_tome (x=1).
"""
import os
from collections import deque
from PIL import Image, ImageDraw

CW, CH = 71, 95
_HERE = os.path.dirname(os.path.abspath(__file__))
_REF = os.path.normpath(os.path.join(_HERE, "..", "..", "assets", "reference", "enchant_voucher"))
_TPL = os.path.normpath(os.path.join(_HERE, "..", "..", "assets", "_templates", "1x"))

# Art window inside the voucher frame (below the "VOUCHER" banner), measured from the masks.
WX0, WY0, WX1, WY1 = 9, 21, 61, 90
BOOK = 16          # bookshelf block size (native texture)
FLOOR_TOP = 76     # y where the stone-brick floor begins


# ---------------------------------------------------------------- texture helpers
def load(name):
    return Image.open(os.path.join(_REF, name + ".png")).convert("RGBA")


def scale(im, f):
    return im.resize((im.width * f, im.height * f), Image.NEAREST)


def tint(im, mul, add=(0, 0, 0)):
    if isinstance(mul, (int, float)):
        mul = (mul, mul, mul)
    out = im.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            px[x, y] = (max(0, min(255, int(r * mul[0] + add[0]))),
                        max(0, min(255, int(g * mul[1] + add[1]))),
                        max(0, min(255, int(b * mul[2] + add[2]))), a)
    return out


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def vgrad(d, x0, y0, x1, y1, top, bot):
    span = max(1, y1 - y0)
    for y in range(y0, y1):
        d.line([(x0, y), (x1 - 1, y)], fill=lerp(top, bot, (y - y0) / span) + (255,))


def glow(img, cx, cy, rx, ry, col, strength):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    for i in range(6, 0, -1):
        t = i / 6
        ld.ellipse([cx - rx * t, cy - ry * t, cx + rx * t, cy + ry * t],
                   fill=col + (int(strength * (1 - t) ** 1.6),))
    img.alpha_composite(layer)


# ---------------------------------------------------------------- scene
def back_wall(img, full_library):
    shelf, brick = load("bookshelf"), load("stone_bricks")
    wall = tint(brick, 0.5)
    for ty in range(WY0, FLOOR_TOP, BOOK):
        for tx in range(WX0, WX1, BOOK):
            img.alpha_composite(wall, (tx, ty))
    if full_library:
        bs = tint(shelf, 0.84, add=(4, 2, 10))
        for ty in (WY0, WY0 + 16, WY0 + 32, WY0 + 48):
            for tx in (WX0, WX0 + 16, WX0 + 32, WX0 + 44):
                img.alpha_composite(bs, (tx, ty))
    else:
        # a couple of bookshelves flanking the floating book / upper table
        img.alpha_composite(shelf, (WX0, WY0 + 5))
        img.alpha_composite(shelf, (WX1 - BOOK, WY0 + 5))


def floor(img):
    brick = load("stone_bricks")
    row = tint(brick, 0.72)
    top = tint(brick, 0.92, add=(10, 10, 14))
    for tx in range(WX0, WX1, BOOK):
        img.alpha_composite(row, (tx, FLOOR_TOP))
        img.alpha_composite(top.crop((0, 0, BOOK, 4)), (tx, FLOOR_TOP))


def draw_open_book(img, cx, cy, bright):
    d = ImageDraw.Draw(img)
    page = (255, 252, 236) if bright else (244, 238, 214)
    edge, spine = (120, 150, 90), (60, 40, 90)
    d.polygon([(cx, cy - 3), (cx - 8, cy - 2), (cx - 8, cy + 4), (cx, cy + 5)], fill=page)
    d.polygon([(cx, cy - 3), (cx + 8, cy - 2), (cx + 8, cy + 4), (cx, cy + 5)], fill=page)
    d.line([(cx - 8, cy - 2), (cx - 8, cy + 4)], fill=edge + (255,))
    d.line([(cx + 8, cy - 2), (cx + 8, cy + 4)], fill=edge + (255,))
    d.line([(cx, cy - 3), (cx, cy + 5)], fill=spine + (255,))
    for dy in (0, 2):
        d.line([(cx - 6, cy + dy), (cx - 2, cy + dy)], fill=(150, 150, 130, 180))
        d.line([(cx + 2, cy + dy), (cx + 6, cy + dy)], fill=(150, 150, 130, 180))


def enchanting_table(img, full_library):
    side = scale(load("enchanting_table_side"), 2)         # 32x32 front face
    bw, bx = 32, (CW - 32) // 2                            # centered in the window (cx=35)
    by = FLOOR_TOP - bw + 2
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([bx - 4, FLOOR_TOP - 4, bx + bw + 4, FLOOR_TOP + 6], fill=(0, 0, 0, 90))
    img.alpha_composite(sh)
    img.alpha_composite(side, (bx, by))
    d = ImageDraw.Draw(img)

    cx, book_y = 35, by - 16
    gcol = (190, 150, 255)
    glow(img, cx, book_y + 3, 20 if full_library else 14, 14 if full_library else 10,
         gcol, 150 if full_library else 95)
    draw_open_book(img, cx, book_y, bright=full_library)

    base = [(cx - 11, by - 3), (cx + 12, by - 6), (cx - 6, by - 11),
            (cx + 7, by - 12), (cx - 12, by + 4), (cx + 13, by + 2)]
    extra = [(cx - 17, by - 7), (cx + 18, by - 9), (cx - 15, by - 18),
             (cx + 16, by - 19), (cx - 3, by - 21), (cx + 5, by - 22)]
    specks = base + (extra if full_library else [])
    for (sx, sy) in specks:
        d.point((sx, sy), fill=(225, 205, 255, 255))
        d.point((sx + 1, sy), fill=(180, 150, 240, 160))
        d.point((sx, sy + 1), fill=(180, 150, 240, 160))


def scene(full_library):
    img = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    vgrad(d, 0, 0, CW, CH, (34, 24, 50), (16, 12, 26))     # clipped to the ticket later
    back_wall(img, full_library)
    floor(img)
    enchanting_table(img, full_library)
    return img


# ---------------------------------------------------------------- voucher-frame bake
def silhouette(template):
    """L-mask: 255 over the whole ticket (art window + frame pixels), 0 outside."""
    W, H = template.size
    px = template.load()
    frame = [[px[x, y][3] > 10 for x in range(W)] for y in range(H)]
    seen = [[False] * W for _ in range(H)]
    q = deque([(35, 60)])                                  # a point inside the art window
    inside = [[False] * W for _ in range(H)]
    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= W or y >= H or seen[y][x] or frame[y][x]:
            continue
        seen[y][x] = True
        inside[y][x] = True
        q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    sil = Image.new("L", (W, H), 0)
    sp = sil.load()
    for y in range(H):
        for x in range(W):
            if frame[y][x] or inside[y][x]:
                sp[x, y] = 255
    return sil


def framed(full_library, template_name):
    template = Image.open(os.path.join(_TPL, template_name + ".png")).convert("RGBA")
    art = scene(full_library)
    # clip the scene to the ticket silhouette
    sil = silhouette(template)
    ap = art.load()
    sp = sil.load()
    for y in range(CH):
        for x in range(CW):
            r, g, b, a = ap[x, y]
            ap[x, y] = (r, g, b, a * sp[x, y] // 255)
    out = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    out.alpha_composite(art)
    out.alpha_composite(template)                          # frame + banner drawn on top
    return out


# ---------------------------------------------------------------- assembly
def nn(img, f):
    return img.resize((img.width * f, img.height * f), Image.NEAREST)


def save(img, name):
    os.makedirs(os.path.join(_HERE, "1x"), exist_ok=True)
    os.makedirs(os.path.join(_HERE, "2x"), exist_ok=True)
    img.save(os.path.join(_HERE, "1x", name))
    nn(img, 2).save(os.path.join(_HERE, "2x", name))
    print("wrote", name, img.size, "(+2x)")


def build():
    sheet = Image.new("RGBA", (CW * 2, CH), (0, 0, 0, 0))
    sheet.alpha_composite(framed(False, "voucher_base_template"), (0, 0))     # enchanting_table
    sheet.alpha_composite(framed(True, "voucher_upgrade_template"), (CW, 0))  # sorcerers_tome
    save(sheet, "enchant_voucher_cards.png")


if __name__ == "__main__":
    build()
