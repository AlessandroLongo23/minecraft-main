-- Cross-run PERSISTENT progression -- the one piece of state in BalaCraft that survives
-- across runs and game restarts (everything else lives on G.GAME and resets per run).
--
-- Lifetime counters (how many times each dimension has been ENTERED, across all runs) are
-- stored in the Love2D save directory as a tiny Lua chunk, exactly the mechanism the base game
-- uses for its own profile files (e.g. '<profile>/meta.jkr' = "return {}"). Entering a dimension
-- PB_UTIL.PORTAL_UNLOCK times unlocks that dimension's start-deck. The Nether is entered by lighting
-- a Ruined Portal blind (Flint & Steel + Obsidian, utilities/structures.lua); the End by completing
-- the Eye-of-Ender trail (utilities/biomes.lua). Both call PB_UTIL.bump_progression on entry.
--
-- Robustness: every filesystem touch is pcall-guarded, so a read/write failure degrades to
-- "deck stays locked" rather than crashing the mod.

local SAVE_FILE = 'balacraft_progression.jkr'   -- save-dir root => global across profiles

-- Enter a dimension this many times (lifetime) to unlock its deck.
PB_UTIL.PORTAL_UNLOCK = 10

-- Win this many antes (boss blinds) in a biome (lifetime) to unlock that biome's start-deck.
PB_UTIL.BIOME_DECK_UNLOCK = 10

-- deck id -> the lifetime dimension-entry counter that unlocks it.
PB_UTIL.DECK_UNLOCK_COUNTER = {
    nether = 'nether_entries',
    ['end'] = 'end_entries',
}

PB_UTIL.progression = { nether_entries = 0, end_entries = 0 }

-- Serialize the flat numeric table to a loadable Lua chunk ("return {...}").
local function serialize(t)
    local parts = {}
    for k, v in pairs(t) do
        if type(v) == 'number' then
            parts[#parts + 1] = string.format('[%q]=%d', k, math.floor(v))
        end
    end
    return 'return {' .. table.concat(parts, ',') .. '}'
end

function PB_UTIL.load_progression()
    pcall(function()
        if not (love and love.filesystem and love.filesystem.getInfo(SAVE_FILE)) then return end
        local content = love.filesystem.read(SAVE_FILE)
        if not content then return end
        local chunk = load(content)
        local data = chunk and chunk()
        if type(data) == 'table' then
            for k, v in pairs(data) do
                if type(v) == 'number' then PB_UTIL.progression[k] = v end
            end
        end
    end)
end

function PB_UTIL.save_progression()
    pcall(function()
        if love and love.filesystem then
            love.filesystem.write(SAVE_FILE, serialize(PB_UTIL.progression))
        end
    end)
end

-- Whether a deck's lifetime threshold is met (used by the deck's `unlocked` field at load).
function PB_UTIL.progression_unlocks_deck(deck_id)
    local key = PB_UTIL.DECK_UNLOCK_COUNTER[deck_id]
    return key ~= nil and (PB_UTIL.progression[key] or 0) >= PB_UTIL.PORTAL_UNLOCK
end

-- Unlock a dimension deck mid-run (sets the center unlocked + shows the base-game
-- "Deck Unlocked" notification, which also persists the unlock in the profile).
function PB_UTIL.try_unlock_deck(deck_id)
    local center = G.P_CENTERS and G.P_CENTERS['b_balacraft_' .. deck_id]
    if center and center.unlocked == false then
        pcall(unlock_card, center)
    end
end

-- ---- Per-biome ante-win counters (unlock the per-biome start-decks) ----
-- Stored as flat keys 'biome_win_<id>' so the same flat serializer persists them.

function PB_UTIL.progression_unlocks_biome_deck(biome_id)
    return (PB_UTIL.progression['biome_win_' .. tostring(biome_id)] or 0) >= PB_UTIL.BIOME_DECK_UNLOCK
end

-- Unlock a biome's start-deck mid-run (center key is b_balacraft_<biome_id>).
function PB_UTIL.try_unlock_biome_deck(biome_id)
    local center = G.P_CENTERS and G.P_CENTERS['b_balacraft_' .. tostring(biome_id)]
    if center and center.unlocked == false then
        pcall(unlock_card, center)
    end
end

-- Record one ante (boss) win in `biome_id`, persist, and unlock its deck on the crossing.
-- Called from the Blind:defeat wrap in utilities/biomes.lua when a boss is defeated.
function PB_UTIL.record_biome_ante_win(biome_id)
    if not biome_id then return end
    local k = 'biome_win_' .. tostring(biome_id)
    PB_UTIL.progression[k] = (PB_UTIL.progression[k] or 0) + 1
    PB_UTIL.save_progression()
    if PB_UTIL.progression[k] >= PB_UTIL.BIOME_DECK_UNLOCK then
        PB_UTIL.try_unlock_biome_deck(biome_id)
    end
end

-- Increment a lifetime counter, persist immediately, and unlock the matching deck if the
-- entry just crossed the threshold. Called when a dimension is entered (Nether: light_nether_portal;
-- End: the Eye-of-Ender trail in bc_select_biome).
function PB_UTIL.bump_progression(counter_key)
    PB_UTIL.progression[counter_key] = (PB_UTIL.progression[counter_key] or 0) + 1
    PB_UTIL.save_progression()
    for deck_id, ckey in pairs(PB_UTIL.DECK_UNLOCK_COUNTER) do
        if ckey == counter_key and PB_UTIL.progression[counter_key] >= PB_UTIL.PORTAL_UNLOCK then
            PB_UTIL.try_unlock_deck(deck_id)
        end
    end
end

-- Load persisted counters now, at mod-load time (before decks register so their `unlocked`
-- field reads the right value).
PB_UTIL.load_progression()
