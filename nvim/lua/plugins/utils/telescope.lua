return {
  enabled = false,
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    -- "nvim-telescope/telescope-project.nvim",
  },

  config = function()
    require("telescope").setup({
      defaults = {
        layout_strategy = "horizontal",
        layout_config = { prompt_position = "top" },
        sorting_strategy = "ascending",
        winblend = 0,
      },

      -- fd command  + find hidden files
      pickers = {
        find_files = {
          find_command = {
            "fd",
            "--type",
            "f",
            "--color=never",
            "--hidden",
            "--follow",
            "-E",
            ".git/*",
            "-E",
            ".terraform/",
            "-E",
            "OLD*/",
          },
        },
      },

      extensions = {
        -- project = {
        --   hidden_files = true, -- default: false
        -- },
        workspaces = {
          -- keep insert mode after selection in the picker, default is false
          keep_insert = true,
        },

        file_browser = {
          select_buffer = true,
          cwd_to_path = true,
          hide_parent_dir = true,
          collapse_dirs = true,
          auto_depth = true,
        },
      },
    })

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
      "dl",
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
    map("n", "<C-l>", ":Telescope workspaces<CR>", { noremap = true, silent = true })
    -- map("n", "<C-l>", ":lua require'telescope'.extensions.projects.projects{}<CR>", { noremap = true, silent = true })

    ------------------------------------------------------------
    -- [[ Extentions ]]
    ------------------------------------------------------------
    -- Project viewer "ahmedkhalf/project.nvim",
    -- require("telescope").load_extension("projects")
    require("telescope").load_extension("workspaces")

    -- File browser + file/folder creation
    require("telescope").load_extension("file_browser")
  end,
}
