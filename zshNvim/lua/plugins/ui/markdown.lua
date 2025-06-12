-- For `plugins/markview.lua` users.
return {
  {
    -- Renders Markdown in Neovim
    "OXY2DEV/markview.nvim",
    lazy = false,
    config = function()
      ------------------------------------------------------------
      -- [[ local vars ]]
      ------------------------------------------------------------
      local map = vim.api.nvim_set_keymap -- set keys
      local options = { noremap = true, silent = true }

      ------------------------------------------------------------
      -- [[ Key Bindings ]]
      ------------------------------------------------------------
      map("n", "<leader>m", ":Markview toggle<CR>", options)
    end,
  },
  {
    -- Renders Markdown in the browser
    "brianhuster/live-preview.nvim",
    dependencies = {
      -- You can choose one of the following pickers
      "nvim-telescope/telescope.nvim",
    },
    config = function()
      ------------------------------------------------------------
      -- [[ local vars ]]
      ------------------------------------------------------------
      local map = vim.api.nvim_set_keymap -- set keys
      local options = { noremap = true, silent = true }

      ------------------------------------------------------------
      -- [[ Key Bindings ]]
      ------------------------------------------------------------
      map("n", "<A-m>", ":LivePreview start<CR>", options)
    end,
  },
}
