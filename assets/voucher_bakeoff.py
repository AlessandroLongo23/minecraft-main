"""Fan the same prompt + palette + reference to each available engine and save
candidate icons side-by-side for visual comparison. Run only after keys are set."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import voucher_gen as vgen, gen_food_vouchers as gfv

PROMPTS = {
  "pasto": "tiny pixel art icon, high three-quarter view of a small table with a cream "
           "tablecloth, a white plate with one roasted chicken drumstick, a glass of water, "
           "a fork, intimate humble meal, dark wine-red background, slate outlines",
  "banchetto": "tiny pixel art icon, high three-quarter view of a banquet table with a cream "
           "tablecloth, white plate with a whole roasted chicken, a wine bottle, a wine glass, "
           "a grape cluster, a lit candle, royal feast, dark wine-red background, slate outlines",
}

def run(which="banchetto"):
    out = gfv.REF                              # top-level generated/ folder
    os.makedirs(out, exist_ok=True)
    gfv.write_reference_pngs()                 # writes 6x reference PNGs + palette
    size = gfv._panel_size()
    ref_img = gfv.render_scene(which)          # native-size RGBA reference (matches `size`)
    pal = os.path.join(out, "palette_burgundy.png")
    if os.environ.get("PIXELLAB_SECRET"):
        try:
            img = vgen.pixellab_icon(PROMPTS[which], size, init_image=ref_img)
            vgen.save_icon(img, os.path.join(out, f"cand_{which}_pixellab.png")); print("pixellab OK")
        except Exception as e: print("pixellab FAILED:", e)
    if os.environ.get("RD_API_TOKEN"):
        try:
            img = vgen.rd_icon(PROMPTS[which], size, palette_image=pal, ref_image=ref_img)
            vgen.save_icon(img, os.path.join(out, f"cand_{which}_rd.png")); print("rd OK")
        except Exception as e: print("rd FAILED:", e)
    print("candidates in", out)

if __name__ == "__main__":
    run(sys.argv[1] if len(sys.argv) > 1 else "banchetto")
