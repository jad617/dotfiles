return {
  "mvllow/modes.nvim",
  config = function()
    require("modes").setup({
      colors = {
        copy = "#f5c359",
        delete = "#c75c6a",
        insert = "#99bc80",
        visual = "#ff4d94",
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

    vim.api.nvim_create_autocmd({ "InsertLeave" }, {
      callback = function()
        vim.cmd([[hi nCursor guibg=#FFFFFF ]])
        vim.opt.guicursor:append("n-c-v:block-nCursor")
      end,
    })
  end,
}
