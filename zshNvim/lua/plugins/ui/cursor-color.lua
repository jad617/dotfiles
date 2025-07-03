return {
  enabled = true,
  "mvllow/modes.nvim",
  config = function()
    require("modes").setup({
      colors = {
        copy = "#f5c359",
        delete = "#c75c6a",
        insert = "#99bc80",
        visual = "#c27fd7",
      },

      -- Set opacity for cursorline and number background
      line_opacity = 0.15,

      -- Enable cursor highlights
      set_cursor = true,

      -- Enable cursorline initially, and disable cursorline for inactive windows
      -- or ignored filetypes
      set_cursorline = true,

      -- Enable line number highlights to match cursorline
      set_number = true,

      -- Disable modes highlights in specified filetypes
      -- Please PR commonly ignored filetypes
      ignore_filetypes = { "NvimTree", "TelescopePrompt", "neo-tree" },
    })

    vim.api.nvim_create_autocmd({ "InsertLeave", "ModeChanged" }, {
      callback = function()
        -- Must have termguicolors=true for guifg/guibg hex to work in terminal
        vim.cmd([[highlight nCursor guifg=#000000 guibg=#FFFFFF]])
        vim.opt.guicursor:append("n-v-c:block-nCursor")
      end,
    })
  end,
}
