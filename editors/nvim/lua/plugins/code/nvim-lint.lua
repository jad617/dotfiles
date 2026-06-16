return {
  "mfussenegger/nvim-lint",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    local lint = require("lint")

    lint.linters_by_ft = {
      ansible = { "yamllint" }, -- ansiblels runs ansible-lint internally
      go = { "golangcilint" },
      -- terraform: tflint runs as LSP (tflint --langserver), no need to duplicate here
      dockerfile = { "hadolint" },
      sh = { "shellcheck" },
      bash = { "shellcheck" },
      yaml = { "yamllint" },
      text = { "proselint" },
      markdown = { "markdownlint", "proselint" },
      -- python: diagnostics handled by ruff LSP
    }

    -- Point each linter at the Mason-managed binary so nvim-lint can always
    -- find them regardless of the shell PATH Neovim was launched with.
    -- Some linters are defined as functions in nvim-lint, so we wrap those.
    local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/"
    local mason_linters = {
      ["golangcilint"] = "golangci-lint", -- nvim-lint key → Mason binary name
      ["hadolint"]     = "hadolint",
      ["shellcheck"]   = "shellcheck",
      ["yamllint"]     = "yamllint",
      ["markdownlint"] = "markdownlint",
      ["proselint"]    = "proselint",
    }
    for linter_key, bin_name in pairs(mason_linters) do
      local linter = lint.linters[linter_key]
      if linter then
        if type(linter) == "function" then
          lint.linters[linter_key] = function()
            local l = linter()
            l.cmd = mason_bin .. bin_name
            return l
          end
        else
          linter.cmd = mason_bin .. bin_name
        end
      end
    end

    -- Run golangci-lint from the directory containing go.mod/go.work so it
    -- can resolve module dependencies regardless of Neovim's cwd.
    local golangcilint_base = lint.linters["golangcilint"]
    lint.linters["golangcilint"] = function()
      local l = type(golangcilint_base) == "function" and golangcilint_base() or vim.deepcopy(golangcilint_base)
      l.cwd = vim.fs.root(vim.api.nvim_buf_get_name(0), { "go.mod", "go.work" }) or vim.fn.getcwd()
      return l
    end

    local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })

    vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
      group = lint_augroup,
      callback = function()
        -- Only lint real, on-disk files. Skip scratch/UI/terminal buffers
        -- (buftype ~= "") and unnamed buffers so heavyweight linters like
        -- proselint never run on throwaway markdown buffers (e.g. plugin
        -- preview floats), which otherwise pegs the CPU.
        if vim.bo.buftype ~= "" or vim.api.nvim_buf_get_name(0) == "" then return end

        -- pcall prevents hard crashes when a linter binary is missing or not yet installed.
        local ok, err = pcall(lint.try_lint)
        if not ok then
          vim.notify("nvim-lint: " .. err, vim.log.levels.WARN)
        end
      end,
    })
  end,
}
