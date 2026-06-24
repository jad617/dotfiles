---------------------------------------------------------------------------
-- DevOps configuration
--
-- Override from your config BEFORE plugins load (e.g. in lua/config/options.lua):
--
--   vim.g.devops = {
--     jira = { project = "DEVOPS" },   -- or jql = "project in (A,B) ..."
--     layout = "float",                -- "float" | "tab"
--     keys = { open = "<leader>dev" },
--   }
---------------------------------------------------------------------------

local M = {}

M.defaults = {
  jira = {
    project = nil, -- e.g. "DEVOPS"; nil => rely on `jql` or just assignee filter
    jql = nil,     -- raw JQL override; when set it fully replaces the default query
    page_size = 100, -- board/sprint views include Done; 50 dropped older Done tickets

  },
  github = {
    enabled = true,
    pr_limit = 30,
  },
  layout = "float", -- "float" | "tab"
  keys = { open = "<leader>dev" },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M
