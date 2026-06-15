-- Resource state + helpers

-- Seed per-run resource counts on G.GAME via an init_game_object wrapper.
-- Runs fresh for every new run, so counts auto-reset; plain integers => auto-saved.
local _init_game_object = Game.init_game_object
function Game:init_game_object()
    local t = _init_game_object(self)
    t.minecraft = t.minecraft or {}
    t.minecraft.resources = {}
    for _, r in ipairs(PB_UTIL.RESOURCES or {}) do
        t.minecraft.resources[r.id] = 0
    end
    return t
end

-- Defensive accessor: guarantees the table exists before read/write.
local function ensure_store()
    G.GAME.minecraft = G.GAME.minecraft or {}
    G.GAME.minecraft.resources = G.GAME.minecraft.resources or {}
    return G.GAME.minecraft.resources
end

function PB_UTIL.get_resource_count(id)
    return ensure_store()[id] or 0
end

function PB_UTIL.set_resource(id, amount)
    local store = ensure_store()
    store[id] = math.max(0, math.floor(tonumber(amount) or 0))
    return store[id]
end

-- Single mutation funnel. Marks the panel dirty when an ore is first owned (0 -> >0)
-- so the UI can flip it from greyed to active (see Task 3).
function PB_UTIL.add_resource(id, amount)
    local store = ensure_store()
    local prev = store[id] or 0
    local new = math.max(0, prev + (math.floor(tonumber(amount) or 0)))
    store[id] = new
    if prev == 0 and new > 0 then
        G.GAME.minecraft._panel_dirty = true
    end
    return new
end
