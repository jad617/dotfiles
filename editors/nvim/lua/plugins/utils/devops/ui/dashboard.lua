---------------------------------------------------------------------------
-- DevOps dashboard — sidebar (sections) + content (list).
-- Opens as a float (default) or a tab. See config.layout.
---------------------------------------------------------------------------

local config = require("plugins.utils.devops.config")
local client = require("plugins.utils.devops.jira.client")
local api = require("plugins.utils.devops.jira.api")
local adf = require("plugins.utils.devops.jira.adf")
local gh = require("plugins.utils.devops.github.api")
local render = require("plugins.utils.devops.ui.render")
local detail = require("plugins.utils.devops.ui.detail")
local user_picker = require("plugins.utils.devops.ui.user_picker")
local input = require("plugins.utils.devops.ui.input")
local store = require("plugins.utils.devops.store")

local M = {}

local TABS = {
  { id = "jira", label = "Jira", icon = "", sections = {
    { id = "jira_issues", label = "My Issues" },
    { id = "jira_sprint", label = "Sprint Board" },
    { id = "jira_epics", label = "Epics" },
    { id = "jira_backlog", label = "Backlog" },
    { id = "jira_bookmarks", label = "Bookmarks" },
  } },
  { id = "github", label = "GitHub", icon = "", sections = {
    { id = "gh_prs", label = "My PRs" },
    { id = "gh_reviews", label = "Reviews" },
    { id = "gh_bookmarks", label = "Bookmarks" },
  } },
}

local SECTIONS = {}
for ti, tab in ipairs(TABS) do
  for si, sec in ipairs(tab.sections) do
    SECTIONS[#SECTIONS + 1] = {
      id = sec.id,
      label = sec.label,
      group = tab.label,
      tab_id = tab.id,
      tab_index = ti,
      section_index = si,
    }
  end
end

local state = {
  layout = "float",
  sidebar = { win = nil, buf = nil },
  content = { win = nil, buf = nil },
  footer = { win = nil, buf = nil },
  tab = 1,
  section = 1,
  jira_user = nil,   -- { account_id, name } or nil => current user
  project = nil,     -- { key, id, name }
  board = nil,       -- { id, name }
  sprint = nil,      -- { id, name } active sprint, or nil
  columns = nil,     -- ordered board columns, or nil for a flat list
  rows = {},         -- 1-based content line → item
  sidebar_rows = {}, -- 1-based sidebar line → local section index
  sidebar_line = nil,-- remembered sidebar cursor line
  content_cursor = nil, -- remembered content cursor {row,col}
  scope_override = nil, -- nil | "project" | "sprint"
  include_done = false, -- when true, include Done issues
  reviews_sort = "newest", -- "newest" | "oldest"
  nav_stack = {},    -- navigation stack: each entry = { cursor, rows, lines_snapshot }
  in_detail = false, -- true when showing a detail view in content pane
  detail_kind = nil, -- nil | "jira" | "pr"
  gh_notif_count = 0,
  bookmarks = {},
}

local function wrap_index(idx, count)
  if count <= 0 then return 1 end
  if idx < 1 then return count end
  if idx > count then return 1 end
  return idx
end

local function tab_index_by_id(tab_id)
  for i, tab in ipairs(TABS) do
    if tab.id == tab_id then return i end
  end
end

local function current_tab(tab_idx)
  return TABS[tab_idx or state.tab]
end

local function current_section(section_idx, tab_idx)
  local tab = current_tab(tab_idx)
  return tab and tab.sections[section_idx or state.section] or nil
end

local function current_tab_id()
  local tab = current_tab()
  return tab and tab.id or ""
end

local function current_section_id()
  local sec = current_section()
  return sec and sec.id or ""
end

local function current_section_label()
  local sec = current_section()
  return sec and sec.label or ""
end

local function section_count(tab_idx)
  local tab = current_tab(tab_idx)
  return tab and #tab.sections or 0
end

local function tab_title(tab)
  if not tab then return "" end
  if tab.icon and tab.icon ~= "" then
    return tab.icon .. " " .. tab.label
  end
  return tab.label
end

local function is_jira_section(sec_id)
  return sec_id == "jira_issues"
    or sec_id == "jira_sprint"
    or sec_id == "jira_epics"
    or sec_id == "jira_backlog"
end

---------------------------------------------------------------------------
-- Low-level buffer/window helpers
---------------------------------------------------------------------------
local function is_open()
  return state.content.win ~= nil and vim.api.nvim_win_is_valid(state.content.win)
end

local function make_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "devops"
  return buf
end

local function set_buf_lines(buf, lines)
  -- Sanitize: nvim_buf_set_lines rejects embedded newlines
  for i, l in ipairs(lines) do
    if l:find("\n") then lines[i] = l:gsub("\n", " ") end
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function apply_highlights(buf, hls)
  vim.api.nvim_buf_clear_namespace(buf, render.ns, 0, -1)
  for _, h in ipairs(hls or {}) do
    pcall(vim.api.nvim_buf_set_extmark, buf, render.ns, h.line, h.col_start, {
      end_col = h.col_end,
      hl_group = h.hl,
    })
  end
end

local function content_width()
  if is_open() then return vim.api.nvim_win_get_width(state.content.win) end
  return 80
end

local NUM_BADGE = { "❶", "❷", "❸", "❹", "❺", "❻", "❼", "❽", "❾" }

local function update_sidebar_winbar()
  if not state.sidebar.win or not vim.api.nvim_win_is_valid(state.sidebar.win) then return end
  local parts = {}
  for i, tab in ipairs(TABS) do
    local hl = (i == state.tab) and "%#DevOpsWinbar#" or "%#DevOpsGroup#"
    local piece = hl .. " " .. tab_title(tab)
    if tab.id == "github" and state.gh_notif_count > 0 then
      piece = piece .. " %#DevOpsErr#" .. tostring(state.gh_notif_count) .. hl
    end
    parts[#parts + 1] = piece .. " "
  end
  vim.wo[state.sidebar.win].winbar = table.concat(parts, "%#DevOpsBorder#│") .. "%*"
end

local function update_winbar()
  if not state.content.win or not vim.api.nvim_win_is_valid(state.content.win) then return end
  local tab = current_tab()
  local sec = current_section()
  if not tab or not sec then return end
  local icon = tab.icon and tab.icon ~= "" and (tab.icon .. " ") or ""
  local bar = " " .. icon .. tab.label .. " › " .. sec.label

  -- Jira context: project · scope
  if tab.id == "jira" then
    local parts = {}
    if state.project then parts[#parts + 1] = state.project.key end
    if state.sprint then
      if state.scope_override == "project" then
        parts[#parts + 1] = "project"
      else
        parts[#parts + 1] = "sprint"
      end
    end
    if state.include_done then parts[#parts + 1] = "+Done" end
    if #parts > 0 then
      bar = bar .. "  ·  " .. table.concat(parts, "  ·  ")
    end
  end

  bar = bar .. " "
  vim.wo[state.content.win].winbar = "%#DevOpsWinbar#" .. bar .. "%*"
end

-- Sidebar buffer line for a given section index (defined early: used by
-- switch_section above and the pane-focus helpers below).
local function sidebar_line_for_section(idx)
  for line, s in pairs(state.sidebar_rows or {}) do
    if s == idx then return line end
  end
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

local function render_sidebar()
  local lines, hls, rows = {}, {}, {}
  local tab = current_tab()
  local function push(text, hl)
    lines[#lines + 1] = text
    if hl then hls[#hls + 1] = { line = #lines - 1, col_start = 0, col_end = #text, hl = hl } end
  end

  push("")
  push("   DEVOPS", "DevOpsTitle")
  if tab and tab.id == "jira" then
    local parts = {}
    if state.project then parts[#parts + 1] = state.project.key end
    if state.sprint then parts[#parts + 1] = (state.scope_override == "project") and "project" or "sprint" end
    if state.include_done then parts[#parts + 1] = "+Done" end
    if #parts > 0 then
      push("   " .. table.concat(parts, " · "), "DevOpsDim")
    end
  end
  push("")

  for i, sec in ipairs(tab and tab.sections or {}) do
    local active = (i == state.section)
    local badge = NUM_BADGE[i] or tostring(i)
    local text = (active and "  ▌ " or "    ") .. badge .. " " .. sec.label
    local badge_start = 4
    local badge_end = badge_start + #badge
    local label_start = badge_end + 1
    lines[#lines + 1] = text
    rows[#lines] = i
    if active then
      hls[#hls + 1] = { line = #lines - 1, col_start = 0, col_end = label_start - 1, hl = "DevOpsSectionBar" }
      hls[#hls + 1] = { line = #lines - 1, col_start = badge_start, col_end = badge_end, hl = "DevOpsBadge" }
      hls[#hls + 1] = { line = #lines - 1, col_start = label_start, col_end = #text, hl = "DevOpsSectionActive" }
    else
      hls[#hls + 1] = { line = #lines - 1, col_start = 0, col_end = 4, hl = "DevOpsDim" }
      hls[#hls + 1] = { line = #lines - 1, col_start = badge_start, col_end = badge_end, hl = "DevOpsBadge" }
      hls[#hls + 1] = { line = #lines - 1, col_start = label_start, col_end = #text, hl = "DevOpsSection" }
    end
  end

  push("")
  push("  ? help", "DevOpsDim")

  set_buf_lines(state.sidebar.buf, lines)
  apply_highlights(state.sidebar.buf, hls)
  state.sidebar_rows = rows
  -- Keep the sidebar cursor (and its green cursorline) on the active section, so
  -- the highlight follows when switching sections with Tab.
  if state.sidebar.win and vim.api.nvim_win_is_valid(state.sidebar.win) then
    local ln = sidebar_line_for_section(state.section)
    if ln then pcall(vim.api.nvim_win_set_cursor, state.sidebar.win, { ln, 0 }) end
  end
  update_sidebar_winbar()
end

---------------------------------------------------------------------------
-- Footer bar — always-visible 2-line key legend at the bottom.
---------------------------------------------------------------------------
local footer_ns = vim.api.nvim_create_namespace("DevOpsFooter")

local function render_footer()
  if not state.footer.buf or not vim.api.nvim_buf_is_valid(state.footer.buf) then return end
  local sec_id = current_section_id()
  local local_sections = tostring(section_count())
  local groups

  if state.in_detail then
    -- Detail view footer
    if state.detail_kind == "jira" then
      groups = {
        { "Navigate", { "q back", "BS back", "Tab section", "H/L tabs" } },
        { "Actions",  { "c comment", "e edit", "a assign", "o browser" } },
        { "Jira",     { "r reply", "? help" } },
        { "Window",   { "Q close" } },
      }
    else
      groups = {
        { "Navigate", { "q back", "BS back", "Tab section", "H/L tabs" } },
        { "Actions",  { "a approve", "R changes", "c comment", "d diff" } },
        { "PR",       { "D ready", "x checkout", "m merge", "o browser" } },
        { "Window",   { "? help", "Q close" } },
      }
    end
  elseif sec_id == "jira_issues" then
    groups = {
      { "Navigate", { "↵ open", "j/k move", "Tab section", "H/L tabs" } },
      { "Actions",  { "c comment", "e edit", "a assign", "m move", "n new", "y clone", "/ search", "* pin" } },
      { "Toggles",  { "s scope", "h done", "p project", "b board", "r refresh" } },
      { "Window",   { "o browser", "? help", "q hide", "Q close" } },
    }
  elseif sec_id == "jira_sprint" or sec_id == "jira_epics" or sec_id == "jira_backlog" then
    groups = {
      { "Navigate", { "↵ open", "j/k move", "Tab section", "H/L tabs" } },
      { "Actions",  { "m move", "c comment", "a assign", "/ search", "* pin" } },
      { "Jira",     { "p project", "b board", "r refresh" } },
      { "Window",   { "o browser", "? help", "q hide", "Q close" } },
    }
  elseif sec_id == "jira_bookmarks" or sec_id == "gh_bookmarks" then
    groups = {
      { "Navigate", { "↵ open", "j/k move", "Tab section", "H/L tabs" } },
      { "Actions",  { "* unpin", "o browser", "r refresh" } },
      { "Window",   { "? help", "q hide", "Q close" } },
    }
  elseif sec_id == "gh_reviews" then
    groups = {
      { "Navigate", { "↵ open", "j/k move", "Tab section", "H/L tabs" } },
      { "Actions",  { "a approve", "R changes", "c comment", "d diff", "m merge", "/ search", "* pin" } },
      { "PR",       { "s sort", "D ready", "x checkout", "r refresh" } },
      { "Window",   { "o browser", "? help", "q hide", "Q close" } },
    }
  else
    groups = {
      { "Navigate", { "↵ open", "j/k move", "Tab section", "H/L tabs" } },
      { "Actions",  { "a approve", "R changes", "c comment", "d diff", "m merge", "/ search", "* pin" } },
      { "PR",       { "D ready", "x checkout", "N new", "r refresh" } },
      { "Window",   { "o browser", "? help", "q hide", "Q close" } },
    }
  end

  local sep = " │ "

  -- Compute the max display width of any single key-desc pair across all groups.
  local max_pair_dw = 0
  for _, grp in ipairs(groups) do
    for _, k in ipairs(grp[2]) do
      local dw = vim.fn.strdisplaywidth(k)
      if dw > max_pair_dw then max_pair_dw = dw end
    end
  end

  -- Compute max label width per column (row pairs share columns).
  local row1_groups = { groups[1], groups[2] }
  local row2_groups = { groups[3], groups[4] }
  local label_widths = {}
  for i = 1, 2 do
    local lw1 = #row1_groups[i][1]
    local lw2 = #row2_groups[i][1]
    label_widths[i] = math.max(lw1, lw2)
  end

  -- Render a single group with fixed-width key-desc pairs and padded label.
  local function render_group(grp, col_idx)
    local highlights = {}
    local label = grp[1]
    local keys = grp[2]
    local col = 0

    highlights[#highlights + 1] = { col_start = col, col_end = col + #label, hl = "DevOpsSection" }
    local label_pad = string.rep(" ", label_widths[col_idx] - #label)
    local segment = label .. label_pad .. "  "
    for ki, k in ipairs(keys) do
      local key_part, desc_part = k:match("^(%S+)%s+(.+)$")
      if key_part then
        highlights[#highlights + 1] = { col_start = col + #segment, col_end = col + #segment + #key_part, hl = "DevOpsKey" }
        segment = segment .. key_part .. " "
        highlights[#highlights + 1] = { col_start = col + #segment, col_end = col + #segment + #desc_part, hl = "DevOpsAction" }
        segment = segment .. desc_part
      else
        segment = segment .. k
      end
      -- Pad this pair to fixed width
      local pair_dw = vim.fn.strdisplaywidth(k)
      local pair_pad = max_pair_dw - pair_dw
      if ki < #keys then
        segment = segment .. string.rep(" ", pair_pad + 2)
      end
    end
    return segment, highlights, vim.fn.strdisplaywidth(segment)
  end

  -- Compute max display width per column so separators align visually.
  local col_widths = {}
  for i = 1, 2 do
    local w1 = select(3, render_group(row1_groups[i], i))
    local w2 = select(3, render_group(row2_groups[i], i))
    col_widths[i] = math.max(w1, w2)
  end

  local function build_line(grp_list)
    local text = " "
    local highlights = {}
    local col = 1
    for gi, grp in ipairs(grp_list) do
      local segment, hls, dw = render_group(grp, gi)
      -- Pad with spaces to reach the column's display width
      local padded = segment .. string.rep(" ", col_widths[gi] - dw)
      for _, h in ipairs(hls) do
        highlights[#highlights + 1] = { col_start = col + h.col_start, col_end = col + h.col_end, hl = h.hl }
      end
      text = text .. padded
      col = col + #padded
      if gi < #grp_list then
        highlights[#highlights + 1] = { col_start = col + 1, col_end = col + 1 + #"│", hl = "DevOpsBorder" }
        text = text .. sep
        col = col + #sep
      end
    end
    return text, highlights
  end

  local text1, h1 = build_line(row1_groups)
  local text2, h2 = build_line(row2_groups)

  vim.bo[state.footer.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.footer.buf, 0, -1, false, { text1, text2 })
  vim.bo[state.footer.buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.footer.buf, footer_ns, 0, -1)
  for _, h in ipairs(h1) do
    pcall(vim.api.nvim_buf_set_extmark, state.footer.buf, footer_ns, 0, h.col_start, {
      end_col = h.col_end, hl_group = h.hl,
    })
  end
  for _, h in ipairs(h2) do
    pcall(vim.api.nvim_buf_set_extmark, state.footer.buf, footer_ns, 1, h.col_start, {
      end_col = h.col_end, hl_group = h.hl,
    })
  end
end

local function header(_, subtitle)
  local lines = { "", "  " .. subtitle, "" }
  local hls = {
    { line = 1, col_start = 0, col_end = #lines[2], hl = "DevOpsDim" },
  }
  return lines, hls
end

local function park_cursor_on_first_item()
  if not state.content_cursor and state.content.win and vim.api.nvim_win_is_valid(state.content.win) then
    local first
    for line, _ in pairs(state.rows) do
      if not first or line < first then first = line end
    end
    if first then pcall(vim.api.nvim_win_set_cursor, state.content.win, { first, 0 }) end
  end
end

local stop_spinner -- forward declaration (defined after set_message)

local function render_jira(issues, assignee_name, columns, title_override)
  stop_spinner()
  local scope = state.sprint and "Active sprints" or (state.project and state.project.key or "no project")
  local subtitle = scope .. "  ·  " .. assignee_name .. "  ·  " .. #issues .. " issue" .. (#issues == 1 and "" or "s")
  local lines, hls = header(title_override or "Jira  ·  My Issues", subtitle)
  local rows = {}
  local w = content_width()

  -- Compute the longest key so all summaries align.
  local max_key = 0
  for _, issue in ipairs(issues) do
    max_key = math.max(max_key, #(issue.key or ""))
  end
  max_key = math.max(max_key, 6) -- minimum padding

  -- Render one issue row. show_status only in flat mode (grouped rows are
  -- already under their status column).
  local function add_issue(issue, indent, show_status)
    local f = issue.fields or {}
    local icon = render.issue_icon(f.issuetype and f.issuetype.name)
    local key = issue.key or ""
    local keypad = render.pad(key, max_key)

    local prefix = indent .. icon .. "  "
    local status_str, cat
    local reserve = #indent + 4 + max_key + 2
    if show_status then
      cat = f.status and f.status.statusCategory and f.status.statusCategory.key
      status_str = render.pad(render.truncate(f.status and f.status.name or "", 13), 13)
      reserve = reserve + 15
    end
    local summary = render.truncate(f.summary or "", math.max(10, w - reserve))

    local text = show_status
      and (prefix .. keypad .. "  " .. status_str .. "  " .. summary)
      or (prefix .. keypad .. "  " .. summary)
    lines[#lines + 1] = text
    local lidx = #lines - 1
    local key_start = #prefix
    hls[#hls + 1] = { line = lidx, col_start = key_start, col_end = key_start + #key, hl = "DevOpsId" }
    hls[#hls + 1] = { line = lidx, col_start = #indent, col_end = #indent + #icon, hl = "DevOpsIcon" }
    if show_status then
      local status_start = key_start + #keypad + 2
      hls[#hls + 1] = { line = lidx, col_start = status_start, col_end = status_start + #status_str, hl = render.status_hl(cat) }
    end
    rows[#lines] = {
      kind = "jira",
      key = issue.key,
      id = issue.id,
      status = f.status and f.status.name or nil,
      title = f.summary or "",
      type_name = f.issuetype and f.issuetype.name or "",
    }
  end

  -- Colored column header with the count right-aligned.
  local function add_column_header(name, count, cat)
    local left = "  ▌ " .. name:upper()
    local cnt = tostring(count)
    local pad = math.max(2, w - vim.fn.strdisplaywidth(left) - #cnt - 2)
    local head = left .. string.rep(" ", pad) .. cnt
    lines[#lines + 1] = head
    local lidx = #lines - 1
    hls[#hls + 1] = { line = lidx, col_start = 0, col_end = #left, hl = render.column_hl(cat, name) }
    hls[#hls + 1] = { line = lidx, col_start = #head - #cnt, col_end = #head, hl = "DevOpsCount" }
  end

  if columns and #columns > 0 then
    -- Bucket issues into board columns by status id, in board order.
    local idx_by_status, buckets, cats, other = {}, {}, {}, {}
    for i, col in ipairs(columns) do
      buckets[i] = {}
      for _, sid in ipairs(col.statuses) do idx_by_status[sid] = i end
    end
    for _, issue in ipairs(issues) do
      local st = issue.fields and issue.fields.status
      local sid = st and tostring(st.id)
      local gi = sid and idx_by_status[sid]
      if gi then
        table.insert(buckets[gi], issue)
        cats[gi] = cats[gi] or (st.statusCategory and st.statusCategory.key)
      else
        table.insert(other, issue)
      end
    end
    for i, col in ipairs(columns) do
      add_column_header(col.name, #buckets[i], cats[i])
      if #buckets[i] == 0 then
        local empty = "       —"
        lines[#lines + 1] = empty
        hls[#hls + 1] = { line = #lines - 1, col_start = 0, col_end = #empty, hl = "DevOpsDim" }
      else
        for _, issue in ipairs(buckets[i]) do add_issue(issue, "    ", false) end
      end
      lines[#lines + 1] = ""
    end
    if #other > 0 then
      add_column_header("Other", #other, nil)
      for _, issue in ipairs(other) do add_issue(issue, "    ", false) end
    end
  else
    if #issues == 0 then lines[#lines + 1] = "  (no issues)" end
    for _, issue in ipairs(issues) do add_issue(issue, "  ", true) end
  end

  set_buf_lines(state.content.buf, lines)
  apply_highlights(state.content.buf, hls)
  state.rows = rows
  park_cursor_on_first_item()
end

-- Render a Jira section straight from cached issues (no network call). Shared by
-- the cache path in load_section and the optimistic update after a transition.
local function render_jira_from_cache(sec_id, cached)
  if sec_id == "jira_issues" then
    local name = state.jira_user and state.jira_user.name or (client.display_name() or "me")
    render_jira(cached, name, state.columns)
  elseif sec_id == "jira_sprint" then
    render_jira(cached, "all", state.columns, "Jira  ·  Sprint Board")
  elseif sec_id == "jira_epics" then
    render_jira(cached, state.project and state.project.key or "project", nil, "Jira  ·  Epics")
  elseif sec_id == "jira_backlog" then
    render_jira(cached, state.project and state.project.key or "project", nil, "Jira  ·  Backlog")
  end
end

local function github_check_status(rollup)
  if not rollup then return "", nil end
  local state_val = type(rollup) == "table" and rollup.state or rollup
  if state_val == "SUCCESS" then return " ✓", "DevOpsOk" end
  if state_val == "FAILURE" or state_val == "ERROR" then return " ✗", "DevOpsErr" end
  if state_val == "PENDING" or state_val == "IN_PROGRESS" then return " ⏳", "DevOpsWarn" end
  return "", nil
end

local function time_ago(iso)
  if not iso or iso == "" then return "?" end
  local y, mo, d, h, mi, s = iso:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return "?" end
  local ts = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
    hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) })
  local diff = os.time(os.date("!*t")) - ts
  if diff < 60 then return "just now" end
  if diff < 3600 then return math.floor(diff / 60) .. "m ago" end
  if diff < 86400 then return math.floor(diff / 3600) .. "h ago" end
  local days = math.floor(diff / 86400)
  if days == 1 then return "1 day ago" end
  if days < 30 then return days .. " days ago" end
  return math.floor(days / 30) .. " months ago"
end

local function render_github(prs, title, show_meta)
  stop_spinner()
  -- Sort reviews by user preference
  if show_meta then
    prs = vim.deepcopy(prs or {})
    if state.reviews_sort == "oldest" then
      table.sort(prs, function(a, b) return (a.createdAt or "") < (b.createdAt or "") end)
    else
      table.sort(prs, function(a, b) return (a.createdAt or "") > (b.createdAt or "") end)
    end
  end
  local sort_hint = show_meta and (" · " .. state.reviews_sort .. " first") or ""
  local subtitle = #prs .. " pull request" .. (#prs == 1 and "" or "s") .. sort_hint
  local lines, hls = header(title, subtitle)
  local rows = {}
  local w = content_width()

  for pi, pr in ipairs(prs) do
    if show_meta and pi > 1 then lines[#lines + 1] = "" end
    local icon = pr.isDraft and "" or ""
    local num = "#" .. tostring(pr.number or "?")
    local numpad = render.pad(num, 6)
    local check_icon, check_hl = github_check_status(pr.statusCheckRollup)
    local repo = (pr.repository and pr.repository.name) or ""
    local tag = (not show_meta) and repo or ""
    local summary = render.truncate(pr.title or "", math.max(10, w - 14 - #tag - #check_icon))

    local prefix = "  " .. icon .. "  "
    local text = prefix .. numpad .. check_icon .. "  " .. summary
    if tag ~= "" then text = text .. "  " .. tag end
    lines[#lines + 1] = text
    local lidx = #lines - 1
    hls[#hls + 1] = { line = lidx, col_start = #("  "), col_end = #("  ") + #icon, hl = pr.isDraft and "DevOpsPrDraft" or "DevOpsPrOpen" }
    local num_start = #prefix
    hls[#hls + 1] = { line = lidx, col_start = num_start, col_end = num_start + #num, hl = "DevOpsId" }
    if check_hl then
      local check_start = #prefix + #numpad
      hls[#hls + 1] = { line = lidx, col_start = check_start, col_end = check_start + #check_icon, hl = check_hl }
    end
    if tag ~= "" then
      hls[#hls + 1] = { line = lidx, col_start = #text - #tag, col_end = #text, hl = "DevOpsDim" }
    end
    rows[#lines] = { kind = "pr", pr = pr }

    if show_meta then
      local indent = string.rep(" ", #prefix + #numpad + 2)
      local full_repo = (pr.repository and pr.repository.nameWithOwner) or repo
      local author = pr.author and pr.author.login or "?"
      local reviewers = pr.reviewReason or "?"

      -- Align values: pad labels to same width
      local lbl_w = #"Reviewers:  "
      local function pad_lbl(lbl) return lbl .. string.rep(" ", lbl_w - #lbl) end

      -- Repo line
      local lbl_r = pad_lbl("Repo:")
      lines[#lines + 1] = indent .. lbl_r .. full_repo
      rows[#lines] = { kind = "pr", pr = pr }
      local rl = #lines - 1
      hls[#hls + 1] = { line = rl, col_start = #indent, col_end = #indent + #lbl_r, hl = "DevOpsDim" }
      hls[#hls + 1] = { line = rl, col_start = #indent + #lbl_r, col_end = #indent + #lbl_r + #full_repo, hl = "DevOpsColumn" }

      -- Author line
      local lbl_a = pad_lbl("Author:")
      lines[#lines + 1] = indent .. lbl_a .. author
      rows[#lines] = { kind = "pr", pr = pr }
      local al = #lines - 1
      hls[#hls + 1] = { line = al, col_start = #indent, col_end = #indent + #lbl_a, hl = "DevOpsDim" }
      hls[#hls + 1] = { line = al, col_start = #indent + #lbl_a, col_end = #indent + #lbl_a + #author, hl = "DevOpsKey" }

      -- Reviewers line
      local lbl_rv = pad_lbl("Reviewers:")
      lines[#lines + 1] = indent .. lbl_rv .. reviewers
      rows[#lines] = { kind = "pr", pr = pr }
      local rv = #lines - 1
      hls[#hls + 1] = { line = rv, col_start = #indent, col_end = #indent + #lbl_rv, hl = "DevOpsDim" }
      hls[#hls + 1] = { line = rv, col_start = #indent + #lbl_rv, col_end = #indent + #lbl_rv + #reviewers, hl = "DevOpsAction" }

      -- Age line
      local age = time_ago(pr.createdAt)
      local lbl_age = pad_lbl("Age:")
      lines[#lines + 1] = indent .. lbl_age .. age
      rows[#lines] = { kind = "pr", pr = pr }
      local ag = #lines - 1
      hls[#hls + 1] = { line = ag, col_start = #indent, col_end = #indent + #lbl_age, hl = "DevOpsDim" }
      hls[#hls + 1] = { line = ag, col_start = #indent + #lbl_age, col_end = #indent + #lbl_age + #age, hl = "DevOpsWarn" }
    end
  end

  if #prs == 0 then lines[#lines + 1] = "  (none)" end
  set_buf_lines(state.content.buf, lines)
  apply_highlights(state.content.buf, hls)
  state.rows = rows
  park_cursor_on_first_item()
end

local function render_bookmarks(tab_id)
  local pins = state.bookmarks[tab_id] or {}
  local lines, hls = header(nil, #pins .. " pinned")
  local rows = {}
  local w = content_width()

  if #pins == 0 then
    lines[#lines + 1] = "  (no bookmarks — press * on any item to pin)"
  end

  for _, bm in ipairs(pins) do
    if bm.kind == "jira" then
      local icon = render.issue_icon(bm.type_name)
      local key = bm.key or ""
      local text = "  " .. icon .. "  " .. render.pad(key, 10) .. "  " .. render.truncate(bm.title or "", w - 20)
      lines[#lines + 1] = text
      local lidx = #lines - 1
      local key_start = #("  " .. icon .. "  ")
      hls[#hls + 1] = { line = lidx, col_start = key_start, col_end = key_start + #key, hl = "DevOpsId" }
      rows[#lines] = { kind = "jira", key = bm.key, id = bm.id, title = bm.title, type_name = bm.type_name }
    elseif bm.kind == "pr" then
      local num = "#" .. tostring(bm.number or "?")
      local text = "  " .. render.pad(num, 6) .. "  " .. render.truncate(bm.title or "", w - 20)
      if bm.repo and bm.repo ~= "" then text = text .. "  " .. bm.repo end
      lines[#lines + 1] = text
      local lidx = #lines - 1
      hls[#hls + 1] = { line = lidx, col_start = 2, col_end = 2 + #num, hl = "DevOpsId" }
      if bm.repo and bm.repo ~= "" then
        hls[#hls + 1] = { line = lidx, col_start = #text - #bm.repo, col_end = #text, hl = "DevOpsDim" }
      end
      rows[#lines] = {
        kind = "pr",
        pr = { number = bm.number, title = bm.title, url = bm.url,
               repository = { nameWithOwner = bm.repo_full, name = bm.repo } },
      }
    end
  end

  set_buf_lines(state.content.buf, lines)
  apply_highlights(state.content.buf, hls)
  state.rows = rows
  park_cursor_on_first_item()
end

-- Animated loading spinner
local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinner_timer = nil

stop_spinner = function()
  if not spinner_timer then return end
  local t = spinner_timer
  spinner_timer = nil
  t:stop()
  if not t:is_closing() then t:close() end
end

local function set_message(msg)
  stop_spinner()
  set_buf_lines(state.content.buf, { "", "  " .. msg })
  apply_highlights(state.content.buf, {})
  state.rows = {}
end

local function start_spinner(label)
  stop_spinner()
  local i = 1
  label = label or "Loading"
  set_message(spinner_frames[1] .. " " .. label .. "…")
  spinner_timer = vim.uv.new_timer()
  spinner_timer:start(80, 80, vim.schedule_wrap(function()
    if not spinner_timer or not is_open() then
      stop_spinner()
      return
    end
    i = (i % #spinner_frames) + 1
    set_buf_lines(state.content.buf, { "", "  " .. spinner_frames[i] .. " " .. label .. "…" })
    apply_highlights(state.content.buf, {})
  end))
end

---------------------------------------------------------------------------
-- Data loading per section
---------------------------------------------------------------------------
-- Cache: avoid re-fetching when switching back to a section within TTL.
-- Seeded from disk on first access for instant startup.
local cache = {} -- { [sec_id] = { data = ..., ts = os.time() } }
local CACHE_TTL = 120 -- seconds
local cache_loaded = false

local function ensure_cache_loaded()
  if cache_loaded then return end
  cache_loaded = true
  local persisted = store.load_section_cache()
  for k, v in pairs(persisted) do
    if not cache[k] then cache[k] = v end
  end
end

local function cache_get(sec_id)
  ensure_cache_loaded()
  local entry = cache[sec_id]
  if entry and (os.time() - entry.ts) < CACHE_TTL then return entry.data end
  return nil
end

local function cache_set(sec_id, data)
  cache[sec_id] = { data = data, ts = os.time() }
  -- Persist async to avoid blocking UI
  vim.schedule(function() store.save_section_cache(cache) end)
end

local function cache_invalidate(sec_id)
  cache[sec_id] = nil
end

local function invalidate_tab_cache(tab_id)
  local ti = tab_index_by_id(tab_id)
  local tab = ti and TABS[ti] or nil
  for _, sec in ipairs(tab and tab.sections or {}) do
    cache_invalidate(sec.id)
  end
end

local function load_section(force)
  local sec_id = current_section_id()

  -- Bookmark sections are local — no API call needed
  if sec_id == "jira_bookmarks" or sec_id == "gh_bookmarks" then
    state.bookmarks = store.load_bookmarks()
    render_bookmarks(current_tab_id())
    return
  end

  -- Serve from cache unless forced (manual refresh)
  if not force then
    local cached = cache_get(sec_id)
    if cached then
      if sec_id == "gh_prs" or sec_id == "gh_reviews" then
        local title = sec_id == "gh_prs" and "GitHub · My PRs" or "GitHub · Reviews"
        render_github(cached, title, sec_id == "gh_reviews")
      else
        render_jira_from_cache(sec_id, cached)
      end
      return
    end
  end

  start_spinner("Loading")

  if sec_id == "jira_issues" then
    if not client.configured() then
      set_message("⚠ Jira not configured — run :JiraAuth. Missing: " .. table.concat(client.missing(), ", "))
      return
    end
    local account = state.jira_user and state.jira_user.account_id or client.account_id()
    local name = state.jira_user and state.jira_user.name or (client.display_name() or "me")
    local function on_issues(ok, issues, err)
      if not is_open() or current_section_id() ~= sec_id then return end
      if not ok then return set_message("⚠ " .. (err or "Jira search failed")) end
      cache_set(sec_id, issues)
      render_jira(issues, name, state.columns)
    end
    local use_sprints = state.sprint ~= nil and state.scope_override ~= "project"
    api.search({
      account_id = account,
      project_key = state.project and state.project.key,
      open_sprints = use_sprints,
      -- In board mode the layout has a Done column, so fetch Done issues to fill
      -- it; the flat list still respects the +Done toggle.
      include_done = state.include_done or state.columns ~= nil,
    }, on_issues)
  elseif sec_id == "jira_sprint" then
    if not client.configured() then
      set_message("⚠ Jira not configured — run :JiraAuth. Missing: " .. table.concat(client.missing(), ", "))
      return
    end
    if not state.sprint then
      set_message("⚠ No active sprint — select a Scrum board with 'b'")
      return
    end
    api.search({
      account_id = nil,
      project_key = state.project and state.project.key,
      open_sprints = true,
      include_done = true,
    }, function(ok, issues, err)
      if not is_open() or current_section_id() ~= sec_id then return end
      if not ok then return set_message("⚠ " .. (err or "sprint fetch failed")) end
      cache_set(sec_id, issues)
      render_jira(issues, "all", state.columns, "Jira  ·  Sprint Board")
    end)
  elseif sec_id == "jira_epics" then
    if not client.configured() then
      set_message("⚠ Jira not configured — run :JiraAuth. Missing: " .. table.concat(client.missing(), ", "))
      return
    end
    if not state.project or not state.project.key then
      set_message("⚠ Pick a Jira project with 'p'")
      return
    end
    api.epics(state.project.key, function(ok, issues, err)
      if not is_open() or current_section_id() ~= sec_id then return end
      if not ok then return set_message("⚠ " .. (err or "epics fetch failed")) end
      cache_set(sec_id, issues)
      render_jira(issues, state.project.key, nil, "Jira  ·  Epics")
    end)
  elseif sec_id == "jira_backlog" then
    if not client.configured() then
      set_message("⚠ Jira not configured — run :JiraAuth. Missing: " .. table.concat(client.missing(), ", "))
      return
    end
    if not state.project or not state.project.key then
      set_message("⚠ Pick a Jira project with 'p'")
      return
    end
    api.backlog(state.project.key, function(ok, issues, err)
      if not is_open() or current_section_id() ~= sec_id then return end
      if not ok then return set_message("⚠ " .. (err or "backlog fetch failed")) end
      cache_set(sec_id, issues)
      render_jira(issues, state.project.key, nil, "Jira  ·  Backlog")
    end)
  else -- gh_prs / gh_reviews
    if not gh.available() then return set_message("⚠ gh CLI not found") end
    local fn = sec_id == "gh_prs" and gh.my_prs or gh.my_reviews
    local title = sec_id == "gh_prs" and "GitHub · My PRs" or "GitHub · Reviews"
    local show_meta = sec_id == "gh_reviews"
    fn(function(ok, prs, err)
      if not is_open() or current_section_id() ~= sec_id then return end
      if not ok then return set_message("⚠ " .. (err or "gh failed")) end
      cache_set(sec_id, prs)
      render_github(prs, title, show_meta)
    end)
  end
end

local function refresh_notifications()
  if not gh.available() then return end
  gh.notifications_count(function(count)
    if not is_open() then return end
    state.gh_notif_count = count
    render_sidebar()
  end)
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local function current_item()
  if not is_open() then return nil end
  return state.rows[vim.api.nvim_win_get_cursor(state.content.win)[1]]
end

---------------------------------------------------------------------------
-- Navigation stack — detail views render into the content pane
---------------------------------------------------------------------------
local function nav_push()
  local cursor = state.content.win and vim.api.nvim_win_is_valid(state.content.win)
    and vim.api.nvim_win_get_cursor(state.content.win) or { 1, 0 }
  state.nav_stack[#state.nav_stack + 1] = {
    cursor = cursor,
    rows = state.rows,
    in_detail = state.in_detail,
    detail_kind = state.detail_kind,
  }
end

local function nav_render_detail(b, make_keys, preserve_cursor)
  if not is_open() then return end
  state.in_detail = true
  state.rows = {}
  detail.write_to_buf(state.content.buf, b)
  -- Clear old keymaps by resetting buffer-local keymaps for action keys
  local action_keys = { "c", "e", "a", "r", "o", "R", "d", "D", "m", "x", "n", "y", "t" }
  for _, k in ipairs(action_keys) do
    pcall(vim.keymap.del, "n", k, { buffer = state.content.buf })
  end
  if make_keys then make_keys(state.content.buf) end
  if not preserve_cursor then
    pcall(vim.api.nvim_win_set_cursor, state.content.win, { 1, 0 })
  end
  render_footer()
end

local function nav_pop()
  if #state.nav_stack == 0 then return false end
  local entry = table.remove(state.nav_stack)
  state.in_detail = entry.in_detail
  state.detail_kind = entry.detail_kind
  state.rows = entry.rows
  if not entry.in_detail then
    -- Restore the list view
    load_section()
    vim.schedule(function()
      if state.content.win and vim.api.nvim_win_is_valid(state.content.win) then
        pcall(vim.api.nvim_win_set_cursor, state.content.win, entry.cursor)
      end
    end)
  else
    -- Restore a previous detail (nested nav)
    -- This case is handled by the caller re-rendering
  end
  render_footer()
  return true
end

local function nav_back()
  if not nav_pop() then return end
end

local function open_detail()
  local item = current_item()
  if not item then return end
  nav_push()
  if item.kind == "jira" then
    state.detail_kind = "jira"
    detail.load_issue(item.key, {
      content_win = state.content.win,
      on_ready = nav_render_detail,
      on_update = function(b, make_keys)
        if state.in_detail then nav_render_detail(b, make_keys, true) end
      end,
    })
  elseif item.kind == "pr" then
    state.detail_kind = "pr"
    detail.load_pr(item.pr, {
      on_ready = nav_render_detail,
      on_update = function(b, make_keys)
        if state.in_detail then nav_render_detail(b, make_keys, true) end
      end,
    })
  end
end

local function open_browser()
  local item = current_item()
  if not item then return end
  if item.kind == "jira" then
    vim.ui.open(client.base_url() .. "/browse/" .. item.key)
  elseif item.kind == "pr" then
    vim.ui.open(item.pr.url)
  end
end

local function refresh_current_jira_section()
  local sec_id = current_section_id()
  if is_open() and is_jira_section(sec_id) then
    cache_invalidate(sec_id)
    load_section(true)
  end
end

-- Optimistically reflect a status change without a network refetch: patch the
-- cached issue's status and re-render from cache, keeping the cursor on the same
-- issue. This avoids the reload flicker on every transition, and keeps an issue
-- visible after it's moved to Done (which the server-side query would otherwise
-- filter out). A real refresh ('r') re-applies the server filter.
local function apply_transition_locally(key, to)
  local sec_id = current_section_id()
  local entry = cache[sec_id]
  local cached = entry and entry.data
  if not cached then
    refresh_current_jira_section() -- nothing cached to patch; fall back to refetch
    return
  end
  for _, issue in ipairs(cached) do
    if issue.key == key then
      issue.fields = issue.fields or {}
      if to then
        issue.fields.status = { id = to.id, name = to.name, statusCategory = to.statusCategory }
      end
      break
    end
  end
  local win = state.content and state.content.win
  local cur = (win and vim.api.nvim_win_is_valid(win)) and vim.api.nvim_win_get_cursor(win) or nil
  render_jira_from_cache(sec_id, cached)
  -- Keep the cursor on the same issue (it may have moved to another column).
  if win and vim.api.nvim_win_is_valid(win) then
    local target
    for line, row in pairs(state.rows) do
      if row.key == key then target = line break end
    end
    if target then
      pcall(vim.api.nvim_win_set_cursor, win, { target, 0 })
    elseif cur then
      cur[1] = math.min(cur[1], vim.api.nvim_buf_line_count(state.content.buf))
      pcall(vim.api.nvim_win_set_cursor, win, cur)
    end
  end
end

local function switch_section(section_idx, tab_idx)
  local next_tab = wrap_index(tab_idx or state.tab, #TABS)
  local next_section = wrap_index(section_idx or state.section, section_count(next_tab))
  state.tab = next_tab
  state.section = next_section
  state.content_cursor = nil
  state.nav_stack = {}
  state.in_detail = false
  state.detail_kind = nil
  render_sidebar()
  render_footer()
  update_winbar()
  state.sidebar_line = sidebar_line_for_section(next_section)
  load_section()
end

local function switch_tab(delta)
  switch_section(1, state.tab + delta)
end

local function select_user()
  if current_section_id() ~= "jira_issues" then
    vim.notify("DevOps: user filter applies to the Jira section", vim.log.levels.INFO)
    return
  end
  api.assignable_users(state.project and state.project.key, function(ok, users, err)
    if not ok then return vim.notify("DevOps: " .. (err or "user lookup failed"), vim.log.levels.ERROR) end
    local me_id = client.account_id()
    local choices = { { label = "● Me" .. (client.display_name() and (" (" .. client.display_name() .. ")") or ""), account_id = me_id, me = true } }
    for _, u in ipairs(users) do
      if u.accountId and u.accountType ~= "app" then
        choices[#choices + 1] = { label = u.displayName or u.accountId, account_id = u.accountId }
      end
    end
    vim.ui.select(choices, {
      prompt = "Show issues assigned to:",
      format_item = function(c) return c.label end,
    }, function(choice)
      if not choice then return end
      state.jira_user = choice.me and nil or { account_id = choice.account_id, name = choice.label }
      invalidate_tab_cache("jira")
      switch_section(1, tab_index_by_id("jira"))
    end)
  end)
end

local function transition()
  local item = current_item()
  if not item or item.kind ~= "jira" then
    vim.notify("DevOps: select a Jira issue first", vim.log.levels.INFO)
    return
  end
  api.transitions(item.key, function(ok, trs, err)
    if not ok then return vim.notify("DevOps: " .. (err or "no transitions"), vim.log.levels.ERROR) end
    local current_status = item.status or "?"

    -- Order destinations the way the board reads (To Do → In Progress → Done),
    -- falling back to status category, then name.
    local col_rank = {}
    for i, col in ipairs(state.columns or {}) do
      for _, sid in ipairs(col.statuses or {}) do col_rank[tostring(sid)] = i end
    end
    local cat_rank = { new = 1, indeterminate = 2, done = 3 }
    local function rank(tr)
      local to = tr.to or {}
      local by_col = to.id and col_rank[tostring(to.id)]
      if by_col then return by_col end
      return 100 + (cat_rank[to.statusCategory and to.statusCategory.key] or 9)
    end
    table.sort(trs, function(a, b)
      local ra, rb = rank(a), rank(b)
      if ra ~= rb then return ra < rb end
      return (a.to and a.to.name or a.name or "") < (b.to and b.to.name or b.name or "")
    end)

    vim.ui.select(trs, {
      prompt = "Move " .. item.key .. ":",
      format_item = function(t) return current_status .. "  →  " .. (t.to and t.to.name or t.name) end,
    }, function(choice)
      if not choice then return end
      api.do_transition(item.key, choice.id, function(ok2, _, err2)
        if not ok2 then return vim.notify("DevOps: " .. (err2 or "transition failed"), vim.log.levels.ERROR) end
        vim.notify("DevOps: " .. item.key .. " → " .. choice.name, vim.log.levels.INFO)
        -- Optimistic local update: no refetch, no flicker, issue stays visible.
        apply_transition_locally(item.key, choice.to)
      end)
    end)
  end)
end

---------------------------------------------------------------------------
-- Write actions — Jira (comment, edit, assign, create, clone)
---------------------------------------------------------------------------

-- Mention handler for Jira input floats: opens the live-search user picker
-- and inserts @[Name]{id} at cursor.
local function jira_mention_handler(insert_fn)
  local pk = state.project and state.project.key or nil
  user_picker.open(function(choice)
    insert_fn(choice.name, choice.id)
  end, { title = "Mention User", project_key = pk })
end

local mention_opts = { on_mention = jira_mention_handler }

local function input_opts_with_win()
  return { on_mention = jira_mention_handler, parent_win = state.content and state.content.win or nil, compact = true }
end

local function jira_comment()
  local item = current_item()
  if not item or item.kind ~= "jira" then
    return vim.notify("DevOps: select a Jira issue first", vim.log.levels.INFO)
  end

  -- If we're in the list view, open detail first, scroll to comments, then open input
  if not state.in_detail then
    nav_push()
    state.detail_kind = "jira"
    detail.load_issue(item.key, {
      content_win = state.content.win,
      on_ready = function(b, make_keys)
        nav_render_detail(b, make_keys)
        -- Scroll to the last line (latest comment) then open comment input
        vim.defer_fn(function()
          if state.content.win and vim.api.nvim_win_is_valid(state.content.win) then
            local lc = vim.api.nvim_buf_line_count(state.content.buf)
            pcall(vim.api.nvim_win_set_cursor, state.content.win, { lc, 0 })
            -- Force redraw so the scroll position is visible
            vim.cmd("redraw")
          end
          input.open("Comment " .. item.key, "", function(text)
            if text == "" then return end
            api.add_comment(item.key, text, function(ok, _, err)
              if not ok then return vim.notify("DevOps: " .. (err or "comment failed"), vim.log.levels.ERROR) end
              vim.notify("DevOps: comment added to " .. item.key, vim.log.levels.INFO)
              -- Refresh the detail view
              detail.load_issue(item.key, {
                content_win = state.content.win,
                on_ready = function(b2, mk2)
                  if state.in_detail then nav_render_detail(b2, mk2, true) end
                  vim.defer_fn(function()
                    local lc2 = vim.api.nvim_buf_line_count(state.content.buf)
                    pcall(vim.api.nvim_win_set_cursor, state.content.win, { lc2, 0 })
                  end, 50)
                end,
              })
            end)
          end, input_opts_with_win())
        end, 50)
      end,
      on_update = function(b, make_keys)
        if state.in_detail then nav_render_detail(b, make_keys, true) end
      end,
    })
    return
  end

  -- Already in detail view — just open the comment input
  input.open("Comment " .. item.key, "", function(text)
    if text == "" then return end
    api.add_comment(item.key, text, function(ok, _, err)
      if not ok then return vim.notify("DevOps: " .. (err or "comment failed"), vim.log.levels.ERROR) end
      vim.notify("DevOps: comment added to " .. item.key, vim.log.levels.INFO)
      refresh_current_jira_section()
    end)
  end, input_opts_with_win())
end

local function jira_edit()
  local item = current_item()
  if not item or item.kind ~= "jira" then
    return vim.notify("DevOps: select a Jira issue first", vim.log.levels.INFO)
  end
  api.get_issue(item.key, function(ok, issue, err)
    if not ok then return vim.notify("DevOps: " .. (err or "fetch failed"), vim.log.levels.ERROR) end
    local f = issue.fields or {}
    -- Edit summary first (single line)
    vim.ui.input({ prompt = "Summary: ", default = f.summary or "" }, function(new_summary)
      if not new_summary then return end
      -- Then edit description (multiline)
      local desc_text = table.concat(adf.adf_to_lines(f.description), "\n")
      input.open("Description " .. item.key, desc_text, function(new_desc)
        local fields = {}
        if new_summary ~= (f.summary or "") then fields.summary = new_summary end
        fields.description = adf.text_to_adf(new_desc)
        api.update_issue(item.key, fields, function(ok2, _, err2)
          if not ok2 then return vim.notify("DevOps: " .. (err2 or "update failed"), vim.log.levels.ERROR) end
          vim.notify("DevOps: " .. item.key .. " updated", vim.log.levels.INFO)
          refresh_current_jira_section()
        end)
      end)
    end)
  end)
end

local function jira_assign()
  local item = current_item()
  if not item or item.kind ~= "jira" then
    return vim.notify("DevOps: select a Jira issue first", vim.log.levels.INFO)
  end
  local project_key = state.project and state.project.key or item.key:match("^(%u+)-")
  api.assignable_users(project_key, function(ok, users, err)
    if not ok then return vim.notify("DevOps: " .. (err or "user lookup failed"), vim.log.levels.ERROR) end
    local choices = {}
    local me_id = client.account_id()
    if me_id then
      choices[#choices + 1] = { label = "● Me (" .. (client.display_name() or "") .. ")", account_id = me_id }
    end
    choices[#choices + 1] = { label = "✗ Unassigned", account_id = nil }
    for _, u in ipairs(users) do
      if u.accountId and u.accountType ~= "app" then
        choices[#choices + 1] = { label = u.displayName or u.accountId, account_id = u.accountId }
      end
    end
    vim.ui.select(choices, {
      prompt = "Assign " .. item.key .. " to:",
      format_item = function(c) return c.label end,
    }, function(choice)
      if not choice then return end
      api.assign(item.key, choice.account_id, function(ok2, _, err2)
        if not ok2 then return vim.notify("DevOps: " .. (err2 or "assign failed"), vim.log.levels.ERROR) end
        vim.notify("DevOps: " .. item.key .. " assigned to " .. choice.label, vim.log.levels.INFO)
        refresh_current_jira_section()
      end)
    end)
  end)
end

local function jira_create()
  if not client.configured() then
    return vim.notify("DevOps: configure Jira first (:JiraAuth)", vim.log.levels.WARN)
  end
  -- Step 1: project (default to current)
  api.list_projects(nil, function(ok, projects, err)
    if not ok then return vim.notify("DevOps: " .. (err or "project list failed"), vim.log.levels.ERROR) end
    vim.ui.select(projects, {
      prompt = "Project:",
      format_item = function(p) return p.key .. "  —  " .. (p.name or "") end,
    }, function(proj)
      if not proj then return end
      -- Step 2: issue type
      api.issue_types(proj.key, function(ok2, types, err2)
        if not ok2 then return vim.notify("DevOps: " .. (err2 or "types failed"), vim.log.levels.ERROR) end
        vim.ui.select(types, {
          prompt = "Issue type:",
          format_item = function(t) return t.name end,
        }, function(itype)
          if not itype then return end
          -- Step 3: summary
          vim.ui.input({ prompt = "Summary: " }, function(summary)
            if not summary or summary == "" then return end
            -- Step 4: description
            input.open("Description (new " .. itype.name .. ")", "", function(desc)
              local fields = {
                project = { key = proj.key },
                issuetype = { name = itype.name },
                summary = summary,
              }
              if desc ~= "" then fields.description = adf.text_to_adf(desc) end
              -- Step 5: assignee (default to me)
              local me_id = client.account_id()
              if me_id then fields.assignee = { accountId = me_id } end
              api.create_issue(fields, function(ok3, data, err3)
                if not ok3 then return vim.notify("DevOps: " .. (err3 or "create failed"), vim.log.levels.ERROR) end
                local new_key = data and data.key or "?"
                vim.notify("DevOps: created " .. new_key, vim.log.levels.INFO)
                refresh_current_jira_section()
              end)
            end)
          end)
        end)
      end)
    end)
  end)
end

local function jira_clone()
  local item = current_item()
  if not item or item.kind ~= "jira" then
    return vim.notify("DevOps: select a Jira issue to clone", vim.log.levels.INFO)
  end
  api.get_issue(item.key, function(ok, issue, err)
    if not ok then return vim.notify("DevOps: " .. (err or "fetch failed"), vim.log.levels.ERROR) end
    local f = issue.fields or {}
    local project_key = item.key:match("^(%u+)-")
    -- Ask for the new title (prefilled), then let the description be edited.
    vim.ui.input({ prompt = "Clone title: ", default = "CLONE - " .. (f.summary or "") }, function(new_summary)
      if not new_summary or new_summary == "" then return end
      local desc_text = table.concat(adf.adf_to_lines(f.description), "\n")
      input.open("Clone description (from " .. item.key .. ")", desc_text, function(new_desc)
        local fields = {
          project = { key = project_key },
          issuetype = { name = f.issuetype and f.issuetype.name or "Task" },
          summary = new_summary,
          description = adf.text_to_adf(new_desc),
        }
        local me_id = client.account_id()
        if me_id then fields.assignee = { accountId = me_id } end
        api.create_issue(fields, function(ok2, data, err2)
          if not ok2 then return vim.notify("DevOps: " .. (err2 or "clone failed"), vim.log.levels.ERROR) end
          local new_key = data and data.key or "?"
          vim.notify("DevOps: cloned " .. item.key .. " → " .. new_key, vim.log.levels.INFO)
          refresh_current_jira_section()
        end)
      end, input_opts_with_win())
    end)
  end)
end

local function jira_search()
  if not client.configured() then
    vim.notify("DevOps: Jira not configured — run :JiraAuth", vim.log.levels.ERROR)
    return
  end
  local prev_win = vim.api.nvim_get_current_win()

  -- Snacks-style search bar anchored to top of content pane
  local input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[input_buf].bufhidden = "wipe"
  local content_cfg = vim.api.nvim_win_get_config(state.content.win)
  local w = content_cfg.width - 2
  local scope_sprint = false -- default: global search

  local function title_text()
    local scope_label = scope_sprint and "sprint" or "global"
    return " 🔍 Jira [" .. scope_label .. "]  C-t: toggle "
  end

  -- Highlight groups matching Snacks picker style
  vim.api.nvim_set_hl(0, "DevOpsSearchBorder", { fg = "#ff9e64" })
  vim.api.nvim_set_hl(0, "DevOpsSearchTitle", { fg = "#c27fd7", bold = true })
  vim.api.nvim_set_hl(0, "DevOpsSearchNormal", { bg = "#242b38" })

  local input_win = vim.api.nvim_open_win(input_buf, true, {
    relative = "win", win = state.content.win,
    width = w, height = 1,
    row = -1, col = 0,
    style = "minimal", border = "rounded",
    title = title_text(), title_pos = "center",
    zindex = 300,
  })
  vim.wo[input_win].winhighlight = "Normal:DevOpsSearchNormal,FloatBorder:DevOpsSearchBorder,FloatTitle:DevOpsSearchTitle"

  local timer = vim.uv.new_timer()
  local closed = false

  local function do_close()
    if closed then return end
    closed = true
    timer:stop()
    vim.cmd("stopinsert")
    if vim.api.nvim_win_is_valid(input_win) then vim.api.nvim_win_close(input_win, true) end
    if prev_win and vim.api.nvim_win_is_valid(prev_win) then
      vim.api.nvim_set_current_win(prev_win)
    end
  end

  -- Debounced search renders results into dashboard content pane
  local last_query = ""
  local function do_search(query)
    timer:stop()
    if query == "" then
      last_query = ""
      load_section() -- restore normal view
      return
    end
    -- Skip queries under 2 chars to reduce noise
    if #query < 2 then return end
    -- Skip if query hasn't changed
    if query == last_query then return end
    last_query = query
    timer:start(400, 0, vim.schedule_wrap(function()
      if closed then return end
      local opts = { project_key = state.project and state.project.key }
      if scope_sprint and state.sprint then
        opts.sprint = true
      end
      api.text_search(query, opts, function(ok, issues, err)
        if closed or not is_open() then return end
        if not ok then return set_message("⚠ " .. (err or "search failed")) end
        render_jira(issues, "search: " .. query, nil, "Jira  ·  Search Results")
      end)
    end))
  end

  -- React to typing
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = input_buf,
    callback = function()
      if closed then return end
      local q = (vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1] or "")
      do_search(q)
    end,
  })

  -- Keymaps
  local function km(modes, lhs, fn, desc)
    vim.keymap.set(modes, lhs, fn, { buffer = input_buf, nowait = true, desc = desc })
  end

  -- Toggle scope
  km({ "i", "n" }, "<C-t>", function()
    scope_sprint = not scope_sprint
    vim.api.nvim_win_set_config(input_win, { title = title_text(), title_pos = "center" })
    -- Re-trigger search with current query
    local q = (vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1] or "")
    do_search(q)
  end, "Toggle scope")

  -- Select item under cursor in content pane
  km({ "i", "n" }, "<CR>", function()
    do_close()
    -- Open detail of the item under content cursor
    local item = current_item()
    if item then open_detail() end
  end, "Open selected")

  km({ "i", "n" }, "<Esc>", function()
    do_close()
    load_section() -- restore normal list
  end, "Cancel")
  km("n", "q", function()
    do_close()
    load_section()
  end, "Cancel")
  km("n", "<C-d>", function()
    do_close()
    load_section()
  end, "Cancel")

  vim.cmd("startinsert")
end

local function gh_search()
  if not gh.available() then
    vim.notify("DevOps: gh CLI not found", vim.log.levels.ERROR)
    return
  end
  local prev_win = vim.api.nvim_get_current_win()

  local input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[input_buf].bufhidden = "wipe"
  local content_cfg = vim.api.nvim_win_get_config(state.content.win)
  local w = content_cfg.width - 2

  -- Detect current repo from cwd for local scope
  local cwd_repo = nil
  local git_remote = vim.fn.systemlist("git -C " .. vim.fn.getcwd() .. " remote get-url origin 2>/dev/null")[1] or ""
  local owner_repo = git_remote:match("[:/]([%w%.%-]+/[%w%.%-]+)%.?g?i?t?$")
  if owner_repo then cwd_repo = owner_repo:gsub("%.git$", "") end

  local scope_local = false -- default: global

  local function title_text()
    local scope_label = scope_local and ("local: " .. (cwd_repo or "repo")) or "global"
    return " 🔍 GitHub [" .. scope_label .. "]  C-t: toggle "
  end

  vim.api.nvim_set_hl(0, "DevOpsSearchBorder", { fg = "#ff9e64" })
  vim.api.nvim_set_hl(0, "DevOpsSearchTitle", { fg = "#c27fd7", bold = true })
  vim.api.nvim_set_hl(0, "DevOpsSearchNormal", { bg = "#242b38" })

  local input_win = vim.api.nvim_open_win(input_buf, true, {
    relative = "win", win = state.content.win,
    width = w, height = 1,
    row = -1, col = 0,
    style = "minimal", border = "rounded",
    title = title_text(), title_pos = "center",
    zindex = 300,
  })
  vim.wo[input_win].winhighlight = "Normal:DevOpsSearchNormal,FloatBorder:DevOpsSearchBorder,FloatTitle:DevOpsSearchTitle"

  local timer = vim.uv.new_timer()
  local closed = false

  local function do_close()
    if closed then return end
    closed = true
    timer:stop()
    vim.cmd("stopinsert")
    if vim.api.nvim_win_is_valid(input_win) then vim.api.nvim_win_close(input_win, true) end
    if prev_win and vim.api.nvim_win_is_valid(prev_win) then
      vim.api.nvim_set_current_win(prev_win)
    end
  end

  local last_query = ""
  local function do_search(query)
    timer:stop()
    if query == "" then
      last_query = ""
      load_section()
      return
    end
    if #query < 2 then return end
    if query == last_query then return end
    last_query = query
    timer:start(400, 0, vim.schedule_wrap(function()
      if closed then return end
      local opts = {}
      if scope_local and cwd_repo then opts.repo = cwd_repo end
      gh.search_prs(query, opts, function(ok, prs, err)
        if closed or not is_open() then return end
        if not ok then return set_message("⚠ " .. (err or "search failed")) end
        render_github(prs, "search: " .. query, true)
      end)
    end))
  end

  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = input_buf,
    callback = function()
      if closed then return end
      local q = (vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1] or "")
      do_search(q)
    end,
  })

  local function km(modes, lhs, fn, desc)
    vim.keymap.set(modes, lhs, fn, { buffer = input_buf, nowait = true, desc = desc })
  end

  -- Toggle scope
  km({ "i", "n" }, "<C-t>", function()
    scope_local = not scope_local
    vim.api.nvim_win_set_config(input_win, { title = title_text(), title_pos = "center" })
    local q = (vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1] or "")
    do_search(q)
  end, "Toggle scope")

  km({ "i", "n" }, "<CR>", function()
    do_close()
    local item = current_item()
    if item then open_detail() end
  end, "Open selected")

  km({ "i", "n" }, "<Esc>", function()
    do_close()
    load_section()
  end, "Cancel")
  km("n", "q", function() do_close(); load_section() end, "Cancel")
  km("n", "<C-d>", function() do_close(); load_section() end, "Cancel")

  vim.cmd("startinsert")
end

local function dispatch_search()
  local tab_id = current_tab_id()
  if tab_id == "github" then
    gh_search()
  elseif tab_id == "jira" then
    jira_search()
  else
    vim.notify("DevOps: search is available on Jira and GitHub tabs", vim.log.levels.INFO)
  end
end

---------------------------------------------------------------------------
-- Write actions — GitHub PR
---------------------------------------------------------------------------

local function pr_item()
  local item = current_item()
  if not item or item.kind ~= "pr" then
    vim.notify("DevOps: select a PR first", vim.log.levels.INFO)
    return nil, nil, nil
  end
  local repo = item.pr.repository and item.pr.repository.nameWithOwner
  local n = item.pr.number
  if not repo or not n then
    vim.notify("DevOps: PR missing repo/number", vim.log.levels.ERROR)
    return nil, nil, nil
  end
  return item, repo, n
end

local function gh_approve()
  local item, repo, n = pr_item()
  if not item then return end
  gh.pr_approve(repo, n, function(ok, _, err)
    if not ok then return vim.notify("DevOps: " .. (err or "approve failed"), vim.log.levels.ERROR) end
    vim.notify("DevOps: approved #" .. n, vim.log.levels.INFO)
    cache_invalidate("gh_prs"); cache_invalidate("gh_reviews"); if is_open() then load_section(true) end
  end)
end

local function gh_request_changes()
  local item, repo, n = pr_item()
  if not item then return end
  input.open("Request changes #" .. n, "", function(body)
    if body == "" then return end
    gh.pr_request_changes(repo, n, body, function(ok, _, err)
      if not ok then return vim.notify("DevOps: " .. (err or "review failed"), vim.log.levels.ERROR) end
      vim.notify("DevOps: requested changes on #" .. n, vim.log.levels.INFO)
      cache_invalidate("gh_prs"); cache_invalidate("gh_reviews"); if is_open() then load_section(true) end
    end)
  end)
end

local function gh_comment()
  local item, repo, n = pr_item()
  if not item then return end
  input.open("Comment #" .. n, "", function(body)
    if body == "" then return end
    gh.pr_comment(repo, n, body, function(ok, _, err)
      if not ok then return vim.notify("DevOps: " .. (err or "comment failed"), vim.log.levels.ERROR) end
      vim.notify("DevOps: commented on #" .. n, vim.log.levels.INFO)
    end)
  end)
end

local function gh_ready()
  local item, repo, n = pr_item()
  if not item then return end
  gh.pr_ready(repo, n, function(ok, _, err)
    if not ok then return vim.notify("DevOps: " .. (err or "ready failed"), vim.log.levels.ERROR) end
    vim.notify("DevOps: #" .. n .. " marked ready for review", vim.log.levels.INFO)
    cache_invalidate("gh_prs"); cache_invalidate("gh_reviews"); if is_open() then load_section(true) end
  end)
end

local function gh_merge()
  local item, repo, n = pr_item()
  if not item then return end
  vim.ui.select({ "Yes, squash merge", "Cancel" }, { prompt = "Merge #" .. n .. "?" }, function(choice)
    if not choice or choice:match("^Cancel") then return end
    gh.pr_merge(repo, n, function(ok, _, err)
      if not ok then return vim.notify("DevOps: " .. (err or "merge failed"), vim.log.levels.ERROR) end
      vim.notify("DevOps: #" .. n .. " merged!", vim.log.levels.INFO)
      cache_invalidate("gh_prs"); cache_invalidate("gh_reviews"); if is_open() then load_section(true) end
    end)
  end)
end

local function gh_diff()
  local item, repo, n = pr_item()
  if not item then return end
  gh.pr_diff(repo, n, function(ok, diff_text, err)
    if not ok then return vim.notify("DevOps: " .. (err or "diff failed"), vim.log.levels.ERROR) end
    local diff_viewer = require("plugins.utils.devops.ui.diff_viewer")
    diff_viewer.open(diff_text, "Diff #" .. n, { pr = { repo = repo, number = n } })
  end)
end

local function gh_checkout()
  local item, repo, n = pr_item()
  if not item then return end
  gh.pr_checkout(repo, n, function(ok, _, err)
    if not ok then return vim.notify("DevOps: " .. (err or "checkout failed — cwd must be the repo"), vim.log.levels.ERROR) end
    vim.notify("DevOps: checked out #" .. n, vim.log.levels.INFO)
  end)
end

local function gh_create_pr()
  local sec_id = current_section_id()
  if sec_id ~= "gh_prs" and sec_id ~= "gh_reviews" then
    vim.notify("DevOps: switch to a GitHub section first", vim.log.levels.INFO)
    return
  end
  if not gh.available() then return vim.notify("DevOps: gh CLI not found", vim.log.levels.ERROR) end
  input.open("PR Title", "", function(title)
    if not title or title == "" then return end
    input.open("PR Body (optional)", "", function(body)
      gh.pr_create(title, body or "", nil, function(ok, out, err)
        if not ok then return vim.notify("DevOps: " .. (err or "PR creation failed"), vim.log.levels.ERROR) end
        vim.notify("DevOps: PR created", vim.log.levels.INFO)
        cache_invalidate("gh_prs")
        cache_invalidate("gh_reviews")
        load_section(true)
      end)
    end)
  end)
end

local function toggle_bookmark()
  local item = current_item()
  if not item then return end

  local tab_id = current_tab_id()
  local bm_key
  if item.kind == "jira" then
    bm_key = item.key
  elseif item.kind == "pr" then
    bm_key = (item.pr.repository and item.pr.repository.nameWithOwner or "") .. "#" .. tostring(item.pr.number)
  else
    return
  end

  local pins = state.bookmarks[tab_id] or {}
  local idx
  for i, b in ipairs(pins) do
    local k = b.kind == "jira" and b.key or ((b.repo_full or "") .. "#" .. tostring(b.number))
    if k == bm_key then
      idx = i
      break
    end
  end

  if idx then
    table.remove(pins, idx)
    vim.notify("DevOps: unpinned", vim.log.levels.INFO)
  else
    if item.kind == "jira" then
      pins[#pins + 1] = {
        kind = "jira",
        key = item.key,
        id = item.id,
        title = item.title or item.key,
        type_name = item.type_name or "",
      }
    elseif item.kind == "pr" then
      pins[#pins + 1] = {
        kind = "pr",
        number = item.pr.number,
        title = item.pr.title,
        url = item.pr.url,
        repo = item.pr.repository and item.pr.repository.name or "",
        repo_full = item.pr.repository and item.pr.repository.nameWithOwner or "",
      }
    end
    vim.notify("DevOps: pinned", vim.log.levels.INFO)
  end

  state.bookmarks[tab_id] = pins
  store.save_bookmarks(state.bookmarks)
end

---------------------------------------------------------------------------
-- Scope / Done toggles
---------------------------------------------------------------------------

local function toggle_scope()
  local sec_id = current_section_id()

  -- GitHub Reviews: toggle sort order
  if sec_id == "gh_reviews" then
    state.reviews_sort = state.reviews_sort == "newest" and "oldest" or "newest"
    local cached = cache_get("gh_reviews")
    if cached then
      render_github(cached, "GitHub · Reviews", true)
    end
    render_footer()
    return
  end

  -- Jira: toggle sprint/project scope
  if not state.sprint then
    return vim.notify("DevOps: no active sprints — scope toggle N/A", vim.log.levels.INFO)
  end
  if state.scope_override == "project" then
    state.scope_override = nil
  else
    state.scope_override = "project"
  end
  render_sidebar()
  update_winbar()
  if sec_id == "jira_issues" then cache_invalidate("jira_issues"); load_section(true) end
end

local function toggle_done()
  state.include_done = not state.include_done
  render_sidebar()
  update_winbar()
  if current_section_id() == "jira_issues" then cache_invalidate("jira_issues"); load_section(true) end
end

---------------------------------------------------------------------------
-- Help popup
---------------------------------------------------------------------------

local function show_help()
  local sec_id = current_section_id()
  local keys
  if sec_id == "jira_issues" then
    keys = {
      { "↵",     "Open issue detail" },
      { "c",     "Add comment" },
      { "e",     "Edit summary/description" },
      { "a",     "Assign issue" },
      { "n",     "Create new issue" },
      { "y",     "Clone selected issue" },
      { "/",     "Search Jira" },
      { "*",     "Pin/unpin selected item" },
      { "m",     "Move (change status)" },
      { "u",     "Change assignee filter" },
      { "p",     "Switch project" },
      { "b",     "Switch board" },
      { "s",     "Toggle scope (sprint/project)" },
      { "h",     "Toggle show Done issues" },
      { "r",     "Refresh" },
      { "o",     "Open in browser" },
      { "Tab",   "Next section" },
      { "S-Tab", "Prev section" },
      { "H/L",   "Previous/next tab" },
      { "{/}",   "Previous/next tab" },
      { "S-←",   "Focus sidebar" },
      { "q/Esc", "Close" },
    }
  elseif sec_id == "jira_sprint" or sec_id == "jira_epics" or sec_id == "jira_backlog" then
    keys = {
      { "↵",     "Open issue detail" },
      { "c",     "Add comment" },
      { "a",     "Assign issue" },
      { "m",     "Move (change status)" },
      { "/",     "Search Jira" },
      { "*",     "Pin/unpin selected item" },
      { "p",     "Switch project" },
      { "b",     "Switch board" },
      { "r",     "Refresh" },
      { "o",     "Open in browser" },
      { "Tab",   "Next section" },
      { "S-Tab", "Prev section" },
      { "H/L",   "Previous/next tab" },
      { "{/}",   "Previous/next tab" },
      { "S-←",   "Focus sidebar" },
      { "q/Esc", "Close" },
    }
  else
    keys = {
      { "↵",     "Open PR detail" },
      { "a",     "Approve PR" },
      { "R",     "Request changes" },
      { "c",     "Comment on PR" },
      { "d",     "View diff" },
      { "D",     "Mark ready for review" },
      { "m",     "Merge (squash)" },
      { "x",     "Checkout branch" },
      { "N",     "Create new PR" },
      { "*",     "Pin/unpin selected item" },
      { "r",     "Refresh" },
      { "o",     "Open in browser" },
      { "Tab",   "Next section" },
      { "S-Tab", "Prev section" },
      { "H/L",   "Previous/next tab" },
      { "{/}",   "Previous/next tab" },
      { "S-←",   "Focus sidebar" },
      { "q/Esc", "Close" },
    }
  end

  local lines = { "", "  Keybindings (" .. current_section_label() .. ")", "" }
  for _, k in ipairs(keys) do
    lines[#lines + 1] = "   " .. render.pad(k[1], 7) .. " " .. k[2]
  end
  lines[#lines + 1] = ""

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local w = 44
  local h = #lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", width = w, height = h,
    row = math.floor((vim.o.lines - h) / 2),
    col = math.floor((vim.o.columns - w) / 2),
    style = "minimal", border = "rounded",
    title = " Help (press any key) ", title_pos = "center",
  })
  local function close_help() vim.api.nvim_win_close(win, true) end
  vim.keymap.set("n", "q", close_help, { buffer = buf })
  vim.keymap.set("n", "<C-d>", close_help, { buffer = buf })
  vim.keymap.set("n", "<Esc>", close_help, { buffer = buf })
  vim.keymap.set("n", "?", close_help, { buffer = buf })
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf, once = true,
    callback = function() if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end end,
  })
end

---------------------------------------------------------------------------
-- Dispatched actions: routes c/a by current item kind
---------------------------------------------------------------------------

local function dispatch_comment()
  local item = current_item()
  if not item then return end
  if item.kind == "jira" then jira_comment()
  elseif item.kind == "pr" then gh_comment()
  end
end

local function dispatch_action_a()
  local item = current_item()
  if not item then return end
  if item.kind == "jira" then jira_assign()
  elseif item.kind == "pr" then gh_approve()
  end
end

-- 'm' = move: Jira issue → change status (transition), PR → merge.
local function dispatch_m()
  local item = current_item()
  if item and item.kind == "pr" then gh_merge() else transition() end
end

---------------------------------------------------------------------------
-- Pane focus
---------------------------------------------------------------------------
local function focus_content()
  if not is_open() then return end
  vim.api.nvim_set_current_win(state.content.win)
  if state.content_cursor then
    pcall(vim.api.nvim_win_set_cursor, state.content.win, state.content_cursor)
  end
end

local function focus_sidebar()
  if not (state.sidebar.win and vim.api.nvim_win_is_valid(state.sidebar.win)) then return end
  if is_open() then state.content_cursor = vim.api.nvim_win_get_cursor(state.content.win) end
  vim.api.nvim_set_current_win(state.sidebar.win)
  local line = state.sidebar_line or sidebar_line_for_section(state.section)
  if line then pcall(vim.api.nvim_win_set_cursor, state.sidebar.win, { line, 0 }) end
end

-- Move the sidebar cursor only between selectable section rows.
local function sidebar_move(dir)
  if not (state.sidebar.win and vim.api.nvim_win_is_valid(state.sidebar.win)) then return end
  local cur = vim.api.nvim_win_get_cursor(state.sidebar.win)[1]
  local sec = (state.sidebar_rows and state.sidebar_rows[cur]) or state.section
  sec = sec + dir
  if sec < 1 then sec = section_count() elseif sec > section_count() then sec = 1 end
  local line = sidebar_line_for_section(sec)
  if line then
    vim.api.nvim_win_set_cursor(state.sidebar.win, { line, 0 })
    state.sidebar_line = line
  end
end

---------------------------------------------------------------------------
-- Project / board selection
---------------------------------------------------------------------------
local function persist_prefs()
  store.save({
    project_key = state.project and state.project.key,
    project_name = state.project and state.project.name,
    board_id = state.board and state.board.id,
    board_name = state.board and state.board.name,
  })
end

-- Load the board's columns and detect whether it has active sprints, then cb().
-- A scrum board can have several parallel active sprints, so we scope the issue
-- list to openSprints() (all of them) rather than a single sprint.
local function load_board_columns(cb)
  state.columns, state.sprint = nil, nil
  if not state.board then return cb() end
  api.board_config(state.board.id, function(ok, cols)
    state.columns = (ok and cols and #cols > 0) and cols or nil
    api.active_sprint(state.board.id, function(ok2, sprint)
      state.sprint = (ok2 and sprint) and { open = true } or nil
      cb()
    end)
  end)
end

-- Resolve which board to use for the project (prompt if more than one),
-- load its columns, persist, then cb().
local function resolve_board_then(cb)
  state.board, state.columns = nil, nil
  api.list_boards(state.project.key, function(ok, boards)
    local function finalize()
      persist_prefs()
      load_board_columns(cb)
    end
    if not ok or #boards == 0 then return finalize() end
    if #boards == 1 then
      state.board = { id = boards[1].id, name = boards[1].name }
      return finalize()
    end
    vim.ui.select(boards, {
      prompt = "Select board for " .. state.project.key .. " (defines the columns):",
      format_item = function(b) return b.name .. "  (" .. (b.type or "") .. ")" end,
    }, function(choice)
      if choice then state.board = { id = choice.id, name = choice.name } end
      finalize()
    end)
  end)
end

-- Re-pick the board for the current project.
local function pick_board()
  if not state.project then
    return vim.notify("DevOps: pick a project first (p)", vim.log.levels.INFO)
  end
  invalidate_tab_cache("jira")
  resolve_board_then(function() switch_section(1, tab_index_by_id("jira")) end)
end

-- Prompt for a project, resolve its board, then cb().
local function pick_project(cb)
  if not client.configured() then
    vim.notify("DevOps: configure Jira first (:JiraAuth)", vim.log.levels.WARN)
    return cb and cb()
  end
  api.list_projects(nil, function(ok, projects, err)
    if not ok then
      vim.notify("DevOps: " .. (err or "project list failed"), vim.log.levels.ERROR)
      return cb and cb()
    end
    vim.ui.select(projects, {
      prompt = "Select Jira project:",
      format_item = function(p) return p.key .. "  —  " .. (p.name or "") end,
    }, function(choice)
      if not choice then return cb and cb() end
      state.project = { key = choice.key, id = choice.id, name = choice.name }
      invalidate_tab_cache("jira")
      resolve_board_then(function() if cb then cb() end end)
    end)
  end)
end

-- Make sure a project is selected before the first Jira load.
local function ensure_project(cb)
  if state.project then return cb() end

  local prefs = store.load()
  if prefs and prefs.project_key then
    state.project = { key = prefs.project_key, name = prefs.project_name }
    state.board = prefs.board_id and { id = prefs.board_id, name = prefs.board_name } or nil
    return load_board_columns(cb)
  end
  if config.options.jira.project and config.options.jira.project ~= "" then
    state.project = { key = config.options.jira.project }
    return resolve_board_then(cb)
  end
  pick_project(cb)
end

---------------------------------------------------------------------------
-- Window lifecycle
---------------------------------------------------------------------------
local function close()
  stop_spinner()
  vim.schedule(function()
    pcall(vim.api.nvim_clear_autocmds, { group = "DevOpsWin" })
    for _, w in ipairs({ state.sidebar.win, state.content.win, state.footer.win }) do
      if w and vim.api.nvim_win_is_valid(w) then pcall(vim.api.nvim_win_close, w, true) end
    end
    for _, b in ipairs({ state.sidebar.buf, state.content.buf, state.footer.buf }) do
      if b and vim.api.nvim_buf_is_valid(b) then pcall(vim.api.nvim_buf_delete, b, { force = true }) end
    end
    state.sidebar = { win = nil, buf = nil }
    state.content = { win = nil, buf = nil }
    state.footer = { win = nil, buf = nil }
    state.rows = {}
  end)
end

-- Hide: close windows but keep buffers + state so we can restore quickly.
local function hide()
  pcall(vim.api.nvim_clear_autocmds, { group = "DevOpsWin" })
  for _, w in ipairs({ state.sidebar.win, state.content.win, state.footer.win }) do
    if w and vim.api.nvim_win_is_valid(w) then pcall(vim.api.nvim_win_close, w, true) end
  end
  state.sidebar.win = nil
  state.content.win = nil
  state.footer.win = nil
end

-- Is the dashboard hidden (buffers exist but windows don't)?
local function is_hidden()
  return state.content.buf ~= nil
    and vim.api.nvim_buf_is_valid(state.content.buf)
    and not is_open()
end

local function open_float_windows()
  local total = vim.o.columns - 2
  local footer_h = 2
  local height = vim.o.lines - 2 - footer_h - 2 -- room for footer + gap
  local sw = 32
  local cw = total - sw - 3
  local row = 0
  local col0 = 0

  local winhl = "Normal:Normal,FloatBorder:DevOpsBorder,FloatTitle:DevOpsTitle"

  state.sidebar.buf = make_buf()
  state.sidebar.win = vim.api.nvim_open_win(state.sidebar.buf, false, {
    relative = "editor", row = row, col = col0, width = sw, height = height,
    style = "minimal", border = "rounded",
  })
  state.content.buf = make_buf()
  state.content.win = vim.api.nvim_open_win(state.content.buf, true, {
    relative = "editor", row = row, col = col0 + sw + 3, width = cw, height = height,
    style = "minimal", border = "rounded",
  })

  -- Footer bar
  state.footer.buf = make_buf()
  state.footer.win = vim.api.nvim_open_win(state.footer.buf, false, {
    relative = "editor", row = height + 2, col = col0, width = total, height = footer_h,
    style = "minimal", border = "rounded", focusable = false,
  })

  vim.wo[state.content.win].cursorline = true
  vim.wo[state.sidebar.win].cursorline = true
  vim.wo[state.sidebar.win].winhighlight = winhl .. ",CursorLine:DevOpsSidebarSel"
  vim.wo[state.content.win].winhighlight = winhl
  vim.wo[state.footer.win].winhighlight = winhl
end

-- Restore hidden float windows with existing buffers (preserves content).
local function restore_float_windows()
  local total = vim.o.columns - 2
  local footer_h = 2
  local height = vim.o.lines - 2 - footer_h - 2
  local sw = 32
  local cw = total - sw - 3
  local row = 0
  local col0 = 0

  local winhl = "Normal:Normal,FloatBorder:DevOpsBorder,FloatTitle:DevOpsTitle"

  state.sidebar.win = vim.api.nvim_open_win(state.sidebar.buf, false, {
    relative = "editor", row = row, col = col0, width = sw, height = height,
    style = "minimal", border = "rounded",
  })
  state.content.win = vim.api.nvim_open_win(state.content.buf, true, {
    relative = "editor", row = row, col = col0 + sw + 3, width = cw, height = height,
    style = "minimal", border = "rounded",
  })

  -- Restore or recreate footer
  if not state.footer.buf or not vim.api.nvim_buf_is_valid(state.footer.buf) then
    state.footer.buf = make_buf()
  end
  state.footer.win = vim.api.nvim_open_win(state.footer.buf, false, {
    relative = "editor", row = height + 2, col = col0, width = total, height = footer_h,
    style = "minimal", border = "rounded", focusable = false,
  })

  vim.wo[state.content.win].cursorline = true
  vim.wo[state.sidebar.win].cursorline = true
  vim.wo[state.sidebar.win].winhighlight = winhl .. ",CursorLine:DevOpsSidebarSel"
  vim.wo[state.content.win].winhighlight = winhl
  vim.wo[state.footer.win].winhighlight = winhl
  render_footer()
end

local function open_tab_windows()
  vim.cmd("tabnew")
  state.content.win = vim.api.nvim_get_current_win()
  state.content.buf = make_buf()
  vim.api.nvim_win_set_buf(state.content.win, state.content.buf)
  vim.cmd("leftabove vsplit")
  state.sidebar.win = vim.api.nvim_get_current_win()
  state.sidebar.buf = make_buf()
  vim.api.nvim_win_set_buf(state.sidebar.win, state.sidebar.buf)
  vim.api.nvim_win_set_width(state.sidebar.win, 32)
  vim.api.nvim_set_current_win(state.content.win)
  vim.wo[state.content.win].cursorline = true
  vim.wo[state.sidebar.win].cursorline = true
  vim.wo[state.sidebar.win].winhighlight = "CursorLine:DevOpsSidebarSel"
end

local function map(lhs, fn, desc)
  vim.keymap.set("n", lhs, fn, { buffer = state.content.buf, nowait = true, silent = true, desc = "DevOps: " .. desc })
end

local function setup_keymaps()
  local function smart_back()
    if state.in_detail then nav_back() else hide() end
  end
  map("q", smart_back, "back / hide")
  map("<C-d>", smart_back, "back / hide")
  map("<Esc>", smart_back, "back / hide")
  map("<BS>", nav_back, "back")
  map("Q", close, "close (destroy)")
  map("<Tab>", function() switch_section(state.section + 1) end, "next section")
  map("<S-Tab>", function() switch_section(state.section - 1) end, "prev section")
  for i = 1, 9 do
    map(tostring(i), function()
      if i <= section_count() then switch_section(i) end
    end, "section " .. i)
  end
  map("H", function() switch_tab(-1) end, "previous tab")
  map("L", function() switch_tab(1) end, "next tab")
  map("{", function() switch_tab(-1) end, "previous tab")
  map("}", function() switch_tab(1) end, "next tab")
  map("<CR>", open_detail, "open")
  map("r", function() load_section(true); refresh_notifications() end, "refresh")
  map("o", open_browser, "open in browser")
  map("u", select_user, "select user")
  map("p", function() pick_project(function() switch_section(1, tab_index_by_id("jira")) end) end, "pick project")
  map("b", pick_board, "pick board")
  map("<S-Left>", focus_sidebar, "focus sidebar")
  -- Write actions (dispatched by item kind for c/a)
  map("c", dispatch_comment, "comment")
  map("a", dispatch_action_a, "assign/approve")
  map("e", jira_edit, "edit issue")
  map("n", jira_create, "new issue")
  map("y", jira_clone, "clone issue")
  map("/", dispatch_search, "search")
  map("*", toggle_bookmark, "bookmark")
  -- GitHub PR actions
  map("R", gh_request_changes, "request changes")
  map("D", gh_ready, "mark ready")
  map("m", dispatch_m, "move issue / merge PR")
  map("d", gh_diff, "view diff")
  map("x", gh_checkout, "checkout PR")
  map("N", gh_create_pr, "new PR")
  -- Toggles
  map("s", toggle_scope, "toggle scope")
  map("h", toggle_done, "toggle done")
  -- Help
  map("?", show_help, "help")
end

local function setup_sidebar_keymaps()
  local b = state.sidebar.buf
  local function smap(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = b, nowait = true, silent = true, desc = "DevOps: " .. desc })
  end
  smap("q", hide, "hide (toggle off)")
  smap("<C-d>", hide, "hide (toggle off)")
  smap("<Esc>", hide, "hide (toggle off)")
  smap("Q", close, "close (destroy)")
  smap("<S-Right>", focus_content, "focus list")
  smap("<Right>", focus_content, "focus list")
  smap("l", focus_content, "focus list")
  smap("j", function() sidebar_move(1) end, "next view")
  smap("k", function() sidebar_move(-1) end, "prev view")
  smap("H", function() switch_tab(-1) end, "previous tab")
  smap("L", function() switch_tab(1) end, "next tab")
  smap("{", function() switch_tab(-1) end, "previous tab")
  smap("}", function() switch_tab(1) end, "next tab")
  smap("<Down>", function() sidebar_move(1) end, "next view")
  smap("<Up>", function() sidebar_move(-1) end, "prev view")
  smap("<CR>", function()
    local line = vim.api.nvim_win_get_cursor(state.sidebar.win)[1]
    local idx = state.sidebar_rows and state.sidebar_rows[line]
    if idx then switch_section(idx) end
    focus_content()
  end, "select section")
end

local function setup_autocmds()
  local grp = vim.api.nvim_create_augroup("DevOpsWin", { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = grp,
    pattern = tostring(state.content.win),
    once = true,
    callback = close,
  })
  -- Focus guard: when focus escapes to a non-DevOps window, pull it back.
  -- (Only in float layout — tab layout coexists with other windows.)
  if state.layout == "float" then
    vim.api.nvim_create_autocmd("WinEnter", {
      group = grp,
      callback = function()
        if not is_open() then return true end -- remove autocmd
        local cur = vim.api.nvim_get_current_win()
        -- Allow DevOps windows and floating windows (sub-floats like input, help, vim.ui.select)
        if cur == state.content.win or cur == state.sidebar.win then return end
        local win_cfg = vim.api.nvim_win_get_config(cur)
        if win_cfg.relative and win_cfg.relative ~= "" then return end -- it's a float, allow it
        -- Landed on a regular window — snap back to content (defer to let
        -- other scheduled callbacks like mention-refocus run first).
        vim.defer_fn(function()
          if not is_open() then return end
          local now = vim.api.nvim_get_current_win()
          -- Re-check: if something already moved us to a float, don't fight it.
          if now == state.content.win or now == state.sidebar.win then return end
          local cfg = vim.api.nvim_win_get_config(now)
          if cfg.relative and cfg.relative ~= "" then return end
          vim.api.nvim_set_current_win(state.content.win)
        end, 50)
      end,
    })
  end
end

-- Ensure the current Jira user is known (default assignee) before first load.
local function ensure_me(cb)
  if not client.configured() or client.account_id() then return cb() end
  client.myself(function(ok, _, err)
    if not ok then vim.notify("DevOps: Jira auth failed — " .. (err or "?"), vim.log.levels.WARN) end
    cb()
  end)
end

---------------------------------------------------------------------------
-- Prefetch — after the initial section loads, silently warm the cache
-- for all other sections so switching feels instant.
---------------------------------------------------------------------------
local prefetched = false
local function prefetch_other_sections()
  if prefetched then return end
  prefetched = true

  -- Jira sections
  if client.configured() then
    local account = client.account_id()
    local project_key = state.project and state.project.key or nil

    -- Skip the active section (load_section already owns its cache) so we don't
    -- race/clobber it; mirror its board-aware include_done for the rest.
    if account and current_section_id() ~= "jira_issues" and not cache_get("jira_issues") then
      api.search({
        account_id = account,
        project_key = project_key,
        open_sprints = state.sprint ~= nil,
        include_done = state.include_done or state.columns ~= nil,
      }, function(ok, issues)
        if ok and issues then cache_set("jira_issues", issues) end
      end)
    end

    if state.sprint and not cache_get("jira_sprint") then
      api.search({
        account_id = nil,
        project_key = project_key,
        open_sprints = true,
        include_done = true,
      }, function(ok, issues)
        if ok and issues then cache_set("jira_sprint", issues) end
      end)
    end

    if project_key and not cache_get("jira_epics") then
      api.epics(project_key, function(ok, issues)
        if ok and issues then cache_set("jira_epics", issues) end
      end)
    end

    if project_key and not cache_get("jira_backlog") then
      api.backlog(project_key, function(ok, issues)
        if ok and issues then cache_set("jira_backlog", issues) end
      end)
    end
  end

  -- GitHub sections
  if gh.available() then
    if not cache_get("gh_prs") then
      gh.my_prs(function(ok, prs)
        if ok and prs then cache_set("gh_prs", prs) end
      end)
    end
    if not cache_get("gh_reviews") then
      gh.my_reviews(function(ok, prs)
        if ok and prs then cache_set("gh_reviews", prs) end
      end)
    end
  end
end

function M.open(layout)
  layout = layout or config.options.layout or "float"

  -- Toggle: if visible, hide it (keep state); if hidden, restore it.
  if is_open() then
    hide()
    return
  end
  if is_hidden() then
    state.bookmarks = store.load_bookmarks()
    restore_float_windows()
    setup_keymaps()
    setup_sidebar_keymaps()
    setup_autocmds()
    render_sidebar()
    render_footer()
    update_winbar()
    refresh_notifications()
    if state.sidebar_line then
      pcall(vim.api.nvim_win_set_cursor, state.sidebar.win, { state.sidebar_line, 0 })
    end
    if state.content_cursor then
      pcall(vim.api.nvim_win_set_cursor, state.content.win, state.content_cursor)
    end
    return
  end

  -- Fresh open.
  state.layout = layout
  state.tab = 1
  state.section = 1
  state.content_cursor = nil
  state.nav_stack = {}
  state.in_detail = false
  state.detail_kind = nil
  state.gh_notif_count = 0
  state.bookmarks = store.load_bookmarks()

  if layout == "tab" then open_tab_windows() else open_float_windows() end
  vim.wo[state.sidebar.win].cursorline = true
  setup_keymaps()
  setup_sidebar_keymaps()
  setup_autocmds()
  render_sidebar()
  render_footer()
  update_winbar()
  -- Park the sidebar cursor on the active section so it never starts on a
  -- non-selectable (info) line.
  state.sidebar_line = sidebar_line_for_section(state.section)
  if state.sidebar.win and state.sidebar_line then
    pcall(vim.api.nvim_win_set_cursor, state.sidebar.win, { state.sidebar_line, 0 })
  end
  ensure_me(function()
    if not is_open() then return end
    if client.configured() then
      ensure_project(function()
        if not is_open() then return end
        render_sidebar() -- now that project/board/sprint are known
        render_footer()
        update_winbar()
        refresh_notifications()
        load_section()
        prefetch_other_sections()
      end)
    else
      refresh_notifications()
      load_section()
      prefetch_other_sections()
    end
  end)
end

return M
