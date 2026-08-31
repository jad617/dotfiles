---------------------------------------------------------------------------
-- Rendering helpers: highlight groups, icons, column padding.
---------------------------------------------------------------------------

local M = {}

M.ns = vim.api.nvim_create_namespace("DevOps")

---------------------------------------------------------------------------
-- Diff colour themes
---------------------------------------------------------------------------

local diff_themes = {
  { name = "Tokyo Night", hl = {
    DevOpsDiffFileHdr  = { fg = "#e0af68", bg = "#292e42" },
    DevOpsDiffHunkHdr  = { fg = "#7aa2f7", bg = "#1f2335" },
    DevOpsDiffAdd      = { fg = "#9ece6a", bg = "#1e3326" },
    DevOpsDiffDel      = { fg = "#f7768e", bg = "#332028" },
    DevOpsDiffAddSign  = { fg = "#73daca", bg = "#1e3326", bold = true },
    DevOpsDiffDelSign  = { fg = "#f7768e", bg = "#332028", bold = true },
    DevOpsDiffEmpty    = { fg = "#3b4261", bg = "#1e1e2e" },
    DevOpsDiffCtx      = { fg = "#565f89" },
    DevOpsDiffLineNr   = { fg = "#3b4261" },
    DevOpsDiffBar      = { fg = "#a9b1d6", bg = "#1f2335" },
    DevOpsDiffSep      = { fg = "#e0af68", bg = "#292e42" },
    DevOpsDiffFileGap  = { bg = "#16161e" },
  }},
  { name = "Pastel", hl = {
    DevOpsDiffFileHdr  = { fg = "#e0af68", bg = "#292e42" },
    DevOpsDiffHunkHdr  = { fg = "#7aa2f7", bg = "#1f2335" },
    DevOpsDiffAdd      = { fg = "#1a1b26", bg = "#99bc80" },
    DevOpsDiffDel      = { fg = "#f7768e", bg = "#332028" },
    DevOpsDiffAddSign  = { fg = "#1a1b26", bg = "#99bc80", bold = true },
    DevOpsDiffDelSign  = { fg = "#f7768e", bg = "#332028", bold = true },
    DevOpsDiffEmpty    = { fg = "#3b4261", bg = "#1e1e2e" },
    DevOpsDiffCtx      = { fg = "#565f89" },
    DevOpsDiffLineNr   = { fg = "#3b4261" },
    DevOpsDiffBar      = { fg = "#a9b1d6", bg = "#1f2335" },
    DevOpsDiffSep      = { fg = "#e0af68", bg = "#292e42" },
    DevOpsDiffFileGap  = { bg = "#16161e" },
  }},
}

local _diff_theme_idx = 1

function M.apply_diff_theme(idx)
  if idx then _diff_theme_idx = idx end
  local theme = diff_themes[_diff_theme_idx] or diff_themes[1]
  for name, val in pairs(theme.hl) do vim.api.nvim_set_hl(0, name, val) end
end

function M.cycle_diff_theme(delta)
  _diff_theme_idx = ((_diff_theme_idx - 1 + (delta or 1)) % #diff_themes) + 1
  M.apply_diff_theme()
  return diff_themes[_diff_theme_idx].name
end

function M.diff_theme_name()
  return diff_themes[_diff_theme_idx].name
end

---------------------------------------------------------------------------
-- Core highlight groups
---------------------------------------------------------------------------

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
    DevOpsColumnNew      = { fg = "#7dcfff", bold = true },
    DevOpsColumnTodo     = { fg = "#9aa5ce", bold = true },
    DevOpsColumnHold     = { fg = "#ff9e64", bold = true },
    DevOpsColumnProgress = { fg = "#e0af68", bold = true },
    DevOpsColumnReview   = { fg = "#bb9af7", bold = true },
    DevOpsColumnQa       = { fg = "#f7768e", bold = true },
    DevOpsColumnMonitor  = { fg = "#7aa2f7", bold = true },
    DevOpsColumnDone     = { fg = "#9ece6a", bold = true },
    DevOpsCount          = { fg = "#565f89" },
    DevOpsIcon           = { fg = "#7aa2f7" },
    DevOpsBorder         = { fg = "#3b4261" },
    DevOpsBorderActive   = { fg = "#99bc80" },
    DevOpsWinbar         = { fg = "#ff8050", bold = true },
    DevOpsBadge          = { fg = "#ff8050" },
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
    DevOpsMdHeader       = { fg = "#7aa2f7", bold = true },
    DevOpsMdBold         = { bold = true },
    DevOpsMdItalic       = { italic = true },
    DevOpsMdCode         = { fg = "#9ece6a", bg = "#1f2335" },
    DevOpsMdCodeBlock    = { fg = "#9ece6a", bg = "#1f2335" },
    DevOpsMdListBullet   = { fg = "#e0af68", bold = true },
    DevOpsMdQuote        = { fg = "#787c99", italic = true },
  }
  for name, val in pairs(hls) do vim.api.nvim_set_hl(0, name, val) end
  M.apply_diff_theme()
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
-- Also accepts an optional column name for finer-grained coloring.
function M.column_hl(category_key, col_name)
  local name = col_name and col_name:upper() or ""
  if name:find("DONE") then return "DevOpsColumnDone" end
  if name:find("PROGRESS") then return "DevOpsColumnProgress" end
  if name:find("NEW") then return "DevOpsColumnNew" end
  if name:find("TO DO") or name:find("TODO") then return "DevOpsColumnTodo" end
  if name:find("HOLD") then return "DevOpsColumnHold" end
  if name:find("REVIEW") then return "DevOpsColumnReview" end
  if name:find("QA") then return "DevOpsColumnQa" end
  if name:find("MONITOR") then return "DevOpsColumnMonitor" end
  -- Fallback to category
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
  -- Truncate on character boundaries by display width (reserve 1 col for …),
  -- so multibyte text isn't cut mid-character and the result fits exactly.
  local budget = math.max(0, w - 1)
  local out, width = {}, 0
  for _, ch in ipairs(vim.fn.split(s, "\\zs")) do
    local cw = vim.fn.strdisplaywidth(ch)
    if width + cw > budget then break end
    out[#out + 1] = ch
    width = width + cw
  end
  return table.concat(out) .. "…"
end

function M.pad(s, w)
  s = s or ""
  local diff = w - vim.fn.strdisplaywidth(s)
  return diff > 0 and (s .. string.rep(" ", diff)) or s
end

-- Truncate then pad to exactly `w` display columns (for aligned columns).
function M.fit(s, w)
  return M.pad(M.truncate(s, w), w)
end

---------------------------------------------------------------------------
-- Time helpers
--
-- os.time() interprets a broken-down table as *local* time, so feeding it the
-- UTC fields of an ISO 8601 string silently shifts the result by the local UTC
-- offset (and again by an hour whenever the isdst flag disagrees). We convert
-- the calendar date to a day count directly instead, which is exact and has no
-- libc timezone/DST involvement at all.
---------------------------------------------------------------------------

-- Days since 1970-01-01 for a proleptic Gregorian date (Howard Hinnant's
-- days_from_civil). Valid for any year in the supported range.
local function days_from_civil(y, m, d)
  y = y - (m <= 2 and 1 or 0)
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end

-- Parse an ISO 8601 timestamp to a Unix epoch, honouring a trailing "Z" or
-- "+HH:MM" / "-HHMM" offset. Returns nil when the string isn't parseable.
function M.iso_to_epoch(iso)
  if type(iso) ~= "string" or iso == "" then return nil end
  local y, mo, d, h, mi, s = iso:match("^(%d%d%d%d)-(%d%d)-(%d%d)[T ](%d%d):(%d%d):(%d%d)")
  if not y then return nil end
  local epoch = days_from_civil(tonumber(y), tonumber(mo), tonumber(d)) * 86400
    + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(s)
  -- A "-0400" stamp is behind UTC, so its UTC epoch is *later* by the offset.
  local sign, oh, om = iso:match("([+%-])(%d%d):?(%d%d)%s*$")
  if sign then
    local off = tonumber(oh) * 3600 + tonumber(om) * 60
    epoch = epoch + (sign == "-" and off or -off)
  end
  return epoch
end

-- Coarse age label used by list rows: "3h ago", "2 days ago", "5 months ago".
function M.time_ago(iso)
  local ts = M.iso_to_epoch(iso)
  if not ts then return "?" end
  local diff = os.time() - ts
  if diff < 0 then diff = 0 end
  if diff < 60 then return "just now" end
  if diff < 3600 then return math.floor(diff / 60) .. "m ago" end
  if diff < 86400 then return math.floor(diff / 3600) .. "h ago" end
  local days = math.floor(diff / 86400)
  if days == 1 then return "1 day ago" end
  if days < 30 then return days .. " days ago" end
  return math.floor(days / 30) .. " months ago"
end

-- Compact age label used by detail cards; falls back to an absolute date once
-- the timestamp is more than a week old.
function M.format_time(iso)
  if not iso or iso == "" then return "" end
  local ts = M.iso_to_epoch(iso)
  if not ts then return iso:sub(1, 10) end
  local diff = os.time() - ts
  if diff < 0 then diff = 0 end
  if diff < 60 then return "just now" end
  if diff < 3600 then return math.floor(diff / 60) .. "m ago" end
  if diff < 86400 then return math.floor(diff / 3600) .. "h ago" end
  if diff < 604800 then return math.floor(diff / 86400) .. "d ago" end
  return os.date("!%Y-%m-%d", ts)
end

return M
