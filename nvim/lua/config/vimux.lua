------------------------------------------------------------
-- [[ Locals ]]
------------------------------------------------------------
local map = vim.api.nvim_set_keymap -- set keys
local options = { noremap = true }

------------------------------------------------------------
-- [[ Key Bindings ]]
------------------------------------------------------------
-- Run code on Alt-c
-- [[ MacOs ]]
map('n', 'ƒ', ":w<CR>:VimuxRunLastCommand<CR>", options)
map('i', 'ƒ', "<C-c>:w<CR>:VimuxRunLastCommand<CR>", options)
-- map('n', 'ƒ', ":VimuxPromptCommand<CR>", options)
-- [[ Linux ]]
-- map('n', '<A-f>', "<C-c>:w<CR>VimuxRunLastCommand<CR>", options)
-- map('n', '<A-f>', "VimuxPromptCommand<CR>", options)

-- FOR PYTHON
-- [[ MacOs ]]

-- if vim.bo.filetype == "python" then
--   -- map('n', 'ç', ":w<CR>:exec '!python3' shellescape(@%, 1)<CR>", options)
--   map('n', 'ç', "Vimux:exec '!python3' shellescape(@%, 1)<CR>", options)
-- end
