local b = require("null-ls").builtins

require("null-ls").setup({
    debug = true,
    sources = {
      -- Lua
      b.formatting.stylua,
      -- b.completion.spell,

      -- Golang
      b.formatting.gofumpt,
      b.formatting.goimports,
      b.formatting.goimports_reviser,
      b.diagnostics.golangci_lint,

      -- Markdown
      b.formatting.markdownlint,
      b.diagnostics.markdownlint,

      -- Terraform
      b.formatting.terraform_fmt,

      -- Yaml
      b.formatting.yamlfmt,
      b.diagnostics.yamllint
    },
})
