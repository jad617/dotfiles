-- Disable LazyVim default autocmd:
-- package.loaded["lazyvim.config.options"] = true
-- package.loaded["lazyvim.config.autocmd"] = true

-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

require("config.plugins.onedark")
require("onedark").load()

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
require("config.plugins.vimux")
-- require("config.plugins.colorful-winseperator")
require("config.plugins.fterm")
