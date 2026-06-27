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

-- Total capacity = base + Chest bonus (the Chest station, once built this run).
function PB_UTIL.inv_capacity()
    local cap = PB_UTIL.INV_BASE_SLOTS
    if bc() and bc().stations and bc().stations.chest then cap = cap + PB_UTIL.CHEST_SLOTS end
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

-- Is there room for one more stored Minecraft consumable?
function PB_UTIL.inv_can_fit_consumable()
    return PB_UTIL.inv_free() >= 1
end
