local lsp = require("vars").lsp

require("mason").setup({
  ui = {
    icons = {
      package_installed = "✓",
      package_pending = "➜",
      package_uninstalled = "✗"
    }
  }
})

-- Create list for ensure_installed
local lsp_servers = {}
local index_start = 0
for lsp_name, _ in pairs(lsp) do
  lsp_servers[index_start] = lsp_name
  index_start = index_start + 1
end

require("mason-lspconfig").setup({
  ensure_installed = lsp_servers,
  automatic_installation = true,
})
