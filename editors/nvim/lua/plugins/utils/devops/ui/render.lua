---------------------------------------------------------------------------
-- Rendering helpers: highlight groups, icons, column padding.
---------------------------------------------------------------------------

local M = {}

M.ns = vim.api.nvim_create_namespace("DevOps")

---------------------------------------------------------------------------
-- Diff colour themes
---------------------------------------------------------------------------

local diff_themes = {
  { name = "One Dark Muted", hl = {
    DevOpsDiffFileHdr  = { fg = "#e5c07b", bg = "#3e4452", bold = true },
    DevOpsDiffHunkHdr  = { fg = "#61afef", bg = "#2c313c" },
    DevOpsDiffAdd      = { fg = "#c8d3c0", bg = "#2b3a2f" },
    DevOpsDiffDel      = { fg = "#d7b8bb", bg = "#3d2b30" },
    DevOpsDiffAddSign  = { fg = "#98c379", bg = "#2b3a2f", bold = true },
    DevOpsDiffDelSign  = { fg = "#e06c75", bg = "#3d2b30", bold = true },
    DevOpsDiffEmpty    = { fg = "#3e4452", bg = "#21252b" },
    DevOpsDiffCtx      = { fg = "#8b929e" },
    DevOpsDiffLineNr   = { fg = "#4b5263" },
    DevOpsDiffBar      = { fg = "#abb2bf", bg = "#2c313c" },
    DevOpsDiffSep      = { fg = "#e5c07b", bg = "#3e4452" },
    DevOpsDiffFileGap  = { bg = "#1b1f24" },
  }},
  { name = "GitHub Dark", hl = {
    DevOpsDiffFileHdr  = { fg = "#e6edf3", bg = "#21262d", bold = true },
    DevOpsDiffHunkHdr  = { fg = "#8b949e", bg = "#121d2f" },
    DevOpsDiffAdd      = { fg = "#e6edf3", bg = "#12261e" },
    DevOpsDiffDel      = { fg = "#e6edf3", bg = "#25171c" },
    DevOpsDiffAddSign  = { fg = "#3fb950", bg = "#12261e", bold = true },
    DevOpsDiffDelSign  = { fg = "#f85149", bg = "#25171c", bold = true },
    DevOpsDiffEmpty    = { fg = "#30363d", bg = "#161b22" },
    DevOpsDiffCtx      = { fg = "#9da5ae" },
    DevOpsDiffLineNr   = { fg = "#484f58" },
    DevOpsDiffBar      = { fg = "#c9d1d9", bg = "#161b22" },
    DevOpsDiffSep      = { fg = "#8b949e", bg = "#21262d" },
    DevOpsDiffFileGap  = { bg = "#010409" },
  }},
  { name = "Catppuccin Mocha", hl = {
    DevOpsDiffFileHdr  = { fg = "#fab387", bg = "#45475a", bold = true },
    DevOpsDiffHunkHdr  = { fg = "#89b4fa", bg = "#313244" },
    DevOpsDiffAdd      = { fg = "#cdd6f4", bg = "#283b33" },
    DevOpsDiffDel      = { fg = "#cdd6f4", bg = "#3c2a35" },
    DevOpsDiffAddSign  = { fg = "#a6e3a1", bg = "#283b33", bold = true },
    DevOpsDiffDelSign  = { fg = "#f38ba8", bg = "#3c2a35", bold = true },
    DevOpsDiffEmpty    = { fg = "#45475a", bg = "#181825" },
    DevOpsDiffCtx      = { fg = "#9399b2" },
    DevOpsDiffLineNr   = { fg = "#585b70" },
    DevOpsDiffBar      = { fg = "#bac2de", bg = "#313244" },
    DevOpsDiffSep      = { fg = "#fab387", bg = "#45475a" },
    DevOpsDiffFileGap  = { bg = "#11111b" },
  }},
  { name = "Nord", hl = {
    DevOpsDiffFileHdr  = { fg = "#88c0d0", bg = "#434c5e", bold = true },
    DevOpsDiffHunkHdr  = { fg = "#81a1c1", bg = "#3b4252" },
    DevOpsDiffAdd      = { fg = "#d8dee9", bg = "#334039" },
    DevOpsDiffDel      = { fg = "#d8dee9", bg = "#40343a" },
    DevOpsDiffAddSign  = { fg = "#a3be8c", bg = "#334039", bold = true },
    DevOpsDiffDelSign  = { fg = "#bf616a", bg = "#40343a", bold = true },
    DevOpsDiffEmpty    = { fg = "#434c5e", bg = "#2b303b" },
    DevOpsDiffCtx      = { fg = "#8a94a8" },
    DevOpsDiffLineNr   = { fg = "#4c566a" },
    DevOpsDiffBar      = { fg = "#d8dee9", bg = "#3b4252" },
    DevOpsDiffSep      = { fg = "#88c0d0", bg = "#434c5e" },
    DevOpsDiffFileGap  = { bg = "#242933" },
  }},
  { name = "Minimal", hl = {
    DevOpsDiffFileHdr  = { fg = "#e5c07b", bg = "#3a3f4b", bold = true },
    DevOpsDiffHunkHdr  = { fg = "#61afef", italic = true },
    DevOpsDiffAdd      = { fg = "#98c379" },
    DevOpsDiffDel      = { fg = "#c26d75" },
    DevOpsDiffAddSign  = { fg = "#98c379", bold = true },
    DevOpsDiffDelSign  = { fg = "#e06c75", bold = true },
    DevOpsDiffEmpty    = { fg = "#3a3f4b" },
    DevOpsDiffCtx      = { fg = "#7f848e" },
    DevOpsDiffLineNr   = { fg = "#4b5263" },
    DevOpsDiffBar      = { fg = "#abb2bf", bg = "#2c313c" },
    DevOpsDiffSep      = { fg = "#5c6370", bg = "#3a3f4b" },
    DevOpsDiffFileGap  = { bg = "#1b1f24" },
  }},
  { name = "High Contrast", hl = {
    DevOpsDiffFileHdr  = { fg = "#1a1a1a", bg = "#e5c07b", bold = true },
    DevOpsDiffHunkHdr  = { fg = "#1a1a1a", bg = "#61afef", bold = true },
    DevOpsDiffAdd      = { fg = "#ffffff", bg = "#1f4d2a" },
    DevOpsDiffDel      = { fg = "#ffffff", bg = "#5c1f26" },
    DevOpsDiffAddSign  = { fg = "#7ee787", bg = "#1f4d2a", bold = true },
    DevOpsDiffDelSign  = { fg = "#ff7b72", bg = "#5c1f26", bold = true },
    DevOpsDiffEmpty    = { fg = "#555555", bg = "#111111" },
    DevOpsDiffCtx      = { fg = "#c8ccd4" },
    DevOpsDiffLineNr   = { fg = "#6b7280" },
    DevOpsDiffBar      = { fg = "#ffffff", bg = "#333333" },
    DevOpsDiffSep      = { fg = "#1a1a1a", bg = "#e5c07b" },
    DevOpsDiffFileGap  = { bg = "#000000" },
  }},
  { name = "Vivid", hl = {
    DevOpsDiffFileHdr  = { fg = "#1e2127", bg = "#c8a86b", bold = true },
    DevOpsDiffHunkHdr  = { fg = "#7cb8f0", bg = "#263445", bold = true },
    DevOpsDiffAdd      = { fg = "#e8f5e0", bg = "#3a6643" },
    DevOpsDiffDel      = { fg = "#fbe3e5", bg = "#6e3138" },
    DevOpsDiffAddSign  = { fg = "#b5e8a0", bg = "#3a6643", bold = true },
    DevOpsDiffDelSign  = { fg = "#ffa0a8", bg = "#6e3138", bold = true },
    DevOpsDiffEmpty    = { fg = "#3e4452", bg = "#1a1d22" },
    DevOpsDiffCtx      = { fg = "#a9b1bd" },
    DevOpsDiffLineNr   = { fg = "#5c6370" },
    DevOpsDiffBar      = { fg = "#e6e6e6", bg = "#2f343d" },
    DevOpsDiffSep      = { fg = "#1e2127", bg = "#c8a86b" },
    DevOpsDiffFileGap  = { bg = "#0f1115" },
  }},
  { name = "Tokyo Bloom", hl = {
    DevOpsDiffFileHdr  = { fg = "#ffc777", bg = "#3b4261", bold = true },
    DevOpsDiffHunkHdr  = { fg = "#82aaff", bg = "#24283b", bold = true },
    DevOpsDiffAdd      = { fg = "#e6f2dc", bg = "#4a6b4c" },
    DevOpsDiffDel      = { fg = "#ffd9df", bg = "#5a2e3a" },
    DevOpsDiffAddSign  = { fg = "#c3e88d", bg = "#4a6b4c", bold = true },
    DevOpsDiffDelSign  = { fg = "#ff9eae", bg = "#5a2e3a", bold = true },
    DevOpsDiffEmpty    = { fg = "#3b4261", bg = "#1a1b26" },
    DevOpsDiffCtx      = { fg = "#828bb8" },
    DevOpsDiffLineNr   = { fg = "#545c7e" },
    DevOpsDiffBar      = { fg = "#c0caf5", bg = "#24283b" },
    DevOpsDiffSep      = { fg = "#ffc777", bg = "#3b4261" },
    DevOpsDiffFileGap  = { bg = "#13141c" },
  }},
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

local function theme_index(name)
  for i, t in ipairs(diff_themes) do
    if t.name == name then return i end
  end
end

-- Saved default (picker 'd'); falls back to the first theme.
local function default_theme_idx()
  local ok, store = pcall(require, "plugins.utils.devops.store")
  local name = ok and store.load_diff_theme() or nil
  return (name and theme_index(name)) or 1
end
_diff_theme_idx = default_theme_idx()

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

--- Small float listing the diff themes. Moving the cursor previews the theme
--- live (extmarks reference the hl groups by name, so open diffs recolor);
--- <CR> keeps it, d saves it as the default, q/<Esc> restores the previous one.
--- @param on_change fun(name: string)|nil called after every applied change
function M.pick_diff_theme(on_change)
  local orig_idx, prev_win = _diff_theme_idx, vim.api.nvim_get_current_win()
  local default_idx = default_theme_idx()
  local ns = vim.api.nvim_create_namespace("DevOpsThemePicker")
  local footer = " ↵ select · d default · esc cancel "
  local lines, width = {}, 0
  local function line_for(i)
    return "  +  -  ▌ " .. diff_themes[i].name .. (i == default_idx and "  ★ " or " ")
  end
  for i, t in ipairs(diff_themes) do
    for _, k in ipairs({ "Add", "Del", "FileHdr" }) do
      vim.api.nvim_set_hl(0, "DevOpsThemeSwatch" .. i .. k, t.hl["DevOpsDiff" .. k] or {})
    end
    lines[i] = line_for(i)
    width = math.max(width, vim.api.nvim_strwidth(lines[i]) + 2)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local function draw()
    for i in ipairs(diff_themes) do lines[i] = line_for(i) end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for i in ipairs(diff_themes) do
      local l = i - 1
      vim.api.nvim_buf_set_extmark(buf, ns, l, 1, { end_col = 4, hl_group = "DevOpsThemeSwatch" .. i .. "Add" })
      vim.api.nvim_buf_set_extmark(buf, ns, l, 4, { end_col = 7, hl_group = "DevOpsThemeSwatch" .. i .. "Del" })
      vim.api.nvim_buf_set_extmark(buf, ns, l, 8, { end_col = 11, hl_group = "DevOpsThemeSwatch" .. i .. "FileHdr" })
      if i == default_idx then
        local s = #lines[i] - #"★ "
        vim.api.nvim_buf_set_extmark(buf, ns, l, s, { end_col = s + #"★", hl_group = "DevOpsWarn" })
      end
    end
  end
  draw()

  width = math.max(width, vim.api.nvim_strwidth(footer) + 2)
  local height = #lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal", border = "rounded", zindex = 250,
    title = " Diff theme ", title_pos = "center",
    footer = footer, footer_pos = "center",
  })
  vim.wo[win].cursorline = true
  vim.wo[win].winhighlight = "Normal:Normal,FloatBorder:DevOpsBorder,FloatTitle:DevOpsTitle"
  vim.api.nvim_win_set_cursor(win, { _diff_theme_idx, 0 })

  local function apply(idx)
    if idx == _diff_theme_idx then return end
    M.apply_diff_theme(idx)
    if on_change then on_change(diff_themes[idx].name) end
  end
  local done = false
  local function finish(keep)
    if done then return end
    done = true
    if keep then
      apply(vim.api.nvim_win_get_cursor(win)[1])
    else
      apply(orig_idx)
    end
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if vim.api.nvim_win_is_valid(prev_win) then vim.api.nvim_set_current_win(prev_win) end
    if keep then
      local label = _diff_theme_idx == default_idx and "Diff theme (default): " or "Diff theme: "
      vim.notify(label .. M.diff_theme_name(), vim.log.levels.INFO, { title = "DevOps" })
    end
  end

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    callback = function() apply(vim.api.nvim_win_get_cursor(win)[1]) end,
  })
  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
    buffer = buf, once = true,
    callback = function() finish(false) end,
  })
  local o = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "<CR>", function() finish(true) end, o)
  -- Save the highlighted theme as the default for future sessions, and keep it.
  vim.keymap.set("n", "d", function()
    local idx = vim.api.nvim_win_get_cursor(win)[1]
    local ok, store = pcall(require, "plugins.utils.devops.store")
    if not (ok and store.save_diff_theme(diff_themes[idx].name)) then
      return vim.notify("DevOps: couldn't save default diff theme", vim.log.levels.ERROR)
    end
    default_idx = idx
    draw()
    finish(true)
  end, o)
  for _, k in ipairs({ "q", "<Esc>", "T" }) do
    vim.keymap.set("n", k, function() finish(false) end, o)
  end
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
