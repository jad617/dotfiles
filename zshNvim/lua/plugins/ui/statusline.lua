-- Statusline, is used for tabline feature only
  
-- return {}
return {
  "beauwilliams/statusline.lua",
  config = function()
    local statusline = require("statusline")
    statusline.lsp_diagnostics = false
  end
}
