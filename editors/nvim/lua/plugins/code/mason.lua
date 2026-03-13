return {
  "williamboman/mason.nvim",
  dependencies = {
    "williamboman/mason-lspconfig.nvim",
    "neovim/nvim-lspconfig",
    "WhoIsSethDaniel/mason-tool-installer.nvim",
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

    LSP_LIST = {}

    for key, _ in pairs(lsp) do
      table.insert(LSP_LIST, key)
    end

    mason_lspconfig.setup({
      ensure_installed = LSP_LIST,
    })

    ------------------------------------------------------------
    -- [[ mason-lsp config ]]
    ------------------------------------------------------------
    local mason_tool_installer = require("mason-tool-installer")
    local linters = require("config.vars").linter

    LINTER_FORMATER_LIST = {}

    for _, linter in ipairs(linters) do
      table.insert(LINTER_FORMATER_LIST, linter)
    end

    mason_tool_installer.setup({
      ensure_installed = LINTER_FORMATER_LIST,
    })
  end,
}
