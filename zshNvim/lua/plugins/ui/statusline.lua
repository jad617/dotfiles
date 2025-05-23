return {
  -- Statusline, is used for tabline feature only
  "beauwilliams/statusline.lua",
  config = function()
    require("statusline").setup({
      tabline = true,
      lsp_diagnostics = false,
    })
  end,
}
