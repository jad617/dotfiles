-- Window resizer
-- Window picker works with neo-tree
return {
  "anuvyklack/windows.nvim",
  keys = {
    { "<C-w>z", "<Cmd>WindowsMaximize<CR>" },
    { "<C-w>_", "<Cmd>WindowsMaximizeVertically<CR>" },
    { "<C-w>|", "<Cmd>WindowsMaximizeHorizontally<CR>" },
    { "<C-w>=", "<Cmd>WindowsEqualize<CR>" },
  },
  dependencies = {
    "anuvyklack/middleclass",
    "anuvyklack/animation.nvim",
  },
  config = function()
    vim.o.winwidth = 10
    vim.o.winminwidth = 10
    vim.o.equalalways = false

    require("windows").setup({
      autowidth = {
        enable = true,
        winwidth = 4,
      },
      ignore = {
        filetype = { "NvimTree", "snacks_picker_list", "undotree", "gundo" },
      },
      animation = {
        enable = true,
        duration = 300,
        fps = 30,
        easing = "in_out_sine",
      },
    })
  end,
}
