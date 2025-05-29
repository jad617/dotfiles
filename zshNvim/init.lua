require("config.options")

-- local enable_config = require("config.global_functions").FileNotTooBig()
-- if enable_config then
require("config.lazy")
require("config.autocmds")
require("config.keymaps")
require("config.functions")
require("config.colorscheme")
-- end
