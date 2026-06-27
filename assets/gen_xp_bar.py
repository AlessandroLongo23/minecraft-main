"""Procedurally generate the Minecraft-style XP bar sprite sheet (deterministic).

Output (1x): assets/1x/xp_bar.png -> 182x10, two stacked 182x5 frames:
  frame row 0 (y 0-4)  = empty bar (dark trough)
  frame row 1 (y 5-9)  = full bar  (MC green)
2x derived by nearest-neighbour upscale -> assets/2x/xp_bar.png

Faithful recreation of Minecraft's experience bar look (NOT a ripped asset):
the real bar is 182x5 -- a thin trough with a 1px dark border, a top highlight
row, a main row, and a bottom shadow row. Run from the Mods/ directory:
    python BalaCraft/assets/gen_xp_bar.py
(paths are written relative to the Mods/ dir, matching gen_resources.py).
"""
from PIL import Image

W, H = 182, 14  # 182 wide (MC); taller than MC's 5px so the 1px border stays THIN
                # once the bar is stretched to its on-screen thickness (atlas py must match)

BORDER = (0, 0, 0, 255)

# empty (unfilled) trough -- dark greys so the green pops
E_HI   = (106, 106, 106, 255)
E_MAIN = (74, 74, 74, 255)
E_SH   = (48, 48, 48, 255)

# filled (green) -- MC XP lime green with a lighter top / darker bottom
F_HI   = (168, 255, 96, 255)
F_MAIN = (124, 243, 49, 255)
F_SH   = (86, 194, 24, 255)

# Segment notches: dark vertical dividers split the bar into SEGMENTS chunks (the
# Minecraft XP bar look). Baked into BOTH frames at the same x, so they stay aligned
# as the green fill clips left->right over the empty trough.
SEGMENTS = 18
NOTCH    = (0, 0, 0, 255)


def draw_bar(px, y0, hi, main, sh):
    # 1px top/bottom border, one highlight row, one shadow row, the rest main fill.
    for y in range(H):
        if y == 0 or y == H - 1:
            row = BORDER
        elif y == 1:
            row = hi
        elif y == H - 2:
            row = sh
        else:
            row = main
        for x in range(W):
            px[x, y0 + y] = row
    for dy in range(H):  # left/right 1px black edges
        px[0, y0 + dy] = BORDER
        px[W - 1, y0 + dy] = BORDER


def draw_notches(px):
    for i in range(1, SEGMENTS):
        x = round(i * W / SEGMENTS)
        if 0 < x < W - 1:
            for y in range(H * 2):  # full height -> both frames, aligned
                px[x, y] = NOTCH


def build():
    img = Image.new("RGBA", (W, H * 2), (0, 0, 0, 0))
    px = img.load()
    draw_bar(px, 0, E_HI, E_MAIN, E_SH)   # frame 0: empty
    draw_bar(px, H, F_HI, F_MAIN, F_SH)   # frame 1: full
    draw_notches(px)                      # segment dividers on both frames
    img.save("BalaCraft/assets/1x/xp_bar.png")
    print("wrote 1x/xp_bar.png", img.size)
    img2 = img.resize((img.width * 2, img.height * 2), Image.NEAREST)
    img2.save("BalaCraft/assets/2x/xp_bar.png")
    print("wrote 2x/xp_bar.png", img2.size)


if __name__ == "__main__":
    build()
