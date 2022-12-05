-- [[ local vars ]]
local map = vim.api.nvim_set_keymap -- set keys
local options = { noremap = true }

------------------------------------------------------------
-- [[ Key Bindings ]]
------------------------------------------------------------

-- [[ Linux ]]
map('n', '<A-m>', ':MarkdownPreview<CR>', options)

-- [[ MacOs ]]
-- Alt + m
map('n', 'µ', ':MarkdownPreview<CR>', options)
