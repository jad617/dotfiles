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

-- ── report ─────────────────────────────────────────────────────────────────
print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
