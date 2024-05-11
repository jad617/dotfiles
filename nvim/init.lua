-- init.lua
-- Guide: https://mattermost.com/blog/turning-neovim-into-a-full-fledged-code-editor-with-lua/

------------------------------------------------------------
-- [[ Import Conf ]]
------------------------------------------------------------
require("settings") -- lua/settings.lua
require("keys") -- lua/keys.lua
require("plugins") -- lua/plugins.lua
require("commands") -- lua/plugins.lua

------------------------------------------------------------
-- [[ Import Plugins ]]
------------------------------------------------------------
-- Direct Import
require("onedark").setup() -- Lua

-- Import Conf
require("config.indent-blankline") -- Lua:Show index lines
require("config.nvim-tree") -- Lua:       Nerdtree
require("config.comfortable-motion") -- VimScript: Scroll
require("config.vim-better-whitespace") -- VimScript: Whitespace
require("config.gitsigns") -- Lua:       Git
require("config.lualine") -- Lua:       Vim bottom line
require("config.statusline") -- Lua:       Vim bottom line
require("config.markdown-preview") -- VimScript: Markdown preview
require("config.lspconfig") -- Lua
require("config.treesitter") -- Lua
require("config.mason") -- Lua
require("config.cmp") -- Lua
require("config.autopairs") -- Lua
require("config.telescope") -- Lua
require("config.null-ls") -- Lua
require("config.goto-preview") -- Lua
require("config.inc-rename") -- Lua
require("config.vimux") -- VimScript: Run command in tmux split
