-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

-- require("onedark").setup() -- Lua

-- custom global configs
require("config.custom.commands")

-- custom plugins config
require("config.plugins.comfortable-motion")
require("config.plugins.nvim-tree")
require("config.plugins.statusline")
require("config.plugins.markdown-preview")
require("config.plugins.gitsigns")
require("config.plugins.inc-rename")
require("config.plugins.telescope")
