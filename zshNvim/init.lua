require("config.options")

local enable_config = require("config.global_functions").FileNotTooBig()
if enable_config then
  require("config.lazy")

  require("config.autocmds")
  require("config.keymaps")
  require("config.functions")

  -- Todo: install
  -- lualine,  --> DONE
  -- conform, --> DONE
  -- nvim-lint, --> DONE
  -- fix hcl tfvars
  -- telescope root dir if .git available else do current dir
end
