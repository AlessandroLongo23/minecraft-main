-- Pure shaped-matching logic for the crafting grid. No UI.
-- A "grid" here is a row-major array of rows; each row is an array of cells,
-- where a cell is a resource id string or `false` (empty). Matching is shaped
-- and position-normalized: trim empty border rows/cols from both the placed
-- grid and each recipe pattern, then compare cell-by-cell. No mirror/rotation.

-- Read the live 3x3 placed grid from PB_UTIL.craft_cells (set up by crafting_grid.lua).
-- Returns a 3x3 row-major table of ids or `false`. Tolerant of cells not existing yet.
function PB_UTIL.read_grid()
    local grid = {}
    local cells = PB_UTIL.craft_cells
    for i = 1, 3 do
        grid[i] = {}
        for j = 1, 3 do
            local id = false
            local area = cells and cells[i] and cells[i][j]
            if area and area.cards and area.cards[1] then
                id = PB_UTIL.tile_resource(area.cards[1]) or false
            end
            grid[i][j] = id
        end
    end
    return grid
end

-- Trim fully-empty leading/trailing rows and columns; return the tight bbox
-- (still row-major, `false` for interior gaps). A fully-empty grid -> {} (0 rows).
function PB_UTIL.normalize(grid)
    local rows = #grid
    if rows == 0 then return {} end
    local cols = #grid[1]
    -- find occupied bounding box
    local min_i, max_i, min_j, max_j = nil, nil, nil, nil
    for i = 1, rows do
        for j = 1, cols do
            if grid[i][j] then
                if not min_i or i < min_i then min_i = i end
                if not max_i or i > max_i then max_i = i end
                if not min_j or j < min_j then min_j = j end
                if not max_j or j > max_j then max_j = j end
            end
        end
    end
    if not min_i then return {} end -- nothing placed
    local out = {}
    for i = min_i, max_i do
        local row = {}
        for j = min_j, max_j do
            row[#row + 1] = grid[i][j] or false
        end
        out[#out + 1] = row
    end
    return out
end

-- Two normalized grids are equal iff same dims and same value in every cell.
local function grids_equal(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if #a[i] ~= #b[i] then return false end
        for j = 1, #a[i] do
            if a[i][j] ~= b[i][j] then return false end
        end
    end
    return true
end

-- Memoized normalized pattern per recipe (patterns never change at runtime).
local _norm_cache = {}
local function normalized_pattern(recipe)
    if _norm_cache[recipe] == nil then
        _norm_cache[recipe] = PB_UTIL.normalize(recipe.pattern)
    end
    return _norm_cache[recipe]
end

-- Match a placed grid (row-major of ids/false) against PB_UTIL.RECIPES.
-- Returns the matched recipe table, or nil. An empty placed grid never matches.
function PB_UTIL.match_grid(grid)
    local placed = PB_UTIL.normalize(grid)
    if #placed == 0 then return nil end
    for _, recipe in ipairs(PB_UTIL.RECIPES) do
        if grids_equal(placed, normalized_pattern(recipe)) then
            return recipe
        end
    end
    return nil
end
