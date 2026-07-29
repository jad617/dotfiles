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
  diff = {
    -- Side-split git diff (follow-current-file mode) behaviour.
    live = true,     -- true: update as you type, without saving. false: refresh on save only.
    debounce = 150,  -- ms to wait after a keystroke before re-diffing (live mode)
    follow = true,   -- scroll the split to the line your cursor is on (f toggles in the split)
  },
  keys = {
    open = "<leader>dev",
    diff = "<leader>dv",      -- git diff side split, follows the current buffer
    diff_all = "<leader>dV",  -- git diff side split, all changed files
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M
