return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope-project.nvim",
  },

  config = function()
    require("telescope").setup({
      defaults = {
        layout_strategy = "horizontal",
        layout_config = { prompt_position = "top" },
        sorting_strategy = "ascending",
        winblend = 0,
      },
    })

    -- [[ Extentions ]]
    -- Project viewer
    require("telescope").load_extension("project")
    ------------------------------------------------------------
    -- [[ local vars ]]
    ------------------------------------------------------------
    local map = vim.api.nvim_set_keymap -- set keys
    local builtin = require("telescope.builtin")
    local options_silent = { noremap = true, silent = true }

    ------------------------------------------------------------
    -- [[ Key Bindings ]]
    ------------------------------------------------------------
    vim.keymap.set("n", "ff", builtin.find_files, {})
    vim.keymap.set("n", "<C-f>", builtin.find_files, {})
    vim.keymap.set("n", "fg", builtin.live_grep, {})
    -- vim.keymap.set("n", "<C-g>", builtin.live_grep, {})
    vim.keymap.set("n", "fb", builtin.buffers, {})
    vim.keymap.set("n", "<leader>fb", builtin.buffers, {})
    vim.keymap.set("n", "fh", builtin.help_tags, {})

    map("n", "gv", '<cmd>lua require"telescope.builtin".lsp_definitions({jump_type="vsplit"})<CR>', options_silent)

    map("n", "gt", '<cmd>lua require"telescope.builtin".lsp_definitions({jump_type="tab"})<CR>', options_silent)

    map(
      "n",
      "gl",
      '<cmd>lua vim.diagnostic.open_float(0, {scope="b", max_width=120})<CR>',
      { noremap = true, silent = true }
    )

    -- map("n", "<A-n>", ":Telescope buffers<cr>", { noremap = true, silent = false })

    map(
      "n",
      "<leader>g",
      ":execute 'Telescope live_grep default_text=' . expand('<cword>')<cr>",
      { noremap = true, silent = true }
    )
    map("n", "<C-l>", ":lua require'telescope'.extensions.project.project{}<CR>", { noremap = true, silent = true })
  end,
}
