-- Cash Out screen: resource reward summary rows.
--
-- grant_blind_drop (the Blind:defeat wrapper in resources.lua) records what dropped into
-- G.GAME.balacraft.last_drop, then calls PB_UTIL.show_cashout_resource_rows() below. The
-- round-eval UIBox (G.round_eval) is created BEFORE G.FUNCS.evaluate_round runs
-- (game.lua:3508 -> 3523), and evaluate_round queues blind:defeat() as an event
-- (state_events.lua:998) -- so G.round_eval exists AND last_drop is fully populated by the time
-- we run here. Hence no evaluate_round wrap and no fixed-delay guessing: we just append rows to
-- the static 'bonus_round_eval' container (UI_definitions.lua:1765).

-- Defensive cap. Real drops produce 1-2 resource types; this keeps a pathological multi-resource
-- grant from overflowing the round-eval box (vanilla caps the whole screen at 7 rows).
local MAX_ROWS = 4

-- The dotted divider separating the base blind row from the bonus rows. add_round_eval_row adds
-- it for the first non-blind1 vanilla row and guards on G.round_eval.divider_added; we add it the
-- same way (and set the same flag) so our rows are separated even on a blind with no
-- Hands/Discards/Interest rows. Setting the flag synchronously means exactly one divider is added
-- regardless of whether our code or vanilla's runs first.
local function ensure_divider()
    if G.round_eval.divider_added then return end
    local width = G.round_eval.T.w - 0.51
    G.E_MANAGER:add_event(Event({
        trigger = 'after', delay = 0.25,
        func = function()
            local spacer = {n = G.UIT.R, config = {align = "cm", minw = width}, nodes = {
                {n = G.UIT.O, config = {object = DynaText({
                    string = {'......................................'}, colours = {G.C.WHITE},
                    shadow = true, float = true, y_offset = -30, scale = 0.45, spacing = 13.5,
                    font = G.LANGUAGES['en-us'].font, pop_in = 0})}}
            }}
            if G.round_eval and G.round_eval:get_UIE_by_ID('bonus_round_eval') then
                G.round_eval:add_child(spacer, G.round_eval:get_UIE_by_ID('bonus_round_eval'))
            end
            return true
        end
    }))
    G.round_eval.divider_added = true
end

-- Build + queue one bonus row for `amount` of resource `res` (a PB_UTIL.RESOURCES entry).
-- Layout mirrors a vanilla bonus row: left column (~55%, left-aligned) = colored count +
-- "<Name> gathered"; right column (~45%, right-aligned) = the resource's 34x34 icon sprite.
local function queue_resource_row(res, amount, pitch)
    G.E_MANAGER:add_event(Event({
        trigger = 'after', delay = 0.22,
        func = function()
            if not (G.round_eval and G.round_eval:get_UIE_by_ID('bonus_round_eval')) then
                return true
            end
            local width = G.round_eval.T.w - 0.51
            local scale = 0.9
            local atlas = G.ASSET_ATLAS[PB_UTIL.icon_atlas.key]
            local spr = Sprite(0, 0, 0.5, 0.5, atlas, res.pos)

            local left_text = {
                {n = G.UIT.T, config = {text = tostring(amount), scale = 0.8 * scale,
                    colour = G.C.GREEN, shadow = true, juice = true}},
                {n = G.UIT.O, config = {object = DynaText({string = {" " .. res.name .. " gathered"},
                    colours = {G.C.UI.TEXT_LIGHT}, shadow = true, pop_in = 0,
                    scale = 0.4 * scale, silent = true})}},
            }
            local full_row = {n = G.UIT.R, config = {align = "cm", minw = 5}, nodes = {
                {n = G.UIT.C, config = {padding = 0.05, minw = width * 0.55, minh = 0.61,
                    align = "cl"}, nodes = left_text},
                {n = G.UIT.C, config = {padding = 0.05, minw = width * 0.45, align = "cr"}, nodes = {
                    {n = G.UIT.O, config = {w = 0.5, h = 0.5, object = spr, can_collide = false}},
                }}
            }}
            G.round_eval:add_child(full_row, G.round_eval:get_UIE_by_ID('bonus_round_eval'))
            spr:juice_up(0.3, 0.2)
            play_sound('highlight1', pitch or 1, 0.4)
            return true
        end
    }))
end

-- One muted "N lost (inventory full)" row, queued like a resource row, when capacity swallowed
-- part of the drop. Drawn in red with no icon so it reads as a warning, not a reward.
local function queue_lost_row(amount, pitch)
    G.E_MANAGER:add_event(Event({
        trigger = 'after', delay = 0.22,
        func = function()
            if not (G.round_eval and G.round_eval:get_UIE_by_ID('bonus_round_eval')) then
                return true
            end
            local width = G.round_eval.T.w - 0.51
            local full_row = {n = G.UIT.R, config = {align = "cm", minw = 5}, nodes = {
                {n = G.UIT.C, config = {padding = 0.05, minw = width, minh = 0.61, align = "cm"}, nodes = {
                    {n = G.UIT.T, config = {text = tostring(amount), scale = 0.72, colour = G.C.RED,
                        shadow = true}},
                    {n = G.UIT.O, config = {object = DynaText({string = {" lost (inventory full)"},
                        colours = {G.C.UI.TEXT_INACTIVE}, shadow = true, pop_in = 0, scale = 0.36,
                        silent = true})}},
                }},
            }}
            G.round_eval:add_child(full_row, G.round_eval:get_UIE_by_ID('bonus_round_eval'))
            play_sound('cancel', pitch or 1, 0.4)
            return true
        end
    }))
end

-- Public entry point, called from grant_blind_drop after it records the drop.
function PB_UTIL.show_cashout_resource_rows()
    if G.STATE ~= G.STATES.ROUND_EVAL then return end
    if not G.round_eval then return end
    local bc = G.GAME and G.GAME.balacraft
    local drop = bc and bc.last_drop
    local lost = (bc and bc.last_drop_lost) or 0
    if not ((drop and #drop > 0) or lost > 0) then return end

    -- Honor vanilla's round-eval row budget. The base game caps the screen at 7 rows via the
    -- global total_cashout_rows (functions/common_events.lua, incremented in add_round_eval_row).
    -- Our rows bypass that function, so respect the same budget here -- and increment the global
    -- as we add rows so the count stays accurate. By now evaluate_round has added all vanilla
    -- rows synchronously, so total_cashout_rows is the full vanilla count.
    local budget = 7 - (total_cashout_rows or 0)
    if budget <= 0 then return end
    if budget > MAX_ROWS then budget = MAX_ROWS end

    ensure_divider()
    local pitch = 1.1
    local shown = 0
    for _, e in ipairs(drop or {}) do
        if shown >= budget then break end
        local res = e.id and PB_UTIL.RESOURCE_BY_ID[e.id]
        if res and e.amount and e.amount > 0 then
            shown = shown + 1
            total_cashout_rows = (total_cashout_rows or 0) + 1
            queue_resource_row(res, e.amount, pitch)
            pitch = pitch + 0.06
        end
    end
    -- A single warning row if capacity swallowed any of the drop (reserve one row from the budget).
    if lost > 0 and shown < budget then
        total_cashout_rows = (total_cashout_rows or 0) + 1
        queue_lost_row(lost, pitch)
    end
end
