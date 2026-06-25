---------------------------------------------------------------------------
-- DevOps — Jira + GitHub dashboard inside Neovim.
--
-- Phase 1: read/navigate (Jira issues, GitHub PRs, detail cards, diff viewer)
-- Phase 2: write actions, PR review, inline comments, scope toggles
--
-- Commands:
--   :JiraAuth       prompt for + store Jira connection credentials
--   :JiraAuthClear  delete the stored credentials
--   :DevOps        open the dashboard (float by default, see config.layout)
--   :DevOpsTab     open the dashboard in a new tab
--   :DevOpsHealth  env / gh / curl / Jira auth report
--
-- Configure (optional) BEFORE plugins load, e.g. in lua/config/options.lua:
--   vim.g.devops = { jira = { project = "DEVOPS" }, layout = "float" }
--
-- Jira credentials come from JIRA_URL/JIRA_EMAIL/JIRA_API_TOKEN env vars, or
-- the file written by :JiraAuth. GitHub uses the authenticated `gh` CLI.
---------------------------------------------------------------------------

local config = require("plugins.utils.devops.config")
config.setup(vim.g.devops or {})

local dashboard = require("plugins.utils.devops.ui.dashboard")
local health = require("plugins.utils.devops.health")
local auth = require("plugins.utils.devops.jira.auth")
local client = require("plugins.utils.devops.jira.client")

vim.api.nvim_create_user_command("JiraAuth", function()
  auth.setup_interactive(function()
    vim.notify("JiraAuth: saved to " .. auth.file() .. " — verifying…", vim.log.levels.INFO)
    client.myself(function(ok, data, err)
      if ok then
        vim.notify("JiraAuth: connected as " .. (data and data.displayName or "?"), vim.log.levels.INFO)
      else
        vim.notify("JiraAuth: saved, but auth check failed — " .. (err or "?"), vim.log.levels.WARN)
      end
    end)
  end)
end, { desc = "Set up Jira credentials" })

vim.api.nvim_create_user_command("JiraAuthClear", function()
  if auth.clear() then
    vim.notify("JiraAuth: stored credentials removed", vim.log.levels.INFO)
  else
    vim.notify("JiraAuth: failed to remove credentials", vim.log.levels.ERROR)
  end
end, { desc = "Remove stored Jira credentials" })

vim.api.nvim_create_user_command("DevOps", function() dashboard.open() end,
  { desc = "Open DevOps (Jira + GitHub)" })
vim.api.nvim_create_user_command("DevOpsTab", function() dashboard.open("tab") end,
  { desc = "Open DevOps in a new tab" })
vim.api.nvim_create_user_command("DevOpsHealth", function() health.run() end,
  { desc = "DevOps health report" })

local open_key = config.options.keys and config.options.keys.open
if open_key and open_key ~= "" then
  vim.keymap.set("n", open_key, "<cmd>DevOps<cr>", { desc = "DevOps (Jira + GitHub)" })
end

-- Warm the persisted section cache during idle so the first open is instant.
if dashboard.preload_cache then vim.schedule(dashboard.preload_cache) end

return {}
