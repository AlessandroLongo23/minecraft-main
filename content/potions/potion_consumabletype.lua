-- Potion ConsumableType + the 8 Phase-1 potion centers.
--
-- Mirrors content/foods/food_consumabletype.lua, but potions are brew-only (shop_rate = 0; they
-- come from the Brewing Stand + the Potion booster pack, never the shop reroll) and route into the
-- Minecraft consumable area (set = 'balacraft_potion', registered in MC_CONSUMABLE_SETS).
--
-- Each center carries the brew-modifier flags on ability.extra (defaulted off; the Brewing Stand
-- stamps them on the produced card). use() delegates to PB_UTIL.use_potion (utilities/potions.lua).
-- bc_use_label drives the Drink/Throw button relabel (lovely.toml patch on use_and_sell_buttons).

SMODS.ConsumableType {
    key = 'balacraft_potion',
    primary_colour = HEX('9b59b6'),      -- potion purple
    secondary_colour = HEX('d2b4de'),
    collection_rows = { 4, 4 },
    shop_rate = 0,                       -- brew-only + Potion pack; never in the shop reroll
    default = 'c_balacraft_potion_healing',
    -- Picking a potion from the Potion pack ADDS it to the consumable area to drink/throw later,
    -- instead of using it on the spot. Without this, the pack falls through to the default
    -- consumable path and shows the Drink/Throw button -- but a potion's can_use is gated on being
    -- in/out of a blind, so picking it from the pack would waste it (or be impossible). SMODS reads
    -- select_card in card_select_area -> the pick emplaces into 'consumeables', and
    -- PB_UTIL.reconcile_mc_consumables() then routes it into the MC area (or inventory if full).
    -- Mirrors balacraft_tool / balacraft_enchant.
    select_card = 'consumeables',
    loc_txt = { name = 'Potion', collection = 'Potions' },
}

-- Per-potion card text (base numbers; brewed potency/duration variants tweak these in a later wave).
local TEXT = {
    swiftness = {
        'Instantly change to one of',
        '{C:attention}3{} biomes in this dimension',
        '{C:inactive}(drink outside a blind)',
    },
    strength = {
        'Balance {C:attention}10%{} of this blind\'s',
        '{C:blue}Chips{} and {C:red}Mult{}',
        '{C:inactive}(drink in a blind)',
    },
    instant_health = {
        'Instantly restore {C:attention}3{} hearts',
        '{C:inactive}(drink anytime)',
    },
    healing = {
        'Restore {C:attention}1{} heart at the start of',
        'each of the next {C:attention}3{} blinds',
        '{C:inactive}(drink anytime)',
    },
    night_vision = {
        'Reveal the next {C:attention}3{} cards',
        'you will draw this blind',
        '{C:inactive}(drink in a blind)',
    },
    invisibility = {
        'Take {C:attention}no damage{} from the',
        'boss blind this blind',
        '{C:inactive}(drink in a blind)',
    },
    poison = {
        'Each hand played or discard,',
        'lower the blind requirement by {C:attention}10%{}',
        '{C:inactive}(throw in a blind)',
    },
    harming = {
        'Instantly lower the blind',
        'requirement by {C:attention}50%{}',
        '{C:inactive}(throw in a blind)',
    },
}

for _, p in ipairs(PB_UTIL.POTIONS) do
    local potion = p
    SMODS.Consumable {
        key = 'potion_' .. potion.id,
        set = 'balacraft_potion',
        atlas = 'bc_potion_cards',
        pos = potion.pos,
        cost = potion.cost,
        discovered = true,
        -- Brew-modifier flags (stamped at brew time); splash is intrinsic to the throwables.
        config = { extra = {
            potency = false, duration = false, lingering = false,
            splash = (potion.kind == 'throw'),
        } },
        -- Read by the Drink/Throw button relabel patch (lovely.toml).
        bc_use_label = (potion.kind == 'throw') and 'Throw' or 'Drink',
        loc_txt = {
            name = potion.name,
            text = TEXT[potion.id] or { potion.name },
        },
        can_use = function(self, card)
            return PB_UTIL.potion_can_use(potion.when)
        end,
        use = function(self, card, area, copier)
            PB_UTIL.use_potion(potion.id, card)
        end,
    }
end
