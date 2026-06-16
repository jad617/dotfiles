---------------------------------------------------------------------------
-- Jira Cloud REST client
--
-- Auth: HTTP Basic with base64(email:token). Credentials come from, in order
-- of precedence:
--   1. environment vars  JIRA_URL / JIRA_EMAIL / JIRA_API_TOKEN
--   2. the stored file written by :JiraAuth (see jira/auth.lua)
--
-- All requests are async (vim.system + curl); callbacks run on the main loop.
---------------------------------------------------------------------------

local auth = require("plugins.utils.devops.jira.auth")

local M = {}

local state = { account_id = nil, display_name = nil }

-- Merge env (highest precedence) over stored credentials.
local function creds()
  local stored = auth.load() or {}
  return {
    url = ((os.getenv("JIRA_URL") or stored.url) or ""):gsub("/+$", ""),
    email = (os.getenv("JIRA_EMAIL") or stored.email) or "",
    token = (os.getenv("JIRA_API_TOKEN") or stored.token) or "",
  }
end

-- Which credential fields are still missing (label, env-var name).
function M.missing()
  local c = creds()
  local miss = {}
  if c.url == "" then miss[#miss + 1] = "URL" end
  if c.email == "" then miss[#miss + 1] = "email" end
  if c.token == "" then miss[#miss + 1] = "API token" end
  return miss
end

function M.configured() return #M.missing() == 0 end

function M.base_url() return creds().url end

local function auth_header()
  local c = creds()
  return "Authorization: Basic " .. vim.base64.encode(c.email .. ":" .. c.token)
end

-- method: "GET"|"POST"|"PUT"; path: starts with "/"; body: table|nil
-- cb(ok:boolean, data:table|nil, err:string|nil)
function M.request(method, path, body, cb)
  if not M.configured() then
    cb(false, nil, "Jira not configured — missing: " .. table.concat(M.missing(), ", ") .. " (run :JiraAuth)")
    return
  end

  local args = {
    "curl", "-sS", "-w", "\n%{http_code}",
    "-X", method,
    "-H", auth_header(),
    "-H", "Accept: application/json",
  }
  if body ~= nil then
    vim.list_extend(args, { "-H", "Content-Type: application/json", "--data-binary", vim.json.encode(body) })
  end
  args[#args + 1] = creds().url .. path

  vim.system(args, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        cb(false, nil, "curl failed: " .. ((res.stderr ~= "" and res.stderr) or ("exit " .. res.code)))
        return
      end

      -- Body, then a trailing line with the HTTP status code (from -w).
      local out = res.stdout or ""
      local body_str, status = out:match("^(.*)\n(%d+)%s*$")
      status = tonumber(status)

      local data = nil
      if body_str and #body_str > 0 then
        local ok, decoded = pcall(vim.json.decode, body_str)
        if ok then data = decoded end
      end

      if not status or status >= 400 then
        local msg = "HTTP " .. tostring(status or "?")
        if type(data) == "table" then
          if type(data.errorMessages) == "table" and #data.errorMessages > 0 then
            msg = msg .. ": " .. table.concat(data.errorMessages, "; ")
          elseif data.errors and next(data.errors) then
            local parts = {}
            for k, v in pairs(data.errors) do parts[#parts + 1] = k .. ": " .. tostring(v) end
            msg = msg .. ": " .. table.concat(parts, "; ")
          end
        end
        cb(false, data, msg)
        return
      end

      cb(true, data, nil)
    end)
  end)
end

function M.get(path, cb) M.request("GET", path, nil, cb) end
function M.post(path, body, cb) M.request("POST", path, body, cb) end
function M.put(path, body, cb) M.request("PUT", path, body, cb) end

-- Validate auth and cache the current user (default assignee).
function M.myself(cb)
  M.get("/rest/api/3/myself", function(ok, data, err)
    if ok and type(data) == "table" then
      state.account_id = data.accountId
      state.display_name = data.displayName
    end
    cb(ok, data, err)
  end)
end

function M.account_id() return state.account_id end
function M.display_name() return state.display_name end

return M
