import sys, os, numpy as np
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import voucher_scenes as vs

def _check(img, name):
    a = np.array(img)
    assert img.size == (56, 66), f"{name} size {img.size}"
    assert a.shape[2] == 4, f"{name} not RGBA"
    top = a[:int(66*0.22), :, 3]
    assert (top < 20).mean() > 0.9, f"{name} top band not transparent"
    bot = a[int(66*0.5):, :, 3]
    assert (bot > 200).mean() > 0.7, f"{name} table not opaque enough"
    print(f"{name} OK")

def test_pasto():
    _check(vs.render_pasto(56, 66), "pasto")

def test_banchetto():
    _check(vs.render_banchetto(56, 66), "banchetto")

if __name__ == "__main__":
    test_pasto(); test_banchetto()
