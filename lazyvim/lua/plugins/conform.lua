return {
  "stevearc/conform.nvim",
  opts = {
    formatters_by_ft = {
      -- All filetypes
      -- ["*"] = { "trim_newlines", "trim_whitespace" },

      -- All filetypes that do not have a formatter
      -- ["_"] = { "trim_newlines", "trim_whitespace" },

      -- yaml
      dockerfile = { "trim_newlines", "trim_whitespace" },
      helm = { "trim_newlines", "trim_whitespace" },
      yaml = { "trim_newlines", "trim_whitespace" },

      -- golang does not work well with gopls lsp
      -- go = { "goimports", "gofumpt" },
      -- go = { "goimports-reviser" },

      -- json
      json = { "jq", "trim_newlines", "trim_whitespace" },

      -- markdown
      markdown = { "markdownlint", "trim_newlines", "trim_whitespace" },

      -- python
      python = { "isort", "black", "trim_newlines", "trim_whitespace" },

      -- terraform
      hcl = { "terraform_fmt", "trim_newlines", "trim_whitespace" },
      terraform = { "terraform_fmt", "trim_newlines", "trim_whitespace" },
    },

    format = {
      -- If set to true, causes an issue with LSP gopls
      lsp_fallback = false,
    },
  },
}
