require("config.options")

-- local enable_config = require("config.global_functions").FileNotTooBig()
require("config.lazy")
-- require("config.autocmds")
require("config.keymaps")
-- require("config.functions")
require("config.coloscheme")

-- Change highlight color for plugin GitSigns
vim.cmd("highlight GitSignsChange guifg=#ff9e64 guibg=NONE")
