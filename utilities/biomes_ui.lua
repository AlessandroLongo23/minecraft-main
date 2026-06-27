-- Biome-selection screen: a TRANSPARENT play-area UIBox (G.balacraft_biome_select), shown like
-- the blind-select screen -- the felt, left panel and background shader all stay visible. The
-- trigger + shop-hold live in utilities/biomes.lua (cash_out sets a pending flag; update_shop
-- holds the shop build and shows this screen until a biome is chosen, so the shop then slides
-- in fresh). Offers three biomes from the current dimension as tall "poster" cards.
--
-- Card layout (mirrors the base game's blind-choice card, functions/UI_definitions.lua):
--   [ title plate ]  ->  [ full-art sprite (dark gradient baked into its lower half) ]
--   ->  [ dark description panel ]  ->  [ Select button ]
-- Art is the placeholder atlas from assets/gen_biomes.py (a real-art pass is a later task).

-- The full-art sprite for a biome card, or nil if the atlas isn't loaded yet (caller falls
-- back to a solid colour block so it never crashes).
local CARD_W, CARD_H = 2.3, 3.55   -- UI units; ~the 90x150 art aspect, sized like blind cards

local function biome_art_sprite(b)
    local atlas = PB_UTIL.biome_card_atlas and G.ASSET_ATLAS[PB_UTIL.biome_card_atlas.key]
    if not atlas or not b.pos then return nil end
    return SMODS.create_sprite(0, 0, CARD_W, CARD_H, atlas, b.pos)
end

local function biome_card_node(id)
    local b = PB_UTIL.get_biome(id)
    if not b then return nil end

    local art = biome_art_sprite(b)
    local art_node = art
        and { n = G.UIT.O, config = { object = art } }
        or  { n = G.UIT.R, config = { minw = CARD_W, minh = CARD_H, r = 0.1, colour = b.colour }, nodes = {} }

    -- Description lines sit directly on the card frame (which is itself a dark panel), so no
    -- separate dark text background is needed.
    local desc_rows = {}
    for _, line in ipairs(b.desc or {}) do
        desc_rows[#desc_rows + 1] = { n = G.UIT.R, config = { align = 'cm', maxw = CARD_W + 0.1 }, nodes = {
            { n = G.UIT.T, config = { text = line, scale = 0.28, colour = G.C.WHITE, shadow = true } },
        } }
    end

    -- Each option is a framed card: a dark rounded panel with a biome-coloured outline,
    -- mirroring the base game's blind-choice card (functions/UI_definitions.lua).
    return {
        n = G.UIT.C, config = { align = 'cm', padding = 0.08 }, nodes = {
            { n = G.UIT.C, config = {
                align = 'tm', padding = 0.12, r = 0.12,
                colour = mix_colours(G.C.BLACK, G.C.L_BLACK, 0.5),
                outline = 1, outline_colour = b.colour, emboss = 0.1,
                minw = CARD_W + 0.5,
            }, nodes = {
                -- Name plate.
                { n = G.UIT.R, config = { align = 'cm', r = 0.1, colour = darken(b.colour, 0.2),
                    outline = 1, outline_colour = b.colour, minw = CARD_W + 0.2, padding = 0.07, emboss = 0.05 }, nodes = {
                    { n = G.UIT.T, config = { text = b.name, scale = 0.5, colour = G.C.WHITE, shadow = true } },
                } },
                -- Full-art sprite.
                { n = G.UIT.R, config = { align = 'cm', padding = 0.06 }, nodes = { art_node } },
                -- Description (on the frame's dark panel).
                { n = G.UIT.R, config = { align = 'cm', padding = 0.02 }, nodes = {
                    { n = G.UIT.C, config = { align = 'cm' }, nodes = desc_rows },
                } },
                -- Select button (classic Balatro orange, commits on press).
                { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
                    { n = G.UIT.R, config = { align = 'cm', minw = CARD_W, minh = 0.55, r = 0.1,
                        colour = G.C.ORANGE, button = 'bc_select_biome', ref_table = { biome = id },
                        hover = true, shadow = true, one_press = true }, nodes = {
                        { n = G.UIT.T, config = { text = 'Select', scale = 0.45, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
                    } },
                } },
            } },
        },
    }
end

function PB_UTIL.build_biome_select(choices)
    local card_row = { n = G.UIT.R, config = { align = 'cm', padding = 0.15 }, nodes = {} }
    for _, id in ipairs(choices) do
        local node = biome_card_node(id)
        if node then card_row.nodes[#card_row.nodes + 1] = node end
    end

    -- TRANSPARENT root (G.C.CLEAR) like the blind-select screen: the felt, left panel and
    -- background shader all stay visible -- only the prompt + cards are drawn.
    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', colour = G.C.CLEAR, padding = 0.1 },
        nodes = {
            { n = G.UIT.R, config = { align = 'cm', padding = 0.08 }, nodes = {
                { n = G.UIT.O, config = { object = DynaText({ string = 'Choose your next Biome',
                    colours = { G.C.WHITE }, shadow = true, bump = true, scale = 0.7, pop_in = 0.3, maxw = 9 }) } },
            } },
            { n = G.UIT.R, config = { align = 'cm', minh = 0.15 }, nodes = {} },
            card_row,
        },
    }
end

-- Show the selection as a transparent play-area UIBox (NOT an overlay): the three biome
-- cards float over the felt, like blind select. Returns false if there's nothing to offer.
function PB_UTIL.open_biome_select()
    if G.balacraft_biome_select then return true end
    -- The Explorer Tag grants one extra choice (4 instead of 3) at the next biome select.
    local extra = G.GAME and G.GAME.balacraft and G.GAME.balacraft._biome_extra
    local n = extra and 4 or 3
    if extra and G.GAME and G.GAME.balacraft then G.GAME.balacraft._biome_extra = nil end
    local choices = PB_UTIL.roll_biome_choices(PB_UTIL.current_dimension(), n, PB_UTIL.current_biome())
    if not choices or #choices == 0 then return false end
    PB_UTIL._biome_choices = choices
    -- Position exactly like the blind-select screen: anchored to G.hand (so it's centered in
    -- the PLAYFIELD, not the whole screen -> equal left/right margins), tucked into the
    -- jokers->hand gap so the prompt sits below the joker row instead of overlapping it.
    G.balacraft_biome_select = UIBox {
        definition = PB_UTIL.build_biome_select(choices),
        config = { align = 'bmi', offset = { x = 0, y = G.ROOM.T.y + 29 }, major = G.hand, bond = 'Weak' },
    }
    G.balacraft_biome_select.alignment.offset.y =
        0.8 - (G.hand.T.y - G.jokers.T.y) + G.balacraft_biome_select.T.h
    G.balacraft_biome_select.alignment.offset.x = 0
    if G.CONTROLLER then G.CONTROLLER.lock_input = false end   -- allow clicking the cards
    return true
end

function PB_UTIL.close_biome_select()
    if G.balacraft_biome_select then
        G.balacraft_biome_select:remove()
        G.balacraft_biome_select = nil
    end
end

-- Click handler: theme the next ante, close the panel, and clear the pending flag so the
-- shop-hold (update_shop wrap in utilities/biomes.lua) releases and the shop slides in.
G.FUNCS.bc_select_biome = function(e)
    local id = e and e.config and e.config.ref_table and e.config.ref_table.biome
    if not id then return end
    PB_UTIL.set_biome(id)
    pcall(play_sound, 'card1', 1, 0.7)
    PB_UTIL.close_biome_select()
    if G.GAME and G.GAME.balacraft then G.GAME.balacraft._biome_pending = nil end
end
