local b = require("null-ls").builtins

require("null-ls").setup({
  debug = true,
  sources = {
    -- Bash
    b.formatting.beautysh,
    b.formatting.shfmt,
    -- b.diagnostics.shellcheck,

    -- Lua
    -- b.formatting.stylua,
    -- b.completion.spell,

    -- Golang
    b.formatting.gofumpt,
    b.formatting.goimports,
    b.formatting.goimports_reviser,
    b.diagnostics.golangci_lint,
    -- b.diagnostics.revive,

    -- Markdown
    b.formatting.markdownlint,
    b.diagnostics.markdownlint,

    -- Python
    b.formatting.black,
    b.formatting.isort,
    b.formatting.autopep8,
    -- b.diagnostics.mypy,
    -- b.diagnostics.flake8,

    -- Ruby
    -- b.formatting.rubocop,
    -- b.diagnostics.rubocop,

    -- Terraform
    b.formatting.terraform_fmt,

    -- Yaml
    -- b.formatting.yamlfmt,
    b.diagnostics.yamllint,
  },
})
