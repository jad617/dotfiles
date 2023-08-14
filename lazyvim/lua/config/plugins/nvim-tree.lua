------------------------------------------------------------
-- [[ local vars ]]
------------------------------------------------------------
local map = vim.api.nvim_set_keymap -- set keys
local options = { noremap = true, silent = true }

------------------------------------------------------------
-- [[ Setup ]]
------------------------------------------------------------
require("nvim-tree").setup({
  sort_by = "case_sensitive",
  view = {
    adaptive_size = true,
    mappings = {
      list = {
        { key = "u", action = "dir_up" },
        { key = "c", action = "cd" },
        { key = "cp", action = "copy" },
      },
    },
  },
  renderer = {
    group_empty = true,
  },
  filters = {
    dotfiles = true,
  },
})

------------------------------------------------------------
-- [[ Auto Close ]]
------------------------------------------------------------
-- https://github.com/nvim-tree/nvim-tree.lua/wiki/Auto-Close
vim.api.nvim_create_autocmd("BufEnter", {
  group = vim.api.nvim_create_augroup("NvimTreeClose", { clear = true }),
  pattern = "NvimTree_*",
  callback = function()
    local layout = vim.api.nvim_call_function("winlayout", {})
    if
      layout[1] == "leaf"
      and vim.api.nvim_buf_get_option(vim.api.nvim_win_get_buf(layout[2]), "filetype") == "NvimTree"
      and layout[3] == nil
    then
      vim.cmd("confirm quit")
    end
  end,
})

------------------------------------------------------------
-- [[ Key Bindings ]]
------------------------------------------------------------
map("n", "<C-n>", "<C-c>:NvimTreeToggle<CR>", options)
