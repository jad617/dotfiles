return {
  "stevearc/conform.nvim",
  event = "BufWritePre",
  opts = {
    formatters_by_ft = {
      -- All filetypes
      ["*"] = { "trim_newlines", "trim_whitespace" },

      -- All filetypes that do not have a formatter
      ["_"] = { "trim_newlines", "trim_whitespace" },

      -- yaml
      sh = { "shfmt" },
      bash = { "shfmt" },
      dockerfile = { "trim_newlines", "trim_whitespace" },
      helm = { "trim_newlines", "trim_whitespace" },
      kdl = { "trim_newlines", "trim_whitespace" },
      yaml = { "trim_newlines", "trim_whitespace" },

      -- go: gofmt on save (formats only, never removes imports)
      -- use <leader>gi to run goimports on demand
      go = { "gofmt" },

      -- json
      json = { "jq", "trim_newlines", "trim_whitespace" },

      -- lua
      lua = { "stylua" },

      -- markdown
      markdown = { "markdownlint", "trim_newlines", "trim_whitespace" },

      -- python
      python = { "ruff_format", "trim_newlines", "trim_whitespace" },

      -- terraform
      hcl = { "terraform_fmt", "trim_newlines", "trim_whitespace" },
      terraform = { "terraform_fmt", "trim_newlines", "trim_whitespace" },
    },
    format_on_save = function(bufnr)
      -- markdownlint (Node.js) needs more time to cold-start
      if vim.bo[bufnr].filetype == "markdown" then
        return { lsp_fallback = true, timeout_ms = 3000 }
      end
      return { lsp_fallback = true, timeout_ms = 500 }
    end,
    formatters = {},
  },
}
