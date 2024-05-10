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
    vim.wo.number = true -- Enable line Numbers
    vim.wo.relativenumber = true -- Relative numbers for easier jumps
    vim.wo.relativenumber = true -- Relative numbers for easier jumps
    -- vim.api.nvim_command("Neotree")
    -- vim.cmd([[wincmd w]])
  end,
})

-- vim.api.nvim_create_autocmd({ "TabEnter", "TabNew" }, {
--   callback = function()
--     vim.api.nvim_command("Neotree")
--   end,
-- })

-- vim.api.nvim_create_autocmd("LspAttach", {
--   callback = function(args)
--     local client = vim.lsp.get_client_by_id(args.data.client_id)
--     client.server_capabilities.semanticTokensProvider = nil
--   end,
-- })

-- Ansible file pattern
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile", "BufEnter" }, {
  group = vim.api.nvim_create_augroup("Ansible", { clear = true }),
  pattern = {
    "*/roles/*/*/*.yaml",
    "*/roles/*/*/.yml",
    "*/inventory/*/group_vars/*",
    "*/inventory/*/host_vars/*",
    "main.yml",
    "main.yaml",
    "*/playbooks/*.yaml",
    "*/playbooks/*.yml",
    "group_vars/*.yml",
    "group_vars/*.yaml",
    "host_vars/*.yml",
    "host_vars/*.yaml",
    "files/*.yaml",
    "files/*.yml",
    "environments/*.yaml",
    "environments/*.yml,",
  },
  callback = function()
    vim.opt.filetype = "yaml.ansible"
  end,
})

-- highlight on yank
vim.cmd([[
  augroup highlight_yank
  autocmd!
  au TextYankPost * silent! lua vim.highlight.on_yank({higroup="Visual", timeout=200})
  augroup END
]])
