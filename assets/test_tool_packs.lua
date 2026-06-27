-- Headless unit tests for utilities/tool_packs.lua (pure pack logic only). NOT loaded by the mod.
-- Run from the mod root:  lua assets/test_tool_packs.lua   (exit 0 = all pass)

-- ---- stub globals the logic reads -------------------------------------------------
local _seed = 1
local rng_queue = {}          -- when non-empty, pseudorandom pops from here (deterministic tests)
function pseudorandom(seed)
    if #rng_queue > 0 then return table.remove(rng_queue, 1) end
    _seed = (_seed * 1103515245 + 12345) % 2147483648
    return _seed / 2147483648
end
function pseudoseed(key) return key end
function pseudorandom_element(t, seed)
    local r = pseudorandom(seed)
    local idx = 1 + math.floor(r * #t)
    if idx > #t then idx = #t end
    return t[idx]
end

local last_created            -- captures the most recent create_card call
function create_card(_type, area, leg, rar, skip, soul, key, key_append)
    last_created = { type = _type, key = key, key_append = key_append,
                     ability = { extra = { enchants = {} } },
                     config = { center = { key = key } } }
    return last_created
end

local enchant_calls = {}      -- set_tool_enchant stub records here (real impl is in enchanting.lua)
PB_UTIL = {}
function PB_UTIL.set_tool_enchant(card, etype, tier)
    enchant_calls[#enchant_calls + 1] = { card = card, etype = etype, tier = tier }
end

PB_UTIL.ENCHANT_ORDER = { 'sharpness', 'durability', 'fortune' }
local APPLIES = {
    sharpness  = { sword = true },
    durability = { sword = true, pickaxe = true, shovel = true },
    fortune    = { pickaxe = true, shovel = true },
}
function PB_UTIL.enchant_applies(etype, kind)
    return APPLIES[etype] ~= nil and APPLIES[etype][kind] == true
end

-- 18 tools (3 kinds x 6 materials), mirroring content/tools/registry.lua build order.
PB_UTIL.TOOLS = {}
do
    local kinds = { 'sword', 'pickaxe', 'shovel' }
    local mats  = { 'wood', 'cobblestone', 'iron', 'gold', 'diamond', 'netherite' }
    for _, kind in ipairs(kinds) do
        for tier, mat in ipairs(mats) do
            PB_UTIL.TOOLS[#PB_UTIL.TOOLS + 1] = { id = kind .. '_' .. mat, tool = kind, tier = tier }
        end
    end
end
local TIER = {}
for _, t in ipairs(PB_UTIL.TOOLS) do TIER[t.id] = t.tier end

G = { GAME = { round_resets = { ante = 1 }, modifiers = {} },
      P_CENTERS = { ['c_balacraft_torch'] = true },
      pack_cards = {} }

-- ---- load the real source under test ----------------------------------------------
dofile('utilities/tool_packs.lua')

-- ---- micro assert harness ---------------------------------------------------------
local failures, total = 0, 0
local function check(name, fn)
    total = total + 1
    local ok, res = pcall(fn)
    if ok and res then
        print('  ok   ' .. name)
    else
        failures = failures + 1
        print('  FAIL ' .. name .. (ok and '' or ('  (error: ' .. tostring(res) .. ')')))
    end
end
local function clear(t) for k in pairs(t) do t[k] = nil end end
local function set_ante(a) G.GAME.round_resets.ante = a end
local function reset_rng() clear(rng_queue); _seed = 1 end

PB_UTIL.ENCHANTS = {}   -- enchant system "on" for most tests (toggled off in the guard test)

-- ===== max_tool_tier ===============================================================
check('max_tool_tier ante1 = 2',  function() return PB_UTIL.max_tool_tier(1) == 2 end)
check('max_tool_tier ante2 = 2',  function() return PB_UTIL.max_tool_tier(2) == 2 end)
check('max_tool_tier ante3 = 3',  function() return PB_UTIL.max_tool_tier(3) == 3 end)
check('max_tool_tier ante4 = 3',  function() return PB_UTIL.max_tool_tier(4) == 3 end)
check('max_tool_tier ante5 = 4',  function() return PB_UTIL.max_tool_tier(5) == 4 end)
check('max_tool_tier ante6 = 5',  function() return PB_UTIL.max_tool_tier(6) == 5 end)
check('max_tool_tier ante7 = 5',  function() return PB_UTIL.max_tool_tier(7) == 5 end)
check('max_tool_tier ante8 = 6',  function() return PB_UTIL.max_tool_tier(8) == 6 end)
check('max_tool_tier ante99 = 6', function() return PB_UTIL.max_tool_tier(99) == 6 end)
check('max_tool_tier nil = 2',    function() return PB_UTIL.max_tool_tier(nil) == 2 end)

-- ===== sample_pack_tools ===========================================================
check('sample ante1 never exceeds tier 2', function()
    set_ante(1); reset_rng()
    for _ = 1, 400 do
        local e = PB_UTIL.sample_pack_tools(1)[1]
        if e.id ~= 'torch' and TIER[e.id] > 2 then return false end
    end
    return true
end)
check('sample favours low tiers at ante8', function()
    set_ante(8); reset_rng()
    local t1, t6 = 0, 0
    for _ = 1, 2000 do
        local e = PB_UTIL.sample_pack_tools(1)[1]
        if e.id ~= 'torch' then
            if TIER[e.id] == 1 then t1 = t1 + 1 elseif TIER[e.id] == 6 then t6 = t6 + 1 end
        end
    end
    return t1 > t6 and t6 > 0   -- wood common, netherite present but rare
end)
check('sample returns distinct ids', function()
    set_ante(8); reset_rng()
    local e = PB_UTIL.sample_pack_tools(3)
    return #e == 3 and e[1].id ~= e[2].id and e[2].id ~= e[3].id and e[1].id ~= e[3].id
end)
check('torch can appear and is never enchanted', function()
    set_ante(1); reset_rng()
    local saw_torch = false
    for _ = 1, 400 do
        for _, e in ipairs(PB_UTIL.sample_pack_tools(1)) do
            if e.id == 'torch' then saw_torch = true; if e.ench ~= nil then return false end end
        end
    end
    return saw_torch
end)
check('torch absent when center missing', function()
    local saved = G.P_CENTERS['c_balacraft_torch']; G.P_CENTERS['c_balacraft_torch'] = nil
    set_ante(1); reset_rng()
    local ok = true
    for _ = 1, 200 do if PB_UTIL.sample_pack_tools(1)[1].id == 'torch' then ok = false end end
    G.P_CENTERS['c_balacraft_torch'] = saved
    return ok
end)

-- ===== roll_pack_enchant ===========================================================
local SWORD = PB_UTIL.TOOLS[1]   -- sword_wood
local PICK  = PB_UTIL.TOOLS[7]   -- pickaxe_wood
check('roll returns nil when enchants disabled', function()
    local saved = PB_UTIL.ENCHANTS; PB_UTIL.ENCHANTS = nil
    reset_rng(); rng_queue = { 0.0, 0.0, 0.0 }
    local r = PB_UTIL.roll_pack_enchant(SWORD, 8)
    PB_UTIL.ENCHANTS = saved
    return r == nil
end)
check('roll fires below chance, nil above (ante1)', function()
    reset_rng(); rng_queue = { 0.9 }                 -- 0.9 >= 0.05 -> no enchant
    if PB_UTIL.roll_pack_enchant(SWORD, 1) ~= nil then return false end
    reset_rng(); rng_queue = { 0.01, 0.0, 0.0 }       -- 0.01 < 0.05 -> fires; type idx0; tier I
    local r = PB_UTIL.roll_pack_enchant(SWORD, 1)
    return r ~= nil and r.tier == 1
end)
check('tier gated: ante1 only I even on high roll', function()
    reset_rng(); rng_queue = { 0.0, 0.0, 0.999 }       -- fire, type idx0, high tier roll
    local r = PB_UTIL.roll_pack_enchant(SWORD, 1)
    return r ~= nil and r.tier == 1
end)
check('tier gated: ante7 high roll reaches III', function()
    reset_rng(); rng_queue = { 0.0, 0.0, 0.999 }
    local r = PB_UTIL.roll_pack_enchant(SWORD, 7)
    return r ~= nil and r.tier == 3
end)
check('sword never rolls fortune', function()
    reset_rng()                                    -- once: let the LCG advance across samples
    for _ = 1, 200 do
        local r = PB_UTIL.roll_pack_enchant(SWORD, 8)
        if r and r.etype == 'fortune' then return false end
    end
    return true
end)
check('pickaxe can roll fortune, never sharpness', function()
    reset_rng()                                    -- once: identical reseed per-iter would freeze the roll
    local saw_fortune = false
    for _ = 1, 400 do
        local r = PB_UTIL.roll_pack_enchant(PICK, 8)
        if r then
            if r.etype == 'sharpness' then return false end
            if r.etype == 'fortune' then saw_fortune = true end
        end
    end
    return saw_fortune
end)

-- ===== create_tool_pack_card =======================================================
check('builds tool key + applies enchant for that slot', function()
    clear(enchant_calls); last_created = nil
    local booster = { balacraft_pack_tools = {
        { id = 'sword_iron', ench = { etype = 'sharpness', tier = 2 } },
        { id = 'torch' },
    } }
    PB_UTIL.create_tool_pack_card(booster, 1, 3)
    if last_created.key ~= 'c_balacraft_tool_sword_iron' then return false end
    if #enchant_calls ~= 1 or enchant_calls[1].etype ~= 'sharpness' or enchant_calls[1].tier ~= 2 then return false end
    PB_UTIL.create_tool_pack_card(booster, 2, 3)
    return last_created.key == 'c_balacraft_torch' and #enchant_calls == 1   -- torch unchanged
end)
check('samples once and caches on the booster', function()
    set_ante(8); reset_rng()
    local booster = {}
    PB_UTIL.create_tool_pack_card(booster, 1, 3)
    return type(booster.balacraft_pack_tools) == 'table'
        and #booster.balacraft_pack_tools >= 1 and #booster.balacraft_pack_tools <= 3
end)
check('honours booster_size_mod', function()
    set_ante(1); reset_rng()
    G.GAME.modifiers.booster_size_mod = 2
    local booster = {}
    PB_UTIL.create_tool_pack_card(booster, 1, 3)         -- ante1 pool = 6 tools + torch = 7; size = min(5,7)
    G.GAME.modifiers.booster_size_mod = 0
    return #booster.balacraft_pack_tools == 5
end)

-- ---- summary ----------------------------------------------------------------------
print(('\n%d/%d checks passed'):format(total - failures, total))
os.exit(failures == 0 and 0 or 1)
