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
  "flake8",
  "golangci-lint",
  "gofumpt",
  "goimports",
  "goimports_reviser",
  "jsonlint",
  "markdownlint",
  "pylint",
  "shellcheck",
  "staticcheck",
  "rubocop",
  "tflint",
  "yamllint"
}

return M
