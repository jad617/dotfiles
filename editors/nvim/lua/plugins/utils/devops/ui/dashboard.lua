---------------------------------------------------------------------------
-- DevOps dashboard — sidebar (sections) + content (list).
-- Opens as a float (default) or a tab. See config.layout.
---------------------------------------------------------------------------

local config = require("plugins.utils.devops.config")
local errors = require("plugins.utils.devops.ui.errors")
local client = require("plugins.utils.devops.jira.client")
local api = require("plugins.utils.devops.jira.api")
local branch = require("plugins.utils.devops.jira.branch")
local watch = require("plugins.utils.devops.github.watch")
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
    { id = "gh_actions", label = "Actions" },
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
  person_filter = {}, -- 'F' filter per section (jira_sprint / jira_backlog): { account_id, name } | { unassigned = true, name }
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

-- The sprint/project scope and +Done toggles only feed the "My Issues" query;
-- the sprint board, epics, and backlog build their own scoped JQL and pin
-- include_done themselves. Used to gate both the indicator and the keymap so
-- the chrome never advertises a filter the current section ignores.
local function section_honours_filters(sec_id)
  return (sec_id or current_section_id()) == "jira_issues"
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
    if section_honours_filters() then
      if state.sprint then
        if state.scope_override == "project" then
          parts[#parts + 1] = "project"
        else
          parts[#parts + 1] = "sprint"
        end
      end
      if state.include_done then parts[#parts + 1] = "+Done" end
    end
    if sec.id == "jira_sprint" and state.sprint then
      parts[#parts + 1] = state.sprint.picked and state.sprint.name or "active sprint"
    end
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
    if section_honours_filters() then
      if state.sprint then parts[#parts + 1] = (state.scope_override == "project") and "project" or "sprint" end
      if state.include_done then parts[#parts + 1] = "+Done" end
    end
    if #parts > 0 then
      push("   " .. table.concat(parts, " · "), "DevOpsDim")
    end
    -- Show the user filter where it applies. The team Sprint Board ignores a
    -- specific user, but the 'Unassigned' filter does narrow it.
    local fsec = current_section_id()
    if state.jira_user and (fsec == "jira_issues" or fsec == "jira_backlog" or fsec == "jira_epics"
        or (fsec == "jira_sprint" and state.jira_user.unassigned)) then
      push("   👤 " .. render.truncate(state.jira_user.name or "user", 24), "DevOpsKey")
    end
    local pf = state.person_filter[fsec]
    if pf then
      push("   ⧩ " .. render.truncate(pf.name or "person", 24), "DevOpsKey")
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
    -- Reviews: open review requests, red while some are new since your last look.
    local count_badge
    if sec.id == "gh_reviews" and watch.total() > 0 then
      count_badge = "  " .. (watch.unseen() > 0 and "● " or "") .. tostring(watch.total())
      text = text .. count_badge
    end
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
    if count_badge then
      hls[#hls + 1] = { line = #lines - 1, col_start = #text - #count_badge, col_end = #text,
        hl = watch.unseen() > 0 and "DevOpsErr" or "DevOpsDim" }
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

-- One keymap table per view feeds both the one-line footer (entries marked
-- `true` in their 4th slot, in that order) and the grouped '?' help.
-- Entry: { key, short label, description, footer? }
local function key_context()
  local sec_id = current_section_id()
  if state.in_detail then return state.detail_kind == "jira" and "jira_detail" or "pr_detail" end
  if sec_id == "jira_sprint" or sec_id == "jira_epics" or sec_id == "jira_backlog" then return "jira_board" end
  if sec_id == "jira_bookmarks" or sec_id == "gh_bookmarks" then return "bookmarks" end
  return sec_id
end

local function nav_list(open_desc, short)
  return { "Navigate", {
    { "↵", short or "open", open_desc or "Open the selected item", true },
    { "j/k", "move", "Move the cursor" },
    { "Tab/S-Tab", "section", "Next / previous section" },
    { "H/L  {/}", "tabs", "Previous / next tab (Jira ↔ GitHub)" },
    { "S-←", "sidebar", "Focus the sidebar" },
  } }
end
local function window_list(extra)
  local t = { { "o", "browser", "Open in the browser" } }
  vim.list_extend(t, extra or {})
  vim.list_extend(t, {
    { "R", "refresh", "Refresh" },
    { "q/Esc", "hide", "Hide the dashboard (state is kept)" },
    { "Q", "close", "Close the dashboard" },
  })
  return { "Window", t }
end
local DETAIL_NAV = function(open_desc, short)
  return { "Navigate", {
    { "q/BS", "back", "Back to the list / previous item", true },
    { "⇥/⇤", "tabs", "Next / previous detail tab", true },
    { "↵", short or "open", open_desc, true },
    { "H/L", "tabs", "Previous / next dashboard tab" },
  } }
end
local JIRA_FILTERS = function(people)
  local t = {}
  if people then t[#t + 1] = { "F", "people", "Filter the board by person (only people on it)", true } end
  vim.list_extend(t, {
    { "u", "user", "Show another user's issues" },
    { "v", "sprint", "Pick a sprint (incl. past ones)" },
    { "p", "project", "Switch project" },
    { "b", "board", "Switch board" },
  })
  return t
end
local PR_ACTIONS = {
  { "a", "approve", "Approve" },
  { "C", "changes", "Request changes" },
  { "c", "comment", "Comment" },
  { "d", "diff", "View the diff (x = toggle viewed, S = submit review)", true },
  { "F", "files", "Changed-files tree (↵ opens the diff at that file)" },
  { "m", "merge", "Merge (squash)", true },
  { "D", "ready", "Mark ready for review" },
  { "x", "checkout", "Check out the branch locally" },
  { "J", "jira", "Open the Jira ticket named in the branch / title", true },
}

local function key_groups(ctx)
  if ctx == "jira_detail" then
    return {
      DETAIL_NAV("Follow the link under the cursor (parent, child, PR)", "link"),
      { "Actions", {
        { "c", "comment", "Comment", true },
        { "r", "reply", "Reply to the comment under the cursor" },
        { "e", "edit", "Edit summary / description", true },
        { "a", "assign", "Assign", true },
        { "V", "sprint", "Move to a sprint / the backlog" },
        { "B", "branch", "Create a git branch from this ticket and start it", true },
      } },
      { "Epic", {
        { "P", "parent", "Jump to the parent epic", true },
        { "F", "filter", "Filter the epic's child issues" },
        { "v", "sprint", "Pick a sprint" },
      } },
      window_list(),
    }
  elseif ctx == "pr_detail" then
    local acts = vim.deepcopy(PR_ACTIONS)
    table.insert(acts, 3, { "r", "reply/re-run", "Reply to a comment · on a check: re-run it" })
    table.insert(acts, 5, { "U", "since review", "Diff of the commits since your last review" })
    acts[1][4] = true
    return {
      DETAIL_NAV("Files: open the diff · Checks: open the job log · links", "file/log"),
      { "Actions", acts },
      window_list({ { "gx", "links", "Pick a link from the PR to open" } }),
    }
  elseif ctx == "jira_issues" then
    return {
      nav_list("Open the issue"),
      { "Actions", {
        { "m", "move", "Change status", true },
        { ">/<", "column", "Move to the next / previous board column" },
        { "c", "comment", "Comment", true },
        { "e", "edit", "Edit summary / description" },
        { "a", "assign", "Assign", true },
        { "+", "new", "Create an issue (epic, sprint, summary from the branch)", true },
        { "y", "clone", "Clone the issue" },
        { "V", "sprint", "Move to a sprint / the backlog" },
        { "B", "branch", "Create a git branch from the issue and start it" },
        { "S", "search", "Search Jira", true },
        { "*", "pin", "Pin / unpin" },
      } },
      { "Filters", vim.list_extend(JIRA_FILTERS(false), {
        { "s", "scope", "Toggle scope (sprint / project)" },
        { "h", "done", "Show / hide Done issues" },
      }) },
      window_list({ { "O", "board", "Open the board in the browser" } }),
    }
  elseif ctx == "jira_board" then
    local sec_id = current_section_id()
    return {
      nav_list("Open the issue"),
      { "Actions", {
        { "m", "move", "Change status", true },
        { ">/<", "column", "Move to the next / previous board column", true },
        { "c", "comment", "Comment" },
        { "a", "assign", "Assign", true },
        { "V", "sprint", "Move to a sprint / the backlog" },
        { "B", "branch", "Create a git branch from the issue and start it" },
        { "S", "search", "Search Jira", true },
        { "*", "pin", "Pin / unpin" },
      } },
      { "Filters", JIRA_FILTERS(sec_id == "jira_sprint" or sec_id == "jira_backlog") },
      window_list({ { "O", "board", "Open the board in the browser" } }),
    }
  elseif ctx == "bookmarks" then
    return {
      nav_list(),
      { "Actions", { { "*", "unpin", "Unpin", true } } },
      window_list(),
    }
  elseif ctx == "gh_actions" then
    return {
      nav_list("Pick a job → its log (live view while it runs)", "jobs/log"),
      { "Actions", {
        { "r", "re-run", "Re-run failed jobs / all jobs", true },
        { "o", "browser", "Open the run in the browser", true },
      } },
      { "Log viewer", {
        { "]e/[e", "error", "Next / previous error" },
        { "]s/[s", "step", "Next / previous step" },
        { "gf", "source", "Open file:line from the log in your checkout" },
        { "y/Y", "copy", "Copy the error block / the whole step" },
        { "r", "re-run", "Re-run (failed / this job / all)" },
        { "␣z", "zoom", "Zoom the log float" },
      } },
      window_list(),
    }
  else -- gh_prs / gh_reviews
    local acts = vim.deepcopy(PR_ACTIONS)
    if ctx == "gh_reviews" then
      acts[1][4], acts[2][4] = true, true
      table.insert(acts, 5, { "U", "since review", "Diff of the commits since your last review", true })
      acts[#acts + 1] = { "s", "sort", "Sort newest / oldest first" }
    else
      acts[#acts + 1] = { "+", "new", "Create a PR", true }
    end
    vim.list_extend(acts, { { "S", "search", "Search PRs in your org (C-t: global)" }, { "*", "pin", "Pin / unpin" } })
    return { nav_list("Open the PR"), { "Actions", acts }, window_list(), { "Badges", {
      { "●", "ready", "Ready to merge (approved, CI green, no conflicts)" },
      { "✔", "approved", "Approved" },
      { "○", "review", "Waiting for review" },
      { "±", "changes", "Changes requested" },
      { "✗ ci", "failing", "CI failing  (ci… = CI running)" },
      { "⚠", "conflict", "Merge conflict" },
    } } }
  end
end

-- Footer entries for a context: the marked keys, in table order.
local function footer_keys(ctx)
  local out = {}
  for _, g in ipairs(key_groups(ctx)) do
    for _, e in ipairs(g[2]) do if e[4] then out[#out + 1] = e end end
  end
  return out
end

local function render_footer()
  if not state.footer.buf or not vim.api.nvim_buf_is_valid(state.footer.buf) then return end
  local keys = footer_keys(key_context())
  local avail = (state.footer.win and vim.api.nvim_win_is_valid(state.footer.win))
    and vim.api.nvim_win_get_width(state.footer.win) or 200
  local right = "? all keys "
  local gap = "   "
  local function build(n)
    local text, hls = " ", {}
    for i = 1, n do
      local e = keys[i]
      if i > 1 then text = text .. gap end
      hls[#hls + 1] = { #text, #text + #e[1], "DevOpsKey" }
      text = text .. e[1] .. " "
      hls[#hls + 1] = { #text, #text + #e[2], "DevOpsAction" }
      text = text .. e[2]
    end
    return text, hls
  end
  -- Narrow window: drop keys from the end; '? all keys' always stays.
  local n = #keys
  local text, hls = build(n)
  while n > 0 and vim.fn.strdisplaywidth(text) + #gap + vim.fn.strdisplaywidth(right) > avail do
    n = n - 1
    text, hls = build(n)
  end
  local pad = math.max(1, avail - vim.fn.strdisplaywidth(text) - vim.fn.strdisplaywidth(right))
  local line = text .. string.rep(" ", pad) .. right
  local rstart = #text + pad
  hls[#hls + 1] = { rstart, rstart + 1, "DevOpsKey" }
  hls[#hls + 1] = { rstart + 2, #line, "DevOpsDim" }

  vim.bo[state.footer.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.footer.buf, 0, -1, false, { line })
  vim.bo[state.footer.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.footer.buf, footer_ns, 0, -1)
  for _, h in ipairs(hls) do
    pcall(vim.api.nvim_buf_set_extmark, state.footer.buf, footer_ns, 0, h[1], { end_col = h[2], hl_group = h[3] })
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

-- opts.show_assignee: add an assignee column (used by the team Sprint Board).
local function render_jira(issues, assignee_name, columns, title_override, opts)
  opts = opts or {}
  stop_spinner()
  local scope = state.sprint and (state.sprint.picked and state.sprint.name or "Active sprints")
    or (state.project and state.project.key or "no project")
  local subtitle = scope .. "  ·  " .. assignee_name .. "  ·  " .. #issues .. " issue" .. (#issues == 1 and "" or "s")
  local lines, hls = header(title_override or "Jira  ·  My Issues", subtitle)
  -- Say why the list is flat/unscoped instead of silently falling back.
  local warn
  if title_override then -- other sections have their own scoping/messages
  elseif state.project and not state.board then
    warn = "⚠ No board selected: press b to pick one (status columns + active-sprint filter)"
  elseif state.board and not columns then
    warn = "⚠ Couldn't load columns for board " .. (state.board.name or state.board.id) .. ": R to retry, b to change"
  end
  if warn then
    table.insert(lines, 3, "  " .. warn)
    hls[#hls + 1] = { line = 2, col_start = 0, col_end = #lines[3], hl = "DevOpsWarn" }
  end
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
      local sname = f.status and f.status.name or ""
      status_str = render.fit(render.status_icon(sname, cat) .. " " .. sname, 15)
      reserve = reserve + 17
    end
    local who_str
    if opts.show_assignee then
      -- JSON null decodes to vim.NIL, so check the type rather than truthiness.
      local a = type(f.assignee) == "table" and f.assignee.displayName or nil
      who_str = render.fit(a or "Unassigned", 18)
      reserve = reserve + 20
    end
    local summary = render.truncate(f.summary or "", math.max(10, w - reserve))

    local text = prefix .. keypad .. "  "
    if show_status then text = text .. status_str .. "  " end
    if who_str then text = text .. who_str .. "  " end
    text = text .. summary
    lines[#lines + 1] = text
    local lidx = #lines - 1
    local key_start = #prefix
    hls[#hls + 1] = { line = lidx, col_start = key_start, col_end = key_start + #key, hl = "DevOpsId" }
    hls[#hls + 1] = { line = lidx, col_start = #indent, col_end = #indent + #icon, hl = render.issue_icon_hl(f.issuetype and f.issuetype.name) }
    local col = key_start + #keypad + 2
    if show_status then
      hls[#hls + 1] = { line = lidx, col_start = col, col_end = col + #status_str, hl = render.status_hl(cat) }
      col = col + #status_str + 2
    end
    if who_str then
      local unassigned = type(f.assignee) ~= "table"
      hls[#hls + 1] = { line = lidx, col_start = col, col_end = col + #who_str, hl = unassigned and "DevOpsDim" or "DevOpsLabel" }
    end
    rows[#lines] = {
      kind = "jira",
      key = issue.key,
      id = issue.id,
      status = f.status and f.status.name or nil,
      status_id = f.status and f.status.id and tostring(f.status.id) or nil,
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
    if #issues == 0 then
      lines[#lines + 1] = state.jira_user
        and ("  (no issues for " .. (state.jira_user.name or "user") .. ")")
        or "  (no issues)"
    end
    for _, issue in ipairs(issues) do add_issue(issue, "  ", true) end
  end

  set_buf_lines(state.content.buf, lines)
  apply_highlights(state.content.buf, hls)
  state.rows = rows
  park_cursor_on_first_item()
end

-- Does `issue` match a person filter ('F')?
local function person_match(issue, filter)
  local a = issue.fields and issue.fields.assignee
  if type(a) ~= "table" then return filter.unassigned == true end
  return not filter.unassigned and a.accountId == filter.account_id
end

-- Apply the section's 'F' person filter locally (no refetch). Returns the shown
-- issues and the subtitle label to use (nil when unfiltered).
local function apply_person_filter(sec_id, issues)
  local pf = state.person_filter[sec_id]
  if not pf then return issues, nil end
  local shown = {}
  for _, it in ipairs(issues) do
    if person_match(it, pf) then shown[#shown + 1] = it end
  end
  return shown, "👤 " .. pf.name .. "  (F to change)"
end

-- Sprint Board: always show assignees (the board data is team-wide).
local function render_sprint(issues)
  local picked = state.sprint and state.sprint.picked
  local title = (picked and state.sprint.name) and ("Jira  ·  " .. state.sprint.name) or "Jira  ·  Sprint Board"
  local who = (state.jira_user and state.jira_user.unassigned) and "Unassigned" or "all"
  local shown, label = apply_person_filter("jira_sprint", issues)
  render_jira(shown, label or who, state.columns, title, { show_assignee = true })
end

-- Backlog: likewise shows assignees and honours its own 'F' filter.
local function render_backlog_list(issues)
  local who = state.jira_user and state.jira_user.name or (state.project and state.project.key or "project")
  local shown, label = apply_person_filter("jira_backlog", issues)
  render_jira(shown, label or who, nil, "Jira  ·  Backlog", { show_assignee = true })
end

-- Render a Jira section straight from cached issues (no network call). Shared by
-- the cache path in load_section and the optimistic update after a transition.
local function render_jira_from_cache(sec_id, cached)
  if sec_id == "jira_issues" then
    local name = state.jira_user and state.jira_user.name or (client.display_name() or "me")
    render_jira(cached, name, state.columns)
  elseif sec_id == "jira_sprint" then
    render_sprint(cached)
  elseif sec_id == "jira_epics" then
    render_jira(cached, state.project and state.project.key or "project", nil, "Jira  ·  Epics")
  elseif sec_id == "jira_backlog" then
    render_backlog_list(cached)
  end
end

local function github_check_status(rollup)
  if not rollup then return "", nil end
  if type(rollup) == "table" and vim.islist(rollup) then
    -- `gh pr list --json` gives the contexts (latest run per check); fold them into one state.
    rollup = detail._check_contexts(rollup)
    if #rollup == 0 then return "", nil end
    local pending = false
    for _, c in ipairs(rollup) do
      local s = c.conclusion or c.state or ""
      if s == "FAILURE" or s == "ERROR" or s == "TIMED_OUT" or s == "CANCELLED" or s == "ACTION_REQUIRED" then
        return "✗", "DevOpsErr"
      end
      if (c.status and c.status ~= "COMPLETED") or s == "PENDING" or s == "" then pending = true end
    end
    if pending then return "⏳", "DevOpsWarn" end
    return "✓", "DevOpsOk"
  end
  local state_val = type(rollup) == "table" and rollup.state or rollup
  if state_val == "SUCCESS" then return "✓", "DevOpsOk" end
  if state_val == "FAILURE" or state_val == "ERROR" then return "✗", "DevOpsErr" end
  if state_val == "PENDING" or state_val == "IN_PROGRESS" or state_val == "EXPECTED" then return "⏳", "DevOpsWarn" end
  return "", nil
end

local time_ago = render.time_ago

-- One badge summing up whether a PR can merge: conflicts / changes requested
-- first, then approved (+ green checks → ready), then awaiting review.
local function pr_readiness(pr)
  if pr.isDraft then return nil end
  local checks = select(1, github_check_status(pr.statusCheckRollup))
  if pr.mergeable == "CONFLICTING" then return "⚠ conflict", "DevOpsErr" end
  if pr.reviewDecision == "CHANGES_REQUESTED" then return "± changes", "DevOpsErr" end
  if pr.reviewDecision == "APPROVED" then
    if checks == "✗" then return "✔ approved · ✗ ci", "DevOpsWarn" end
    if checks == "⏳" then return "✔ approved · ci…", "DevOpsWarn" end
    return "● ready", "DevOpsOk"
  end
  if pr.reviewDecision == "REVIEW_REQUIRED" then return "○ review", "DevOpsDim" end
  return nil
end

local function render_github(prs, title, show_meta)
  stop_spinner()
  -- Sort reviews by user preference (shallow copy — we only reorder references).
  if show_meta then
    prs = vim.list_extend({}, prs or {})
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
    local check_cell = render.pad(check_icon, 2) -- fixed 2 display cols (or "  " when none)
    local repo = (pr.repository and pr.repository.name) or ""
    local tag = (not show_meta) and repo or ""
    local badge, badge_hl = pr_readiness(pr)
    local badge_w = badge and (vim.fn.strdisplaywidth(badge) + 2) or 0
    local summary = render.truncate(pr.title or "", math.max(10, w - 15 - vim.fn.strdisplaywidth(tag) - badge_w))

    local prefix = "  " .. icon .. "  "
    local text = prefix .. numpad .. check_cell .. " " .. summary
    local badge_col
    if badge then badge_col = #text + 2; text = text .. "  " .. badge end
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
    if badge then hls[#hls + 1] = { line = lidx, col_start = badge_col, col_end = badge_col + #badge, hl = badge_hl } end
    -- Jira keys in the title (J opens them).
    local title_start = #prefix + #numpad + #check_cell + 1
    for ks, ke in summary:gmatch("()%f[%w][A-Z][A-Z0-9_]+%-%d+%f[^%w]()") do
      hls[#hls + 1] = { line = lidx, col_start = title_start + ks - 1, col_end = title_start + ke - 1, hl = "DevOpsKey" }
    end
    rows[#lines] = { kind = "pr", pr = pr }

    if show_meta then
      -- Indent the meta block to the *display* column where the title text starts
      -- (icon/check are multi-byte glyphs but 1 column wide, so byte width over-
      -- shoots and the lines wouldn't align under the title).
      local indent = string.rep(" ", vim.fn.strdisplaywidth(prefix .. numpad .. check_cell .. " "))
      local full_repo = (pr.repository and pr.repository.nameWithOwner) or repo
      local author = pr.author and pr.author.login or "?"
      local reviewers = pr.reviewReason or "?"

      -- Align values: pad labels to same width
      local lbl_w = #"Approved by:  "
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

      -- Approved by line
      if pr.approvedBy and #pr.approvedBy > 0 then
        local lbl_ap = pad_lbl("Approved by:")
        local approvers = table.concat(pr.approvedBy, ", ")
        lines[#lines + 1] = indent .. lbl_ap .. approvers
        rows[#lines] = { kind = "pr", pr = pr }
        local apl = #lines - 1
        hls[#hls + 1] = { line = apl, col_start = #indent, col_end = #indent + #lbl_ap, hl = "DevOpsDim" }
        hls[#hls + 1] = { line = apl, col_start = #indent + #lbl_ap, col_end = #indent + #lbl_ap + #approvers, hl = "DevOpsOk" }
      end

      -- Pushed since my verdict → re-review
      if pr.updatedSinceReview then
        local lbl_up = pad_lbl("Updated:")
        local txt = "↻ New commits since your "
          .. (pr.updatedSinceReview == "APPROVED" and "approval" or "change request")
        lines[#lines + 1] = indent .. lbl_up .. txt
        rows[#lines] = { kind = "pr", pr = pr }
        local ul = #lines - 1
        hls[#hls + 1] = { line = ul, col_start = #indent, col_end = #indent + #lbl_up, hl = "DevOpsDim" }
        hls[#hls + 1] = { line = ul, col_start = #indent + #lbl_up, col_end = #indent + #lbl_up + #txt, hl = "DevOpsWarn" }
      end

      -- Comments line (awaiting reply / new reply)
      if pr.commentStatus == "awaiting_reply" then
        local lbl_cm = pad_lbl("Comments:")
        local txt = "󰍡 Awaiting reply"
        lines[#lines + 1] = indent .. lbl_cm .. txt
        rows[#lines] = { kind = "pr", pr = pr }
        local cl = #lines - 1
        hls[#hls + 1] = { line = cl, col_start = #indent, col_end = #indent + #lbl_cm, hl = "DevOpsDim" }
        hls[#hls + 1] = { line = cl, col_start = #indent + #lbl_cm, col_end = #indent + #lbl_cm + #txt, hl = "DevOpsWarn" }
      elseif pr.commentStatus == "replied" then
        local lbl_cm = pad_lbl("Comments:")
        local txt = pr.commentInfo and require("plugins.utils.devops.github.threads").reply_label(pr.commentInfo)
          or "↩ Reply to your comment"
        lines[#lines + 1] = indent .. lbl_cm .. txt
        rows[#lines] = { kind = "pr", pr = pr }
        local cl = #lines - 1
        hls[#hls + 1] = { line = cl, col_start = #indent, col_end = #indent + #lbl_cm, hl = "DevOpsDim" }
        hls[#hls + 1] = { line = cl, col_start = #indent + #lbl_cm, col_end = #indent + #lbl_cm + #txt, hl = "DevOpsOk" }
      end

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

-- Workflow run state → icon, highlight.
local function run_icon(run)
  local st, c = run.status or "", run.conclusion or ""
  if st ~= "completed" then
    if st == "in_progress" then return "⟳", "DevOpsWarn" end
    return "⏳", "DevOpsWarn"
  end
  if c == "success" then return "✓", "DevOpsOk" end
  if c == "failure" or c == "timed_out" or c == "startup_failure" then return "✗", "DevOpsErr" end
  if c == "cancelled" then return "⊘", "DevOpsDim" end
  if c == "skipped" or c == "neutral" then return "↷", "DevOpsDim" end
  if c == "action_required" then return "!", "DevOpsWarn" end
  return "·", "DevOpsDim"
end

local function runs_active(runs)
  for _, r in ipairs(runs or {}) do if r.status ~= "completed" then return true end end
  return false
end

-- GitHub › Actions: the cwd repo's recent workflow runs.
local function render_actions(data)
  stop_spinner()
  local runs = data.runs or {}
  local active = 0
  for _, r in ipairs(runs) do if r.status ~= "completed" then active = active + 1 end end
  local lines, hls = header(nil, data.repo .. "  ·  " .. #runs .. " run" .. (#runs == 1 and "" or "s")
    .. (active > 0 and ("  ·  " .. active .. " running (auto-refresh)") or ""))
  local rows = {}
  local w = content_width()
  local wf_w = 0
  for _, r in ipairs(runs) do wf_w = math.max(wf_w, vim.fn.strdisplaywidth(r.workflowName or "")) end
  wf_w = math.min(wf_w, 22)
  for _, r in ipairs(runs) do
    local icon, ihl = run_icon(r)
    local wf = render.pad(render.truncate(r.workflowName or "?", wf_w), wf_w)
    local age = time_ago(r.createdAt)
    local branch = r.headBranch or ""
    local tail = branch .. "  " .. age
    local prefix = "  " .. icon .. "  "
    local avail = math.max(10, w - vim.fn.strdisplaywidth(prefix) - wf_w - 2 - vim.fn.strdisplaywidth(tail) - 3)
    local title = render.truncate(r.displayTitle or "", avail)
    local mid = prefix .. wf .. "  " .. title
    local gap = math.max(2, w - vim.fn.strdisplaywidth(mid) - vim.fn.strdisplaywidth(tail) - 1)
    local text = mid .. string.rep(" ", gap) .. tail
    lines[#lines + 1] = text
    local li = #lines - 1
    hls[#hls + 1] = { line = li, col_start = 2, col_end = 2 + #icon, hl = ihl }
    hls[#hls + 1] = { line = li, col_start = #prefix, col_end = #prefix + #wf, hl = "DevOpsColumn" }
    local tail_start = #text - #tail
    hls[#hls + 1] = { line = li, col_start = tail_start, col_end = tail_start + #branch, hl = "DevOpsLabel" }
    hls[#hls + 1] = { line = li, col_start = tail_start + #branch, col_end = #text, hl = "DevOpsDim" }
    rows[#lines] = { kind = "run", run = r, repo = data.repo }
  end
  if #runs == 0 then lines[#lines + 1] = "  (no workflow runs)" end
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
      hls[#hls + 1] = { line = lidx, col_start = 2, col_end = 2 + #icon, hl = render.issue_icon_hl(bm.type_name) }
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

-- Warm the persisted cache off the critical path (call from idle/init) so the first
-- open doesn't pay the file read.
function M.preload_cache() pcall(ensure_cache_loaded) end

local function cache_get(sec_id)
  ensure_cache_loaded()
  local entry = cache[sec_id]
  if entry and (os.time() - entry.ts) < CACHE_TTL then return entry.data end
  return nil
end

-- Cached data ignoring the TTL — used when restoring a list we just left (e.g.
-- backing out of a story), so we don't re-fetch the list we were just viewing.
local function cache_get_raw(sec_id)
  ensure_cache_loaded()
  local entry = cache[sec_id]
  return entry and entry.data or nil
end

local cache_save_timer = vim.uv.new_timer()
local function cache_set(sec_id, data)
  cache[sec_id] = { data = data, ts = os.time() }
  -- Persist off the UI thread, coalescing rapid sets (e.g. prefetch) into one write.
  cache_save_timer:stop()
  cache_save_timer:start(500, 0, vim.schedule_wrap(function()
    store.save_section_cache(cache)
  end))
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

-- A list fetch is stale if the user moved on: another section/load, or a detail
-- view is open or loading (its result would otherwise overwrite the ticket).
local function list_stale(sec_id, gen)
  return not is_open() or state.in_detail or state.detail_loading
    or current_section_id() ~= sec_id or state.load_gen ~= gen
end

local warm_cwd_repo -- forward decl (defined with the GitHub helpers below)

-- Fetch the cwd repo's runs. `quiet` (auto-refresh) repaints in place, keeping the cursor.
local actions_timer
local schedule_actions_refresh
local function fetch_actions(sec_id, gen, quiet)
  warm_cwd_repo(nil, function(repo)
    if list_stale(sec_id, gen) then return end
    if not repo then
      return set_message("⚠ Not in a GitHub repo — Actions lists the runs of the current directory's repo")
    end
    gh.run_list(repo, function(ok, runs, err)
      if list_stale(sec_id, gen) then return end
      if not ok then
        if quiet then return end
        return set_message("⚠ " .. (err or "gh run list failed"))
      end
      local data = { repo = repo, runs = runs or {} }
      cache_set(sec_id, data)
      local cur = quiet and vim.api.nvim_win_get_cursor(state.content.win)
      render_actions(data)
      if cur then pcall(vim.api.nvim_win_set_cursor, state.content.win, cur) end
      if runs_active(data.runs) then schedule_actions_refresh() end
    end)
  end)
end

-- While runs are in progress, refresh the Actions list every 10s (only while it's shown).
schedule_actions_refresh = function()
  actions_timer = actions_timer or vim.uv.new_timer()
  actions_timer:stop()
  actions_timer:start(10000, 0, vim.schedule_wrap(function()
    if not is_open() or state.in_detail or state.detail_loading or current_section_id() ~= "gh_actions" then return end
    state.load_gen = (state.load_gen or 0) + 1
    fetch_actions("gh_actions", state.load_gen, true)
  end))
end

local function load_section(force, allow_stale)
  local sec_id = current_section_id()
  -- Generation token: only the latest load's callback applies, so rapid section
  -- switches (or re-loads of the same section) don't double-render or race.
  state.load_gen = (state.load_gen or 0) + 1
  local gen = state.load_gen
  -- A ticket is shown (or loading): don't paint the list over it. Filter changes
  -- made from a ticket invalidate the cache, so Back refetches the list.
  if state.in_detail or state.detail_loading then return end

  if sec_id == "gh_reviews" and watch.unseen() > 0 then watch.mark_seen() end

  -- Bookmark sections are local — no API call needed
  if sec_id == "jira_bookmarks" or sec_id == "gh_bookmarks" then
    state.bookmarks = store.load_bookmarks()
    render_bookmarks(current_tab_id())
    return
  end

  -- Serve from cache unless forced (manual refresh). allow_stale ignores the TTL
  -- (restoring a list we just left shouldn't re-query it).
  if not force then
    local cached = (allow_stale and cache_get_raw(sec_id)) or cache_get(sec_id)
    if cached then
      if sec_id == "gh_prs" or sec_id == "gh_reviews" then
        local title = sec_id == "gh_prs" and "GitHub · My PRs" or "GitHub · Reviews"
        render_github(cached, title, sec_id == "gh_reviews")
      elseif sec_id == "gh_actions" then
        local repo = state._cwd_repo and state._cwd_repo[vim.fn.getcwd()]
        if cached.repo and cached.repo == repo then
          render_actions(cached)
          if runs_active(cached.runs) then schedule_actions_refresh() end
          return
        end
        return load_section(true)
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
    local u = state.jira_user
    local unassigned = (u and u.unassigned) or false
    local account = (not unassigned) and ((u and u.account_id) or client.account_id()) or nil
    local name = unassigned and "Unassigned" or (u and u.name) or (client.display_name() or "me")
    local function on_issues(ok, issues, err)
      if list_stale(sec_id, gen) then return end
      if not ok then return set_message("⚠ " .. (err or "Jira search failed")) end
      cache_set(sec_id, issues)
      render_jira(issues, name, state.columns)
    end
    local use_sprints = state.sprint ~= nil and state.scope_override ~= "project"
    api.search({
      account_id = account,
      unassigned = unassigned or nil,
      -- My Issues spans projects by default; only scope to the project on 's' toggle.
      project_key = (state.scope_override == "project") and state.project and state.project.key or nil,
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
    if not state.board then
      set_message("⚠ Select a Scrum board with 'b' to see the sprint board")
      return
    end
    -- Default: this project's issues in any active sprint (follows the project, not
    -- whatever team owns the board's sprint). A specific sprint is used only when
    -- explicitly picked with 'v'.
    local picked = state.sprint and state.sprint.picked
    -- Team-wide by default; only the 'Unassigned' user-filter narrows it (so you can
    -- spot sprint tickets nobody's picked up). A specific 'u' user still doesn't apply.
    local unassigned = (state.jira_user and state.jira_user.unassigned) or false
    api.search({
      account_id = nil,
      unassigned = unassigned or nil,
      project_key = state.project and state.project.key,
      sprint_id = picked and state.sprint.id or nil,
      open_sprints = not picked,
      scope_project = true, -- sprint board follows the selected project
      include_done = true,
    }, function(ok, issues, err)
      if list_stale(sec_id, gen) then return end
      if not ok then return set_message("⚠ " .. (err or "sprint fetch failed")) end
      cache_set(sec_id, issues)
      render_sprint(issues)
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
    local efilter = state.jira_user
      and (state.jira_user.unassigned and { unassigned = true }
        or (state.jira_user.account_id and { account_id = state.jira_user.account_id }))
      or nil
    api.epics(state.project.key, efilter, function(ok, issues, err)
      if list_stale(sec_id, gen) then return end
      if not ok then return set_message("⚠ " .. (err or "epics fetch failed")) end
      cache_set(sec_id, issues)
      render_jira(issues, state.jira_user and state.jira_user.name or state.project.key, nil, "Jira  ·  Epics")
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
    local acct = state.jira_user and state.jira_user.account_id or nil
    local unassigned = (state.jira_user and state.jira_user.unassigned) or false
    local function render_backlog(issues)
      -- board backlog isn't assignee-filtered server-side; do it here.
      if unassigned then
        local filtered = {}
        for _, it in ipairs(issues) do
          if not (it.fields and it.fields.assignee) then filtered[#filtered + 1] = it end
        end
        issues = filtered
      elseif acct then
        local filtered = {}
        for _, it in ipairs(issues) do
          local a = it.fields and it.fields.assignee
          if a and a.accountId == acct then filtered[#filtered + 1] = it end
        end
        issues = filtered
      end
      cache_set(sec_id, issues)
      render_backlog_list(issues)
    end
    local on_bl = function(ok, issues, err)
      if list_stale(sec_id, gen) then return end
      if not ok then return set_message("⚠ " .. (err or "backlog fetch failed")) end
      render_backlog(issues)
    end
    if state.board then
      api.board_backlog(state.board.id, on_bl) -- matches Jira's full Backlog view
    else
      api.backlog(state.project.key, acct, on_bl)
    end
  elseif sec_id == "gh_actions" then
    if not gh.available() then return set_message("⚠ gh CLI not found") end
    fetch_actions(sec_id, gen)
  else -- gh_prs / gh_reviews
    if not gh.available() then return set_message("⚠ gh CLI not found") end
    gh.fetch_current_user() -- ensure login is cached for status detection
    local fn = sec_id == "gh_prs" and gh.my_prs or gh.my_reviews
    local title = sec_id == "gh_prs" and "GitHub · My PRs" or "GitHub · Reviews"
    local show_meta = sec_id == "gh_reviews"
    fn(function(ok, prs, err)
      if list_stale(sec_id, gen) then return end
      if not ok then return set_message("⚠ " .. (err or "gh failed")) end
      cache_set(sec_id, prs)
      render_github(prs, title, show_meta)
    end)
  end
end

-- Starts the background watch (review requests + notification count) and
-- polls now; the sidebar badges repaint whenever the counts change.
local function refresh_notifications()
  if not gh.available() then return end
  watch.start(function()
    state.gh_notif_count = watch.state.notif or 0
    if not is_open() then return end
    if current_section_id() == "gh_reviews" and not state.in_detail then
      for _, r in ipairs(watch.state.requests or {}) do watch.state.seen[r.id] = true end
    end
    render_sidebar()
  end)
end

-- Resolve cwd → "owner/repo" asynchronously and cache it, so the PR-search
-- local-scope label never blocks the UI thread (was a synchronous git call).
-- "owner/repo" from a git remote URL (ssh or https), or nil.
local function remote_owner_repo(remote)
  -- Strip a trailing ".git" first, then take the last two path segments.
  -- The character class must include "_" — underscores are legal in both
  -- owner and repo names.
  remote = (remote or ""):gsub("%s+", ""):gsub("%.git$", "")
  return remote:match("[:/]([%w%._%-]+/[%w%._%-]+)$")
end

-- origin's URL straight from .git/config (no git binary — it may be unusable,
-- e.g. macOS's /usr/bin/git before the Xcode licence is accepted). Handles
-- worktrees (.git file → gitdir, commondir).
local function origin_from_config(cwd)
  local root = vim.fs.root(cwd, ".git")
  if not root then return nil end
  local dotgit = root .. "/.git"
  local gitdir = dotgit
  if vim.fn.isdirectory(dotgit) == 0 then
    local f = io.open(dotgit)
    if not f then return nil end
    local line = f:read("*l") or ""
    f:close()
    gitdir = line:match("^gitdir:%s*(.-)%s*$")
    if not gitdir then return nil end
    if gitdir:sub(1, 1) ~= "/" then gitdir = root .. "/" .. gitdir end
    local cf = io.open(gitdir .. "/commondir")
    if cf then
      local common = vim.trim(cf:read("*a") or "")
      cf:close()
      gitdir = common:sub(1, 1) == "/" and common or (gitdir .. "/" .. common)
    end
  end
  local f = io.open(gitdir .. "/config")
  if not f then return nil end
  local in_origin, url = false, nil
  for line in f:lines() do
    local sec = line:match("^%s*%[(.-)%]")
    if sec then in_origin = sec:match('^remote%s+"origin"$') ~= nil
    elseif in_origin then url = url or line:match("^%s*url%s*=%s*(.-)%s*$") end
  end
  f:close()
  return url
end
M._remote_owner_repo = remote_owner_repo
M._origin_from_config = origin_from_config

warm_cwd_repo = function(cwd, cb)
  cwd = cwd or vim.fn.getcwd()
  state._cwd_repo = state._cwd_repo or {}
  if state._cwd_repo[cwd] ~= nil then
    if cb then cb(state._cwd_repo[cwd] or nil) end
    return
  end
  local direct = remote_owner_repo(origin_from_config(cwd))
  if direct then
    state._cwd_repo[cwd] = direct
    if cb then cb(direct) end
    return
  end
  vim.system({ "git", "-C", cwd, "remote", "get-url", "origin" }, { text = true }, function(res)
    vim.schedule(function()
      local owner_repo = remote_owner_repo(res.code == 0 and res.stdout or "")
      state._cwd_repo[cwd] = owner_repo or false
      if cb then cb(owner_repo) end
    end)
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
local move_to_sprint -- forward decl; defined below, also mapped to 'V' in Jira details
local setup_keymaps -- forward decl; defined below, re-run when leaving a detail
                    -- (nav_render_detail deletes the list action maps, e.g. 'y')
local function nav_push()
  local cursor = state.content.win and vim.api.nvim_win_is_valid(state.content.win)
    and vim.api.nvim_win_get_cursor(state.content.win) or { 1, 0 }
  state.nav_stack[#state.nav_stack + 1] = {
    cursor = cursor,
    rows = state.rows,
    in_detail = state.in_detail,
    detail_kind = state.detail_kind,
    reopen = state.in_detail and state.detail_reopen or nil,
  }
end

-- Keys a detail view maps on the content buffer (cleared when switching views).
local DETAIL_ACTION_KEYS = { "c", "e", "a", "r", "o", "R", "C", "d", "D", "m", "x", "+", "y", "V", "t", "U", "P", "F" }
local function clear_action_keys()
  for _, k in ipairs(DETAIL_ACTION_KEYS) do
    pcall(vim.keymap.del, "n", k, { buffer = state.content.buf })
  end
end

local function nav_render_detail(b, make_keys, preserve_cursor)
  if not is_open() then return end
  state.in_detail = true
  state.rows = {}
  detail.write_to_buf(state.content.buf, b)
  clear_action_keys()
  if make_keys then make_keys(state.content.buf) end
  if state.detail_kind == "jira" and move_to_sprint then
    vim.keymap.set("n", "V", move_to_sprint,
      { buffer = state.content.buf, nowait = true, silent = true, desc = "DevOps: move issue to sprint" })
    -- Refetch everything (incl. an epic's child issues), keeping the cursor.
    vim.keymap.set("n", "R", function()
      if not state.detail_key then return end
      detail.invalidate_cache(state.detail_key)
      if state.detail_reopen then state.detail_reopen(vim.api.nvim_win_get_cursor(state.content.win)) end
    end, { buffer = state.content.buf, nowait = true, silent = true, desc = "DevOps: refresh issue" })
  end
  if not preserve_cursor then
    pcall(vim.api.nvim_win_set_cursor, state.content.win, { 1, 0 })
  end
  render_footer()
end

-- Navigating away from a ticket: drop its in-flight load so it can't render later.
local function cancel_detail_load()
  state.detail_gen = (state.detail_gen or 0) + 1
  state.detail_loading = false
end

local function nav_pop()
  if #state.nav_stack == 0 then return false end
  local entry = table.remove(state.nav_stack)
  cancel_detail_load()
  state.in_detail = entry.in_detail
  state.detail_kind = entry.detail_kind
  state.rows = entry.rows
  if not entry.in_detail then
    -- Restore the list view from cache (no re-fetch of the list we just left).
    -- Re-apply the list keymaps: opening a detail deleted the list action maps
    -- (e.g. 'y' clone) and they're not otherwise restored on the way back.
    clear_action_keys() -- drop detail-only maps (e.g. 'r' reply)
    if setup_keymaps then setup_keymaps() end
    load_section(false, true)
    vim.schedule(function()
      if state.content.win and vim.api.nvim_win_is_valid(state.content.win) then
        pcall(vim.api.nvim_win_set_cursor, state.content.win, entry.cursor)
      end
    end)
  elseif entry.reopen then
    -- Back from a linked item to the detail we came from.
    state.detail_reopen = entry.reopen
    entry.reopen(entry.cursor)
  end
  render_footer()
  return true
end

local function nav_back()
  if not nav_pop() then return end
end

-- Render the detail of a Jira key or PR in the content pane. `cursor` (optional)
-- restores a position once rendered (used when navigating back).
local follow_jira_link -- forward decl (needs show_detail)
local function show_detail(kind, target, cursor)
  -- Only the newest detail request may render (e.g. pressing P before the ticket
  -- finished loading), and any in-flight list fetch is dropped.
  state.detail_gen = (state.detail_gen or 0) + 1
  state.load_gen = (state.load_gen or 0) + 1
  state.detail_loading = true
  local dgen = state.detail_gen
  local function ready(b, make_keys)
    if state.detail_gen ~= dgen then return end
    state.detail_loading = false
    nav_render_detail(b, make_keys)
    if cursor then pcall(vim.api.nvim_win_set_cursor, state.content.win, cursor) end
  end
  local function update(b, make_keys)
    if state.detail_gen ~= dgen then return end
    if state.in_detail then nav_render_detail(b, make_keys, true) end
  end
  state.detail_kind = kind
  state.detail_key = kind == "jira" and target or nil
  state.detail_pr = kind == "pr" and target or nil
  state.detail_reopen = function(c) show_detail(kind, target, c) end
  if kind == "jira" then
    detail.load_issue(target, {
      content_win = state.content.win, on_ready = ready, on_update = update,
      on_parent = function(link) follow_jira_link(link) end,
      on_rerender = function()
        if state.detail_gen == dgen and state.detail_reopen then
          state.detail_reopen(vim.api.nvim_win_get_cursor(state.content.win))
        end
      end,
      on_error = function()
        if state.detail_gen == dgen then state.detail_loading = false end
      end,
    })
  else
    detail.load_pr(target, { on_ready = ready, on_update = update })
  end
end

-- Open a parent epic inside the Epics section, the way Jira's web UI shows it
-- (description + child issues). The nav stack becomes: Epics list → the issue we
-- came from → the epic, so Back walks out the way you came in.
local function jump_to_epic(epic_key)
  local ti = tab_index_by_id("jira")
  local si
  for i, sec in ipairs(TABS[ti].sections) do
    if sec.id == "jira_epics" then si = i end
  end
  if state.tab == ti and state.section == si then
    nav_push()
    return show_detail("jira", epic_key)
  end
  -- Remember the current detail (if any) so Back returns to it.
  local from = state.in_detail and {
    cursor = vim.api.nvim_win_get_cursor(state.content.win),
    rows = {}, in_detail = true, detail_kind = state.detail_kind, reopen = state.detail_reopen,
  } or nil
  state.load_gen = (state.load_gen or 0) + 1 -- drop any in-flight list render
  state.tab, state.section = ti, si
  state.content_cursor = nil
  state.nav_stack = { { cursor = { 1, 0 }, rows = {}, in_detail = false } }
  if from then state.nav_stack[2] = from end
  render_sidebar()
  update_winbar()
  state.sidebar_line = sidebar_line_for_section(si)
  if state.sidebar.win and vim.api.nvim_win_is_valid(state.sidebar.win) then
    pcall(vim.api.nvim_win_set_cursor, state.sidebar.win, { state.sidebar_line, 0 })
  end
  show_detail("jira", epic_key)
end

follow_jira_link = function(link)
  if link.epic then return jump_to_epic(link.key) end
  nav_push()
  show_detail("jira", link.key)
end

-- A run's jobs → pick one (the failed ones first) → its log / live view.
local function job_ctx(job)
  return { name = job.name, detailsUrl = job.url, status = (job.status or ""):upper(),
    conclusion = (job.conclusion or ""):upper() }
end

local function open_run(item)
  local jl = require("plugins.utils.devops.ui.job_log")
  vim.notify("DevOps: loading jobs of run #" .. (item.run.number or item.run.databaseId) .. "…", vim.log.levels.INFO)
  gh.run_jobs(item.repo, item.run.databaseId, function(ok, jobs, err)
    if not ok then return require("plugins.utils.devops.ui.errors").show("DevOps: " .. (err or "gh run view failed")) end
    if #jobs == 0 then return vim.ui.open(item.run.url) end
    if #jobs == 1 then return jl.open(job_ctx(jobs[1])) end
    local rank = { failure = 0, timed_out = 0, cancelled = 2 }
    table.sort(jobs, function(a, b)
      local ra = a.status ~= "completed" and 1 or (rank[a.conclusion] or 3)
      local rb = b.status ~= "completed" and 1 or (rank[b.conclusion] or 3)
      if ra ~= rb then return ra < rb end
      return (a.name or "") < (b.name or "")
    end)
    vim.ui.select(jobs, {
      prompt = (item.run.workflowName or "Run") .. " · jobs",
      format_item = function(j) return (run_icon(j)) .. "  " .. (j.name or "?") end,
    }, function(j) if j then jl.open(job_ctx(j)) end end)
  end)
end

local function open_detail()
  if state.in_detail then
    -- Follow a Linked PR / Linked Jira Issue / Parent / Child row; Back returns here.
    local row = vim.api.nvim_win_get_cursor(state.content.win)[1]
    local file = detail.file_at(state.content.buf, row)
    if file then return detail.open_pr_file(file) end
    local ck = detail.check_at(state.content.buf, row)
    if ck then return require("plugins.utils.devops.ui.job_log").open(ck.ctx) end
    local rv = detail.reviewer_at(state.content.buf, row)
    if rv then return detail.open_reviewer_comments(state.content.buf, rv) end
    local link = detail.link_at(state.content.buf, row)
    if not link then return end
    if link.kind == "jira_link" then return follow_jira_link(link) end
    nav_push()
    show_detail("pr", link.pr)
    return
  end
  local item = current_item()
  if not item then return end
  if item.kind == "run" then return open_run(item) end
  nav_push()
  if item.kind == "jira" then
    show_detail("jira", item.key)
  elseif item.kind == "pr" then
    show_detail("pr", item.pr)
  end
end

local function open_browser()
  local item = current_item()
  if not item then return end
  if item.kind == "jira" then
    vim.ui.open(client.base_url() .. "/browse/" .. item.key)
  elseif item.kind == "pr" then
    vim.ui.open(item.pr.url)
  elseif item.kind == "run" then
    vim.ui.open(item.run.url)
  end
end

-- r on a workflow run: re-run it (failed / all jobs).
local function rerun_run()
  local item = current_item()
  if not (item and item.kind == "run") then return end
  require("plugins.utils.devops.ui.job_log").rerun(item.run.url, function()
    if current_section_id() == "gh_actions" then schedule_actions_refresh() end
  end)
end

-- J: open the Jira ticket(s) a PR mentions (branch, title, body).
local function pr_jira()
  local pr
  if state.in_detail then
    pr = state.detail_kind == "pr" and state.detail_pr or nil
  else
    local item = current_item()
    pr = item and item.kind == "pr" and item.pr or nil
  end
  if not pr then return end
  local keys = detail.issue_keys(pr.headRefName, pr.title, pr.body)
  if #keys == 0 then return vim.notify("DevOps: no Jira key in this PR's branch or title", vim.log.levels.INFO) end
  if not client.configured() then return vim.notify("DevOps: Jira not configured — run :JiraAuth", vim.log.levels.WARN) end
  if #keys == 1 then return follow_jira_link({ key = keys[1] }) end
  vim.ui.select(keys, { prompt = "Open Jira ticket" }, function(k) if k then follow_jira_link({ key = k }) end end)
end

-- Open the project's Scrum board in the browser, scoped to the active user filter
-- (or you), e.g. .../jira/software/c/projects/DEVOPS/boards/174?assignee=<id>.
local function open_board_in_browser()
  if not (state.project and state.project.key) then
    return vim.notify("DevOps: pick a project first ('p')", vim.log.levels.INFO)
  end
  if not (state.board and state.board.id) then
    return vim.notify("DevOps: pick a board first ('b')", vim.log.levels.INFO)
  end
  -- Team-managed (next-gen) projects omit the "/c/" segment; company-managed keep it.
  local seg = (state.project.style == "next-gen") and "/jira/software/projects/"
    or "/jira/software/c/projects/"
  local url = client.base_url() .. seg .. state.project.key .. "/boards/" .. tostring(state.board.id)
  -- Sprint Board is team-wide → open the full board; elsewhere scope to you / the filter.
  local assignee
  if current_section_id() ~= "jira_sprint" then
    assignee = (state.jira_user and state.jira_user.account_id) or client.account_id()
  end
  if assignee and assignee ~= "" then
    url = url .. "?assignee=" .. (assignee:gsub(":", "%%3A"))
  end
  vim.ui.open(url)
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
-- filter out). A real refresh ('R') re-applies the server filter.
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
  local was_detail = state.in_detail
  state.tab = next_tab
  state.section = next_section
  state.content_cursor = nil
  state.nav_stack = {}
  state.in_detail = false
  state.detail_kind = nil
  cancel_detail_load()
  if was_detail then
    -- The detail view deleted the list action maps (V, y, c, …) and added its own;
    -- swap them back, as nav_pop does when going Back.
    clear_action_keys()
    if setup_keymaps then setup_keymaps() end
  end
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
  if not is_jira_section(current_section_id()) then
    vim.notify("DevOps: user filter applies to the Jira tab", vim.log.levels.INFO)
    return
  end
  if not (state.project and state.project.key) then
    vim.notify("DevOps: pick a project first with 'p' (users are project-scoped)", vim.log.levels.INFO)
    return
  end
  api.project_assignees(state.project.key, function(ok, users, err)
    if not ok then return errors.show("DevOps: " .. (err or "user lookup failed")) end
    local me_id = client.account_id()
    local choices = { { label = "● Me" .. (client.display_name() and (" (" .. client.display_name() .. ")") or ""), account_id = me_id, me = true } }
    choices[#choices + 1] = { label = "○ Unassigned", unassigned = true }
    for _, u in ipairs(users) do
      if u.accountId and u.accountType ~= "app" and u.accountId ~= me_id then
        choices[#choices + 1] = { label = u.displayName or u.accountId, account_id = u.accountId }
      end
    end
    choices[#choices + 1] = { label = "🔍 Search by name…", search = true }
    vim.ui.select(choices, {
      prompt = "Show issues assigned to (persists across sections):",
      format_item = function(c) return c.label end,
    }, function(choice)
      if not choice then return end
      local function apply(user) -- user = nil (me / no filter) or { account_id, name }
        state.jira_user = user
        invalidate_tab_cache("jira")
        render_sidebar()
        if is_jira_section(current_section_id()) then load_section(true)
        else switch_section(1, tab_index_by_id("jira")) end
      end
      if choice.search then -- live, project-scoped search for anyone (not just recent)
        user_picker.open(function(picked)
          apply({ account_id = picked.id, name = picked.name })
        end, { title = "Filter by user", project_key = state.project.key })
        return
      end
      if choice.me then
        apply(nil)
      elseif choice.unassigned then
        apply({ unassigned = true, name = "Unassigned" })
      else
        apply({ account_id = choice.account_id, name = choice.label })
      end
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
    if not ok then return errors.show("DevOps: " .. (err or "no transitions")) end
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
        if not ok2 then return errors.show("DevOps: " .. (err2 or "transition failed")) end
        vim.notify("DevOps: " .. item.key .. " → " .. choice.name, vim.log.levels.INFO)
        -- Optimistic local update: no refetch, no flicker, issue stays visible.
        apply_transition_locally(item.key, choice.to)
      end)
    end)
  end)
end

-- '>' / '<': move the issue to the next / previous board column in one key
-- (the nearest column it has a transition into). Falls back to the 'm' picker.
local function advance(delta)
  local item = current_item()
  if not item or item.kind ~= "jira" then
    return vim.notify("DevOps: select a Jira issue first", vim.log.levels.INFO)
  end
  local cols = state.columns
  if not cols or #cols == 0 then
    return vim.notify("DevOps: no board columns: pick a board with 'b' (or use 'm')", vim.log.levels.INFO)
  end
  local function col_of(sid)
    for i, col in ipairs(cols) do
      for _, s in ipairs(col.statuses or {}) do
        if s == tostring(sid) then return i end
      end
    end
  end
  local cur = item.status_id and col_of(item.status_id)
  if not cur then return transition() end
  api.transitions(item.key, function(ok, trs, err)
    if not ok then return errors.show("DevOps: " .. (err or "no transitions")) end
    local i = cur + delta
    while i >= 1 and i <= #cols do
      for _, tr in ipairs(trs) do
        if tr.to and tr.to.id and col_of(tr.to.id) == i then
          return api.do_transition(item.key, tr.id, function(ok2, _, err2)
            if not ok2 then return errors.show("DevOps: " .. (err2 or "transition failed")) end
            vim.notify(("DevOps: %s  %s → %s"):format(item.key, item.status or "?", tr.to.name or tr.name),
              vim.log.levels.INFO)
            apply_transition_locally(item.key, tr.to)
          end)
        end
      end
      i = i + delta
    end
    vim.notify("DevOps: " .. item.key .. " can't move " .. (delta > 0 and "forward" or "back")
      .. " from " .. (item.status or "?") .. " (m for all transitions)", vim.log.levels.INFO)
  end)
end

-- 'B': create/switch to a branch named after the issue in the cwd's repo, then
-- move the issue to In Progress if it hasn't started yet.
local function jira_branch()
  local item = current_item()
  if not item and state.in_detail and state.detail_kind == "jira" and state.detail_key then
    item = { kind = "jira", key = state.detail_key }
  end
  if not item or item.kind ~= "jira" then
    return vim.notify("DevOps: select a Jira issue first", vim.log.levels.INFO)
  end
  local key = item.key
  api.get_issue(key, function(ok, issue, err)
    if not ok then return errors.show("DevOps: " .. (err or "issue fetch failed")) end
    local f = issue.fields or {}
    local default = branch.name(key, f.summary, f.issuetype and f.issuetype.name)
    vim.ui.input({ prompt = "Branch: ", default = default }, function(name)
      if not name or vim.trim(name) == "" then return end
      name = vim.trim(name)
      branch.checkout(name, vim.fn.getcwd(), function(ok2, how, err2)
        if not ok2 then return errors.show("DevOps: git — " .. (err2 or "checkout failed")) end
        vim.notify(("DevOps: %s branch %s"):format(how, name), vim.log.levels.INFO)
        vim.cmd("silent! checktime")
        local cat = f.status and f.status.statusCategory and f.status.statusCategory.key
        if cat ~= "new" then return end
        api.transitions(key, function(ok3, trs)
          local tr = ok3 and branch.pick_start(trs)
          if not tr then return end
          api.do_transition(key, tr.id, function(ok4, _, err4)
            if not ok4 then return errors.show("DevOps: " .. (err4 or "transition failed")) end
            vim.notify(("DevOps: %s → %s"):format(key, tr.to and tr.to.name or tr.name), vim.log.levels.INFO)
            if state.in_detail then
              detail.invalidate_cache(key)
              if state.detail_reopen then state.detail_reopen(vim.api.nvim_win_get_cursor(state.content.win)) end
            else
              apply_transition_locally(key, tr.to)
            end
          end)
        end)
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
    detail.set_tab(item.key, "comments")
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
              if not ok then return errors.show("DevOps: " .. (err or "comment failed")) end
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
      if not ok then return errors.show("DevOps: " .. (err or "comment failed")) end
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
    if not ok then return errors.show("DevOps: " .. (err or "fetch failed")) end
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
          if not ok2 then return errors.show("DevOps: " .. (err2 or "update failed")) end
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
  local project_key = state.project and state.project.key or item.key:match("^(%u[%u%d_]*)%-")
  -- Use the project's teammates (distinct assignees), not the org-wide assignable
  -- list — short and findable. Me + Unassigned are always offered.
  api.project_assignees(project_key, function(ok, users, err)
    if not ok then return errors.show("DevOps: " .. (err or "user lookup failed")) end
    local choices = {}
    local me_id = client.account_id()
    if me_id then
      choices[#choices + 1] = { label = "● Me (" .. (client.display_name() or "") .. ")", account_id = me_id }
    end
    choices[#choices + 1] = { label = "✗ Unassigned", account_id = nil }
    for _, u in ipairs(users) do
      if u.accountId and u.accountType ~= "app" and u.accountId ~= me_id then
        choices[#choices + 1] = { label = u.displayName or u.accountId, account_id = u.accountId }
      end
    end
    vim.ui.select(choices, {
      prompt = "Assign " .. item.key .. " to:",
      format_item = function(c) return c.label end,
    }, function(choice)
      if not choice then return end
      api.assign(item.key, choice.account_id, function(ok2, _, err2)
        if not ok2 then return errors.show("DevOps: " .. (err2 or "assign failed")) end
        vim.notify("DevOps: " .. item.key .. " assigned to " .. choice.label, vim.log.levels.INFO)
        refresh_current_jira_section()
      end)
    end)
  end)
end

-- Popup confirming a clone, showing the new key with quick actions.
-- old_key nil → a newly created issue.
local function show_clone_popup(old_key, new_key)
  local url = client.base_url() .. "/browse/" .. new_key
  -- Auto-copy the new key to the system (and unnamed) clipboard.
  pcall(vim.fn.setreg, "+", new_key)
  pcall(vim.fn.setreg, '"', new_key)
  local lines = {
    "",
    old_key and ("  ✓ Cloned  " .. old_key .. "  →  " .. new_key .. "    📋 copied")
      or ("  ✓ Created  " .. new_key .. "    📋 copied"),
    "",
    "  ↵  open in DevOps     o  open in browser     y  copy     q  close",
    "",
  }
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local width = 0
  for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
  width = math.min(width + 2, vim.o.columns - 4)
  local prev = vim.api.nvim_get_current_win()
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", width = width, height = #lines,
    row = math.floor((vim.o.lines - #lines) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal", border = "rounded",
    title = old_key and " Issue cloned " or " Issue created ", title_pos = "center",
  })
  vim.wo[win].winhighlight = "Normal:Normal,FloatBorder:DevOpsBorder,FloatTitle:DevOpsTitle"
  local cns = vim.api.nvim_create_namespace("DevOpsClone")
  local s = lines[2]:find(new_key, 1, true)
  if s then
    pcall(vim.api.nvim_buf_set_extmark, buf, cns, 1, s - 1, { end_col = s - 1 + #new_key, hl_group = "DevOpsId" })
  end
  local function close_popup()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if vim.api.nvim_win_is_valid(prev) then pcall(vim.api.nvim_set_current_win, prev) end
  end
  vim.keymap.set("n", "<CR>", function()
    close_popup(); detail.open_issue(new_key)
  end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "o", function()
    close_popup(); vim.ui.open(url)
  end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "y", function()
    vim.fn.setreg("+", new_key); vim.fn.setreg('"', new_key)
    vim.notify("DevOps: copied " .. new_key, vim.log.levels.INFO)
    close_popup()
  end, { buffer = buf, nowait = true, silent = true })
  for _, k in ipairs({ "q", "<C-d>", "<Esc>" }) do
    vim.keymap.set("n", k, close_popup, { buffer = buf, nowait = true, silent = true })
  end
end

-- '+': project (current first) → type → epic → sprint → summary (prefilled
-- from the git branch) → description. Assigned to me.
local function jira_create()
  if not client.configured() then
    return vim.notify("DevOps: configure Jira first (:JiraAuth)", vim.log.levels.WARN)
  end
  local cur_key = state.project and state.project.key
  local sel = {}

  local function finish()
    local fields = {
      project = { key = sel.proj.key },
      issuetype = { name = sel.itype.name },
      summary = sel.summary,
    }
    if sel.desc and sel.desc ~= "" then fields.description = adf.text_to_adf(sel.desc) end
    if sel.epic then fields.parent = { key = sel.epic } end
    local me_id = client.account_id()
    if me_id then fields.assignee = { accountId = me_id } end
    api.create_issue(fields, function(ok, data, err)
      if not ok then return errors.show("DevOps: " .. (err or "create failed")) end
      local new_key = data and data.key or "?"
      local function done()
        show_clone_popup(nil, new_key)
        refresh_current_jira_section()
      end
      if not sel.sprint then return done() end
      api.move_to_sprint(sel.sprint.id, new_key, function(ok2, _, err2)
        if not ok2 then errors.show("DevOps: created " .. new_key .. " but sprint move failed — " .. (err2 or "?")) end
        done()
      end)
    end)
  end

  local function ask_text()
    branch.current(vim.fn.getcwd(), function(br)
      vim.ui.input({ prompt = "Summary: ", default = branch.summary_from_branch(br) or "" }, function(summary)
        if not summary or vim.trim(summary) == "" then return end
        sel.summary = vim.trim(summary)
        input.open("Description (new " .. sel.itype.name .. ")", "", function(desc)
          sel.desc = desc
          finish()
        end)
      end)
    end)
  end

  local function ask_sprint()
    if sel.itype.subtask then return ask_text() end
    local board_id = state.board and sel.proj.key == cur_key and state.board.id or nil
    api.project_sprints(sel.proj.key, board_id, "active,future", function(ok, sprints)
      if not ok or #sprints == 0 then return ask_text() end
      table.sort(sprints, function(x, y)
        if (x.state == "active") ~= (y.state == "active") then return x.state == "active" end
        return (x.startDate or x.name or "") < (y.startDate or y.name or "")
      end)
      local items = { { backlog = true, name = "Backlog" } }
      vim.list_extend(items, sprints)
      vim.ui.select(items, {
        prompt = "Sprint:",
        format_item = function(sp)
          if sp.backlog then return "○ Backlog" end
          return (sp.state == "active" and "● " or "◌ ") .. sp.name
        end,
      }, function(sp)
        if not sp then return end
        sel.sprint = not sp.backlog and sp or nil
        ask_text()
      end)
    end)
  end

  local function ask_epic()
    local tname = (sel.itype.name or ""):lower()
    if sel.itype.subtask or tname == "epic" then return ask_sprint() end
    api.epics(sel.proj.key, nil, function(ok, epics)
      if not ok or #epics == 0 then return ask_sprint() end
      local items = { { none = true } }
      vim.list_extend(items, epics)
      vim.ui.select(items, {
        prompt = "Epic:",
        format_item = function(e)
          if e.none then return "— No epic —" end
          return e.key .. "  " .. ((e.fields or {}).summary or "")
        end,
      }, function(e)
        if not e then return end
        sel.epic = not e.none and e.key or nil
        ask_sprint()
      end)
    end)
  end

  api.list_projects(nil, function(ok, projects, err)
    if not ok then return errors.show("DevOps: " .. (err or "project list failed")) end
    if cur_key then
      table.sort(projects, function(x, y)
        if (x.key == cur_key) ~= (y.key == cur_key) then return x.key == cur_key end
        return false
      end)
    end
    vim.ui.select(projects, {
      prompt = "Project:",
      format_item = function(p) return p.key .. "  —  " .. (p.name or "") .. (p.key == cur_key and "  (current)" or "") end,
    }, function(proj)
      if not proj then return end
      sel.proj = proj
      api.issue_types(proj.key, function(ok2, types, err2)
        if not ok2 then return errors.show("DevOps: " .. (err2 or "types failed")) end
        vim.ui.select(types, {
          prompt = "Issue type:",
          format_item = function(t) return t.name end,
        }, function(itype)
          if not itype then return end
          sel.itype = itype
          ask_epic()
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
    if not ok then return errors.show("DevOps: " .. (err or "fetch failed")) end
    local f = issue.fields or {}
    local project_key = item.key:match("^(%u[%u%d_]*)%-")
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
          if not ok2 then return errors.show("DevOps: " .. (err2 or "clone failed")) end
          local new_key = data and data.key or "?"
          refresh_current_jira_section()
          show_clone_popup(item.key, new_key)
        end)
      end, input_opts_with_win())
    end)
  end)
end

-- Move the selected Jira issue into a sprint (or the backlog). Sprints live on
-- per-team boards, so we gather active+future sprints from all of the issue's
-- *project* boards (not just the dashboard's selected board, which may not own
-- the sprint you want — e.g. HORA's future sprint lives on the Horasphere board).
move_to_sprint = function()
  local item = current_item()
  if not item and state.in_detail and state.detail_kind == "jira" and state.detail_key then
    item = { kind = "jira", key = state.detail_key }
  end
  if not item or item.kind ~= "jira" then
    return vim.notify("DevOps: select a Jira issue to move", vim.log.levels.INFO)
  end
  local project = item.key:match("^(%u[%u%d_]*)%-")

  local function pick(sprints)
    if #sprints == 0 then
      return vim.notify("DevOps: no active/future sprints for " .. (project or "?"), vim.log.levels.INFO)
    end
    local rank = { future = 0, active = 1 } -- future first (soonest), then active
    table.sort(sprints, function(a, b)
      local ra, rb = rank[a.state] or 3, rank[b.state] or 3
      if ra ~= rb then return ra < rb end
      return (a.id or 0) < (b.id or 0)
    end)
    local choices = {}
    for _, s in ipairs(sprints) do choices[#choices + 1] = s end
    choices[#choices + 1] = { name = "○ Backlog", backlog = true }
    vim.ui.select(choices, {
      prompt = "Move " .. item.key .. " to (future/active sprints):",
      format_item = function(s) return (s.name or "?") .. (s.backlog and "" or ("   [" .. (s.state or "?") .. "]")) end,
    }, function(choice)
      if not choice then return end
      local function done(ok2, _, err2)
        if not ok2 then return errors.show("DevOps: move failed — " .. (err2 or "?")) end
        vim.notify("DevOps: moved " .. item.key .. " → " .. (choice.name or "?"), vim.log.levels.INFO)
        if state.in_detail then
          -- Lists are stale now; re-render the ticket being viewed (its Sprint changed).
          for _, sid in ipairs({ "jira_issues", "jira_sprint", "jira_backlog" }) do cache_invalidate(sid) end
          detail.invalidate_cache(item.key)
          if state.detail_reopen then
            state.detail_reopen(vim.api.nvim_win_get_cursor(state.content.win))
          end
        else
          refresh_current_jira_section()
        end
      end
      if choice.backlog then api.move_to_backlog(item.key, done)
      else api.move_to_sprint(choice.id, item.key, done) end
    end)
  end

  if not project and not state.board then
    return vim.notify("DevOps: pick a Scrum board first ('b')", vim.log.levels.INFO)
  end
  -- Only this project's own sprints, not other teams' sprints leaking onto the board.
  local board_id = (state.board and (not project or project == (state.project and state.project.key)))
    and state.board.id or nil
  api.project_sprints(project, board_id, "active,future", function(ok, sprints, err)
    if not ok then return errors.show("DevOps: " .. (err or "sprint list failed")) end
    pick(sprints)
  end)
end

local function jira_search()
  if not client.configured() then
    errors.show("DevOps: Jira not configured — run :JiraAuth")
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
    if not timer:is_closing() then timer:close() end
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
    do_close() -- just close the search bar; keep the current view (don't navigate)
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

-- Org for the scoped PR search: config github.org, else the org your gh token's
-- account belongs to (if it's in several, the one most of your PRs/reviews are
-- in). Fetched once per session by warm_search_org. nil → global only.
local function pr_owner_counts()
  local counts = {}
  for _, sec in ipairs({ "gh_prs", "gh_reviews" }) do
    local data = cache_get_raw(sec)
    for _, pr in ipairs(type(data) == "table" and data or {}) do
      local o = type(pr) == "table" and type(pr.repository) == "table"
        and (pr.repository.nameWithOwner or ""):match("^([^/]+)/")
      if o then counts[o] = (counts[o] or 0) + 1 end
    end
  end
  return counts
end

local function search_org()
  local cfg = config.options.github and config.options.github.org
  if cfg and cfg ~= "" then return cfg end
  local orgs = state._token_orgs
  if not orgs or #orgs == 0 then return nil end
  if #orgs == 1 then return orgs[1] end
  local counts, best = pr_owner_counts(), orgs[1]
  for _, o in ipairs(orgs) do if (counts[o] or 0) > (counts[best] or 0) then best = o end end
  return best
end

local function warm_search_org(cb)
  if state._token_orgs then if cb then cb() end return end
  gh.user_orgs(function(ok, orgs)
    if ok then state._token_orgs = orgs end
    if cb then vim.schedule(cb) end
  end)
end

local function gh_search()
  if not gh.available() then
    errors.show("DevOps: gh CLI not found")
    return
  end
  local prev_win = vim.api.nvim_get_current_win()

  local input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[input_buf].bufhidden = "wipe"
  local content_cfg = vim.api.nvim_win_get_config(state.content.win)
  local w = content_cfg.width - 2

  local org = search_org()
  local scope_org = org ~= nil -- default: current org; C-t toggles to global

  local function title_text()
    local scope_label = scope_org and ("org: " .. org) or "global"
    return " 🔍 GitHub [" .. scope_label .. "]  C-t: " .. (scope_org and "global" or ("org" .. (org and "" or " (none)"))) .. " "
  end


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
  local last_query = ""
  local do_search

  -- Org not fetched yet (S pressed right after opening): scope it once it lands.
  if not org then
    warm_search_org(function()
      org = search_org()
      if closed or not org or not vim.api.nvim_win_is_valid(input_win) then return end
      scope_org = true
      vim.api.nvim_win_set_config(input_win, { title = title_text(), title_pos = "center" })
      last_query = ""
      do_search(vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1] or "")
    end)
  end

  local function do_close()
    if closed then return end
    closed = true
    timer:stop()
    if not timer:is_closing() then timer:close() end
    vim.cmd("stopinsert")
    if vim.api.nvim_win_is_valid(input_win) then vim.api.nvim_win_close(input_win, true) end
    if prev_win and vim.api.nvim_win_is_valid(prev_win) then
      vim.api.nvim_set_current_win(prev_win)
    end
  end

  function do_search(query)
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
      if scope_org and org then opts.owner = org end
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
    if not org then return end
    scope_org = not scope_org
    last_query = "" -- same text, new scope: search again
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
    do_close() -- just close the search bar; keep the current view (don't navigate)
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
    errors.show("DevOps: PR missing repo/number")
    return nil, nil, nil
  end
  return item, repo, n
end

-- GitHub rejects approving / requesting changes on your own PR; say so up front.
local function refuse_own(pr, what)
  if not gh.is_me(pr and pr.author and pr.author.login) then return false end
  vim.notify("DevOps: you can't " .. what .. " your own PR — use c to comment", vim.log.levels.WARN)
  return true
end

local function gh_approve()
  local item, repo, n = pr_item()
  if not item then return end
  if refuse_own(item.pr, "approve") then return end
  gh.pr_approve(repo, n, function(ok, _, err)
    if not ok then return errors.show("DevOps: " .. (err or "approve failed")) end
    vim.notify("DevOps: approved #" .. n, vim.log.levels.INFO)
    cache_invalidate("gh_prs"); cache_invalidate("gh_reviews"); if is_open() then load_section(true) end
  end)
end

local function gh_request_changes()
  local item, repo, n = pr_item()
  if not item then return end
  if refuse_own(item.pr, "request changes on") then return end
  input.open("Request changes #" .. n, "", function(body)
    if body == "" then return end
    gh.pr_request_changes(repo, n, body, function(ok, _, err)
      if not ok then return errors.show("DevOps: " .. (err or "review failed")) end
      vim.notify("DevOps: requested changes on #" .. n, vim.log.levels.INFO)
      cache_invalidate("gh_prs"); cache_invalidate("gh_reviews"); if is_open() then load_section(true) end
    end)
  end, detail.pr_comment_preview(item.pr, "Requesting changes on"))
end

local function gh_comment()
  local item, repo, n = pr_item()
  if not item then return end
  input.open("Comment #" .. n, "", function(body)
    if body == "" then return end
    gh.pr_comment(repo, n, body, function(ok, _, err)
      if not ok then return errors.show("DevOps: " .. (err or "comment failed")) end
      vim.notify("DevOps: commented on #" .. n, vim.log.levels.INFO)
    end)
  end, detail.pr_comment_preview(item.pr, "Commenting on"))
end

local function gh_ready()
  local item, repo, n = pr_item()
  if not item then return end
  gh.pr_ready(repo, n, function(ok, _, err)
    if not ok then return errors.show("DevOps: " .. (err or "ready failed")) end
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
      if not ok then return errors.show("DevOps: " .. (err or "merge failed")) end
      vim.notify("DevOps: #" .. n .. " merged!", vim.log.levels.INFO)
      cache_invalidate("gh_prs"); cache_invalidate("gh_reviews"); if is_open() then load_section(true) end
    end)
  end)
end

local function gh_diff()
  local item, repo, n = pr_item()
  if not item then return end
  gh.pr_diff(repo, n, function(ok, diff_text, err)
    if not ok then return errors.show("DevOps: " .. (err or "diff failed")) end
    require("plugins.utils.devops.ui.diff_viewer").open(diff_text, "Diff #" .. n, { pr = { repo = repo, number = n } })
  end)
end

local function gh_since_review()
  local item, repo, n = pr_item()
  if not item then return end
  detail.diff_since_review(repo, n)
end

local function gh_files()
  local item, repo, n = pr_item()
  if not item then return end
  gh.pr_diff(repo, n, function(ok, diff_text, err)
    if not ok then return errors.show("DevOps: " .. (err or "diff failed")) end
    require("plugins.utils.devops.ui.pr_files_picker").open(repo, n, diff_text)
  end)
end

-- Sprint Board 'F': filter by one of the people actually on the board (built
-- from the loaded sprint issues, not the company directory).
local PERSON_FILTER_LABEL = { jira_sprint = "Sprint Board", jira_backlog = "Backlog" }
local function filter_people(sec_id)
  local what = PERSON_FILTER_LABEL[sec_id]
  local issues = cache_get_raw(sec_id)
  if not issues then
    return vim.notify("DevOps: " .. what .. " not loaded yet", vim.log.levels.INFO)
  end
  local by_id, n_unassigned = {}, 0
  for _, it in ipairs(issues) do
    local a = it.fields and it.fields.assignee
    if type(a) == "table" and a.accountId then
      local p = by_id[a.accountId] or { account_id = a.accountId, name = a.displayName or a.accountId, count = 0 }
      p.count = p.count + 1
      by_id[a.accountId] = p
    else
      n_unassigned = n_unassigned + 1
    end
  end
  local people = {}
  for _, p in pairs(by_id) do people[#people + 1] = p end
  table.sort(people, function(x, y) return x.name:lower() < y.name:lower() end)

  local me = client.account_id()
  local choices = { { label = "● Everyone  (" .. #issues .. ")", clear = true } }
  if me and by_id[me] then
    choices[#choices + 1] = { label = "● Me  (" .. by_id[me].count .. ")", person = by_id[me] }
  end
  for _, p in ipairs(people) do
    choices[#choices + 1] = { label = p.name .. "  (" .. p.count .. ")", person = p }
  end
  if n_unassigned > 0 then
    choices[#choices + 1] = {
      label = "✗ Unassigned  (" .. n_unassigned .. ")",
      person = { unassigned = true, name = "Unassigned" },
    }
  end

  vim.ui.select(choices, {
    prompt = "Filter " .. what .. " by:",
    format_item = function(c) return c.label end,
  }, function(choice)
    if not choice then return end
    state.person_filter[sec_id] = (not choice.clear) and { account_id = choice.person.account_id,
      unassigned = choice.person.unassigned, name = choice.person.name } or nil
    if current_section_id() ~= sec_id or state.in_detail then return end
    state.content_cursor = nil
    render_jira_from_cache(sec_id, cache_get_raw(sec_id) or issues)
    render_sidebar()
  end)
end

-- 'F': people filter on the Sprint Board / Backlog lists; changed-files tree for PRs elsewhere.
local function dispatch_F()
  local sec_id = current_section_id()
  if PERSON_FILTER_LABEL[sec_id] and not state.in_detail then
    filter_people(sec_id)
  else
    gh_files()
  end
end

local function gh_checkout()
  local item, repo, n = pr_item()
  if not item then return end
  gh.pr_checkout(repo, n, function(ok, _, err)
    if not ok then return errors.show("DevOps: " .. (err or "checkout failed — cwd must be the repo")) end
    vim.notify("DevOps: checked out #" .. n, vim.log.levels.INFO)
  end)
end

local function gh_create_pr()
  local sec_id = current_section_id()
  if sec_id ~= "gh_prs" and sec_id ~= "gh_reviews" then
    vim.notify("DevOps: switch to a GitHub section first", vim.log.levels.INFO)
    return
  end
  if not gh.available() then return errors.show("DevOps: gh CLI not found") end
  input.open("PR Title", "", function(title)
    if not title or title == "" then return end
    input.open("PR Body (optional)", "", function(body)
      gh.pr_create(title, body or "", nil, function(ok, out, err)
        if not ok then return errors.show("DevOps: " .. (err or "PR creation failed")) end
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
  if not section_honours_filters(sec_id) then
    return vim.notify("DevOps: scope toggle only applies to My Issues", vim.log.levels.INFO)
  end
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
  cache_invalidate("jira_issues")
  load_section(true)
end

local function toggle_done()
  if not section_honours_filters() then
    return vim.notify("DevOps: +Done toggle only applies to My Issues", vim.log.levels.INFO)
  end
  state.include_done = not state.include_done
  render_sidebar()
  update_winbar()
  cache_invalidate("jira_issues")
  load_section(true)
end

---------------------------------------------------------------------------
-- Help popup
---------------------------------------------------------------------------

local function show_help()
  local groups = key_groups(key_context())
  local key_w = 0
  for _, g in ipairs(groups) do
    for _, e in ipairs(g[2]) do key_w = math.max(key_w, vim.fn.strdisplaywidth(e[1])) end
  end
  local lines, marks = { "" }, {}
  local function add(text, hl_spans)
    lines[#lines + 1] = text
    for _, h in ipairs(hl_spans or {}) do marks[#marks + 1] = { #lines - 1, h[1], h[2], h[3] } end
  end
  for gi, g in ipairs(groups) do
    if gi > 1 then add("") end
    add("  " .. g[1], { { 2, 2 + #g[1], "DevOpsSection" } })
    for _, e in ipairs(g[2]) do
      local k = "    " .. e[1] .. string.rep(" ", key_w - vim.fn.strdisplaywidth(e[1])) .. "   "
      local spans = { { 4, 4 + #e[1], "DevOpsKey" } }
      if e[4] then spans[#spans + 1] = { #k + #e[3] + 2, #k + #e[3] + 5, "DevOpsDim" } end
      add(k .. e[3] .. (e[4] and "  ·" or ""), spans)
    end
  end
  add("")
  add("  · = shown in the footer", { { 2, 25, "DevOpsDim" } })

  local w = 0
  for _, l in ipairs(lines) do w = math.max(w, vim.fn.strdisplaywidth(l)) end
  w = math.min(w + 3, vim.o.columns - 6)
  local h = math.min(#lines, vim.o.lines - 6)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local hns = vim.api.nvim_create_namespace("DevOpsHelp")
  for _, m in ipairs(marks) do
    pcall(vim.api.nvim_buf_set_extmark, buf, hns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", width = w, height = h,
    row = math.floor((vim.o.lines - h) / 2) - 1,
    col = math.floor((vim.o.columns - w) / 2),
    style = "minimal", border = "rounded", zindex = 60,
    title = { { " Keys · " .. current_section_label() .. (state.in_detail and " · detail" or "") .. " ", "DevOpsTitle" } },
    title_pos = "center",
    footer = { { " q close ", "DevOpsDim" } }, footer_pos = "center",
  })
  vim.wo[win].winhighlight = "Normal:Normal,FloatBorder:DevOpsBorderActive,FloatTitle:DevOpsTitle"
  local function close_help() if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end end
  for _, k in ipairs({ "q", "<C-d>", "<Esc>", "?" }) do
    vim.keymap.set("n", k, close_help, { buffer = buf, nowait = true })
  end
  vim.api.nvim_create_autocmd("BufLeave", { buffer = buf, once = true, callback = function() vim.schedule(close_help) end })
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

-- Shift+Arrow: sidebar · content, then the adjacent WezTerm pane. Uses the
-- focus helpers so the sidebar/content cursors are restored.
local function pane_move(dir)
  local cur = vim.api.nvim_get_current_win()
  if dir == "Left" and cur == state.content.win
    and state.sidebar.win and vim.api.nvim_win_is_valid(state.sidebar.win) then
    return focus_sidebar()
  elseif dir == "Right" and cur == state.sidebar.win and is_open() then
    return focus_content()
  end
  require("plugins.utils.devops.ui.pane_nav").move(dir)
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
    project_style = state.project and state.project.style,
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
      -- Keep the real sprint {id,name} so the sprint picker can swap to a past one.
      state.sprint = (ok2 and sprint) and { id = sprint.id, name = sprint.name } or nil
      cb()
    end)
  end)
end

-- Resolve which board to use for the project (prompt if more than one),
-- load its columns, persist, then cb().
local function resolve_board_then(cb)
  -- Keep the current board if it still belongs to this project and the fetch
  -- fails or the prompt is cancelled — never persist a wiped board on a hiccup.
  local prev = state.board
  state.board, state.columns = nil, nil
  api.list_boards(state.project.key, function(ok, boards)
    local function finalize()
      persist_prefs()
      load_board_columns(cb)
    end
    if not ok then
      state.board = prev
      return load_board_columns(cb)
    end
    if prev then
      for _, b in ipairs(boards) do
        if b.id == prev.id then state.board = prev end
      end
    end
    if #boards == 0 then return finalize() end
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

-- Index of a section within a tab (for switch_section).
local function section_index_by_id(tab_idx, sec_id)
  local tab = TABS[tab_idx]
  for i, sec in ipairs(tab and tab.sections or {}) do
    if sec.id == sec_id then return i end
  end
  return 1
end

-- Pick a sprint (active / future / past-closed) for the board and show its board.
local function pick_sprint()
  if not state.board then
    return vim.notify("DevOps: pick a Scrum board first ('b')", vim.log.levels.INFO)
  end
  local project_key = state.project and state.project.key
  api.project_sprints(project_key, state.board.id, nil, function(ok, sprints, err)
    if not ok then return errors.show("DevOps: " .. (err or "sprint list failed")) end
    if #sprints == 0 then return vim.notify("DevOps: no sprints on this board", vim.log.levels.INFO) end
    -- Active, then upcoming (soonest first), then closed (most recent first).
    local rank = { active = 0, future = 1, closed = 2 }
    table.sort(sprints, function(a, b)
      local ra, rb = rank[a.state] or 3, rank[b.state] or 3
      if ra ~= rb then return ra < rb end
      local da, db = a.startDate or "", b.startDate or ""
      if a.state == "future" then
        if da ~= db then
          if da == "" then return false elseif db == "" then return true end
          return da < db
        end
        return (a.id or 0) < (b.id or 0)
      end
      if da ~= db then return da > db end
      return (a.id or 0) > (b.id or 0)
    end)
    -- Offer a reset to the live active sprint(s) at the top.
    table.insert(sprints, 1, { name = "● Active sprint(s)", state = "active", reset = true })
    vim.ui.select(sprints, {
      prompt = "Select sprint:",
      format_item = function(s) return (s.name or "?") .. (s.reset and "" or ("   [" .. (s.state or "?") .. "]")) end,
    }, function(choice)
      if not choice then return end
      local function show_sprint_board()
        cache_invalidate("jira_sprint")
        render_sidebar()
        local jt = tab_index_by_id("jira")
        switch_section(section_index_by_id(jt, "jira_sprint"), jt)
      end
      if choice.reset then -- back to the live active sprint (openSprints default)
        api.active_sprint(state.board.id, function(ok2, sprint)
          state.sprint = (ok2 and sprint) and { id = sprint.id, name = sprint.name } or nil
          show_sprint_board()
        end)
        return
      end
      state.sprint = { id = choice.id, name = choice.name, state = choice.state, picked = true }
      vim.notify("DevOps: Sprint Board → " .. (choice.name or "?"), vim.log.levels.INFO)
      show_sprint_board()
    end)
  end)
end

-- Prompt for a project, resolve its board, then cb().
local function pick_project(cb)
  if not client.configured() then
    vim.notify("DevOps: configure Jira first (:JiraAuth)", vim.log.levels.WARN)
    return cb and cb()
  end
  api.list_projects(nil, function(ok, projects, err)
    if not ok then
      errors.show("DevOps: " .. (err or "project list failed"))
      return cb and cb()
    end
    vim.ui.select(projects, {
      prompt = "Select Jira project:",
      format_item = function(p) return p.key .. "  —  " .. (p.name or "") end,
    }, function(choice)
      if not choice then return cb and cb() end
      state.project = { key = choice.key, id = choice.id, name = choice.name, style = choice.style }
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
    state.project = { key = prefs.project_key, name = prefs.project_name, style = prefs.project_style }
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
  watch.stop()
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

-- Float layout geometry, derived from the current editor size.
local function float_geometry()
  local total = vim.o.columns - 2
  local footer_h = 1
  local height = vim.o.lines - 2 - footer_h - 2 -- room for footer + gap
  local sw = 32
  return total, footer_h, height, sw, total - sw - 3
end

local function open_float_windows()
  local total, footer_h, height, sw, cw = float_geometry()
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
  vim.wo[state.sidebar.win].winhighlight = winhl
  vim.wo[state.content.win].winhighlight = winhl
  vim.wo[state.footer.win].winhighlight = winhl
end

-- Restore hidden float windows with existing buffers (preserves content).
local function restore_float_windows()
  local total, footer_h, height, sw, cw = float_geometry()
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
  vim.api.nvim_win_resize(state.sidebar.win, 32, -1)
  vim.api.nvim_set_current_win(state.content.win)
  vim.wo[state.content.win].cursorline = true
  vim.wo[state.sidebar.win].cursorline = true
end

local function map(lhs, fn, desc)
  vim.keymap.set("n", lhs, fn, { buffer = state.content.buf, nowait = true, silent = true, desc = "DevOps: " .. desc })
end

function setup_keymaps()
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
  map("<2-LeftMouse>", open_detail, "open")
  map("R", function()
    gh.clear_diff_cache()
    api.clear_sprint_cache()
    load_section(true)
    refresh_notifications()
    -- Re-warm the sprint pickers ('v' / 'V').
    if state.project and state.project.key and state.board and state.board.id then
      api.project_sprints(state.project.key, state.board.id, nil, function() end)
      api.project_sprints(state.project.key, state.board.id, "active,future", function() end)
    end
  end, "refresh")
  map("o", open_browser, "open in browser")
  map("O", open_board_in_browser, "open board in browser")
  map("u", select_user, "select user")
  map("p", function() pick_project(function() switch_section(1, tab_index_by_id("jira")) end) end, "pick project")
  map("b", pick_board, "pick board")
  map("v", pick_sprint, "pick sprint")
  for _, d in ipairs({ "Left", "Right", "Up", "Down" }) do
    map("<S-" .. d .. ">", function() pane_move(d) end, "pane / WezTerm " .. d:lower())
  end
  -- Write actions (dispatched by item kind for c/a)
  map("c", dispatch_comment, "comment")
  map("a", dispatch_action_a, "assign/approve")
  map("e", jira_edit, "edit issue")
  -- '+' creates (Jira issue in a Jira section, PR in a GitHub section). 'n'/'N'
  -- are left to Vim's search-next/prev.
  map("+", function()
    if is_jira_section(current_section_id()) then jira_create() else gh_create_pr() end
  end, "new issue / PR")
  map("y", jira_clone, "clone issue")
  map("V", move_to_sprint, "move issue to sprint")
  -- '/' stays native Vim search in the buffer; 'S' runs the DevOps Jira/GitHub search.
  map("S", dispatch_search, "search")
  map("*", toggle_bookmark, "bookmark")
  -- GitHub PR actions
  map("C", gh_request_changes, "request changes")
  map("D", gh_ready, "mark ready")
  map("m", dispatch_m, "move issue / merge PR")
  map(">", function() advance(1) end, "issue → next column")
  map("<", function() advance(-1) end, "issue → previous column")
  map("d", gh_diff, "view diff")
  map("F", dispatch_F, "sprint people filter / changed files tree")
  map("U", gh_since_review, "diff since my review")
  map("x", gh_checkout, "checkout PR")
  map("J", pr_jira, "open the PR's Jira ticket")
  map("r", rerun_run, "re-run workflow run")
  map("B", jira_branch, "branch from issue")
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
  for _, d in ipairs({ "Left", "Right", "Up", "Down" }) do
    smap("<S-" .. d .. ">", function() pane_move(d) end, "pane / WezTerm " .. d:lower())
  end
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

-- Re-fit the dashboard to a new editor size (e.g. a terminal split opened or
-- closed): resize the floats and re-render the width-dependent list + footer.
local function relayout()
  if not is_open() then return end
  if state.layout == "float" then
    local total, footer_h, height, sw, cw = float_geometry()
    local function fit(win, cfg)
      if win and vim.api.nvim_win_is_valid(win) then
        cfg.relative = "editor"
        pcall(vim.api.nvim_win_set_config, win, cfg)
      end
    end
    fit(state.sidebar.win, { row = 0, col = 0, width = sw, height = height })
    fit(state.content.win, { row = 0, col = sw + 3, width = cw, height = height })
    fit(state.footer.win, { row = height + 2, col = 0, width = total, height = footer_h })
  end
  if not state.in_detail and not state.detail_loading then
    local cursor = vim.api.nvim_win_get_cursor(state.content.win)
    load_section(false, true)
    pcall(vim.api.nvim_win_set_cursor, state.content.win, cursor)
  end
  render_footer()
end

local function setup_autocmds()
  local grp = vim.api.nvim_create_augroup("DevOpsWin", { clear = true })
  local resize_timer
  vim.api.nvim_create_autocmd("VimResized", {
    group = grp,
    callback = function()
      if not is_open() then return end
      resize_timer = resize_timer or vim.uv.new_timer()
      resize_timer:stop()
      resize_timer:start(50, 0, vim.schedule_wrap(relayout))
    end,
  })
  -- Any of the three panes closing tears the whole dashboard down; watching only
  -- the content window left orphaned sidebar/footer windows behind when one of
  -- those was closed directly (e.g. :q while focused there).
  for _, w in ipairs({ state.content.win, state.sidebar.win, state.footer.win }) do
    if w and vim.api.nvim_win_is_valid(w) then
      vim.api.nvim_create_autocmd("WinClosed", {
        group = grp,
        pattern = tostring(w),
        once = true,
        callback = close,
      })
    end
  end
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
-- Keyed on the context the warmed entries belong to, so switching project,
-- account, or sprint re-warms instead of leaving the caches cold forever.
local prefetched_ctx = nil
local function prefetch_other_sections()
  local ctx = table.concat({
    (state.project and state.project.key) or "-",
    client.account_id() or "-",
    (state.sprint and tostring(state.sprint.id or state.sprint.name)) or "-",
  }, "|")
  if prefetched_ctx == ctx then return end
  prefetched_ctx = ctx

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

    -- Warm the sprint lists so 'v' / 'V' open instantly (cached in the API layer).
    if project_key and state.board and state.board.id then
      api.project_sprints(project_key, state.board.id, nil, function() end)
      api.project_sprints(project_key, state.board.id, "active,future", function() end)
    end

    -- Sprint/Epics/Backlog depend on the active user filter and selected sprint, so
    -- they're loaded fresh on first switch (load_section) rather than prefetched,
    -- to avoid caching a version inconsistent with the current filter.
  end

  -- GitHub sections
  if gh.available() then
    gh.fetch_current_user() -- ensure login is cached for review status detection
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

-- Test hooks (headless spec drives these flows with stubbed pickers).
M._actions = { jira_create = jira_create, jira_branch = jira_branch }
M._check_status = github_check_status
M._readiness = pr_readiness
M._search_org = search_org
M._cache_set = cache_set
M._set_token_orgs = function(o) state._token_orgs = o end
M._key_groups = key_groups
M._footer_keys = footer_keys
M._run_icon = run_icon
-- Step aside (float layout only) so a file can open in a regular window.
function M.hide_float()
  if is_open() and state.layout == "float" then hide() end
end
M._refuse_own = refuse_own

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
    if state.in_detail and state.detail_reopen then
      -- setup_keymaps() put the list maps back; re-show the ticket to restore its own.
      clear_action_keys()
      state.detail_reopen(vim.api.nvim_win_get_cursor(state.content.win))
    end
    return
  end

  -- Fresh open.
  state.layout = layout
  state.tab = 1
  state.section = 1
  state.jira_user = nil -- reset the user filter back to "me" on each open
  state.person_filter = {}
  state.content_cursor = nil
  state.nav_stack = {}
  state.in_detail = false
  state.detail_loading = false
  state.detail_kind = nil
  state.gh_notif_count = 0
  state.bookmarks = store.load_bookmarks()
  warm_cwd_repo() -- async-resolve cwd→repo so PR search never blocks on it
  warm_search_org() -- the token account's org, for the org-scoped PR search

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
