"""Generate the BalaCraft seal sheet (bc_seals).

The three custom seals -- Ore, Soul, Cooked -- reuse Balatro's own seal "wax stamp"
pixel art, re-tinted into new colours (the user's request: "same pixel art, different
colours"). The base is the vanilla Red seal cell from the centers/Enhancers atlas, staged
at assets/reference/seals/seal_base.png (71x95, a clean 6-colour opaque palette).

Re-tint preserves the base seal's OWN per-shade lightness *and* saturation profile and only
rotates the hue (scaling saturation per seal). Because the lightness band is taken verbatim
from a real vanilla seal (L 44%->73%), the shaded-vs-lit contrast matches the stock seals
exactly -- no over-bright highlights or near-black shadows. Tints:
  Ore    -> cobblestone grey   (near-neutral, faint cool stone tint)
  Soul   -> XP-bar lime green  (assets/.../gen_xp_bar.py F_MAIN #7cf331)
  Cooked -> cooked-chicken brown/orange (assets/reference/food/cooked_chicken.png)

Output (1x written, 2x derived nearest-neighbour):
  assets/1x/seals.png -> 71x95 cells, 1 row x 3 cols = 213x95

Grid order MUST match each seal's `pos` in content/seals/seals.lua:
  ore {0,0}   soul {1,0}   cooked {2,0}

Run from the Mods/ directory:  python BalaCraft/assets/gen_seals.py
"""
import colorsys
import os
from PIL import Image
from utils import scale_image

CW, CH = 71, 95
_HERE = os.path.dirname(os.path.abspath(__file__))
_BASE = os.path.normpath(os.path.join(_HERE, "..", "..", "assets", "reference", "seals", "seal_base.png"))

# seal id -> (col, row); MUST match content/seals/seals.lua pos.
ORDER = [("ore", 0), ("soul", 1), ("cooked", 2)]

# Per-seal tint: (target hue in degrees, saturation scale applied over the base's own
# saturation profile). Lightness is always the base seal's lightness -> vanilla contrast.
TINTS = {
    "ore":    (215, 0.10),  # cobblestone: near-grey with a faint cool stone tint
    "soul":   (96,  0.82),  # XP-bar lime green (more green, no cyan)
    "cooked": (24,  0.60),  # cooked-chicken brown / orange
}


def _lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def retint(base, hue_deg, sat_scale):
    """Keep each base shade's lightness & (scaled) saturation; rotate hue."""
    h = hue_deg / 360.0
    lut = {}
    for shade in {p[:3] for p in base.getdata() if p[3] > 0}:
        _, l0, s0 = colorsys.rgb_to_hls(shade[0] / 255, shade[1] / 255, shade[2] / 255)
        r, g, b = colorsys.hls_to_rgb(h, l0, min(1.0, s0 * sat_scale))
        lut[shade] = (round(r * 255), round(g * 255), round(b * 255))
    out = Image.new("RGBA", base.size, (0, 0, 0, 0))
    src, dst = base.load(), out.load()
    for j in range(base.height):
        for i in range(base.width):
            r, g, b, a = src[i, j]
            if a == 0:
                continue
            # Exact swap for the base shades; any stray edge tone maps to the nearest by luminance.
            nr, ng, nb = lut.get((r, g, b)) or lut[min(lut, key=lambda s: abs(_lum(s) - _lum((r, g, b))))]
            dst[i, j] = (nr, ng, nb, a)
    return out


def main():
    base = Image.open(_BASE).convert("RGBA")
    sheet = Image.new("RGBA", (CW * 3, CH), (0, 0, 0, 0))
    for sid, col in ORDER:
        sheet.alpha_composite(retint(base, *TINTS[sid]), (col * CW, 0))
    os.makedirs("BalaCraft/assets/1x", exist_ok=True)
    os.makedirs("BalaCraft/assets/2x", exist_ok=True)
    sheet.save("BalaCraft/assets/1x/seals.png")
    scale_image("BalaCraft/assets/1x/seals.png", "BalaCraft/assets/2x/seals.png", 2)
    print("wrote BalaCraft/assets/1x/seals.png (213x95) + 2x")


if __name__ == "__main__":
    main()
