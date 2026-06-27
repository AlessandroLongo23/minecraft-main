"""Procedurally bake the enchanted-tool atlas `bc_tool_cards` using Visual Enchantments art.

Layout: 18 rows x 16 cols of 71x95 card cells (1136x1710).
  row = tool_index*6 + material_index   (build order in content/tools/registry.lua:
        swords wood..netherite = 0..5, pickaxes = 6..11, shovels = 12..17)
  col = enchant state index 0..15 = (primary_tier*4 + durability_tier)
        sword:   primary = Sharpness tier  (0..3)
        pickaxe/shovel: primary = Fortune tier (0..3)
        durability tier = 0..3 (all tools)

CHANNEL B = the item ART itself changes per enchant, an additional read on top of the live
colour-coded glint SHADER (assets/shaders/balacraft_enchant.fs). The sprite encodes WHICH enchants
are present (presence, not tier); the glint encodes colour + TIER. So the only thing that matters
to the sprite per cell is (primary_present, durability_present) -- all three primary tiers share a
sprite, as do all durability tiers.

ART = the Visual Enchantments resource pack (CiscuLog/Visual-Enchantments), staged under
Mods/assets/reference/ve_enchant/ (see download notes in that folder / the feature plan). VE is a
LAYERED system, so we composite per the analysed compatibility:
  * SWORD  : VE per-material sword = base + blade. Sharpness swaps in the sharpness blade; Durability
             adds the (disjoint) unbreaking pommel overlay. 32px -> box-downscaled to 16.
  * PICK/SHOVEL: the VANILLA 16px tool (reference/tools/<tool>_<token>.png) + VE overlays. Fortune and
             Unbreaking overlays OVERLAP on these, so they layer with Fortune (the primary) ON TOP;
             Durability still reads via the cyan glint regardless.
The composited 16px sprite replaces the tool art in the card's sprite window (the card frame,
durability bar and name come from the base tools.png cell). Column 0 (un-enchanted) is left as the
plain base; the Lua side never swaps to it. Row/col mapping is fixed & shared with
utilities/enchanting.lua -- do NOT change it.

Run:  python assets/gen_enchanted_tools.py   (writes assets/1x + assets/2x/tool_cards.png)
"""
import os
from PIL import Image

CARD_W, CARD_H = 71, 95
COLS, ROWS = 16, 18

TOOLS = ["sword", "pickaxe", "shovel"]
MATERIALS = ["wood", "cobblestone", "iron", "gold", "diamond", "netherite"]
# BalaCraft material id -> Visual Enchantments / vanilla file token.
MAT_TOKEN = {"wood": "wooden", "cobblestone": "stone", "iron": "iron",
             "gold": "golden", "diamond": "diamond", "netherite": "netherite"}

HERE = os.path.dirname(os.path.abspath(__file__))          # BalaCraft/assets
MODS = os.path.normpath(os.path.join(HERE, "..", ".."))    # Mods/
VE_DIR = os.path.join(MODS, "assets", "reference", "ve_enchant")
VAN_DIR = os.path.join(MODS, "assets", "reference", "tools")

# MC tool sprite window on the card (see gen_tool_cards.py: SPRITE_X=11, SPRITE_TOP=14, 48x48).
SPR_L, SPR_T = 11, 14
CARD_GREY = (151, 151, 151, 255)   # card body behind the sprite (baked by gen_tool_cards.py)

_cache = {}
def _img(path):
    im = _cache.get(path)
    if im is None:
        im = Image.open(path).convert("RGBA")
        _cache[path] = im
    return im


def composite_sprite(tool, material, primary, durability):
    """Return the 16x16 enchanted item sprite for (tool, material) given which enchants are present."""
    tok = MAT_TOKEN[material]
    if tool == "sword":
        # VE per-material sword: base + blade (sharpness blade if the primary is on), plus the
        # disjoint unbreaking pommel. The textures are 32px but VE draws the actual sword in the
        # BOTTOM-LEFT 16x16 quadrant (bbox 0,16..16,32; the rest is empty) -- so we CROP that
        # quadrant to get the real 16x16 sword. (Downscaling the whole 32 canvas shrank it into an
        # 8x8 corner, which is what made the sword render tiny/off.)
        spr = _img(os.path.join(VE_DIR, f"sword_base_{tok}.png")).copy()
        blade = _img(os.path.join(VE_DIR, f"sword_blade_sharpness_{tok}.png" if primary
                                  else f"sword_blade_{tok}.png"))
        spr = Image.alpha_composite(spr, blade)
        if durability:
            spr = Image.alpha_composite(spr, _img(os.path.join(VE_DIR, "sword_unbreaking.png")))
        return spr.crop((0, 16, 16, 32))
    # pickaxe / shovel: vanilla 16px base + VE overlays (Unbreaking under, Fortune on top).
    ov = "pick" if tool == "pickaxe" else "shovel"
    spr = _img(os.path.join(VAN_DIR, f"{tool}_{tok}.png")).copy()
    if durability:
        spr = Image.alpha_composite(spr, _img(os.path.join(VE_DIR, f"{ov}_unbreaking.png")))
    if primary:
        spr = Image.alpha_composite(spr, _img(os.path.join(VE_DIR, f"{ov}_fortune.png")))
    return spr


def clear_sprite_window(cell):
    """Wipe the card's sprite window back to flat card-grey so the replacement sprite has a clean
    backdrop (the base tools.png cell has the vanilla item baked in). Stays clear of the nameplate
    tab (y<14) and the durability bar (y>=72)."""
    px = cell.load()
    for y in range(14, 70):
        for x in range(9, 62):
            px[x, y] = CARD_GREY


def build_atlas():
    tools = Image.open(os.path.join(HERE, "1x", "tools.png")).convert("RGBA")  # base cards (full-durability col 0)
    atlas = Image.new("RGBA", (COLS * CARD_W, ROWS * CARD_H), (0, 0, 0, 0))

    for ti, tool in enumerate(TOOLS):
        for mi, material in enumerate(MATERIALS):
            row = ti * len(MATERIALS) + mi
            base_card = tools.crop((0, row * CARD_H, CARD_W, row * CARD_H + CARD_H)).convert("RGBA")
            for state in range(COLS):
                primary = (state // 4) > 0
                durability = (state % 4) > 0
                cell = base_card.copy()
                if state > 0:
                    clear_sprite_window(cell)
                    spr = composite_sprite(tool, material, primary, durability)
                    spr = spr.resize((48, 48), Image.NEAREST)         # 16 -> 48, crisp
                    cell.alpha_composite(spr, (SPR_L, SPR_T))
                atlas.alpha_composite(cell, (state * CARD_W, row * CARD_H))
    return atlas


def nn(img, factor):
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


if __name__ == "__main__":
    atlas = build_atlas()
    atlas.save(os.path.join(HERE, "1x", "tool_cards.png"))
    nn(atlas, 2).save(os.path.join(HERE, "2x", "tool_cards.png"))
    print("wrote tool_cards.png", atlas.size, "(18 rows x 16 cols of 71x95) from Visual Enchantments art")
