import sys, os, numpy as np
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import gen_food_vouchers as gfv
import gen_voucher as gv

def test_build_card_from_scene():
    card = gfv.build_card("pasto", icon=None)
    a = np.array(card)
    assert card.size == (71, 95), card.size
    assert (a[10:18, 12:60, :3] > 230).all(axis=2).mean() > 0.5, "banner missing"
    dark, light = gv.derive_split(345, 72, 62)
    band = a[24:30, 9:62, :3]
    hit = (np.abs(band - np.array(light)).sum(2) < 30) | (np.abs(band - np.array(dark)).sum(2) < 30)
    assert hit.mean() > 0.3, "burgundy split not visible in wall band"
    print("test_build_card_from_scene OK")

if __name__ == "__main__":
    test_build_card_from_scene()
