-- stylua: ignore
return {
  "neovim/nvim-lspconfig",
  ---@class PluginLspOpts
  opts = {
    ---@type lspconfig.options
    servers = {
      bashls = {},
      dockerls = {}, -- docker
      jsonls = {}, -- json
      gopls = {}, -- golang
      golangci_lint_ls = {}, -- golangci
      pyright = {},
      tflint = {}, -- terraform docs
      terraformls = {}, -- terraform
    },
  },
}
