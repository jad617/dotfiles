return {
  -- Git diff view
  {
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
  },

  -- GitHub octo
  {
    "pwntester/octo.nvim",
    requires = {
      "nvim-lua/plenary.nvim",
      "folke/snacks.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      require("octo").setup()
    end,
  },

  -- Git integration
  { "tpope/vim-fugitive" },

  -- Git signs
  {
    "lewis6991/gitsigns.nvim",
    config = function()
      -- Add spacing for gitsigns
      vim.cmd("set signcolumn=yes")

      ------------------------------------------------------------
      -- [[ Setup ]]
      ------------------------------------------------------------
      require("gitsigns").setup({
        signs = {
          add = { text = "┃" },
          change = { text = "┃" },
          delete = { text = "┃" },
          topdelete = { text = "‾" },
          changedelete = { text = "-" },
          untracked = { text = "┆" },
        },
        signcolumn = true, -- Toggle with `:Gitsigns toggle_signs`
        numhl = false, -- Toggle with `:Gitsigns toggle_numhl`
        linehl = false, -- Toggle with `:Gitsigns toggle_linehl`
        word_diff = false, -- Toggle with `:Gitsigns toggle_word_diff`
      })

      ------------------------------------------------------------
      -- [[ local vars ]]
      ------------------------------------------------------------
      local map = vim.api.nvim_set_keymap -- set keys
      local options = { noremap = true }

      ------------------------------------------------------------
      -- [[ Key Bindings ]]
      ------------------------------------------------------------
      map("n", "<A-a>", ":Gitsigns preview_hunk<CR>", options)
      map("i", "<A-a>", "<C-c>:Gitsigns preview_hunk<CR>", options)

      map("n", "<A-g>", ":Gitsigns diffthis<CR>", options)
      map("i", "<A-g>", "<C-c>:Gitsigns diffthis<CR>", options)

      map("n", "<A-d>", ":Gitsigns toggle_deleted<CR>", options)
      map("i", "<A-d>", "<C-c>:Gitsigns toggle_deleted<CR>", options)

      -- [[ MacOs ]]
      -- Alt + a
      map("n", "å", ":Gitsigns preview_hunk<CR>", options)
      map("i", "å", "<C-c>:Gitsigns preview_hunk<CR>", options)
      -- Alt + g
      map("n", "©", ":Gitsigns diffthis<CR>", options)
      map("i", "©", "<C-c>:Gitsigns diffthis<CR>", options)
      -- Alt + d
      map("n", "∂", ":Gitsigns toggle_deleted<CR>", options)
      map("i", "∂", "<C-c>:Gitsigns toggle_deleted<CR>", options)
    end,
  },
}
