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
map("n", "<leader>t", ":e ~/todo<CR>", options) -- Replace 1 by 1
------------------------------------------------------------
-- [[ Float Terminal]]
------------------------------------------------------------
-- map("n", "<c-/>", ":FloatTermToggle<CR>", options_silent)
-- map("i", "<c-/>", "<C-c>:FloatTermToggle<CR>", options_silent)

------------------------------------------------------------
-- [[ Neo-tree ]]
------------------------------------------------------------
map("n", "<C-n>", "<C-c>:Neotree action=show toggle=true<CR>", options_silent)
-- map(
--   "n",
--   "<C-n>",
--   '<C-c>:lua require("neo-tree.command").execute({ action = "show", toggle = true, dir = dir })<CR>',
--   options_silent
-- )

-- Jump to words Right|Left with Ctrl
map("n", "<C-Right>", "e", {})
map("n", "<C-Left>", "ge", {})
map("v", "<C-Right>", "e", {})
map("v", "<C-Left>", "ge", {})

-- Exit without saving: C-q
map("n", "<C-d>", ":q!<CR><CR>", {})
map("i", "<C-d>", "<C-c>:q!<CR>", {})

-- Save only: C-x
map("n", "<C-x>", ":w<CR>", options_silent)
map("i", "<C-x>", "<C-c>:w<CR>", options_silent)

-- Disable search highlight
map("n", "\\", ":noh<return>", options_silent)

-- Open HTML in browser
-- [[ MacOs ]]
map("n", "˙", ":silent !sensible-browser %<CR>", options) -- Open HTML in default browser
-- [[ Linux ]]
-- map("n", "<A-h>", ":silent !sensible-browser %<CR>", options) -- Open HTML in default browser
map("n", "<A-h>", ":LiveServerStart<CR>", options) -- Open HTML in default browser

-- Replace word
map("n", "<leader>l", '*``"_cgn', options) -- Replace 1 by 1

------------------------------------------------------------
-- [[ Navigation ]]
------------------------------------------------------------
-- [[ MacOs ]]
map("n", "<M-up>", ":tabprevious<CR>", options_silent)
map("n", "<M-down>", ":tabnext<CR>", options_silent)

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
map("n", "<A-\\>", ":vertical resize -70<CR>", options_silent)
map("i", "<A-\\>", "<C-c>:vertical resize -70<CR>", options_silent)

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

-- [[ Delete without yanking ]]
map("n", "<leader>dd", '"_dd', options)
map("v", "<leader>dd", '"_dd', options)

-- [[ Copy current word ]]
-- Select word between double quote
map("n", "<C-y>", 'yi"', options)
map("i", "<C-y>", '<C-c>yi"', options)

-- Select word between single quote
map("n", "<C-u>", "yi'", options)
map("n", "<C-u>", "<C-c>yi'", options)

-- Disable Diagnostic warnings
map("n", "<leader>di", "<cmd>lua vim.diagnostic.config({ virtual_text = false })<CR>", options) -- show lsp implementations
-- Enable Diagnostic warnings
map("n", "<leader>de", "<cmd>lua vim.diagnostic.config({ virtual_text = true })<CR>", options) -- show lsp implementations

------------------------------------------------------------
-- [[ VIM TROUBLESHOOT ]]
------------------------------------------------------------
-- :verbose imap <Tab>                             " This command can show which config is overwritting a key remap
