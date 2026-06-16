-- Inert, draggable, display-only resource tiles. Registers NOTHING new.
-- make_resource_tile builds a plain Card from an always-present harmless base center
-- (c_balacraft_res_wood) and then OVERRIDES the center sprite to the resource's
-- 34x34 ICON art on bc_resource_icons at r.pos. Tiles are small square icons (TILE_SZ).
-- make_resource_source produces an identical inert handle for the inventory row;
-- source cards are NEVER reserved (no add_resource) and flagged bc_source=true.

-- Tunable size constant -- small square to match Minecraft slot aesthetic.
local TILE_SZ = 0.55   -- both width and height in Balatro world-units; tune in-game

-- Build an inert, draggable tile Card for resource id `rid` (e.g. 'wood', 'sticks').
-- Uses the 34x34 icon atlas for a flat square icon look (not the 71x95 card art).
-- Returns the Card, or nil if the resource id or base center is missing.
function PB_UTIL.make_resource_tile(rid, x, y)
    local r = PB_UTIL.RESOURCE_BY_ID[rid]
    if not r then return nil end
    -- Build from an always-present harmless center, then override sprite to the
    -- 34x34 icon atlas for a flat square look.
    local base = G.P_CENTERS['c_balacraft_res_wood']
    if not base then return nil end
    local card = Card(x or 0, y or 0, G.CARD_W, G.CARD_H, nil, base,
        { bypass_discovery_center = true, bypass_discovery_ui = true, discover = false })
    if card.children and card.children.center then
        card.children.center.atlas = G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]
        card.children.center:set_sprite_pos(r.pos)
    end
    -- Shrink to small square (Minecraft slot size). Sprite scale may need in-game tuning
    -- to avoid distortion from the base card aspect ratio.
    card.T.w = TILE_SZ
    card.T.h = TILE_SZ
    card.balacraft_resource = rid
    if card.ability then card.ability.balacraft_resource = rid end
    card.no_ui = true
    return card
end

-- Build an inert INVENTORY SOURCE handle for `rid`. Identical small square icon card,
-- but flagged bc_source=true. Sources are NEVER reserved (no add_resource call here).
-- They live in the inventory CardAreas and snap home after drag; the drop hook in
-- crafting_grid.lua is what reserves + spawns a real tile when a source lands on a cell.
function PB_UTIL.make_resource_source(rid, x, y)
    local r = PB_UTIL.RESOURCE_BY_ID[rid]
    if not r then return nil end
    local base = G.P_CENTERS['c_balacraft_res_wood']
    if not base then return nil end
    local card = Card(x or 0, y or 0, G.CARD_W, G.CARD_H, nil, base,
        { bypass_discovery_center = true, bypass_discovery_ui = true, discover = false })
    if card.children and card.children.center then
        card.children.center.atlas = G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]
        card.children.center:set_sprite_pos(r.pos)
    end
    card.T.w = TILE_SZ
    card.T.h = TILE_SZ
    card.balacraft_resource = rid
    if card.ability then card.ability.balacraft_resource = rid end
    card.no_ui = true
    card.bc_source = true   -- inert handle: never reserved, snaps home after drag
    return card
end

-- Recover the resource id from a tile Card (works for both placed tiles and sources).
function PB_UTIL.tile_resource(card)
    if not card then return nil end
    return card.balacraft_resource or (card.ability and card.ability.balacraft_resource) or nil
end
