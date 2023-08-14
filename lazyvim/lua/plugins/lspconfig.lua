return {
  "neovim/nvim-lspconfig",
  ---@class PluginLspOpts
  opts = {
    ---@type lspconfig.options
    servers = {
      pyright = {},
      bashls = {},
      dockerls = {}, -- docker
      jsonls = {}, -- json
      gopls = {}, -- golang
      golangci_lint_ls = {}, -- golangci
      tflint = {}, -- terraform docs
      terraformls = {}, -- terraform
    },
  },
}
