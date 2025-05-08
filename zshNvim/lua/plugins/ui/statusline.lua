-- Statusline, is used for tabline feature only

return {
  "beauwilliams/statusline.lua",
  config = function()
    require("statusline").setup({
      tabline = true,
      lsp_diagnostics = false,
    })
  end,
}
