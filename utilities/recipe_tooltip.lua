-- Recipe reference panel on craftable cards' hover popup. For any card whose center is the
-- output of a crafting recipe (the 18 tools, Torch, Arrow, TNT, Firework, Bone Meal, and the
-- Bow/Fishing Rod/Crossbow jokers), this appends a separate "Recipe" box -- a static 3x3
-- crafting grid of the ingredient icons -- next to the card's description, exactly the way the
-- base game shows an enhancement reference (e.g. the Gold Card box) beside a card.
--
-- HOW IT ATTACHES: Card:generate_UIBox_ability_table builds the card's ability_UIBox_table (AUT)
-- whose `.info` array becomes the side reference panels (G.UIDEF.card_h_popup -> info_tip_from_rows,
-- one titled box per entry, auto-arranged into columns). We wrap that builder and push ONE entry:
--   { { <grid node> }, name = 'Recipe' }
-- info_tip_from_rows iterates the entry as rows (each element = a row's node list) and renders
-- `name` as the box title -- so our single row holds the whole 3x3 grid under a "Recipe" header.
--
-- LIFECYCLE: the grid embeds fresh Sprite objects via G.UIT.O. The popup UIBox is rebuilt every
-- hover and removed on un-hover; UIElement:remove() (engine/ui.lua) removes each node's
-- config.object, so the ingredient sprites are torn down automatically -- no manual cleanup.
--
-- Depends on PB_UTIL.RECIPES (content/resources/recipes.lua), PB_UTIL.RESOURCE_BY_ID +
-- PB_UTIL.icon_atlas (content/resources/registry.lua). All resolved lazily at hover time, so the
-- forward reference to the joker/consumable centers (registered later in main.lua) is fine.

-- Tooltip grid sizing (smaller than the interactive crafting grid; tune in-game).
local ICON = 0.46   -- ingredient icon size (the 34x34 bc_resource_icons cell), world-units
local SLOT = ICON + 0.1

-- center key -> the recipe that outputs it (first registered wins, so Torch shows its coal recipe
-- rather than the alt Glow Ink one). Built once, lazily, after every recipe is registered.
local _by_output = nil
local function recipe_for_center(key)
    if not _by_output then
        _by_output = {}
        for _, r in ipairs(PB_UTIL.RECIPES or {}) do
            local o = r.output
            if o and o.id and (o.type == 'joker' or o.type == 'consumable') and not _by_output[o.id] then
                _by_output[o.id] = r
            end
        end
    end
    return _by_output[key]
end

-- One grid cell: a dark slot square (matches crafting_grid's cell), with the resource icon
-- centered when the pattern cell is filled (`rid` a resource id), empty when it is `false`.
local function cell_node(rid)
    local spr
    if rid then
        local r = PB_UTIL.RESOURCE_BY_ID[rid]
        local atlas = r and G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]
        if atlas then spr = Sprite(0, 0, ICON, ICON, atlas, r.pos) end
    end
    return {
        n = G.UIT.C,
        config = { align = 'cm', padding = 0.02, minw = SLOT, minh = SLOT,
                   r = 0.04, colour = G.C.UI.TRANSPARENT_DARK },
        nodes = spr and { { n = G.UIT.O, config = { object = spr } } } or {},
    }
end

-- The full 3x3 grid node (black rounded backing + nine dark slots), mirroring the crafting
-- table's look. Always the full 3x3 so the recognizable Minecraft grid shape is preserved.
function PB_UTIL.build_recipe_grid_node(recipe)
    local rows = {}
    for i = 1, 3 do
        local row = { n = G.UIT.R, config = { align = 'cm', padding = 0.02 }, nodes = {} }
        for j = 1, 3 do
            row.nodes[#row.nodes + 1] = cell_node(recipe.pattern[i][j])
        end
        rows[#rows + 1] = row
    end
    return { n = G.UIT.C, config = { align = 'cm', padding = 0.04, r = 0.06, colour = G.C.BLACK }, nodes = rows }
end

-- Wrap the AUT builder once: append the "Recipe" side panel for craftable cards. vars_only is a
-- non-UI early return (card.lua:1136 -> loc_vars, main_start, main_end), so forward it untouched.
if not PB_UTIL._recipe_tooltip_hooked then
    PB_UTIL._recipe_tooltip_hooked = true
    local _orig = Card.generate_UIBox_ability_table
    function Card:generate_UIBox_ability_table(vars_only)
        if vars_only then return _orig(self, vars_only) end
        local t = _orig(self, vars_only)
        if type(t) == 'table' and t.info then
            local key = self.config and self.config.center and self.config.center.key
            local recipe = key and recipe_for_center(key)
            if recipe then
                t.info[#t.info + 1] = { { PB_UTIL.build_recipe_grid_node(recipe) }, name = 'Recipe' }
            end
        end
        return t
    end
end
