---------------------------------------------------------------------------
-- Rendering helpers: highlight groups, icons, column padding.
---------------------------------------------------------------------------

local M = {}

M.ns = vim.api.nvim_create_namespace("DevOps")

local function set_hl()
  local hls = {
    DevOpsTitle          = { fg = "#99bc80", bold = true },
    DevOpsSection        = { fg = "#7aa2f7", bold = true },
    DevOpsSectionActive  = { fg = "#99bc80", bold = true },
    DevOpsSectionBar     = { fg = "#99bc80", bold = true },
    DevOpsGroup          = { fg = "#565f89", bold = true },
    DevOpsKey            = { fg = "#e0af68" },
    DevOpsDim            = { fg = "#565f89" },
    DevOpsId             = { fg = "#7dcfff", bold = true },
    DevOpsStatusTodo     = { fg = "#9aa5ce" },
    DevOpsStatusProgress = { fg = "#e0af68" },
    DevOpsStatusDone     = { fg = "#9ece6a" },
    DevOpsPrOpen         = { fg = "#9ece6a" },
    DevOpsPrDraft        = { fg = "#565f89" },
    DevOpsLabel          = { fg = "#7aa2f7" },
    DevOpsColumn         = { fg = "#bb9af7", bold = true },
    DevOpsColumnTodo     = { fg = "#9aa5ce", bold = true },
    DevOpsColumnProgress = { fg = "#e0af68", bold = true },
    DevOpsColumnDone     = { fg = "#9ece6a", bold = true },
    DevOpsCount          = { fg = "#565f89" },
    DevOpsIcon           = { fg = "#7aa2f7" },
    DevOpsBorder         = { fg = "#3b4261" },
    DevOpsBorderActive   = { fg = "#99bc80" },
    DevOpsCommentBorder  = { fg = "#7aa2f7" },
    DevOpsReplyBorder    = { fg = "#e0af68" },
    DevOpsReplyLabel     = { fg = "#e0af68", bold = true },
    DevOpsDetailTitle    = { fg = "#c0caf5", bold = true },
    DevOpsSectionHead    = { fg = "#7aa2f7", bold = true },
    DevOpsOk             = { fg = "#9ece6a" },
    DevOpsErr            = { fg = "#f7768e" },
    DevOpsWarn           = { fg = "#e0af68" },
    DevOpsPill           = { fg = "#1a1b26", bg = "#7aa2f7", bold = true },
    DevOpsAction         = { fg = "#f7768e" },
    -- Diff viewer
    DevOpsDiffFileHdr    = { fg = "#e0af68", bg = "#292e42" },
    DevOpsDiffHunkHdr    = { fg = "#7aa2f7", bg = "#1f2335" },
    DevOpsDiffAdd        = { fg = "#9ece6a", bg = "#1e3326" },
    DevOpsDiffDel        = { fg = "#f7768e", bg = "#332028" },
    DevOpsDiffAddSign    = { fg = "#73daca", bg = "#1e3326", bold = true },
    DevOpsDiffDelSign    = { fg = "#f7768e", bg = "#332028", bold = true },
    DevOpsDiffEmpty      = { fg = "#3b4261", bg = "#1e1e2e" },
    DevOpsDiffCtx        = { fg = "#565f89" },
    DevOpsDiffLineNr     = { fg = "#3b4261" },
    DevOpsDiffBar        = { fg = "#a9b1d6", bg = "#1f2335" },
  }
  for name, val in pairs(hls) do vim.api.nvim_set_hl(0, name, val) end
end
set_hl()
vim.api.nvim_create_autocmd("ColorScheme", { callback = set_hl })

-- Jira statusCategory key → status text highlight group.
function M.status_hl(category_key)
  if category_key == "done" then return "DevOpsStatusDone" end
  if category_key == "indeterminate" then return "DevOpsStatusProgress" end
  return "DevOpsStatusTodo"
end

-- Jira statusCategory key → column header highlight group.
function M.column_hl(category_key)
  if category_key == "done" then return "DevOpsColumnDone" end
  if category_key == "indeterminate" then return "DevOpsColumnProgress" end
  return "DevOpsColumn"
end

local TYPE_ICON = {
  Story = "", Task = "", Bug = "", Epic = "", ["Sub-task"] = "", Subtask = "",
}
function M.issue_icon(type_name) return TYPE_ICON[type_name] or "" end

function M.truncate(s, w)
  s = s or ""
  if vim.fn.strdisplaywidth(s) <= w then return s end
  return s:sub(1, math.max(0, w - 1)) .. "…"
end

function M.pad(s, w)
  s = s or ""
  local diff = w - vim.fn.strdisplaywidth(s)
  return diff > 0 and (s .. string.rep(" ", diff)) or s
end

return M
