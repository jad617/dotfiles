if vim.env.PROF then
  -- example for lazy.nvim
  -- change this to the correct path for your plugin manager
  local snacks = vim.fn.stdpath("data") .. "/lazy/snacks.nvim"
  vim.opt.rtp:append(snacks)
  require("snacks.profiler").startup({
    startup = {
      event = "VimEnter", -- stop profiler on this event. Defaults to `VimEnter`
      -- event = "UIEnter",
      -- event = "VeryLazy",
    },
  })
end

require("config.options")

-- local enable_config = require("config.global_functions").FileNotTooBig()
-- if enable_config then
require("config.lazy")
require("config.autocmds")
require("config.keymaps")
require("config.functions")
require("config.colorscheme")
-- end
