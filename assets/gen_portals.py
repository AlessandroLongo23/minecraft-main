"""Procedurally generate PLACEHOLDER art for the portal vouchers and dimension decks.

Outputs (1x + nearest-neighbour 2x):
  assets/?x/voucher_cards.png  -> 71x95 cells, 1 row: nether_portal, end_portal
  assets/?x/NetherDeck.png     -> 71x95 deck splash
  assets/?x/EndDeck.png        -> 71x95 deck splash

Placeholders -- real pixel art is a later task (see docs/biomes-and-dimensions.md).
Voucher cell order MUST match content/vouchers/ pos: nether_portal (x=0), end_portal (x=1).
"""
import os
from PIL import Image, ImageDraw

CW, CH = 71, 95
HERE = os.path.dirname(os.path.abspath(__file__))


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def vgrad(d, x0, y0, x1, y1, top, bot):
    span = max(1, y1 - y0)
    for y in range(y0, y1):
        d.line([(x0, y), (x1 - 1, y)], fill=lerp(top, bot, (y - y0) / span) + (255,))


def frame(img, col):
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, img.width - 1, img.height - 1], outline=col + (255,))
    d.rectangle([1, 1, img.width - 2, img.height - 2], outline=col + (255,))


def portal_card(kind):
    """A dark obsidian-framed card with a glowing portal interior."""
    img = Image.new("RGBA", (CW, CH), (18, 16, 22, 255))
    d = ImageDraw.Draw(img)
    # obsidian frame band
    d.rectangle([5, 5, CW - 6, CH - 6], fill=(28, 24, 34, 255))
    # portal interior
    ix0, iy0, ix1, iy1 = 14, 16, CW - 15, CH - 16
    if kind == "nether":
        vgrad(d, ix0, iy0, ix1, iy1, (150, 40, 200), (70, 16, 120))
        swirl = (210, 150, 245)
    else:  # end
        vgrad(d, ix0, iy0, ix1, iy1, (18, 40, 40), (6, 14, 16))
        swirl = (140, 240, 210)
    # a few swirl/star specks
    for (sx, sy) in [(24, 30), (40, 26), (32, 48), (46, 60), (26, 70), (44, 40)]:
        d.point((sx, sy), fill=swirl + (255,))
        d.point((sx + 1, sy), fill=swirl + (200,))
    frame(img, (8, 6, 12))
    return img


def deck_splash(kind):
    img = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if kind == "nether":
        vgrad(d, 0, 0, CW, CH, (96, 26, 24), (40, 12, 12))
        # small purple portal motif
        d.rectangle([26, 34, 45, 62], fill=(120, 40, 170, 255))
        d.rectangle([29, 38, 42, 58], fill=(170, 90, 215, 255))
        accent = (200, 90, 50)
    else:  # end
        vgrad(d, 0, 0, CW, CH, (36, 30, 46), (16, 12, 22))
        # pale end-stone block + dragon-egg dot
        d.rectangle([24, 40, 47, 60], fill=(216, 214, 168, 255))
        d.ellipse([32, 30, 40, 40], fill=(20, 16, 26, 255))
        accent = (120, 220, 190)
    d.rectangle([0, 0, CW - 1, 4], fill=accent + (255,))
    frame(img, (12, 10, 16))
    return img


def nn(img, f):
    return img.resize((img.width * f, img.height * f), Image.NEAREST)


def save(img, name):
    os.makedirs(os.path.join(HERE, "1x"), exist_ok=True)
    os.makedirs(os.path.join(HERE, "2x"), exist_ok=True)
    img.save(os.path.join(HERE, "1x", name))
    nn(img, 2).save(os.path.join(HERE, "2x", name))
    print("wrote", name, img.size, "(+2x)")


def build():
    vouchers = Image.new("RGBA", (CW * 2, CH), (0, 0, 0, 0))
    vouchers.alpha_composite(portal_card("nether"), (0, 0))
    vouchers.alpha_composite(portal_card("end"), (CW, 0))
    save(vouchers, "voucher_cards.png")
    save(deck_splash("nether"), "NetherDeck.png")
    save(deck_splash("end"), "EndDeck.png")


if __name__ == "__main__":
    build()
