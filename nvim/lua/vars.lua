M = {}

M.lsp = {
  "bashls",               -- bash
  "dockerls",             -- docker
  "jsonls",               -- json
  "gopls",                -- golang
  "golangci_lint_ls",     -- golangci
  "groovyls",             -- groovy
  "pyright",              -- python
  "solargraph",           -- ruby
  "sumneko_lua",          -- lua
  "terraformls",          -- terraform
  "tflint",               -- terraform docs
  "tsserver",             -- javascript
}

M.linter = {
  "flake8",
  "golangci-lint",
  "jsonlint",
  "markdownlint",
  "pylint",
  "shellcheck",
  "staticcheck",
  "tflint",
  "yamllint"
}

return M
