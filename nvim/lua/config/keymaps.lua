-- Keymaps are automatically loaded on the VeryLazy event
--
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

-- Disable recording
map("n", "q", "<Nop>", options_silent)
map("n", "<c-z>", "<Nop>", options_silent)

-- Remove lazyvim default key maps
--vim.keymap.del({ "t", "n" }, "<c-l>")

------------------------------------------------------------
-- [[ Shortcuts ]]
------------------------------------------------------------
-- Jump to begining of line
map("n", "<c-q>", "^", options_silent)
map("v", "<c-q>", "^", options_silent)
map("i", "<c-q>", "<C-c>^", options_silent)

-- Jump to end of line
map("n", "<c-e>", "$", options_silent)
map("v", "<c-e>", "$", options_silent)
map("i", "<c-e>", "<C-c>$", options_silent)

-- Open new empty tab
map("n", "<C-t>", ":tabnew<CR>", options_silent)
map("i", "<C-t>", "<C-c>:tabnew<CR>", options_silent)

-- Open Todo
-- map("n", "<leader>t", ":e ~/todo<CR>", options) -- Replace 1 by 1

-- Save only: C-x
map("n", "<C-x>", ":w<CR>", options_silent)
map("i", "<C-x>", "<C-c>:w<CR>", options_silent)

-- Close
map("n", "<C-d>", ":q<CR>", options_silent)
map("i", "<C-d>", "<C-c>:q<CR>", options_silent)

-- Disable search highlight
map("n", "\\", ":noh<return>", options_silent)

-- Open HTML in browser
map("n", "<A-h>", ":LiveServerStart<CR>", options) -- Open HTML in default browser

-- Replace word
map("n", "<leader>l", "*``cgn", options) -- Replace 1 by 1

------------------------------------------------------------
-- [[ Navigation ]]
------------------------------------------------------------
-- [[ MacOs ]]
map("n", "<M-up>", ":tabprevious<CR>", options_silent)
map("n", "<M-down>", ":tabnext<CR>", options_silent)

-- Alt + b
map("n", "<A-b>", ":b#<CR>", options) -- Jump back from definition

-- Window Navigation
-- map("n", "<S-Left>", "<C-w>h", options)
-- map("n", "<S-Right>", "<C-w>l", options)
-- map("n", "<S-Up>", "<C-w>k", options)
-- map("n", "<S-Down>", "<C-w>j", options)

------------------------------------------------------------
-- [[ Resize ]]
------------------------------------------------------------
-- [[ MacOs ]]
-- Alt + =
-- map("n", "≠", ":vertical resize +10<CR>", options_silent)
-- map("i", "≠", "<C-c>:vertical resize +10<CR>", options_silent)
--
-- -- Alt + -
-- map("n", "–", ":vertical resize -10<CR>", options_silent)
-- map("i", "–", "<C-c>:vertical resize -10<CR>", options_silent)
--
-- -- Alt + .
-- map("n", "≥", ":resize +10<CR>", options_silent)
-- map("i", "≥", "<C-c>:resize +10<CR>", options_silent)
--
-- -- Alt + ,
-- map("n", "≤", ":resize -10<CR>", options_silent)
-- map("i", "≤", "<C-c>:resize -10<CR>", options_silent)
--
-- -- [[ Linux ]]
-- map("n", "<A-\\>", ":vertical resize -70<CR>", options_silent)
-- map("i", "<A-\\>", "<C-c>:vertical resize -70<CR>", options_silent)
--
-- map("n", "<A-=>", ":vertical resize +10<CR>", options_silent)
-- map("i", "<A-=>", "<C-c>:vertical resize +10<CR>", options_silent)
--
-- map("n", "<A-->", ":vertical resize -10<CR>", options_silent)
-- map("i", "<A-->", "<C-c>:vertical resize -10<CR>", options_silent)
--
-- map("n", "<A-.>", ":resize +10<CR>", options_silent)
-- map("i", "<A-.>", "<C-c>:resize +10<CR>", options_silent)
--
-- map("n", "<A-,>", ":resize -10<CR>", options_silent)
-- map("i", "<A-,>", "<C-c>:resize -10<CR>", options_silent)

------------------------------------------------------------
-- [[ CODE ]]
------------------------------------------------------------

-- [[ Copy current word ]]
-- Copy current word under cursor
map("n", "<leader>y", 'viwy"', options)

-- Select word between double quote
map("n", "<C-y>", 'yi"', options)
map("i", "<C-y>", '<C-c>yi"', options)

-- Select word between single quote
-- map("n", "<C-u>", "yi'", options)
-- map("n", "<C-u>", "<C-c>yi'", options)

------------------------------------------------------------
-- [[ VIM TROUBLESHOOT ]]
------------------------------------------------------------
-- :verbose imap <Tab>                             " This command can show which config is overwritting a key remap
