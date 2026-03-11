return {
  {
    -- Renders Markdown in the browser
    "brianhuster/live-preview.nvim",
    dependencies = {
      "nvim-telescope/telescope.nvim",
    },
    config = function()
      local map = vim.api.nvim_set_keymap
      local options = { noremap = true, silent = true }

      map("n", "<A-m>", ":LivePreview start<CR>", options)
      map("n", "µ", ":LivePreview start<CR>", options)
    end,
  },
}
