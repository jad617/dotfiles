---------------------------------------------------------------------------
-- DevOps preferences (non-secret) — remembers the selected project/board.
-- Stored next to the credentials file: $XDG_CONFIG_HOME/devops/state.json
---------------------------------------------------------------------------

local auth = require("plugins.utils.devops.jira.auth")

local M = {}

function M.file() return auth.dir() .. "/state.json" end

function M.load()
  local f = io.open(M.file(), "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then return nil end
  return data
end

function M.save(tbl)
  vim.fn.mkdir(auth.dir(), "p", tonumber("700", 8))
  local f = io.open(M.file(), "w")
  if not f then return false end
  f:write(vim.json.encode(tbl))
  f:close()
  return true
end

function M.bookmarks_file() return auth.dir() .. "/bookmarks.json" end

function M.load_bookmarks()
  local f = io.open(M.bookmarks_file(), "r")
  if not f then return {} end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then return {} end
  -- Migrate old flat array format to per-section map
  if data[1] ~= nil then return {} end
  return data
end

function M.save_bookmarks(bookmarks)
  vim.fn.mkdir(auth.dir(), "p", tonumber("700", 8))
  local f = io.open(M.bookmarks_file(), "w")
  if not f then return false end
  f:write(vim.json.encode(bookmarks))
  f:close()
  return true
end

---------------------------------------------------------------------------
-- Pending review comments (draft inline comments not yet submitted),
-- keyed "repo#number", so an in-progress review survives close / restart.
---------------------------------------------------------------------------
function M.pending_file() return auth.dir() .. "/pending_reviews.json" end

function M.load_pending()
  local f = io.open(M.pending_file(), "r")
  if not f then return {} end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then return {} end
  return data
end

function M.save_pending(map)
  vim.fn.mkdir(auth.dir(), "p", tonumber("700", 8))
  local f = io.open(M.pending_file(), "w")
  if not f then return false end
  f:write(vim.json.encode(map or {}))
  f:close()
  return true
end

---------------------------------------------------------------------------
-- Section cache persistence — instant startup by reusing last fetched data.
---------------------------------------------------------------------------
local SECTION_CACHE_TTL = 300 -- 5 minutes

function M.cache_file() return auth.dir() .. "/section_cache.json" end

function M.load_section_cache()
  local f = io.open(M.cache_file(), "r")
  if not f then return {} end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then return {} end
  -- Prune expired entries
  local now = os.time()
  local pruned = {}
  for k, v in pairs(data) do
    if type(v) == "table" and v.ts and (now - v.ts) < SECTION_CACHE_TTL then
      pruned[k] = v
    end
  end
  return pruned
end

function M.save_section_cache(cache_map)
  vim.fn.mkdir(auth.dir(), "p", tonumber("700", 8))
  local f = io.open(M.cache_file(), "w")
  if not f then return false end
  -- Only persist entries with data (strip stale)
  local out = {}
  for k, v in pairs(cache_map) do
    if type(v) == "table" and v.data then
      out[k] = { data = v.data, ts = v.ts }
    end
  end
  f:write(vim.json.encode(out))
  f:close()
  return true
end

return M
