-- Inventory capacity model.
--
-- The unified Minecraft inventory has REAL capacity: a fixed number of slots. Resources auto-stack
-- (up to STACK_MAX each); every stored Minecraft consumable (tool / food / book) takes one slot.
-- The two EQUIPPED Minecraft-consumable slots (the on-screen "hotbar") are SEPARATE and do NOT
-- count against this capacity.
--
-- Source of truth (both plain tables on G.GAME => auto-saved within a run, auto-reset per run, the
-- same hybrid model as the resource counts -- no custom save/load):
--   * G.GAME.balacraft.resources       -> { id = count }            (shown as 16-stacks)
--   * G.GAME.balacraft.inv.stored       -> { <card:save()>, ... }    (stored MC consumables)
--   * G.GAME.balacraft.inv.equipped     -> { <card:save()>, ... }    (the 2 equipped slots; mirror)

PB_UTIL.STACK_MAX      = 16    -- resources per inventory slot
PB_UTIL.INV_BASE_SLOTS = 18    -- default capacity (the Chest station expands it; see inv_capacity)
PB_UTIL.CHEST_SLOTS    = 9     -- extra slots once the Chest station is built

local function bc() return G.GAME and G.GAME.balacraft end

-- Slots a single resource count occupies (ceil to STACK_MAX; 0 when none owned).
function PB_UTIL.resource_slots_for(count)
    count = count or 0
    if count <= 0 then return 0 end
    return math.ceil(count / PB_UTIL.STACK_MAX)
end

-- Total slots used by all resource stacks.
function PB_UTIL.resource_slots_used()
    local used = 0
    local store = bc() and bc().resources
    if store then
        for _, n in pairs(store) do used = used + PB_UTIL.resource_slots_for(n) end
    end
    return used
end

-- Total slots used by stored (un-equipped) Minecraft consumables.
function PB_UTIL.consumable_slots_used()
    local inv = bc() and bc().inv
    return (inv and inv.stored and #inv.stored) or 0
end

function PB_UTIL.inv_slots_used()
    return PB_UTIL.resource_slots_used() + PB_UTIL.consumable_slots_used()
end

-- Total capacity = base + Chest bonus (the Chest station, once built this run) + any run-scoped
-- bonus (G.GAME.balacraft.inv_bonus_slots; a plain int, so auto-saved/reset per run like the rest
-- of the hybrid model -- used by the dev Test deck to make room for a stack of every resource).
function PB_UTIL.inv_capacity()
    local cap = PB_UTIL.INV_BASE_SLOTS
    if bc() and bc().stations and bc().stations.chest then cap = cap + PB_UTIL.CHEST_SLOTS end
    if bc() and bc().inv_bonus_slots then cap = cap + bc().inv_bonus_slots end
    return cap
end

function PB_UTIL.inv_free()
    return math.max(0, PB_UTIL.inv_capacity() - PB_UTIL.inv_slots_used())
end

-- How much of `amount` (>0) of resource `id` will actually FIT: fills the resource's current partial
-- stack first (no new slot), then one fresh slot per STACK_MAX, bounded by the free slots. Returns
-- 0..amount. Non-positive amounts (spends) pass straight through -- capacity never blocks a spend.
function PB_UTIL.resource_addable(id, amount)
    if not amount or amount <= 0 then return amount or 0 end
    if not bc() then return amount end   -- pre-run / no store: don't cap
    local cur = PB_UTIL.get_resource_count(id)
    local room_in_partial = PB_UTIL.resource_slots_for(cur) * PB_UTIL.STACK_MAX - cur
    local addable = room_in_partial + PB_UTIL.inv_free() * PB_UTIL.STACK_MAX
    return math.min(amount, addable)
end

-- Does adding `amount` of `id` fit completely (no loss)?
function PB_UTIL.inv_can_fit_resource(id, amount)
    return PB_UTIL.resource_addable(id, amount) >= (amount or 0)
end

-- Room for one more stored Minecraft consumable. When a stackable item's (set, center_key) is
-- given, it also fits if an existing non-full matching stack can absorb it (no new slot needed).
-- The no-arg form keeps the old meaning (is there a free slot?).
function PB_UTIL.inv_can_fit_consumable(set, center_key)
    if set and center_key then
        local inv = bc() and bc().inv
        if inv and inv.stored and PB_UTIL.stored_find_mergeable(inv.stored, set, center_key) then
            return true
        end
    end
    return PB_UTIL.inv_free() >= 1
end

-- ── Consumable stacking (sheets / food / non-core tools) ─────────────────────────
-- Fungible consumables stack up to CONSUMABLE_STACK_MAX per inventory slot; per-instance-stateful
-- ones never do. Core tools carry durability + enchants and have keys 'c_balacraft_tool_*';
-- potions carry potency/modifier variants; enchant books differ by enchant. See the design spec.
PB_UTIL.CONSUMABLE_STACK_MAX = 4

function PB_UTIL.is_stackable_consumable(set, center_key)
    if set == 'balacraft_sheet' then return true end
    if set == 'balacraft_food'  then return true end
    if set == 'balacraft_tool'  then
        return center_key ~= nil and center_key:match('^c_balacraft_tool_') == nil
    end
    return false
end

-- A stored entry is either the new { saved = <card:save()>, count = N } or a LEGACY bare save table
-- (implicit count 1, from a run started before stacking existed). `entry.saved` is the discriminator
-- (a card:save() table never has a top-level `saved` key). These accessors tolerate both formats.
function PB_UTIL.stored_entry_saved(entry)
    if not entry then return nil end
    if entry.saved then return entry.saved end
    return entry
end
function PB_UTIL.stored_entry_count(entry)
    if not entry then return 0 end
    return entry.count or 1
end
function PB_UTIL.stored_entry_center(entry)
    local s = PB_UTIL.stored_entry_saved(entry)
    return s and s.save_fields and s.save_fields.center or nil
end

-- Index of a stored entry that a NEW copy of (set, center_key) may merge into: same center,
-- stackable, and not yet full. nil if none / not stackable. Pure (operates on the plain list).
function PB_UTIL.stored_find_mergeable(stored, set, center_key)
    if not (stored and PB_UTIL.is_stackable_consumable(set, center_key)) then return nil end
    for i, entry in ipairs(stored) do
        if PB_UTIL.stored_entry_center(entry) == center_key
           and PB_UTIL.stored_entry_count(entry) < PB_UTIL.CONSUMABLE_STACK_MAX then
            return i
        end
    end
    return nil
end

-- Add one copy (its `saved` table + set + center_key) to `stored`: merge into a matching non-full
-- stack when stackable, else append a fresh { saved, count = 1 }. A legacy bare-save entry that is
-- merged into is upgraded to the { saved, count } format. Mutates `stored`; returns the entry index.
function PB_UTIL.stored_merge_add(stored, saved, set, center_key)
    local i = PB_UTIL.stored_find_mergeable(stored, set, center_key)
    if i then
        local entry = stored[i]
        if entry.saved then
            entry.count = (entry.count or 1) + 1
        else
            stored[i] = { saved = entry, count = 2 }   -- upgrade legacy bare-save entry
        end
        return i
    end
    stored[#stored + 1] = { saved = saved, count = 1 }
    return #stored
end
