-- For `plugins/markview.lua` users.
return {
  {
    -- Renders Markdown in Neovim
    "OXY2DEV/markview.nvim",
    lazy = false,
  },
  {
    -- Renders Markdown in the browser
    "brianhuster/live-preview.nvim",
    dependencies = {
      -- You can choose one of the following pickers
      "nvim-telescope/telescope.nvim",
    },
  },
}
