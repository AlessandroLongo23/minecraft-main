-- Headless unit tests for the consumable-stacking logic in utilities/inventory_model.lua.
-- NOT loaded by the mod. Run from the mod root:  lua assets/test_consumable_stacking.lua
-- Exit 0 = all pass.

-- ---- stub the globals inventory_model.lua reads (only inside functions) ----
G = { GAME = { balacraft = { resources = {}, inv = { stored = {} }, stations = {} } } }
PB_UTIL = {}
function PB_UTIL.get_resource_count(id) return (G.GAME.balacraft.resources[id]) or 0 end

dofile('utilities/inventory_model.lua')

-- ---- tiny test runner (mirrors assets/test_tool_packs.lua) ----
local total, failures = 0, 0
local function check(name, cond)
    total = total + 1
    if cond then print('  ok   ' .. name)
    else failures = failures + 1; print('  FAIL ' .. name) end
end

-- a fake saved-card table for center `key`
local function saved(key) return { save_fields = { center = key } } end

-- is_stackable_consumable
check('sheet stacks',      PB_UTIL.is_stackable_consumable('balacraft_sheet', 'c_balacraft_sheet_lapis') == true)
check('food stacks',       PB_UTIL.is_stackable_consumable('balacraft_food', 'c_balacraft_food_steak') == true)
check('non-core tool stacks', PB_UTIL.is_stackable_consumable('balacraft_tool', 'c_balacraft_arrow') == true)
check('core tool no stack', PB_UTIL.is_stackable_consumable('balacraft_tool', 'c_balacraft_tool_sword_wood') == false)
check('potion no stack',    PB_UTIL.is_stackable_consumable('balacraft_potion', 'c_balacraft_potion_healing') == false)
check('book no stack',      PB_UTIL.is_stackable_consumable('balacraft_enchant', 'c_balacraft_enchant_sharpness') == false)
check('nil key tool no stack', PB_UTIL.is_stackable_consumable('balacraft_tool', nil) == false)

-- CONSUMABLE_STACK_MAX
check('stack max is 4', PB_UTIL.CONSUMABLE_STACK_MAX == 4)

-- accessors: new format
local new_entry = { saved = saved('c_balacraft_food_steak'), count = 3 }
check('new saved',  PB_UTIL.stored_entry_saved(new_entry).save_fields.center == 'c_balacraft_food_steak')
check('new count',  PB_UTIL.stored_entry_count(new_entry) == 3)
check('new center', PB_UTIL.stored_entry_center(new_entry) == 'c_balacraft_food_steak')

-- accessors: legacy bare-save format (implicit count 1)
local legacy = saved('c_balacraft_arrow')
check('legacy saved',  PB_UTIL.stored_entry_saved(legacy).save_fields.center == 'c_balacraft_arrow')
check('legacy count',  PB_UTIL.stored_entry_count(legacy) == 1)
check('legacy center', PB_UTIL.stored_entry_center(legacy) == 'c_balacraft_arrow')

-- stored_find_mergeable
local list = { { saved = saved('c_balacraft_food_steak'), count = 2 } }
check('find matching non-full', PB_UTIL.stored_find_mergeable(list, 'balacraft_food', 'c_balacraft_food_steak') == 1)
check('find different center nil', PB_UTIL.stored_find_mergeable(list, 'balacraft_food', 'c_balacraft_food_apple') == nil)
check('find non-stackable nil', PB_UTIL.stored_find_mergeable(list, 'balacraft_potion', 'c_balacraft_potion_healing') == nil)
local full = { { saved = saved('c_balacraft_food_steak'), count = 4 } }
check('find full stack nil', PB_UTIL.stored_find_mergeable(full, 'balacraft_food', 'c_balacraft_food_steak') == nil)

-- stored_merge_add: merge into existing
local m1 = { { saved = saved('c_balacraft_food_steak'), count = 2 } }
PB_UTIL.stored_merge_add(m1, saved('c_balacraft_food_steak'), 'balacraft_food', 'c_balacraft_food_steak')
check('merge increments count', #m1 == 1 and m1[1].count == 3)

-- stored_merge_add: new entry when full
local m2 = { { saved = saved('c_balacraft_food_steak'), count = 4 } }
PB_UTIL.stored_merge_add(m2, saved('c_balacraft_food_steak'), 'balacraft_food', 'c_balacraft_food_steak')
check('full stack spills to new entry', #m2 == 2 and m2[2].count == 1)

-- stored_merge_add: non-stackable always appends count 1
local m3 = { { saved = saved('c_balacraft_potion_healing'), count = 1 } }
PB_UTIL.stored_merge_add(m3, saved('c_balacraft_potion_healing'), 'balacraft_potion', 'c_balacraft_potion_healing')
check('non-stackable never merges', #m3 == 2)

-- stored_merge_add: legacy bare entry upgrades to {saved,count} on merge
local m4 = { saved('c_balacraft_arrow') }   -- legacy bare-save, implicit count 1
PB_UTIL.stored_merge_add(m4, saved('c_balacraft_arrow'), 'balacraft_tool', 'c_balacraft_arrow')
check('legacy merge upgrades format', #m4 == 1 and m4[1].saved ~= nil and m4[1].count == 2)

-- inv_can_fit_consumable: no-arg keeps "is there a free slot?" meaning (18 base, 0 used -> yes)
G.GAME.balacraft.inv.stored = {}
check('empty inv fits (no-arg)', PB_UTIL.inv_can_fit_consumable() == true)

-- fill all 18 base slots with non-stackable entries -> no free slot
G.GAME.balacraft.inv.stored = {}
for _ = 1, 18 do
    G.GAME.balacraft.inv.stored[#G.GAME.balacraft.inv.stored + 1] =
        { saved = saved('c_balacraft_potion_healing'), count = 1 }
end
check('full inv rejects new (no-arg)', PB_UTIL.inv_can_fit_consumable() == false)
check('full inv rejects new potion', PB_UTIL.inv_can_fit_consumable('balacraft_potion', 'c_balacraft_potion_healing') == false)

-- but a stackable with a non-full matching stack fits even at 0 free slots
G.GAME.balacraft.inv.stored[1] = { saved = saved('c_balacraft_food_steak'), count = 2 }
check('stackable merges at 0 free', PB_UTIL.inv_can_fit_consumable('balacraft_food', 'c_balacraft_food_steak') == true)
check('stackable no match rejected at 0 free', PB_UTIL.inv_can_fit_consumable('balacraft_food', 'c_balacraft_food_apple') == false)

print(('\n%d/%d checks passed'):format(total - failures, total))
os.exit(failures == 0 and 0 or 1)
