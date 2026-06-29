import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import gen_voucher as gv
import voucher_gen as vgen

def test_burgundy_palette():
    cols = gv.make_palette(345, accent=280, sat=72, val=62)
    assert gv.SLATE in cols, "slate outline must be in palette"
    assert gv.WHITE in cols, "white highlight must be in palette"
    assert 8 <= len(cols) <= 16, f"palette out of budget: {len(cols)}"
    dark, light = gv.derive_split(345, 72, 62)
    assert dark in cols and light in cols
    print("test_burgundy_palette OK")

def test_payloads():
    # PixelLab uses the SDK directly (PIL images), so only the RD payload is a pure dict.
    r = vgen._rd_payload("a roasted chicken on a table", 56, 66, "stylecode")
    assert r["width"] == 56 and r["height"] == 66 and r["prompt"] and r["num_images"] == 1
    print("test_payloads OK")

def test_save_png_roundtrip():
    import tempfile
    from PIL import Image
    with tempfile.TemporaryDirectory() as d:
        img = Image.new("RGBA", (56,66), (10,20,30,255))
        out = os.path.join(d, "rt.png")
        vgen.save_icon(img, out)
        assert Image.open(out).size == (56,66)
    print("test_save_png_roundtrip OK")

if __name__ == "__main__":
    test_burgundy_palette(); test_payloads(); test_save_png_roundtrip()
