M = {}

M.lsp = {
  bashls = {},
  dockerls = {}, -- docker
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

  terraformls = {}, -- terraform
}

M.linter = {
  formatting = {
    -- "stylua",
    "gofumpt",
    "goimports",
    "goimports-reviser",
    "markdownlint",
    -- "beautysh",
    -- "rubocop",
    -- "shellharden",       -- Requires Cargo
    "shfmt",
    -- "terraform-fmt",     -- Not found by Mason
    "yamlfmt",
    "black",
    "isort",
    "autopep8",
    "mypy",
  },
  diagnostics = {
    "flake8",
    "golangci-lint",
    "jsonlint",
    "markdownlint",
    "pylint",
    -- "rubocop",
    "shellcheck",
    "staticcheck",
    "tflint",
    "yamllint",
  },
}

return M
