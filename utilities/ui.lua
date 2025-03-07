SMODS.current_mod.config_tab = function()
  return {
    n = G.UIT.ROOT,
    config = { align = 'cm', padding = 0.05, emboss = 0.05, r = 0.1, colour = G.C.BLACK },
    nodes = {
      {
        n = G.UIT.R,
        config = { align = 'cm', minh = 1 },
        nodes = {
          { n = G.UIT.T, config = { text = "Minecraft", colour = G.C.RED, scale = 0.5 } }
        }
      },
      {
        n = G.UIT.R,
        nodes = {
          {
            n = G.UIT.C,
            nodes = {
              create_toggle {
                label = "Tags",
                ref_table = PB_UTIL.config,
                ref_value = 'tags_enabled'
              },
              create_toggle {
                label = "Jokers",
                ref_table = PB_UTIL.config,
                ref_value = 'jokers_enabled',
              },
              create_toggle {
                label = "Vouchers",
                ref_table = PB_UTIL.config,
                ref_value = 'vouchers_enabled'
              },
              create_toggle {
                label = "Decks",
                ref_table = PB_UTIL.config,
                ref_value = 'decks_enabled',
              },
            }
          },
          {
            n = G.UIT.C,
            nodes = {
              create_toggle {
                label = "Enhancements",
                ref_table = PB_UTIL.config,
                ref_value = 'enhancements_enabled',
              },
              create_toggle {
                label = "Blinds",
                ref_table = PB_UTIL.config,
                ref_value = 'blinds_enabled',
              },
              create_toggle {
                label = "Boosters",
                ref_table = PB_UTIL.config,
                ref_value = 'boosters_enabled',
              },
            }
          }
        }
      }
    }
  }
end

SMODS.current_mod.extra_tabs = function()
  local credits_tab = {
    n = G.UIT.ROOT,
    config = { align = 'tl', padding = 0.05, emboss = 0.05, r = 0.1, colour = G.C.BLACK },
    nodes = { {
      n = G.UIT.R,
      nodes = {
        {
          n = G.UIT.C,
          config = { padding = 0.5 },
          nodes = {
            {
              n = G.UIT.R,
              nodes = {
                { n = G.UIT.T, config = { text = "Artists", colour = G.C.CHIPS, scale = 0.75 } },
              }
            },
            {
              n = G.UIT.R,
              config = { align = 'cm', minh = 0.25 },
              nodes = {
                { n = G.UIT.T, config = { text = 'Lohengrin', colour = G.C.MULT, scale = 0.4 } }
              }
            },
          }
        },
        {
          n = G.UIT.C,
          config = { padding = 0.5 },
          nodes = {
            {
              n = G.UIT.R,
              nodes = {
                { n = G.UIT.T, config = { text = "Developers", colour = G.C.CHIPS, scale = 0.75 } },
              }
            },
            {
              n = G.UIT.R,
              config = { align = 'cm', minh = 0.25 },
              nodes = {
                { n = G.UIT.T, config = { text = 'Falesteo', colour = G.C.GREEN, scale = 0.4 } }
              }
            },
          }
        },
      }
    } 
  }
  }

  return {
    {
      label = "Credits",
      tab_definition_function = function()
        return credits_tab
      end
    }
  }
end