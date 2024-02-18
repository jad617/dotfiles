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

------------------------------------------------------------
-- [[ Neo-tree ]]
------------------------------------------------------------
map("n", "<C-n>", "<C-c>:Neotree toggle<CR>", options_silent)

-- Jump to words Right|Left with Ctrl
map("n", "<C-Right>", "e", {})
map("n", "<C-Left>", "ge", {})

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
-- map("n", "<A-h>", ":silent !sensible-browser %<CR>", options) -- Open HTML in default browser
map("n", "<A-h>", ":LiveServerStart<CR>", options) -- Open HTML in default browser

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
-- map("n", "<t-up>", ":tabprevious<CR>", options)
-- map("n", "<t-down>", ":tabnext<CR>", options)

map("n", "<A-b>", ":b#<CR>", options) -- Jump back from definition

------------------------------------------------------------
-- [[ Resize ]]
------------------------------------------------------------
-- [[ MacOs ]]
-- Alt + =
map("n", "≠", ":vertical resize +10<CR>", options_silent)
map("i", "≠", "<C-c>:vertical resize +10<CR>", options_silent)

-- Alt + -
map("n", "–", ":vertical resize -10<CR>", options_silent)
map("i", "–", "<C-c>:vertical resize -10<CR>", options_silent)

-- Alt + .
map("n", "≥", ":resize +10<CR>", options_silent)
map("i", "≥", "<C-c>:resize +10<CR>", options_silent)

-- Alt + ,
map("n", "≤", ":resize -10<CR>", options_silent)
map("i", "≤", "<C-c>:resize -10<CR>", options_silent)

-- [[ Linux ]]
map("n", "<A-\\>", ":vertical resize -90<CR>", options_silent)
map("i", "<A-\\>", "<C-c>:vertical resize -90<CR>", options_silent)

map("n", "<A-=>", ":vertical resize +10<CR>", options_silent)
map("i", "<A-=>", "<C-c>:vertical resize +10<CR>", options_silent)

map("n", "<A-->", ":vertical resize -10<CR>", options_silent)
map("i", "<A-->", "<C-c>:vertical resize -10<CR>", options_silent)

map("n", "<A-.>", ":resize +10<CR>", options_silent)
map("i", "<A-.>", "<C-c>:resize +10<CR>", options_silent)

map("n", "<A-,>", ":resize -10<CR>", options_silent)
map("i", "<A-,>", "<C-c>:resize -10<CR>", options_silent)

------------------------------------------------------------
-- [[ CODE ]]
------------------------------------------------------------

-- Colorizer
-- [[ Linux ]]
map("n", "<A-c>", ":ColorizerToggle<CR>", options)
-- [[ MacOs ]]
map("n", "ç", ":ColorizerToggle<CR>", options)

------------------------------------------------------------
-- [[ VIM TROUBLESHOOT ]]
------------------------------------------------------------
-- :verbose imap <Tab>                             " This command can show which config is overwritting a key remap
