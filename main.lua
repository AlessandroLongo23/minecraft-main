PB_UTIL = {}
PB_UTIL.config = SMODS.current_mod.config

SMODS.load_file("utilities/definitions.lua")()
SMODS.load_file("utilities/functions.lua")()
SMODS.load_file("utilities/ui.lua")()

if PB_UTIL.config.blinds_enabled then
    PB_UTIL.load_blinds(PB_UTIL.ENABLED_BLINDS)
end

if PB_UTIL.config.boosters_enabled then
    PB_UTIL.register_items(PB_UTIL.ENABLED_BOOSTERS, "boosters")
end

if PB_UTIL.config.decks_enabled then
    PB_UTIL.register_items(PB_UTIL.ENABLED_DECKS, "decks")
end

if PB_UTIL.config.enhancements_enabled then
    PB_UTIL.register_items(PB_UTIL.ENABLED_ENHANCEMENTS, "enhancements")
end

if PB_UTIL.config.jokers_enabled then
    PB_UTIL.register_items(PB_UTIL.ENABLED_JOKERS, "jokers")
end

if PB_UTIL.config.tags_enabled then
    PB_UTIL.register_items(PB_UTIL.ENABLED_TAGS, "tags")
end

if PB_UTIL.config.vouchers_enabled then
    PB_UTIL.register_items(PB_UTIL.ENABLED_VOUCHERS, "vouchers")
end