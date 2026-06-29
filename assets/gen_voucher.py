#!/usr/bin/env python3
"""
gen_voucher.py — compose a Balatro-style voucher card (71x95) from a centered icon.

Strategy (see docs/voucher-art-style.md):
  * The card FRAME + "VOUCHER" banner is identical on every voucher, so we borrow it
    pixel-perfect from the real sheet (assets/1x/Vouchers.png) instead of redrawing it.
    We knock the inner art panel out of a donor card -> a reusable frame OVERLAY.
  * The background is a vertical LEFT/RIGHT split of ONE hue: lighter half vs darker half
    (same hue, lighter ~1.25x value & ~8 sat points lower). Split line is dead center.
  * A new voucher = paint the split background in the art panel, composite the icon,
    then lay the frame overlay on top. Frame/banner/text are never touched.

Public API:
  compose_voucher(icon, dark=None, light=None, hue=None, light_side='left', ...) -> PIL.Image
  derive_split(hue, sat=78, val=66) -> (dark_rgb, light_rgb)
  extract_icon(r, c) -> PIL.Image           # pull a real icon out of the sheet (reuse/test)
  scale2x(img) -> PIL.Image

CLI:
  python assets/gen_voucher.py --icon icon.png --hue 200 --light-side left --out card.png
  python assets/gen_voucher.py --icon icon.png --dark 32,123,179 --light 0,156,253 --out card.png
  python assets/gen_voucher.py --selftest          # reconstruct real cards, report pixel diff
"""

import argparse
import colorsys
import os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
# Vanilla Balatro voucher atlas — borrowed only to lift the pixel-perfect card frame.
SHEET = os.path.join(HERE, "_vanilla_ref", "atlases", "1x", "Vouchers.png")

CW, CH = 71, 95
SPLIT_X = 35          # vertical divide (dead center of 71)
ART_TOP = 21          # first row of the art panel (banner occupies above this)
DONOR = (0, 0)        # which sheet cell to borrow the frame from (any card works)

# --- color helpers -----------------------------------------------------------

def hsv2rgb(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h / 360.0, s / 100.0, v / 100.0)
    return (int(round(r * 255)), int(round(g * 255)), int(round(b * 255)))

def rgb2hsv(c):
    h, s, v = colorsys.rgb_to_hsv(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0)
    return (h * 360, s * 100, v * 100)

def derive_split(hue, sat=78, val=66):
    """Style rule: dark half = (H,sat,val); light half = same hue, +~25% value, -8 sat."""
    dark = hsv2rgb(hue, sat, val)
    light = hsv2rgb(hue, max(0, sat - 8), min(100, val * 1.28))
    return dark, light

def split_from_color(base, lighten=1.28, desat=8):
    """Build a (dark, light) pair from a single base color, keeping hue fixed."""
    h, s, v = rgb2hsv(base)
    dark = hsv2rgb(h, s, v)
    light = hsv2rgb(h, max(0, s - desat), min(100, v * lighten))
    return dark, light

# --- frame template (borrowed from the real sheet) ---------------------------

def _cell(arr, r, c):
    return arr[r * CH:(r + 1) * CH, c * CW:(c + 1) * CW]

def _two_bg_colors(cell):
    """The two most common flat colors in the art region == the split halves."""
    art = cell[ART_TOP:, :, :]
    mask = art[:, :, 3] > 200
    px = art[mask][:, :3]
    vals, counts = np.unique(px, axis=0, return_counts=True)
    order = counts.argsort()[::-1]
    return tuple(int(x) for x in vals[order[0]]), tuple(int(x) for x in vals[order[1]])

def _art_panel_mask(cell, bg_cols, tol=10):
    """Filled interior of the art panel: per-row span between outermost bg pixels,
    clipped to the card silhouette and to y>=ART_TOP. Follows rounded corners/notch."""
    a = cell[:, :, 3] > 0
    rgb = cell[:, :, :3].astype(int)
    is_bg = np.zeros((CH, CW), bool)
    for col in bg_cols:
        is_bg |= (np.abs(rgb - np.array(col)).sum(2) <= tol)
    panel = np.zeros((CH, CW), bool)
    for y in range(ART_TOP, CH):
        xs = np.where(is_bg[y])[0]
        if len(xs):
            panel[y, xs.min():xs.max() + 1] = True
    return panel & a

def build_frame_overlay(donor=DONOR):
    """Return (overlay RGBA uint8, art_panel bool mask) for the shared frame.

    overlay = a real card with the art panel knocked out to transparent, so it
    carries the exact frame ring, inner bevel, banner box and 'VOUCHER' text."""
    sheet = np.array(Image.open(SHEET).convert("RGBA"))
    cell = _cell(sheet, *donor).copy()
    bg = _two_bg_colors(cell)
    panel = _art_panel_mask(cell, bg)
    overlay = cell.copy()
    overlay[panel] = (0, 0, 0, 0)
    return overlay, panel

# --- composition -------------------------------------------------------------

def _resolve_colors(dark, light, hue, sat, val):
    if dark is not None and light is not None:
        return tuple(dark), tuple(light)
    if hue is not None:
        return derive_split(hue, sat, val)
    raise ValueError("provide either (dark & light) or hue")

def paint_background(panel, dark, light, light_side="left", split_x=SPLIT_X):
    """RGBA array with the split background painted inside `panel`, else transparent."""
    out = np.zeros((CH, CW, 4), np.uint8)
    light_is_left = (light_side == "left")
    for y in range(CH):
        xs = np.where(panel[y])[0]
        for x in xs:
            on_left = x < split_x
            col = light if (on_left == light_is_left) else dark
            out[y, x] = (col[0], col[1], col[2], 255)
    return out

def compose_voucher(icon, dark=None, light=None, hue=None, light_side="left",
                    sat=78, val=66, overlay=None, panel=None):
    """Compose a 71x95 voucher: split background + centered icon + shared frame.

    `icon`: a PIL.Image (RGBA) of the centered art, sized <= the art panel
            (~56x66). It is centered into the panel automatically.
    """
    dark, light = _resolve_colors(dark, light, hue, sat, val)
    if overlay is None or panel is None:
        overlay, panel = build_frame_overlay()

    base = Image.fromarray(paint_background(panel, dark, light, light_side))

    # center the icon within the art panel bounding box, clip to the panel
    ys, xs = np.where(panel)
    pcx = (xs.min() + xs.max()) // 2
    pcy = (ys.min() + ys.max()) // 2
    if icon.mode != "RGBA":
        icon = icon.convert("RGBA")
    ox = pcx - icon.width // 2
    oy = pcy - icon.height // 2
    icon_layer = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    icon_layer.alpha_composite(icon, (ox, oy))
    # clip icon to the panel so it can never spill onto the frame
    clip = np.array(icon_layer)
    clip[~panel] = (0, 0, 0, 0)
    icon_layer = Image.fromarray(clip)

    card = Image.alpha_composite(base, icon_layer)
    card = Image.alpha_composite(card, Image.fromarray(overlay))
    return card

# --- palette image (to feed Retro Diffusion / PixelLab) ----------------------

# Fixed "chrome" the compositor draws — usually NOT needed in the ICON palette,
# but slate + white ARE (outline + highlight on the icon itself).
SLATE = (79, 99, 103)     # universal outline / "VOUCHER" text — never pure black
WHITE = (255, 255, 255)   # icon highlight
FRAME = (192, 200, 214)   # card frame line
BANNER = (248, 248, 248)  # banner off-white

def value_ladder(hue, sat=78, val=66, steps=4):
    """A small set of same-hue values for shading an icon (shadow->highlight)."""
    out = []
    for i in range(steps):
        t = i / (steps - 1)                      # 0..1
        v = min(100, val * (0.6 + 0.7 * t))      # 0.6x .. 1.3x
        s = max(0, sat + 6 - 22 * t)             # darker = more saturated
        out.append(hsv2rgb(hue, s, v))
    return out

def make_palette(hue, accent=None, steps=4, include_bg=True, light_side="left",
                 sat=78, val=66):
    """Build the allowed-color list for an icon: slate outline + white highlight +
    a value ladder of `hue` (+ optional `accent` hue) + optionally the two
    background-split colors so the model can match the card. Returns list[rgb]."""
    pal = [SLATE, WHITE]
    pal += value_ladder(hue, sat, val, steps)
    if accent is not None:
        pal += value_ladder(accent, sat, val, max(2, steps - 1))
    if include_bg:
        pal += list(derive_split(hue, sat, val))
    # de-dup, preserve order
    seen, uniq = set(), []
    for c in pal:
        if c not in seen:
            seen.add(c); uniq.append(c)
    return uniq

def palette_image(colors, block=16):
    """Render a palette as a 1-row PNG of color blocks (unique colors == the palette)."""
    img = Image.new("RGB", (len(colors) * block, block))
    px = img.load()
    for i, c in enumerate(colors):
        for x in range(block):
            for y in range(block):
                px[i * block + x, y] = c
    return img

def extract_icon(r, c, tol=10):
    """Pull a real icon out of sheet cell (r,c): art-panel pixels that are NOT
    background, placed on a transparent canvas the size of the panel bbox."""
    sheet = np.array(Image.open(SHEET).convert("RGBA"))
    cell = _cell(sheet, r, c).copy()
    bg = _two_bg_colors(cell)
    panel = _art_panel_mask(cell, bg)
    rgb = cell[:, :, :3].astype(int)
    is_bg = np.zeros((CH, CW), bool)
    for col in bg:
        is_bg |= (np.abs(rgb - np.array(col)).sum(2) <= tol)
    icon_mask = panel & ~is_bg & (cell[:, :, 3] > 0)
    out = cell.copy()
    out[~icon_mask] = (0, 0, 0, 0)
    ys, xs = np.where(icon_mask)
    crop = out[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    return Image.fromarray(crop), bg

def scale2x(img):
    return img.resize((img.width * 2, img.height * 2), Image.NEAREST)

# --- CLI ---------------------------------------------------------------------

def _parse_rgb(s):
    return tuple(int(x) for x in s.split(","))

def main():
    ap = argparse.ArgumentParser(description="Compose a Balatro voucher card.")
    ap.add_argument("--icon", help="centered icon PNG (RGBA, ~56x66)")
    ap.add_argument("--hue", type=float, help="background hue 0-360 (auto light/dark)")
    ap.add_argument("--sat", type=float, default=78)
    ap.add_argument("--val", type=float, default=66)
    ap.add_argument("--dark", type=_parse_rgb, help="dark half R,G,B (overrides hue)")
    ap.add_argument("--light", type=_parse_rgb, help="light half R,G,B (overrides hue)")
    ap.add_argument("--light-side", choices=["left", "right"], default="left")
    ap.add_argument("--out", default="voucher.png")
    ap.add_argument("--also-2x", action="store_true", help="also write <out>@2x.png")
    ap.add_argument("--selftest", action="store_true", help="reconstruct real cards & diff")
    ap.add_argument("--palette", action="store_true",
                    help="write a palette image for --hue (feed to RD/PixelLab) and exit")
    ap.add_argument("--accent", type=float, help="optional accent hue for the palette")
    args = ap.parse_args()

    if args.selftest:
        return selftest()

    if args.palette:
        if args.hue is None:
            ap.error("--palette needs --hue")
        cols = make_palette(args.hue, accent=args.accent, sat=args.sat, val=args.val)
        palette_image(cols).save(args.out)
        print(f"wrote {args.out} — {len(cols)} colors:")
        for c in cols:
            print("  ", c)
        return

    if not args.icon:
        ap.error("--icon required (or use --selftest)")
    icon = Image.open(args.icon).convert("RGBA")
    card = compose_voucher(icon, dark=args.dark, light=args.light, hue=args.hue,
                           light_side=args.light_side, sat=args.sat, val=args.val)
    card.save(args.out)
    print("wrote", args.out)
    if args.also_2x:
        p = args.out.replace(".png", "@2x.png")
        scale2x(card).save(p)
        print("wrote", p)

def selftest():
    """Reconstruct several real cards from their own extracted icon+bg and report
    how many pixels differ from the original (frame fidelity check)."""
    overlay, panel = build_frame_overlay()
    sheet = np.array(Image.open(SHEET).convert("RGBA"))
    cases = [(0, 0), (0, 4), (0, 5), (0, 6), (2, 2), (2, 6)]
    print(f"{'cell':6}{'light_side':12}{'diff px':>9}{'  of':>5}")
    montage = Image.new("RGBA", (len(cases) * 80, 200), (40, 40, 45, 255))
    for i, (r, c) in enumerate(cases):
        icon, bg = extract_icon(r, c)
        # which bg color is on the left half? sample original
        cell = _cell(sheet, r, c)
        left = tuple(int(v) for v in cell[40, 12, :3])
        light = bg[0] if rgb2hsv(bg[0])[2] >= rgb2hsv(bg[1])[2] else bg[1]
        dark = bg[1] if light == bg[0] else bg[0]
        light_side = "left" if np.abs(np.array(left) - np.array(light)).sum() < \
                               np.abs(np.array(left) - np.array(dark)).sum() else "right"
        card = compose_voucher(icon, dark=dark, light=light, light_side=light_side,
                               overlay=overlay, panel=panel)
        orig = Image.fromarray(cell)
        diff = (np.array(card).astype(int) - cell.astype(int))
        nd = int((np.abs(diff).sum(2) > 12).sum())
        print(f"r{r}c{c:<3}{light_side:12}{nd:9}{CW*CH:>5}")
        montage.alpha_composite(scale2x(orig), (i * 80 + 4, 4))
        montage.alpha_composite(scale2x(card), (i * 80 + 4, 100))
    out = os.path.join(HERE, "..", "docs", "voucher_selftest.png")
    montage.convert("RGB").save(out)
    print("montage (top=original, bottom=reconstruction):", os.path.normpath(out))

if __name__ == "__main__":
    main()
