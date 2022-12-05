-- local lsp_servers = require("vars").lsp

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
  -- ensure_installed = { "sumneko_lua", "golangci_lint_ls", "gopls", "bashls", "jsonls", "gofumpt", "goimports", "gilangci-lint" },
  ensure_installed = { "sumneko_lua", "golangci_lint_ls", "gopls", "bashls", "jsonls" },
  -- ensure_installed = lsp
  automatic_installation = true,
})
