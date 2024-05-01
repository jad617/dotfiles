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

-- Remove lazyvim default key maps
vim.keymap.del({ "t", "n" }, "<c-l>")

------------------------------------------------------------
-- [[ Shortcuts ]]
------------------------------------------------------------
------------------------------------------------------------
-- [[ Float Terminal]]
------------------------------------------------------------
map("n", "<c-/>", ":FloatTermToggle<CR>", options_silent)
map("i", "<c-/>", "<C-c>:FloatTermToggle<CR>", options_silent)

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

-- [[ Copy current word ]]
-- Select word between double quote
map("n", "<C-y>", 'yi"', options)
map("i", "<C-y>", '<C-c>yi"', options)

-- Select word between single quote
map("n", "<C-u>", "yi'", options)
map("n", "<C-u>", "<C-c>yi'", options)

-- [[ Git ]]
function GitCommitAndPush(commit_message)
  local command = 'git add -A && git commit -m "' .. commit_message .. '" && git push'
  vim.fn.system(command)
end

function GitCommitAmendAndForcePush()
  local confirm = vim.fn.input("Are you sure you want to amend the last commit and force push? (y/n): ")
  if confirm == "y" then
    local command = "git add . && git commit --amend --no-edit && git push -f"
    print("Force Push Done")
    vim.fn.system(command)
  else
    print("Force Push Canceled")
  end
end

map("n", "<A-f>", ":lua GitCommitAmendAndForcePush()<CR>", options)
map("i", "<A-f>", "<C-c>:lua GitCommitAmendAndForcePush()<CR>", options)

map("n", "<A-/>", ':lua GitCommitAndPush(vim.fn.input("Git Push commit message: "))<CR> ', options)
map("i", "<A-/>", '<C-c>:lua GitCommitAndPush(vim.fn.input("Git Push commit message: "))<CR> ', options)

-- [[ Make ]]
map("n", "<A-'>", ":!make ", options)
map("i", "<A-'>", "<C-c>:!make ", options)

------------------------------------------------------------
-- [[ VIM TROUBLESHOOT ]]
------------------------------------------------------------
-- :verbose imap <Tab>                             " This command can show which config is overwritting a key remap
