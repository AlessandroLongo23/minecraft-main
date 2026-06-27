"""Generate the hearts HUD spritesheet (Minecraft-style, faithful 16x16 pixel art).

Produces a 48x16 sheet of three 16x16 cells in a row:
  cell 0 = full heart, cell 1 = half heart, cell 2 = empty (container).

Run from the mod root:
    python assets/gen_hearts.py
Then derive the 2x sheet (this script writes both 1x and 2x directly).
"""
from PIL import Image

# ---- palette (MC-ish) ----
TRANSPARENT = (0, 0, 0, 0)
OUTLINE     = (45, 24, 24, 255)    # near-black dark-red border
RED         = (224, 49, 49, 255)   # heart body
RED_DARK    = (176, 30, 30, 255)   # lower-body shading for a little depth
SHINE       = (255, 158, 158, 255) # top-left lobe highlight
GRAY        = (78, 78, 78, 255)    # empty-container interior
GRAY_DARK   = (58, 58, 58, 255)    # empty-container lower shading

CELL = 16

# Heart body mask, 13 wide x 11 tall. 'X' = body pixel.
MASK = [
    "..XXX...XXX..",
    ".XXXXX.XXXXX.",
    "XXXXXXXXXXXXX",
    "XXXXXXXXXXXXX",
    "XXXXXXXXXXXXX",
    ".XXXXXXXXXXX.",
    "..XXXXXXXXX..",
    "...XXXXXXX...",
    "....XXXXX....",
    ".....XXX.....",
    "......X......",
]
MW = len(MASK[0])   # 13
MH = len(MASK)      # 11
OFF_X = (CELL - MW) // 2   # 1
OFF_Y = 3                  # nudge down, leaving room for the top outline

CENTER_COL = 6             # split column for the half heart
SHINE_PX = {(1, 2), (1, 3), (2, 2)}   # (row, col) on the left lobe


def body_pixels():
    return {(r, c) for r in range(MH) for c in range(MW) if MASK[r][c] == "X"}


def outline_pixels(body):
    """1px silhouette border: empty cells touching a body pixel (8-neighbourhood)."""
    out = set()
    for r in range(-1, MH + 1):
        for c in range(-1, MW + 1):
            if (r, c) in body:
                continue
            for dr in (-1, 0, 1):
                for dc in (-1, 0, 1):
                    if (r + dr, c + dc) in body:
                        out.add((r, c))
                        break
                else:
                    continue
                break
    return out


def draw_cell(img, cell_index, mode):
    body = body_pixels()
    outline = outline_pixels(body)
    base_x = cell_index * CELL

    def put(r, c, color):
        x, y = base_x + OFF_X + c, OFF_Y + r
        if 0 <= x < img.width and 0 <= y < img.height:
            img.putpixel((x, y), color)

    # outline first (under the body silhouette)
    for (r, c) in outline:
        put(r, c, OUTLINE)

    # body
    for (r, c) in body:
        if mode == "empty":
            color = GRAY_DARK if r >= 6 else GRAY
        else:
            is_filled = (mode == "full") or (mode == "half" and c <= CENTER_COL)
            if is_filled:
                color = RED_DARK if r >= 7 else RED
                if (r, c) in SHINE_PX:
                    color = SHINE
            else:
                color = GRAY_DARK if r >= 6 else GRAY
        put(r, c, color)


def build_sheet():
    img = Image.new("RGBA", (CELL * 3, CELL), TRANSPARENT)
    draw_cell(img, 0, "full")
    draw_cell(img, 1, "half")
    draw_cell(img, 2, "empty")
    return img


def scale(img, factor):
    out = Image.new("RGBA", (img.width * factor, img.height * factor), TRANSPARENT)
    for y in range(img.height):
        for x in range(img.width):
            px = img.getpixel((x, y))
            for dy in range(factor):
                for dx in range(factor):
                    out.putpixel((x * factor + dx, y * factor + dy), px)
    return out


if __name__ == "__main__":
    import os
    here = os.path.dirname(os.path.abspath(__file__))
    sheet = build_sheet()
    sheet.save(os.path.join(here, "1x", "hearts.png"))
    scale(sheet, 2).save(os.path.join(here, "2x", "hearts.png"))
    print("Wrote assets/1x/hearts.png (48x16) and assets/2x/hearts.png (96x32)")
