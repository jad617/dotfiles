---------------------------------------------------------------------------
-- DevOps configuration
--
-- Override from your config BEFORE plugins load (e.g. in lua/config/options.lua):
--
--   vim.g.devops = {
--     jira = { project = "DEVOPS" },   -- or jql = "project in (A,B) ..."
--     layout = "float",                -- "float" | "tab"
--     ui = { theme = "auto" },         -- follow the colorscheme (see M.defaults.ui)
--     keys = { open = "<leader>dev" },
--   }
---------------------------------------------------------------------------

local M = {}

M.defaults = {
  jira = {
    project = nil, -- e.g. "DEVOPS"; nil => rely on `jql` or just assignee filter
    jql = nil,     -- raw JQL override; when set it fully replaces the default query
    page_size = 100, -- board/sprint views include Done; 50 dropped older Done tickets
    branch_format = "feature/{key}-{slug}", -- 'B' branch name; also {type} = fix|feature

  },
  github = {
    enabled = true,
    pr_limit = 30,
    org = nil, -- org for the scoped PR search (S); default: the org your gh token's account belongs to
    poll_interval = 120, -- seconds between background checks for review requests (0 = off)
  },
  layout = "float", -- "float" | "tab"
  ui = {
    theme = "devops", -- "devops" (built-in palette) | "auto" (link to your colorscheme's groups)
    highlights = {},  -- per-group overrides, e.g. { DevOpsChip = { link = "Visual" } }
    -- Issue-type styles by name (case-insensitive): { bug = { icon = "", hl = "DevOpsErr" } }
    issue_types = {},
    -- Status icons: by status name (case-insensitive) or category ("new" | "indeterminate" | "done").
    status_icons = {},
    detail_tabs = true, -- split issue / PR details into tabs (<Tab> / <S-Tab>)
    diff_overscroll = 2, -- scrolls past a file's edge (after the stop) to flip to the next/prev file
  },
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
