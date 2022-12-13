M = {}

M.lsp = {
  bashls = {},
  dockerls = {},             -- docker
  jsonls = {},               -- json
  gopls = {},                -- golang
  golangci_lint_ls = {},     -- golangci
  groovyls = {},             -- groovy
  pyright = {},              -- python
  solargraph = {},           -- ruby
  sumneko_lua = {            -- lua
    settings = {
      Lua = {
        diagnostics = {
          globals = {'vim'},  -- removes warning: 'Global vim is undefined'
        }
      }
    }
  },
  tflint = {},               -- terraform docs
  tsserver = {},             -- javascript
  terraformls = {},          -- terraform
}

M.linter = {
  formatting = {
    "stylua",
    "gofumpt",
    "goimports",
    "goimports-reviser",
    "markdownlint",
    "rubocop",
    -- "terraform-fmt",
    "yamlfmt"
  },
  diagnostics = {
    "flake8",
    "golangci-lint",
    "jsonlint",
    "markdownlint",
    "pylint",
    "rubocop",
    "shellcheck",
    "staticcheck",
    "tflint",
    "yamllint"
  },
}

return M
