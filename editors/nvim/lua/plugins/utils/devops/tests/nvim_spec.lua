-- Headless-Neovim tests for the Jira API wrappers and the issue card builder,
-- with the HTTP client stubbed (offline, no side effects).
-- Run:  nvim --headless --clean -l tests/nvim_spec.lua   (from the devops/ dir, or any cwd)

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = here .. "../../../../?.lua;" .. here .. "../../../../?/init.lua;" .. package.path

-- ── tiny assert framework ──────────────────────────────────────────────────
local passed, failed = 0, 0
local function ok(cond, name)
  if cond then passed = passed + 1
  else failed = failed + 1; print("  ✗ " .. name) end
end
local function eq(got, want, name)
  if vim.deep_equal(got, want) then passed = passed + 1
  else failed = failed + 1; print(("  ✗ %s\n      want: %s\n      got:  %s"):format(name, vim.inspect(want), vim.inspect(got))) end
end

-- ── stub HTTP client: route(method, path, body) → data | nil, err ───────────
local client = require("plugins.utils.devops.jira.client")
local calls, route, async = {}, nil, false
client.request = function(method, path, body, cb)
  calls[#calls + 1] = { method = method, path = path, body = body }
  local data, err = route(method, path, body)
  local function done() cb(err == nil, data, err) end
  if async then vim.schedule(done) else done() end
end
local function reset(r) calls, route, async = {}, r, false end
local function count(pat)
  local n = 0
  for _, c in ipairs(calls) do if c.path:find(pat) then n = n + 1 end end
  return n
end

local api = require("plugins.utils.devops.jira.api")
local detail = require("plugins.utils.devops.ui.detail")

-- ── api.list_sprints: paging past the 50-per-page cap ──────────────────────
local function sprints_route(per_board)
  return function(_, path)
    if path:find("/board%?projectKeyOrId=") then
      return { values = {
        { id = 174, location = { projectKey = "DEVOPS" } },
        { id = 1369, location = { projectKey = "DEVOPS" } },
        { id = 1631, location = { projectKey = "SRE" } },
      } }
    end
    local board, at = path:match("/board/(%d+)/sprint%?.-startAt=(%d+)")
    if board then
      local all, page = per_board[tonumber(board)] or {}, {}
      for i = tonumber(at) + 1, math.min(#all, tonumber(at) + 50) do page[#page + 1] = all[i] end
      return { values = page, isLast = tonumber(at) + 50 >= #all }
    end
    return nil, "unexpected " .. path
  end
end
local function mk(n, origin, prefix)
  local t = {}
  for i = 1, n do t[i] = { id = origin * 1000 + i, name = prefix .. " " .. i, originBoardId = origin, state = "closed" } end
  return t
end

local big = mk(120, 174, "DevOps")
vim.list_extend(big, mk(30, 9, "PROG")) -- another team's sprints leaking onto the board
reset(sprints_route({ [174] = big }))
local got
api.list_sprints(174, function(okk, s) got = okk and s end)
eq(got and #got, 150, "list_sprints: returns every page (150 > 50 cap)")

-- ── api.project_sprints: own-board filter, cache, coalescing ───────────────
api.clear_sprint_cache()
reset(sprints_route({ [174] = big, [1369] = mk(5, 1369, "DevOps 26") }))
api.project_sprints("DEVOPS", 1369, nil, function(okk, s) got = okk and s end)
eq(got and #got, 125, "project_sprints: keeps sprints from the project's boards only")
local leaked = false
for _, s in ipairs(got or {}) do if s.name:find("^PROG") then leaked = true end end
ok(not leaked, "project_sprints: other teams' sprints dropped")
eq(count("/board/1631/"), 0, "project_sprints: other projects' boards not queried")

local before = #calls
api.project_sprints("DEVOPS", 1369, nil, function(okk, s) got = okk and s end)
eq(#calls, before, "project_sprints: second call served from cache")
got[1].name = "mutated"
api.project_sprints("DEVOPS", 1369, nil, function(_, s) got = s end)
ok(got[1].name ~= "mutated", "project_sprints: cache hands out copies")

api.clear_sprint_cache()
before = #calls
api.project_sprints("DEVOPS", 1369, nil, function() end)
ok(#calls > before, "clear_sprint_cache: next call refetches")

api.clear_sprint_cache()
reset(sprints_route({ [1369] = mk(3, 1369, "DevOps 26") }))
async = true
local results = {}
for i = 1, 3 do
  api.project_sprints("DEVOPS", 1369, "active,future", function(okk, s) results[i] = okk and #s end)
end
vim.wait(1000, function() return #results == 3 end)
eq(results, { 3, 3, 3 }, "project_sprints: concurrent callers all answered")
eq(count("projectKeyOrId"), 1, "project_sprints: concurrent callers share one fetch")

-- ── api.children: token paging ─────────────────────────────────────────────
reset(function(_, path, body)
  if path:find("search/jql") then
    if not body.nextPageToken then
      return { issues = { { key = "A-1" }, { key = "A-2" } }, nextPageToken = "t2" }
    end
    return { issues = { { key = "A-3" } } }
  end
end)
api.children("A-0", function(okk, kids) got = okk and kids end)
eq(got and #got, 3, "children: follows nextPageToken")
ok(calls[1].body.jql:find('parent = "A%-0"'), "children: queries by parent")

-- ── detail: issue card with parent link + child issues ─────────────────────
local function issue(key, cat, assignee, typ)
  return { key = key, fields = {
    summary = "summary " .. key,
    issuetype = { name = typ or "Story" },
    status = { name = cat, statusCategory = { key = cat } },
    assignee = assignee or vim.NIL, -- JSON null decodes to vim.NIL
  } }
end
local ann = { accountId = "u1", displayName = "Ann" }
local bob = { accountId = "u2", displayName = "Bob" }
local epic = issue("E-1", "indeterminate", ann, "Epic")
epic.id = "1"
local kids = {
  issue("E-2", "done", ann), issue("E-3", "indeterminate", bob),
  issue("E-4", "new"), issue("E-5", "new", bob),
}

local function text(b) return table.concat(b.lines(), "\n") end
local function child_rows(b)
  local keys = {}
  for l = 1, #b.lines() do -- tags: line → data
    local t = b.tags()[l]
    if t and t.kind == "jira_link" and not t.parent then keys[#keys + 1] = t.key end
  end
  return keys
end

local okb, b = pcall(detail._build_issue, epic, nil, nil, 120, nil)
ok(okb, "build_issue: epic renders while children load")
ok(okb and text(b):find("loading…"), "build_issue: children panel shows loading")

okb, b = pcall(detail._build_issue, epic, nil, nil, 120, kids)
ok(okb, "build_issue: null assignees don't crash (vim.NIL)")
eq(okb and child_rows(b), { "E-2", "E-3", "E-4", "E-5" }, "build_issue: one openable row per child")
ok(okb and text(b):find("25%% done"), "build_issue: progress counts done children")
ok(okb and text(b):find("Unassigned"), "build_issue: unassigned child labelled")

local story = issue("S-1", "new", bob)
story.fields.parent = { key = "E-1", fields = { summary = "the epic", issuetype = { name = "Epic" } } }
okb, b = pcall(detail._build_issue, story, nil, nil, 120, nil)
local parent_tag
for _, t in pairs(okb and b.tags() or {}) do if t.parent then parent_tag = t end end
eq(parent_tag and { parent_tag.key, parent_tag.epic }, { "E-1", true }, "build_issue: parent row links to the epic")
ok(okb and not text(b):find("Child issues"), "build_issue: stories have no children panel")

-- ── detail.pick_children_filter ────────────────────────────────────────────
local function pick(label_pat)
  local orig = vim.ui.select
  local offered = {}
  vim.ui.select = function(items, opts, cb)
    local chosen
    for _, it in ipairs(items) do
      local l = opts.format_item(it)
      offered[#offered + 1] = l
      if not chosen and l:find(label_pat) then chosen = it end
    end
    cb(chosen)
  end
  local rerendered = false
  detail.pick_children_filter("E-1", kids, function() rerendered = true end)
  vim.ui.select = orig
  return offered, rerendered
end

local offered, rer = pick("^Not done")
ok(rer, "children filter: re-renders after picking")
ok(vim.tbl_contains(offered, "👤 Ann  (1)") and vim.tbl_contains(offered, "👤 Bob  (2)"),
  "children filter: offers only the children's assignees, with counts")
ok(vim.tbl_contains(offered, "👤 Unassigned  (1)"), "children filter: offers Unassigned")
b = detail._build_issue(epic, nil, nil, 120, kids)
eq(child_rows(b), { "E-3", "E-4", "E-5" }, "children filter: Not done hides Done")
ok(text(b):find("25%% done"), "children filter: progress bar still covers all children")
ok(text(b):find("F filter: Not done"), "children filter: active filter shown in header")

pick("^👤 Bob")
eq(child_rows(detail._build_issue(epic, nil, nil, 120, kids)), { "E-3", "E-5" }, "children filter: by assignee")
pick("^👤 Unassigned")
eq(child_rows(detail._build_issue(epic, nil, nil, 120, kids)), { "E-4" }, "children filter: unassigned")
pick("^● All")
eq(#child_rows(detail._build_issue(epic, nil, nil, 120, kids)), 4, "children filter: All clears it")

-- ── detail tabs, chips, status pill ────────────────────────────────────────
local config = require("plugins.utils.devops.config")
local cmts = { { id = "c1", author = { displayName = "Zed" }, created = "2026-01-01T00:00:00Z",
  body = { type = "doc", content = { { type = "paragraph", content = { { type = "text", text = "hello there" } } } } } } }
local prs = { { id = "#7", name = "fix it", status = "OPEN" } }
story.fields.labels = { "infra", "urgent" }
story.fields.components = { { name = "API" } }
story.fields.description = { type = "doc", content = { { type = "paragraph", content = { { type = "text", text = "the desc" } } } } }

b = detail._build_issue(story, prs, cmts, 120, nil, "overview")
ok(text(b):find(" Overview ") and text(b):find(" Comments 1 ") and text(b):find(" Pull requests 1 "),
  "tabs: tab bar lists Overview / Comments n / Pull requests n")
ok(text(b):find("the desc") and not text(b):find("hello there") and not text(b):find("fix it"),
  "tabs: Overview shows the description only")
ok(text(b):find(" infra ") and text(b):find(" API "), "chips: labels and components rendered as chips")
ok(b.lines()[1]:find(" new ") ~= nil, "header: status pill after the key")
local cr
b, cr = detail._build_issue(story, prs, cmts, 120, nil, "comments")
ok(text(b):find("hello there") and not text(b):find("the desc"), "tabs: Comments tab shows comments only")
ok(next(cr) ~= nil, "tabs: comment rows tracked on the Comments tab (r / e work)")
b = detail._build_issue(story, prs, cmts, 120, nil, "prs")
ok(text(b):find("fix it") and not text(b):find("hello there"), "tabs: Pull requests tab shows linked PRs")
detail.set_tab("S-1", "comments")
ok(text(detail._build_issue(story, prs, cmts, 120, nil)):find("hello there"), "tabs: set_tab selects the remembered tab")
detail.set_tab("S-1", nil)

config.options.ui.detail_tabs = false
b = detail._build_issue(story, prs, cmts, 120, nil)
ok(not text(b):find(" Overview ") and text(b):find("the desc") and text(b):find("hello there") and text(b):find("fix it"),
  "tabs: detail_tabs=false renders everything in one scroll")
config.options.ui.detail_tabs = true

-- ── theme ──────────────────────────────────────────────────────────────────
local theme = require("plugins.utils.devops.ui.theme")
local res_auto = theme.resolve("auto")
local res_dev = theme.resolve("devops")
eq(vim.tbl_count(res_auto), vim.tbl_count(res_dev), "theme: auto palette covers every group")
eq(res_auto.DevOpsOk.link, "DiagnosticOk", "theme: auto links to colorscheme groups")
ok(res_auto.DevOpsPillDone.bg ~= nil, "theme: auto pills derive a background")
config.options.ui.highlights = { DevOpsId = { fg = "#123456" } }
theme.apply()
eq(vim.api.nvim_get_hl(0, { name = "DevOpsId" }).fg, 0x123456, "theme: ui.highlights overrides win")
config.options.ui.highlights = {}

-- ── PR Files tab: ↵ opens the diff on that file ────────────────────────────
local ghapi = require("plugins.utils.devops.github.api")
local dv = require("plugins.utils.devops.ui.diff_viewer")
local pr = { number = 9, title = "t", state = "OPEN", url = "u", repository = { nameWithOwner = "o/r" },
  files = { { path = "a.lua", additions = 1, deletions = 0 }, { path = "dir/b.lua", additions = 2, deletions = 1 } } }
b = detail._build_pr(pr, 120, "files")
local frow
for l, t in pairs(b.tags()) do if t.kind == "pr_file" and t.path == "dir/b.lua" then frow = l end end
ok(frow and b.lines()[frow]:find("dir/b.lua"), "files: rows tagged with their path")
local buf = vim.api.nvim_create_buf(false, true)
detail.write_to_buf(buf, b)
local orig_diff, orig_open = ghapi.pr_diff, dv.open
local opened
ghapi.pr_diff = function(_, _, cb)
  cb(true, "diff --git a/a.lua b/a.lua\n--- a/a.lua\n+++ b/a.lua\n@@ -1 +1 @@\n-x\n+y\n"
    .. "diff --git a/dir/b.lua b/dir/b.lua\n--- a/dir/b.lua\n+++ b/dir/b.lua\n@@ -1 +1 @@\n-x\n+y\n")
end
dv.open = function(_, title, o) opened = { title, o.focus_file, o.pr.repo } end
detail.open_pr_file(detail.file_at(buf, frow))
ghapi.pr_diff, dv.open = orig_diff, orig_open
eq(opened, { "Diff #9", 2, "o/r" }, "files: ↵ opens the diff focused on that file")

-- ── diff viewer: one file per page ─────────────────────────────────────────
do
  local function file(p, n)
    local t = { "diff --git a/" .. p .. " b/" .. p, "--- a/" .. p, "+++ b/" .. p, "@@ -1," .. n .. " +1," .. n .. " @@" }
    for i = 1, n do t[#t + 1] = " line " .. p .. " " .. i end
    return table.concat(t, "\n")
  end
  local diff = file("a.lua", 5) .. "\n" .. file("b.lua", 60) .. "\n" .. file("c.lua", 4) .. "\n"
  local dvw = require("plugins.utils.devops.ui.diff_viewer")
  vim.o.scrolloff = 15
  dvw.open(diff, "Diff", { focus_file = 3 })
  local w
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local t = vim.inspect(vim.api.nvim_win_get_config(win).title or "")
    if t:find("· old") then w = win end
  end
  local function view()
    return vim.api.nvim_win_call(w, function()
      return { top = vim.fn.getline(vim.fn.line("w0")), above = vim.fn.foldclosed(vim.fn.line("w0")) ~= -1,
        cur = vim.fn.getline(".") }
    end)
  end
  local v = view()
  ok(not v.above and v.top:find("^─ ─") and v.cur:find("c%.lua"), "diff pages: last file opens at its rules, no previous file")
  vim.api.nvim_set_current_win(w)
  vim.api.nvim_feedkeys("[f", "x", false)
  v = view()
  ok(not v.above and v.cur:find("b%.lua"), "diff pages: [f shows the previous file at the top")
  vim.api.nvim_feedkeys("G", "x", false)
  local clock, real_now = 1e6, dvw._now
  dvw._now = function() return clock end
  local function bump(dt)
    clock = clock + dt
    vim.api.nvim_feedkeys("j", "x", false)
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = vim.api.nvim_get_current_buf() })
  end
  local function marker()
    local t = ""
    local nsp = vim.api.nvim_get_namespaces().DevOpsDiffPage
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(vim.api.nvim_win_get_buf(w), nsp, 0, -1, { details = true })) do
      for _, vl in ipairs(m[4].virt_lines or {}) do
        for _, c in ipairs(vl) do t = t .. c[1] end
      end
    end
    return t
  end
  bump(0)
  ok(view().cur:find("line b%.lua 60") and marker():find("END") and marker():find("▱▱"),
    "diff pages: hitting the end is a stop (banner, empty meter)")
  for _ = 1, 3 do bump(30) end
  ok(view().cur:find("line b%.lua 60") and marker():find("▱▱"), "diff pages: a momentum burst after the stop does not count")
  bump(400)
  ok(view().cur:find("line b%.lua 60") and marker():find("▰▱"), "diff pages: the 1st separate scroll fills the meter")
  bump(400)
  ok(view().cur:find("c%.lua"), "diff pages: the 2nd separate scroll flips to the next file")
  vim.api.nvim_feedkeys("[f", "x", false)
  vim.api.nvim_feedkeys("G", "x", false)
  clock = clock + 2000
  bump(0)
  bump(150)
  bump(150)
  ok(view().cur:find("c%.lua"), "diff pages: a steady wheel flips after 3 scrolls (stop + 2)")
  local rows = 0
  local nsp = vim.api.nvim_get_namespaces().DevOpsDiffPage
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(vim.api.nvim_win_get_buf(w), nsp, 0, -1, { details = true })) do
    if not m[4].virt_lines_above then rows = #(m[4].virt_lines or {}) end
  end
  local th = vim.api.nvim_win_text_height(w, {}).all
  ok(rows > 2 and th >= vim.api.nvim_win_get_height(w), "diff pages: a short file's end banner is pinned to the bottom row")
  dvw._now = real_now
  vim.api.nvim_feedkeys("q", "x", false)
end

-- ── diff viewer: banner on long pages, titles, placeholders, unified ───────
do
  local fake_eof = { opts = { disabled_filetypes = {} } }
  package.loaded["scrollEOF"] = fake_eof
  local function mod(p, n)
    local t = { "diff --git a/" .. p .. " b/" .. p, "--- a/" .. p, "+++ b/" .. p, "@@ -1," .. n .. " +1," .. n .. " @@" }
    for i = 1, n do t[#t + 1] = " line " .. i end
    return table.concat(t, "\n")
  end
  local function add(p, n)
    local t = { "diff --git a/" .. p .. " b/" .. p, "new file mode 100644", "--- /dev/null", "+++ b/" .. p, "@@ -0,0 +1," .. n .. " @@" }
    for i = 1, n do t[#t + 1] = "+added " .. i end
    return table.concat(t, "\n")
  end
  local dvw = require("plugins.utils.devops.ui.diff_viewer")
  dvw.open(mod("a.lua", 5) .. "\n" .. add("docs/very/deep/nested/path/release.md", 200) .. "\n", "Diff", { focus_file = 2 })
  local L, R
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local t = vim.inspect(vim.api.nvim_win_get_config(win).title or "")
    if t:find("· old") then L = win elseif t:find("· new") then R = win end
  end
  ok(fake_eof.opts.disabled_filetypes.devops_diff and vim.bo[vim.api.nvim_win_get_buf(L)].filetype == "devops_diff",
    "diff: buffers are exempted from scrollEOF")
  ok(vim.wo[L].scrolloffpad == 0, "diff: scrolloffpad is 0 in diff windows")
  local title = vim.api.nvim_win_get_config(R).title
  local ttext = type(title) == "table" and (title[1][1] .. title[2][1]) or tostring(title)
  ok(ttext:find("%.md · new") and ttext:find("…") and not ttext:find("──"),
    "diff: pane title is the file path (trimmed from the left) · side")
  local ph = vim.api.nvim_buf_get_extmarks(vim.api.nvim_win_get_buf(L), vim.api.nvim_get_namespaces().DevOpsDiffPlaceholder, 0, -1, { details = true })
  ok(#ph == 1 and ph[1][4].virt_text[1][1]:find("new file"), "diff: the old pane of a new file shows a placeholder")
  -- the end banner (last virtual row under the page) fits inside the window
  local function banner_visible(win, pat)
    local buf = vim.api.nvim_win_get_buf(win)
    local nsp = vim.api.nvim_get_namespaces().DevOpsDiffPage
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, nsp, 0, -1, { details = true })) do
      local d = m[4]
      if d.virt_lines and not d.virt_lines_above then
        local txt = ""
        for _, c in ipairs(d.virt_lines[#d.virt_lines]) do txt = txt .. c[1] end
        local w0 = vim.api.nvim_win_call(win, function() return vim.fn.line("w0") end)
        local rows = vim.api.nvim_win_text_height(win, { start_row = w0 - 1, end_row = m[2] }).all + #d.virt_lines
        return txt:find(pat) ~= nil and rows <= vim.api.nvim_win_get_height(win)
      end
    end
    return false
  end
  vim.api.nvim_set_current_win(R)
  vim.api.nvim_feedkeys("G", "x", false)
  ok(banner_visible(R, "END OF DIFF"), "diff: the end banner is on screen at the end of a long file")
  vim.api.nvim_feedkeys("\t", "x", false) -- unified
  local U
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.inspect(vim.api.nvim_win_get_config(win).title or ""):find("· unified") then U = win end
  end
  ok(U ~= nil, "diff unified: title shows the file · unified")
  if U then
    vim.api.nvim_set_current_win(U)
    vim.api.nvim_feedkeys("G", "x", false)
    ok(banner_visible(U, "END OF DIFF"), "diff unified: end banner on screen at the end of a long file")
    vim.api.nvim_feedkeys("[f", "x", false)
    ok(banner_visible(U, "END"), "diff unified: short file shows its end banner")
    vim.api.nvim_feedkeys("q", "x", false)
  end
  package.loaded["scrollEOF"] = nil
end

-- ── api.epics / api.backlog: follow nextPageToken ──────────────────────────
do
  local function paged(_, path, body)
    if not path:find("/search/jql") then return nil, "unexpected " .. path end
    if body.nextPageToken == "p2" then return { issues = { { key = "E-3" } } } end
    return { issues = { { key = "E-1" }, { key = "E-2" } }, nextPageToken = "p2" }
  end
  reset(paged)
  local e, b
  api.epics("DEVOPS", nil, function(okk, xs) e = okk and xs end)
  api.backlog("DEVOPS", nil, function(okk, xs) b = okk and xs end)
  eq(e and #e, 3, "epics: follows nextPageToken")
  eq(b and #b, 3, "backlog fallback: follows nextPageToken")
end

-- ── health: gh token scopes ────────────────────────────────────────────────
do
  local health = require("plugins.utils.devops.health")
  local sc = health.parse_gh_scopes("  - Token: ghp_x\n  - Token scopes: 'admin:org', 'gist', 'repo'\n")
  ok(sc and sc.repo and sc["admin:org"], "health: parses gh token scopes")
  eq(#health.missing_gh_scopes(sc), 0, "health: admin:org covers read:org, repo covers notifications")
  local m = health.missing_gh_scopes(health.parse_gh_scopes("Token scopes: 'gist'"))
  eq(#m, 3, "health: reports every missing scope")
  eq(health.parse_gh_scopes("Logged in (fine-grained)"), nil, "health: no scopes line → not checked")
end

-- ── jira.branch: names, start transition, git checkout ─────────────────────
do
  local br = require("plugins.utils.devops.jira.branch")
  eq(br.slug("Fix: Login page 500s on SSO!"), "fix-login-page-500s-on-sso", "branch: slug")
  eq(#br.slug(string.rep("word ", 30)) <= 40, true, "branch: slug capped at 40 chars")
  eq(br.name("DEVOPS-12", "Add the thing"), "feature/DEVOPS-12-add-the-thing", "branch: default format")
  local cfg = require("plugins.utils.devops.config").options.jira
  cfg.branch_format = "{type}/{key}"
  eq(br.name("OPS-1", "x", "Bug"), "fix/OPS-1", "branch: {type} is fix for bugs")
  cfg.branch_format = nil
  local trs = {
    { id = "1", name = "Start", to = { name = "Doing", statusCategory = { key = "indeterminate" } } },
    { id = "2", name = "Go", to = { name = "In Progress", statusCategory = { key = "indeterminate" } } },
    { id = "3", name = "Done", to = { name = "Done", statusCategory = { key = "done" } } },
  }
  eq(br.pick_start(trs).id, "2", "branch: prefers the In Progress transition")
  eq(br.pick_start({ trs[1], trs[3] }).id, "1", "branch: falls back to the in-progress category")
  eq(br.pick_start({ trs[3] }), nil, "branch: no start transition")
  -- macOS: /usr/bin/git may be blocked by an unaccepted Xcode licence
  local clt = "/Library/Developer/CommandLineTools/usr/bin"
  if vim.fn.executable(clt .. "/git") == 1 then vim.env.PATH = clt .. ":" .. vim.env.PATH end
  local repo = vim.fn.tempname()
  vim.fn.mkdir(repo, "p")
  vim.fn.system({ "git", "-C", repo, "init", "-q" })
  vim.fn.system({ "git", "-C", repo, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "i" })
  local r1, r2
  br.checkout("feature/X-1-a", repo, function(o, how) r1 = { o, how } end)
  vim.wait(3000, function() return r1 ~= nil end)
  vim.fn.system({ "git", "-C", repo, "checkout", "-q", "-" })
  br.checkout("feature/X-1-a", repo, function(o, how) r2 = { o, how } end)
  vim.wait(3000, function() return r2 ~= nil end)
  eq(r1, { true, "created" }, "branch: creates a new branch")
  eq(r2, { true, "switched" }, "branch: switches to an existing branch")
  eq(vim.trim(vim.fn.system({ "git", "-C", repo, "branch", "--show-current" })), "feature/X-1-a", "branch: checked out")
  local r3
  br.checkout("x", vim.fn.tempname(), function(o) r3 = { o } end)
  vim.wait(3000, function() return r3 ~= nil end)
  eq(r3, { false }, "branch: outside a repo fails")
  vim.fn.delete(repo, "rf")
end

-- ── '+' create: project → type → epic → sprint → summary from branch ───────
do
  local br = require("plugins.utils.devops.jira.branch")
  eq(br.summary_from_branch("feature/OPS-12-add-sso_login"), "Add sso login", "create: summary from branch")
  eq(br.summary_from_branch("main"), nil, "create: no summary from main")
  local created, moved
  reset(function(method, path, body)
    if path:find("/project/search") then return { values = { { key = "AAA", name = "A" }, { key = "DEVOPS", name = "D" } } } end
    if path:find("/issuetypes") then return { issueTypes = { { name = "Story" }, { name = "Sub-task", subtask = true } } } end
    if path:find("/search/jql") then return { issues = { { key = "DEVOPS-1", fields = { summary = "Epic one" } } } } end
    if path:find("/board%?projectKeyOrId") then return { values = { { id = 7, location = { projectKey = "DEVOPS" } } } } end
    if path:find("/board/7/sprint") then return { values = { { id = 70, name = "S1", state = "active", originBoardId = 7 } }, isLast = true } end
    if method == "POST" and path == "/rest/api/3/issue" then created = body.fields; return { key = "DEVOPS-99" } end
    if path:find("/sprint/70/issue") then moved = body.issues; return {} end
    return nil, "unexpected " .. path
  end)
  api.clear_sprint_cache()
  local ui_select, ui_input = vim.ui.select, vim.ui.input
  local inp = require("plugins.utils.devops.ui.input")
  local inp_open = inp.open
  local prompts = {}
  vim.ui.select = function(items, o, cb)
    prompts[#prompts + 1] = o.prompt
    local pick = ({ ["Project:"] = 2, ["Issue type:"] = 1, ["Epic:"] = 2, ["Sprint:"] = 2 })[o.prompt]
    cb(items[pick])
  end
  vim.ui.input = function(o, cb) cb(o.default ~= "" and o.default or "Typed summary") end
  inp.open = function(_, _, cb) cb("Body") end
  require("plugins.utils.devops.ui.dashboard")._actions.jira_create()
  vim.wait(3000, function() return moved ~= nil end)
  vim.ui.select, vim.ui.input, inp.open = ui_select, ui_input, inp_open
  eq(prompts, { "Project:", "Issue type:", "Epic:", "Sprint:" }, "create: asks project, type, epic, sprint")
  ok(created and created.project.key == "DEVOPS" and created.parent and created.parent.key == "DEVOPS-1"
    and created.summary ~= "" and created.description, "create: fields include the epic parent and description")
  eq(moved, { "DEVOPS-99" }, "create: new issue moved into the picked sprint")
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then pcall(vim.api.nvim_win_close, w, true) end
  end
end

-- ── CI job logs ─────────────────────────────────────────────────────────────
do
  local jl = require("plugins.utils.devops.ui.job_log")
  local repo, run, job = jl.parse_url("https://github.com/o/r/actions/runs/12/job/34")
  eq({ repo, run, job }, { "o/r", "12", "34" }, "job log: parses an Actions job URL")
  eq({ jl.parse_url("https://ci.example.com/build/1") }, {}, "job log: external CI is not an Actions job")
  local text = table.concat({
    "build\tSet up job\t2024-05-01T10:00:00.1234567Z Starting",
    "build\tRun tests\t2024-05-01T10:00:01.0000000Z \27[31mFAIL\27[0m spec",
    "build\tRun tests\t2024-05-01T10:00:02.0000000Z ##[error]Process completed with exit code 1.",
  }, "\n")
  local log = jl.parse(text)
  eq(vim.tbl_map(function(st) return st.name end, log.steps), { "Set up job", "Run tests" }, "job log: steps from gh step names")
  eq(log.steps[2].lines[1].text, "FAIL spec", "job log: strips timestamps/ANSI")
  eq({ log.steps[2].errors, log.errors }, { 2, 2 }, "job log: counts error lines")
  eq(log.steps[2].secs, 1.0, "job log: step duration from timestamps")
  -- Newer gh: every line is "UNKNOWN STEP"; steps come from ##[group]Run markers.
  local U = function(ts, m) return "j\tUNKNOWN STEP\t2024-05-01T10:00:" .. ts .. ".0000000Z " .. m end
  local log2 = jl.parse(table.concat({
    U("00", "Current runner version"), U("00", "##[group]Runner Image"), U("00", "img"), U("00", "##[endgroup]"),
    U("01", "##[group]Run make"), U("01", "^[[36;1mmake^[[0m"), U("01", "shell: bash"), U("01", "##[endgroup]"),
    U("02", "[command]/usr/bin/make all"), U("03", "/home/runner/work/r/r/src/a.c:3:1: error: boom"), U("04", "##[error]Process completed with exit code 2."),
    U("05", "Post job cleanup."), U("05", "Post job cleanup."), U("05", "x"),
    U("06", "Cleaning up orphan processes"), U("06", "##[warning]Node 20 is deprecated"),
  }, "\n"))
  eq(vim.tbl_map(function(st) return st.name end, log2.steps), { "Set up job", "Run make", "Post job cleanup", "Complete job" },
    "job log: steps recovered from runner markers")
  local mk = log2.steps[2]
  eq(vim.tbl_map(function(l) return l.kind end, mk.lines), { "group", "script", "config", "cmd", "error", "error" },
    "job log: line kinds (details/config/cmd/compiler error/##[error])")
  eq(mk.lines[2].text, "make", "job log: literal ^[[..m codes from gh stripped")
  eq(mk.lines[6].text, "Process completed with exit code 2.", "job log: ##[error] marker stripped")
  eq(log2.steps[1].groups[1].name, "Runner Image", "job log: nested group recorded")
  eq({ log2.errors, log2.warnings }, { 2, 1 }, "job log: totals")
  local L = jl.layout(log2)
  ok(L.lines[1]:find("✗ 1 failed step") and L.lines[1]:find("⚠ 1 warning") and L.lines[1]:find("4 steps"), "job log: summary line")
  eq(#L.headers, 4, "job log: one header per step")
  ok(L.lines[L.headers[2]]:find("✗  Run make"), "job log: failed step header")
  eq(L.lines[L.first_err], "./src/a.c:3:1: error: boom", "job log: first error is the compiler error (checkout path → ./)")
  local open_steps = vim.tbl_map(function(f) return f.from end, vim.tbl_filter(function(f) return f.step and f.open end, L.folds))
  eq(open_steps, { L.headers[2] }, "job log: only the failed step starts open")
  local gha = require("plugins.utils.devops.github.api")
  local orig = gha.job_log
  local calls_l = {}
  gha.job_log = function(r, j, failed, cb) calls_l[#calls_l + 1] = { r, j, failed }; cb(true, failed and "" or text, "") end
  jl.open({ name = "build", conclusion = "FAILURE", detailsUrl = "https://github.com/o/r/actions/runs/12/job/34" })
  gha.job_log = orig
  eq(calls_l, { { "o/r", "34", true }, { "o/r", "34", false } }, "job log: falls back to the full log when --log-failed is empty")
  local w = vim.api.nvim_get_current_win()
  local row = vim.api.nvim_win_get_cursor(w)[1]
  ok(vim.api.nvim_win_get_config(w).relative ~= "" and vim.api.nvim_get_current_line() == "FAIL spec",
    "job log: float opens on the first error")
  ok(vim.fn.foldclosed(row) == -1 and vim.fn.foldclosed(3) ~= -1, "job log: failed step open, passing step folded")
  vim.api.nvim_feedkeys("]e", "x", false)
  eq(vim.api.nvim_get_current_line(), "Process completed with exit code 1.", "job log: ]e next error")
  vim.api.nvim_feedkeys("gg]s", "x", false)
  ok(vim.api.nvim_get_current_line():find("Set up job"), "job log: ]s jumps to a step header")
  local ft = vim.api.nvim_win_call(w, function() vim.v.foldstart = 3; return jl.foldtext() end)
  ok(type(ft) == "table" and ft[1][1] == "▸ ", "job log: closed step shows a ▸ header bar")
  ok(vim.api.nvim_win_get_config(w).zindex < 100, "job log: float sits just above the dashboard")
  local other = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true,
    { relative = "editor", width = 10, height = 2, row = 1, col = 1 })
  vim.wait(50, function() return not vim.api.nvim_win_is_valid(w) end)
  ok(not vim.api.nvim_win_is_valid(w), "job log: closes when focus moves to another window")
  vim.api.nvim_win_close(other, true)
end

-- ── background watch: review requests + badges ─────────────────────────────
do
  local watch = require("plugins.utils.devops.github.watch")
  local gha = require("plugins.utils.devops.github.api")
  local o_rr, o_nc, o_av, o_notify = gha.review_requests, gha.notifications_count, gha.available, vim.notify
  local reqs = { { number = 1, title = "A", repository = { nameWithOwner = "o/r" } } }
  gha.available = function() return true end
  gha.review_requests = function(cb) cb(true, vim.deepcopy(reqs)) end
  gha.notifications_count = function(cb) cb(4) end
  local notes, changes = {}, 0
  vim.notify = function(m) notes[#notes + 1] = m end
  watch.state.requests, watch.state.seen = nil, {}
  require("plugins.utils.devops.config").options.github.poll_interval = 0
  watch.start(function() changes = changes + 1 end)
  eq({ watch.total(), watch.unseen(), watch.state.notif }, { 1, 1, 4 }, "watch: first poll counts requests, all unseen")
  eq(#notes, 0, "watch: no popup for requests already pending at startup")
  watch.mark_seen()
  eq(watch.unseen(), 0, "watch: visiting Reviews marks them seen")
  reqs[2] = { number = 9, title = "Fix SSO", repository = { nameWithOwner = "o/x" } }
  watch.poll()
  eq({ watch.total(), watch.unseen() }, { 2, 1 }, "watch: a new request is unseen")
  ok(#notes == 1 and notes[1]:find("o/x#9") and notes[1]:find("Fix SSO"), "watch: notifies on a new review request")
  ok(changes > 0, "watch: repaints on change")
  watch.stop()
  gha.review_requests, gha.notifications_count, gha.available, vim.notify = o_rr, o_nc, o_av, o_notify
end

-- ── diff viewer: suggestions + review summary ──────────────────────────────
do
  local dvw = require("plugins.utils.devops.ui.diff_viewer")
  local lm = {
    [1] = { path = "a.lua", line = 10, new = true, text = "local x = 1" },
    [2] = { path = "a.lua", line = 5, kind = "del", new = false, text = "old" },
    [3] = { path = "a.lua", line = 11, new = true, text = "return x" },
    [5] = { path = "b.lua", line = 1, new = true, text = "b" },
  }
  local r = dvw.suggestion_range(lm, 3, 1)
  eq(r, { path = "a.lua", start_line = 10, line = 11, lines = { "local x = 1", "return x" } },
    "suggest: multi-line range on the new side (deleted lines skipped)")
  eq(dvw.suggestion_range(lm, 3, 3), { path = "a.lua", line = 11, lines = { "return x" } }, "suggest: single line")
  local none, why = dvw.suggestion_range(lm, 2, 2)
  ok(none == nil and why:find("new side"), "suggest: deleted-only selection is refused")
  local _, why2 = dvw.suggestion_range(lm, 1, 5)
  ok(why2 and why2:find("two files"), "suggest: cross-file selection is refused")
  eq(dvw.suggestion_body({ "a", "b" }), "```suggestion\na\nb\n```", "suggest: body template")
  local sm = dvw._review_summary({
    { path = "a.lua", line = 11, start_line = 10, body = "```suggestion\nx\n```" },
    { path = "b.lua", line = 3, body = "nit: rename\nmore" },
  })
  eq(sm.lines, { "  💬 a.lua:10-11  ✎ suggestion", "  💬 b.lua:3  nit: rename" }, "review: summary lists pending comments")
  -- payload carries the multi-line range
  local gha = require("plugins.utils.devops.github.api")
  local o_sys = vim.system
  local sent
  vim.system = function(cmd, opts, cb) sent = opts.stdin; cb({ code = 0, stdout = "", stderr = "" }); return {} end
  gha.pr_review("o/r", 1, "COMMENT", "", { { path = "a.lua", line = 11, start_line = 10, body = "s" } }, function() end)
  vim.system = o_sys
  local c = sent and vim.json.decode(sent).comments[1]
  ok(c and c.start_line == 10 and c.start_side == "RIGHT" and c.line == 11, "review: multi-line comment sends start_line")
end

-- ── diff viewer: 's' in visual mode opens a suggestion prefilled with the lines
do
  local dvw = require("plugins.utils.devops.ui.diff_viewer")
  local gha = require("plugins.utils.devops.github.api")
  local o_rc = gha.pr_review_comments
  gha.pr_review_comments = function(_, _, cb) cb(true, {}) end
  local inp = require("plugins.utils.devops.ui.input")
  local o_open = inp.open
  local got_title, got_text
  inp.open = function(title, text) got_title, got_text = title, text end
  local diff = table.concat({ "diff --git a/s.lua b/s.lua", "--- a/s.lua", "+++ b/s.lua", "@@ -1,2 +1,3 @@",
    " keep", "+one", "+two" }, "\n") .. "\n"
  dvw.open(diff, "Diff", { pr = { repo = "o/r", number = 5 }, focus_file = 1 })
  local R
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.inspect(vim.api.nvim_win_get_config(win).title or ""):find("· new") then R = win end
  end
  vim.api.nvim_set_current_win(R)
  local rows = {}
  for r = 1, vim.api.nvim_buf_line_count(0) do
    local l = vim.api.nvim_buf_get_lines(0, r - 1, r, false)[1]
    if l:find("one$") or l:find("two$") then rows[#rows + 1] = r end
  end
  vim.api.nvim_win_set_cursor(R, { rows[1], 0 })
  vim.api.nvim_feedkeys("Vjs", "x", false)
  inp.open, gha.pr_review_comments = o_open, o_rc
  eq(got_title, "Suggestion on s.lua:2-3", "suggest: title shows the line range")
  eq(got_text, "```suggestion\none\ntwo\n```", "suggest: input prefilled with the selected new lines")
  vim.api.nvim_feedkeys("q", "x", false)
end

-- ── diff viewer: / ? n N jump across files; j/k still stop at the edge ─────
do
  local dvw = require("plugins.utils.devops.ui.diff_viewer")
  local function f(p, word)
    return table.concat({ "diff --git a/" .. p .. " b/" .. p, "--- a/" .. p, "+++ b/" .. p, "@@ -1,1 +1,2 @@", " keep", "+" .. word }, "\n")
  end
  dvw.open(f("a.lua", "alpha") .. "\n" .. f("b.lua", "needle") .. "\n" .. f("c.lua", "gamma") .. "\n", "Diff", { focus_file = 2 })
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.inspect(vim.api.nvim_win_get_config(win).title or ""):find("· new") then vim.api.nvim_set_current_win(win) end
  end
  local function file() return vim.api.nvim_win_get_config(0).title[1][1]:match("%S+") end
  local function cm() vim.api.nvim_exec_autocmds("CursorMoved", {}) end
  vim.api.nvim_feedkeys("ggk", "x", false); cm()
  eq(file(), "b.lua", "search: k at the top still stops on the page")
  vim.api.nvim_feedkeys("Gj", "x", false); cm()
  eq(file(), "b.lua", "search: j at the bottom still stops on the page")
  vim.cmd("normal! /gamma\r"); cm()
  ok(file() == "c.lua" and vim.api.nvim_get_current_line():find("gamma"), "search: / jumps to the match in the next file")
  vim.cmd("normal! ?alpha\r"); cm()
  ok(file() == "a.lua" and vim.api.nvim_get_current_line():find("alpha"), "search: ? jumps back to an earlier file")
  vim.api.nvim_feedkeys("q", "x", false)
end

-- ── diff viewer: x marks viewed, ✓ in tree/title, ]f skips viewed files ─────
do
  local dvw = require("plugins.utils.devops.ui.diff_viewer")
  local gha = require("plugins.utils.devops.github.api")
  eq(dvw._next_file(1, 1, 3, function(i) return i == 2 end), 3, "viewed: next skips a viewed file")
  eq(dvw._next_file(1, 1, 3, function() return true end), 2, "viewed: all viewed → plain next")
  eq(dvw._next_file(1, -1, 3, function(i) return i == 3 end), 2, "viewed: prev skips and wraps")
  local o_rc, o_vf, o_set = gha.pr_review_comments, gha.pr_viewed_files, gha.set_file_viewed
  gha.pr_review_comments = function(_, _, cb) cb(true, {}) end
  gha.pr_viewed_files = function(_, _, cb) cb(true, { id = "PR_1", viewed = { ["b.lua"] = true } }) end
  local sets = {}
  gha.set_file_viewed = function(id, path, v, cb) sets[#sets + 1] = { id, path, v }; cb(true) end
  local function f(p)
    return table.concat({ "diff --git a/" .. p .. " b/" .. p, "--- a/" .. p, "+++ b/" .. p, "@@ -1,1 +1,2 @@", " keep", "+x" }, "\n")
  end
  local o_cols = vim.o.columns
  vim.o.columns = 160
  dvw.open(f("a.lua") .. "\n" .. f("b.lua") .. "\n" .. f("c.lua") .. "\n", "Diff", { pr = { repo = "o/r", number = 7 }, focus_file = 1 })
  local R, T
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local title = vim.inspect(vim.api.nvim_win_get_config(win).title or "")
    if title:find("· new") then R = win end
    if title:find("Files") or vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, 1, false)[1]:find("Changed files") then T = win end
  end
  local function file() return vim.api.nvim_win_get_config(R).title[1][1]:match("%S+") end
  vim.api.nvim_set_current_win(R)
  vim.api.nvim_feedkeys("]f", "x", false)
  eq(file(), "c.lua", "viewed: ]f skips b.lua (viewed on GitHub)")
  vim.api.nvim_feedkeys("[f", "x", false)
  eq(file(), "a.lua", "viewed: [f skips it going back too")
  vim.api.nvim_feedkeys("x", "x", false)
  ok(sets[1] and sets[1][1] == "PR_1" and sets[1][2] == "a.lua" and sets[1][3] == true, "viewed: x sends markFileAsViewed")
  eq(file(), "c.lua", "viewed: x moves on to the next unviewed file")
  local tree = T and table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(T), 0, -1, false), "\n") or ""
  ok(tree:find("✓ %S* ?a%.lua") and tree:find("✓ %S* ?b%.lua") and not tree:find("✓ %S* ?c%.lua"), "viewed: tree marks a.lua and b.lua")
  ok(tree:find("✓ 2"), "viewed: tree header counts viewed files")
  vim.api.nvim_set_current_win(R)
  ok(not vim.inspect(vim.api.nvim_win_get_config(R).title):find("✓"), "viewed: unviewed page title has no ✓")
  vim.api.nvim_feedkeys("[f", "x", false)
  eq(file(), "b.lua", "viewed: [f with every other file viewed moves to the plain neighbour")
  ok(vim.inspect(vim.api.nvim_win_get_config(R).title):find("✓"), "viewed: title shows ✓ on a viewed file")
  vim.api.nvim_feedkeys("x", "x", false)
  ok(sets[2] and sets[2][2] == "b.lua" and sets[2][3] == false, "viewed: x on a viewed file unmarks it")
  eq(file(), "b.lua", "viewed: unmarking stays on the page")
  gha.set_file_viewed = function(_, _, _, cb) cb(false, nil, "boom") end
  local o_notify = vim.notify
  vim.notify = function() end
  vim.api.nvim_feedkeys("x", "x", false)
  vim.notify = o_notify
  ok(not vim.inspect(vim.api.nvim_win_get_config(R).title):find("✓"), "viewed: failed mutation rolls back")
  gha.pr_review_comments, gha.pr_viewed_files, gha.set_file_viewed = o_rc, o_vf, o_set
  vim.api.nvim_feedkeys("q", "x", false)
  vim.o.columns = o_cols
end

-- ── checks: `gh pr view --json statusCheckRollup` returns a plain array ─────
do
  local d = require("plugins.utils.devops.ui.detail")
  local db = require("plugins.utils.devops.ui.dashboard")
  local roll = {
    { __typename = "CheckRun", name = "lint", status = "COMPLETED", conclusion = "SUCCESS" },
    { __typename = "CheckRun", name = "test", status = "COMPLETED", conclusion = "FAILURE" },
  }
  local out = d._build_pr({ number = 1, title = "t", state = "OPEN", statusCheckRollup = roll }, 100, "checks")
  local text = table.concat(type(out.lines) == "function" and out.lines() or out.lines, "\n")
  ok(text:find("Checks 2 ✗1"), "checks: tab counts array-shaped rollup")
  ok(text:find("lint") and text:find("test"), "checks: rows listed")
  eq(db._check_status(roll), "✗", "checks: list icon from array rollup (fail)")
  eq(db._check_status({ roll[1] }), "✓", "checks: list icon from array rollup (pass)")
  eq(db._check_status({ { name = "x", status = "IN_PROGRESS" } }), "⏳", "checks: list icon pending")
  eq(db._check_status({}), "", "checks: no checks → no icon")
end

-- ── own PR: approve / request changes are refused before calling GitHub ────
do
  local db = require("plugins.utils.devops.ui.dashboard")
  local dvw = require("plugins.utils.devops.ui.diff_viewer")
  local gha = require("plugins.utils.devops.github.api")
  local o_me, o_notify = gha.is_me, vim.notify
  gha.is_me = function(l) return l == "me" end
  local msg
  vim.notify = function(m) msg = m end
  ok(db._refuse_own({ author = { login = "me" } }, "approve") and msg:find("own PR"), "own PR: approve refused with a hint")
  ok(not db._refuse_own({ author = { login = "bob" } }, "approve"), "own PR: others' PRs allowed")
  ok(not db._refuse_own({}, "approve"), "own PR: unknown author falls through to GitHub")
  vim.notify = o_notify

  local o_rc, o_vf, o_sel = gha.pr_review_comments, gha.pr_viewed_files, vim.ui.select
  gha.pr_review_comments = function(_, _, cb) cb(true, {}) end
  local author = "me"
  gha.pr_viewed_files = function(_, _, cb) cb(true, { id = "P", author = author, viewed = {} }) end
  local seen
  vim.ui.select = function(items, opts) seen = { items = items, prompt = opts.prompt } end
  local diff = table.concat({ "diff --git a/o.lua b/o.lua", "--- a/o.lua", "+++ b/o.lua", "@@ -1,1 +1,2 @@", " k", "+x" }, "\n") .. "\n"
  local function submit_menu()
    dvw.open(diff, "Diff", { pr = { repo = "o/r", number = 11 } })
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.inspect(vim.api.nvim_win_get_config(win).title or ""):find("· new") then vim.api.nvim_set_current_win(win) end
    end
    seen = nil
    vim.api.nvim_feedkeys("S", "x", false)
    vim.api.nvim_feedkeys("q", "x", false)
    return seen
  end
  local m = submit_menu()
  ok(m and #m.items == 1 and m.items[1]:find("^Comment") and m.prompt:find("your PR"), "own PR: S offers comment only")
  author = "bob"
  dvw.open(diff, "Diff", { pr = { repo = "o/r", number = 12 } }); vim.api.nvim_feedkeys("q", "x", false)
  m = submit_menu()
  ok(m and #m.items == 3, "own PR: someone else's PR keeps approve / request changes")
  gha.is_me, gha.pr_review_comments, gha.pr_viewed_files, vim.ui.select = o_me, o_rc, o_vf, o_sel
end

-- ── outdated review comment: line = JSON null (vim.NIL) must not crash ────
do
  local d = require("plugins.utils.devops.ui.detail")
  local pr = { number = 1, title = "t", state = "OPEN", comments = {}, reviews = {},
    reviewComments = { { id = 1, path = "a.lua", line = vim.NIL, original_line = 7, position = vim.NIL,
      body = "old", user = { login = "bob" }, in_reply_to_id = vim.NIL } } }
  for _, tab in ipairs({ "comments", "overview" }) do
    local okb, out = pcall(d._build_pr, pr, 100, tab)
    ok(okb, "outdated comment: " .. tab .. " renders (" .. tostring(not okb and out or "") .. ")")
    if okb and tab == "comments" then
      local text = table.concat(type(out.lines) == "function" and out.lines() or out.lines, "\n")
      ok(text:find("L7"), "outdated comment: falls back to original_line")
    end
  end
end

-- ── CI log token colors ────────────────────────────────────────────────────
do
  local jl = require("plugins.utils.devops.ui.job_log")
  local function hl_of(text, kind, sub)
    local a = text:find(sub, 1, true) - 1
    local got
    for _, sp in ipairs(jl.tokens(text, kind)) do
      if sp[1] <= a and sp[2] >= a + #sub then got = sp[3] end
    end
    return got
  end
  local e = "src/a.zig:9:3: error: no member named 'x86_64' in $HOME"
  eq(hl_of(e, "error", "src/a.zig:9:3"), "DevOpsLogPath", "tokens: file:line:col path")
  eq(hl_of(e, "error", "error"), "DevOpsErr", "tokens: error word")
  eq(hl_of(e, "error", "'x86_64'"), "DevOpsLogStr", "tokens: quoted string")
  eq(hl_of(e, "error", "$HOME"), "DevOpsLogVar", "tokens: env var")
  eq(hl_of("arch x86_64", "text", "64"), nil, "tokens: no number inside identifiers")
  eq(hl_of("took 12.5s", "text", "12.5s"), "DevOpsLogNum", "tokens: durations")
  eq(hl_of("see https://x.io/a?b=1", "text", "https://x.io/a?b=1"), "DevOpsLogUrl", "tokens: url")
  eq(hl_of("if [ -f x ]; then echo hi; fi", "script", "then"), "DevOpsLogKeyword", "tokens: shell keyword")
  eq(hl_of("make # build it", "script", "# build it"), "DevOpsDim", "tokens: shell comment")
  eq(hl_of("  shell: /usr/bin/bash", "config", "  shell:"), "DevOpsLogKey", "tokens: config key")
  local log = jl.parse("j\tUNKNOWN STEP\t2024-05-01T10:00:00.0Z ##[group]Run x\n"
    .. "j\tUNKNOWN STEP\t2024-05-01T10:00:00.0Z ^[[36;1mecho hi^[[0m\n"
    .. "j\tUNKNOWN STEP\t2024-05-01T10:00:00.0Z shell: bash\n")
  eq(vim.tbl_map(function(l) return l.kind end, log.steps[1].lines), { "group", "script", "config" },
    "job log: cyan runner lines are the step script")
end

-- ── checks: dedupe re-runs, strip baked-in glyphs, group by workflow ───────
do
  local d = require("plugins.utils.devops.ui.detail")
  local db = require("plugins.utils.devops.ui.dashboard")
  local roll = {
    { name = "lint", workflowName = "CI", conclusion = "FAILURE", status = "COMPLETED", startedAt = "2024-01-01T00:00:00Z" },
    { name = "lint", workflowName = "CI", conclusion = "SUCCESS", status = "COMPLETED", startedAt = "2024-01-02T00:00:00Z" },
    { name = "✓ build / job", workflowName = "Tests", conclusion = "SUCCESS", status = "COMPLETED" },
    { context = "Wiz", state = "SUCCESS" },
  }
  eq(#d._check_contexts(roll), 3, "checks: re-runs collapse to one row")
  eq(d._check_contexts(roll)[1].conclusion, "SUCCESS", "checks: newest run wins")
  eq(d._check_name(roll[3]), "build / job", "checks: leading ✓ in the job name stripped")
  eq(db._check_status(roll), "✓", "checks: list icon ignores an old failed run")
  local out = d._build_pr({ number = 1, title = "t", state = "OPEN", statusCheckRollup = roll }, 100, "checks")
  local text = table.concat(out.lines(), "\n")
  ok(text:find("Checks 3") and text:find("\n  CI  1") and text:find("\n  Tests  1") and text:find("\n  Other checks  1"),
    "checks: grouped under workflow headers")
  ok(text:find("    ✓  build / job") and not text:find("✓  ✓"), "checks: no doubled glyph")
end

-- ── r on a non-comment row (check/file) is a no-op, not a crash ───────────
do
  local d = require("plugins.utils.devops.ui.detail")
  local roll = { { name = "lint", workflowName = "CI", conclusion = "SUCCESS", status = "COMPLETED" } }
  local out = d._build_pr({ number = 1, title = "t", state = "OPEN", statusCheckRollup = roll }, 100, "checks")
  local buf = vim.api.nvim_create_buf(false, true)
  d.write_to_buf(buf, out)
  vim.api.nvim_set_current_buf(buf)
  local row
  for i, l in ipairs(out.lines()) do if l:find("lint") then row = i end end
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  ok(d.check_at(buf, row) ~= nil, "reply: cursor is on a tagged check row")
  local okc, res = pcall(d._pr_reply, buf, "o/r", 1, function() end)
  ok(okc and res == false, "reply: r on a check row returns false instead of crashing")
end

-- ── ↵ on a Reviewers row jumps to that reviewer's comment(s) ──────────────
do
  local d = require("plugins.utils.devops.ui.detail")
  local pr = {
    number = 7, title = "t", state = "OPEN", repository = { nameWithOwner = "o/r" }, author = { login = "me" },
    reviews = { { author = { login = "bob" }, state = "COMMENTED", body = "", createdAt = "2026-01-02T00:00:00Z" } },
    reviewComments = { { id = 1, user = { login = "bob" }, path = "a/b.lua", line = 3, body = "nit", created_at = "2026-01-02T00:00:00Z" } },
    comments = { { author = { login = "ann" }, body = "hi", createdAt = "2026-01-01T00:00:00Z" },
      { author = { login = "ann" }, body = "again", createdAt = "2026-01-03T00:00:00Z" } },
    reviewRequests = { { login = "ann" } },
  }
  local function row_of(out, pat)
    for i, l in ipairs(out.lines()) do if l:find(pat) then return i end end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  local out = d._build_pr(pr, 100, "overview")
  d.write_to_buf(buf, out)
  local bob = d.reviewer_at(buf, row_of(out, "^  bob "))
  ok(bob and #bob.comments == 1, "reviewers: bob's row tagged with his 1 comment")
  ok(out.lines()[row_of(out, "^  bob ")]:find("1 comment"), "reviewers: comment count hint")
  eq(#(d.reviewer_at(buf, row_of(out, "^  ann ")) or {}).comments, 2, "reviewers: ann has 2 comments")

  local conv = d._build_pr(pr, 100, "comments")
  local function rerender() d.write_to_buf(buf, d._build_pr(pr, 100)) end
  d.set_tab("o/r#7", "overview")
  d.write_to_buf(buf, out)
  -- Register the rerender the way open_pr/load_pr do (via their keymap setup).
  d._set_rerender(buf, rerender)
  d.open_reviewer_comments(buf, bob)
  eq(vim.api.nvim_win_get_cursor(0)[1], row_of(conv, "@bob"), "reviewers: single comment → jumps directly")

  local orig, seen = vim.ui.select, nil
  vim.ui.select = function(items, _, cb) seen = items; cb(items[2]) end
  d.write_to_buf(buf, out)
  d.open_reviewer_comments(buf, d.reviewer_at(buf, row_of(out, "^  ann ")))
  vim.ui.select = orig
  ok(seen and #seen == 2, "reviewers: several comments → picker")
  ok(vim.api.nvim_get_current_line():find("ann commented"), "reviewers: picked comment is under the cursor")
  local second
  for i, l in ipairs(conv.lines()) do if l:find("ann commented") then second = i end end
  eq(vim.api.nvim_win_get_cursor(0)[1], second, "reviewers: picker jumps to the chosen (2nd) comment")

  -- Comments tab = people's words; Activity tab = bare reviews, bots, pushes.
  table.insert(pr.comments, { author = { login = "github-actions" }, body = "coverage 90%", createdAt = "2026-01-04T00:00:00Z" })
  pr.commits = { { oid = "abcdef1234", messageHeadline = "wip", committedDate = "2026-01-05T00:00:00Z", authors = { { login = "me" } } } }
  local ctext = table.concat(d._build_pr(pr, 100, "comments").lines(), "\n")
  local atext = table.concat(d._build_pr(pr, 100, "activity").lines(), "\n")
  ok(ctext:find(" Comments 3 ") and ctext:find(" Activity 3 "), "tabs: Comments and Activity counts")
  ok(ctext:find("ann commented") and ctext:find("Code review threads") and not ctext:find("coverage"),
    "comments tab: people's comments + inline threads, no bots")
  ok(atext:find("github%-actions") and atext:find("bob reviewed") and atext:find("pushed abcdef1")
    and not atext:find("ann commented"), "activity tab: bot comment, bare review and push only")

  -- Copilot's review is a real comment; a thread I answered last awaits the reviewer.
  local gha = require("plugins.utils.devops.github.api")
  local o_me = gha.current_user_login
  gha.current_user_login = function() return "me" end
  local cp = { number = 8, title = "t", state = "OPEN", comments = {},
    reviews = { { author = { login = "copilot-pull-request-reviewer" }, state = "COMMENTED", body = "Copilot reviewed 2 files" } },
    reviewComments = { { id = 5, user = { login = "Copilot", type = "Bot" }, path = "x.yml", line = 9, body = "unsafe quoting" },
      { id = 6, in_reply_to_id = 5, user = { login = "me" }, path = "x.yml", line = 9, body = "fixed" } } }
  local cl = d._build_pr(cp, 100, "comments").lines()
  gha.current_user_login = o_me
  local ctext2 = table.concat(cl, "\n")
  ok(ctext2:find("Copilot reviewed 2 files"), "comments tab: Copilot's review counts as a comment")
  local root_l, reply_l
  for _, l in ipairs(cl) do
    if l:find("@Copilot") then root_l = l end
    if l:find("↳.*@me") then reply_l = l end
  end
  ok(root_l and root_l:find("awaiting reply") and not reply_l:find("awaiting"),
    "inline thread: status only on the root (my reply last → awaiting reply)")
  cp.threadStates = { [5] = { resolved = true, outdated = true } }
  gha.current_user_login = function() return "me" end
  local rtext = table.concat(d._build_pr(cp, 100, "comments").lines(), "\n")
  gha.current_user_login = o_me
  ok(rtext:find("0 open, 1 resolved") and rtext:find("✓ x.yml:9  @Copilot · 1 reply · outdated")
    and not rtext:find("fixed") and not rtext:find("awaiting"), "inline thread: resolved one collapses to a line")
end


-- ── <leader>z zooms the log float in place (no extra window → no close) ──
do
  vim.g.mapleader = " "
  local jl = require("plugins.utils.devops.ui.job_log")
  local _, win = jl._show("Build", jl.parse("job\tUNKNOWN STEP\t2024-01-01T00:00:00Z hello\n"), "u")
  local w0 = vim.api.nvim_win_get_width(win)
  local m = vim.fn.maparg(" z", "n", false, true)
  eq(m.buffer, 1, "zoom: <leader>z is buffer-local")
  m.callback()
  ok(vim.api.nvim_win_is_valid(win), "zoom: float survives")
  eq(vim.api.nvim_win_get_width(win), vim.o.columns - 2, "zoom: full width")
  m.callback()
  eq(vim.api.nvim_win_get_width(win), w0, "zoom: back to normal size")
  vim.api.nvim_win_close(win, true)
end
-- ── CI: source refs, copy blocks, live view, re-run, readiness ──────────────
do
  local jl = require("plugins.utils.devops.ui.job_log")
  local p, l, c = jl.find_ref("./src/foo.c:12:3: error: boom")
  eq(p, "./src/foo.c", "ref: path"); eq(l, 12, "ref: line"); eq(c, 3, "ref: col")
  p, l = jl.find_ref('  File "app/main.py", line 7, in <module>')
  eq(p, "app/main.py", "ref: python path"); eq(l, 7, "ref: python line")
  local t = "a.lua:1 and b/c.ts:42:5"
  p, l = jl.find_ref(t, t:find("b/c") + 1)
  eq(p, "b/c.ts", "ref: the one under the cursor"); eq(l, 42, "ref: its line")
  eq(jl.find_ref("version 1.2.3 done"), nil, "ref: none")

  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. "/pkg/sub", "p")
  vim.fn.writefile({ "x" }, root .. "/pkg/sub/mod.lua")
  eq(jl.resolve("./pkg/sub/mod.lua", root), root .. "/pkg/sub/mod.lua", "resolve: relative")
  eq(jl.resolve("/opt/build/other/sub/mod.lua", root), root .. "/pkg/sub/mod.lua", "resolve: by path suffix")
  eq(jl.resolve("nope/missing.lua", root), nil, "resolve: missing")
  vim.fn.delete(root, "rf")

  local log = jl.parse(table.concat({
    "j\tUNKNOWN STEP\t2024-01-01T00:00:00Z ##[group]Run make",
    "j\tUNKNOWN STEP\t2024-01-01T00:00:00Z make",
    "j\tUNKNOWN STEP\t2024-01-01T00:00:00Z ##[endgroup]",
    "j\tUNKNOWN STEP\t2024-01-01T00:00:01Z src/a.c:3:1: error: bad",
    "j\tUNKNOWN STEP\t2024-01-01T00:00:01Z   3 | int x",
    "j\tUNKNOWN STEP\t2024-01-01T00:00:01Z     | ^",
    "j\tUNKNOWN STEP\t2024-01-01T00:00:02Z ##[error]Process completed with exit code 2.",
  }, "\n"))
  local L = jl.layout(log)
  local a, b = jl.error_block(L, L.errors[1])
  eq(L.raw[a], "src/a.c:3:1: error: bad", "copy: block starts at the error")
  eq(b - a, 2, "copy: block takes the context lines, stops at the next error")

  local lines = jl.live_layout({ status = "in_progress", started_at = "2024-01-01T00:00:00Z", steps = {
    { name = "Set up job", status = "completed", conclusion = "success" },
    { name = "Build", status = "in_progress" },
    { name = "Test", status = "queued" },
  } })
  ok(lines[1]:find("running") and lines[1]:find("step 2/3"), "live: header shows progress")
  ok(lines[3]:find("✓  Set up job") and lines[4]:find("⟳  Build") and lines[5]:find("·  Test"), "live: step icons")
  ok(jl._running({ status = "IN_PROGRESS" }) and jl._running({ state = "PENDING" }), "live: running checks detected")
  ok(not jl._running({ status = "COMPLETED", conclusion = "FAILURE" }), "live: completed isn't live")

  local gh = require("plugins.utils.devops.github.api")
  eq(table.concat(gh._rerun_args("o/r", 5, "failed"), " "), "gh run rerun 5 --failed --repo o/r", "rerun: failed")
  eq(table.concat(gh._rerun_args("o/r", 5, "job", 9), " "), "gh run rerun --job 9 --repo o/r", "rerun: one job")
  eq(table.concat(gh._rerun_args("o/r", 5, "all"), " "), "gh run rerun 5 --repo o/r", "rerun: all")
  local pr = gh.normalize_readiness({ reviewDecision = vim.NIL,
    commits = { nodes = { { commit = { statusCheckRollup = { state = "SUCCESS" } } } } } })
  eq(pr.statusCheckRollup.state, "SUCCESS", "readiness: rollup state lifted"); eq(pr.reviewDecision, nil, "readiness: null decision")

  local db = require("plugins.utils.devops.ui.dashboard")
  eq(db._readiness({ reviewDecision = "APPROVED", statusCheckRollup = { state = "SUCCESS" } }), "● ready", "badge: ready")
  eq(db._readiness({ reviewDecision = "APPROVED", statusCheckRollup = { state = "FAILURE" } }), "✔ approved · ✗ ci", "badge: red ci")
  eq(db._readiness({ mergeable = "CONFLICTING", reviewDecision = "APPROVED" }), "⚠ conflict", "badge: conflict first")
  eq(db._readiness({ reviewDecision = "CHANGES_REQUESTED" }), "± changes", "badge: changes")
  eq(db._readiness({ isDraft = true, reviewDecision = "APPROVED" }), nil, "badge: none on drafts")
  eq(db._run_icon({ status = "completed", conclusion = "failure" }), "✗", "runs: failed icon")
  eq(db._run_icon({ status = "in_progress" }), "⟳", "runs: running icon")
  eq(table.concat(require("plugins.utils.devops.ui.detail").issue_keys("feat/DEVOPS-12-x", "DEVOPS-12 and OPS-3"), ","),
    "DEVOPS-12,OPS-3", "jira: keys from branch + title, deduped")
end

-- ── cwd repo from .git/config (no git binary) ─────────────────────────────
do
  local db = require("plugins.utils.devops.ui.dashboard")
  eq(db._remote_owner_repo("git@github.com:o_x/r.y.git\n"), "o_x/r.y", "remote: ssh")
  eq(db._remote_owner_repo("https://github.com/o/r"), "o/r", "remote: https")
  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. "/.git", "p"); vim.fn.mkdir(root .. "/sub", "p")
  vim.fn.writefile({ "[core]", "\tbare = false", '[remote "upstream"]', "\turl = git@github.com:a/b.git",
    '[remote "origin"]', "\turl = https://github.com/me/proj.git", "\tfetch = +refs/heads/*" }, root .. "/.git/config")
  eq(db._origin_from_config(root .. "/sub"), "https://github.com/me/proj.git", "config: origin url from a subdir")
  local wt = vim.fn.tempname()
  vim.fn.mkdir(wt, "p"); vim.fn.mkdir(root .. "/.git/worktrees/w", "p")
  vim.fn.writefile({ "gitdir: " .. root .. "/.git/worktrees/w" }, wt .. "/.git")
  vim.fn.writefile({ "../.." }, root .. "/.git/worktrees/w/commondir")
  eq(db._origin_from_config(wt), "https://github.com/me/proj.git", "config: worktree → common config")
  vim.fn.delete(root, "rf"); vim.fn.delete(wt, "rf")
end

do
  local d = require("plugins.utils.devops.ui.dashboard")
  local function keys(ctx)
    local t = {}
    for _, e in ipairs(d._footer_keys(ctx)) do t[#t + 1] = e[1] end
    return table.concat(t, " ")
  end
  eq(keys("gh_prs"), "↵ d m J +", "footer: My PRs keys")
  eq(keys("gh_actions"), "↵ r o", "footer: Actions keys")
  ok(#d._footer_keys("pr_detail") <= 7 and #d._footer_keys("jira_issues") <= 7, "footer: at most 7 keys")
  local names = {}
  for _, g in ipairs(d._key_groups("gh_actions")) do names[#names + 1] = g[1] end
  eq(table.concat(names, ","), "Navigate,Actions,Log viewer,Window", "help: actions groups")
  local found = false
  for _, g in ipairs(d._key_groups("gh_reviews")) do
    for _, e in ipairs(g[2]) do if e[1] == "J" then found = true end end
  end
  ok(found, "help: reviews lists J jira")
end

do
  -- <C-d> is the global "quit vim"; every devops window that closes on q
  -- must map <C-d> too, or it falls through and quits the editor.
  local root = debug.getinfo(1, "S").source:sub(2):match("(.*/)tests/") or "./"
  local bad = {}
  for _, f in ipairs(vim.fn.globpath(root, "**/*.lua", false, true)) do
    if not f:match("/tests/") then
      local src = table.concat(vim.fn.readfile(f), "\n")
      -- Ignore footer hints like { "q", "close" } / { "q", h(...) }.
      local stripped = src:gsub('{%s*"q"%s*,%s*"%l+"%s*}', ""):gsub('{%s*"q"%s*,%s*h%(', "")
      local q = select(2, stripped:gsub('[%(%{,]%s*"q"%s*[,%)]', ""))
      local cd = select(2, src:gsub('"<C%-d>"', ""))
      if q > cd then bad[#bad + 1] = vim.fn.fnamemodify(f, ":t") .. " (" .. q .. " q / " .. cd .. " <C-d>)" end
    end
  end
  eq(table.concat(bad, ", "), "", "every q-close also maps <C-d>")
end

do
  local d = require("plugins.utils.devops.ui.dashboard")
  local cfg = require("plugins.utils.devops.config")
  cfg.options.github = cfg.options.github or {}
  local saved = cfg.options.github.org
  cfg.options.github.org = nil
  local fx = function(o) return { repository = { nameWithOwner = o .. "/x" } } end
  d._set_token_orgs({ "work" })
  eq(d._search_org(), "work", "search org: token account's org")
  d._set_token_orgs({ "other", "work" })
  d._cache_set("gh_prs", { fx("work"), fx("work"), fx("me") })
  eq(d._search_org(), "work", "search org: several orgs → the one your PRs are in")
  d._cache_set("gh_prs", {})
  d._set_token_orgs({})
  eq(d._search_org(), nil, "search org: no org → global")
  cfg.options.github.org = "myorg"
  eq(d._search_org(), "myorg", "search org: config wins")
  cfg.options.github.org = saved
end

-- ── report ─────────────────────────────────────────────────────────────────
print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
