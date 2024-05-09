M = {}

M.linter = {
  formatting = {
    "gofumpt",
    "goimports",
    -- "goimports-reviser",
    "markdownlint",
    "black",
    "isort",
    "shfmt",
  },
  diagnostics = {
    "ansible-lint",
    "golangci-lint",
    "pylint",
    "tflint",
  },
}

return M
