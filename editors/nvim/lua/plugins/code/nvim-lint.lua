return {
  "mfussenegger/nvim-lint",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    local lint = require("lint")

    lint.linters_by_ft = {
      ansible = { "yamllint" }, -- ansiblels runs ansible-lint internally
      go = { "golangci-lint" },
      -- terraform: tflint runs as LSP (tflint --langserver), no need to duplicate here
      dockerfile = { "hadolint" },
      sh = { "shellcheck" },
      bash = { "shellcheck" },
      yaml = { "yamllint" },
      text = { "proselint" },
      markdown = { "proselint" },
      -- python: diagnostics handled by ruff LSP
    }

    local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })

    vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
      group = lint_augroup,
      callback = function()
        lint.try_lint()
      end,
    })
  end,
}
