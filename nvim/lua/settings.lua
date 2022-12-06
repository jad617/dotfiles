-- TO reviewn config from : https://github.com/brainfucksec/neovim-lua/blob/main/nvim/lua/core/options.lua

-- [[ local vars ]]
--
local o = vim.o                     -- global
local wo = vim.wo                   -- window
local bo = vim.bo                   -- buffer
local cmd = vim.cmd                 -- cmd
local map = vim.api.nvim_set_keymap -- set keys
local options = { noremap = true }

-- [[ global options ]]
o.clipboard = 'unnamedplus'
o.swapfile = true                          -- Toggle swapfile
o.dir = '/tmp'                              -- Swapfile location
o.laststatus = 2                            -- Always enable statusline
o.hlsearch = true                           -- Highlight word while searching
o.incsearch = true                          -- Jump to word while searching
o.ignorecase = true                         -- Ignore case while searching
o.smartcase = true                          -- Overide ignorecase if search pattern contains upper case
o.smarttab = true                           -- Uses shiftwidth instead of tabstop at start of lines
o.splitright = true                         -- Go right of current buffer when splitting
o.splitbelow = true                         -- Go under current buffer when splitting
o.linebreak = true                          -- Wrap on word boundary
o.termguicolors = true                      -- Enable 24-bit RGB colors
-- o.scrolloff = 10                            -- Minimal number to keep above and below cursor: Set to 999 for cursor to always be in the middle

o.mouse = 'a'                               -- Mouse configs
o.mousemodel = 'extend'
map('n', '<LeftMouse>', '<nop>', options)
map('i', '<LeftMouse>', '<nop>', options)

-- [[ window-local options ]]
wo.number = true                            -- Enable line Numbers
wo.relativenumber = true                    -- Relative numbers for easier jumps
wo.wrap = true                              -- When on, lines longer than the width of the window will wrap and displaying continues on the next line.
wo.foldcolumn = "2"                         -- Left Margin

-- [[ buffer-local options ]]
bo.expandtab = true                         -- In Insert mode: Use the appropriate number of spaces to insert a
bo.tabstop = 2                              -- Converted tabs now jump 4 spaces
-- bo.softtabstop = 2
bo.shiftwidth = 2                           -- When indenting with '>', use 2 spaces width
bo.smartindent = true                       -- Do smart autoindenting when starting a new line

-- [[ Autocmd ]]
cmd [[au FileType * set fo-=c fo-=r fo-=o]] -- Disable auto comment on next line
cmd [[ au BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g'\"" | endif ]] --Jump to the last position when reopening a file

-- [[ FileType ]]
cmd [[au BufNewFile,BufRead Jenkinsfile setf groovy]]
cmd [[au FileType bash,lua,yaml,json,html setlocal tabstop=2 expandtab shiftwidth=2 softtabstop=2]]
cmd [[au FileType python,go,groovy setlocal tabstop=4 expandtab shiftwidth=4 softtabstop=4]]
