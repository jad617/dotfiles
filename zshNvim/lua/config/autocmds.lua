--- Autocmds are automatically loaded on the VeryLazy event
--- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--- Add any additional autocmds here

------------------------------------------------------------
-- [[ Auto Open ]]
------------------------------------------------------------
vim.api.nvim_create_autocmd({ "VimEnter", "TabNewEntered" }, {
  callback = function()
    if vim.fn.expand("%") == "" then
      -- require("telescope").extensions.projects.projects({})
      vim.cmd("Telescope workspaces")

      local function check_buffer_id()
        if vim.fn.bufnr() == 1 then
          vim.cmd("Neotree action=show toggle=true dir=")
        else
          vim.defer_fn(check_buffer_id, 100)
        end
      end

      -- Start checking buffer ID
      check_buffer_id()
    elseif not (vim.fn.expand("%") == "dbui") then
      vim.defer_fn(OpenNeotree, 100)
    end
  end,
})

------------------------------------------------------------
-- [[ Auto Reload if file changed ]]
------------------------------------------------------------
vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold", "CursorHoldI", "FocusGained" }, {
  command = "if mode() != 'c' | checktime | endif",
  pattern = { "*" },
})
-- vim.api.nvim_create_autocmd({ "TabNewEntered" }, {
--   -- callback = function()
--   --   vim.defer_fn(OpenNeotree, 100)
--   -- end,
--   callback = function()
--     if vim.fn.expand("%") == "" then
--       -- require("telescope").extensions.projects.projects({})
--       vim.cmd("Telescope workspaces")
--
--       local function check_buffer_id()
--         if vim.fn.bufnr() == 1 then
--           vim.cmd("Neotree action=show toggle=true dir=")
--         else
--           vim.defer_fn(check_buffer_id, 100)
--         end
--       end
--
--       -- Start checking buffer ID
--       check_buffer_id()
--     elseif not (vim.fn.expand("%") == "dbui") then
--       vim.defer_fn(OpenNeotree, 100)
--     end
--   end,
-- })

-- Disable semanticTokensProvider
-- This messes up the syntax highlight colorscheme
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    client.server_capabilities.semanticTokensProvider = nil
  end,
})

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
    vim.cmd("TSDisable highlight")
  end,
})

--fix terraform and hcl comment string
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("FixTerraformCommentString", { clear = true }),
  callback = function(ev)
    vim.bo[ev.buf].commentstring = "# %s"
  end,
  pattern = { "terraform", "hcl" },
})

-- highlight on yank
vim.cmd([[
  augroup highlight_yank
  autocmd!
  au TextYankPost * silent! lua vim.highlight.on_yank({higroup="Visual", timeout=200})
  augroup END
]])
