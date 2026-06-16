-- Inert, draggable, display-only resource tiles. Registers NOTHING new.
-- make_resource_tile builds a plain Card from an always-present harmless base center
-- (c_balacraft_res_wood) and then OVERRIDES the center sprite to the real resource's
-- 71x95 art on bc_resource_cards at r.pos. This works UNIFORMLY for every resource id
-- in PB_UTIL.RESOURCES -- gathered ores AND the crafted 'sticks' -- because the id is
-- carried explicitly on the card, NOT derived from the base center key. No SMODS.* call
-- runs here, so there is no loc-nil crash and no pool insert. The tile Card is never
-- emplaced into G.consumeables/G.shop_*/G.pack_cards/G.play, so it never scores or
-- gets used.

-- Build an inert, draggable tile Card for resource id `rid` (e.g. 'wood', 'sticks').
-- Returns the Card, or nil if the resource id or base center is missing.
function PB_UTIL.make_resource_tile(rid, x, y)
    local r = PB_UTIL.RESOURCE_BY_ID[rid]
    if not r then return nil end
    -- Build from an always-present harmless center, then override the sprite to the
    -- real resource's 71x95 art. Works for gathered AND crafted (sticks).
    local base = G.P_CENTERS['c_balacraft_res_wood']
    if not base then return nil end
    local card = Card(x or 0, y or 0, G.CARD_W, G.CARD_H, nil, base,
        { bypass_discovery_center = true, bypass_discovery_ui = true, discover = false })
    if card.children and card.children.center then
        card.children.center.atlas = G.ASSET_ATLAS['bc_resource_cards']
        card.children.center:set_sprite_pos(r.pos)
    end
    card.balacraft_resource = rid
    if card.ability then card.ability.balacraft_resource = rid end
    card.no_ui = true
    return card
end

-- Recover the resource id from a tile Card.
function PB_UTIL.tile_resource(card)
    if not card then return nil end
    return card.balacraft_resource or (card.ability and card.ability.balacraft_resource) or nil
end
