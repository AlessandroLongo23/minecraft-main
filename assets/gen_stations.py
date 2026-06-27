"""Generate the Base STATION-ICON atlas (bc_station_icons) from genuine 16x16 Minecraft block
textures. These are the small framed icons shown on the station "cards" in the "Your Base" overlay
(utilities/furnace.lua -> build_base_modal), one per craftable station.

Pipeline mirrors gen_resources.py: source textures live in `assets/reference/stations/<id>.png`
(downloaded from the InventivetalentDev minecraft-assets mirror, a representative block FACE -- e.g.
furnace_front, crafting_table_front, composter_side). Each is nearest-scaled into a 34x34 cell to
match the resource/tool icon convention.

Stations with no clean single-face texture (chest, ender_chest -- entity-rendered in Minecraft) get
NO cell here; their base card falls back to a name-only card (see build_base_modal).

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
    "brewing_stand":  (0, 1),
    "chest":          (1, 1),   # composited from the MC chest entity front face (see reference/stations)
}


def cell_for(idn):
    """16x16 texture nearest-scaled x2 (=32) and centered on a transparent 34x34 cell."""
    tex = Image.open(os.path.join(_REF, idn + ".png")).convert("RGBA")
    tex = tex.resize((tex.width * 2, tex.height * 2), Image.NEAREST)   # 16 -> 32
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
