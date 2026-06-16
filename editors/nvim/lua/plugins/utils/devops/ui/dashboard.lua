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

local SECTIONS = {
  { id = "jira_issues", group = "Jira", label = "My Issues" },
  { id = "gh_prs", group = "GitHub", label = "My PRs" },
  { id = "gh_reviews", group = "GitHub", label = "Reviews" },
}

local state = {
  layout = "float",
  sidebar = { win = nil, buf = nil },
  content = { win = nil, buf = nil },
  footer = { win = nil, buf = nil },
  section = 1,
  jira_user = nil,   -- { account_id, name } or nil => current user
  project = nil,     -- { key, id, name }
  board = nil,       -- { id, name }
  sprint = nil,      -- { id, name } active sprint, or nil
  columns = nil,     -- ordered board columns, or nil for a flat list
  rows = {},         -- 1-based content line → item
  sidebar_rows = {}, -- 1-based sidebar line → section index
  sidebar_line = nil,-- remembered sidebar cursor line
  content_cursor = nil, -- remembered content cursor {row,col}
  scope_override = nil, -- nil | "project" | "sprint"
  include_done = false, -- when true, include Done issues
}

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
local GROUP_ICON = { Jira = "", GitHub = "" }

local function render_sidebar()
  local lines, hls, rows = {}, {}, {}
  local sw = (state.sidebar.win and vim.api.nvim_win_is_valid(state.sidebar.win))
    and vim.api.nvim_win_get_width(state.sidebar.win) or 32
  local function push(text, hl)
    lines[#lines + 1] = text
    if hl then hls[#hls + 1] = { line = #lines - 1, col_start = 0, col_end = #text, hl = hl } end
  end

  push("")
  push("   DEVOPS", "DevOpsTitle")

  -- Group the sections in declared order so we can nest extras per group.
  local order, by_group = {}, {}
  for i, sec in ipairs(SECTIONS) do
    if not by_group[sec.group] then by_group[sec.group] = {}; order[#order + 1] = sec.group end
    table.insert(by_group[sec.group], { idx = i, sec = sec })
  end

  for _, gname in ipairs(order) do
    push("")
    push("  " .. (GROUP_ICON[gname] or "") .. "  " .. gname:upper(), "DevOpsGroup")
    for _, e in ipairs(by_group[gname]) do
      local active = (e.idx == state.section)
      local text = (active and "  ▌ " or "    ") .. e.sec.label
      lines[#lines + 1] = text
      rows[#lines] = e.idx
      if active then
        hls[#hls + 1] = { line = #lines - 1, col_start = 0, col_end = 5, hl = "DevOpsSectionBar" }
        hls[#hls + 1] = { line = #lines - 1, col_start = 5, col_end = #text, hl = "DevOpsSectionActive" }
      end
    end
    -- Jira context (project / board / scope) shown as a labeled tree block.
    if gname == "Jira" then
      local scope_label
      if state.sprint then
        if state.scope_override == "project" then
          scope_label = "project (all)"
        else
          scope_label = "active sprints"
        end
      end
      local meta = { { "project", state.project and state.project.key or "(none)", "DevOpsId" } }
      if state.board then meta[#meta + 1] = { "board", state.board.name, "DevOpsDim" } end
      if scope_label then meta[#meta + 1] = { "scope", scope_label, "DevOpsStatusProgress" } end
      if state.include_done then meta[#meta + 1] = { "filter", "+Done", "DevOpsWarn" } end
      for i, m in ipairs(meta) do
        local conn = (#meta == 1 and "╶") or (i == 1 and "╭") or (i == #meta and "╰") or "│"
        local prefix = "  " .. conn .. " " .. render.pad(m[1], 7) .. " "
        local avail = math.max(4, sw - vim.fn.strdisplaywidth(prefix) - 1)
        local text = prefix .. render.truncate(m[2], avail)
        lines[#lines + 1] = text
        hls[#hls + 1] = { line = #lines - 1, col_start = 0, col_end = #prefix, hl = "DevOpsDim" }
        hls[#hls + 1] = { line = #lines - 1, col_start = #prefix, col_end = #text, hl = m[3] }
      end
    end
  end

  push("")
  push("  ? help", "DevOpsDim")

  set_buf_lines(state.sidebar.buf, lines)
  apply_highlights(state.sidebar.buf, hls)
  state.sidebar_rows = rows
end

---------------------------------------------------------------------------
-- Footer bar — always-visible 2-line key legend at the bottom.
---------------------------------------------------------------------------
local footer_ns = vim.api.nvim_create_namespace("DevOpsFooter")

local function render_footer()
  if not state.footer.buf or not vim.api.nvim_buf_is_valid(state.footer.buf) then return end
  local sec_id = SECTIONS[state.section] and SECTIONS[state.section].id or ""
  local groups
  if sec_id == "jira_issues" then
    groups = {
      { "Navigate", { "↵ open", "j/k move", "Tab section", "←→ pane" } },
      { "Actions",  { "c comment", "e edit", "a assign", "t move", "n new", "y clone" } },
      { "Toggles",  { "s scope", "H done", "p project", "b board", "r refresh" } },
      { "Window",   { "o browser", "? help", "q hide", "Q close" } },
    }
  else
    groups = {
      { "Navigate", { "↵ open", "j/k move", "Tab section", "←→ pane" } },
      { "Actions",  { "a approve", "R changes", "c comment", "d diff", "m merge" } },
      { "PR",       { "D ready", "x checkout", "r refresh" } },
      { "Window",   { "o browser", "? help", "q hide", "Q close" } },
    }
  end

  -- Build two lines, distributing groups across them
  local line1_parts, line2_parts = {}, {}
  local hls1, hls2 = {}, {}
  local mid = math.ceil(#groups / 2)

  local function build_line(group_list)
    local parts, highlights = {}, {}
    local col = 1 -- start with 1 char padding
    for gi, grp in ipairs(group_list) do
      local label = grp[1]
      local keys = grp[2]
      -- Group label
      highlights[#highlights + 1] = { col_start = col, col_end = col + #label, hl = "DevOpsSection" }
      local segment = label .. "  "
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
        if ki < #keys then segment = segment .. "  " end
      end
      parts[#parts + 1] = segment
      col = col + #segment
      if gi < #group_list then
        local sep = "   │   "
        parts[#parts + 1] = sep
        highlights[#highlights + 1] = { col_start = col + 3, col_end = col + 3 + #"│", hl = "DevOpsBorder" }
        col = col + #sep
      end
    end
    return " " .. table.concat(parts), highlights
  end

  local text1, h1 = build_line({ groups[1], groups[2] })
  local text2, h2 = build_line({ groups[3], groups[4] })

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

local function header(title, subtitle)
  local lines = { "", "  " .. title, "  " .. subtitle, "" }
  local hls = {
    { line = 1, col_start = 0, col_end = #lines[2], hl = "DevOpsTitle" },
    { line = 2, col_start = 0, col_end = #lines[3], hl = "DevOpsDim" },
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

local function render_jira(issues, assignee_name, columns)
  local scope = state.sprint and "Active sprints" or (state.project and state.project.key or "no project")
  local subtitle = scope .. "  ·  " .. assignee_name .. "  ·  " .. #issues .. " issue" .. (#issues == 1 and "" or "s")
  local lines, hls = header("Jira  ·  My Issues", subtitle)
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
    rows[#lines] = { kind = "jira", key = issue.key, id = issue.id, status = f.status and f.status.name or nil }
  end

  -- Colored column header with the count right-aligned.
  local function add_column_header(name, count, cat)
    local left = "  ▌ " .. name:upper()
    local cnt = tostring(count)
    local pad = math.max(2, w - vim.fn.strdisplaywidth(left) - #cnt - 2)
    local head = left .. string.rep(" ", pad) .. cnt
    lines[#lines + 1] = head
    local lidx = #lines - 1
    hls[#hls + 1] = { line = lidx, col_start = 0, col_end = #left, hl = render.column_hl(cat) }
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

local function render_github(prs, title, show_meta)
  local subtitle = #prs .. " pull request" .. (#prs == 1 and "" or "s")
  local lines, hls = header(title, subtitle)
  local rows = {}
  local w = content_width()

  for pi, pr in ipairs(prs) do
    if show_meta and pi > 1 then lines[#lines + 1] = "" end
    local icon = pr.isDraft and "" or ""
    local num = "#" .. tostring(pr.number or "?")
    local numpad = render.pad(num, 6)
    local repo = (pr.repository and pr.repository.name) or ""
    local tag = (not show_meta) and repo or ""
    local summary = render.truncate(pr.title or "", math.max(10, w - 14 - #tag))

    local prefix = "  " .. icon .. "  "
    local text = prefix .. numpad .. "  " .. summary
    if tag ~= "" then text = text .. "  " .. tag end
    lines[#lines + 1] = text
    local lidx = #lines - 1
    hls[#hls + 1] = { line = lidx, col_start = #("  "), col_end = #("  ") + #icon, hl = pr.isDraft and "DevOpsPrDraft" or "DevOpsPrOpen" }
    local num_start = #prefix
    hls[#hls + 1] = { line = lidx, col_start = num_start, col_end = num_start + #num, hl = "DevOpsId" }
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
    end
  end

  if #prs == 0 then lines[#lines + 1] = "  (none)" end
  set_buf_lines(state.content.buf, lines)
  apply_highlights(state.content.buf, hls)
  state.rows = rows
  park_cursor_on_first_item()
end

local function set_message(msg)
  set_buf_lines(state.content.buf, { "", "  " .. msg })
  apply_highlights(state.content.buf, {})
  state.rows = {}
end

---------------------------------------------------------------------------
-- Data loading per section
---------------------------------------------------------------------------
-- Cache: avoid re-fetching when switching back to a section within TTL.
local cache = {} -- { [sec_id] = { data = ..., ts = os.time() } }
local CACHE_TTL = 120 -- seconds

local function cache_get(sec_id)
  local entry = cache[sec_id]
  if entry and (os.time() - entry.ts) < CACHE_TTL then return entry.data end
  return nil
end

local function cache_set(sec_id, data)
  cache[sec_id] = { data = data, ts = os.time() }
end

local function cache_invalidate(sec_id)
  cache[sec_id] = nil
end

local function load_section(force)
  local sec_id = SECTIONS[state.section].id

  -- Serve from cache unless forced (manual refresh)
  if not force then
    local cached = cache_get(sec_id)
    if cached then
      if sec_id == "jira_issues" then
        local name = state.jira_user and state.jira_user.name or (client.display_name() or "me")
        render_jira(cached, name, state.columns)
      else
        local title = sec_id == "gh_prs" and "GitHub · My PRs" or "GitHub · Review Requests"
        render_github(cached, title, sec_id == "gh_reviews")
      end
      return
    end
  end

  set_message("Loading…")

  if sec_id == "jira_issues" then
    if not client.configured() then
      set_message("⚠ Jira not configured — run :JiraAuth. Missing: " .. table.concat(client.missing(), ", "))
      return
    end
    local account = state.jira_user and state.jira_user.account_id or client.account_id()
    local name = state.jira_user and state.jira_user.name or (client.display_name() or "me")
    local function on_issues(ok, issues, err)
      if not is_open() or SECTIONS[state.section].id ~= sec_id then return end
      if not ok then return set_message("⚠ " .. (err or "Jira search failed")) end
      cache_set(sec_id, issues)
      render_jira(issues, name, state.columns)
    end
    local use_sprints = state.sprint ~= nil and state.scope_override ~= "project"
    api.search({
      account_id = account,
      project_key = state.project and state.project.key,
      open_sprints = use_sprints,
      include_done = state.include_done,
    }, on_issues)
  else -- gh_prs / gh_reviews
    if not gh.available() then return set_message("⚠ gh CLI not found") end
    local fn = sec_id == "gh_prs" and gh.my_prs or gh.my_reviews
    local title = sec_id == "gh_prs" and "GitHub · My PRs" or "GitHub · Review Requests"
    local show_meta = sec_id == "gh_reviews"
    fn(function(ok, prs, err)
      if not is_open() or SECTIONS[state.section].id ~= sec_id then return end
      if not ok then return set_message("⚠ " .. (err or "gh failed")) end
      cache_set(sec_id, prs)
      render_github(prs, title, show_meta)
    end)
  end
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local function current_item()
  if not is_open() then return nil end
  return state.rows[vim.api.nvim_win_get_cursor(state.content.win)[1]]
end

local function open_detail()
  local item = current_item()
  if not item then return end
  if item.kind == "jira" then
    detail.open_issue(item.key)
  elseif item.kind == "pr" then
    detail.open_pr(item.pr)
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

local function switch_section(idx)
  if idx < 1 then idx = #SECTIONS elseif idx > #SECTIONS then idx = 1 end
  state.section = idx
  state.content_cursor = nil
  render_sidebar()
  render_footer()
  state.sidebar_line = sidebar_line_for_section(idx)
  load_section()
end

local function select_user()
  if SECTIONS[state.section].id ~= "jira_issues" then
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
      switch_section(1)
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
    vim.ui.select(trs, {
      prompt = "Move " .. item.key .. ":",
      format_item = function(t) return current_status .. "  →  " .. (t.to and t.to.name or t.name) end,
    }, function(choice)
      if not choice then return end
      api.do_transition(item.key, choice.id, function(ok2, _, err2)
        if not ok2 then return vim.notify("DevOps: " .. (err2 or "transition failed"), vim.log.levels.ERROR) end
        vim.notify("DevOps: " .. item.key .. " → " .. choice.name, vim.log.levels.INFO)
        if is_open() and SECTIONS[state.section].id == "jira_issues" then cache_invalidate("jira_issues"); load_section(true) end
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
  user_picker.open(function(choice)
    insert_fn("@[" .. choice.name .. "]{" .. choice.id .. "}")
  end, { title = "Mention User" })
end

local mention_opts = { on_mention = jira_mention_handler }

local function jira_comment()
  local item = current_item()
  if not item or item.kind ~= "jira" then
    return vim.notify("DevOps: select a Jira issue first", vim.log.levels.INFO)
  end
  input.open("Comment " .. item.key, "", function(text)
    if text == "" then return end
    api.add_comment(item.key, text, function(ok, _, err)
      if not ok then return vim.notify("DevOps: " .. (err or "comment failed"), vim.log.levels.ERROR) end
      vim.notify("DevOps: comment added to " .. item.key, vim.log.levels.INFO)
      if is_open() and SECTIONS[state.section].id == "jira_issues" then cache_invalidate("jira_issues"); load_section(true) end
    end)
  end, mention_opts)
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
          if is_open() and SECTIONS[state.section].id == "jira_issues" then cache_invalidate("jira_issues"); load_section(true) end
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
        if is_open() and SECTIONS[state.section].id == "jira_issues" then cache_invalidate("jira_issues"); load_section(true) end
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
                if is_open() and SECTIONS[state.section].id == "jira_issues" then cache_invalidate("jira_issues"); load_section(true) end
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
    local fields = {
      project = { key = project_key },
      issuetype = { name = f.issuetype and f.issuetype.name or "Task" },
      summary = "CLONE - " .. (f.summary or ""),
    }
    -- Pass description ADF through directly (already ADF format)
    if f.description then fields.description = f.description end
    local me_id = client.account_id()
    if me_id then fields.assignee = { accountId = me_id } end
    api.create_issue(fields, function(ok2, data, err2)
      if not ok2 then return vim.notify("DevOps: " .. (err2 or "clone failed"), vim.log.levels.ERROR) end
      local new_key = data and data.key or "?"
      vim.notify("DevOps: cloned " .. item.key .. " → " .. new_key, vim.log.levels.INFO)
      if is_open() and SECTIONS[state.section].id == "jira_issues" then cache_invalidate("jira_issues"); load_section(true) end
    end)
  end)
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
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "diff"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(diff_text, "\n", { plain = true }))
    local w = math.floor(vim.o.columns * 0.85)
    local h = math.floor(vim.o.lines * 0.85)
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor", width = w, height = h,
      row = math.floor((vim.o.lines - h) / 2),
      col = math.floor((vim.o.columns - w) / 2),
      style = "minimal", border = "rounded",
      title = " Diff #" .. n .. " ", title_pos = "center",
    })
    vim.keymap.set("n", "q", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
    vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
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

---------------------------------------------------------------------------
-- Scope / Done toggles
---------------------------------------------------------------------------

local function toggle_scope()
  if not state.sprint then
    return vim.notify("DevOps: no active sprints — scope toggle N/A", vim.log.levels.INFO)
  end
  if state.scope_override == "project" then
    state.scope_override = nil
  else
    state.scope_override = "project"
  end
  render_sidebar()
  if SECTIONS[state.section].id == "jira_issues" then cache_invalidate("jira_issues"); load_section(true) end
end

local function toggle_done()
  state.include_done = not state.include_done
  render_sidebar()
  if SECTIONS[state.section].id == "jira_issues" then cache_invalidate("jira_issues"); load_section(true) end
end

---------------------------------------------------------------------------
-- Help popup
---------------------------------------------------------------------------

local function show_help()
  local sec_id = SECTIONS[state.section] and SECTIONS[state.section].id or ""
  local keys
  if sec_id == "jira_issues" then
    keys = {
      { "↵",     "Open issue detail" },
      { "c",     "Add comment" },
      { "e",     "Edit summary/description" },
      { "a",     "Assign issue" },
      { "n",     "Create new issue" },
      { "y",     "Clone selected issue" },
      { "t",     "Transition status" },
      { "u",     "Change assignee filter" },
      { "p",     "Switch project" },
      { "b",     "Switch board" },
      { "s",     "Toggle scope (sprint/project)" },
      { "H",     "Toggle show Done issues" },
      { "r",     "Refresh" },
      { "o",     "Open in browser" },
      { "Tab",   "Next section" },
      { "S-Tab", "Prev section" },
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
      { "r",     "Refresh" },
      { "o",     "Open in browser" },
      { "Tab",   "Next section" },
      { "S-Tab", "Prev section" },
      { "S-←",   "Focus sidebar" },
      { "q/Esc", "Close" },
    }
  end

  local lines = { "", "  Keybindings (" .. SECTIONS[state.section].label .. ")", "" }
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
  vim.keymap.set("n", "q", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
  vim.keymap.set("n", "?", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
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
  if sec < 1 then sec = #SECTIONS elseif sec > #SECTIONS then sec = 1 end
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
  resolve_board_then(function() switch_section(1) end)
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
  vim.wo[state.sidebar.win].winhighlight = winhl
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
  vim.wo[state.sidebar.win].winhighlight = winhl
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
end

local function map(lhs, fn, desc)
  vim.keymap.set("n", lhs, fn, { buffer = state.content.buf, nowait = true, silent = true, desc = "DevOps: " .. desc })
end

local function setup_keymaps()
  map("q", hide, "hide (toggle off)")
  map("<Esc>", hide, "hide (toggle off)")
  map("Q", close, "close (destroy)")
  map("<Tab>", function() switch_section(state.section + 1) end, "next section")
  map("<S-Tab>", function() switch_section(state.section - 1) end, "prev section")
  for i = 1, #SECTIONS do map(tostring(i), function() switch_section(i) end, "section " .. i) end
  map("<CR>", open_detail, "open")
  map("r", function() load_section(true) end, "refresh")
  map("o", open_browser, "open in browser")
  map("u", select_user, "select user")
  map("t", transition, "transition status")
  map("p", function() pick_project(function() switch_section(1) end) end, "pick project")
  map("b", pick_board, "pick board")
  map("<S-Left>", focus_sidebar, "focus sidebar")
  -- Write actions (dispatched by item kind for c/a)
  map("c", dispatch_comment, "comment")
  map("a", dispatch_action_a, "assign/approve")
  map("e", jira_edit, "edit issue")
  map("n", jira_create, "new issue")
  map("y", jira_clone, "clone issue")
  -- GitHub PR actions
  map("R", gh_request_changes, "request changes")
  map("D", gh_ready, "mark ready")
  map("m", gh_merge, "merge PR")
  map("d", gh_diff, "view diff")
  map("x", gh_checkout, "checkout PR")
  -- Toggles
  map("s", toggle_scope, "toggle scope")
  map("H", toggle_done, "toggle done")
  -- Help
  map("?", show_help, "help")
end

local function setup_sidebar_keymaps()
  local b = state.sidebar.buf
  local function smap(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = b, nowait = true, silent = true, desc = "DevOps: " .. desc })
  end
  smap("q", hide, "hide (toggle off)")
  smap("<Esc>", hide, "hide (toggle off)")
  smap("Q", close, "close (destroy)")
  smap("<S-Right>", focus_content, "focus list")
  smap("<Right>", focus_content, "focus list")
  smap("l", focus_content, "focus list")
  smap("j", function() sidebar_move(1) end, "next view")
  smap("k", function() sidebar_move(-1) end, "prev view")
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

function M.open(layout)
  layout = layout or config.options.layout or "float"

  -- Toggle: if visible, hide it (keep state); if hidden, restore it.
  if is_open() then
    hide()
    return
  end
  if is_hidden() then
    restore_float_windows()
    setup_keymaps()
    setup_sidebar_keymaps()
    setup_autocmds()
    render_sidebar()
    render_footer()
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
  state.section = 1
  state.content_cursor = nil

  if layout == "tab" then open_tab_windows() else open_float_windows() end
  vim.wo[state.sidebar.win].cursorline = true
  setup_keymaps()
  setup_sidebar_keymaps()
  setup_autocmds()
  render_sidebar()
  render_footer()
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
        load_section()
      end)
    else
      load_section()
    end
  end)
end

return M
