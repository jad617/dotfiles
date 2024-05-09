return  {
  "williamboman/mason.nvim",
  dependencies = {
    "williamboman/mason-lspconfig.nvim",
    "neovim/nvim-lspconfig",
  },
  config = function()
    ------------------------------------------------------------
    -- [[ mason config ]]
    ------------------------------------------------------------
    local mason = require("mason")
    mason.setup({})

    ------------------------------------------------------------
    -- [[ mason-lsp config ]]
    ------------------------------------------------------------
    local mason_lspconfig = require("mason-lspconfig")
    local lsp = require("config.vars").lsp
    
    lsp_list = {}

    for key, _ in pairs(lsp) do
        table.insert(lsp_list, key)
    end
        
    mason_lspconfig.setup({
        ensure_installed =  lsp_list
    })
  end
}
