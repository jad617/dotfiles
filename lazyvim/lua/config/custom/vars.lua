M = {}

M.lsp = {
  -- bashls = {},
  dockerls = {}, -- docker
  helm_ls = {},
  jsonls = {}, -- json
  gopls = {}, -- golang
  golangci_lint_ls = {}, -- golangci
  -- groovyls = {}, -- groovy
  pyright = {}, -- python
  -- solargraph = {}, -- ruby
  sumneko_lua = { -- lua
    settings = {
      Lua = {
        diagnostics = {
          globals = { "vim" }, -- removes warning: 'Global vim is undefined'
        },
      },
    },
  },
  tflint = {}, -- terraform docs
  tsserver = {}, -- javascript

  -- terraformls = {}, -- terraform
  yamlls = {},
}

M.linter = {
  formatting = {
    -- "stylua",
    "gofumpt",
    "goimports",
    "goimports-reviser",
    "markdownlint",
    -- "shfmt",
    "yamlfmt",
    "black",
    "isort",
    "hclfmt",
    "autopep8",
    "mypy",
    "prettierd",
  },
  diagnostics = {
    "flake8",
    "golangci-lint",
    "jsonlint",
    "markdownlint",
    "pylint",
    "shellcheck",
    "staticcheck",
    "tflint",
    "yamllint",
  },
}

return M
