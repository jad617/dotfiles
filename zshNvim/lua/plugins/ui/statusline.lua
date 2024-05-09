-- Statusline, is used for tabline feature only
return { 
  "beauwilliams/statusline.lua",
  config = function()
    local statusline = require("statusline")
    statusline.lsp_diagnostics = false
  end
}
