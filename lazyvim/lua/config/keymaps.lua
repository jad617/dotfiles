-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- maps.lua
local map = vim.api.nvim_set_keymap -- set keys
local options = { noremap = true }
local options_silent = { noremap = true, silent = true }

------------------------------------------------------------
-- [[ DEFAULT ]]
------------------------------------------------------------
-- map the leader key
map("n", "<Space>", "", {})
vim.g.mapleader = " " -- 'vim.g' sets global variables

------------------------------------------------------------
-- [[ Shortcuts ]]
------------------------------------------------------------
-- Exit without saving: C-q
map("n", "<C-d>", ":q!<CR>", {})
map("i", "<C-d>", "<C-c>:q!<CR>", {})

-- Save only: C-x
map("n", "<C-x>", ":w<CR>", options)
map("i", "<C-x>", "<C-c>:w<CR>", options)

-- Disable search highlight
map("n", "\\", ":noh<return>", options_silent)

-- Open HTML in browser
-- [[ MacOs ]]
map("n", "˙", ":silent !sensible-browser %<CR>", options) -- Open HTML in default browser
-- [[ Linux ]]
map("n", "<A-h>", ":silent !sensible-browser %<CR>", options) -- Open HTML in default browser

-- Replace word
map("n", "<leader>l", "*``cgn", options) -- Replace 1 by 1

------------------------------------------------------------
-- [[ Navigation ]]
------------------------------------------------------------
-- [[ MacOs ]]
map("n", "<M-up>", ":tabprevious<CR>", options)
map("n", "<M-down>", ":tabnext<CR>", options)

-- Alt + b
map("n", "∫", ":b#<CR>", options) -- Jump back from definition

-- [[ Linux ]]
map("n", "<A-up>", ":tabprevious<CR>", options)
map("n", "<A-down>", ":tabnext<CR>", options)

map("n", "<A-b>", ":b#<CR>", options) -- Jump back from definition

------------------------------------------------------------
-- [[ Resize ]]
------------------------------------------------------------
-- [[ MacOs ]]
-- Alt + =
map("n", "≠", ":vertical resize +10<CR>", options)
map("i", "≠", "<C-c>:vertical resize +10<CR>", options)

-- Alt + -
map("n", "–", ":vertical resize -10<CR>", options)
map("i", "–", "<C-c>:vertical resize -10<CR>", options)

-- Alt + .
map("n", "≥", ":resize +10<CR>", options)
map("i", "≥", "<C-c>:resize +10<CR>", options)

-- Alt + ,
map("n", "≤", ":resize -10<CR>", options)
map("i", "≤", "<C-c>:resize -10<CR>", options)

-- [[ Linux ]]
map("n", "<A-=>", ":vertical resize +10<CR>", options)
map("i", "<A-=>", "<C-c>:vertical resize +10<CR>", options)

map("n", "<A-->", ":vertical resize -10<CR>", options)
map("i", "<A-->", "<C-c>:vertical resize -10<CR>", options)

map("n", "<A-.>", ":resize +10<CR>", options)
map("i", "<A-.>", "<C-c>:resize +10<CR>", options)

map("n", "<A-,>", ":resize -10<CR>", options)
map("i", "<A-,>", "<C-c>:resize -10<CR>", options)

------------------------------------------------------------
-- [[ CODE ]]
------------------------------------------------------------
---- TMUX
-----------------------------------------
----"""""""""""""""""""""""""""""""""Runs last Vimux Command""""""""""""""""""""""""""""""""""""""
--"Will launch a popup window with the slected word
--"
--
--map('n', '<A-s>', ':CocCommand git.chunkInfo<CR>', options)
--noremap ƒ :VimuxRunLastCommand<CR>
--noremap ∂ :VimuxPromptCommand<CR>
--
--noremap <A-f> :VimuxRunLastCommand<CR>
--noremap <A-d> :VimuxPromptCommand<CR>
--
--""""""""""""""""""""""""""""""""Go to definition with cTags"""""""""""""""""""""""""""""""""""
--"Will launch a popup window with the slected word
--noremap <A-z> :Tags <C-r><C-w><CR>
--noremap Ω :Tags <C-r><C-w><CR>
--
--
--""""""""""""""""""""""""""""""""""""""""Replace All"""""""""""""""""""""""""""""""""""""""""""
--"Alt+l ---> type the word and ESC, then pres . as many time as you want to replace the next word
--nnoremap ¬ *``cgn
--nnoremap <A-l> *``cgn
--
--" Alt-k For global replace
--nnoremap ˚ gD:%s/<C-R>///gc<left><left><left>
--nnoremap <A-k> gD:%s/<C-R>///gc<left><left><left>
--
--""""""""""""""""""""""""""""""""""""""""Search"""""""""""""""""""""""""""""""""""""""""""
--"Clear highlight on pressing ESC
--nnoremap \ :noh<return>
--
--""""""""""""""""""""""""""""""""""""""""Save & Exit""""""""""""""""""""""""""""""""""""""
--""Ctrl+d --> Exit all without saving
--"Normal mode
--noremap <C-d> :q!<cr>
--"Insert mode
--inoremap <C-d> <C-c>:q!<cr>
--
--""Ctrl+x --> Save and exit
--"Normal mode
--noremap <C-x> :w<cr>
--"Insert mode
--inoremap <C-x> <C-c>:w<cr>
--
--""""""""""""""""""""""""""""""""""""""Vim Buffers""""""""""""""""""""""""""""""""""""""""
--"MAC
--nnoremap ∫ :b#<CR>
--
--"LINUX
--nnoremap <A-b> :b#<CR>
--
--""""""""""""""""""""""""""""""""""""""Vim reload"""""""""""""""""""""""""""""""""""""""""
--"Alt+r reload nvim config
--  "LINUX
--  nnoremap <A-r> :source $MYVIMRC<CR>
--
--""""""""""""""""""""""""""""""""""""""Vim Window"""""""""""""""""""""""""""""""""""""""""
--
--"" alt + w in order to move between windows
--"Normal mode: use alt+w as Ctrl+w
--"MAC
--noremap ∑ <C-w>
--inoremap ∑ <C-c><C-w>
--
--"LINUX
--noremap <A-w> <C-w>
--"Insert mode: use alt+w as Ctrl+w
--inoremap <A-w> <C-c><C-w>
--
--""Resize vertical split size +
--"Alt+="
--
--"MAC
--noremap ≠ :vertical resize +10<cr>
--inoremap ≠ <C-c>:vertical resize +10<cr>
--"LINUX
--noremap <A-=> :vertical resize +10<cr>
--inoremap <A-=> <C-c>:vertical resize +10<cr>
--
--""Resize vertical split size -
--"Alt+-"
--"MAC
--noremap – :vertical resize -10<cr>
--inoremap – <C-c>:vertical resize -10<cr>
--
--"LINUX
--noremap <A--> :vertical resize -10<cr>
--inoremap <A--> <C-c>:vertical resize -10<cr>
--
--"Resize horizontal split size +
--"Alt+<
--"MAC
--noremap ≥ :resize +10<cr>
--inoremap ≥ <C-c>:resize +10<cr>
--
--"LINUX
--noremap <A-.> :resize +10<cr>
--inoremap <A-.> <C-c>:resize +10<cr>
--
--"Resize horizontal split size -
--"Alt+>
--"MAC
--noremap ≤ :resize -10<cr>
--inoremap ≤ <C-c>:resize -10<cr>
--"LINUX
--noremap <A-,> :resize -10<cr>
--inoremap <A-,> <C-c>:resize -10<cr>
--
--" Remap leader key to ,
--let g:mapleader=','
--
--"""""""""""""""""""""""""""""""""""""""""FZF"""""""""""""""""""""""""""""""""""""""""""""
--""Ctrl + f ---> FZF
--map <C-f> :Ag<CR>
--inoremap <C-g> :Gfiles?<CR>
--map <C-b> :Buffers<CR>
--
--
--" map <C-f> :Clap grep ./<CR>
--" map <C-g> :Clap grep2 ./<CR>
--" map <C-b> :Clap buffers<CR>
--
--""Alt+D
--"noremap ∂ :!ansible-vault decrypt --vault-password-file=~/.vault_pass  %<CR>
--"inoremap ∂ <C-c>:!ansible-vault decrypt --vault-password-file=~/.vault_pass  %<CR>
--
--""Alt+S
--"noremap ß :!ansible-vault encrypt %<CR>
--"inoremap ß <C-c>:!ansible-vault encrypt %<CR>
--
--"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
--" ==========================> VIM TROUBLESHOOT
--"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
--" :verbose imap <Tab>                             " This command can show which config is overwritting a key remap
--" :ALEInfo                                        " Show ALE loaded CONFIG
--" :CocList extensions                             " To list all the installed extensions
--" :CocConfig                                      " To configure coc
