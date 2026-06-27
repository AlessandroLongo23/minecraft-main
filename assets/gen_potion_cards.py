#!/usr/bin/env python3
"""Generate the potion consumable card sheet (assets/1x/potion_cards.png + 2x), atlas
`bc_potion_cards` (71x95 cells).

Card chrome comes from the hand-drawn assets/1x/potion_template.png: a sage-green body, a pale
rounded frame, and a bottom nameplate. The user drew THREE bubbles in the background; we EXTRACT
those rings and re-scatter them into a denser "rising bubbles" backdrop -- and, like the starfield
on Planet cards, each potion gets its OWN deterministic scatter so no two cards look alike.

The full potion NAME is baked on the nameplate, auto-fitting the font: the 6px bold alphabet when it
fits, else the narrower 6px "thin" alphabet (assets/reference/font/thin, completed from bold for the
few missing letters) so long names like NIGHT VISION / INVISIBILITY still fit. The per-potion MC
sprite (assets/reference/potions/<id>.png) is pasted centred on top when present.

Run from Mods/:  python BalaCraft/assets/gen_potion_cards.py
"""
import os
import random
from collections import deque
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))            # BalaCraft/assets
MODS = os.path.normpath(os.path.join(HERE, "..", ".."))      # Mods/
REF  = os.path.join(MODS, "assets", "reference")
BOLDDIR = os.path.join(REF, "font", "bold")
THINDIR = os.path.join(REF, "font", "thin")
SPRITEDIR = os.path.join(REF, "potions")
OUT1 = os.path.join(HERE, "1x")
OUT2 = os.path.join(HERE, "2x")

# --- palette (sampled from potion_template.png) ---
BODY   = (118, 143, 125, 255)
PALE   = (230, 239, 233, 255)
BUBBLE = (145, 169, 151, 255)
NAME   = (85, 93, 87, 255)

W, H = 71, 95
IX0, IX1 = 10, 60        # interior the bubble pattern may occupy
IY0, IY1 = 6, 72
SPRITE_SCALE = int(os.environ.get("POTION_SCALE", "3"))
NAMEPLATE = (13, 76, 57, 85)   # interior rect to centre the label in (recomputed in main)

# Each potion is one ROW; the four columns are the (Level, Lasts-more) combinations:
#   col 0 = Level I,  normal      col 1 = Level I,  lasts more (clock)
#   col 2 = Level II, normal      col 3 = Level II, lasts more (clock)
# A potion only fills the columns its modifiers allow: `pot` = accepts Glowstone (Level II),
# `las` = accepts "lasts more" (Redstone duration on drinkables / Dragon's Breath lingering on
# throwables). Row order MUST match content/potions/registry.lua. Atlas cell -> (col, row).
#            id,              label,          pot,   las
POTIONS = [
    ("swiftness",      "SWIFTNESS",    True,  False),
    ("strength",       "STRENGTH",     True,  True),
    ("instant_health", "INST. HEALTH", True,  False),
    ("healing",        "HEALING",      True,  True),
    ("night_vision",   "NIGHT VISION", True,  True),
    ("invisibility",   "INVISIBILITY", False, True),
    ("poison",         "POISON",       True,  True),
    ("harming",        "HARMING",      True,  True),
]
# (potency, lasts) per column.
COMBOS = [(False, False), (False, True), (True, False), (True, True)]


def near(c, t, tol=10):
    return c[3] > 0 and all(abs(c[i] - t[i]) <= tol for i in range(3))


# ---------- bubble extraction + scatter ----------
def extract_bubbles(tmpl):
    px = tmpl.load()
    pts = [(x, y) for y in range(H) for x in range(W) if near(px[x, y], BUBBLE)]
    pset, seen, clusters = set(pts), set(), []
    for p in pts:
        if p in seen:
            continue
        comp, q = [], deque([p]); seen.add(p)
        while q:
            cx, cy = q.popleft(); comp.append((cx, cy))
            for dx in range(-3, 4):
                for dy in range(-3, 4):
                    n = (cx + dx, cy + dy)
                    if n in pset and n not in seen:
                        seen.add(n); q.append(n)
        clusters.append(comp)
    glyphs = []
    for comp in clusters:
        xs = [c[0] for c in comp]; ys = [c[1] for c in comp]
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        g = Image.new("RGBA", (x1 - x0 + 1, y1 - y0 + 1), (0, 0, 0, 0)); gp = g.load()
        for (cx, cy) in comp:
            gp[cx - x0, cy - y0] = BUBBLE
        glyphs.append(g)
    glyphs.sort(key=lambda g: -g.width * g.height)   # big, medium, small
    return glyphs


def bubble_pool(tmpl):
    """Only the three hand-drawn template bubbles (big/medium/small). Repeats from this pool are
    allowed when scattering, but no other shapes -- clean procedural rings read as 'mines', not bubbles."""
    return extract_bubbles(tmpl)


def clock_region(t1, t2):
    """Locate the clock badge: the LARGEST cluster of pixels that differ between the two templates
    (the small upper diff is just the level-pip change). Returns a padded bbox (x0,y0,x1,y1)."""
    w, h = t1.size; p1, p2 = t1.load(), t2.load()
    diff = [(x, y) for y in range(h) for x in range(w) if p1[x, y] != p2[x, y]]
    dset, seen, clusters = set(diff), set(), []
    for d in diff:
        if d in seen:
            continue
        comp, q = [], deque([d]); seen.add(d)
        while q:
            cx, cy = q.popleft(); comp.append((cx, cy))
            for ddx in range(-2, 3):
                for ddy in range(-2, 3):
                    n = (cx + ddx, cy + ddy)
                    if n in dset and n not in seen:
                        seen.add(n); q.append(n)
        xs = [c[0] for c in comp]; ys = [c[1] for c in comp]
        clusters.append((min(xs), min(ys), max(xs), max(ys), len(comp)))
    if not clusters:
        return (1, 26, 15, 38)
    clusters.sort(key=lambda c: -c[4])
    c = clusters[0]
    return (max(0, c[0] - 1), max(0, c[1] - 1), min(w - 1, c[2] + 1), min(h - 1, c[3] + 1))


def build_bases(t1, t2):
    """Derive all four (potency, lasts) base templates by swapping just the clock-badge region:
      (False,False) Lvl I  normal = t1 with the clock cleared (clock region copied from t2)
      (False,True)  Lvl I  lasts  = t1 as given (1 pip + clock)
      (True,False)  Lvl II normal = t2 as given (2 pips, no clock)
      (True,True)   Lvl II lasts  = t2 with the clock added (clock region copied from t1)"""
    x0, y0, x1, y1 = clock_region(t1, t2)
    crop1 = t1.crop((x0, y0, x1 + 1, y1 + 1))
    crop2 = t2.crop((x0, y0, x1 + 1, y1 + 1))
    b_ff = t1.copy(); b_ff.paste(crop2, (x0, y0))
    b_tt = t2.copy(); b_tt.paste(crop1, (x0, y0))
    return {(False, False): b_ff, (False, True): t1.copy(),
            (True, False): t2.copy(), (True, True): b_tt}


def blank_card(tmpl):
    card = tmpl.copy(); px = card.load()
    for y in range(H):
        for x in range(W):
            if near(px[x, y], BUBBLE):
                px[x, y] = BODY
    return card


def _overlaps(a, b, margin=1):
    """True if bounding boxes a,b (x0,y0,x1,y1) intersect (with a separating margin)."""
    return not (a[2] + margin < b[0] or a[0] - margin > b[2]
                or a[3] + margin < b[1] or a[1] - margin > b[3])


# Bubbles MAY be placed across nearly the whole card -- including over the nameplate/border -- but
# are CLIPPED to the sage body when drawn (so they never paint on the frame/nameplate). They must
# never touch the potion sprite, and never overlap each other.
PX0, PY0, PX1, PY1 = 3, 2, W - 4, H - 3


def paint_background(blank, pool, seed, sprite_bbox):
    """Scatter bubbles from `pool` (the three hand-drawn template bubbles) with a per-potion seeded
    RNG, so every card differs (like the varied starfields on Planet cards). More than three, repeats
    allowed. Each bubble pixel is drawn ONLY where the underlying card is sage body, so bubbles get
    clipped against the frame/nameplate instead of painting over them. Rejection sampling keeps every
    bubble's bounding box off the potion `sprite_bbox` and clear of the other bubbles."""
    rng = random.Random(seed)
    card = blank.copy()
    bpx = blank.load()
    placed = []
    forbidden = sprite_bbox and (sprite_bbox[0] - 1, sprite_bbox[1] - 1, sprite_bbox[2] + 1, sprite_bbox[3] + 1)
    target = rng.randint(9, 14)
    count, attempts = 0, 0
    while count < target and attempts < 900:
        attempts += 1
        g = rng.choice(pool)
        gx = rng.randint(PX0, PX1 - g.width)
        gy = rng.randint(PY0, PY1 - g.height)
        box = (gx, gy, gx + g.width - 1, gy + g.height - 1)
        if forbidden and _overlaps(box, forbidden, margin=0):      # never touch the potion
            continue
        if any(_overlaps(box, p) for p in placed):                 # never overlap another bubble
            continue
        gp = g.load(); drew = False
        for y in range(g.height):
            for x in range(g.width):
                if gp[x, y][3] == 0:
                    continue
                tx, ty = gx + x, gy + y
                if near(bpx[tx, ty], BODY):                        # clip to the sage body only
                    card.putpixel((tx, ty), BUBBLE); drew = True
        if drew:
            placed.append(box); count += 1
    return card


# ---------- fonts: bold + thin (thin completed from narrowed bold) ----------
def load_glyphs(gdir, colour):
    g = {}
    if not os.path.isdir(gdir):
        return g
    for f in os.listdir(gdir):
        if not (len(f) == 5 and f.endswith(".png") and f[0].isalpha()):
            continue
        im = Image.open(os.path.join(gdir, f)).convert("RGBA"); p = im.load()
        for y in range(im.height):
            for x in range(im.width):
                if p[x, y][3] > 0:
                    p[x, y] = colour
        g[f[0].upper()] = im
    return g


def narrow(glyph):
    """Approximate a thin glyph from a bold one: shave ~1px of width (min 2)."""
    w = max(2, glyph.width - 1)
    return glyph.resize((w, glyph.height), Image.NEAREST)


def period_glyph(colour):
    """A '.' glyph (6px tall to match letters; a single 1x1 dot on the baseline). For 'INST. HEALTH'."""
    g = Image.new("RGBA", (1, 6), (0, 0, 0, 0))
    g.load()[0, 5] = colour
    return g


def render_word(word, glyphs, gap=1, space=2):
    out_glyphs, total = [], 0
    for c in word:
        if c == " ":
            out_glyphs.append(None); total += space
        elif c in glyphs:
            out_glyphs.append(glyphs[c]); total += glyphs[c].width
    if not any(g is not None for g in out_glyphs):
        return None
    real = [g for g in out_glyphs if g is not None]
    total += gap * (len(out_glyphs) - 1)
    h = max(g.height for g in real)
    out = Image.new("RGBA", (max(1, total), h), (0, 0, 0, 0))
    x = 0
    for g in out_glyphs:
        if g is None:
            x += space + gap
            continue
        out.alpha_composite(g, (x, h - g.height)); x += g.width + gap
    return out


def fit_name(label, bold, thin, plate_w):
    """Pick the font + spacing that fits the nameplate. Bold needs a comfortable margin (else it reads
    cramped, e.g. STRENGTH at 42px in a 44px plate), so anything wider falls to the narrower thin font."""
    for glyphs, gap, limit in ((bold, 1, plate_w - 5), (thin, 1, plate_w), (thin, 0, plate_w)):
        w = render_word(label, glyphs, gap=gap)
        if w is not None and w.width <= limit:
            return w
    return render_word(label, thin, gap=0)   # last resort (may overflow slightly)


# ---------- nameplate detection (centre the label inside it) ----------
def nameplate_box(card):
    px = card.load(); seen = set(); best = None
    for y in range(60, H):
        for x in range(W):
            if (x, y) in seen or not near(px[x, y], PALE):
                continue
            comp, q = [], deque([(x, y)]); seen.add((x, y))
            while q:
                cx, cy = q.popleft(); comp.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < W and 0 <= ny < H and (nx, ny) not in seen and near(px[nx, ny], PALE):
                        seen.add((nx, ny)); q.append((nx, ny))
            xs = [c[0] for c in comp]; ys = [c[1] for c in comp]
            box = (min(xs), min(ys), max(xs), max(ys))
            if box[1] >= 70 and (box[2] - box[0]) >= 20 and len(comp) > (best and len(best[1]) or 0):
                best = (box, comp)
    return best[0] if best else (10, 76, 60, 85)


# ---------- compose one card ----------
def make_card(blank, pool, bold, thin, pid, label, seed):
    # 1) place the potion sprite (centred above the nameplate) and note its bounding box.
    sprite, sxy, sbbox = None, None, None
    sprite_path = os.path.join(SPRITEDIR, pid + ".png")
    if os.path.exists(sprite_path):
        sp = Image.open(sprite_path).convert("RGBA")
        sp = sp.resize((sp.width * SPRITE_SCALE, sp.height * SPRITE_SCALE), Image.NEAREST)
        bb = sp.getbbox(); bw, bh = bb[2] - bb[0], bb[3] - bb[1]
        cx, cy = (IX0 + IX1) / 2, (IY0 + IY1) / 2
        ox, oy = round(cx - (bb[0] + bw / 2)), round(cy - (bb[1] + bh / 2))
        sprite, sxy = sp, (ox, oy)
        sbbox = (ox + bb[0], oy + bb[1], ox + bb[2] - 1, oy + bb[3] - 1)
    # 2) bubbles around (and clipped to body), avoiding the sprite; 3) sprite on top; 4) name.
    card = paint_background(blank, pool, seed, sbbox)
    if sprite:
        card.alpha_composite(sprite, sxy)
    nx0, ny0, nx1, ny1 = NAMEPLATE
    word = fit_name(label, bold, thin, nx1 - nx0 + 1)
    if word is not None:
        px = nx0 + ((nx1 - nx0 + 1) - word.width) // 2
        py = ny0 + ((ny1 - ny0 + 1) - word.height) // 2
        card.alpha_composite(word, (px, py))
    return card


def main():
    global NAMEPLATE
    t1 = Image.open(os.path.join(OUT1, "potion_template_1_clock.png")).convert("RGBA")     # Lvl I + clock
    t2 = Image.open(os.path.join(OUT1, "potion_template_2_no_clock.png")).convert("RGBA")  # Lvl II, no clock
    bases = build_bases(t1, t2)                              # {(potency, lasts): badged template}
    blanks = {k: blank_card(v) for k, v in bases.items()}   # bubbles removed, badges kept
    pool = bubble_pool(t1)                                   # the 3 hand-drawn bubbles
    NAMEPLATE = nameplate_box(blanks[(False, False)])

    bold = load_glyphs(BOLDDIR, NAME)
    thin = load_glyphs(THINDIR, NAME)
    for ch, g in bold.items():                              # complete the thin alphabet from narrowed bold
        if ch not in thin:
            thin[ch] = narrow(g)
    bold['.'] = period_glyph(NAME); thin['.'] = period_glyph(NAME)   # for 'INST. HEALTH'

    cols, rows = len(COMBOS), len(POTIONS)
    sheet = Image.new("RGBA", (cols * W, rows * H), (0, 0, 0, 0))
    made = 0
    for row, (pid, label, accepts_pot, accepts_las) in enumerate(POTIONS):
        for col, (pot, las) in enumerate(COMBOS):
            if (pot and not accepts_pot) or (las and not accepts_las):
                continue                                    # this combo doesn't exist for this potion
            card = make_card(blanks[(pot, las)], pool, bold, thin, pid, label, seed=1000 + row * 4 + col)
            sheet.alpha_composite(card, (col * W, row * H))
            made += 1
    os.makedirs(OUT1, exist_ok=True); os.makedirs(OUT2, exist_ok=True)
    sheet.save(os.path.join(OUT1, "potion_cards.png"))
    sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(os.path.join(OUT2, "potion_cards.png"))
    print(f"Wrote 1x/potion_cards.png {sheet.size} ({cols}x{rows} grid, {made} cards) + 2x")


if __name__ == "__main__":
    main()
