local function cmd(command)
  return table.concat({ "<Cmd>", command, "<CR>" })
end

vim.keymap.set("n", "<C-w>z", cmd("WindowsMaximize"))
vim.keymap.set("n", "<C-w>_", cmd("WindowsMaximizeVertically"))
vim.keymap.set("n", "<C-w>|", cmd("WindowsMaximizeHorizontally"))
vim.keymap.set("n", "<C-w>=", cmd("WindowsEqualize"))

require("windows").setup({
  autowidth = {
    enable = true,
    winwidth = 50,
    -- filetype = {
    --   help = 2,
    -- },
  },
  ignore = {
    filetype = { "NvimTree", "neo-tree", "undotree", "gundo" },
    -- filetype = {},
  },
  animation = {
    enable = true,
    duration = 300,
    fps = 30,
    easing = "in_out_sine",
  },
})
