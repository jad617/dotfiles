return {
  "nvimtools/none-ls.nvim",
  opts = function(_, opts)
    if type(opts.sources) == "table" then
      local null_ls = require("null-ls")
      vim.list_extend(opts.sources, {
        -- html
        null_ls.builtins.formatting.prettierd,

        -- golang
        null_ls.builtins.code_actions.gomodifytags,
        null_ls.builtins.code_actions.impl,
        null_ls.builtins.formatting.gofumpt,
        null_ls.builtins.formatting.goimports_reviser,
        null_ls.builtins.formatting.goimports,

        -- Python
        null_ls.builtins.formatting.black,
        null_ls.builtins.formatting.isort,
        null_ls.builtins.formatting.autopep8,

        -- terraform
        null_ls.builtins.formatting.terraform_fmt,
        null_ls.builtins.diagnostics.terraform_validate,
      })
    end
  end,
}

-- `conform.nvim` and `nvim-lint` are now the default formatters and linters in LazyVim.
--
-- You can use those plugins together with `none-ls.nvim`,
-- but you need to enable the `lazyvim.plugins.extras.lsp.none-ls` extra,
-- for formatting to work correctly.
--
-- In case you no longer want to use `none-ls.nvim`, just remove the spec from your config.
