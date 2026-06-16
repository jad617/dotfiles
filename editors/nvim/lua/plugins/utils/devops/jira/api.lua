---------------------------------------------------------------------------
-- Jira API — thin wrappers over the REST endpoints DevOps needs.
---------------------------------------------------------------------------

local client = require("plugins.utils.devops.jira.client")
local config = require("plugins.utils.devops.config")

local M = {}

-- Fields requested for the issue list (keep it lean).
local LIST_FIELDS = { "summary", "status", "issuetype", "assignee", "updated", "parent", "priority" }

-- Build the JQL for the list view. opts = { account_id, project_key, open_sprints, include_done }.
-- open_sprints => scope to issues in any active sprint (spans projects); we then
-- skip the project filter and don't drop Done (the sprint board shows all columns).
function M.build_jql(opts)
  opts = opts or {}
  if config.options.jira.jql and config.options.jira.jql ~= "" then
    return config.options.jira.jql
  end

  local parts = {}
  if opts.account_id and opts.account_id ~= "" then
    parts[#parts + 1] = 'assignee = "' .. opts.account_id .. '"'
  end
  if opts.open_sprints then
    parts[#parts + 1] = "sprint in openSprints()"
    if not opts.include_done then
      parts[#parts + 1] = "statusCategory != Done"
    end
  else
    if opts.project_key and opts.project_key ~= "" then
      parts[#parts + 1] = 'project = "' .. opts.project_key .. '"'
    end
    if not opts.include_done then
      parts[#parts + 1] = "statusCategory != Done"
    end
  end
  return table.concat(parts, " AND ") .. " ORDER BY updated DESC"
end

-- List issues. opts = { account_id, project_key, open_sprints }. cb(ok, issues[], err)
function M.search(opts, cb)
  local body = {
    jql = M.build_jql(opts),
    fields = LIST_FIELDS,
    maxResults = config.options.jira.page_size or 50,
  }
  client.post("/rest/api/3/search/jql", body, function(ok, data, err)
    if not ok then return cb(false, nil, err) end
    cb(true, (data and data.issues) or {}, nil)
  end)
end

-- Projects the user can see (for the project picker). cb(ok, projects[], err)
function M.list_projects(query, cb)
  local path = "/rest/api/3/project/search?maxResults=100&orderBy=key"
  if query and query ~= "" then path = path .. "&query=" .. vim.uri_encode(query) end
  client.get(path, function(ok, data, err)
    if not ok then return cb(false, nil, err) end
    cb(true, (data and data.values) or {}, nil)
  end)
end

-- Agile boards for a project. cb(ok, boards[], err)
function M.list_boards(project_key, cb)
  client.get("/rest/agile/1.0/board?projectKeyOrId=" .. project_key .. "&maxResults=50", function(ok, data, err)
    if not ok then return cb(false, nil, err) end
    cb(true, (data and data.values) or {}, nil)
  end)
end

-- Active sprint for a board (first one). cb(ok, sprint|nil, err)
-- Kanban boards have no sprints and return an error → treated as no sprint.
function M.active_sprint(board_id, cb)
  client.get("/rest/agile/1.0/board/" .. board_id .. "/sprint?state=active&maxResults=1", function(ok, data, err)
    if not ok then return cb(false, nil, err) end
    local s = data and data.values and data.values[1]
    cb(true, s and { id = s.id, name = s.name } or nil, nil)
  end)
end

-- Ordered board columns, each { name, statuses = { "<statusId>", ... } }.
-- cb(ok, columns[], err)
function M.board_config(board_id, cb)
  client.get("/rest/agile/1.0/board/" .. board_id .. "/configuration", function(ok, data, err)
    if not ok then return cb(false, nil, err) end
    local cols = {}
    local cc = data and data.columnConfig
    for _, col in ipairs(cc and cc.columns or {}) do
      local statuses = {}
      for _, s in ipairs(col.statuses or {}) do statuses[#statuses + 1] = tostring(s.id) end
      cols[#cols + 1] = { name = col.name, statuses = statuses }
    end
    cb(true, cols, nil)
  end)
end

-- Full issue (all fields incl. description). cb(ok, issue, err)
function M.get_issue(key, cb)
  client.get("/rest/api/3/issue/" .. key, function(ok, data, err) cb(ok, data, err) end)
end

-- Available transitions for an issue. cb(ok, transitions[], err)
function M.transitions(key, cb)
  client.get("/rest/api/3/issue/" .. key .. "/transitions", function(ok, data, err)
    if not ok then return cb(false, nil, err) end
    cb(true, (data and data.transitions) or {}, nil)
  end)
end

-- Apply a transition (POST returns 204, so data is nil on success).
function M.do_transition(key, transition_id, cb)
  client.post("/rest/api/3/issue/" .. key .. "/transitions", { transition = { id = transition_id } }, cb)
end

-- Users that can be assigned (for the user selector). cb(ok, users[], err)
function M.assignable_users(project_key, cb)
  local path
  if project_key and project_key ~= "" then
    path = "/rest/api/3/user/assignable/search?project=" .. project_key .. "&maxResults=100"
  else
    path = "/rest/api/3/users/search?maxResults=200"
  end
  client.get(path, function(ok, data, err) cb(ok, data or {}, err) end)
end

-- Search all users by name/email (for mentions). cb(ok, users[], err)
function M.search_users(query, cb)
  local q = (query and query ~= "") and query or ""
  local path = "/rest/api/3/user/search?maxResults=200&query=" .. vim.uri_encode(q)
  client.get(path, function(ok, data, err) cb(ok, data or {}, err) end)
end

-- Linked GitHub PRs via the (undocumented) dev-status endpoint.
-- Best-effort: requires the GitHub-for-Jira app on the instance. cb(ok, prs[], err)
function M.dev_status(issue_id, cb)
  local path = "/rest/dev-status/latest/issue/detail?issueId=" .. issue_id
    .. "&applicationType=GitHub&dataType=pullrequest"
  client.get(path, function(ok, data, err)
    if not ok then return cb(false, nil, err) end
    local prs = {}
    if data and data.detail then
      for _, d in ipairs(data.detail) do
        for _, pr in ipairs(d.pullRequests or {}) do
          prs[#prs + 1] = pr
        end
      end
    end
    cb(true, prs, nil)
  end)
end

---------------------------------------------------------------------------
-- Write operations
---------------------------------------------------------------------------

-- Add a comment to an issue (ADF body). cb(ok, data, err)
function M.add_comment(key, text, cb)
  local adf = require("plugins.utils.devops.jira.adf")
  client.post("/rest/api/3/issue/" .. key .. "/comment", { body = adf.text_to_adf(text) }, cb)
end

-- Update issue fields (summary, description, etc). cb(ok, data, err)
function M.update_issue(key, fields, cb)
  client.put("/rest/api/3/issue/" .. key, { fields = fields }, cb)
end

-- Assign an issue (account_id or nil to unassign). cb(ok, data, err)
function M.assign(key, account_id, cb)
  client.put("/rest/api/3/issue/" .. key .. "/assignee", { accountId = account_id }, cb)
end

-- Comments on an issue (newest last). cb(ok, comments[], err)
function M.comments(key, cb)
  client.get("/rest/api/3/issue/" .. key .. "/comment?orderBy=created&maxResults=50", function(ok, data, err)
    if not ok then return cb(false, nil, err) end
    cb(true, (data and data.comments) or {}, nil)
  end)
end

-- Issue types for a project (for the create flow). cb(ok, types[], err)
function M.issue_types(project_key, cb)
  client.get("/rest/api/3/issue/createmeta/" .. project_key .. "/issuetypes", function(ok, data, err)
    if not ok then return cb(false, nil, err) end
    cb(true, (data and data.issueTypes) or data or {}, nil)
  end)
end

-- Create a new issue. fields = { project, issuetype, summary, description, ... }
-- cb(ok, data, err) — data contains { key = "DEVOPS-123", ... }
function M.create_issue(fields, cb)
  client.post("/rest/api/3/issue", { fields = fields }, cb)
end

return M
