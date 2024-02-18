--- Autocmds are automatically loaded on the VeryLazy event
--- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--- Add any additional autocmds here

------------------------------------------------------------
-- [[ Auto Open ]]
------------------------------------------------------------
-- https://github.com/nvim-tree/nvim-tree.lua/wiki/Open-At-Startup

-- Neotree
vim.api.nvim_create_autocmd({ "VimEnter" }, {
  callback = function()
    require("neo-tree.command").execute({ action = "show", toggle = true, dir = vim.loop.cwd() })
    require("neo-tree.command").execute({ action = "show", toggle = true, dir = vim.loop.cwd() })
    -- vim.api.nvim_command("Neotree")
    -- vim.cmd([[wincmd w]])
  end,
})
