-- function joker_add(jKey)
--     if type(jKey) == 'string' then
--         local j = SMODS.create_card({
--             key = jKey,
--         })

--         j:add_to_deck()
--         G.jokers:emplace(j)

--         -- SMODS.Stickers["eternal"]:apply(j, true)
--     end
-- end

-- SMODS.Atlas {
--     key = "depaJoker",
--     path = "Depa.png",
--     px = 71,
--     py = 95
-- }

-- SMODS.Joker {
-- 	key = "depaJoker",
-- 	prefix_config = { key = true },
-- 	loc_txt = {
-- 		name = "Depa",
-- 		text = {
-- 			"A simple Joker with no special abilities."
-- 		}
-- 	},
	
-- 	unlocked = true,
-- 	discovered = true,

-- 	blueprint_compat = false,
-- 	brainstorm_compat = false,
-- 	eternal_compat = true,
-- 	perishable_compat = true,
	
-- 	rarity = 1,
-- 	atlas = "depaJoker",
-- 	pos = { x = 0, y = 0 },
-- 	cost = 4,
-- 	value = 8,
	
-- 	pools = {
-- 		Common = true,
-- 		Shop = true,
-- 		Event = true,
-- 		Rare = false,
-- 		Legendary = false,
-- 		Buffoon = false
-- 	},


-- 	calculate = function(self, card, context)
-- 		-- This joker has no special abilities
-- 	end
-- }

-- SMODS.Atlas{
--     key = 'overworldDeck',
--     path = 'DepaDeck.png',
--     px = 71,
--     py = 95
-- }

-- SMODS.Back{
--     name = 'Overworld',
--     key = 'overworldDeck',
--     atlas = 'overworldDeck',
--     pos = {x = 0, y = 0},
--     loc_txt = {
--         name = 'Overworld Deck',
--         text = {
--             'Start with a',
--             '{C:red}Depa Joker{}.'
--         },
--     },

--     apply = function ()
--         G.E_MANAGER:add_event(Event({
--             func = function ()
--                 -- Add eternal Depa Joker
--                 joker_add('j_minecraft_depaJoker')

--                 return true
--             end
--         }))
--     end,
-- }

SMODS.Atlas(
    {
        key = 'blinds', 
        path = 'blinds.png', 
        px = 34, 
        py = 34, 
        frames = 21, 
        atlas_table = 'ANIMATION_ATLAS'
    }
)

local ENABLED_BLINDS = {
    'skeleton',
    'zombie',
    'creeper',
    'enderman',
    'spider',
}

sendDebugMessage("Loading Blinds...", 'Minecraft')
for i = 1, #ENABLED_BLINDS do
    local status, err = pcall(function()
        return NFS.load(SMODS.current_mod.path .. 'items/blinds/' .. ENABLED_BLINDS[i] .. '.lua')()
    end)
    sendDebugMessage("Loaded blind: " .. ENABLED_BLINDS[i], 'Minecraft')

    if not status then
        error(ENABLED_BLINDS[i] .. ": " .. err)
    end
end
sendDebugMessage("", 'Minecraft')
