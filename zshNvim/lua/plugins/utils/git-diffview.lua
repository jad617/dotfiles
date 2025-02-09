return {
  "sindrets/diffview.nvim",
  config = function()
    ------------------------------------------------------------
    -- [[ local vars ]]
    ------------------------------------------------------------
    local map = vim.api.nvim_set_keymap -- set keys
    local options_silent = { noremap = true, silent = true }

    ------------------------------------------------------------
    -- [[ Key Bindings ]]
    ------------------------------------------------------------
    map("n", "<leader>gm", "<cmd>DiffviewOpen<CR>", options_silent)
  end,
}
