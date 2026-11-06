return {
  "williamboman/mason.nvim",
  cond = vim.fn.filereadable("/etc/NIXOS") == 0, -- disabled on NixOS (nixpkgs provides all tools)
  dependencies = {
    "williamboman/mason-lspconfig.nvim",
    "neovim/nvim-lspconfig",
    "WhoIsSethDaniel/mason-tool-installer.nvim",
  },

  config = function()
    local mason = require("mason")
    mason.setup({})

    local mason_lspconfig = require("mason-lspconfig")
    local lsp = require("config.vars").lsp
    LSP_LIST = {}
    for key, _ in pairs(lsp) do
      table.insert(LSP_LIST, key)
    end
    -- NVIM_NO_AUTO_INSTALL=1 (used by CI) skips downloading servers and tools
    local auto_install = vim.env.NVIM_NO_AUTO_INSTALL == nil
    mason_lspconfig.setup({ ensure_installed = auto_install and LSP_LIST or {} })

    local mason_tool_installer = require("mason-tool-installer")
    local linters = require("config.vars").linter
    LINTER_FORMATER_LIST = {}
    for _, linter in ipairs(linters) do
      table.insert(LINTER_FORMATER_LIST, linter)
    end
    mason_tool_installer.setup({ ensure_installed = auto_install and LINTER_FORMATER_LIST or {} })
  end,
}
