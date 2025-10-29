--- Autocmds are automatically loaded on the VeryLazy event
--- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--- Add any additional autocmds here

------------------------------------------------------------
-- [[ Auto add project with WorkspacesAdd ]]
------------------------------------------------------------
-- Function to get the Git repository name dynamically
-- local function get_repo_name_from_git()
--   -- Get the Git remote URL using the 'git remote get-url origin' command
--   local git_url = vim.fn.system("git remote get-url origin")
--
--   -- If the git command returns an error or the URL is empty, return nil
--   if vim.fn.empty(git_url) == 1 then
--     -- vim.notify("No Git repository found!")
--     return nil
--   end
--
--   -- Extract the repository name from the URL (example: 'bi-control-tower-tool')
--   local repo_name = git_url:match(".*/(.*)%.git")
--   if repo_name then
--     return repo_name
--   else
--     -- vim.notify("Could not extract repo name from URL!")
--     return nil
--   end
-- end
--
-- -- Function to get existing workspace names
-- local function get_existing_workspace_names()
--   -- Execute the Vim command 'WorkspacesList' and capture its output
--   local list = vim.fn.execute("WorkspacesList")
--
--   -- Split the result into lines (one workspace per line)
--   local names = {}
--   for line in list:gmatch("[^\r\n]+") do
--     -- Extract the workspace name from each line (first word before space)
--     local name = line:match("^(%S+)")
--     if name then
--       names[name] = true
--     end
--   end
--
--   -- Debugging output
--   -- vim.notify("Existing workspace names: " .. table.concat(vim.tbl_keys(names), ", "))
--   return names
-- end
--
-- -- Function to add a new workspace
-- local function add_workspace(repo_name)
--   -- Run the WorkspacesAdd command for the given repo name
--   local result = vim.fn.execute("WorkspacesAdd " .. repo_name)
--
--   -- Debugging: Show the result of the WorkspacesAdd command
--   -- vim.notify("Workspace add result: " .. result)
-- end
--
-- -- Function to validate if the workspace exists or not, and add it if needed
-- local function validate_and_add_workspace()
--   -- Dynamically get the repo name from Git
--   local repo_name = get_repo_name_from_git()
--
--   -- If no repo name is found, do nothing
--   if not repo_name then
--     return
--   end
--
--   -- Get existing workspace names
--   local existing_names = get_existing_workspace_names()
--
--   -- Debugging: Show what repo name we are checking
--   -- vim.notify("Checking workspace for repo: " .. repo_name)
--
--   -- If the workspace exists, notify the user
--   if existing_names[repo_name] then
--     -- vim.notify("Workspace already exists: " .. repo_name)
--   else
--     -- Otherwise, add the workspace and notify the user
--     vim.notify("Workspace does not exist, adding: " .. repo_name)
--     add_workspace(repo_name)
--   end
-- end
--
-- -- Autocommand to run the function when opening Neovim
-- vim.api.nvim_create_augroup("WorkspaceValidation", { clear = true })
--
-- vim.api.nvim_create_autocmd("VimEnter", {
--   desc = "Validate and add workspace if not exists",
--   group = "WorkspaceValidation",
--   callback = validate_and_add_workspace,
-- })
--
-- ------------------------------------------------------------
-- -- [[ Auto Open Workspace List ]]
-- ------------------------------------------------------------
-- -- https://github.com/AstroNvim/AstroNvim/issues/344#issuecomment-1214143220
-- -- vim.api.nvim_create_augroup("workspaces", {})
-- -- vim.api.nvim_create_autocmd("UiEnter", {
-- --   desc = "Open workspaces automatically",
--   group = "workspaces",
--   callback = function()
--     if vim.fn.argc() == 0 then
--       vim.fn.execute("Telescope workspaces")
--     end
--   end,
-- })

------------------------------------------------------------
-- [[ Auto Open Neotree ]]
------------------------------------------------------------
-- https://github.com/AstroNvim/AstroNvim/issues/344#issuecomment-1214143220
vim.api.nvim_create_augroup("neotree", {})
vim.api.nvim_create_autocmd("UiEnter", {
  desc = "Open Neotree automatically",
  group = "neotree",
  callback = function()
    if vim.fn.argc() > 0 then
      vim.cmd("Neotree action=show toggle=true dir=")
      vim.cmd("Neotree action=show toggle=true dir=")
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

------------------------------------------------------------
-- Disable semanticTokensProvider
-- This messes up the syntax highlight colorscheme
------------------------------------------------------------
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    client.server_capabilities.semanticTokensProvider = nil
  end,
})

------------------------------------------------------------
-- Ansible file pattern
------------------------------------------------------------
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

------------------------------------------------------------
-- Fix terraform and hcl comment string
------------------------------------------------------------
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("FixTerraformCommentString", { clear = true }),
  callback = function(ev)
    vim.bo[ev.buf].commentstring = "# %s"
  end,
  pattern = { "terraform", "hcl" },
})

------------------------------------------------------------
-- highlight on yank
------------------------------------------------------------
vim.cmd([[
  augroup highlight_yank
  autocmd!
  au TextYankPost * silent! lua vim.highlight.on_yank({higroup="Visual", timeout=200})
  augroup END
]])
