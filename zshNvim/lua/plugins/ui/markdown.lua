-- For `plugins/markview.lua` users.
return {
  {
    -- Renders Markdown in Neovim
    "OXY2DEV/markview.nvim",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "folke/snacks.nvim",
    },
    lazy = false,

    -- For `nvim-treesitter` users.
    priority = 49,

    config = function()
      require("markview").setup({
        experimental = {
          check_rtp = false,
          check_rtp_message = false,
        },
      })

      vim.schedule(function()
        local ok, indent = pcall(require, "snacks.indent")
        if ok then
          indent.disable()
        end
      end)
      ------------------------------------------------------------
      -- [[ local vars ]]
      ------------------------------------------------------------
      local map = vim.keymap.set -- set keys
      local options = { noremap = true, silent = true }

      ------------------------------------------------------------
      -- [[ Functions ]]
      ------------------------------------------------------------
      local indent_enabled = false

      function ToggleSnacksIndent()
        if indent_enabled then
          require("snacks.indent").disable()
          indent_enabled = false
          vim.cmd("Markview enable")
          vim.notify("Snacks indent disabled")
        else
          require("snacks.indent").enable()
          indent_enabled = true
          vim.notify("Snacks indent enabled")
          vim.cmd("Markview disable")
        end
      end
      ------------------------------------------------------------
      -- [[ Key Bindings ]]
      ------------------------------------------------------------
      -- map("n", "<leader>m", ":Markview toggle<CR>", options)
      map("n", "<leader>m", function()
        ToggleSnacksIndent()
      end, options)
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
