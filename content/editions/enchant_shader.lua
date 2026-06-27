-- Registers the single composite enchant glint shader (assets/shaders/balacraft_enchant.fs) and
-- feeds it the per-enchant tiers every frame. SMODS prefixes the key by the mod prefix, so
-- key 'enchant' -> G.SHADERS['balacraft_enchant']; the edition files set shader = 'enchant'
-- (also prefixed to 'balacraft_enchant'), so they line up with NO prefix_config override.
--
-- Loads FIRST in PB_UTIL.ENABLED_EDITIONS (see utilities/definitions.lua) so the shader exists
-- before the editions that reference it register. send_vars runs at DRAW time, by which point
-- PB_UTIL.is_tool_card (utilities/enchanting.lua) is loaded.
--
-- send_vars(sprite, parent_card): parent_card is the Card being drawn (set by Sprite:draw_shader
-- as self.role.major). Returns enchant_tiers = {sharpness, durability, fortune} each 0..3.
--   * Tools  -> live, STACKED tiers off card.ability.extra.enchants.
--   * Cards  -> the one enchant encoded in the edition key (e_balacraft_<type>_<tier>).
-- Animation/time is NOT sent here -- the shader reads it from the built-in `enchant` vec2
-- (send_to_shader), exactly like vanilla foil/holo.

SMODS.Shader {
    key = 'enchant',
    path = 'balacraft_enchant.fs',
    send_vars = function(_, card)
        if card and PB_UTIL.is_tool_card and PB_UTIL.is_tool_card(card) then
            local e = (card.ability and card.ability.extra and card.ability.extra.enchants) or {}
            return { enchant_tiers = { e.sharpness or 0, e.durability or 0, e.fortune or 0 } }
        end
        local key = card and card.edition and card.edition.key
        if key then
            local t = key:match('sharpness_(%d)')
            if t then return { enchant_tiers = { tonumber(t), 0, 0 } } end
            t = key:match('lucky_(%d)')
            if t then return { enchant_tiers = { 0, 0, tonumber(t) } } end
            if key:match('unbreaking') then
                return { enchant_tiers = { 0, 3, 0 } }   -- flat Unbreaking -> full-strength cyan
            end
        end
        return { enchant_tiers = { 0, 0, 0 } }
    end,
}
