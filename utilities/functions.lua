function joker_add(jKey)
    if type(jKey) == 'string' then
        local j = SMODS.create_card({
            key = jKey,
        })

        j:add_to_deck()
        G.jokers:emplace(j)
    end
end

function PB_UTIL.register_items(items, folder)
    for i = 1, #items do
        SMODS.load_file("content/" .. folder .. "/" .. items[i] .. ".lua")()
    end
end

function PB_UTIL.load_blinds(items)
    sendDebugMessage("Loading Blinds...", 'Minecraft')
    for i = 1, #items do
        local status, err = pcall(function()
            return NFS.load(SMODS.current_mod.path .. 'content/blinds/' .. items[i] .. '.lua')()
        end)
        sendDebugMessage("Loaded blind: " .. items[i], 'Minecraft')

        if not status then
            error(items[i] .. ": " .. err)
        end
    end
    sendDebugMessage("", 'Minecraft')

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
end