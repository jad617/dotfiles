require("config.options")

local enable_config = require("config.global_functions").FileNotTooBig()
if enable_config then
  require("config.lazy")
  require("config.autocmds")
  require("config.keymaps")
  require("config.functions")
  require("config.colorscheme")
end

-- Change highlight color for plugin GitSigns
vim.cmd("highlight GitSignsChange guifg=#ff9e64 guibg=NONE")
vim.cmd("highlight GitSignsAdd guifg=#9ECE6A guibg=NONE")
