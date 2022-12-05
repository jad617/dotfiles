-- [[ local vars ]]
local map = vim.api.nvim_set_keymap -- set keys
local options = { noremap = true }

-- [[ Setup ]]
require("nvim-tree").setup {
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
}

------------------------------------------------------------
-- [[ Key Bindings ]]
------------------------------------------------------------

-- [[ Global ]]
map('n', '<C-n>', '<C-c>:NvimTreeToggle<CR>', options)
