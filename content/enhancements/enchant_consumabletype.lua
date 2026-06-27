-- Enchanting Book consumable type + the 9 books (3 types x 3 tiers).
--
-- Books are bought in the SHOP (gated by the Enchanting Table voucher) and appear in the
-- Enchanting booster pack. A book is NOT "used" on its own (can_use = false): it is consumed
-- by the Enchant action -- select a tool + a book, then click Enchant (utilities/enchanting.lua).
--
-- ART: each book is a per-type tinted enchanted-book card on the bc_enchant_cards atlas
-- (col = tier I/II/III, row = type). Baked by assets/gen_enchant_books.py.
--
-- Depends on PB_UTIL.ENCHANTS / PB_UTIL.ENCHANT_BOOKS and the bc_enchant_cards atlas, both
-- in content/enhancements/registry.lua (loads first).

SMODS.ConsumableType {
    key = 'balacraft_enchant',
    primary_colour = HEX('8e44ad'),         -- enchant purple
    secondary_colour = HEX('c39bd3'),
    collection_rows = { 3, 3, 3 },          -- 9 books, three rows of three (by type)
    shop_rate = 0,                          -- base 0; the voucher enables shop appearance (Phase C)
    -- From a booster pack a book is SELECTED into the consumable area (like a Buffoon-pack joker),
    -- NOT "used" (books are can_use = false; they're consumed later by the Enchant action, which
    -- reads tool + book from G.consumeables). The Select button auto-greys when the consumable
    -- area is full (SMODS' can_select_from_booster checks card_limit), giving the "only if there's
    -- room" behavior for free. See SMODS.card_select_area / use_card's select_to branch.
    select_card = 'consumeables',
    default = 'c_balacraft_enchant_sharpness_1',
    loc_txt = { name = 'Enchant', collection = 'Enchanting Books' },
}

-- A book is eligible for pools only once the Enchanting Table voucher is owned. (Direct
-- spawns -- dev console, the Enchant booster's create_card -- bypass in_pool, so the booster
-- and tests still work; this only gates the random shop/pool appearance.)
local function book_unlocked()
    return G.GAME and G.GAME.used_vouchers
        and G.GAME.used_vouchers['v_balacraft_enchanting_table'] == true
end

-- Tier III books are gated behind the upgraded voucher (Sorcerer's Tome), so owning it
-- shifts the shop pool toward higher tiers.
local function tier3_unlocked()
    return G.GAME and G.GAME.used_vouchers
        and G.GAME.used_vouchers['v_balacraft_sorcerers_tome'] == true
end

local function book_text(b)
    local def = PB_UTIL.ENCHANTS[b.etype]
    if b.etype == 'sharpness' then
        -- Dual-target: on a sword it scales by tier (X-mult); on a playing card it applies the
        -- tiered Sharpness edition (+10/+15/+20 Mult, doubled vs boss).
        local cm = ({ 10, 15, 20 })[b.tier]
        return {
            '{C:attention}Sword{}: {X:mult,C:white}X' .. def.mult[b.tier] .. '{} Mult.',
            '{C:attention}Card{}: {C:mult}+' .. cm .. '{} Mult ({C:mult}+' .. (cm * 2) .. '{} vs boss).',
            '{C:inactive}Select a sword or a card, + this book.',
        }
    elseif b.etype == 'durability' then
        -- Dual-target: on a tool it raises max Uses; on a card it applies the flat Unbreaking edition.
        return {
            '{C:attention}Tool{}: {C:green}X' .. def.mult[b.tier] .. '{} max Uses (round up).',
            '{C:attention}Card{}: can\'t be {C:attention}debuffed{} by bosses.',
            '{C:inactive}Select a tool or a card, + this book.',
        }
    else -- fortune
        -- Dual-target: on a pickaxe/shovel it adds loot; on a card it applies the Lucky edition.
        return {
            '{C:attention}Tool{}: up to {C:attention}+' .. def.bonus[b.tier] .. '{} bonus loot.',
            '{C:attention}Card{}: drops {C:attention}Emeralds{} on score.',
            '{C:inactive}Select a tool or a card, + this book.',
        }
    end
end

for _, book in ipairs(PB_UTIL.ENCHANT_BOOKS) do
    local b = book
    SMODS.Consumable {
        key = 'enchant_' .. b.id,               -- => c_balacraft_enchant_sharpness_1
        set = 'balacraft_enchant',
        atlas = 'bc_enchant_cards',             -- per-type tinted book, col = tier, row = type
        pos = b.pos,
        cost = b.cost,
        discovered = true,
        config = { extra = { etype = b.etype, tier = b.tier } },
        loc_txt = { name = b.name, text = book_text(b) },
        -- Consumed by the Enchant action, never the Use button.
        can_use = function(self, card) return false end,
        use = function(self, card, area, copier) end,
        in_pool = function(self, args)
            if not book_unlocked() then return false end
            if b.tier >= 3 and not tier3_unlocked() then return false end
            return true
        end,
    }
end
