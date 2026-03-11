return {
  "stevearc/conform.nvim",
  opts = {
    formatters_by_ft = {
      -- All filetypes
      ["*"] = { "trim_newlines", "trim_whitespace" },

      -- All filetypes that do not have a formatter
      ["_"] = { "trim_newlines", "trim_whitespace" },

      -- yaml
      dockerfile = { "trim_newlines", "trim_whitespace" },
      helm = { "trim_newlines", "trim_whitespace" },
      kdl = { "trim_newlines", "trim_whitespace" },
      yaml = { "trim_newlines", "trim_whitespace" },

      -- go
      -- go = { "goimports", "goimports-reviser" },
      go = { "gopls_add_imports", "goimports-reviser" },

      -- json
      json = { "jq", "trim_newlines", "trim_whitespace" },

      -- lua
      lua = { "stylua" },

      -- markdown
      markdown = { "markdownlint", "trim_newlines", "trim_whitespace" },

      -- python
      python = { "isort", "black", "trim_newlines", "trim_whitespace" },

      -- terraform
      hcl = { "terraform_fmt", "trim_newlines", "trim_whitespace" },
      terraform = { "terraform_fmt", "trim_newlines", "trim_whitespace" },
    },
    format_on_save = {
      lsp_fallback = true,
      timeout_ms = 500,
    },
    formatters = {
      gopls_add_imports = {
        command = "gopls",
        args = { "check", "--only=source.add_imports", "-" },
        stdin = true,
      },
    },
  },
}
