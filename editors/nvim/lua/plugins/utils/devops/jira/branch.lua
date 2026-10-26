---------------------------------------------------------------------------
-- Branch from a Jira issue: name it from the key + summary, create (or switch
-- to) it in the cwd's git repo, and move the issue to "In Progress".
---------------------------------------------------------------------------

local config = require("plugins.utils.devops.config")

local M = {}

-- "Fix: Login page 500s on SSO!" → "fix-login-page-500s-on-sso"
function M.slug(s, max)
  max = max or 40
  s = (s or ""):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  if #s > max then s = s:sub(1, max):gsub("%-[^%-]*$", "") end
  return s
end

-- Branch name from config.jira.branch_format ({key}, {slug}, {type}).
-- {type} is "fix" for bugs and "feature" otherwise.
function M.name(key, summary, type_name)
  local fmt = config.options.jira.branch_format or "feature/{key}-{slug}"
  local kind = (type_name or ""):lower():find("bug") and "fix" or "feature"
  local slug = M.slug(summary)
  local out = fmt:gsub("{key}", key):gsub("{type}", kind):gsub("{slug}", slug)
  return (out:gsub("%-$", ""))
end

-- The transition into "In Progress": a status named like it, else the first
-- one into the "in progress" category. nil when there's none.
function M.pick_start(transitions)
  local fallback
  for _, tr in ipairs(transitions or {}) do
    local to = tr.to or {}
    local name = (to.name or tr.name or ""):lower()
    if name:find("in progress", 1, true) or name:find("in-progress", 1, true) then return tr end
    local cat = to.statusCategory and to.statusCategory.key
    if cat == "indeterminate" and not fallback then fallback = tr end
  end
  return fallback
end

-- Readable summary from a branch name ("feature/OPS-1-add-sso_login" →
-- "Add sso login"); nil for main/master/develop/detached HEAD.
function M.summary_from_branch(name)
  if not name or name == "" or name == "HEAD" then return nil end
  if ({ main = 1, master = 1, develop = 1, dev = 1, trunk = 1 })[name] then return nil end
  local s = name:gsub("^.*/", ""):gsub("^%u[%u%d_]*%-%d+[%-_]?", ""):gsub("[%-_]+", " ")
  s = vim.trim(s)
  if s == "" then return nil end
  return s:sub(1, 1):upper() .. s:sub(2)
end

local function git(args, cwd, cb)
  local cmd = { "git", "-C", cwd }
  vim.list_extend(cmd, args)
  vim.system(cmd, { text = true }, function(res)
    vim.schedule(function() cb(res.code == 0, vim.trim(res.stdout or ""), vim.trim(res.stderr or "")) end)
  end)
end

-- Current branch in cwd (nil outside a repo). cb(name|nil)
function M.current(cwd, cb)
  git({ "branch", "--show-current" }, cwd, function(ok, out) cb(ok and out ~= "" and out or nil) end)
end

-- Create or switch to `name` in cwd. cb(ok, "created"|"switched", err)
function M.checkout(name, cwd, cb)
  git({ "rev-parse", "--is-inside-work-tree" }, cwd, function(in_repo)
    if not in_repo then return cb(false, nil, cwd .. " is not a git repository") end
    git({ "show-ref", "--verify", "--quiet", "refs/heads/" .. name }, cwd, function(exists)
      local args = exists and { "checkout", name } or { "checkout", "-b", name }
      git(args, cwd, function(ok, _, err)
        cb(ok, exists and "switched" or "created", err)
      end)
    end)
  end)
end

return M
