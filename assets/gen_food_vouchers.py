"""Assemble the Pasto & Banchetto voucher cards.
icon=None  -> use the deterministic placeholder scene (no AI)
icon=Image -> use a supplied (AI-generated) RGBA icon."""
import os, numpy as np
from PIL import Image
import gen_voucher as gv
import voucher_scenes as vs

HUE, SAT, VAL = 345, 72, 62
# All preview/work output (composited cards, AI candidates, references, palette) goes
# to BalaCraft/assets/generated/. Final atlas packing into 1x/ is a separate wiring step.
REF = os.path.join(os.path.dirname(os.path.abspath(__file__)), "generated")

def _panel_size():
    _, panel = gv.build_frame_overlay()
    ys, xs = np.where(panel)
    return (xs.max()-xs.min()+1, ys.max()-ys.min()+1)

def render_scene(which):
    w, h = _panel_size()
    return vs.render_pasto(w, h) if which == "pasto" else vs.render_banchetto(w, h)

def build_card(which, icon=None):
    dark, light = gv.derive_split(HUE, SAT, VAL)
    if icon is None:
        icon = render_scene(which)
    return gv.compose_voucher(icon, dark=dark, light=light, light_side="left")

def write_reference_pngs():
    os.makedirs(REF, exist_ok=True)
    for which in ("pasto", "banchetto"):
        s = render_scene(which)
        s.resize((s.width*6, s.height*6)).save(os.path.join(REF, f"ref_{which}.png"))
    gv.palette_image(gv.make_palette(HUE, accent=280, sat=SAT, val=VAL)).save(
        os.path.join(REF, "palette_burgundy.png"))

def main():
    os.makedirs(REF, exist_ok=True)
    for which in ("pasto", "banchetto"):
        card = build_card(which)
        p = os.path.join(REF, f"voucher_{which}.png")
        card.save(p); gv.scale2x(card).save(p.replace(".png", "@2x.png"))
        print("wrote", p)
    write_reference_pngs()
    print("wrote reference PNGs + palette to", REF)

if __name__ == "__main__":
    main()
