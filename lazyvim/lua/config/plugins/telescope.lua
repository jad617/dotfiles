-- [[ local vars ]]
local map = vim.api.nvim_set_keymap -- set keys
local builtin = require("telescope.builtin")

------------------------------------------------------------
-- [[ Key Bindings ]]
------------------------------------------------------------
vim.keymap.set("n", "ff", builtin.find_files, {})
vim.keymap.set("n", "<C-f>", builtin.find_files, {})
vim.keymap.set("n", "fg", builtin.live_grep, {})
vim.keymap.set("n", "<C-g>", builtin.live_grep, {})
vim.keymap.set("n", "fb", builtin.buffers, {})
vim.keymap.set("n", "<C-b>", builtin.buffers, {})
vim.keymap.set("n", "<leader>fb", builtin.buffers, {})
vim.keymap.set("n", "fh", builtin.help_tags, {})

map(
  "n",
  "gv",
  '<cmd>lua require"telescope.builtin".lsp_definitions({jump_type="vsplit"})<CR>',
  { noremap = true, silent = true }
)

map(
  "n",
  "<leader>g",
  ":execute 'Telescope live_grep default_text=' . expand('<cword>')<cr>",
  { noremap = true, silent = true }
)
