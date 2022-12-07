local lsp_servers = require("vars").lsp

require("mason").setup({
  ui = {
    icons = {
      package_installed = "✓",
      package_pending = "➜",
      package_uninstalled = "✗"
    }
  }
})

require("mason-lspconfig").setup({
  -- ensure_installed = { "sumneko_lua", "golangci_lint_ls", "gopls", "bashls", "jsonls" },
  ensure_installed = lsp_servers,
  automatic_installation = true,
})
