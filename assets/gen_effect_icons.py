#!/usr/bin/env python3
"""Generate the active-effect status-icon sheet (assets/1x/effect_icons.png + 2x), atlas
`bc_effect_icons` (34x34 cells).

Each icon is the authentic 18x18 Minecraft mob-effect texture -- the in-game status-effect
HUD sprite (sword/heart/eye/etc.) -- FETCHED from the vanilla asset mirror into
assets/reference/effects/<name>.png, then framed in the project's Balatro tag-badge style
(assets/badge.py) with a per-effect accent recolour of the frame ring (the vanilla
potion-liquid colours, so each badge reads at a glance).

This backs the active-effects HUD row (utilities/effects_ui.lua): one cell per lasting
potion effect, shown below the consumable area while the effect's timer is running.

Authentic textures only -- nothing is hand-drawn or procedurally synthesised; the fetch
raises on any failure and never falls back to generated art.

Run from Mods/:  python3 BalaCraft/assets/gen_effect_icons.py
"""
import os
import urllib.request
from PIL import Image
from badge import badge_icon
from utils import scale_image

CELL = 34

# Vanilla mob_effect texture mirror (filenames match the canonical effect names).
_MIRROR = ("https://raw.githubusercontent.com/InventivetalentDev/minecraft-assets/"
           "1.20.4/assets/minecraft/textures/mob_effect")

# (HUD effect id, MC mob_effect texture name, accent RGB for the frame ring).
# The Healing potion's effect is regeneration-over-blinds, so it uses the Regeneration
# sprite; Harming is MC Instant Damage. ORDER == the column order in the sheet and MUST
# match PB_UTIL.EFFECT_HUD / icon_pos in utilities/effects_ui.lua.
EFFECTS = [
    ("strength",     "strength",       (147,  36,  35)),  # dark red
    ("regeneration", "regeneration",   (205,  92, 171)),  # pink
    ("night_vision", "night_vision",   ( 31,  31, 161)),  # deep blue
    ("invisibility", "invisibility",   (127, 131, 146)),  # grey
    ("poison",       "poison",         ( 78, 147,  49)),  # green
    ("harming",      "instant_damage", (110,  28,  28)),  # crimson
]

_HERE = os.path.dirname(os.path.abspath(__file__))                       # Mods/BalaCraft/assets
_REF  = os.path.normpath(os.path.join(_HERE, "..", "..", "assets", "reference", "effects"))


def fetch(tex_name):
    """Local path to the authentic texture, downloading it from the vanilla mirror on
    first run. Raises on any network/HTTP failure -- never substitutes generated art."""
    os.makedirs(_REF, exist_ok=True)
    path = os.path.join(_REF, tex_name + ".png")
    if not os.path.exists(path):
        urllib.request.urlretrieve(_MIRROR + "/" + tex_name + ".png", path)   # raises on failure
    return path


def build():
    sheet = Image.new("RGBA", (CELL * len(EFFECTS), CELL), (0, 0, 0, 0))
    for col, (eid, tex, accent) in enumerate(EFFECTS):
        spr = Image.open(fetch(tex)).convert("RGBA")
        bb = spr.getbbox()
        if bb:
            spr = spr.crop(bb)                  # trim the 18x18 texture's transparent padding
        cell = badge_icon(spr, accent)          # thin accent frame + neutral interior + sprite
        sheet.alpha_composite(cell, (col * CELL, 0))
    out1 = "BalaCraft/assets/1x/effect_icons.png"
    os.makedirs(os.path.dirname(out1), exist_ok=True)
    sheet.save(out1)
    scale_image(out1, "BalaCraft/assets/2x/effect_icons.png", 2)
    print("wrote effect_icons.png", sheet.size, "cols:", [e[0] for e in EFFECTS])


if __name__ == "__main__":
    build()
