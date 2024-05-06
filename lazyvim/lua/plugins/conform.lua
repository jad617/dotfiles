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
      -- helm = { "trim_newlines", "trim_whitespace" },
      -- yaml = { "yamlfmt" },

      -- golang
      go = { "goimports", "gofumpt" },

      -- json
      json = { "jq" },

      -- markdown
      markdown = { "markdownlint" },

      -- python
      python = { "isort", "black" },

      -- terraform
      hcl = { "terraform_fmt" },
      terraform = { "terraform_fmt" },
    },
  },
}
