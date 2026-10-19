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

-- ── report ─────────────────────────────────────────────────────────────────
print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
