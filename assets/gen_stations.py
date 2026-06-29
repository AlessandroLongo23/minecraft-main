"""Generate the Base STATION-ICON atlas (bc_station_icons) from genuine Minecraft 3D INVENTORY
renders. These are the small icons shown on the station "cards" in the "Your Base" overlay
(utilities/furnace.lua -> build_base_modal) AND the station recipe squares + station picker in the
unified Inventory modal (utilities/crafting_ui.lua), one per craftable station.

Pipeline mirrors gen_resources.py: source art lives in `assets/reference/stations/<id>.png`, the
genuine MC isometric inventory render downloaded from minecraft.wiki's `Invicon_<Name>.png`
convenience URLs (the same source the food/hunger sheets use). These are authentic 3D iso cubes
(crafting table, furnace, chest, composter, anvil, enchanting table) -- NOT flat block faces -- so
they match how cobblestone/wood render in BalaCraft. Most are 32x32 (a 16px model at 2x); the
brewing stand has no cube render, so its genuine icon is the flat 16x16 item sprite.

cell_for() nearest-scales each source up to ~32px (16x16 -> x2; 32x32 kept as-is) and centers it on
a transparent 34x34 cell, matching the resource/tool icon convention.

Stations with no clean inventory render (ender_chest -- entity-only) get NO cell here; their base
card falls back to a name-only card (see build_base_modal).

Output:
  assets/1x/station_icons.png  -> 34x34 cells, 4x2 grid (136x68)  + 2x derived (272x136)
Cell layout MUST match the STATION_ICONS table in utilities/furnace.lua.
"""
import os
from PIL import Image
from utils import scale_image

CELL = 34
COLS, ROWS = 4, 2

_HERE = os.path.dirname(os.path.abspath(__file__))
# Source art lives OUTSIDE the mod folder, at Mods/assets/reference/ (the parent of BalaCraft/),
# same as gen_ore_blocks.py / gen_resources.py.
_REF  = os.path.normpath(os.path.join(_HERE, "..", "..", "assets", "reference", "stations"))

# station id (== reference texture filename) -> (col, row) in the bc_station_icons atlas.
CELLS = {
    "crafting_table": (0, 0),
    "furnace":        (1, 0),
    "composter":      (2, 0),
    "anvil":          (3, 0),
    "brewing_stand":  (0, 1),   # no cube render -> genuine flat 16x16 brewing-stand item sprite
    "chest":          (1, 1),
    "enchanting_table": (2, 1),
}


def cell_for(idn):
    """Genuine MC inventory render nearest-scaled up to ~32px and centered on a 34x34 cell.
    Iso renders arrive at 32x32 (kept as-is); the 16x16 brewing-stand sprite is x2'd to 32."""
    tex = Image.open(os.path.join(_REF, idn + ".png")).convert("RGBA")
    factor = max(1, 32 // tex.width)                                  # 16 -> x2, 32 -> x1
    if factor > 1:
        tex = tex.resize((tex.width * factor, tex.height * factor), Image.NEAREST)
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    ox = (CELL - tex.width) // 2
    oy = (CELL - tex.height) // 2
    cell.alpha_composite(tex, (ox, oy))
    return cell


def build():
    sheet = Image.new("RGBA", (CELL * COLS, CELL * ROWS), (0, 0, 0, 0))
    for idn, (col, row) in CELLS.items():
        sheet.alpha_composite(cell_for(idn), (col * CELL, row * CELL))
    out = "BalaCraft/assets/1x/station_icons.png"
    sheet.save(out)
    scale_image(out, "BalaCraft/assets/2x/station_icons.png", 2)
    print("wrote station_icons.png", sheet.size, "cells:", len(CELLS))


if __name__ == "__main__":
    build()
